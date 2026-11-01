import Foundation

struct Exercise: Sendable, Hashable {
    let name: String
    let primary: MuscleGroup
    let secondary: [MuscleGroup]
    /// All of these must be present at the gym. Empty = bodyweight.
    let equipment: Set<Equipment>
    let flags: Set<MovementFlag>
    /// Reps per set ("8-12", "10/side"), or a time for holds and stretches ("30 s", "30 s/side", "3 min").
    let reps: String
    /// Bigger compound lifts first in a session.
    let isCompound: Bool
    /// Created by the user (synced via iCloud) rather than built in.
    var isCustom: Bool = false
    /// The user's own description, shown in place of a built-in form guide.
    var customNotes: String? = nil
    var kind: ExerciseKind = .strength
    /// Nil for single-muscle accessories.
    var pattern: MovementPattern? = nil
    /// Who it suits: `.new` is fine on day one.
    var level: Experience = .new
    /// For warm-ups and stretches: where you'll feel it.
    var areas: Set<BodyArea> = []
    /// Helps undo desk posture: upper back, rear shoulders, hip flexors, deep core.
    var helpsPosture: Bool = false
    /// A whole-body pulse raiser (row, bike, jacks) rather than a targeted drill.
    var isGeneralWarmUp: Bool = false
    /// Start/finish photos from free-exercise-db, bundled as "<photo>-0" and "<photo>-1".
    var photo: String? = nil

    /// Rep target as a range: "8-12" -> 8...12, "10/leg" -> 10...10.
    var repRange: ClosedRange<Int> { RepRange.parse(reps) }

    /// Done for a time rather than a rep count.
    var isTimed: Bool { reps.contains(" s") || reps.contains("min") }

    func isDoable(with gym: Set<Equipment>, avoiding: Set<MovementFlag>) -> Bool {
        equipment.isSubset(of: gym) && flags.isDisjoint(with: avoiding)
    }
}

/// The only exercises the coach is allowed to program. Equipment and coach notes
/// filter this list *before* the model sees it, so the model can't suggest a leg
/// press at a home gym or a back squat after "squats make me lightheaded".
///
/// Curated from free-exercise-db (public domain, github.com/yuhonas/free-exercise-db):
/// the major lifts, plus warm-ups, stretches and posture work.
enum ExerciseCatalog {
    private static func ex(_ name: String, _ primary: MuscleGroup, _ secondary: [MuscleGroup] = [],
                           _ equipment: Set<Equipment> = [], _ flags: Set<MovementFlag> = [],
                           reps: String = "8-12", compound: Bool = false, pattern: MovementPattern? = nil,
                           level: Experience = .new, posture: Bool = false, photo: String? = nil) -> Exercise {
        Exercise(name: name, primary: primary, secondary: secondary, equipment: equipment,
                 flags: flags, reps: reps, isCompound: compound, pattern: pattern, level: level,
                 helpsPosture: posture, photo: photo)
    }

    private static func warmUp(_ name: String, _ primary: MuscleGroup, _ areas: Set<BodyArea>,
                               _ equipment: Set<Equipment> = [], _ flags: Set<MovementFlag> = [],
                               dose: String, posture: Bool = false, general: Bool = false, photo: String? = nil) -> Exercise {
        Exercise(name: name, primary: primary, secondary: [], equipment: equipment, flags: flags, reps: dose,
                 isCompound: false, kind: .warmUp, areas: areas, helpsPosture: posture,
                 isGeneralWarmUp: general, photo: photo)
    }

    private static func stretch(_ name: String, _ primary: MuscleGroup, _ areas: Set<BodyArea>,
                                _ equipment: Set<Equipment> = [], _ flags: Set<MovementFlag> = [],
                                dose: String = "30 s/side", posture: Bool = false, photo: String? = nil) -> Exercise {
        Exercise(name: name, primary: primary, secondary: [], equipment: equipment, flags: flags, reps: dose,
                 isCompound: false, kind: .stretch, areas: areas, helpsPosture: posture, photo: photo)
    }

    static let builtIn: [Exercise] = strength + warmUps + stretches

