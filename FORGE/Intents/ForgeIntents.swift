import AppIntents
import SwiftData

/// "Hey Siri, what's today's workout in FORGE"
struct TodaysWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's Workout"
    static let description = IntentDescription("Hear what your FORGE coach planned for today.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let plan = DataStore.todayPlan(in: DataStore.shared.mainContext)?.plan else {
            return .result(dialog: "Open FORGE once today and your coach will plan your workout.")
        }
        if plan.isRestDay { return .result(dialog: "Today is a rest day.") }
        let first = plan.exercises.prefix(3).map(\.name).joined(separator: ", ")
        return .result(dialog: "\(plan.focus) at \(plan.gymName): \(plan.exercises.count) exercises, about \(plan.minutes) minutes. You start with \(first).")
    }
}

/// "Hey Siri, log a set in FORGE" -> Siri asks for exercise, weight and reps.
struct LogSetIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Set"
    static let description = IntentDescription("Log a set to today's FORGE workout and your live Health workout.")

    @Parameter(title: "Exercise") var exercise: String
    @Parameter(title: "Weight", description: "In your FORGE units (lb or kg)") var weight: Double
    @Parameter(title: "Reps") var reps: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$reps) reps of \(\.$exercise) at \(\.$weight)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = DataStore.shared.mainContext
        let plan = DataStore.todayPlan(in: ctx)?.plan
        // Match what the user said to a catalog name when possible ("leg press" -> "Leg press").
        let name = ExerciseCatalog.all.first { $0.name.localizedCaseInsensitiveContains(exercise) }?.name ?? exercise
        let unit = SyncedSettings.unit
        SetLogger.log(exercise: name, weight: unit.toPounds(weight), reps: reps,
                      focus: plan?.focus ?? "Workout", gymName: plan?.gymName ?? "", in: ctx)
        return .result(dialog: "Logged \(reps) reps of \(name) at \(unit.format(pounds: unit.toPounds(weight))).")
    }
}

struct ForgeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TodaysWorkoutIntent(),
                    phrases: ["What's today's workout in \(.applicationName)",
                              "What am I training in \(.applicationName)"],
                    shortTitle: "Today's Workout", systemImageName: "dumbbell")
        AppShortcut(intent: LogSetIntent(),
                    phrases: ["Log a set in \(.applicationName)",
                              "Log a set with \(.applicationName)"],
                    shortTitle: "Log a Set", systemImageName: "plus.circle")
    }
}
