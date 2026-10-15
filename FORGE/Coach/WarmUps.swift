import Foundation

/// Builds the warm-up and cool-down around a day's lifts. Deterministic, so AI and rule-based
/// plans get the same treatment, and it only picks what the gym and the notes allow.
enum WarmUps {
    /// Drills that prepare each movement pattern, best first.
    private static let drills: [MovementPattern: [String]] = [
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

    /// One pulse raiser, then up to three drills for the day's main patterns.
    static func warmUp(for exercises: [PlannedExercise], context: CoachContext) -> [PlannedExercise] {
        let doable = doable(.warmUp, context)
        var picked: [Exercise] = []
        // Machines first: a rower or bike beats jumping jacks when the gym has one.
        let general = doable.filter(\.isGeneralWarmUp).sorted { !$0.equipment.isEmpty && $1.equipment.isEmpty }
        if let first = general.first { picked.append(first) }

        let patterns = exercises.compactMap { ExerciseCatalog.named($0.name)?.pattern }
        var orderedPatterns: [MovementPattern] = []
        for p in patterns where !orderedPatterns.contains(p) { orderedPatterns.append(p) }
        // Round-robin over patterns so a squat + press day gets a drill for each.
        let lists = orderedPatterns.map { drills[$0] ?? [] }
        var depth = 0
        while picked.count < 4, depth < (lists.map(\.count).max() ?? 0) {
            for list in lists where depth < list.count && picked.count < 4 {
                if let ex = doable.first(where: { $0.name == list[depth] }), !picked.contains(ex) { picked.append(ex) }
            }
            depth += 1
        }
        return picked.map { PlannedExercise(name: $0.name, sets: 1, reps: $0.reps) }
    }

    /// Three stretches for what was trained, posture stretches breaking ties.
    static func coolDown(for muscles: [MuscleGroup], context: CoachContext) -> [PlannedExercise] {
        let areas = muscles.reduce(into: Set<BodyArea>()) { $0.formUnion(BodyArea.stretched(by: $1)) }
        let ranked = doable(.stretch, context)
            .map { ex in (ex, ex.areas.intersection(areas).count) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : ($0.0.helpsPosture && !$1.0.helpsPosture) }
        var covered = Set<BodyArea>()
        var picked: [Exercise] = []
        // Prefer stretches that reach an area not covered yet.
        for (ex, _) in ranked where picked.count < 3 && !ex.areas.isSubset(of: covered) {
            picked.append(ex)
            covered.formUnion(ex.areas)
        }
        return picked.map { PlannedExercise(name: $0.name, sets: 1, reps: $0.reps) }
    }

    private static func doable(_ kind: ExerciseKind, _ context: CoachContext) -> [Exercise] {
        ExerciseCatalog.available(gym: context.equipment, avoiding: context.avoid,
                                  excluding: context.limitedExercises, kind: kind)
    }
}

/// Lighter sets before the first heavy lift, worked out from its target weight.
enum RampUp {
    struct Step: Hashable {
        /// Pounds.
        let weight: Double
        let reps: Int
    }

    /// 50 % × 8, 70 % × 5, 85 % × 3, rounded to the unit's step and never below an empty bar.
    /// Nothing for light or bodyweight lifts, where the first working set is warm-up enough.
    static func steps(for exercise: Exercise, target: LoadTarget?, unit: WeightUnit) -> [Step] {
        guard let target, exercise.isCompound, target.weight > 0 else { return [] }
        let bar = exercise.equipment.contains(.barbell) ? unit.toPounds(unit == .lb ? 45 : 20) : 0
        guard target.weight >= max(bar * 1.5, unit.toPounds(unit == .lb ? 50 : 22.5)) else { return [] }
        var steps: [Step] = []
        for (share, reps) in [(0.5, 8), (0.7, 5), (0.85, 3)] {
            let weight = max(bar, unit.toPounds(unit.roundToStep(unit.fromPounds(target.weight * share))))
            if weight < target.weight, !steps.contains(where: { $0.weight == weight }) {
                steps.append(Step(weight: weight, reps: reps))
            }
        }
        return steps
    }
}
