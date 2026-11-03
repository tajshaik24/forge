import Foundation
import SwiftData
import WatchKit

/// The workout under way on the wrist: which lift you're on, what's on the tiles, rest, and every set
/// of this workout from both devices. The screens only read it and call its actions, so the whole flow
/// (and the debug demo states) lives in one place.
///
/// Counting always goes through `WorkoutProgress`, built from `WorkoutSets.combine`: the same rules as
/// the iPhone, each set counted once wherever it came from.
@MainActor
@Observable
final class WatchWorkout {
    /// Grows as you add lifts, and follows the iPhone's edits in a shared workout.
    private(set) var plan: PlannedWorkout
    /// Started from the iPhone before its plan reached the Watch: take the first real plan that arrives.
    private(set) var isPlaceholder: Bool
    /// The lift on screen, an index into `plan.exercises`.
    private(set) var index = 0
    /// On the tiles, in the user's unit (weight) and reps or seconds.
    var weight: Double = 0
    var reps: Double = 8
    private(set) var restUntil: Date?
    private(set) var restLength: TimeInterval = 90
    /// When the set on the tiles began, for its Health segment.
    private(set) var setStarted = Date()
    /// The coach's call for the set on the tiles, in a line.
    private(set) var note: String?
    /// Logged with ✓, waiting for how it felt before it's saved and sent (the RPE travels with the set).
    private(set) var pending: Pending?
    /// "+ Add set" on a lift whose planned sets are done: allows exactly one more.
    private(set) var extraSet = false
    /// Opened a lift from the list after everything was done, to look at it or add a set.
    private(set) var reviewing = false
    /// Ending here: the tracker stopping isn't the iPhone ending it.
    private(set) var isFinishing = false
    private(set) var summary: Summary?

    /// Every set of this workout, each once, and where that leaves the plan.
    private(set) var sets: [WorkoutProgress.DoneSet] = []
    private(set) var progress: WorkoutProgress

    private var own: [WorkoutProgress.DoneSet] = []
    private var remote: [WorkoutProgress.DoneSet] = []
    private var stored: [WorkoutProgress.DoneSet] = []
    private var remoteSeen = 0
    private var ctx: ModelContext?
    private var warmUpPlan: [String: [WarmUps.Step]] = [:]

    let unit = SyncedSettings.unit
    let goal = TrainingGoal(rawValue: SyncedSettings.goal) ?? .buildMuscle
    private let tracker = WorkoutTracker.shared

    struct Pending: Equatable {
        let exercise: String
        /// Pounds.
        let weight: Double
        let reps: Int
        let start: Date
        let end: Date
        let isTest: Bool
    }

    struct Summary: Equatable {
        let start: Date
        let end: Date
        let sets: [WorkoutProgress.DoneSet]
        let calories: Double
        let averageHeartRate: Double
        let maxHeartRate: Double
    }

    /// Sets logged on this Watch, kept across the workout screen closing and opening again (in a shared
    /// workout they aren't in the store: the iPhone keeps them). Tied to the workout's start.
    private static var ownLog: (start: Date, sets: [WorkoutProgress.DoneSet])?

    init(plan: PlannedWorkout, isPlaceholder: Bool = false) {
        self.plan = plan
        self.isPlaceholder = isPlaceholder
        progress = WorkoutProgress(plan: plan, sets: [])
        warmUpPlan = WarmUps.beforeEachLift(plan, unit: unit)
    }

    #if DEBUG
    /// Demo screens: no Health workout, so these stand in for the tracker's numbers.
    var demoStart: Date?
    var demoHeartRate: Double?
    var demoCalories: Double?
    var isDemo: Bool { demoStart != nil }
    #else
    var isDemo: Bool { false }
    #endif

    // MARK: What the screens show

    var startDate: Date? {
        #if DEBUG
        if let demoStart { return demoStart }
        #endif
        return tracker.startDate
    }

    var heartRate: Double {
        #if DEBUG
        if let demoHeartRate { return demoHeartRate }
        #endif
        return tracker.heartRate
    }

