import Foundation
import HealthKit
import Observation
import SwiftData

/// Runs a real HealthKit strength workout on iPhone (iOS 26+) or Apple Watch:
/// live heart rate + calories while you train, each logged set saved as a workout segment,
/// and the finished workout written to Health so it shows up in Fitness.
///
/// With both devices, there is one shared workout: the Watch runs it (best heart-rate sensor)
/// and mirrors it to the iPhone. Sets and rest changes travel between them as `MirrorMessage`s;
/// the iPhone keeps the set history, the Watch writes the Health workout.
@MainActor
@Observable
final class WorkoutTracker: NSObject {
    static let shared = WorkoutTracker()

    let store = HKHealthStore()

    private(set) var isRunning = false
    private(set) var startDate: Date?
    private(set) var heartRate: Double = 0
    private(set) var activeCalories: Double = 0
    /// One reading roughly every 15 s, for the summary chart.
    private(set) var heartRateTimeline: [Int] = []
    private(set) var lastError: String?

    /// The live workout is shared with the other device (iPhone: a mirror of the Watch's session;
    /// Watch: mirroring to the iPhone).
    private(set) var isMirrored = false
    /// iPhone: waiting for the Watch to pick up a workout started here.
    private(set) var isStartingOnWatch = false
    /// Sets the other device logged during this workout, oldest first.
    private(set) var remoteSets: [LoggedSet] = []
    /// The other device started, extended or skipped rest.
    private(set) var remoteRest: RestChange?
    /// The last workout was thrown away rather than saved.
    private(set) var discarded = false
    /// iPhone: bumps when the Watch ended the shared workout on its own.
    private(set) var remoteFinishCount = 0

    struct RestChange: Equatable {
        let until: Date?
        let id = UUID()
    }

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var lastTimelineSample: Date = .distantPast
    /// iPhone: the Watch's result for a shared workout, once it arrives.
    private var remoteResult: Result?
    private var awaitingRemoteResult = false

    struct Result: Codable, Sendable {
        let workoutID: UUID?
        let start: Date
        let end: Date
        let activeCalories: Double
        let averageHeartRate: Double
        let maxHeartRate: Double
        let timeline: [Int]
    }

    private static var configuration: HKWorkoutConfiguration {
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        return config
    }

    // MARK: Permissions

