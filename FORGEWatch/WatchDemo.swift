#if DEBUG
import SwiftUI
import SwiftData

/// Debug-only: launch with `-demo` for an in-memory store with a planned week and some history
/// (nothing touches iCloud or Health), and `-screen <name>` to open one state of the workout directly,
/// for simulator screenshots:
///
///     xcrun simctl launch <watch sim> com.taj.forge.watchkitapp -demo -screen log
///
/// Screens: home, log, rest, effort, warmup, test, list, controls, summary, alldone.
enum WatchDemo {
    static var isOn: Bool { DataStore.isDemo }

    static var screen: String {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screen"), args.indices.contains(i + 1) else { return "home" }
        return args[i + 1]
    }

    static let steps = 6_240

    struct Root: View {
        @Environment(\.modelContext) private var ctx
        @State private var state: (model: WatchWorkout, page: WatchWorkoutView.Page)?
        @State private var seeded = false

        var body: some View {
            NavigationStack {
                if !seeded {
                    ProgressView()
                } else if let state {
                    WatchWorkoutView(model: state.model, page: state.page)
                } else {
                    WatchPlanView()
                }
            }
            .task {
                guard !seeded else { return }
                WatchDemo.seed(ctx)
                state = WatchDemo.workout(for: WatchDemo.screen, in: ctx)
                seeded = true
            }
        }
    }

    // MARK: Sample data

    private static let bench = "Barbell bench press"
    private static let press = "Standing barbell overhead press"
    private static let incline = "Incline dumbbell press"
    private static let raise = "Cable lateral raise"
    private static let pushdown = "Cable triceps pushdown"

    @MainActor
    static func todayPlan() -> PlannedWorkout {
        var ohp = PlannedExercise(name: press, sets: 3, reps: "6-10")
        ohp.calibrate = true
        let lifts = [
            PlannedExercise(name: bench, sets: 3, reps: "6-10", target: LoadTarget(weight: 135, reps: 8, note: "")),
            ohp,
            PlannedExercise(name: incline, sets: 3, reps: "8-12", target: LoadTarget(weight: 45, reps: 10, note: "")),
            PlannedExercise(name: raise, sets: 3, reps: "10-15", target: LoadTarget(weight: 15, reps: 12, note: "")),
            PlannedExercise(name: pushdown, sets: 2, reps: "10-15", target: LoadTarget(weight: 40, reps: 12, note: "")),
        ]
        let warm = ["Arm circles", "Band pass-through"].compactMap(ExerciseCatalog.named)
            .map { PlannedExercise(name: $0.name, sets: 1, reps: $0.reps) }
        return PlannedWorkout(date: Calendar.current.startOfDay(for: .now), focus: "Push",
                              muscles: [.chest, .shoulders, .triceps], minutes: 45, reasons: [], exercises: lifts,
                              restSeconds: 90, gymName: "Downtown gym", engine: "demo", warmUp: warm)
    }