    static let strength: [Exercise] = [
        // Chest
        ex("Barbell bench press", .chest, [.triceps, .shoulders], [.barbell, .bench, .squatRack], reps: "5-8", compound: true,
           pattern: .horizontalPush, level: .intermediate, photo: "Barbell_Bench_Press_-_Medium_Grip"),
        ex("Incline barbell bench press", .chest, [.shoulders, .triceps], [.barbell, .bench, .squatRack], reps: "6-10", compound: true,
           pattern: .horizontalPush, level: .intermediate, photo: "Barbell_Incline_Bench_Press_-_Medium_Grip"),
        ex("Dumbbell bench press", .chest, [.triceps, .shoulders], [.dumbbells, .bench], reps: "8-10", compound: true,
           pattern: .horizontalPush, photo: "Dumbbell_Bench_Press"),
        ex("Incline dumbbell press", .chest, [.shoulders, .triceps], [.dumbbells, .bench], reps: "8-12", compound: true,
           pattern: .horizontalPush, photo: "Incline_Dumbbell_Press"),
        ex("Machine chest press", .chest, [.triceps, .shoulders], [.machines], reps: "8-12", compound: true,
           pattern: .horizontalPush, photo: "Machine_Bench_Press"),
        ex("Dumbbell fly", .chest, [], [.dumbbells, .bench], reps: "10-15", photo: "Dumbbell_Flyes"),
        ex("Cable fly", .chest, [], [.cableStack], reps: "12-15", photo: "Cable_Crossover"),
        ex("Pec deck", .chest, [], [.machines], reps: "12-15", photo: "Butterfly"),
        ex("Push-up", .chest, [.triceps, .core], [], [.floorTransitions], reps: "10-20", compound: true,
           pattern: .horizontalPush, photo: "Pushups"),
        ex("Incline push-up", .chest, [.triceps, .core], [.bench], reps: "8-15", compound: true,
           pattern: .horizontalPush, photo: "Incline_Push-Up"),
        ex("Dip", .chest, [.triceps], [.dipStation], reps: "6-12", compound: true,
           pattern: .verticalPush, level: .intermediate, photo: "Dips_-_Chest_Version"),
        // Back
        ex("Pull-up", .back, [.biceps], [.pullUpBar], reps: "5-10", compound: true,
           pattern: .verticalPull, level: .intermediate, photo: "Pullups"),
        ex("Chin-up", .back, [.biceps], [.pullUpBar], reps: "5-10", compound: true,
           pattern: .verticalPull, level: .intermediate, photo: "Chin-Up"),
        ex("Band-assisted pull-up", .back, [.biceps], [.pullUpBar, .bands], reps: "5-8", compound: true, pattern: .verticalPull),
        ex("Negative pull-up", .back, [.biceps], [.pullUpBar], reps: "3-5", compound: true, pattern: .verticalPull),
        ex("Lat pulldown", .back, [.biceps], [.cableStack], reps: "8-12", compound: true,
           pattern: .verticalPull, photo: "Wide-Grip_Lat_Pulldown"),
        ex("Straight-arm pulldown", .back, [], [.cableStack], reps: "12-15", photo: "Straight-Arm_Pulldown"),
        ex("Chest-supported dumbbell row", .back, [.biceps, .shoulders], [.dumbbells, .bench], reps: "8-12", compound: true,
           pattern: .horizontalPull, posture: true),
        ex("One-arm dumbbell row", .back, [.biceps], [.dumbbells, .bench], reps: "8-12", compound: true,
           pattern: .horizontalPull, photo: "One-Arm_Dumbbell_Row"),
        ex("Bent-over dumbbell row", .back, [.biceps, .hamstrings], [.dumbbells], reps: "8-12", compound: true,
           pattern: .horizontalPull, photo: "Bent_Over_Two-Dumbbell_Row"),
        ex("Seated cable row", .back, [.biceps], [.cableStack], reps: "10-12", compound: true,
           pattern: .horizontalPull, posture: true, photo: "Seated_Cable_Rows"),
        ex("Barbell row", .back, [.biceps, .hamstrings], [.barbell], [.standingHeavy], reps: "6-10", compound: true,
           pattern: .horizontalPull, level: .intermediate, photo: "Bent_Over_Barbell_Row"),
        ex("Inverted row", .back, [.biceps, .core], [.barbell, .squatRack], reps: "6-12", compound: true,
           pattern: .horizontalPull, posture: true, photo: "Inverted_Row"),
        ex("Band row", .back, [.biceps], [.bands], reps: "12-15", compound: true, pattern: .horizontalPull, posture: true),
        ex("Dumbbell pullover", .back, [.chest], [.dumbbells, .bench], reps: "10-12", photo: "Straight-Arm_Dumbbell_Pullover"),
        ex("Superman", .back, [.glutes], [], [.floorTransitions], reps: "10-12", posture: true, photo: "Superman"),
        ex("Band pull-apart", .shoulders, [.back], [.bands], reps: "15-20", posture: true),
        // Shoulders
        ex("Standing barbell overhead press", .shoulders, [.triceps], [.barbell, .squatRack], [.overhead, .axialLoading, .standingHeavy],
           reps: "5-8", compound: true, pattern: .verticalPush, level: .intermediate, photo: "Standing_Military_Press"),
        ex("Seated neutral-grip dumbbell press", .shoulders, [.triceps], [.dumbbells, .bench], [.overhead], reps: "8-10", compound: true,
           pattern: .verticalPush, photo: "Seated_Dumbbell_Press"),
        ex("Arnold press", .shoulders, [.triceps], [.dumbbells, .bench], [.overhead], reps: "8-12", compound: true,
           pattern: .verticalPush, level: .intermediate, photo: "Arnold_Dumbbell_Press"),
        ex("Machine shoulder press", .shoulders, [.triceps], [.machines], [.overhead], reps: "8-12", compound: true,
           pattern: .verticalPush, photo: "Machine_Shoulder_Military_Press"),
        ex("Pike push-up", .shoulders, [.triceps], [], [.overhead, .floorTransitions], reps: "6-10", compound: true,
           pattern: .verticalPush, level: .intermediate),
        ex("Dumbbell lateral raise", .shoulders, [], [.dumbbells], reps: "12-15", photo: "Side_Lateral_Raise"),
        ex("Cable lateral raise", .shoulders, [], [.cableStack], reps: "12-15"),
        ex("Band lateral raise", .shoulders, [], [.bands], reps: "15-20", photo: "Lateral_Raise_-_With_Bands"),
        ex("Cable face pull", .shoulders, [.back], [.cableStack], reps: "12-15", posture: true, photo: "Face_Pull"),
        ex("Reverse dumbbell fly", .shoulders, [.back], [.dumbbells, .bench], reps: "12-15", posture: true, photo: "Reverse_Flyes"),
        ex("Rear-delt machine fly", .shoulders, [.back], [.machines], reps: "12-15", posture: true, photo: "Reverse_Machine_Flyes"),
        ex("Prone Y-T-W raise", .shoulders, [.back], [.bench], reps: "6-8", posture: true),
        ex("Dumbbell shrug", .shoulders, [.back], [.dumbbells], reps: "10-15", photo: "Dumbbell_Shrug"),
        // Arms
        ex("Dumbbell curl", .biceps, [], [.dumbbells], reps: "10-12", photo: "Dumbbell_Bicep_Curl"),
        ex("Hammer curl", .biceps, [], [.dumbbells], reps: "10-12", photo: "Hammer_Curls"),
        ex("Barbell curl", .biceps, [], [.barbell], reps: "8-12", photo: "Barbell_Curl"),
        ex("Incline dumbbell curl", .biceps, [], [.dumbbells, .bench], reps: "10-12", photo: "Incline_Dumbbell_Curl"),
        ex("Concentration curl", .biceps, [], [.dumbbells, .bench], reps: "10-12/arm", photo: "Concentration_Curls"),
        ex("Cable curl", .biceps, [], [.cableStack], reps: "10-15", photo: "Standing_Biceps_Cable_Curl"),
        ex("Band curl", .biceps, [], [.bands], reps: "15-20"),
        ex("Cable triceps pushdown", .triceps, [], [.cableStack], reps: "10-15", photo: "Triceps_Pushdown"),
        ex("Overhead cable triceps extension", .triceps, [], [.cableStack], [.overhead], reps: "10-15",
           photo: "Cable_Rope_Overhead_Triceps_Extension"),
        ex("Overhead dumbbell triceps extension", .triceps, [], [.dumbbells], [.overhead], reps: "10-12",
           photo: "Standing_Dumbbell_Triceps_Extension"),
        ex("Dumbbell skull crusher", .triceps, [], [.dumbbells, .bench], reps: "10-12", photo: "Lying_Dumbbell_Tricep_Extension"),
        ex("Close-grip bench press", .triceps, [.chest, .shoulders], [.barbell, .bench, .squatRack], reps: "6-10", compound: true,
           pattern: .horizontalPush, level: .intermediate, photo: "Close-Grip_Barbell_Bench_Press"),
        ex("Bench dip", .triceps, [.chest], [.bench], reps: "8-15", photo: "Bench_Dips"),
        ex("Close-grip push-up", .triceps, [.chest], [], [.floorTransitions], reps: "8-15", photo: "Push-Ups_-_Close_Triceps_Position"),
        // Quads
        ex("Back squat", .quads, [.glutes, .hamstrings, .core], [.barbell, .squatRack], [.axialLoading, .standingHeavy, .deepKneeBend],
           reps: "5-8", compound: true, pattern: .squat, level: .intermediate, photo: "Barbell_Squat"),
        ex("Front squat", .quads, [.glutes, .core], [.barbell, .squatRack], [.axialLoading, .standingHeavy, .deepKneeBend],
           reps: "5-8", compound: true, pattern: .squat, level: .advanced, photo: "Front_Barbell_Squat"),
        ex("Goblet squat", .quads, [.glutes, .core], [.dumbbells], [.deepKneeBend], reps: "8-12", compound: true,
           pattern: .squat, photo: "Goblet_Squat"),
        ex("Box squat to bench", .quads, [.glutes], [.dumbbells, .bench], reps: "10-12", compound: true, pattern: .squat),
        ex("Leg press", .quads, [.glutes], [.legPress], reps: "8-12", compound: true, pattern: .squat, photo: "Leg_Press"),
        ex("Smith machine squat", .quads, [.glutes], [.smithMachine], [.axialLoading, .deepKneeBend], reps: "8-10", compound: true,
           pattern: .squat, photo: "Smith_Machine_Squat"),
        ex("Split squat (hand on bench)", .quads, [.glutes], [.dumbbells, .bench], reps: "8-10/leg", compound: true,
           pattern: .lunge, photo: "Split_Squat_with_Dumbbells"),
        ex("Bulgarian split squat", .quads, [.glutes], [.dumbbells, .bench], [.deepKneeBend], reps: "8-10/leg", compound: true,
           pattern: .lunge, level: .intermediate),
        ex("Reverse lunge", .quads, [.glutes, .hamstrings], [.dumbbells], [.deepKneeBend], reps: "8-10/leg", compound: true,
           pattern: .lunge, photo: "Dumbbell_Rear_Lunge"),
        ex("Walking lunge", .quads, [.glutes, .hamstrings], [.dumbbells], [.deepKneeBend], reps: "10/leg", compound: true,
           pattern: .lunge, level: .intermediate, photo: "Dumbbell_Lunges"),
        ex("Bench step-up", .quads, [.glutes], [.dumbbells, .bench], reps: "10/leg", compound: true,
           pattern: .lunge, photo: "Dumbbell_Step_Ups"),
        ex("Leg extension", .quads, [], [.legExtension], reps: "12-15", photo: "Leg_Extensions"),
        ex("Wall sit", .quads, [.glutes], [], reps: "30-45 s"),
        ex("Jump squat", .quads, [.glutes, .calves], [], [.jumping, .deepKneeBend], reps: "8-10",
           level: .intermediate, photo: "Freehand_Jump_Squat"),
        // Posterior chain
        ex("Barbell deadlift", .hamstrings, [.glutes, .back], [.barbell], [.standingHeavy, .axialLoading], reps: "3-6", compound: true,
           pattern: .hinge, level: .intermediate, photo: "Barbell_Deadlift"),
        ex("Barbell Romanian deadlift", .hamstrings, [.glutes, .back], [.barbell], [.standingHeavy], reps: "6-10", compound: true,
           pattern: .hinge, level: .intermediate, photo: "Romanian_Deadlift"),
        ex("Dumbbell Romanian deadlift", .hamstrings, [.glutes, .back], [.dumbbells], reps: "8-12", compound: true,
           pattern: .hinge, photo: "Stiff-Legged_Dumbbell_Deadlift"),
        ex("Single-leg Romanian deadlift", .hamstrings, [.glutes, .core], [.dumbbells], reps: "8-10/leg", compound: true,
           pattern: .hinge, level: .intermediate, photo: "Kettlebell_One-Legged_Deadlift"),
        ex("Kettlebell deadlift", .hamstrings, [.glutes, .back], [.kettlebell], reps: "10-15", compound: true, pattern: .hinge),
        ex("Good morning", .hamstrings, [.glutes, .back], [.barbell, .squatRack], [.axialLoading, .standingHeavy], reps: "8-10",
           compound: true, pattern: .hinge, level: .advanced, photo: "Good_Morning"),
        ex("Cable pull-through", .glutes, [.hamstrings], [.cableStack], reps: "12-15", compound: true,
           pattern: .hinge, photo: "Pull_Through"),
        ex("Kettlebell swing", .glutes, [.hamstrings], [.kettlebell], reps: "15-20", compound: true,
           pattern: .hinge, level: .intermediate),
        ex("Seated leg curl", .hamstrings, [], [.legCurl], reps: "10-15", photo: "Seated_Leg_Curl"),
        ex("Lying leg curl", .hamstrings, [], [.legCurl], reps: "10-15", photo: "Lying_Leg_Curls"),
        ex("Banded leg curl", .hamstrings, [], [.bands], [.floorTransitions], reps: "15-20"),
        ex("Glute bridge", .glutes, [.hamstrings], [], [.floorTransitions], reps: "12-15", pattern: .hinge, posture: true,
           photo: "Butt_Lift_Bridge"),
        ex("Single-leg glute bridge", .glutes, [.hamstrings], [], [.floorTransitions], reps: "10/leg", pattern: .hinge,
           photo: "Single_Leg_Glute_Bridge"),
        ex("Dumbbell hip thrust", .glutes, [.hamstrings], [.dumbbells, .bench], reps: "10-12", compound: true, pattern: .hinge),
        ex("Barbell hip thrust", .glutes, [.hamstrings], [.barbell, .bench], reps: "8-12", compound: true,
           pattern: .hinge, level: .intermediate, photo: "Barbell_Hip_Thrust"),
        ex("Cable kickback", .glutes, [], [.cableStack], reps: "12-15/leg"),
        // Calves
        ex("Standing dumbbell calf raise", .calves, [], [.dumbbells], reps: "12-20"),
        ex("Seated dumbbell calf raise", .calves, [], [.dumbbells, .bench], reps: "12-20", photo: "Dumbbell_Seated_One-Leg_Calf_Raise"),
        ex("Single-leg calf raise", .calves, [], [], reps: "12-20"),
        ex("Leg press calf raise", .calves, [], [.legPress], reps: "12-20", photo: "Calf_Press_On_The_Leg_Press_Machine"),
        // Core
        ex("Plank", .core, [.shoulders], [], [.floorTransitions], reps: "30-45 s", pattern: .core, posture: true, photo: "Plank"),
        ex("Side plank", .core, [.shoulders], [], [.floorTransitions], reps: "20-30 s/side", pattern: .core, photo: "Side_Bridge"),
        ex("Dead bug", .core, [], [], [.floorTransitions], reps: "10/side", pattern: .core, posture: true, photo: "Dead_Bug"),
        ex("Bird dog", .core, [.glutes, .back], [], [.floorTransitions], reps: "8/side", pattern: .core, posture: true),
        ex("Pallof press", .core, [], [.bands], reps: "10/side", pattern: .core, photo: "Pallof_Press"),
        ex("Cable woodchop", .core, [.shoulders], [.cableStack], reps: "10/side", pattern: .core, photo: "Standing_Cable_Wood_Chop"),
        ex("Cable crunch", .core, [], [.cableStack], reps: "12-15", photo: "Cable_Crunch"),
        ex("Reverse crunch", .core, [], [], [.floorTransitions], reps: "10-15", photo: "Reverse_Crunch"),
        ex("Hanging knee raise", .core, [], [.pullUpBar], reps: "10-15"),
        ex("Hanging leg raise", .core, [], [.pullUpBar], reps: "8-12", level: .intermediate, photo: "Hanging_Leg_Raise"),
        ex("Farmer's carry", .core, [.shoulders, .back], [.dumbbells], reps: "30-40 s", compound: true,
           pattern: .carry, posture: true, photo: "Farmers_Walk"),
        ex("Suitcase carry", .core, [.shoulders], [.dumbbells], reps: "30 s/side", compound: true, pattern: .carry),
    ]