    var calories: Double {
        #if DEBUG
        if let demoCalories { return demoCalories }
        #endif
        return tracker.activeCalories
    }

    var lift: WorkoutProgress.Lift? { progress.lifts.indices.contains(index) ? progress.lifts[index] : nil }
    var catalog: Exercise? { lift.flatMap { ExerciseCatalog.named($0.exercise.name) } }
    var isTimed: Bool { catalog?.isTimed ?? false }
    var isBodyweight: Bool { catalog.map { $0.equipment.isEmpty } ?? false }
    var isAllDone: Bool { progress.isComplete }
    /// The All done screen, unless you went back to a lift from the list.
    var showsAllDone: Bool { isAllDone && !extraSet && !reviewing }
    /// The lift on screen has its planned sets and no extra one was asked for: ✓ isn't offered.
    var liftFinished: Bool { (lift?.isDone ?? false) && !extraSet }
    var setsDone: Int { progress.setsDone }

    /// Warm-up steps still to tick before the first set of the lift on screen.
    var warmUpSteps: [WarmUps.Step] {
        guard SyncedSettings.warmUps, let lift, !lift.isStarted else { return [] }
        return warmUpPlan[lift.exercise.name] ?? []
    }

    var showsWarmUp: Bool {
        guard let lift, !warmUpSteps.isEmpty else { return false }
        return warmUpSteps.indices.contains { !isWarmUpDone(lift.exercise.name, $0) }
    }

    func isWarmUpDone(_ exercise: String, _ step: Int) -> Bool {
        tracker.warmUpsDone.contains(WorkoutTracker.warmUpKey(exercise, step))
    }

    /// Reps for a test set on a "find your weight" lift.
    var testReps: Int { catalog.map(Calibration.testReps) ?? 5 }

    // MARK: Starting and resuming

    /// Opens the workout: picks up the sets already logged in it and the lift you were on.
    func begin(in ctx: ModelContext) {
        self.ctx = ctx
        noteStart()
        if let start = startDate, let log = Self.ownLog, log.start == start { own = log.sets }
        remoteSeen = 0
        remote = []
        ingestRemote(announce: false)
        refreshStored()
        resume()
    }

    /// Back at the right lift and set after the screen was closed, the app relaunched, or sets came from the iPhone.
    func resume() {
        recount()
        if isAllDone {
            index = min(index, max(plan.exercises.count - 1, 0))
            restUntil = nil
        } else {
            index = WorkoutSets.resumeLift(in: progress, sets: sets) ?? 0
        }
        extraSet = false
        prefill()
    }

    // MARK: Logging a set

    /// ✓: the set is done. Rest starts now; it's saved once you say how it felt.
    func logTapped() {
        guard let lift, !liftFinished, pending == nil else { return }
        let set = Pending(exercise: lift.exercise.name, weight: unit.toPounds(weight), reps: Int(reps), start: setStarted, end: .now, isTest: lift.isTesting)
        pending = set
        WKInterfaceDevice.current().play(.success)
        // Rest runs while you rate it; it's cancelled again if that was the last set of the workout.
        startRest(TimeInterval(plan.restSeconds))
    }

    /// How the set felt (or Good, when the question timed out): save it, send it, move on.
    func rate(_ effort: Effort) {
        guard let set = pending else { return }
        pending = nil
        save(set, rpe: effort.rpe)
        advance(from: set.exercise)
    }

    /// Counts the set here at once; in a shared workout, returns the delivery to the iPhone.
    @discardableResult
    private func save(_ set: Pending, rpe: Int) -> Task<Void, Never>? {
        let done = WorkoutProgress.DoneSet(exercise: set.exercise, weight: set.weight, reps: set.reps, rpe: rpe, date: set.end)
        own.append(done)
        if let start = startDate { Self.ownLog = (start, own) }
        if tracker.isMirrored {
            // The iPhone keeps the history; this adds the Health segment and sends it over
            // (and saves it here if the iPhone can't be reached).
            let logged = LoggedSet(exercise: set.exercise, weight: set.weight, reps: set.reps, rpe: rpe,
                                   start: set.start, end: set.end)
            recount()
            return Task { await tracker.recordSet(logged) }
        }
        SetLogger.log(exercise: set.exercise, weight: set.weight, reps: set.reps, rpe: rpe,
                      focus: plan.focus, gymName: plan.gymName, setStarted: set.start, in: ctx)
        refreshStored()
        recount()
        return nil
    }

