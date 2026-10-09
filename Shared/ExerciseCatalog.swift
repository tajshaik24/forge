import Foundation

struct Exercise: Sendable, Hashable {
    let name: String
    let primary: MuscleGroup
    let secondary: [MuscleGroup]
    /// All of these must be present at the gym. Empty = bodyweight.
    let equipment: Set<Equipment>
    let flags: Set<MovementFlag>
    let reps: String
    /// Bigger compound lifts first in a session.
    let isCompound: Bool
    /// Created by the user (synced via iCloud) rather than built in.
    var isCustom: Bool = false
    /// The user's own description, shown in place of a built-in form guide.
    var customNotes: String? = nil

    /// Rep target as a range: "8-12" -> 8...12, "10/leg" -> 10...10.
    var repRange: ClosedRange<Int> { RepRange.parse(reps) }

    func isDoable(with gym: Set<Equipment>, avoiding: Set<MovementFlag>) -> Bool {
        equipment.isSubset(of: gym) && flags.isDisjoint(with: avoiding)
    }
}

/// The only exercises the coach is allowed to program. Equipment and coach notes
/// filter this list *before* the model sees it, so the model can't suggest a leg
/// press at a home gym or a back squat after "squats make me lightheaded".
enum ExerciseCatalog {
    private static func ex(_ name: String, _ primary: MuscleGroup, _ secondary: [MuscleGroup] = [],
                           _ equipment: Set<Equipment> = [], _ flags: Set<MovementFlag> = [],
                           reps: String = "8-12", compound: Bool = false) -> Exercise {
        Exercise(name: name, primary: primary, secondary: secondary, equipment: equipment,
                 flags: flags, reps: reps, isCompound: compound)
    }

