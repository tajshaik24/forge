import Foundation
import Observation
import SwiftData
import SwiftUI

/// The workout under way on the iPhone: which lift is open, the numbers for the next set, rest, and
/// what the coach says between sets. Counting always goes through `WorkoutProgress` over the open
/// session's sets, the same way the Watch counts, so neither device can show "3 of 2".
@MainActor
@Observable
final class WorkoutModel {
    @ObservationIgnored private(set) var ctx: ModelContext?
    @ObservationIgnored private(set) var coach: CoachStore?
    @ObservationIgnored private let tracker = WorkoutTracker.shared
    let unit = SyncedSettings.unit
    let goal = TrainingGoal(rawValue: SyncedSettings.goal) ?? .buildMuscle

    /// The open session's sets, oldest first.
    private(set) var entries: [SetEntry] = []
    /// The expanded card. Nil when every lift is done (or there are none).
    private(set) var focus: Int?
    /// Weight (pounds) and reps you changed by hand for a lift's next set; otherwise the coach's numbers.
    private var drafts: [String: Draft] = [:]
    /// The set whose "How did it feel?" is showing.
    private(set) var askingEffort: PersistentIdentifier?
    /// A lift's last planned set is in: close its card once you've rated it or rest is over.
    private var advanceWhenReady = false
    /// A test set waiting for its rating, which logs it.
    var ratingTest: String?
    /// The weight or reps you're adjusting, for one lift.
    var editing: Field?

    private(set) var restUntil: Date?
    private(set) var restStarted: Date?
    /// What comes after this rest, for the rest bar, the alert and the Live Activity.
    private(set) var restNext = ""
    private(set) var setStarted = Date()

    private(set) var toast: String?
    private var toastID = 0
    @ObservationIgnored var toastSeconds: Double = 2.5
    private(set) var recordBuzz = 0
    private(set) var restBuzz = 0
    private(set) var logBuzz = 0

    /// The AI coach's wording of a rule note, keyed by the rule text so it only shows while that note stands.
    private(set) var aiNotes: [String: String] = [:]
    /// One sentence about each finished lift, from the AI coach.
    private(set) var recaps: [String: String] = [:]

    /// Each lift's sets from before this workout, for "since last time" and personal records.
    @ObservationIgnored private var before: [String: [SetRecord]] = [:]
    @ObservationIgnored private var remoteSeen = 0
    @ObservationIgnored private var appeared = Date()

    var sheet: Sheet?
    var confirmFinish = false
    var confirmCancel = false
    private(set) var isFinishing = false
    var finished: WorkoutSession?
    var coolingDown = false
    /// Debug screenshots: text already in the exercise search.
    @ObservationIgnored var pickerSearch = ""
    /// Debug screenshots: a heart rate to show without a Watch.
    var demoHeartRate: Double?

    struct Draft: Equatable {
        /// Pounds.
        var weight: Double
        var reps: Int
    }

    enum Field: Equatable {
        case weight(String), reps(String)
        var exercise: String {
            switch self { case .weight(let n), .reps(let n): n }
        }
    }

    enum Sheet: Identifiable {
        case howTo(PlannedExercise), progress(String), swap(Int), add, edit(SetEntry), guide(String)
        var id: String {
            switch self {
            case .howTo(let ex): "how-\(ex.name)"
            case .progress(let name): "progress-\(name)"
            case .swap(let i): "swap-\(i)"
            case .add: "add"
            case .edit(let s): "edit-\(s.persistentModelID.hashValue)"
            case .guide(let name): "guide-\(name)"
            }
        }
    }

    // MARK: Reading the workout

    var plan: PlannedWorkout? { coach?.plan }
    var lifts: [PlannedExercise] { plan?.exercises ?? [] }

    var doneSets: [WorkoutProgress.DoneSet] { entries.map(Self.done) }

    var progress: WorkoutProgress {
        WorkoutProgress(plan: plan ?? .own(gymName: "", restSeconds: 90), sets: doneSets)
    }

    var setsLogged: Int { entries.count }
    var isResting: Bool { restUntil != nil }
    var heartRate: Double { demoHeartRate ?? tracker.heartRate }
    var startDate: Date { tracker.startDate ?? entries.first?.session?.date ?? appeared }

    private static func done(_ e: SetEntry) -> WorkoutProgress.DoneSet {
        .init(exercise: e.exercise, weight: e.weight, reps: e.reps, rpe: e.rpe, date: e.date)
    }

    /// The saved set behind a row.
    func entry(for set: WorkoutProgress.DoneSet) -> SetEntry? {
        entries.first { $0.exercise == set.exercise && $0.date == set.date }
    }