    /// After a set of `exercise`: the next set of the same lift, the next unfinished lift, or All done.
    private func advance(from exercise: String) {
        extraSet = false
        reviewing = false
        guard let i = plan.exercises.firstIndex(where: { $0.name == exercise }) else { return }
        index = i
        if isAllDone {
            // Never ends the workout on its own: you might add a set or a lift.
            stopRest()
            note = nil
            return
        }
        if progress.lifts[i].isDone, let next = progress.current(from: i) { index = next }
        prefill()
    }

    // MARK: Rest

    func startRest(_ seconds: TimeInterval) {
        restLength = seconds
        let until = Date().addingTimeInterval(seconds)
        restUntil = until
        tracker.shareRest(until: until)
    }

    func addRest(_ seconds: TimeInterval) {
        guard let until = restUntil else { return }
        restLength += seconds
        restUntil = until.addingTimeInterval(seconds)
        tracker.shareRest(until: restUntil)
    }

    func stopRest() {
        guard restUntil != nil else { return }
        restUntil = nil
        setStarted = .now
        tracker.shareRest(until: nil)
    }

    /// The rest ran out (the timer on screen, or the iPhone said so).
    func restEnded() {
        restUntil = nil
        setStarted = .now
    }

    /// The iPhone started, extended or skipped rest.
    func remoteRest(until: Date?) {
        if let until {
            restLength = max(until.timeIntervalSinceNow, 1)
            restUntil = until
        } else {
            restEnded()
        }
    }

    // MARK: Moving around

    /// From the workout list: do this lift next. A finished lift shows its sets, with "+ Add set" only.
    /// Rest keeps running: it's between sets, whichever lift comes next.
    func jump(to i: Int) {
        guard plan.exercises.indices.contains(i) else { return }
        reviewing = isAllDone
        guard i != index else { return }
        index = i
        extraSet = false
        if restUntil == nil { setStarted = .now }
        prefill()
    }

    /// Leaves the lift for later (it comes back once the others are done).
    func skipLift() {
        guard let next = WorkoutSets.lift(after: index, in: progress) else { return }
        jump(to: next)
    }

    var canSkip: Bool { WorkoutSets.lift(after: index, in: progress) != nil && !isAllDone }

    /// "+ Add set" on a finished lift.
    func addSet() {
        guard lift?.isDone == true else { return }
        extraSet = true
        setStarted = .now
        if let lift, let last = lift.working.last {
            weight = unit.roundToStep(unit.fromPounds(last.weight))
            reps = Double(last.reps)
        }
        note = "Extra set: it's on top of the plan."
    }

    /// A lift picked on the Watch: up next if the one you're on is finished.
    func add(_ ex: PlannedExercise) {
        let at = plan.exercises.isEmpty ? 0 : min(index + 1, plan.exercises.count)
        let finishedCurrent = lift?.isDone ?? true
        plan.exercises.insert(ex, at: at)
        if plan.isCustom { plan.retitle(unit: unit, warmUps: SyncedSettings.warmUps) }
        warmUpPlan = WarmUps.beforeEachLift(plan, unit: unit)
        recount()
        if finishedCurrent {
            index = at
            extraSet = false
            prefill()
        }
    }