    static let builtIn: [Exercise] = [
        // Chest
        ex("Barbell bench press", .chest, [.triceps, .shoulders], [.barbell, .bench, .squatRack], reps: "5-8", compound: true),
        ex("Dumbbell bench press", .chest, [.triceps, .shoulders], [.dumbbells, .bench], reps: "8-10", compound: true),
        ex("Incline dumbbell press", .chest, [.shoulders, .triceps], [.dumbbells, .bench], reps: "8-12", compound: true),
        ex("Cable fly", .chest, [], [.cableStack], reps: "12-15"),
        ex("Push-up", .chest, [.triceps, .core], [], [.floorTransitions], reps: "10-20", compound: true),
        ex("Dip", .chest, [.triceps], [.dipStation], reps: "6-12", compound: true),
        // Back
        ex("Pull-up", .back, [.biceps], [.pullUpBar], reps: "5-10", compound: true),
        ex("Lat pulldown", .back, [.biceps], [.cableStack], reps: "8-12", compound: true),
        ex("Chest-supported dumbbell row", .back, [.biceps, .shoulders], [.dumbbells, .bench], reps: "8-12", compound: true),
        ex("One-arm dumbbell row", .back, [.biceps], [.dumbbells, .bench], reps: "8-12", compound: true),
        ex("Seated cable row", .back, [.biceps], [.cableStack], reps: "10-12", compound: true),
        ex("Barbell row", .back, [.biceps, .hamstrings], [.barbell], [.standingHeavy], reps: "6-10", compound: true),
        ex("Band pull-apart", .shoulders, [.back], [.bands], reps: "15-20"),
        // Shoulders
        ex("Standing barbell overhead press", .shoulders, [.triceps], [.barbell, .squatRack], [.overhead, .axialLoading, .standingHeavy], reps: "5-8", compound: true),
        ex("Seated neutral-grip dumbbell press", .shoulders, [.triceps], [.dumbbells, .bench], [.overhead], reps: "8-10", compound: true),
        ex("Dumbbell lateral raise", .shoulders, [], [.dumbbells], reps: "12-15"),
        ex("Cable face pull", .shoulders, [.back], [.cableStack], reps: "12-15"),
        ex("Reverse dumbbell fly", .shoulders, [.back], [.dumbbells, .bench], reps: "12-15"),
        // Arms
        ex("Dumbbell curl", .biceps, [], [.dumbbells], reps: "10-12"),
        ex("Incline dumbbell curl", .biceps, [], [.dumbbells, .bench], reps: "10-12"),
        ex("Cable curl", .biceps, [], [.cableStack], reps: "10-15"),
        ex("Band curl", .biceps, [], [.bands], reps: "15-20"),
        ex("Cable triceps pushdown", .triceps, [], [.cableStack], reps: "10-15"),
        ex("Dumbbell skull crusher", .triceps, [], [.dumbbells, .bench], reps: "10-12"),
        ex("Close-grip push-up", .triceps, [.chest], [], [.floorTransitions], reps: "8-15"),
        // Quads
        ex("Back squat", .quads, [.glutes, .hamstrings, .core], [.barbell, .squatRack], [.axialLoading, .standingHeavy, .deepKneeBend], reps: "5-8", compound: true),
        ex("Goblet squat", .quads, [.glutes, .core], [.dumbbells], [.deepKneeBend], reps: "8-12", compound: true),
        ex("Leg press", .quads, [.glutes], [.legPress], reps: "8-12", compound: true),
        ex("Smith machine squat", .quads, [.glutes], [.smithMachine], [.axialLoading, .deepKneeBend], reps: "8-10", compound: true),
        ex("Split squat (hand on bench)", .quads, [.glutes], [.dumbbells, .bench], reps: "8-10/leg", compound: true),
        ex("Bench step-up", .quads, [.glutes], [.dumbbells, .bench], reps: "10/leg", compound: true),
        ex("Leg extension", .quads, [], [.legExtension], reps: "12-15"),
        ex("Jump squat", .quads, [.glutes, .calves], [], [.jumping, .deepKneeBend], reps: "8-10"),
        // Posterior chain
        ex("Barbell deadlift", .hamstrings, [.glutes, .back], [.barbell], [.standingHeavy, .axialLoading], reps: "3-6", compound: true),
        ex("Dumbbell Romanian deadlift", .hamstrings, [.glutes, .back], [.dumbbells], reps: "8-12", compound: true),
        ex("Seated leg curl", .hamstrings, [], [.legCurl], reps: "10-15"),
        ex("Banded leg curl", .hamstrings, [], [.bands], [.floorTransitions], reps: "15-20"),
        ex("Kettlebell swing", .glutes, [.hamstrings], [.kettlebell], reps: "15-20", compound: true),
        ex("Dumbbell hip thrust", .glutes, [.hamstrings], [.dumbbells, .bench], reps: "10-12", compound: true),
        // Calves + core
        ex("Seated dumbbell calf raise", .calves, [], [.dumbbells, .bench], reps: "12-20"),
        ex("Single-leg calf raise", .calves, [], [], reps: "12-20"),
        ex("Hanging knee raise", .core, [], [.pullUpBar], reps: "10-15"),
        ex("Cable crunch", .core, [], [.cableStack], reps: "12-15"),
        ex("Dead bug", .core, [], [], [.floorTransitions], reps: "10/side"),
        ex("Pallof press", .core, [], [.bands], reps: "10/side"),
    ]

    /// User-created exercises. Refreshed from SwiftData on launch and whenever they change.
    nonisolated(unsafe) static var custom: [Exercise] = []

    static var all: [Exercise] { builtIn + custom }

    static func named(_ name: String) -> Exercise? {
        let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return all.first { $0.name.lowercased() == key }
    }

    static func available(gym: Set<Equipment>, avoiding: Set<MovementFlag>) -> [Exercise] {
        all.filter { $0.isDoable(with: gym, avoiding: avoiding) }
    }

    /// The first catalog exercise for this muscle that the gym/notes *would* have allowed
    /// were it not for the restriction — used to label "replaces back squat".
    static func blockedStaple(for muscle: MuscleGroup, gym: Set<Equipment>, avoiding: Set<MovementFlag>) -> Exercise? {
        builtIn.first { $0.primary == muscle && $0.isCompound && !$0.isDoable(with: gym, avoiding: avoiding) }
    }
}

enum RepRange {
    static func parse(_ text: String) -> ClosedRange<Int> {
        let digits = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let low = digits.first else { return 8...12 }
        let high = digits.count > 1 && text.contains("-") ? max(digits[1], low) : low
        return low...high
    }
}