    /// Pulse raisers and mobility drills. Never counted as training volume.
    static let warmUps: [Exercise] = [
        warmUp("Easy row", .back, [], [.rower], dose: "2 min", general: true, photo: "Rowing_Stationary"),
        warmUp("Easy bike", .quads, [], [.bike], dose: "2 min", general: true, photo: "Bicycling_Stationary"),
        warmUp("Jumping jacks", .calves, [], [], [.jumping], dose: "60 s", general: true),
        warmUp("March in place", .quads, [], [], dose: "60 s", general: true),
        warmUp("Arm circles", .shoulders, [.shoulders], dose: "30 s", photo: "Arm_Circles"),
        warmUp("Band pass-through", .shoulders, [.shoulders, .chest], [.bands], dose: "10", posture: true),
        warmUp("Band external rotation", .shoulders, [.shoulders], [.bands], dose: "12/side", posture: true,
               photo: "External_Rotation_with_Band"),
        warmUp("Scapular pull-up", .back, [.upperBack, .shoulders], [.pullUpBar], dose: "8", posture: true),
        warmUp("Wall slide", .shoulders, [.shoulders, .upperBack], dose: "10", posture: true),
        warmUp("Chin tuck", .shoulders, [.neck], dose: "10", posture: true),
        warmUp("Cat-cow", .back, [.upperBack, .lowerBack], [], [.floorTransitions], dose: "8", posture: true, photo: "Cat_Stretch"),
        warmUp("Open book", .back, [.upperBack, .chest], [], [.floorTransitions], dose: "8/side", posture: true),
        warmUp("World's greatest stretch", .hamstrings, [.hips, .hamstrings, .upperBack], [], [.floorTransitions], dose: "5/side",
               photo: "Worlds_Greatest_Stretch"),
        warmUp("Inchworm", .hamstrings, [.hamstrings, .shoulders], [], [.floorTransitions], dose: "5", photo: "Inchworm"),
        warmUp("Leg swing", .hamstrings, [.hips, .hamstrings], dose: "10/side"),
        warmUp("Hip circle", .glutes, [.hips], dose: "10/side", photo: "Standing_Hip_Circles"),
        warmUp("Walking knee hug", .glutes, [.hips, .glutes], dose: "10"),
        warmUp("Ankle rock", .calves, [.calves], dose: "10/side"),
        warmUp("Bodyweight squat", .quads, [.hips, .quads], [], [.deepKneeBend], dose: "10", photo: "Bodyweight_Squat"),
        warmUp("Lateral band walk", .glutes, [.hips, .glutes], [.bands], dose: "12/side", photo: "Monster_Walk"),
        warmUp("Foam roll upper back", .back, [.upperBack], [.foamRoller], [.floorTransitions], dose: "60 s", posture: true,
               photo: "Rhomboids-SMR"),
        warmUp("Foam roll quads", .quads, [.quads], [.foamRoller], [.floorTransitions], dose: "60 s", photo: "Quadriceps-SMR"),
        warmUp("Foam roll hamstrings", .hamstrings, [.hamstrings], [.foamRoller], [.floorTransitions], dose: "60 s",
               photo: "Hamstring-SMR"),
    ]

