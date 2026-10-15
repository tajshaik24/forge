import Foundation

/// Rep ranges, rest and working weights by goal. The goal sets the rep range;
/// your estimated max sets the weight.
enum RepScheme {
    /// Reps per set for this lift and goal. Bodyweight and timed moves keep the catalog's dose,
    /// since you can't change their load.
    static func range(for exercise: Exercise, goal: TrainingGoal) -> ClosedRange<Int> {
        guard exercise.kind == .strength, !exercise.isTimed, !exercise.equipment.isEmpty else { return exercise.repRange }
        let big = exercise.isCompound
        switch goal {
        case .getStronger: return big ? 3...6 : 6...10
        case .buildMuscle: return big ? 6...10 : 10...15
        // Heavy enough to keep muscle while eating less, shorter rests to keep the pace up.
        case .loseFat: return big ? 5...8 : 10...15
        case .generalFitness: return big ? 8...12 : 12...15
        }
    }

    static func reps(for exercise: Exercise, goal: TrainingGoal) -> String {
        guard exercise.kind == .strength, !exercise.isTimed, !exercise.equipment.isEmpty else { return exercise.reps }
        let r = range(for: exercise, goal: goal)
        return "\(r.lowerBound)-\(r.upperBound)" + (exercise.reps.contains("/") ? "/" + (exercise.reps.split(separator: "/").last ?? "") : "")
    }

    /// Rest between sets, in seconds.
    static func rest(for goal: TrainingGoal) -> Int {
        switch goal {
        case .getStronger: 150
        case .buildMuscle: 90
        case .loseFat: 60
        case .generalFitness: 75
        }
    }

    /// What the goal means in a sentence, for plans and the form page.
    static func summary(for goal: TrainingGoal) -> String {
        switch goal {
        case .getStronger: "Heavy sets of 3–6 on the big lifts, long rests."
        case .buildMuscle: "Moderate weight for 6–10 on big lifts, 10–15 on smaller ones."
        case .loseFat: "Keep the big lifts heavy (5–8) so you keep muscle; short rests."
        case .generalFitness: "Lighter weight for 8–15 reps, steady pace."
        }
    }
}

/// Estimated one-rep max and the weights that follow from it.
enum Strength {
    /// Reps you leave in the tank on working sets: hard, but form stays clean.
    static let workingReserve = 2

    /// Epley, counting the reps left in the tank: 135 × 5 at RPE 8 counts as 7 reps to failure.
    static func estimatedMax(weight: Double, reps: Int, rpe: Int?) -> Double {
        let reserve = rpe.map { max(0, 10 - $0) } ?? workingReserve
        let toFailure = reps + reserve
        return toFailure <= 1 ? weight : weight * (1 + Double(toFailure) / 30)
    }

    /// The best estimate from a set of records (the most recent session that has one).
    static func estimatedMax(from history: [SetRecord]) -> Double? {
        guard let last = Progression.lastSession(history.filter { $0.weight > 0 }) else { return nil }
        return last.map { estimatedMax(weight: $0.weight, reps: $0.reps, rpe: $0.rpe) }.max()
    }

    /// Weight for `reps` with `reserve` left in the tank, rounded down to the unit's step.
    static func weight(forReps reps: Int, max: Double, reserve: Int = workingReserve, unit: WeightUnit) -> Double {
        let raw = max / (1 + Double(reps + reserve) / 30)
        return unit.toPounds((unit.fromPounds(raw) / unit.step).rounded(.down) * unit.step)
    }
}

/// "Find your weight": test sets the first time you do a weighted lift.
enum Calibration {
    /// Big lifts test at 5 reps (a close estimate of your max); smaller ones at 10.
    static func testReps(for exercise: Exercise) -> Int { exercise.isCompound ? 5 : 10 }

    /// A set this hard ends the test.
    static let foundAtRPE = 8

    /// Needs a weight to find: weighted strength moves only.
    static func applies(to exercise: Exercise) -> Bool {
        exercise.kind == .strength && !exercise.isTimed && !exercise.equipment.isEmpty
    }

    /// The next test weight after a set that still felt easy, or nil once it's hard enough.
    static func nextWeight(after weight: Double, rpe: Int, unit: WeightUnit) -> Double? {
        guard rpe < foundAtRPE else { return nil }
        let share = rpe <= 6 ? 0.2 : 0.1
        let minSteps = rpe <= 6 ? 2.0 : 1.0
        let jump = max(unit.fromPounds(weight) * share, unit.step * minSteps)
        let next = ((unit.fromPounds(weight) + jump) / unit.step).rounded(.up) * unit.step
        return unit.toPounds(next)
    }

    /// Where the test landed and what to train with.
    struct Result: Hashable {
        let tested: SetRecord
        let estimatedMax: Double
        let working: LoadTarget
    }

    /// From the test sets logged so far: nil until one reaches RPE 8.
    static func result(for exercise: Exercise, sets: [SetRecord], goal: TrainingGoal, unit: WeightUnit) -> Result? {
        guard let hard = sets.first(where: { ($0.rpe ?? 0) >= foundAtRPE && $0.weight > 0 }) else { return nil }
        let max = Strength.estimatedMax(weight: hard.weight, reps: hard.reps, rpe: hard.rpe)
        let reps = RepScheme.range(for: exercise, goal: goal).lowerBound
        let weight = Strength.weight(forReps: reps, max: max, unit: unit)
        return Result(tested: hard, estimatedMax: max,
                      working: LoadTarget(weight: weight, reps: reps,
                                          note: "From your test: \(unit.format(pounds: hard.weight)) × \(hard.reps)"))
    }
}