    func catalog(_ name: String) -> Exercise? { ExerciseCatalog.named(name) }
    func isTimed(_ name: String) -> Bool { catalog(name)?.isTimed ?? false }
    func history(_ name: String) -> [SetRecord] { before[name] ?? [] }

    /// Warm-up steps before each lift (drills and lighter sets), when warm-ups are on.
    var warmUps: [String: [WarmUps.Step]] {
        guard SyncedSettings.warmUps, let plan else { return [:] }
        return WarmUps.beforeEachLift(plan, unit: unit)
    }

    /// Where a "find your weight" test landed, once a set felt Good or Hard.
    func calibration(_ lift: WorkoutProgress.Lift) -> Calibration.Result? {
        guard lift.exercise.calibrate == true, let ex = catalog(lift.exercise.name) else { return nil }
        return Calibration.result(for: ex, sets: lift.tests.map(\.record), goal: goal, unit: unit)
    }

    /// The target the working sets aim at: the plan's, or what the weight test found.
    func target(_ lift: WorkoutProgress.Lift) -> LoadTarget? {
        calibration(lift)?.working ?? lift.exercise.target
    }

    /// The coach's call for the next working set, from how the last one went.
    func call(_ lift: WorkoutProgress.Lift) -> NextSet.Call? {
        guard let last = lift.working.last, let ex = catalog(lift.exercise.name) else { return nil }
        return NextSet.after(last, exercise: ex, target: target(lift), setNumber: lift.working.count + 1,
                             goal: goal, unit: unit)
    }

    /// The weight and reps the next set (test or working) starts at.
    func draft(_ lift: WorkoutProgress.Lift) -> Draft {
        if let edited = drafts[lift.exercise.name] { return edited }
        return suggested(lift)
    }

    private func suggested(_ lift: WorkoutProgress.Lift) -> Draft {
        let name = lift.exercise.name
        let ex = catalog(name)
        if lift.isTesting, let ex {
            let reps = Calibration.testReps(for: ex)
            if let last = lift.tests.last,
               let next = Calibration.nextWeight(after: last.weight, rpe: last.rpe ?? Effort.easy.rpe, unit: unit) {
                return Draft(weight: next, reps: reps)
            }
            if let last = lift.tests.last { return Draft(weight: last.weight, reps: reps) }
            // An empty bar is a safe first test; otherwise you pick something light.
            return Draft(weight: ex.equipment.contains(.barbell) ? unit.toPounds(unit == .lb ? 45 : 20) : 0, reps: reps)
        }
        if let call = call(lift) { return Draft(weight: call.weight, reps: call.reps) }
        if let t = target(lift) { return Draft(weight: t.weight, reps: t.reps) }
        if let last = history(name).last { return Draft(weight: last.weight, reps: last.reps) }
        return Draft(weight: 0, reps: RepRange.parse(lift.exercise.reps).lowerBound)
    }

    func setDraft(_ lift: WorkoutProgress.Lift, _ draft: Draft) {
        drafts[lift.exercise.name] = draft
    }

    /// What the coach says under the sets: after a set, its call; before, the plan's reason.
    func coachLine(_ lift: WorkoutProgress.Lift) -> String {
        let timed = isTimed(lift.exercise.name)
        if lift.isTesting, let ex = catalog(lift.exercise.name) {
            return WorkoutText.testGuide(tests: lift.tests.count, testReps: Calibration.testReps(for: ex))
        }
        if lift.isDone, let recap = recaps[lift.exercise.name] { return recap }
        if let call = call(lift) {
            if lift.isDone { return "All \(lift.planned) sets done. Tap Add set for an extra one." }
            return aiNotes[call.note] ?? call.note
        }
        if let result = calibration(lift) {
            return "\(WorkoutText.amount(weight: result.tested.weight, reps: result.tested.reps, timed: false, unit: unit)) felt \(Effort(rpe: result.tested.rpe).label.lowercased()), so that's your weight found. Working sets: \(WorkoutText.amount(weight: result.working.weight, reps: result.working.reps, timed: false, unit: unit))."
        }
        if let t = lift.exercise.target { return t.note }
        return timed
            ? "First time: hold for \(WorkoutText.range(lift.exercise.reps)), stopping while your form is still good."
            : "First time: pick a weight you could do for \(WorkoutText.range(lift.exercise.reps)) reps with 2 left in the tank."
    }