    /// Static stretches for cool-downs and rest days.
    static let stretches: [Exercise] = [
        stretch("Half-kneeling hip flexor stretch", .quads, [.hips, .quads], [], [.floorTransitions], posture: true,
                photo: "Kneeling_Hip_Flexor"),
        stretch("Standing quad stretch", .quads, [.quads]),
        stretch("Standing hamstring stretch", .hamstrings, [.hamstrings], photo: "Hamstring_Stretch"),
        stretch("Figure-four stretch", .glutes, [.glutes, .hips], [], [.floorTransitions], photo: "Ankle_On_The_Knee"),
        stretch("Butterfly stretch", .glutes, [.hips], [], [.floorTransitions], dose: "45 s"),
        stretch("Child's pose", .back, [.lowerBack, .upperBack], [], [.floorTransitions], dose: "45 s", photo: "Childs_Pose"),
        stretch("Cobra stretch", .core, [.lowerBack], [], [.floorTransitions], dose: "30 s"),
        stretch("Seated spinal twist", .back, [.lowerBack, .upperBack], [], [.floorTransitions]),
        stretch("Upper back stretch", .back, [.upperBack], dose: "30 s", photo: "Upper_Back_Stretch"),
        stretch("Kneeling lat stretch", .back, [.upperBack, .shoulders], [.bench], [.floorTransitions]),
        stretch("Doorway chest stretch", .chest, [.chest, .shoulders], posture: true),
        stretch("Cross-body shoulder stretch", .shoulders, [.shoulders]),
        stretch("Overhead triceps stretch", .triceps, [.shoulders], photo: "Triceps_Stretch"),
        stretch("Side neck stretch", .shoulders, [.neck], posture: true, photo: "Side_Neck_Stretch"),
        stretch("Wall calf stretch", .calves, [.calves], photo: "Calf_Stretch_Hands_Against_Wall"),
    ]

