import Foundation
import HealthKit
import Observation
import SwiftData

/// Runs a real HealthKit strength workout on iPhone (iOS 26+) or Apple Watch:
/// live heart rate + calories while you train, each logged set saved as a workout segment,
/// and the finished workout written to Health so it shows up in Fitness.
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

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var lastTimelineSample: Date = .distantPast

    struct Result {
        let workoutID: UUID?
        let start: Date
        let end: Date
        let activeCalories: Double
        let averageHeartRate: Double
        let maxHeartRate: Double
        let timeline: [Int]
    }

    // MARK: Permissions

    static var readTypes: Set<HKObjectType> {
        [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
         HKQuantityType(.heartRateVariabilitySDNN), HKQuantityType(.restingHeartRate),
         HKCategoryType(.sleepAnalysis), HKObjectType.workoutType()]
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
        guard !isRunning, HKHealthStore.isHealthDataAvailable() else { return }
        await requestAuthorization()

        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor

        do {
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
            self.startDate = start
            self.heartRate = 0
            self.activeCalories = 0
            self.heartRateTimeline = []
            self.isRunning = true
        } catch {
            lastError = "Couldn't start the Health workout: \(error.localizedDescription)"
        }
    }

    /// Each set becomes a segment event on the workout, with what you lifted in its metadata.
    func recordSet(exercise: String, weight: Double, reps: Int, start: Date, end: Date = .now) async {
        // A segment can't begin before the workout itself (the first set's timer starts when the screen opens).
        let start = max(start, startDate ?? start)
        guard let builder, start < end else { return }
        let event = HKWorkoutEvent(type: .segment, dateInterval: DateInterval(start: start, end: end),
                                   metadata: ["FORGEExercise": exercise,
                                              "FORGEWeightLb": weight,
                                              "FORGEReps": reps])
        try? await builder.addWorkoutEvents([event])
    }

    func finish() async -> Result? {
        guard let session, let builder, let startDate else { return nil }
        let end = Date()
        session.end()
        defer { reset() }
        do {
            try await builder.endCollection(at: end)
            let workout = try await builder.finishWorkout()
            let hrStats = builder.statistics(for: HKQuantityType(.heartRate))
            let bpm = HKUnit.count().unitDivided(by: .minute())
            return Result(workoutID: workout?.uuid, start: startDate, end: end,
                          activeCalories: activeCalories,
                          averageHeartRate: hrStats?.averageQuantity()?.doubleValue(for: bpm) ?? 0,
                          maxHeartRate: hrStats?.maximumQuantity()?.doubleValue(for: bpm) ?? 0,
                          timeline: heartRateTimeline)
        } catch {
            lastError = "Couldn't save the workout to Health: \(error.localizedDescription)"
            return Result(workoutID: nil, start: startDate, end: end, activeCalories: activeCalories,
                          averageHeartRate: 0, maxHeartRate: 0, timeline: heartRateTimeline)
        }
    }

    func discard() {
        session?.end()
        builder?.discardWorkout()
        reset()
    }

    private func reset() {
        isRunning = false
        session = nil
        builder = nil
        startDate = nil
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
                                    from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.lastError = message }
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
        let start = setStarted ?? Date().addingTimeInterval(-45)
        Task { await WorkoutTracker.shared.recordSet(exercise: exercise, weight: weight, reps: reps, start: start) }
        return entry
    }

    @MainActor
    static func openSession(focus: String, gymName: String, in ctx: ModelContext) -> WorkoutSession {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        let d = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.date >= startOfDay && $0.endDate == nil },
                                                sortBy: [SortDescriptor(\.date, order: .reverse)])
        if let open = try? ctx.fetch(d).first { return open }
        let s = WorkoutSession(focus: focus, gymName: gymName)
        ctx.insert(s)
        return s
    }
}