    /// Today's push day, then the week: pull, rest, legs, nothing planned, upper, rest.
    @MainActor
    static func seed(_ ctx: ModelContext) {
        Seed.ifNeeded(ctx)
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        DataStore.save(todayPlan(), in: ctx)
        let week: [(Int, String, [(String, Int, String, Double)])] = [
            (1, "Pull", [("Barbell row", 3, "6-10", 115), ("Lat pulldown", 3, "8-12", 110),
                         ("Cable face pull", 3, "10-15", 35), ("Dumbbell curl", 3, "10-15", 25)]),
            (2, "Rest", []),
            (3, "Legs", [("Back squat", 3, "6-10", 185), ("Barbell Romanian deadlift", 3, "6-10", 155),
                         ("Leg press", 3, "8-12", 250), ("Seated leg curl", 2, "10-15", 80), ("Standing calf raise", 3, "10-15", 90)]),
            (5, "Upper", [("Incline dumbbell press", 3, "8-12", 50), ("Barbell row", 3, "6-10", 120),
                          ("Dumbbell shoulder press", 3, "8-12", 35), ("Lat pulldown", 3, "8-12", 115)]),
            (6, "Rest", []),
        ]
        for (offset, focus, lifts) in week {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let plan = lifts.isEmpty
                ? PlannedWorkout.rest(on: day, gymName: "Downtown gym", engine: "demo")
                : PlannedWorkout(date: day, focus: focus, muscles: [], minutes: 40 + lifts.count * 2, reasons: [],
                                 exercises: lifts.map { PlannedExercise(name: $0.0, sets: $0.1, reps: $0.2,
                                                                        target: LoadTarget(weight: $0.3, reps: 8, note: "")) },
                                 restSeconds: 90, gymName: "Downtown gym", engine: "demo")
            DataStore.save(plan, in: ctx)
        }
        // A few past push days, for weights from history.
        for back in [3, 7, 10] {
            guard let day = cal.date(byAdding: .day, value: -back, to: today),
                  let begin = cal.date(bySettingHour: 18, minute: 0, second: 0, of: day) else { continue }
            let session = WorkoutSession(date: begin, focus: "Push", gymName: "Downtown gym")
            ctx.insert(session)
            var t = begin
            for (name, weight) in [(bench, 130.0), (incline, 45), (raise, 15), (pushdown, 40)] {
                for _ in 0..<3 {
                    t = t.addingTimeInterval(150)
                    let entry = SetEntry(exercise: name, weight: weight, reps: 8, rpe: 8, date: t)
                    entry.session = session
                    ctx.insert(entry)
                }
            }
            session.endDate = t
        }
        try? ctx.save()
    }

    // MARK: Workout states

    @MainActor
    static func workout(for screen: String, in ctx: ModelContext) -> (WatchWorkout, WatchWorkoutView.Page)? {
        let start = Date().addingTimeInterval(-23 * 60 - 17)
        let model = WatchWorkout(plan: todayPlan())
        model.demoStart = start
        model.demoHeartRate = 128
        model.demoCalories = 186
        var minute = 2.0
        func set(_ name: String, _ weight: Double, _ reps: Int, _ effort: Effort = .good) -> WorkoutProgress.DoneSet {
            minute += 2.5
            return .init(exercise: name, weight: weight, reps: reps, rpe: effort.rpe, date: start.addingTimeInterval(minute * 60))
        }
        let benchDone = [set(bench, 135, 8), set(bench, 135, 8), set(bench, 135, 7, .hard)]
        let pressTests = [set(press, 45, 5, .easy), set(press, 65, 5, .good)]

        switch screen {
        case "log", "controls":
            model.demo(sets: [set(bench, 135, 8, .easy)], at: 0, in: ctx)
            return (model, screen == "log" ? .log : .controls)
        case "rest":
            model.demo(sets: [set(bench, 135, 8, .easy)], at: 0, in: ctx)
            model.startRest(90)
            return (model, .log)
        case "effort":
            model.demo(sets: [set(bench, 135, 8)], at: 0, in: ctx)
            model.demoPending(.init(exercise: bench, weight: 135, reps: 8, start: .now.addingTimeInterval(-40),
                                    end: .now, isTest: false))
            return (model, .log)
        case "warmup":
            model.demo(sets: [], at: 0, in: ctx)
            WorkoutTracker.shared.setWarmUp(WorkoutTracker.warmUpKey(bench, 0), done: true)
            return (model, .log)
        case "test":
            model.demo(sets: benchDone + [set(press, 45, 5, .easy)], at: 1, in: ctx)
            return (model, .log)
        case "list":
            model.demo(sets: benchDone + pressTests + [set(press, 75, 8)], at: 1, in: ctx)
            return (model, .list)
        case "summary", "alldone":
            let all = benchDone + pressTests
                + [set(press, 75, 8), set(press, 75, 8), set(press, 75, 7)]
                + [set(incline, 45, 10), set(incline, 45, 10), set(incline, 50, 9)]
                + [set(raise, 15, 12), set(raise, 15, 12), set(raise, 15, 12)]
                + [set(pushdown, 40, 12), set(pushdown, 40, 12)]
            model.demo(sets: all, at: 4, in: ctx)
            if screen == "summary" {
                model.demoSummary(.init(start: start, end: start.addingTimeInterval(48 * 60), sets: all, calories: 312,
                                        averageHeartRate: 121, maxHeartRate: 158))
            }
            return (model, .log)
        default:
            return nil
        }
    }
}
#endif
