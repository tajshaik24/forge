import Foundation
import CloudKit
import Observation
import SwiftData
import UIKit

/// Crews (beta): a small group sharing workout check-ins through a CloudKit zone-wide share.
///
/// The crew's creator owns a custom zone in their private database and shares the whole zone.
/// Members reach the same zone through their shared database. No server: CloudKit holds the
/// records and sends pushes. Only check-ins (workout type, sets, minutes, Health-verified) are
/// shared; weights, heart rate, sleep and coach notes never leave the user's own iCloud data.
@MainActor
@Observable
final class CrewService {
    static let shared = CrewService()

    /// Which crew this device is in. Synced through iCloud key-value storage so all your devices agree.
    struct CrewRef: Codable, Equatable {
        var zoneName: String
        var ownerName: String
        var isOwner: Bool
        var name: String
    }

    private let container = CKContainer(identifier: DataStore.cloudContainerID)

    private(set) var crew: CrewRef?
    private(set) var members: [CrewMember] = []
    private(set) var checkIns: [CrewCheckIn] = []
    private(set) var nudges: [CrewNudge] = []
    private(set) var myUserID: String?
    private(set) var shareURL: URL?
    private(set) var isLoading = false
    var errorText: String?

    private static let crewKey = "crewRef"
    private static let nameKey = "crewDisplayName"
    private var kv: NSUbiquitousKeyValueStore { .default }

    /// Bumped on every name change so views observing `displayName` re-render
    /// (the value itself lives in key-value storage, which Observation can't see).
    private var displayNameRevision = 0

    var displayName: String {
        get { _ = displayNameRevision; return kv.string(forKey: Self.nameKey) ?? "" }
        set { kv.set(newValue, forKey: Self.nameKey); kv.synchronize(); displayNameRevision += 1 }
    }

    var weeklyGoal: Int { max(1, SyncedSettings.trainingWeekdays.count) }

    init() {
        if let data = kv.data(forKey: Self.crewKey) { crew = try? JSONDecoder().decode(CrewRef.self, from: data) }
    }

    private func store(_ ref: CrewRef?) {
        crew = ref
        if let ref, let data = try? JSONEncoder().encode(ref) { kv.set(data, forKey: Self.crewKey) } else { kv.removeObject(forKey: Self.crewKey) }
        kv.synchronize()
    }

    private var zoneID: CKRecordZone.ID? {
        crew.map { CKRecordZone.ID(zoneName: $0.zoneName, ownerName: $0.ownerName) }
    }

    /// Owners write to their private database; members to their shared database.
    private var database: CKDatabase {
        crew?.isOwner == false ? container.sharedCloudDatabase : container.privateCloudDatabase
    }

    // MARK: Derived

    var standings: [CrewStanding] {
        members.map { CrewStreaks.standing(for: $0, checkIns: checkIns) }
            .sorted { ($0.member.id == myUserID ? 0 : 1, -$0.count) < ($1.member.id == myUserID ? 0 : 1, -$1.count) }
    }

    var crewStreak: Int { CrewStreaks.crewStreak(members: members, checkIns: checkIns) }

    var nudgesForMe: [CrewNudge] {
        let since = Date().addingTimeInterval(-48 * 3600)
        return nudges.filter { $0.toUserID == myUserID && $0.date > since }.sorted { $0.date > $1.date }
    }

    // MARK: Create / join / leave

