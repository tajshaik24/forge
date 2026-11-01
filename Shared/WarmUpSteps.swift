import Foundation

// The warm-up inside a workout, shared by the iPhone and the Watch. Choosing which drills a day
// gets needs the coach (FORGE/Coach/WarmUps.swift); spreading them over the lifts doesn't.

enum WarmUps {
    /// Drills that prepare each movement pattern, best first.
    static let drills: [MovementPattern: [String]] = [
        .squat: ["Bodyweight squat", "Ankle rock", "Hip circle", "Lateral band walk", "Foam roll quads"],
        .lunge: ["World's greatest stretch", "Hip circle", "Ankle rock", "Lateral band walk"],
        .hinge: ["Leg swing", "Walking knee hug", "Inchworm", "Cat-cow", "Foam roll hamstrings"],
        .horizontalPush: ["Arm circles", "Band pass-through", "Band external rotation", "Wall slide"],
        .verticalPush: ["Wall slide", "Band pass-through", "Band external rotation", "Arm circles"],
        .horizontalPull: ["Band pass-through", "Open book", "Cat-cow", "Arm circles"],
        .verticalPull: ["Scapular pull-up", "Band pass-through", "Open book", "Arm circles"],
        .carry: ["Cat-cow", "Walking knee hug"],
        .core: ["Cat-cow", "Inchworm"],
    ]

    // MARK: Warming up inside the workout

    /// One thing to do before a lift: a drill, or a lighter set of the lift itself.
    enum Step: Hashable {
        case drill(PlannedExercise)
        case ramp(RampUp.Step)

        /// Roughly how long it takes, including the rest after it.
        var seconds: Int {
            switch self {
            case .drill(let d): let dose = Dose(d.reps); return dose.seconds.map { $0 * dose.sides } ?? 45
            case .ramp(let r): return 30 + r.rest
            }
        }
    }

    /// Drills fit in five minutes for the whole workout, at most two before any one lift.
    static let budget = 300
    static let perLift = 2

    /// Spreads the warm-up through the workout instead of front-loading it. Drills: the pulse raiser
    /// before the first lift, then one for each movement not warmed up yet. Warm-up sets: before
    /// every lift with a working weight, sized to that weight.
    static func beforeEachLift(_ plan: PlannedWorkout, unit: WeightUnit) -> [String: [Step]] {
        var left = budget
        var unused = plan.warmUp
        var warmedPatterns = Set<MovementPattern>()
        /// The heaviest working weight done so far for each muscle.
        var warmedMuscles: [MuscleGroup: Double] = [:]
        var out: [String: [Step]] = [:]
        for (i, lift) in plan.exercises.enumerated() {
            guard let ex = ExerciseCatalog.named(lift.name) else { continue }
            var drillsWanted: [PlannedExercise] = []
            if i == 0, let general = unused.first(where: { ExerciseCatalog.named($0.name)?.isGeneralWarmUp == true }) {
                drillsWanted.append(general)
            }
            if let pattern = ex.pattern, !warmedPatterns.contains(pattern),
               let drill = unused.first(where: { drills[pattern]?.contains($0.name) == true }) {
                drillsWanted.append(drill)
            }
            if let pattern = ex.pattern { warmedPatterns.insert(pattern) }

            var steps: [Step] = []
            for drill in drillsWanted where steps.count < perLift {
                let step = Step.drill(drill)
                guard step.seconds <= left else { continue }
                steps.append(step)
                left -= step.seconds
                unused.removeAll { $0 == drill }
            }

            // Test sets on a new lift ramp up on their own.
            if lift.calibrate != true {
                let weight = lift.target?.weight ?? 0
                let warm = (warmedMuscles[ex.primary] ?? 0) >= weight * 0.8 && weight > 0
                steps += RampUp.steps(for: ex, target: lift.target, unit: unit, alreadyWarm: warm).map(Step.ramp)
                warmedMuscles[ex.primary] = max(warmedMuscles[ex.primary] ?? 0, weight)
            }
            if !steps.isEmpty { out[lift.name] = steps }
        }
        return out
    }
}

