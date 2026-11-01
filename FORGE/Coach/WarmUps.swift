import Foundation

/// Builds the warm-up and cool-down around a day's lifts. Deterministic, so AI and rule-based
/// plans get the same treatment, and it only picks what the gym and the notes allow.
extension WarmUps {
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