    /// Only what's read: live heart rate and calories in a workout, plus (iPhone only) last night's sleep,
    /// HRV and steps for the coach.
    static var readTypes: Set<HKObjectType> {
        #if os(iOS)
        [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
         HKQuantityType(.heartRateVariabilitySDNN), HKCategoryType(.sleepAnalysis), HKQuantityType(.stepCount)]
        #else
        [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        #endif
    }

    static var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)]
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do { try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes) }
        catch { lastError = error.localizedDescription }
    }

    // MARK: Lifecycle

    func start(focus: String) async {
        guard !isRunning, !isStartingOnWatch, HKHealthStore.isHealthDataAvailable() else { return }
        await requestAuthorization()
        #if os(iOS)
        if PhoneWatchLink.shared.canStartOnWatch, await startOnWatch() { return }
        #endif
        guard !isRunning else { return }

        do {
            let config = Self.configuration
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self

            let start = Date()
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: "FORGE · \(focus)",
                                           "FORGEFocus": focus])
            self.session = session
            self.builder = builder
            begin(at: start)
            #if os(watchOS)
            do {
                try await session.startMirroringToCompanionDevice()
                isMirrored = true
            } catch {
                print("FORGE: running without the iPhone: \(error.localizedDescription)")
            }
            #endif
        } catch {
            lastError = "Couldn't start the Health workout: \(error.localizedDescription)"
        }
    }

    private func begin(at start: Date) {
        startDate = start
        heartRate = 0
        activeCalories = 0
        heartRateTimeline = []
        lastTimelineSample = .distantPast
        remoteSets = []
        remoteRest = nil
        remoteResult = nil
        discarded = false
        isRunning = true
    }

    #if os(iOS)
    /// Call at launch: the Watch can start a shared workout while FORGE is in the background.
    func listenForMirroredWorkouts() {
        store.workoutSessionMirroringStartHandler = { session in
            Task { @MainActor in WorkoutTracker.shared.adopt(session) }
        }
    }

    private func adopt(_ mirrored: HKWorkoutSession) {
        if isRunning {
            guard !isMirrored else { return }
            // The Watch started after startOnWatch gave up and the phone began on its own. The Watch's
            // workout wins, so Health gets one entry; the sets are already saved here either way.
            session?.delegate = nil
            builder?.delegate = nil
            session?.end()
            builder?.discardWorkout()
        }
        mirrored.delegate = self
        let builder = mirrored.associatedWorkoutBuilder()
        builder.delegate = self
        session = mirrored
        self.builder = builder
        begin(at: mirrored.startDate ?? .now)
        isMirrored = true
    }

    /// Launches FORGE on the Watch, which starts the workout and mirrors it back here.
    private func startOnWatch() async -> Bool {
        isStartingOnWatch = true
        defer { isStartingOnWatch = false }
        do { try await store.startWatchApp(toHandle: Self.configuration) }
        catch { return false }
        // The mirrored session arrives through workoutSessionMirroringStartHandler.
        for _ in 0..<16 where !isRunning { try? await Task.sleep(for: .milliseconds(500)) }
        return isRunning
    }
    #endif

    /// Each set becomes a segment event on the workout, with what you lifted in its metadata.
    /// In a shared workout the Watch owns the Health workout, so the iPhone hands its sets over.
    func recordSet(_ set: LoggedSet, notifyOtherDevice: Bool = true) async {
        #if os(iOS)
        if isMirrored {
            if notifyOtherDevice { send(.setLogged(set)) }
            return
        }
        #endif
        // A segment can't begin before the workout itself (the first set's timer starts when the screen opens).
        let start = max(set.start, startDate ?? set.start)
        guard let builder, start < set.end else { return }
        let event = HKWorkoutEvent(type: .segment, dateInterval: DateInterval(start: start, end: set.end),
                                   metadata: ["FORGEExercise": set.exercise,
                                              "FORGEWeightLb": set.weight,
                                              "FORGEReps": set.reps])
        try? await builder.addWorkoutEvents([event])
        #if os(watchOS)
        if isMirrored, notifyOtherDevice { send(.setLogged(set)) }
        #endif
    }

    /// Tells the other device about a rest change made here.
    func shareRest(until: Date?) {
        send(.rest(until: until))
    }

    func finish() async -> Result? {
        #if os(iOS)
        if isMirrored { return await finishShared() }
        #endif
        guard let session, let builder, let startDate else { return nil }
        let end = Date()
        let wasMirrored = isMirrored
        session.end()
        defer { reset() }
        var result: Result
        do {
            try await builder.endCollection(at: end)
            let workout = try await builder.finishWorkout()
            result = summary(workoutID: workout?.uuid, start: startDate, end: end)
        } catch {
            lastError = "Couldn't save the workout to Health: \(error.localizedDescription)"
            result = Result(workoutID: nil, start: startDate, end: end, activeCalories: activeCalories,
                            averageHeartRate: 0, maxHeartRate: 0, timeline: heartRateTimeline)
        }
        #if os(watchOS)
        // The mirror closes with the session, so the result goes over WatchConnectivity.
        if wasMirrored { PhoneWatchLink.shared.send(result: result) }
        #else
        _ = wasMirrored
        #endif
        return result
    }

    func discard() {
        if isMirrored { send(.discard) }
        #if os(iOS)
        if isMirrored { reset(discarded: true); return }   // the Watch throws its workout away
        #endif
        session?.end()
        builder?.discardWorkout()
        reset(discarded: true)
    }

    private func summary(workoutID: UUID?, start: Date, end: Date) -> Result {
        let hrStats = builder?.statistics(for: HKQuantityType(.heartRate))
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return Result(workoutID: workoutID, start: start, end: end,
                      activeCalories: activeCalories,
                      averageHeartRate: hrStats?.averageQuantity()?.doubleValue(for: bpm) ?? 0,
                      maxHeartRate: hrStats?.maximumQuantity()?.doubleValue(for: bpm) ?? 0,
                      timeline: heartRateTimeline)
    }

    #if os(iOS)
    /// Asks the Watch to save the shared workout and waits for its result.
    private func finishShared() async -> Result? {
        defer { reset() }
        if let remoteResult { return remoteResult }
        awaitingRemoteResult = true
        defer { awaitingRemoteResult = false }
        send(.finish)
        for _ in 0..<60 where remoteResult == nil { try? await Task.sleep(for: .milliseconds(250)) }
        // No answer: keep what the phone saw. The Watch still saves the workout to Health.
        return remoteResult ?? summary(workoutID: nil, start: startDate ?? .now, end: .now)
    }

    /// The Watch's result for the shared workout (over WatchConnectivity).
    func received(_ result: Result) {
        guard isRunning, isMirrored, remoteResult == nil else { return }
        remoteResult = result
        if !awaitingRemoteResult { remoteFinishCount += 1 }   // ended on the Watch
    }

    /// The Watch's session ended but its result never came: finish with what the phone saw.
    private func mirrorEnded() async {
        try? await Task.sleep(for: .seconds(20))
        guard isRunning, isMirrored, remoteResult == nil, !awaitingRemoteResult else { return }
        remoteResult = summary(workoutID: nil, start: startDate ?? .now, end: .now)
        remoteFinishCount += 1
    }
    #endif

    private func reset(discarded: Bool = false) {
        isRunning = false
        isMirrored = false
        session = nil
        builder = nil
        startDate = nil
        remoteResult = nil
        self.discarded = discarded
    }

    // MARK: Messages between the devices

    private func send(_ message: MirrorMessage) {
        guard isMirrored, let session, let data = try? message.encoded() else { return }
        Task {
            do { try await session.sendToRemoteWorkoutSession(data: data) }
            catch { print("FORGE: couldn't reach the other device: \(error.localizedDescription)") }
        }
    }

    fileprivate func receive(_ message: MirrorMessage) {
        guard isRunning else { return }
        switch message {
        case .setLogged(let set):
            #if os(iOS)
            SetLogger.save(set)   // the iPhone keeps the history
            #else
            Task { await recordSet(set, notifyOtherDevice: false) }
            #endif
            remoteSets.append(set)
        case .rest(let until):
            remoteRest = RestChange(until: until)
        case .finish:
            #if os(watchOS)
            Task { _ = await finish() }
            #endif
        case .discard:
            #if os(watchOS)
            discard()
            #endif
        }
    }

    fileprivate func disconnected() {
        #if os(watchOS)
        isMirrored = false   // keep training; sets are saved on the Watch from here on
        #else
        lastError = "Lost the connection to Apple Watch. Keep logging; sets still save here."
        #endif
    }

    fileprivate func sessionEnded() {
        #if os(iOS)
        if isMirrored { Task { await mirrorEnded() } }
        #endif
    }

    fileprivate func ingest(_ stats: [HKStatistics]) {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        for s in stats {
            switch s.quantityType {
            case HKQuantityType(.heartRate):
                if let v = s.mostRecentQuantity()?.doubleValue(for: bpm) {
                    heartRate = v
                    if Date().timeIntervalSince(lastTimelineSample) >= 15 {
                        heartRateTimeline.append(Int(v.rounded()))
                        lastTimelineSample = Date()
                    }
                }
            case HKQuantityType(.activeEnergyBurned):
                activeCalories = s.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? activeCalories
            default: break
            }
        }
    }
}