    /// User-created exercises. Refreshed from SwiftData on launch and whenever they change.
    nonisolated(unsafe) static var custom: [Exercise] = []

    static var all: [Exercise] { builtIn + custom }

    static func named(_ name: String) -> Exercise? {
        let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return all.first { $0.name.lowercased() == key }
    }

    /// Strength exercises the coach can program here. Warm-ups and stretches are picked separately.
    static func available(gym: Set<Equipment>, avoiding: Set<MovementFlag>, excluding: Set<String> = [],
                          kind: ExerciseKind = .strength) -> [Exercise] {
        all.filter { $0.kind == kind && $0.isDoable(with: gym, avoiding: avoiding) && !excluding.contains($0.name) }
    }

    /// Easier versions to build toward a lift, logged and progressed as their own exercises.
    static let easierVersions: [String: [String]] = [
        "Pull-up": ["Band-assisted pull-up", "Negative pull-up"],
        "Push-up": ["Incline push-up"],
        "Goblet squat": ["Box squat to bench"],
        "Dip": ["Bench dip"],
    ]

    /// The lift an easier version builds toward ("Band-assisted pull-up" -> "Pull-up").
    static func harderVersion(of name: String) -> String? {
        easierVersions.first { $0.value.contains(name) }?.key
    }

    /// Catalog exercise for a loosely written name: "pull ups", "Pullup", "pull-up".
    static func match(_ text: String) -> Exercise? {
        let key = normalized(text)
        guard !key.isEmpty else { return nil }
        return all.first { normalized($0.name) == key }
    }

