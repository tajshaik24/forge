import Testing
import Foundation
@testable import FORGE

@Suite("Exercise library")
struct LibraryTests {
    @Test func namesAreUnique() {
        let names = ExerciseCatalog.builtIn.map { $0.name.lowercased() }
        #expect(Set(names).count == names.count)
    }

    @Test func everyExerciseHasAKeyCue() {
        for ex in ExerciseCatalog.builtIn { #expect(FormGuides.keyCue(for: ex.name) != nil, "\(ex.name)") }
    }

    @Test func bigLiftsHaveAPattern() {
        for ex in ExerciseCatalog.strength where ex.isCompound { #expect(ex.pattern != nil, "\(ex.name)") }
    }

    @Test func drillsSayWhereYouFeelThem() {
        for ex in ExerciseCatalog.warmUps + ExerciseCatalog.stretches {
            #expect(ex.isGeneralWarmUp || !ex.areas.isEmpty, "\(ex.name)")
        }
    }

    @Test func stretchesAreTimed() {
        for ex in ExerciseCatalog.stretches { #expect(ex.isTimed, "\(ex.name)") }
    }

    @Test func everyPhotoIsBundled() {
        for ex in ExerciseCatalog.builtIn {
            guard let photo = ex.photo else { continue }
            for frame in 0...1 {
                #expect(Bundle.main.url(forResource: "\(photo)-\(frame)", withExtension: "jpg") != nil, "\(ex.name)")
            }
        }
    }

    @Test func postureWorkCoversEachKind() {
        let posture = ExerciseCatalog.builtIn.filter(\.helpsPosture)
        for kind in ExerciseKind.allCases { #expect(posture.contains { $0.kind == kind }, "\(kind)") }
    }

    @Test func plannerOnlyGetsStrengthAtTheRightLevel() {
        var c = libraryContext(equipment: Set(Equipment.allCases))
        c.experience = .new
        #expect(c.pool.allSatisfy { $0.kind == .strength })
        #expect(!c.pool.contains { $0.name == "Front squat" })    // advanced
        #expect(c.pool.contains { $0.name == "Back squat" })      // one level up is fine
        c.experience = .intermediate
        #expect(c.pool.contains { $0.name == "Front squat" })
    }

    @Test func warmUpsDontCountAsVolume() {
        let plan = PlannedWorkout(date: .now, focus: "Legs", muscles: [.quads], minutes: 45, reasons: [],
                                  exercises: [PlannedExercise(name: "Bodyweight squat", sets: 3, reps: "10")],
                                  restSeconds: 90, gymName: "Gym", engine: "test")
        #expect(Readiness.summarize(plan).setsByMuscle.isEmpty)
    }

    @Test func plansSavedBeforeWarmUpsStillLoad() throws {
        let old = #"{"date":0,"focus":"Push","muscles":["chest"],"minutes":45,"reasons":[],"exercises":[],"restSeconds":90,"gymName":"Gym","engine":"test"}"#
        let plan = try JSONDecoder().decode(PlannedWorkout.self, from: Data(old.utf8))
        #expect(plan.warmUp.isEmpty && plan.coolDown.isEmpty)
    }

    @Test(arguments: [("30 s", 30, 1), ("30 s/side", 30, 2), ("3 min", 180, 1), ("10/side", nil, 2), ("8", nil, 1)] as [(String, Int?, Int)])
    func readsDoses(_ text: String, _ seconds: Int?, _ sides: Int) {
        let dose = Dose(text)
        #expect(dose.seconds == seconds)
        #expect(dose.sides == sides)
    }
}

@Suite("Warm-ups and cool-downs")
struct WarmUpTests {
    private func planned(_ names: String...) -> [PlannedExercise] {
        names.map { PlannedExercise(name: $0, sets: 3, reps: "8") }
    }

    @Test func squatDayWarmsUpHipsAndKnees() {
        let c = libraryContext(equipment: [.dumbbells, .bench, .barbell, .squatRack, .bands])
        let warm = WarmUps.warmUp(for: planned("Back squat", "Dumbbell Romanian deadlift"), context: c).map(\.name)
        #expect(warm.first == "Jumping jacks")                 // no rower or bike here
        #expect(warm.contains("Bodyweight squat"))
        #expect(warm.contains("Leg swing"))                    // the hinge gets a drill too
        #expect(warm.count == 4)
    }

    @Test func machinesBeatJumpingJacks() {
        let c = libraryContext(equipment: [.rower, .dumbbells])
        #expect(WarmUps.warmUp(for: planned("Goblet squat"), context: c).first?.name == "Easy row")
    }

    @Test func warmUpsRespectNotes() {
        let note = NoteSnapshot(said: "Jumping hurts my knees", rule: "No jumping", avoid: [.jumping])
        let c = libraryContext(equipment: [.dumbbells], notes: [note])
        let warm = WarmUps.warmUp(for: planned("Goblet squat"), context: c).map(\.name)
        #expect(!warm.contains("Jumping jacks"))
        #expect(warm.first == "March in place")
    }

    @Test func coolDownStretchesWhatWasTrained() {
        let c = libraryContext(equipment: [])
        let cool = WarmUps.coolDown(for: [.quads, .hamstrings], context: c)
        let areas = cool.compactMap { ExerciseCatalog.named($0.name) }.reduce(into: Set<BodyArea>()) { $0.formUnion($1.areas) }
        #expect(cool.count <= 3)
        #expect(areas.contains(.quads) || areas.contains(.hips))
        #expect(areas.contains(.hamstrings))
    }

    @Test func finishedPlansCarryWarmUpAndCoolDown() {
        let c = libraryContext(equipment: Set(Equipment.allCases))
        let plan = PlanFinisher.finish(focus: "Push", muscles: [.chest, .shoulders], reasons: [],
                                       exercises: planned("Dumbbell bench press", "Seated neutral-grip dumbbell press"),
                                       context: c, engine: "test")
        #expect(!plan.warmUp.isEmpty)
        #expect(!plan.coolDown.isEmpty)
        #expect(plan.exercises.allSatisfy { ExerciseCatalog.named($0.name)?.kind == .strength })
    }

    @Test func rampUpClimbsToTheWorkingWeight() {
        let squat = ExerciseCatalog.named("Back squat")!
        let steps = RampUp.steps(for: squat, target: LoadTarget(weight: 225, reps: 5, note: ""), unit: .lb)
        #expect(steps.map(\.weight) == [115, 160, 190])
        #expect(steps.map(\.reps) == [8, 5, 3])
    }

    @Test func noRampUpForLightOrSmallLifts() {
        let squat = ExerciseCatalog.named("Back squat")!
        let curl = ExerciseCatalog.named("Dumbbell curl")!
        #expect(RampUp.steps(for: squat, target: LoadTarget(weight: 55, reps: 5, note: ""), unit: .lb).isEmpty)
        #expect(RampUp.steps(for: curl, target: LoadTarget(weight: 30, reps: 10, note: ""), unit: .lb).isEmpty)
        #expect(RampUp.steps(for: squat, target: nil, unit: .lb).isEmpty)
    }
}

func libraryContext(equipment: Set<Equipment>, notes: [NoteSnapshot] = []) -> CoachContext {
    CoachContext(date: .now, isTrainingDay: true, trainingDaysThisWeek: 4, split: .coachDecides,
                 goal: "Build muscle", minutes: 48, gymName: "Test", equipment: equipment,
                 notes: notes, recent: [], readiness: [:], health: HealthSnapshot(), currentPlan: nil)
}