    func createCrew(named name: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let zone = CKRecordZone(zoneName: "crew-\(UUID().uuidString)")
            let db = container.privateCloudDatabase
            _ = try await db.modifyRecordZones(saving: [zone], deleting: [])

            let share = CKShare(recordZoneID: zone.zoneID)
            share[CKShare.SystemFieldKey.title] = name as CKRecordValue
            share.publicPermission = .readWrite   // anyone with the link can join (beta)
            let crewRecord = CKRecord(recordType: "Crew", recordID: CKRecord.ID(recordName: "crew", zoneID: zone.zoneID))
            crewRecord["name"] = name as CKRecordValue

            let result = try await db.modifyRecords(saving: [share, crewRecord], deleting: [], savePolicy: .allKeys)
            if let saved = try? result.saveResults[share.recordID]?.get() as? CKShare { shareURL = saved.url }

            store(CrewRef(zoneName: zone.zoneID.zoneName, ownerName: zone.zoneID.ownerName, isOwner: true, name: name))
            try await joinAsMember()
            await subscribe()
            await refresh()
        } catch {
            errorText = "Couldn't create the crew: \(error.localizedDescription)"
        }
    }

    /// Called when someone opens an invite link (see `SceneDelegate`).
    func accept(_ metadata: CKShare.Metadata) async {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await container.accept(metadata)
            let zoneID = metadata.share.recordID.zoneID
            let title = metadata.share[CKShare.SystemFieldKey.title] as? String ?? "Crew"
            store(CrewRef(zoneName: zoneID.zoneName, ownerName: zoneID.ownerName, isOwner: false, name: title))
            if !displayName.isEmpty { try await joinAsMember() }
            await subscribe()
            await refresh()
        } catch {
            errorText = "Couldn't join the crew: \(error.localizedDescription)"
        }
    }

    /// Owners end the crew for everyone; members just leave.
    func leave() async {
        guard let zoneID, let crew else { return }
        do {
            if crew.isOwner {
                _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [zoneID])
            } else {
                _ = try await container.sharedCloudDatabase.modifyRecordZones(saving: [], deleting: [zoneID])
            }
        } catch {
            errorText = "Couldn't leave cleanly: \(error.localizedDescription)"
        }
        store(nil)
        members = []; checkIns = []; nudges = []; shareURL = nil
    }

    /// Writes (or updates) this user's member record. Safe to call repeatedly.
    func joinAsMember() async throws {
        guard let zoneID else { return }
        let me = try await userID()
        let record = CKRecord(recordType: "Member", recordID: CKRecord.ID(recordName: "member-\(me)", zoneID: zoneID))
        record["userID"] = me as CKRecordValue
        record["name"] = (displayName.isEmpty ? "Me" : displayName) as CKRecordValue
        record["weeklyGoal"] = weeklyGoal as CKRecordValue
        _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
    }

    private func userID() async throws -> String {
        if let myUserID { return myUserID }
        let id = try await container.userRecordID().recordName
        myUserID = id
        return id
    }

    // MARK: Check-ins + nudges

    /// Posts one check-in per finished workout day in the last two weeks (idempotent per day).
    /// Runs on launch and after finishing, so Watch workouts get posted once they sync to the iPhone.
    func postCheckIns(from ctx: ModelContext) async {
        guard let zoneID else { return }
        let since = Calendar.current.date(byAdding: .day, value: -14, to: .now)!
        let sessions = ((try? ctx.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date)]))) ?? [])
            .filter { $0.endDate != nil && $0.date >= since && !$0.orderedSets.isEmpty }
        guard !sessions.isEmpty else { return }
        do {
            let me = try await userID()
            let name = displayName.isEmpty ? "Me" : displayName
            // One record per day: the biggest session of the day wins.
            var byDay: [String: WorkoutSession] = [:]
            for s in sessions {
                let key = DayKey.of(s.date)
                if let existing = byDay[key], existing.orderedSets.count >= s.orderedSets.count { continue }
                byDay[key] = s
            }
            let records: [CKRecord] = byDay.map { key, s in
                let r = CKRecord(recordType: "CheckIn", recordID: CKRecord.ID(recordName: "checkin-\(me)-\(key)", zoneID: zoneID))
                r["userID"] = me as CKRecordValue
                r["name"] = name as CKRecordValue
                r["date"] = s.date as CKRecordValue
                r["focus"] = s.focus as CKRecordValue
                r["sets"] = s.orderedSets.count as CKRecordValue
                r["minutes"] = Int(s.duration / 60) as CKRecordValue
                r["verified"] = (s.healthWorkoutID != nil ? 1 : 0) as CKRecordValue
                return r
            }
            _ = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
        } catch {
            errorText = "Couldn't post your check-in: \(error.localizedDescription)"
        }
    }

    func nudge(_ member: CrewMember) async {
        guard let zoneID else { return }
        let r = CKRecord(recordType: "Nudge", recordID: CKRecord.ID(recordName: "nudge-\(UUID().uuidString)", zoneID: zoneID))
        r["fromName"] = (displayName.isEmpty ? "Someone" : displayName) as CKRecordValue
        r["toUserID"] = member.id as CKRecordValue
        r["date"] = Date() as CKRecordValue
        do { _ = try await database.modifyRecords(saving: [r], deleting: [], savePolicy: .allKeys) }
        catch { errorText = "Couldn't send the nudge: \(error.localizedDescription)" }
        await refresh()
    }

    // MARK: Sync

    /// Re-reads the whole crew zone. Crews are small, so a full fetch is simplest and always correct.
    func refresh() async {
        guard let zoneID else { return }
        do {
            _ = try await userID()
            var token: CKServerChangeToken?
            var records: [CKRecord] = []
            var more = true
            while more {
                let page = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
                for (_, result) in page.modificationResultsByID {
                    if let mod = try? result.get() { records.append(mod.record) }
                }
                token = page.changeToken
                more = page.moreComing
            }
            apply(records)
            if shareURL == nil {
                let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
                shareURL = (try? await database.record(for: shareID) as? CKShare)?.url
            }
            errorText = nil
        } catch let error as CKError where Self.zoneIsGone(error) {
            // The owner ended the crew, or you were removed.
            store(nil)
            members = []; checkIns = []; nudges = []; shareURL = nil
            errorText = "This crew no longer exists."
        } catch {
            errorText = "Couldn't refresh the crew: \(error.localizedDescription)"
        }
    }

    /// Zone errors can arrive directly or wrapped in a partial failure.
    private static func zoneIsGone(_ error: CKError) -> Bool {
        let gone: Set<CKError.Code> = [.zoneNotFound, .userDeletedZone]
        if gone.contains(error.code) { return true }
        guard error.code == .partialFailure, let partial = error.partialErrorsByItemID else { return false }
        return partial.values.contains { ($0 as? CKError).map { gone.contains($0.code) } ?? false }
    }

    private func apply(_ records: [CKRecord]) {
        var m: [CrewMember] = [], c: [CrewCheckIn] = [], n: [CrewNudge] = []
        for r in records {
            switch r.recordType {
            case "Member":
                guard let id = r["userID"] as? String else { continue }
                m.append(CrewMember(id: id, name: r["name"] as? String ?? "Member", weeklyGoal: r["weeklyGoal"] as? Int ?? 3))
            case "CheckIn":
                guard let id = r["userID"] as? String, let date = r["date"] as? Date else { continue }
                c.append(CrewCheckIn(id: r.recordID.recordName, userID: id, name: r["name"] as? String ?? "",
                                     date: date, focus: r["focus"] as? String ?? "Workout",
                                     sets: r["sets"] as? Int ?? 0, minutes: r["minutes"] as? Int ?? 0,
                                     verified: (r["verified"] as? Int ?? 0) == 1))
            case "Nudge":
                guard let to = r["toUserID"] as? String, let date = r["date"] as? Date else { continue }
                n.append(CrewNudge(id: r.recordID.recordName, fromName: r["fromName"] as? String ?? "Someone", toUserID: to, date: date))
            case "Crew":
                if let name = r["name"] as? String, var ref = crew, ref.name != name { ref.name = name; store(ref) }
            default:
                break
            }
        }
        members = m.sorted { $0.name < $1.name }
        checkIns = c.sorted { $0.date > $1.date }
        nudges = n
    }

    /// Push notifications when anyone in the crew checks in or nudges.
    func subscribe() async {
        guard let crew, let zoneID else { return }
        let info = CKSubscription.NotificationInfo()
        info.alertBody = "New activity in \(crew.name)"
        info.soundName = "default"
        info.shouldSendContentAvailable = true
        do {
            if crew.isOwner {
                let sub = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: "crew-zone-\(zoneID.zoneName)")
                sub.notificationInfo = info
                _ = try await container.privateCloudDatabase.modifySubscriptions(saving: [sub], deleting: [])
            } else {
                let sub = CKDatabaseSubscription(subscriptionID: "crew-shared")
                sub.notificationInfo = info
                _ = try await container.sharedCloudDatabase.modifySubscriptions(saving: [sub], deleting: [])
            }
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            // Non-fatal: the crew still works, you just won't get pushes.
            errorText = "Notifications for your crew aren't set up yet."
        }
    }
}