extension WorkoutTracker: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        Task { @MainActor in self.sessionEnded() }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.lastError = message }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let messages = data.compactMap(MirrorMessage.decode)
        Task { @MainActor in messages.forEach(self.receive) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        Task { @MainActor in self.disconnected() }
    }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let stats = collectedTypes.compactMap { $0 as? HKQuantityType }.compactMap { workoutBuilder.statistics(for: $0) }
        Task { @MainActor in self.ingest(stats) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

// MARK: - Shared "log a set" path used by iPhone, Watch and Siri

enum SetLogger {
    /// Finds today's open session (or starts one), saves the set, and adds it to the live Health workout.
    @MainActor
    @discardableResult
    static func log(exercise: String, weight: Double, reps: Int, rpe: Int? = nil,
                    focus: String, gymName: String, setStarted: Date? = nil,
                    in ctx: ModelContext? = nil) -> SetEntry {
        let ctx = ctx ?? DataStore.shared.mainContext
        let session = openSession(focus: focus, gymName: gymName, in: ctx)
        let entry = SetEntry(exercise: exercise, weight: weight, reps: reps, rpe: rpe)
        entry.session = session
        ctx.insert(entry)
        try? ctx.save()
        let set = LoggedSet(exercise: exercise, weight: weight, reps: reps, rpe: rpe,
                            start: setStarted ?? Date().addingTimeInterval(-45), end: .now)
        Task { await WorkoutTracker.shared.recordSet(set) }
        return entry
    }

    /// Saves a set the other device logged. Its Health segment is already handled there.
    @MainActor
    static func save(_ set: LoggedSet, in ctx: ModelContext? = nil) {
        let ctx = ctx ?? DataStore.shared.mainContext
        let plan = DataStore.todayPlan(in: ctx)?.plan
        let session = openSession(focus: plan?.focus ?? "Workout", gymName: plan?.gymName ?? "", in: ctx)
        let entry = SetEntry(exercise: set.exercise, weight: set.weight, reps: set.reps, rpe: set.rpe)
        entry.session = session
        ctx.insert(entry)
        try? ctx.save()
    }

    @MainActor
    static func openSession(focus: String, gymName: String, in ctx: ModelContext) -> WorkoutSession {
        if let open = openSessions(in: ctx).first { return open }
        let s = WorkoutSession(focus: focus, gymName: gymName)
        ctx.insert(s)
        return s
    }

    /// Today's unfinished sessions, newest first.
    @MainActor
    static func openSessions(in ctx: ModelContext) -> [WorkoutSession] {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let d = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.date >= startOfDay && $0.endDate == nil },
                                                sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? ctx.fetch(d)) ?? []
    }

    /// A cancelled workout: delete its session and the sets logged in it, so they don't count anywhere.
    @MainActor
    static func discardOpenSessions(in ctx: ModelContext) {
        openSessions(in: ctx).forEach(ctx.delete)   // sets go with it (cascade)
        try? ctx.save()
    }
}