    /// "Set 2 of 3", "Test set", "Warm-up": where you are in a lift, for the Live Activity.
    func setLabel(_ lift: WorkoutProgress.Lift) -> String {
        if lift.isTesting { return "Test set \(lift.tests.count + 1)" }
        if !lift.isStarted, let steps = warmUps[lift.exercise.name],
           steps.indices.contains(where: { !tracker.warmUpsDone.contains(WorkoutTracker.warmUpKey(lift.exercise.name, $0)) }) {
            return "Warm-up"
        }
        if lift.isDone { return "\(lift.working.count) of \(lift.planned) done" }
        return "Set \(lift.nextSet) of \(lift.planned)"
    }

    /// "Up next: set 2 of 3 · 135 lb × 8", or the next lift, or the end.
    func upNext() -> String {
        let p = progress
        guard let i = p.current(from: focus ?? 0) else { return "Every lift is done. Finish when you're ready." }
        let lift = p.lifts[i]
        let d = draft(lift)
        let amount = WorkoutText.amount(weight: d.weight, reps: d.reps, timed: isTimed(lift.exercise.name), unit: unit)
        if lift.isTesting { return "Up next: test set \(lift.tests.count + 1) · \(amount)" }
        if i != focus || !lift.isStarted { return "Up next: \(lift.exercise.name) · \(amount)" }
        return "Up next: set \(lift.nextSet) of \(lift.planned) · \(amount)"
    }

    // MARK: Starting and resuming

    /// Loads the open session and opens the lift you were on, not lift 1.
    func configure(ctx: ModelContext, coach: CoachStore) {
        let first = self.ctx == nil
        self.ctx = ctx
        self.coach = coach
        reload()
        loadHistory()
        if first {
            remoteSeen = tracker.remoteSets.count
            appeared = .now
            setStarted = .now
            let lastLift = entries.last.flatMap { last in lifts.firstIndex { $0.name == last.exercise } } ?? 0
            focus = progress.current(from: lastLift)
        }
    }

    func reload() {
        guard let ctx else { return }
        entries = (SetLogger.openSessions(in: ctx).first?.sets ?? []).sorted { $0.date < $1.date }
        if let focus, !lifts.indices.contains(focus) { self.focus = progress.current(from: 0) }
    }

    /// Earlier sets of every lift in the plan, before this workout began.
    private func loadHistory() {
        guard let ctx else { return }
        let start = entries.first?.session?.date ?? .now
        for lift in lifts where before[lift.name] == nil {
            before[lift.name] = DataStore.history(of: lift.name, in: ctx, days: 3650).filter { $0.date < start }
        }
    }

    // MARK: Cards

    func open(_ index: Int) {
        guard lifts.indices.contains(index) else { return }
        advanceWhenReady = false
        editing = nil
        ratingTest = nil
        withAnimation(.snappy) { focus = index }
    }

    /// Moves to the next unfinished lift once the one you're on has its sets.
    private func advanceIfDone() {
        guard advanceWhenReady else { return }
        advanceWhenReady = false
        let p = progress
        guard let focus, p.lifts.indices.contains(focus), p.lifts[focus].isDone else { return }
        askingEffort = nil
        withAnimation(.snappy) { self.focus = p.current(from: focus) }
    }

    // MARK: Logging

    /// Logs the next working set at the row's numbers, then asks how it felt (Good unless you say).
    func logWorking(_ index: Int) {
        guard let ctx, let plan, lifts.indices.contains(index) else { return }
        let lift = progress.lifts[index]
        let d = draft(lift)
        let entry = SetLogger.log(exercise: lift.exercise.name, weight: d.weight, reps: d.reps, rpe: Effort.good.rpe,
                                  focus: plan.focus, gymName: plan.gymName, setStarted: setStarted, in: ctx)
        afterLogging(entry, index: index)
        askingEffort = entry.persistentModelID
        celebrate(entry, in: index)
        let now = progress.lifts[index]
        if now.isDone {
            advanceWhenReady = true
            recap(now)
        }
        if !progress.isComplete { startRest(plan.restSeconds, next: upNext()) }
        reword(index)
    }

    /// A test set is logged with the rating you tap: the rating decides the next test weight.
    func logTest(_ index: Int, effort: Effort) {
        guard let ctx, let plan, lifts.indices.contains(index) else { return }
        let lift = progress.lifts[index]
        let d = draft(lift)
        let entry = SetLogger.log(exercise: lift.exercise.name, weight: d.weight, reps: d.reps, rpe: effort.rpe,
                                  focus: plan.focus, gymName: plan.gymName, setStarted: setStarted, in: ctx)
        ratingTest = nil
        afterLogging(entry, index: index)
        startRest(plan.restSeconds, next: upNext())
    }

