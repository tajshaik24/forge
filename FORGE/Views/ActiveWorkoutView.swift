import SwiftUI
import SwiftData

/// The workout: one scrolling page of exercise cards under a pinned header. The lift you're on is
/// open, finished ones fold to a line, and the plan decides when a lift is done.
struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(CoachStore.self) private var coach
    @Environment(\.hinge) private var hinge
    @Query private var notes: [CoachNote]
    @State private var model = WorkoutModel()
    private let tracker = WorkoutTracker.shared

    #if DEBUG
    /// Debug screenshots: puts the workout in a state once it has loaded (see WorkoutScreens).
    private var demo: ((WorkoutModel) -> Void)?
    init(demo: ((WorkoutModel) -> Void)? = nil) { self.demo = demo }
    #else
    init() {}
    #endif

    var body: some View {
        Group {
            if let finished = model.finished {
                SummaryView(session: finished) { dismiss() }
            } else if model.coolingDown, let plan = coach.plan {
                DrillsView(mode: .coolDown, drills: plan.coolDown, onSkip: { model.coolingDown = false }) {
                    model.coolingDown = false
                    model.confirmFinish = true
                }
            } else if let plan = coach.plan {
                switch hinge {
                case .open:
                    // iPhone Duo opened flat: the form guide for the lift you're on fills the other side.
                    FoldSplit {
                        page(plan)
                    } second: {
                        if let i = model.focus, plan.exercises.indices.contains(i) {
                            NavigationStack { ExerciseDetailView(name: plan.exercises[i].name, planned: plan.exercises[i]) }
                                .id(plan.exercises[i].name)
                        } else {
                            Theme.ground
                        }
                    } single: {
                        page(plan)
                    }
                default:
                    page(plan)
                }
            } else {
                ProgressView()
            }
        }
        .background(Theme.ground)
        .task {
            model.configure(ctx: ctx, coach: coach)
            #if DEBUG
            if let demo { demo(model); return }
            #endif
            if !DataStore.isDemo {
                await RestAlerts.requestPermission()
                await tracker.start(focus: coach.plan?.focus ?? "Workout")
            }
            SetCoach.shared.prewarm()
        }
        // Rest ends on time even if the countdown hit zero while the app was in the background.
        .task(id: model.restUntil) {
            guard let until = model.restUntil else { return }
            do {
                try await Task.sleep(until: .now + .seconds(max(0, until.timeIntervalSinceNow)), clock: .continuous)
            } catch { return }
            if model.restUntil == until { model.endRest() }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active, let until = model.restUntil, until <= .now { model.endRest() }
        }
        .sheet(item: $model.sheet, onDismiss: { model.reload() }) { sheet(for: $0) }
        .sensoryFeedback(.success, trigger: model.restBuzz)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.logBuzz)
        .sensoryFeedback(.success, trigger: model.recordBuzz)
        .onChange(of: tracker.remoteSets.count) { model.receiveRemoteSets() }
        .onChange(of: tracker.remoteRest) {
            if let change = tracker.remoteRest { model.remoteRest(until: change.until) }
        }
        .onChange(of: coach.lastFinished) {
            if let done = coach.lastFinished, model.finished == nil, done.endDate != nil { model.finished = done }
        }
        .onChange(of: liveState, initial: true) {
            if let liveState, let plan = coach.plan {
                LiveActivityController.show(liveState, focus: plan.focus, workoutStart: model.startDate)
            } else {
                LiveActivityController.end()
            }
        }
        .onDisappear { LiveActivityController.end() }
        .onReceive(NotificationCenter.default.publisher(for: RestCommand.notification)) { note in
            guard model.isResting else { return }
            switch note.object as? RestCommand {
            case .skip: model.skipRest()
            case .extend: model.extendRest()
            case nil: break
            }
        }
    }

    // MARK: The page

    private func page(_ plan: PlannedWorkout) -> some View {
        let progress = model.progress
        return VStack(spacing: 0) {
            WorkoutHeader(title: plan.focus, start: model.startDate, heartRate: model.heartRate,
                          onWatch: tracker.isMirrored, startingOnWatch: tracker.isStartingOnWatch,
                          progress: progress, finishing: model.isFinishing,
                          onCancel: askCancel, onFinish: { model.confirmFinish = true })
                .confirmationDialog("Cancel this workout?", isPresented: $model.confirmCancel, titleVisibility: .visible) {
                    Button("Delete workout and its sets", role: .destructive) { model.cancel(); dismiss() }
                    Button("Keep going", role: .cancel) {}
                } message: {
                    Text("The sets you logged won't count toward your progress. To keep them, tap Finish instead.")
                }
                .confirmationDialog("Finish workout?", isPresented: $model.confirmFinish, titleVisibility: .visible) {
                    Button(model.setsLogged == 0 ? "End workout" : "Finish and save") { model.finish { dismiss() } }
                    Button("Keep going", role: .cancel) {}
                } message: {
                    Text(finishMessage(progress))
                }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        if plan.exercises.isEmpty { emptyCard }
                        ForEach(Array(progress.lifts.enumerated()), id: \.element.exercise.name) { i, lift in
                            ExerciseCard(model: model, index: i, lift: lift, expanded: model.focus == i,
                                         coachName: coach.engine.displayName)
                                .id(lift.exercise.name)
                        }
                        if progress.isComplete { completeCard(plan, progress) }
                        if !plan.exercises.isEmpty, !progress.isComplete { addExercise }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, model.isResting ? 96 : 32)
                    .animation(.snappy, value: model.focus)
                    .animation(.snappy, value: model.setsLogged)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.focus) {
                    guard let i = model.focus, plan.exercises.indices.contains(i) else { return }
                    withAnimation(.snappy) { proxy.scrollTo(plan.exercises[i].name, anchor: .top) }
                }
                .onAppear {
                    if let i = model.focus, plan.exercises.indices.contains(i), i > 0 {
                        proxy.scrollTo(plan.exercises[i].name, anchor: .top)
                    }
                }
            }
            .overlay(alignment: .top) {
                if let toast = model.toast { RecordToast(text: toast).transition(.move(edge: .top).combined(with: .opacity)) }
            }
            .overlay(alignment: .bottom) {
                if let until = model.restUntil {
                    RestBar(until: until, next: model.restNext, extend: model.extendRest, skip: model.skipRest)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.restUntil == nil)
        }
    }

    private func finishMessage(_ progress: WorkoutProgress) -> String {
        if model.setsLogged == 0 { return "Nothing's logged yet, so there's nothing to save." }
        let sets = "\(model.setsLogged) set\(model.setsLogged == 1 ? "" : "s") logged"
        if progress.isComplete || progress.setsPlanned == 0 { return "\(sets). It'll be saved to your history." }
        return "\(sets): \(progress.setsDone) of the \(progress.setsPlanned) planned. It'll be saved to your history."
    }

    private func askCancel() {
        if SetLogger.openSessions(in: ctx).contains(where: { !($0.sets ?? []).isEmpty }) {
            model.confirmCancel = true
        } else {
            model.cancel()
            dismiss()
        }
    }

    // MARK: Cards around the lifts

    /// Your own workout before the first lift.
    private var emptyCard: some View {
        Card {
            Text("YOUR WORKOUT").font(Theme.display(28)).foregroundStyle(Theme.text)
            Text("Add lifts as you go. Weights come from your history, with warm-up sets before heavy lifts. A lift you've never logged starts with a few light test sets to find your weight.")
                .font(.system(size: 14)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add your first exercise") { model.sheet = .add }
                .buttonStyle(AccentButtonStyle())
                .padding(.top, 4)
        }
    }

    private func completeCard(_ plan: PlannedWorkout, _ progress: WorkoutProgress) -> some View {
        let minutes = max(1, Int(Date().timeIntervalSince(model.startDate) / 60))
        return Card {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 24)).foregroundStyle(Theme.accent)
                Text("WORKOUT COMPLETE").font(Theme.display(20)).foregroundStyle(Theme.text)
            }
            Text("\(model.setsLogged) sets in \(minutes) min. Finish to save it, or keep going.")
                .font(.system(size: 14)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button("Finish") { model.confirmFinish = true }
                .buttonStyle(AccentButtonStyle())
                .disabled(model.isFinishing)
            HStack(spacing: 8) {
                Button { model.sheet = .add } label: { Label("Add exercise", systemImage: "plus") }
                if !plan.coolDown.isEmpty {
                    Button { model.coolingDown = true } label: { Label("Cool-down", systemImage: "figure.cooldown") }
                }
            }
            .buttonStyle(RaisedButtonStyle())
        }
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.accent.opacity(0.55), lineWidth: 1.5))
    }

    private var addExercise: some View {
        Button { model.sheet = .add } label: {
            Label("Add exercise", systemImage: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accentText)
                .frame(maxWidth: .infinity, minHeight: 52)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheet(for sheet: WorkoutModel.Sheet) -> some View {
        switch sheet {
        case .howTo(let ex):
            closable { ExerciseDetailView(name: ex.name, planned: ex) }
        case .guide(let name):
            closable { ExerciseDetailView(name: name) }
        case .progress(let name):
            closable { LiftProgressView(name: name) }
        case .swap(let i):
            if let current = coach.plan?.exercises[safe: i] {
                ExercisePickerSheet(title: "Swap exercise", subtitle: "Instead of \(current.name.lowercased())", suggestedTitle: "Suggested · same muscle",
                                    suggested: swapSuggestions(for: current), excluding: inWorkout,
                                    gym: gym, avoiding: avoid, initialSearch: model.pickerSearch) { model.swap(i, to: $0) }
            }
        case .add:
            ExercisePickerSheet(title: "Add exercise", suggestedTitle: "Suggested · fits today",
                                suggested: addSuggestions, excluding: inWorkout,
                                gym: gym, avoiding: avoid) { model.add($0) }
        case .edit(let entry):
            EditSetSheet(entry: entry, unit: model.unit)
        }
    }

    private func closable(@ViewBuilder _ content: () -> some View) -> some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { model.sheet = nil } }
                }
        }
    }

    private var gym: GymProfile? { DataStore.activeGym(in: ctx) }
    private var avoid: Set<MovementFlag> { notes.reduce(into: Set<MovementFlag>()) { $0.formUnion($1.avoid) } }
    private var inWorkout: Set<String> { Set(coach.plan?.exercises.map(\.name) ?? []) }

    /// Exercises this gym and your notes allow.
    private var pool: [Exercise] {
        ExerciseCatalog.available(gym: gym?.equipment ?? Set(Equipment.allCases), avoiding: avoid)
    }

    private func swapSuggestions(for current: PlannedExercise) -> [Exercise] {
        let muscle = ExerciseCatalog.named(current.name)?.primary
        return pool.filter { $0.kind == .strength && $0.primary == muscle }
    }

    /// Today's muscles first; for your own workout with nothing in it yet, the big lifts.
    private var addSuggestions: [Exercise] {
        let muscles = Set(coach.plan?.muscles ?? [])
        let strength = pool.filter { $0.kind == .strength }
        let picks = muscles.isEmpty ? strength.filter(\.isCompound) : strength.filter { muscles.contains($0.primary) }
        return Array(picks.prefix(8))
    }

    // MARK: Live Activity

    /// What the Lock Screen and Dynamic Island show. Nil once the workout is over.
    private var liveState: WorkoutActivityAttributes.ContentState? {
        guard model.finished == nil, !model.coolingDown, coach.plan != nil else { return nil }
        let progress = model.progress
        let bpm = model.heartRate > 0 ? Int(model.heartRate.rounded()) : nil
        let resting = model.restUntil.map { $0 > .now } == true
        let rest = (started: resting ? model.restStarted : nil, until: resting ? model.restUntil : nil)
        guard let i = model.focus ?? progress.current(from: 0), progress.lifts.indices.contains(i) else {
            let empty = progress.lifts.isEmpty
            return .init(exercise: empty ? "Your workout" : "Every lift done",
                         setLabel: empty ? "Getting started" : "Workout complete",
                         detail: empty ? "Add an exercise to begin" : "Finish to save it",
                         heartRate: bpm, restStarted: rest.started, restUntil: rest.until,
                         onWatch: tracker.isMirrored, progress: progress.fraction)
        }
        let lift = progress.lifts[i]
        let d = model.draft(lift)
        let detail = resting ? model.restNext
            : WorkoutText.amount(weight: d.weight, reps: d.reps, timed: model.isTimed(lift.exercise.name), unit: model.unit)
        return .init(exercise: lift.exercise.name, setLabel: model.setLabel(lift), detail: detail,
                     heartRate: bpm, restStarted: rest.started, restUntil: rest.until,
                     onWatch: tracker.isMirrored, progress: progress.fraction)
    }
}

fileprivate extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
