import SwiftUI
import SwiftData

/// Start a workout the coach didn't plan: a quick focus, or the muscles you pick.
struct WatchCustomWorkoutView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var muscles: Set<MuscleGroup> = []
    /// Called with the workout to run.
    let onStart: (PlannedWorkout) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Button("Start empty") {
                    let goal = TrainingGoal(rawValue: SyncedSettings.goal) ?? .buildMuscle
                    onStart(.own(gymName: DataStore.activeGym(in: ctx)?.name ?? "Gym", restSeconds: RepScheme.rest(for: goal)))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                Text("Add lifts as you go.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                Text("QUICK START").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
                ForEach(FocusTemplate.all, id: \.name) { template in
                    Button(template.name) { start(template.name, template.muscles) }
                }
                Text("OR PICK MUSCLES").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
                    .padding(.top, 6)
                ForEach(MuscleGroup.allCases, id: \.self) { m in
                    Toggle(m.label, isOn: Binding(get: { muscles.contains(m) },
                                                  set: { if $0 { muscles.insert(m) } else { muscles.remove(m) } }))
                }
                Button("Start") {
                    let picked = MuscleGroup.allCases.filter(muscles.contains)
                    start(PlannedWorkout.focus(for: picked), picked)
                }
                .buttonStyle(.borderedProminent)
                .disabled(muscles.isEmpty)
            }
        }
        .navigationTitle("Custom")
    }

    private func start(_ focus: String, _ muscles: [MuscleGroup]) {
        onStart(build(focus: focus, muscles: muscles))
        dismiss()
    }

    /// About six lifts the active gym can do, compound lifts first, spread over the muscles.
    /// Respects your coach notes; weights come from your history.
    private func build(focus: String, muscles: [MuscleGroup]) -> PlannedWorkout {
        let pool = WatchPicks.pool(ctx)
        let perMuscle = max(1, min(3, 6 / max(muscles.count, 1)))
        var exercises: [PlannedExercise] = []
        for m in muscles {
            let options = pool.filter { $0.primary == m }.sorted { $0.isCompound && !$1.isCompound }
            for ex in options.prefix(perMuscle) where !exercises.contains(where: { $0.name == ex.name }) {
                exercises.append(WatchPicks.planned(ex, ctx))
            }
        }
        var plan = PlannedWorkout.own(gymName: DataStore.activeGym(in: ctx)?.name ?? "Gym",
                                      restSeconds: RepScheme.rest(for: WatchPicks.goal))
        plan.exercises = exercises
        plan.reasons = ["Custom workout."]
        plan.retitle(unit: SyncedSettings.unit, warmUps: SyncedSettings.warmUps)
        plan.focus = focus
        return plan
    }
}

/// Lifts you pick on the Watch, outside the coach's plan.
enum WatchPicks {
    static var goal: TrainingGoal { TrainingGoal(rawValue: SyncedSettings.goal) ?? .buildMuscle }

    /// What the active gym and your coach notes allow.
    @MainActor
    static func pool(_ ctx: ModelContext) -> [Exercise] {
        let notes = (try? ctx.fetch(FetchDescriptor<CoachNote>())) ?? []
        return ExerciseCatalog.available(gym: DataStore.activeGym(in: ctx)?.equipment ?? Set(Equipment.allCases),
                                         avoiding: notes.reduce(into: []) { $0.formUnion($1.avoid) },
                                         excluding: notes.reduce(into: []) { $0.formUnion($1.exercises) })
    }

    /// Three sets, with the weight from your history.
    @MainActor
    static func planned(_ ex: Exercise, _ ctx: ModelContext) -> PlannedExercise {
        PlannedExercise(name: ex.name, sets: 3, reps: RepScheme.reps(for: ex, goal: goal),
                        target: Progression.target(for: ex, history: DataStore.history(of: ex.name, in: ctx),
                                                   unit: SyncedSettings.unit, goal: goal))
    }
}

/// Pick a lift to add: by muscle, then exercise.
struct WatchAddExerciseView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let existing: Set<String>
    let onPick: (PlannedExercise) -> Void

    var body: some View {
        let pool = WatchPicks.pool(ctx)
        List {
            ForEach(MuscleGroup.allCases, id: \.self) { m in
                let items = pool.filter { $0.primary == m && !existing.contains($0.name) }
                    .sorted { $0.isCompound && !$1.isCompound }
                if !items.isEmpty {
                    NavigationLink(m.label) {
                        List(items, id: \.name) { ex in
                            Button(ex.name) {
                                onPick(WatchPicks.planned(ex, ctx))
                                dismiss()
                            }
                        }
                        .navigationTitle(m.label)
                    }
                }
            }
        }
        .navigationTitle("Add exercise")
    }
}
