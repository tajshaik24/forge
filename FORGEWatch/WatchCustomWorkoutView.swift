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
                    start(picked.prefix(2).map(\.label).joined(separator: " + ") + (picked.count > 2 ? " +" : ""), picked)
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
        let gym = DataStore.activeGym(in: ctx)
        let notes = (try? ctx.fetch(FetchDescriptor<CoachNote>())) ?? []
        let pool = ExerciseCatalog.available(gym: gym?.equipment ?? Set(Equipment.allCases),
                                             avoiding: notes.reduce(into: []) { $0.formUnion($1.avoid) },
                                             excluding: notes.reduce(into: []) { $0.formUnion($1.exercises) })
        let goal = TrainingGoal(rawValue: SyncedSettings.goal) ?? .buildMuscle
        let perMuscle = max(1, min(3, 6 / max(muscles.count, 1)))
        var exercises: [PlannedExercise] = []
        for m in muscles {
            let options = pool.filter { $0.primary == m }.sorted { $0.isCompound && !$1.isCompound }
            for ex in options.prefix(perMuscle) where !exercises.contains(where: { $0.name == ex.name }) {
                exercises.append(PlannedExercise(
                    name: ex.name, sets: 3, reps: RepScheme.reps(for: ex, goal: goal),
                    target: Progression.target(for: ex, history: DataStore.history(of: ex.name, in: ctx),
                                               unit: SyncedSettings.unit, goal: goal)))
            }
        }
        return PlannedWorkout(date: Calendar.current.startOfDay(for: .now), focus: focus, muscles: muscles,
                              minutes: exercises.count * 8, reasons: ["Custom workout."], exercises: exercises,
                              restSeconds: RepScheme.rest(for: goal), gymName: gym?.name ?? "Gym", engine: "Custom")
    }
}