extension PlannedWorkout {
    /// The whole session in minutes, warm-up included: about 40 s per working set, the rest after
    /// each one, a minute to change over between lifts, plus the warm-up steps and their rests.
    func estimatedMinutes(unit: WeightUnit, warmUps: Bool) -> Int {
        guard !isRestDay else { return 0 }
        let sets = totalSets
        let lifting = sets * 40 + max(0, sets - exercises.count) * restSeconds + max(0, exercises.count - 1) * 60
        let warm = warmUps ? WarmUps.beforeEachLift(self, unit: unit).values.joined().reduce(0) { $0 + $1.seconds } : 0
        return Int((Double(lifting + warm) / 60).rounded())
    }
}

/// Warm-up sets before a lift, sized to its working weight so muscles and tendons get there in steps.
enum RampUp {
    struct Step: Hashable {
        /// Pounds.
        let weight: Double
        let reps: Int
        /// Seconds to rest after it: short after light sets, longer as they get close to working weight.
        let rest: Int
    }

    /// The heavier the working weight, the more (and smaller) the jumps:
    /// light: 50 % × 8 · moderate: 50 % × 8, 75 % × 4 · heavy: 40 % × 8, 60 % × 5, 80 % × 3 ·
    /// very heavy: 40 % × 8, 55 % × 5, 70 % × 3, 85 % × 2.
    /// A focused (isolation) lift gets one light set; a lift whose muscle is already warm from an
    /// earlier, heavier lift gets one feeler set. Rounded to the unit's step, never below an empty bar.
    static func steps(for exercise: Exercise, target: LoadTarget?, unit: WeightUnit, alreadyWarm: Bool = false) -> [Step] {
        guard let target, target.weight > 0, exercise.kind == .strength, !exercise.isTimed else { return [] }
        let bar = exercise.equipment.contains(.barbell) ? unit.toPounds(unit == .lb ? 45 : 20) : 0
        // Dumbbell weights are per hand: compare the pair against the barbell-sized thresholds.
        let load = exercise.equipment.contains(.dumbbells) && bar == 0 ? target.weight * 2 : target.weight

        let scheme: [(share: Double, reps: Int)]
        if alreadyWarm {
            scheme = exercise.isCompound ? [(0.6, 5)] : []
        } else if !exercise.isCompound {
            scheme = load >= 20 ? [(0.5, 10)] : []
        } else if load < 95 {
            scheme = [(0.5, 8)]
        } else if load < 185 {
            scheme = [(0.5, 8), (0.75, 4)]
        } else if load < 275 {
            scheme = [(0.4, 8), (0.6, 5), (0.8, 3)]
        } else {
            scheme = [(0.4, 8), (0.55, 5), (0.7, 3), (0.85, 2)]
        }

        var steps: [Step] = []
        for (share, reps) in scheme {
            let weight = max(bar, unit.toPounds(unit.roundToStep(unit.fromPounds(target.weight * share))))
            guard weight > 0, weight < target.weight, !steps.contains(where: { $0.weight == weight }) else { continue }
            steps.append(Step(weight: weight, reps: reps, rest: share < 0.6 ? 30 : share < 0.8 ? 60 : 90))
        }
        return steps
    }
}

/// "30 s", "30 s/side", "3 min", "10/side": how long one round takes and how many sides it has.
struct Dose {
    /// Nil when it's a rep count.
    let seconds: Int?
    let sides: Int

    init(_ text: String) {
        let lower = text.lowercased()
        sides = lower.contains("/side") || lower.contains("/leg") || lower.contains("/arm") ? 2 : 1
        let number = Int(lower.split(whereSeparator: { !$0.isNumber }).first ?? "") ?? 0
        if lower.contains("min") {
            seconds = number * 60
        } else if lower.contains(" s") {
            seconds = number
        } else {
            seconds = nil
        }
    }

    static func label(_ seconds: Int) -> String {
        seconds >= 60 && seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) s"
    }
}
