#if DEBUG
import SwiftUI
import SwiftData

/// Demo screens for the workout flow (`-screen <name>`). Nil for names it doesn't know.
/// Each one builds a plan, then drives the real workout model into the state to check, so the
/// screenshot shows what the code actually does.
enum WorkoutScreens {
    @MainActor
    static func view(_ name: String) -> AnyView? {
        guard let kind = Kind(rawValue: name) else { return nil }
        return AnyView(DemoWorkout(kind: kind))
    }

    enum Kind: String {
        /// Bench done, overhead press one set in with the effort question showing.
        case workout = "workout"
        case rest = "workout-rest"
        /// Changing the weight of the next set.
        case edit = "workout-edit"
        /// A heavier bench than ever: gold row and toast.
        case record = "workout-pr"
        /// A lift you've never done: one test set in, rating the next.
        case test = "workout-test"
        /// The test found the weight: working sets follow.
        case found = "workout-found"
        case done = "workout-done"
        case finish = "workout-finish"
        case coolDown = "workout-cooldown"
        /// Your own workout before the first lift.
        case empty = "workout-empty"
        /// Your own workout with a bodyweight lift and a hold.
        case custom = "workout-custom"
        case swap = "swap"
        /// Swap at the home gym: most of the library isn't there, and says so.
        case swapHome = "swap-home"
        case add = "add"
    }
}

private struct DemoWorkout: View {
    let kind: WorkoutScreens.Kind
    @Environment(\.modelContext) private var ctx
    @Environment(CoachStore.self) private var coach
    @State private var ready = false

    var body: some View {
        Group {
            if ready {
                ActiveWorkoutView(demo: setUp)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.ground)
            }
        }
        .task {
            // The root seeds the history and plans today first; wait for it, then use our own plan.
            for _ in 0..<100 where coach.plan == nil || coach.isThinking || coach.isPlanningWeek {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if kind == .swapHome {
                let gyms = (try? ctx.fetch(FetchDescriptor<GymProfile>())) ?? []
                gyms.forEach { $0.isActive = $0.name == "Home gym" }
            }
            coach.useDemoPlan(plan, ctx)
            SetLogger.discardOpenSessions(in: ctx)
            ready = true
        }
    }

    private var plan: PlannedWorkout {
        let custom = kind == .empty || kind == .custom
        let names: [String] = switch kind {
        case .empty: []
        case .custom: ["Push-up", "Plank"]
        case .test, .found: ["Pec deck", "Barbell bench press", "Cable lateral raise"]
        default: ["Barbell bench press", "Standing barbell overhead press", "Incline dumbbell press", "Cable lateral raise"]
        }
        let lifts = names.compactMap(ExerciseCatalog.named).map { coach.adding($0, ctx) }
        let drills = ["Easy row", "Band pass-through", "Arm circles"].map { PlannedExercise(name: $0, sets: 1, reps: ExerciseCatalog.named($0)?.reps ?? "30 s") }
        let stretches = ["Doorway chest stretch", "Cross-body shoulder stretch", "Overhead triceps stretch"]
            .map { PlannedExercise(name: $0, sets: 1, reps: ExerciseCatalog.named($0)?.reps ?? "30 s") }
        var plan = PlannedWorkout(date: Calendar.current.startOfDay(for: .now), focus: custom ? PlannedWorkout.ownFocus : "Push",
                                  muscles: custom ? [] : [.chest, .shoulders, .triceps], minutes: 50,
                                  reasons: [], exercises: lifts, restSeconds: 90,
                                  gymName: DataStore.activeGym(in: ctx)?.name ?? "Gym",
                                  engine: custom ? PlannedWorkout.customEngine : coach.engine.displayName,
                                  warmUp: custom ? [] : drills, coolDown: custom ? [] : stretches)
        if custom { plan.retitle(unit: SyncedSettings.unit, warmUps: true) }
        return plan
    }

    /// Logs sets through the model, as taps would.
    private func setUp(_ m: WorkoutModel) {
        m.demoHeartRate = 132
        func sets(_ lift: Int, _ count: Int, effort: Effort = .good) {
            for _ in 0..<count {
                m.logWorking(lift)
                if let last = m.entries.last { m.setEffort(last, effort) }
                m.endRest()
            }
        }
        func weight(_ lift: Int, _ pounds: Double) {
            var d = m.draft(m.progress.lifts[lift])
            d.weight = pounds
            m.setDraft(m.progress.lifts[lift], d)
        }
        switch kind {
        case .workout, .rest, .edit:
            // Warm-up ticked off, bench done, one set of the overhead press.
            for (i, step) in (m.warmUps[m.lifts[0].name] ?? []).enumerated() { m.tickWarmUp(m.lifts[0], i, step); m.endRest() }
            sets(0, 1)
            sets(0, 1, effort: .easy)
            sets(0, 1)
            m.tickWarmUp(m.lifts[1], 0, (m.warmUps[m.lifts[1].name] ?? [])[0])
            m.endRest()
            m.logWorking(1)
            if kind != .rest { m.endRest() }
            if kind == .edit {
                if let last = m.entries.last { m.setEffort(last, .easy) }
                m.editing = .weight(m.lifts[1].name)
            }
        case .record:
            m.toastSeconds = 600
            sets(0, 1)
            weight(0, 175)
            m.logWorking(0)
            m.endRest()
        case .test:
            weight(0, 50)
            m.logTest(0, effort: .easy)
            m.endRest()
            m.ratingTest = m.lifts[0].name
        case .found:
            weight(0, 50)
            m.logTest(0, effort: .easy)
            m.endRest()
            m.logTest(0, effort: .good)
            m.endRest()
        case .done, .finish, .coolDown:
            for i in m.lifts.indices { sets(i, m.lifts[i].sets, effort: i == 2 ? .hard : .good) }
            m.confirmFinish = kind == .finish
            m.coolingDown = kind == .coolDown
        case .empty:
            break
        case .custom:
            sets(0, 1, effort: .easy)
            m.logWorking(0)
            m.endRest()
        case .swap, .swapHome:
            sets(0, 3)
            if kind == .swapHome { m.pickerSearch = "press" }
            m.sheet = .swap(1)
        case .add:
            m.sheet = .add
        }
    }
}
#endif