    /// The iPhone changed the plan (added or swapped lifts) during a shared workout, or the first real
    /// plan arrived for a workout started on the iPhone.
    func adopt(_ updated: PlannedWorkout) {
        guard updated != plan else { return }
        let name = lift?.exercise.name
        plan = updated
        isPlaceholder = false
        warmUpPlan = WarmUps.beforeEachLift(plan, unit: unit)
        recount()
        if let name, let i = plan.exercises.firstIndex(where: { $0.name == name }) {
            index = i
        } else {
            index = WorkoutSets.resumeLift(in: progress, sets: sets) ?? 0
            prefill()
        }
    }

    /// Sets the iPhone logged: every new one, even when several arrive together.
    func ingestRemote(announce: Bool = true) {
        let all = tracker.remoteSets
        if all.count < remoteSeen { remoteSeen = 0; remote = [] }   // a new workout began
        let new = all.dropFirst(remoteSeen)
        remoteSeen = all.count
        guard !new.isEmpty else { return }
        for set in new {
            remote.append(WorkoutProgress.DoneSet(set))
            if !plan.exercises.contains(where: { $0.name == set.exercise }), let ex = ExerciseCatalog.named(set.exercise), let ctx {
                // Added on the iPhone; its updated plan may not have arrived yet.
                plan.exercises.append(WatchPicks.planned(ex, ctx))
                warmUpPlan = WarmUps.beforeEachLift(plan, unit: unit)
            }
        }
        refreshStored()
        recount()
        guard announce, let last = new.last else { return }
        WKInterfaceDevice.current().play(.click)
        // Follow the iPhone to the lift it's on. Rest arrives separately, from the iPhone's timer.
        advance(from: last.exercise)
        setStarted = .now
    }

    // MARK: Finishing

    /// Saves the workout here (or, when shared, lets the iPhone file it) and shows the summary.
    func finish() async {
        guard !isFinishing, summary == nil else { return }
        isFinishing = true
        defer { isFinishing = false }
        // A set still waiting for its rating goes in as Good, and reaches the iPhone before the workout ends.
        if let set = pending { pending = nil; await save(set, rpe: Effort.good.rpe)?.value }
        let shared = tracker.isMirrored
        let start = startDate ?? .now
        let result = isDemo ? nil : await tracker.finish()
        if !shared, !isDemo, let ctx, !sets.isEmpty {
            let session = SetLogger.openSession(focus: plan.focus, gymName: plan.gymName, in: ctx)
            // Named after the lifts you added, which the first set didn't know yet.
            if plan.isCustom { session.focus = plan.focus }
            session.endDate = result?.end ?? .now
            if let r = result {
                session.date = min(session.date, r.start)
                session.healthWorkoutID = r.workoutID
                session.activeCalories = r.activeCalories
                session.averageHeartRate = r.averageHeartRate
                session.maxHeartRate = r.maxHeartRate
                session.heartRates = r.timeline
            }
            try? ctx.save()
        }
        Self.ownLog = nil
        if let r = result {
            summary = Summary(start: r.start, end: r.end, sets: sets, calories: r.activeCalories,
                              averageHeartRate: r.averageHeartRate, maxHeartRate: r.maxHeartRate)
        } else {
            summary = endedElsewhere(start: start)
        }
    }

    /// The iPhone ended the shared workout (and the Watch saved it to Health without a result for this
    /// screen): the summary comes from what the tracker saw.
    func endedOnPhone() {
        guard !isFinishing, summary == nil else { return }
        // A set still waiting for its rating can't reach the iPhone any more; it shows here.
        if let set = pending {
            pending = nil
            own.append(.init(exercise: set.exercise, weight: set.weight, reps: set.reps, rpe: Effort.good.rpe, date: set.end))
            recount()
        }
        Self.ownLog = nil
        summary = endedElsewhere(start: knownStart ?? .now)
    }

    /// The start, remembered while the workout runs: the tracker forgets it once the workout ends.
    private var knownStart: Date?
    func noteStart() { if let s = startDate { knownStart = s } }

    private func endedElsewhere(start: Date) -> Summary {
        let timeline = tracker.heartRateTimeline.filter { $0 > 0 }
        let avg = timeline.isEmpty ? heartRate : Double(timeline.reduce(0, +)) / Double(timeline.count)
        return Summary(start: knownStart ?? start, end: .now, sets: sets, calories: calories,
                       averageHeartRate: avg, maxHeartRate: Double(timeline.max() ?? 0))
    }