    /// Exercises the athlete says they can't do, want to avoid or that hurt.
    /// Positive mentions ("I love squats") don't count.
    static func limited(in text: String) -> [String] {
        let lower = text.lowercased()
        let negative = ["can't", "can’t", "cannot", "unable", "hurt", "pain", "avoid", "hate", "don't like", "don’t like",
                        "skip", "not able", "struggle", "too hard", "work towards", "work toward", "build up to"]
        guard negative.contains(where: lower.contains) else { return [] }
        return mentioned(in: text)
    }

    /// Catalog exercises named in free text ("pull ups" -> Pull-up).
    static func mentioned(in text: String) -> [String] {
        // Longest names first so "Pull-up" doesn't also claim "Band-assisted pull-up".
        var found: [String] = []
        var remaining = normalized(text)
        for ex in all.sorted(by: { $0.name.count > $1.name.count }) {
            let key = normalized(ex.name)
            if key.count >= 4, remaining.contains(key) {
                found.append(ex.name)
                remaining = remaining.replacingOccurrences(of: key, with: " ")
            }
        }
        return found
    }

    /// Letters only, each word singular: "Pull ups" -> "pullup", "Lat pulldowns" -> "latpulldown".
    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map { $0.hasSuffix("s") && !$0.hasSuffix("ss") && $0.count > 2 ? $0.dropLast() : $0 }
            .joined()
    }

    /// The first catalog exercise for this muscle that the gym/notes *would* have allowed
    /// were it not for the restriction — used to label "replaces back squat".
    static func blockedStaple(for muscle: MuscleGroup, gym: Set<Equipment>, avoiding: Set<MovementFlag>) -> Exercise? {
        strength.first { $0.primary == muscle && $0.isCompound && !$0.isDoable(with: gym, avoiding: avoiding) }
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
