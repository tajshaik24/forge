import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(CoachStore.self) private var coach
    @Environment(\.hinge) private var hinge
    private let tracker = WorkoutTracker.shared

    @Query private var todaysSets: [SetEntry]
    @Query private var notes: [CoachNote]

    @State private var exerciseIndex = 0
    /// In the user's unit (lb or kg); converted to pounds when saved.
    @State private var weight: Double = 0
    @State private var reps = 10
    @State private var rpe = 8
    @State private var restUntil: Date?
    @State private var setStarted = Date()
    @State private var finished: WorkoutSession?
    @State private var sheet: Sheet?
    @State private var restBuzz = 0
    @State private var restStarted: Date?
    @State private var phase: Phase = .lifting
    @State private var confirmCancel = false
    /// Warm-up steps ticked off, as "exercise#index".
    @State private var warmedUp: Set<String> = []

    /// The lifts (each with its own short warm-up), then an optional cool-down.
    enum Phase { case lifting, coolDown }

    private let unit = SyncedSettings.unit

    enum Sheet: Identifiable {
        case form, swap, add, edit(SetEntry), guide(String)
        var id: String {
            switch self {
            case .form: "form"
            case .guide(let name): "guide-\(name)"
            case .swap: "swap"
            case .add: "add"
            case .edit(let s): "edit-\(s.persistentModelID.hashValue)"
            }
        }
    }

    init() {
        let start = Calendar.current.startOfDay(for: .now)
        _todaysSets = Query(filter: #Predicate<SetEntry> { $0.date >= start }, sort: \SetEntry.date)
    }

    private var plan: PlannedWorkout? { coach.plan }
    private var exercises: [PlannedExercise] { plan?.exercises ?? [] }
    private var current: PlannedExercise? {
        exercises.indices.contains(exerciseIndex) ? exercises[exerciseIndex] : nil
    }
    private func logged(_ name: String) -> [SetEntry] { todaysSets.filter { $0.exercise == name } }
    private var setNumber: Int { (current.map { working(logged($0.name), $0) } ?? 0) + 1 }
    private let goal = TrainingGoal(rawValue: SyncedSettings.goal) ?? .buildMuscle

    /// Working sets done. On a "find your weight" lift the test sets don't count: the set that
    /// reached RPE 8 is the first working set, and the rest follow at the weight it implies.
    private func working(_ sets: [SetEntry], _ ex: PlannedExercise) -> Int {
        guard ex.calibrate == true else { return sets.count }
        guard let found = sets.firstIndex(where: { ($0.rpe ?? 0) >= Calibration.foundAtRPE && $0.weight > 0 }) else { return 0 }
        return sets.count - found
    }

    private func records(_ sets: [SetEntry]) -> [SetRecord] {
        sets.map { SetRecord(date: $0.date, weight: $0.weight, reps: $0.reps, rpe: $0.rpe) }
    }

    /// Where the weight test landed, once a set has felt hard enough.
    private func calibration(_ ex: PlannedExercise, _ sets: [SetEntry]) -> Calibration.Result? {
        guard ex.calibrate == true, let catalog = ExerciseCatalog.named(ex.name) else { return nil }
        return Calibration.result(for: catalog, sets: records(sets), goal: goal, unit: unit)
    }

    /// Exercises this gym and your notes allow.
    private var pool: [Exercise] {
        let gym = DataStore.activeGym(in: ctx)?.equipment ?? Set(Equipment.allCases)
        let avoid = notes.reduce(into: Set<MovementFlag>()) { $0.formUnion($1.avoid) }
        return ExerciseCatalog.available(gym: gym, avoiding: avoid)
    }

    var body: some View {
        Group {
            if let finished {
                SummaryView(session: finished) { dismiss() }
            } else if phase == .coolDown, let plan {
                DrillsView(mode: .coolDown, drills: plan.coolDown) { finish() }
            } else if let current, let plan {
                training(current, plan)
            } else if let plan, plan.isCustom {
                emptyWorkout(plan)
            } else {
                ProgressView()
            }
        }
        .background(Theme.ground)
        .task {
            await RestAlerts.requestPermission()
            await tracker.start(focus: plan?.focus ?? "Workout")
            prefill()
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .form:
                if let current { NavigationStack { ExerciseDetailView(name: current.name, planned: current) } }
            case .guide(let name):
                NavigationStack { ExerciseDetailView(name: name) }
            case .swap:
                if let current { SwapSheet(current: current, pool: pool) { swap(to: $0) } }
            case .add:
                AddExerciseSheet(pool: pool, existing: Set(exercises.map(\.name))) { add($0) }
            case .edit(let entry):
                EditSetSheet(entry: entry, unit: unit)
            }
        }
        .sensoryFeedback(.success, trigger: restBuzz)
        .onChange(of: tracker.remoteSets.count) { if let set = tracker.remoteSets.last { loggedOnWatch(set) } }
        .onChange(of: tracker.remoteRest) {
            guard let change = tracker.remoteRest else { return }
            if let until = change.until { restUntil = until } else { endRest(share: false) }
        }
        .onChange(of: coach.lastFinished) { if let done = coach.lastFinished, finished == nil { finished = done } }
        .onChange(of: restUntil) { old, new in if old == nil, new != nil { restStarted = .now } }
        .onChange(of: liveState, initial: true) {
            if let liveState, let plan {
                LiveActivityController.show(liveState, focus: plan.focus, workoutStart: tracker.startDate ?? .now)
            } else {
                LiveActivityController.end()
            }
        }
        .onDisappear { LiveActivityController.end() }
        .onReceive(NotificationCenter.default.publisher(for: RestCommand.notification)) { note in
            guard restUntil != nil else { return }
            switch note.object as? RestCommand {
            case .skip: endRest()
            case .extend: extendRest()
            case nil: break
            }
        }
    }

    /// What the Lock Screen / Dynamic Island shows. Nil once the workout is over.
    private var liveState: WorkoutActivityAttributes.ContentState? {
        guard finished == nil, phase == .lifting, let current else { return nil }
        let resting = restUntil.map { $0 > .now } == true
        return .init(exercise: current.name, setNumber: min(setNumber, current.sets), totalSets: current.sets,
                     restStarted: resting ? restStarted : nil, restUntil: resting ? restUntil : nil,
                     nextUp: liveDetail(current, resting: resting), onWatch: tracker.isMirrored)
    }

    /// The Live Activity's last line, which shouldn't repeat the name above it: the target while
    /// lifting, what's next while resting.
    private func liveDetail(_ ex: PlannedExercise, resting: Bool) -> String {
        if resting {
            return setNumber <= ex.sets ? "Up next: set \(setNumber) of \(ex.sets)" : nextUp
        }
        if let t = ex.target, t.weight > 0 { return "Target \(unit.format(pounds: t.weight)) × \(t.reps)" }
        if exercises.indices.contains(exerciseIndex + 1) { return "Then \(exercises[exerciseIndex + 1].name)" }
        return "Last exercise"
    }

    /// One scrolling column on a regular iPhone. On iPhone Duo, propped half-open, what you read sits above
    /// the fold and what you tap below it; opened flat, the form guide fills the other side.
    @ViewBuilder
    private func training(_ ex: PlannedExercise, _ plan: PlannedWorkout) -> some View {
        switch hinge {
        case .partlyOpen:
            FoldSplit {
                ScrollView { readout(ex, plan).padding(20) }
            } second: {
                ScrollView { controls(ex, plan).padding(20) }
            } single: {
                column(ex, plan)
            }
        case .open:
            FoldSplit {
                column(ex, plan)
            } second: {
                NavigationStack { ExerciseDetailView(name: ex.name, planned: ex) }.id(ex.name)
            } single: {
                column(ex, plan)
            }
        default:
            column(ex, plan)
        }
    }

    private func column(_ ex: PlannedExercise, _ plan: PlannedWorkout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                readout(ex, plan)
                controls(ex, plan)
            }
            .padding(20)
        }
    }

    /// The exercise, its target, where you are in it, and the rest timer.
    private func readout(_ ex: PlannedExercise, _ plan: PlannedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(plan)

            HStack(alignment: .top) {
                Button { sheet = .form } label: {
                    HStack(spacing: 8) {
                        Text(ex.name.uppercased()).font(Theme.display(30)).multilineTextAlignment(.leading)
                        Text("Form").font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .overlay(Capsule().stroke(Theme.hairline))
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Menu {
                    Button("Swap exercise", systemImage: "arrow.triangle.2.circlepath") { sheet = .swap }
                    Button(plan.isCustom ? "Add exercise" : "Add exercise after this", systemImage: "plus") { sheet = .add }
                    Button("Skip to next", systemImage: "forward") { next() }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 22)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Exercise options")
            }

            if let catalog = ExerciseCatalog.named(ex.name), catalog.photo != nil {
                ExercisePhotoPair(exercise: catalog, height: 110)
            }

            if ex.calibrate == true {
                CalibrationCard(exercise: ex, tests: logged(ex.name), result: calibration(ex, logged(ex.name)),
                                goal: goal, unit: unit)
            } else if let target = ex.target {
                Label(target.weight > 0
                      ? "Target \(unit.format(pounds: target.weight)) × \(target.reps)\(timed ? " s" : "") · \(target.note)"
                      : "Target \(target.reps) \(timed ? "s" : "reps") · \(target.note)",
                      systemImage: "scope")
                    .font(.system(size: 13)).foregroundStyle(Theme.accentText)
            } else if timed {
                Text("First time: hold for \(ex.reps), stopping while your form is still good.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
            } else {
                Text("First time: pick a weight you could do for \(ex.reps) reps with 2 left in the tank.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            if let cue = ex.cue { NoteChip(text: cue) }

            if SyncedSettings.warmUps, logged(ex.name).isEmpty, let steps = warmUpSteps[ex.name] {
                warmUpCard(ex, steps)
            }

            setStrip(ex)

            if plan.isCustom, exerciseIndex + 1 >= exercises.count, working(logged(ex.name), ex) >= ex.sets {
                allDoneCard
            }

            if let restUntil {
                RestPanel(until: restUntil,
                          cue: plan.restSeconds > 90 ? "Breathe out as you press. Sit for 10 s before standing." : nil,
                          done: { endRest() },
                          extend: extendRest)
            }
        }
    }

    /// Weight, reps and effort for the next set, then the sets logged so far.
    private func controls(_ ex: PlannedExercise, _ plan: PlannedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if restUntil == nil {
                Stepper(value: $weight, in: 0...1000, step: unit.step) {
                    valueLabel(weight.formatted(.number.precision(.fractionLength(0...1))), unit.label)
                }
                if timed {
                    Stepper(value: $reps, in: 5...300, step: 5) { valueLabel("\(reps)", "SECONDS") }
                } else {
                    Stepper(value: $reps, in: 1...50) { valueLabel("\(reps)", "REPS") }
                }
                SectionLabel("How hard? (RPE)")
                Picker("RPE", selection: $rpe) { ForEach(6...10, id: \.self) { Text("\($0)") } }
                    .pickerStyle(.segmented)
                Text("10 = nothing left · 8 = two reps left").font(.system(size: 11)).foregroundStyle(Theme.muted)
                Button(ex.calibrate == true && calibration(ex, logged(ex.name)) == nil ? "Log test set" : "Log set \(setNumber)") { logSet(ex, plan) }.buttonStyle(AccentButtonStyle())
            }

            loggedList(ex)
        }
    }

    /// Holds and carries log seconds in place of reps.
    private var timed: Bool { current.flatMap { ExerciseCatalog.named($0.name) }?.isTimed ?? false }

    private func header(_ plan: PlannedWorkout) -> some View {
        HStack {
            Button {
                if SetLogger.openSessions(in: ctx).contains(where: { !($0.sets ?? []).isEmpty }) { confirmCancel = true } else { cancel() }
            } label: { Image(systemName: "xmark") }
                .frame(width: 44, height: 44).accessibilityLabel("Cancel workout")
                .confirmationDialog("Cancel this workout?", isPresented: $confirmCancel, titleVisibility: .visible) {
                    Button("Delete workout and its sets", role: .destructive) { cancel() }
                    Button("Keep going", role: .cancel) {}
                } message: {
                    Text("The sets you logged won't count toward your progress. To keep them, tap Finish instead.")
                }
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack(spacing: 12) {
                    if tracker.isStartingOnWatch {
                        Label("Starting on Watch…", systemImage: "applewatch")
                    } else if tracker.isMirrored {
                        Image(systemName: "applewatch").foregroundStyle(Theme.accent)
                            .accessibilityLabel("Shared with Apple Watch")
                    }
                    Text(elapsed).monospacedDigit()
                    Label("\(Int(tracker.heartRate))", systemImage: "heart.fill")
                        .foregroundStyle(tracker.heartRate > 0 ? Theme.text : Theme.muted)
                    if !exercises.isEmpty { Text("\(exerciseIndex + 1) OF \(exercises.count)") }
                }
                .font(Theme.mono(13)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("Finish") { finish() }
                .font(.system(size: 15, weight: .semibold))
        }
    }

    private func setStrip(_ ex: PlannedExercise) -> some View {
        let done = working(logged(ex.name), ex)
        return HStack(spacing: 6) {
            ForEach(1...max(ex.sets, done + 1), id: \.self) { n in
                Text(n <= done ? "DONE" : (n == done + 1 ? "NOW" : "SET \(n)"))
                    .font(.system(size: 11, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .foregroundStyle(n == done + 1 ? Theme.onAccent : Theme.muted)
                    .background(n == done + 1 ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private func loggedList(_ ex: PlannedExercise) -> some View {
        let sets = logged(ex.name)
        if !sets.isEmpty {
            SectionLabel("Logged · tap to fix")
            ForEach(Array(sets.enumerated()), id: \.element.persistentModelID) { i, s in
                Button { sheet = .edit(s) } label: {
                    HStack {
                        Text("Set \(i + 1)").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text("\(unit.format(pounds: s.weight)) × \(s.reps)\(timed ? " s" : "")\(s.rpe.map { " · RPE \($0)" } ?? "")")
                            .font(Theme.mono(13)).foregroundStyle(Theme.muted)
                        Image(systemName: "pencil").foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func valueLabel(_ value: String, _ unitText: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value).font(Theme.mono(44)).monospacedDigit()
            Text(unitText).font(Theme.label).foregroundStyle(Theme.muted)
        }
    }

    private var elapsed: String {
        guard let start = tracker.startDate else { return "0:00" }
        let s = Int(Date().timeIntervalSince(start))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var nextUp: String {
        guard let current else { return "Next set" }
        if setNumber <= current.sets { return "\(current.name) · set \(setNumber) of \(current.sets)" }
        if exercises.indices.contains(exerciseIndex + 1) { return "Next: \(exercises[exerciseIndex + 1].name)" }
        return "Last one done — finish your workout"
    }

    // MARK: Actions

    private func logSet(_ ex: PlannedExercise, _ plan: PlannedWorkout) {
        let entry = SetLogger.log(exercise: ex.name, weight: unit.toPounds(weight), reps: reps, rpe: rpe,
                                  focus: plan.focus, gymName: plan.gymName, setStarted: setStarted, in: ctx)
        // @Query may or may not have refreshed yet: take earlier sets without the new one, then add it.
        let sets = logged(ex.name).filter { $0 !== entry } + [entry]
        advance(after: ex, doneCount: working(sets, ex), plan)
        if ex.calibrate == true { prefillCalibration(ex, sets) }
    }

    /// A set logged on the Watch (already saved by the tracker): move on as if it was logged here.
    private func loggedOnWatch(_ set: LoggedSet) {
        if let plan, !plan.exercises.contains(where: { $0.name == set.exercise }),
           let catalog = ExerciseCatalog.named(set.exercise) {
            // Added on the Watch: add it here too, so both show the same workout.
            coach.replaceTodayExercises(plan.exercises + [coach.adding(catalog, ctx)], ctx)
        }
        guard let plan, let ex = exercises.first(where: { $0.name == set.exercise }) else { return }
        let name = set.exercise
        let start = Calendar.current.startOfDay(for: .now)
        let sets = (try? ctx.fetch(FetchDescriptor<SetEntry>(
            predicate: #Predicate { $0.exercise == name && $0.date >= start }, sortBy: [SortDescriptor(\.date)]))) ?? []
        let count = working(sets, ex)
        if let i = exercises.firstIndex(of: ex), i != exerciseIndex { exerciseIndex = i; prefill() }
        // The Watch finishes on its own after its last set; its result files the workout here.
        advance(after: ex, doneCount: count, plan, finishWhenDone: false)
    }

    private func advance(after ex: PlannedExercise, doneCount: Int, _ plan: PlannedWorkout, finishWhenDone: Bool = true) {
        let upNext = "\(ex.name) · set \(doneCount + 1) of \(ex.sets)"
        if doneCount >= ex.sets {
            if exerciseIndex + 1 < exercises.count {
                exerciseIndex += 1
                prefill()
            } else if plan.isCustom {
                // Your own workout ends when you say: rest, then add another lift or tap Finish.
            } else {
                guard finishWhenDone else { return }
                if plan.coolDown.isEmpty { finish() } else { withAnimation { phase = .coolDown } }
                return
            }
        }
        let until = Date().addingTimeInterval(TimeInterval(plan.restSeconds))
        restUntil = until
        scheduleRestAlert(at: until, next: doneCount < ex.sets ? upNext : nextUp)
    }

    /// Throws the workout away: the Health workout and the sets logged in it.
    private func cancel() {
        tracker.discard()
        SetLogger.discardOpenSessions(in: ctx)
        RestAlerts.cancel()
        coach.restoreCoachPlan(ctx)
        dismiss()
    }

    private func finish() {
        Task { finished = await coach.finishWorkout(ctx) }
    }

    /// Up to two warm-up steps before each lift, five minutes in all.
    private var warmUpSteps: [String: [WarmUps.Step]] {
        plan.map { WarmUps.beforeEachLift($0, unit: unit) } ?? [:]
    }

    /// Shown above the first set of a lift until you log it. Ticking is optional: logging the
    /// first working set moves on either way.
    private func warmUpCard(_ ex: PlannedExercise, _ steps: [WarmUps.Step]) -> some View {
        let seconds = steps.reduce(0) { $0 + $1.seconds }
        return VStack(alignment: .leading, spacing: 6) {
            Text("WARM UP FIRST · ABOUT \(max(1, Int((Double(seconds) / 60).rounded()))) MIN")
                .font(Theme.mono(11)).foregroundStyle(Theme.accentText)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                let key = "\(ex.name)#\(i)"
                let done = warmedUp.contains(key)
                HStack(spacing: 10) {
                    Button {
                        if done {
                            warmedUp.remove(key)
                        } else {
                            warmedUp.insert(key)
                            // A short rest after each warm-up set, longer as they get heavier.
                            if case .ramp(let r) = step { restAfterWarmUp(r.rest, next: ex) }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(done ? Theme.accent : Theme.muted)
                            switch step {
                            case .drill(let d):
                                Text(d.name).font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Text(d.reps).font(Theme.mono(13)).foregroundStyle(Theme.muted)
                            case .ramp(let r):
                                Text("\(unit.format(pounds: r.weight)) × \(r.reps)").font(Theme.mono(15))
                                Text("warm-up set").font(.system(size: 12)).foregroundStyle(Theme.muted)
                                Spacer()
                                Text("rest \(Dose.label(r.rest))").font(Theme.mono(12)).foregroundStyle(Theme.muted)
                            }
                        }
                        .strikethrough(done, color: Theme.muted)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if case .drill(let d) = step {
                        Button { sheet = .guide(d.name) } label: { Image(systemName: "info.circle").foregroundStyle(Theme.muted) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("How to do \(d.name)")
                    }
                }
                .frame(minHeight: 36)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline))
    }

    /// Test sets: the suggested next weight at the test reps. Once found: the working weight.
    private func prefillCalibration(_ ex: PlannedExercise, _ sets: [SetEntry]) {
        guard let catalog = ExerciseCatalog.named(ex.name) else { return }
        if let result = calibration(ex, sets) {
            weight = unit.roundToStep(unit.fromPounds(result.working.weight))
            reps = result.working.reps
            rpe = 8
        } else if let last = sets.last, let next = Calibration.nextWeight(after: last.weight, rpe: last.rpe ?? 7, unit: unit) {
            weight = unit.roundToStep(unit.fromPounds(next))
            reps = Calibration.testReps(for: catalog)
            rpe = 7
        } else if sets.isEmpty {
            // An empty bar is a safe first test; otherwise you pick something light.
            weight = catalog.equipment.contains(.barbell) ? (unit == .lb ? 45 : 20) : 0
            reps = Calibration.testReps(for: catalog)
            rpe = 7
        }
    }

    private func restAfterWarmUp(_ seconds: Int, next ex: PlannedExercise) {
        let until = Date().addingTimeInterval(TimeInterval(seconds))
        restUntil = until
        scheduleRestAlert(at: until, next: "\(ex.name) warm-up")
        tracker.shareRest(until: until)
    }

    private func extendRest() {
        guard let restUntil else { return }
        let later = restUntil.addingTimeInterval(30)
        self.restUntil = later
        scheduleRestAlert(at: later, next: nextUp)
        tracker.shareRest(until: later)
    }

    /// In a shared workout the Watch buzzes when rest ends; a phone alert would buzz the wrist twice.
    private func scheduleRestAlert(at date: Date, next: String) {
        if !tracker.isMirrored { RestAlerts.schedule(at: date, next: next) }
    }

    private func endRest(share: Bool = true) {
        if share, restUntil.map({ $0 > .now }) == true { tracker.shareRest(until: nil) }   // skipped early
        restUntil = nil
        setStarted = .now
        restBuzz += 1
        RestAlerts.cancel()
    }

    private func next() {
        if exerciseIndex + 1 < exercises.count {
            exerciseIndex += 1
            restUntil = nil
            RestAlerts.cancel()
            prefill()
        }
    }

    private func swap(to replacement: Exercise) {
        guard var list = plan?.exercises, list.indices.contains(exerciseIndex) else { return }
        let old = list[exerciseIndex]
        list[exerciseIndex] = PlannedExercise(name: replacement.name, sets: old.sets, reps: replacement.reps,
                                              cue: old.cue, replaces: old.name,
                                              target: coach.target(for: replacement.name, ctx))
        coach.replaceTodayExercises(list, ctx)
        prefill()
    }

    private func add(_ exercise: Exercise) {
        guard var list = plan?.exercises else { return }
        let at = list.isEmpty ? 0 : min(exerciseIndex + 1, list.count)
        list.insert(coach.adding(exercise, ctx), at: at)
        // Done with the lift you're on (or nothing yet): the new one is up next.
        let finishedCurrent = current.map { working(logged($0.name), $0) >= $0.sets } ?? true
        coach.replaceTodayExercises(list, ctx)
        if finishedCurrent {
            exerciseIndex = at
            prefill()
        }
    }

    // MARK: Your own workout

    /// Before the first lift: pick one to start.
    private func emptyWorkout(_ plan: PlannedWorkout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(plan)
                Text("YOUR WORKOUT").font(Theme.display(40))
                Text("Add lifts as you go. Weights come from your history, with warm-up sets before heavy lifts, and lifts you've never logged start with a light test set.")
                    .font(.system(size: 14)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add your first exercise") { sheet = .add }
                    .buttonStyle(AccentButtonStyle())
            }
            .padding(20)
        }
    }

    /// The last lift's sets are done in your own workout.
    private var allDoneCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SETS DONE").font(Theme.mono(11)).foregroundStyle(Theme.accentText)
            Text("Add another exercise, keep doing sets of this one, or finish.")
                .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Add exercise") { sheet = .add }
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(Capsule().stroke(Theme.hairline))
                Button("Finish") { finish() }
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.text, in: Capsule())
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline))
    }

    /// Start from the coach's target, else what you lifted last time.
    private func prefill() {
        guard let current else { return }
        if current.calibrate == true {
            prefillCalibration(current, logged(current.name))
            return
        }
        if let t = current.target {
            weight = unit.roundToStep(unit.fromPounds(t.weight))
            reps = t.reps
            return
        }
        if let last = DataStore.history(of: current.name, in: ctx).last {
            weight = unit.roundToStep(unit.fromPounds(last.weight))
            reps = last.reps
        } else {
            weight = 0
            reps = RepRange.parse(current.reps).lowerBound
        }
    }
}

// MARK: - Rest

struct RestPanel: View {
    let until: Date
    let cue: String?
    let done: () -> Void
    let extend: () -> Void

    var body: some View {
        Card {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = max(0, Int(until.timeIntervalSince(context.date)))
                VStack(spacing: 14) {
                    SectionLabel("Rest")
                    Text(String(format: "%d:%02d", left / 60, left % 60)).font(Theme.mono(72)).monospacedDigit()
                    if let cue { NoteChip(text: cue) }
                    HStack {
                        Button("+30 s", action: extend)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .overlay(Capsule().stroke(Theme.hairline))
                        Button("Next set", action: done)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Theme.text, in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                .onChange(of: left == 0) { _, isZero in if isZero { done() } }
            }
        }
    }
}

// MARK: - Sheets

struct SwapSheet: View {
    let current: PlannedExercise
    let pool: [Exercise]
    let onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss

    init(current: PlannedExercise, pool: [Exercise], onPick: @escaping (Exercise) -> Void) {
        self.current = current
        self.pool = pool
        self.onPick = onPick
    }

    var body: some View {
        let muscle = ExerciseCatalog.named(current.name)?.primary
        let options = pool.filter { $0.primary == muscle && $0.name != current.name }
        NavigationStack {
            List {
                Section {
                    if options.isEmpty {
                        Text("Nothing else here works this muscle with your gym and notes.").foregroundStyle(Theme.muted)
                    }
                    ForEach(options, id: \.name) { ex in
                        Button { onPick(ex); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.name).font(.system(size: 16, weight: .semibold))
                                Text(ex.equipment.isEmpty ? "Bodyweight" : ex.equipment.map(\.label).sorted().joined(separator: ", "))
                                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                } header: {
                    Text("Same muscle · fits your gym and notes")
                }
            }
            .navigationTitle("Swap \(current.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct AddExerciseSheet: View {
    let pool: [Exercise]
    let existing: Set<String>
    let onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    init(pool: [Exercise], existing: Set<String>, onPick: @escaping (Exercise) -> Void) {
        self.pool = pool
        self.existing = existing
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(MuscleGroup.allCases, id: \.self) { m in
                    let items = pool.filter {
                        $0.primary == m && !existing.contains($0.name)
                            && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
                    }
                    if !items.isEmpty {
                        Section(m.label) {
                            ForEach(items, id: \.name) { ex in
                                Button(ex.name) { onPick(ex); dismiss() }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() } }
        }
    }
}

struct EditSetSheet: View {
    @Bindable var entry: SetEntry
    let unit: WeightUnit
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var weight: Double = 0

    init(entry: SetEntry, unit: WeightUnit) {
        self.entry = entry
        self.unit = unit
    }

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Weight: \(weight.formatted(.number.precision(.fractionLength(0...1)))) \(unit.rawValue)",
                        value: $weight, in: 0...1000, step: unit.step)
                Stepper("Reps: \(entry.reps)", value: $entry.reps, in: 0...50)
                Picker("RPE", selection: Binding(get: { entry.rpe ?? 8 }, set: { entry.rpe = $0 })) {
                    ForEach(6...10, id: \.self) { Text("\($0)").tag($0) }
                }
                Section {
                    Button("Delete set", role: .destructive) {
                        ctx.delete(entry)
                        try? ctx.save()
                        dismiss()
                    }
                }
            }
            .navigationTitle(entry.exercise)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") {
                    entry.weight = unit.toPounds(weight)
                    try? ctx.save()
                    dismiss()
                }
            }
            .onAppear { weight = unit.roundToStep(unit.fromPounds(entry.weight)) }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Find your weight

/// The test-set guide on a lift you haven't done before, then what the test found.
struct CalibrationCard: View {
    let exercise: PlannedExercise
    let tests: [SetEntry]
    let result: Calibration.Result?
    let goal: TrainingGoal
    let unit: WeightUnit

    private var testReps: Int { ExerciseCatalog.named(exercise.name).map(Calibration.testReps) ?? 5 }

    var body: some View {
        Card {
            if let result {
                SectionLabel("First Heat · done")
                Text("\(unit.format(pounds: result.tested.weight)) × \(result.tested.reps) felt like an RPE \(result.tested.rpe ?? 8), so your estimated max is about \(unit.format(pounds: result.estimatedMax)).")
                    .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                Label("Working sets: \(unit.format(pounds: result.working.weight)) × \(exercise.reps) reps",
                      systemImage: "scope")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accentText)
                Text(RepScheme.summary(for: goal)).font(.system(size: 12)).foregroundStyle(Theme.muted)
            } else {
                SectionLabel("First Heat · set \(tests.count + 1)")
                Text(tests.isEmpty
                     ? "First time on this lift. Do \(testReps) reps with a weight you're sure about, then rate how hard it was. We'll suggest the next weight until a set feels like an 8: two reps left in the tank."
                     : "Do \(testReps) reps at the suggested weight. Rate it honestly. An 8 means you could have done two more.")
                    .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                if !tests.isEmpty {
                    Text(tests.map { "\(unit.format(pounds: $0.weight)) × \($0.reps) @ \($0.rpe ?? 0)" }.joined(separator: "  ·  "))
                        .font(Theme.mono(12)).foregroundStyle(Theme.muted)
                }
            }
        }
    }
}