    // MARK: Counting

    private func refreshStored() {
        guard let ctx else { return }
        stored = SetLogger.currentSets(in: ctx)
    }

    private func recount() {
        sets = WorkoutSets.combine(own: own, remote: remote, stored: stored, since: startDate)
        progress = WorkoutProgress(plan: plan, sets: sets)
    }

    // MARK: The coach's call for the next set

    /// Puts the right weight and reps on the tiles for the set coming up, with the coach's one-line why.
    func prefill() {
        guard let lift, let catalog else {
            note = nil
            return
        }
        let ex = lift.exercise
        if ex.calibrate == true, lift.working.isEmpty {
            prefillTest(lift, catalog)
            return
        }
        if lift.isDone, !extraSet {
            note = nil
            if let last = lift.working.last { show(weight: last.weight, reps: last.reps) }
            return
        }
        if let last = lift.working.last {
            let call = NextSet.after(last, exercise: catalog, target: target(for: lift, catalog),
                                     setNumber: lift.working.count + 1, goal: goal, unit: unit)
            show(weight: call.weight, reps: call.reps)
            note = call.note
            return
        }
        if let t = ex.target {
            show(weight: t.weight, reps: t.reps)
            note = nil
            return
        }
        let history = ctx.map { DataStore.history(of: ex.name, in: $0) } ?? []
        if let last = history.last {
            show(weight: last.weight, reps: last.reps)
        } else {
            weight = 0
            reps = Double(RepRange.parse(ex.reps).lowerBound)
        }
        note = nil
    }

    /// Test sets: the next weight to try after an easy one; once a set felt Good or Hard, the working weight it found.
    private func prefillTest(_ lift: WorkoutProgress.Lift, _ catalog: Exercise) {
        if let result = Calibration.result(for: catalog, sets: lift.tests.map(\.record), goal: goal, unit: unit) {
            show(weight: result.working.weight, reps: result.working.reps)
            note = "Found it: \(unit.format(pounds: result.working.weight)) × \(result.working.reps) from here."
        } else if let last = lift.tests.last,
                  let next = Calibration.nextWeight(after: last.weight, rpe: last.rpe ?? Effort.easy.rpe, unit: unit) {
            show(weight: next, reps: testReps)
            note = "Easy, so go up. \(testReps) reps, then rate it."
        } else {
            // An empty bar is a safe first test; otherwise you pick something light.
            weight = catalog.equipment.contains(.barbell) ? (unit == .lb ? 45 : 20) : 0
            reps = Double(testReps)
            note = nil
        }
    }

    private func target(for lift: WorkoutProgress.Lift, _ catalog: Exercise) -> LoadTarget? {
        if let t = lift.exercise.target { return t }
        guard lift.exercise.calibrate == true else { return nil }
        return Calibration.result(for: catalog, sets: lift.tests.map(\.record), goal: goal, unit: unit)?.working
    }

    private func show(weight pounds: Double, reps: Int) {
        weight = unit.roundToStep(unit.fromPounds(pounds))
        self.reps = Double(reps)
    }

    // MARK: Text

    /// "135×8", or "×12" for bodyweight.
    func describe(_ set: WorkoutProgress.DoneSet) -> String {
        guard set.weight > 0 else { return "×\(set.reps)" }
        return unit.fromPounds(set.weight).formatted(.number.precision(.fractionLength(0...1))) + "×\(set.reps)"
    }

    #if DEBUG
    /// Demo screens: put the workout in a given state without a Health session.
    func demo(sets: [WorkoutProgress.DoneSet], at index: Int, in ctx: ModelContext) {
        self.ctx = ctx
        own = sets
        recount()
        self.index = index
        prefill()
    }

    func demoPending(_ set: Pending) { pending = set }
    func demoSummary(_ s: Summary) { summary = s }
    #endif
}