    private func afterLogging(_ entry: SetEntry, index: Int) {
        drafts[entry.exercise] = nil
        editing = nil
        logBuzz += 1
        if focus != index { focus = index }
        reload()
    }

    /// Changes how a set felt. The coach's next call follows.
    func setEffort(_ entry: SetEntry, _ effort: Effort) {
        entry.rpe = effort.rpe
        try? ctx?.save()
        askingEffort = nil
        reload()
        if let i = lifts.firstIndex(where: { $0.name == entry.exercise }) { reword(i) }
        advanceIfDone()
    }

    /// Gold row, a tap and a toast when a set beats your best.
    private func celebrate(_ entry: SetEntry, in index: Int) {
        let lift = progress.lifts[index]
        guard let i = lift.working.firstIndex(where: { $0.date == entry.date }),
              let kind = WorkoutText.records(lift.working, before: history(lift.exercise.name))[i] else { return }
        recordBuzz += 1
        show(toast: "New best: \(WorkoutText.record(kind))")
    }

    /// The personal record each working set of a lift broke, by date.
    func records(_ lift: WorkoutProgress.Lift) -> [Date: PersonalRecords.Kind] {
        let kinds = WorkoutText.records(lift.working, before: history(lift.exercise.name))
        var out: [Date: PersonalRecords.Kind] = [:]
        for (set, kind) in zip(lift.working, kinds) { if let kind { out[set.date] = kind } }
        return out
    }

