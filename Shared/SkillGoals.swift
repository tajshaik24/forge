import Foundation

/// Building toward a bodyweight lift you can't do yet ("I can't do a pull-up"): a short ladder of
/// easier versions, one rung at a time. Each rung moves up after two sessions where every set
/// reached its rep goal without feeling Hard. The last rung is the lift itself.
///
/// Rules, not the model: which rung you're on and when you move up must be predictable.
struct SkillLadder: Sendable, Hashable {
    struct Step: Sendable, Hashable {
        /// Catalog names, best first; the first one the gym has the kit for is used.
        let options: [String]
        let sets: Int
        /// Every working set must reach this many reps for the session to count.
        let graduateAt: Int
    }

    /// The lift you're working toward, e.g. "Pull-up".
    let target: String
    let steps: [Step]

    /// "a pull-up", for sentences.
    var phrase: String { "a \(target.lowercased())" }

    static let all: [SkillLadder] = [
        SkillLadder(target: "Pull-up", steps: [
            Step(options: ["Inverted row", "Lat pulldown"], sets: 3, graduateAt: 12),
            Step(options: ["Band-assisted pull-up", "Lat pulldown"], sets: 3, graduateAt: 8),
            Step(options: ["Negative pull-up"], sets: 3, graduateAt: 5),
            Step(options: ["Pull-up"], sets: 3, graduateAt: 5),
        ]),
        SkillLadder(target: "Chin-up", steps: [
            Step(options: ["Inverted row", "Lat pulldown"], sets: 3, graduateAt: 12),
            Step(options: ["Band-assisted chin-up", "Lat pulldown"], sets: 3, graduateAt: 8),
            Step(options: ["Negative chin-up"], sets: 3, graduateAt: 5),
            Step(options: ["Chin-up"], sets: 3, graduateAt: 5),
        ]),
        SkillLadder(target: "Push-up", steps: [
            Step(options: ["Incline push-up"], sets: 3, graduateAt: 15),
            Step(options: ["Push-up"], sets: 3, graduateAt: 10),
        ]),
        SkillLadder(target: "Dip", steps: [
            Step(options: ["Bench dip"], sets: 3, graduateAt: 15),
            Step(options: ["Dip"], sets: 3, graduateAt: 8),
        ]),
    ]

    static func named(_ target: String) -> SkillLadder? { all.first { $0.target == target } }

    /// Lifts in a message the athlete says they can't do yet and that have a ladder.
    static func targets(in text: String) -> [String] {
        ExerciseCatalog.limited(in: text).filter { named($0) != nil }
    }
}

/// One goal in progress, saved in synced settings so the iPhone and Watch agree.
struct SkillGoal: Codable, Sendable, Hashable, Identifiable {
    var target: String
    /// Index into the ladder's steps.
    var step: Int = 0
    /// Sessions on this step that met the rep goal.
    var passes: Int = 0
    var started: Date = .now
    /// The last workout already counted, so a session is never counted twice.
    var lastCounted: Date?

    var id: String { target }
    var ladder: SkillLadder? { SkillLadder.named(target) }
    static let passesToMoveUp = 2

    /// The exercise for the current step at a gym, or nil if the gym can't do any option.
    func exercise(gym: Set<Equipment>, avoiding: Set<MovementFlag>) -> Exercise? {
        guard let ladder, ladder.steps.indices.contains(step) else { return nil }
        return ladder.steps[step].options.lazy.compactMap(ExerciseCatalog.named)
            .first { $0.isDoable(with: gym, avoiding: avoiding) }
    }

    /// "Step 2 of 4 toward a pull-up".
    var label: String {
        guard let ladder else { return target }
        return "Step \(step + 1) of \(ladder.steps.count) toward \(ladder.phrase)"
    }

    var isOnTarget: Bool { ladder.map { step == $0.steps.count - 1 } ?? false }

    /// What happened to a goal after a workout.
    enum Outcome: Equatable, Sendable {
        /// Not trained, or already counted.
        case unchanged
        /// Trained; `passes` sessions of `needed` so far on this step.
        case progress(passes: Int, needed: Int)
        /// Moved up a step.
        case movedUp(to: String)
        /// Did the lift itself for the first time, so the ladder skips to the last step.
        case firstRep
        /// Hit the rep goal on the lift itself: done.
        case achieved
    }

    /// Counts one finished workout's sets toward the goal.
    /// - Parameter sets: every set in the workout, any lift. Rep goals use reps only: an assisted
    ///   machine's weight isn't compared.
    mutating func record(_ sets: [WorkoutProgress.DoneSet], on date: Date) -> Outcome {
        guard let ladder, ladder.steps.indices.contains(step), lastCounted.map({ date > $0 }) ?? true else { return .unchanged }
        let current = ladder.steps[step]
        let finalStep = ladder.steps.count - 1

        // Did the real lift before reaching its step: jump to it.
        if step < finalStep, sets.contains(where: { $0.exercise == target && $0.reps >= 1 }) {
            lastCounted = date
            step = finalStep
            passes = 0
            return .firstRep
        }

        let done = sets.filter { current.options.contains($0.exercise) }
        guard !done.isEmpty else { return .unchanged }
        lastCounted = date
        let met = done.count >= current.sets
            && done.allSatisfy { $0.reps >= current.graduateAt && ($0.rpe ?? Effort.good.rpe) < Effort.hard.rpe }
        guard met else { return .progress(passes: passes, needed: Self.passesToMoveUp) }

        passes += 1
        if step == finalStep { return .achieved }
        guard passes >= Self.passesToMoveUp else { return .progress(passes: passes, needed: Self.passesToMoveUp) }
        step += 1
        passes = 0
        return .movedUp(to: ladder.steps[step].options.first ?? target)
    }
}

extension SkillGoal {
    /// Adds the goal's current step to a plan that trains its muscles, first, in place of the lift
    /// and its other easier versions. Returns the reason line to show, or nil when the plan doesn't
    /// train those muscles or the gym can't do the step.
    static func apply(_ goals: [SkillGoal], to exercises: inout [PlannedExercise], muscles: [MuscleGroup],
                      gym: Set<Equipment>, avoiding: Set<MovementFlag>,
                      target: (Exercise) -> LoadTarget?) -> [String] {
        var reasons: [String] = []
        for goal in goals {
            guard let ladder = goal.ladder, let ex = goal.exercise(gym: gym, avoiding: avoiding),
                  let goalLift = ExerciseCatalog.named(goal.target),
                  muscles.contains(goalLift.primary) else { continue }
            // The step stands in for the lift and its other stand-ins. Other back (or chest) work stays:
            // the time fit below drops the last lift if the session runs long.
            let ladderLifts = Set([goal.target] + (ExerciseCatalog.easierVersions[goal.target] ?? []))
            exercises.removeAll { $0.name == ex.name || ladderLifts.contains($0.name) }
            let step = ladder.steps[goal.step]
            var planned = PlannedExercise(name: ex.name, sets: step.sets, reps: ex.reps)
            planned.goal = goal.label
            planned.target = target(ex)
            exercises.insert(planned, at: 0)
            reasons.append("\(goal.label): \(step.sets) sets of \(step.graduateAt) \(ex.name.lowercased())s moves you up.")
        }
        return reasons
    }
}
