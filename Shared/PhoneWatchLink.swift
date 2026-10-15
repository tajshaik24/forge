import Foundation
import Observation
import WatchConnectivity

/// Direct iPhone → Watch channel for today's plan and settings. iCloud also syncs the plan,
/// but this needs no entitlement (free Apple teams) and arrives as soon as the Watch is in range.
@MainActor
@Observable
final class PhoneWatchLink: NSObject {
    static let shared = PhoneWatchLink()

    struct Context: Codable, Equatable {
        var plan: PlannedWorkout?
        var unit: WeightUnit
    }

    /// Latest context from the iPhone (Watch side).
    private(set) var received: Context?
    /// Last context built on the iPhone, re-sent when the session activates or the Watch app appears.
    private var latest: Context?
    nonisolated private static let key = "forge.context.v1"
    nonisolated private static let resultKey = "forge.result.v1"

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Today's plan, if the iPhone sent one for today.
    var todayPlan: PlannedWorkout? {
        guard let plan = received?.plan, Calendar.current.isDateInToday(plan.date) else { return nil }
        return plan
    }

    #if os(iOS)
    /// A paired Watch with FORGE installed, so a workout started here can run on the wrist.
    var canStartOnWatch: Bool {
        let session = WCSession.default
        return WCSession.isSupported() && session.activationState == .activated
            && session.isPaired && session.isWatchAppInstalled
    }

    func send(plan: PlannedWorkout?) {
        latest = Context(plan: plan, unit: SyncedSettings.unit)
        flush()
    }

    private func flush() {
        let session = WCSession.default
        guard let context = latest, WCSession.isSupported(), session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(context) else { return }
        do {
            try session.updateApplicationContext([Self.key: data])
        } catch {
            print("FORGE: couldn't send plan to Watch: \(error)")
        }
    }
    #else
    /// The saved shared workout, for the iPhone's history and summary.
    func send(result: WorkoutTracker.Result) {
        let session = WCSession.default
        guard session.activationState == .activated, let data = try? JSONEncoder().encode(result) else { return }
        let payload = [Self.resultKey: data]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in session.transferUserInfo(payload) }
        } else {
            session.transferUserInfo(payload)
        }
    }
    #endif

    fileprivate func activated() {
        #if os(iOS)
        flush()
        #else
        ingest(WCSession.default.receivedApplicationContext)
        #endif
    }

    fileprivate func ingest(_ applicationContext: [String: Any]) {
        guard let data = applicationContext[Self.key] as? Data,
              let context = try? JSONDecoder().decode(Context.self, from: data) else { return }
        received = context
        #if PERSONAL_TEAM
        SyncedSettings.unit = context.unit   // no iCloud key-value store to carry it
        #endif
    }
}

extension PhoneWatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.activated() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[Self.key] as? Data else { return }
        Task { @MainActor in self.ingest([Self.key: data]) }
    }

    #if os(iOS)
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receiveResult(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receiveResult(userInfo)
    }

    nonisolated private func receiveResult(_ payload: [String: Any]) {
        guard let data = payload[Self.resultKey] as? Data,
              let result = try? JSONDecoder().decode(WorkoutTracker.Result.self, from: data) else { return }
        Task { @MainActor in WorkoutTracker.shared.received(result) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The user switched to a different Watch: activate again for the new one.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.flush() }
    }
    #endif
}
