import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(CoachStore.self) private var coach
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

    private let unit = SyncedSettings.unit

    enum Sheet: Identifiable {
        case form, swap, add, edit(SetEntry)
        var id: String {
            switch self {
            case .form: "form"
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
    private var setNumber: Int { (current.map { logged($0.name).count } ?? 0) + 1 }

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
            } else if let current, let plan {
                training(current, plan)
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
            case .swap:
                if let current { SwapSheet(current: current, pool: pool) { swap(to: $0) } }
            case .add:
                AddExerciseSheet(pool: pool, existing: Set(exercises.map(\.name))) { add($0) }
            case .edit(let entry):
                EditSetSheet(entry: entry, unit: unit)
            }
        }
        .sensoryFeedback(.success, trigger: restBuzz)
    }

    private func training(_ ex: PlannedExercise, _ plan: PlannedWorkout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(plan)

                HStack(alignment: .top) {
                    Button { sheet = .form } label: {
                        HStack(spacing: 8) {
                            Text(ex.name.uppercased()).font(Theme.display(38)).multilineTextAlignment(.leading)
                            Text("Form").font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .overlay(Capsule().stroke(Theme.hairline))
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Menu {
                        Button("Swap exercise", systemImage: "arrow.triangle.2.circlepath") { sheet = .swap }
                        Button("Add exercise after this", systemImage: "plus") { sheet = .add }
                        Button("Skip to next", systemImage: "forward") { next() }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 22)).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Exercise options")
                }

                if let target = ex.target {
                    Label(target.weight > 0
                          ? "Target \(unit.format(pounds: target.weight)) × \(target.reps) · \(target.note)"
                          : "Target \(target.reps) reps · \(target.note)",
                          systemImage: "scope")
                        .font(.system(size: 13)).foregroundStyle(Theme.emberSoft)
                } else {
                    Text("First time: pick a weight you could do for \(ex.reps) reps with 2 left in the tank.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                if let cue = ex.cue { NoteChip(text: cue) }

                setStrip(ex)

                if let restUntil {
                    RestPanel(until: restUntil,
                              cue: plan.restSeconds > 90 ? "Breathe out as you press. Sit for 10 s before standing." : nil,
                              done: endRest,
                              extend: {
                                  let later = restUntil.addingTimeInterval(30)
                                  self.restUntil = later
                                  RestAlerts.schedule(at: later, next: nextUp)
                              })
                } else {
                    Stepper(value: $weight, in: 0...1000, step: unit.step) {
                        valueLabel(weight.formatted(.number.precision(.fractionLength(0...1))), unit.label)
                    }
                    Stepper(value: $reps, in: 1...50) { valueLabel("\(reps)", "REPS") }
                    SectionLabel("How hard? (RPE)")
                    Picker("RPE", selection: $rpe) { ForEach(6...10, id: \.self) { Text("\($0)") } }
                        .pickerStyle(.segmented)
                    Text("10 = nothing left · 8 = two reps left").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Button("Log set \(setNumber)") { logSet(ex, plan) }.buttonStyle(EmberButtonStyle())
                }

                loggedList(ex)
            }
            .padding(20)
        }
    }

    private func header(_ plan: PlannedWorkout) -> some View {
        HStack {
            Button { tracker.discard(); RestAlerts.cancel(); dismiss() } label: { Image(systemName: "xmark") }
                .frame(width: 44, height: 44).accessibilityLabel("Cancel workout")
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack(spacing: 12) {
                    Text(elapsed).monospacedDigit()
                    Label("\(Int(tracker.heartRate))", systemImage: "heart.fill")
                        .foregroundStyle(tracker.heartRate > 0 ? Theme.text : Theme.muted)
                    Text("\(exerciseIndex + 1) OF \(exercises.count)")
                }
                .font(Theme.mono(13)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("Finish") { Task { finished = await coach.finishWorkout(ctx) } }
                .font(.system(size: 15, weight: .semibold))
        }
    }

    private func setStrip(_ ex: PlannedExercise) -> some View {
        let done = logged(ex.name).count
        return HStack(spacing: 6) {
            ForEach(1...max(ex.sets, done + 1), id: \.self) { n in
                Text(n <= done ? "DONE" : (n == done + 1 ? "NOW" : "SET \(n)"))
                    .font(.system(size: 11, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .foregroundStyle(n == done + 1 ? Theme.onEmber : Theme.muted)
                    .background(n == done + 1 ? Theme.ember : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
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
                        Text("\(unit.format(pounds: s.weight)) × \(s.reps)\(s.rpe.map { " · RPE \($0)" } ?? "")")
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
        // @Query may or may not have refreshed yet: count earlier sets without the new one, then add it.
        let doneCount = logged(ex.name).filter { $0 !== entry }.count + 1
        let upNext = "\(ex.name) · set \(doneCount + 1) of \(ex.sets)"
        if doneCount >= ex.sets {
            if exerciseIndex + 1 < exercises.count {
                exerciseIndex += 1
                prefill()
            } else {
                Task { finished = await coach.finishWorkout(ctx) }
                return
            }
        }
        let until = Date().addingTimeInterval(TimeInterval(plan.restSeconds))
        restUntil = until
        RestAlerts.schedule(at: until, next: doneCount < ex.sets ? upNext : nextUp)
    }

    private func endRest() {
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
        let item = PlannedExercise(name: exercise.name, sets: 3, reps: exercise.reps,
                                   target: coach.target(for: exercise.name, ctx))
        list.insert(item, at: min(exerciseIndex + 1, list.count))
        coach.replaceTodayExercises(list, ctx)
    }

    /// Start from the coach's target, else what you lifted last time.
    private func prefill() {
        guard let current else { return }
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
                            .foregroundStyle(Theme.onEmber)
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