    func show(toast text: String) {
        toastID += 1
        let id = toastID
        withAnimation(.snappy) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(toastSeconds))
            if toastID == id { withAnimation(.easeOut) { toast = nil } }
        }
    }

    /// "+ Add set": one more planned set on this lift, so the count stays honest (4 of 4, never 4 of 3).
    func addSet(_ index: Int) {
        guard let coach, let ctx, var list = plan?.exercises, list.indices.contains(index) else { return }
        list[index].sets += 1
        coach.replaceTodayExercises(list, ctx)
        drafts[list[index].name] = nil
        open(index)
    }

    // MARK: Warm-ups

    func tickWarmUp(_ lift: PlannedExercise, _ i: Int, _ step: WarmUps.Step) {
        let key = WorkoutTracker.warmUpKey(lift.name, i)
        if tracker.warmUpsDone.contains(key) {
            tracker.setWarmUp(key, done: false)
            return
        }
        tracker.setWarmUp(key, done: true)
        logBuzz += 1
        // A short rest after each warm-up set, longer as they get heavier.
        if case .ramp(let r) = step {
            let steps = warmUps[lift.name] ?? []
            let more = steps.indices.contains(where: { $0 > i && !tracker.warmUpsDone.contains(WorkoutTracker.warmUpKey(lift.name, $0)) })
            startRest(r.rest, next: more ? "Up next: \(lift.name) warm-up" : upNext(), share: true)
        } else {
            setStarted = .now
        }
    }

    // MARK: Rest

    func startRest(_ seconds: Int, next: String, share: Bool = true) {
        guard seconds > 0 else { return }
        let until = Date().addingTimeInterval(TimeInterval(seconds))
        restStarted = .now
        restUntil = until
        restNext = next
        scheduleAlert(at: until)
        if share { tracker.shareRest(until: until) }
    }

    func extendRest() {
        guard let restUntil else { return }
        let later = max(restUntil, .now).addingTimeInterval(30)
        self.restUntil = later
        scheduleAlert(at: later)
        tracker.shareRest(until: later)
    }

    /// Skip: ends rest here and on the Watch.
    func skipRest() {
        if restUntil.map({ $0 > .now }) == true { tracker.shareRest(until: nil) }
        endRest()
    }

    /// Rest is over, by time or because the other device skipped it.
    func endRest() {
        guard restUntil != nil else { return }
        restUntil = nil
        restStarted = nil
        setStarted = .now
        restBuzz += 1
        RestAlerts.cancel()
        advanceIfDone()
    }

    /// The other device started, extended or skipped rest.
    func remoteRest(until: Date?) {
        guard let until else { return endRest() }
        if restUntil == nil { restStarted = .now; restNext = upNext() }
        restUntil = until
    }

    /// In a shared workout the Watch buzzes when rest ends; a phone alert would buzz the wrist twice.
    private func scheduleAlert(at date: Date) {
        if !tracker.isMirrored { RestAlerts.schedule(at: date, next: restNext) }
    }

    // MARK: Sets from the Watch

    /// Every set the Watch sent since last time (they can arrive in a burst), already saved by the tracker.
    func receiveRemoteSets() {
        let all = tracker.remoteSets
        guard all.count > remoteSeen else { return }
        let new = all[remoteSeen...]
        remoteSeen = all.count
        if let coach, let ctx, let plan {
            // Lifts added on the Watch: add them here too, so both show the same workout.
            var list = plan.exercises
            for set in new where !list.contains(where: { $0.name == set.exercise }) {
                if let ex = catalog(set.exercise) { list.append(coach.adding(ex, ctx)) }
            }
            if list != plan.exercises { coach.replaceTodayExercises(list, ctx) }
        }
        reload()
        loadHistory()
        guard let last = new.last, let i = lifts.firstIndex(where: { $0.name == last.exercise }) else { return }
        drafts[last.exercise] = nil
        logBuzz += 1
        let p = progress
        withAnimation(.snappy) { focus = p.lifts[i].isDone ? p.current(from: i) : i }
        // The Watch runs its own rest; this one shows it here without sending it back.
        if !p.isComplete, let plan { startRest(plan.restSeconds, next: upNext(), share: false) }
    }

    // MARK: Changing the workout

    /// Swaps a lift. One you've started keeps its sets as they are, and the new lift takes the sets left.
    func swap(_ index: Int, to replacement: Exercise) {
        guard let coach, let ctx, var list = plan?.exercises, list.indices.contains(index) else { return }
        let lift = progress.lifts[index]
        var new = coach.adding(replacement, ctx)
        if lift.isStarted {
            list[index].calibrate = nil
            list[index].sets = max(1, lift.all.count)
            new.sets = max(1, lift.planned - lift.working.count)
            list.insert(new, at: index + 1)
        } else {
            new.sets = lift.planned
            list[index] = new
        }
        coach.replaceTodayExercises(list, ctx)
        loadHistory()
        open(lift.isStarted ? index + 1 : index)
    }

    /// Adds a lift at the end. It opens straight away if nothing else is waiting.
    func add(_ exercise: Exercise) {
        guard let coach, let ctx, var list = plan?.exercises else { return }
        list.append(coach.adding(exercise, ctx))
        coach.replaceTodayExercises(list, ctx)
        loadHistory()
        let p = progress
        if focus == nil || focus.map({ p.lifts.indices.contains($0) && p.lifts[$0].isDone }) == true {
            open(list.count - 1)
        }
    }

    // MARK: The AI coach

    /// Rewords the rule's note while you rest; the rule text shows until (and unless) a reply fits.
    private func reword(_ index: Int) {
        guard SetCoach.shared.isAvailable, let restUntil, lifts.indices.contains(index) else { return }
        let lift = progress.lifts[index]
        guard !lift.isDone, let note = call(lift)?.note, aiNotes[note] == nil else { return }
        Task {
            if let text = await SetCoach.shared.reword(note, lift: lift.exercise.name, within: restUntil.timeIntervalSinceNow) {
                aiNotes[note] = text
            }
        }
    }

    private func recap(_ lift: WorkoutProgress.Lift) {
        guard SetCoach.shared.isAvailable, let plan else { return }
        let timed = isTimed(lift.exercise.name)
        let sets = lift.working.map {
            WorkoutText.amount(weight: $0.weight, reps: $0.reps, timed: timed, unit: unit) + ", " + Effort(rpe: $0.rpe).label
        }
        Task {
            if let text = await SetCoach.shared.recap(lift: lift.exercise.name, sets: sets, within: TimeInterval(plan.restSeconds)) {
                recaps[lift.exercise.name] = text
            }
        }
    }

    // MARK: Ending

    /// Saves the workout. A workout with no sets isn't kept: the screen just closes.
    func finish(dismiss: @escaping () -> Void) {
        guard let coach, let ctx, !isFinishing else { return }
        isFinishing = true
        RestAlerts.cancel()
        restUntil = nil
        Task {
            let alreadySaving = coach.isFinishing
            var session = await coach.finishWorkout(ctx)
            if session == nil, alreadySaving {
                // The Watch ended it at the same moment: wait for that save and show its summary.
                while coach.isFinishing { try? await Task.sleep(for: .milliseconds(100)) }
                session = coach.lastFinished.flatMap { $0.endDate.map { -$0.timeIntervalSinceNow < 60 } == true ? $0 : nil }
            }
            isFinishing = false
            if let session {
                finished = session
            } else {
                LiveActivityController.end()
                dismiss()
            }
        }
    }

    /// Throws the workout away: the Health workout and the sets logged in it.
    func cancel() {
        guard let coach, let ctx else { return }
        tracker.discard()
        SetLogger.discardOpenSessions(in: ctx)
        RestAlerts.cancel()
        coach.restoreCoachPlan(ctx)
        LiveActivityController.end()
    }
}
