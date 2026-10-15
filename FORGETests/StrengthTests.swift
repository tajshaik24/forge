import Testing
import Foundation
@testable import FORGE

@Suite("First Heat")
struct StrengthTests {
    private let bench = ExerciseCatalog.named("Barbell bench press")!
    private let curl = ExerciseCatalog.named("Dumbbell curl")!

    private func set(_ weight: Double, _ reps: Int, rpe: Int?, daysAgo: Double = 0) -> SetRecord {
        SetRecord(date: Date().addingTimeInterval(-daysAgo * 86_400), weight: weight, reps: reps, rpe: rpe)
    }

    @Test func estimatedMaxCountsRepsInTheTank() {
        // 135 × 5 with two left is like 7 reps to failure.
        #expect(abs(Strength.estimatedMax(weight: 135, reps: 5, rpe: 8) - 166.5) < 0.01)
        #expect(Strength.estimatedMax(weight: 135, reps: 5, rpe: 10) < Strength.estimatedMax(weight: 135, reps: 5, rpe: 8))
    }

    @Test func goalsSetTheRepRange() {
        #expect(RepScheme.range(for: bench, goal: .getStronger) == 3...6)
        #expect(RepScheme.range(for: bench, goal: .buildMuscle) == 6...10)
        #expect(RepScheme.range(for: curl, goal: .buildMuscle) == 10...15)
        #expect(RepScheme.rest(for: .loseFat) < RepScheme.rest(for: .getStronger))
        // Bodyweight and timed moves keep their own dose.
        #expect(RepScheme.reps(for: ExerciseCatalog.named("Push-up")!, goal: .getStronger) == "10-20")
        #expect(RepScheme.reps(for: ExerciseCatalog.named("Plank")!, goal: .getStronger) == "30-45 s")
    }

    @Test func easyTestSetsClimb() {
        #expect(Calibration.nextWeight(after: 95, rpe: 6, unit: .lb) == 115)   // +20 %
        #expect(Calibration.nextWeight(after: 95, rpe: 7, unit: .lb) == 105)   // +10 %
        #expect(Calibration.nextWeight(after: 135, rpe: 8, unit: .lb) == nil)  // found it
    }

    @Test func testFindsWorkingWeightForTheGoal() throws {
        let tests = [set(95, 5, rpe: 6), set(115, 5, rpe: 7), set(135, 5, rpe: 8)]
        let muscle = try #require(Calibration.result(for: bench, sets: tests, goal: .buildMuscle, unit: .lb))
        #expect(muscle.tested.weight == 135)
        #expect(muscle.working.weight == 130 && muscle.working.reps == 6)
        let strength = try #require(Calibration.result(for: bench, sets: tests, goal: .getStronger, unit: .lb))
        #expect(strength.working.weight == 140 && strength.working.reps == 3)
        #expect(Calibration.result(for: bench, sets: Array(tests.prefix(2)), goal: .buildMuscle, unit: .lb) == nil)
    }

    @Test func nextSessionAfterATestUsesTheEstimatedMax() throws {
        // Test week: 135 × 5 at RPE 8. Building muscle next time means 6-10 reps, not "lighter, you missed".
        let t = try #require(Progression.target(for: bench, history: [set(135, 5, rpe: 8, daysAgo: 3)], goal: .buildMuscle))
        #expect(t.weight == 130)
        #expect(t.reps == 6)
    }

    @Test func changingGoalReworksTheWeight() throws {
        // Was training for muscle at 115 × 10; switching to strength moves to heavy triples.
        let history = [set(115, 10, rpe: 8, daysAgo: 2), set(115, 10, rpe: 8, daysAgo: 2)]
        let t = try #require(Progression.target(for: bench, history: history, goal: .getStronger))
        #expect(t.reps == 3)
        #expect(t.weight > 115)
    }

    @Test func newWeightedLiftsGetTestSets() {
        let c = libraryContext(equipment: Set(Equipment.allCases))
        let plan = PlanFinisher.finish(focus: "Push", muscles: [.chest], reasons: [],
                                       exercises: [PlannedExercise(name: "Barbell bench press", sets: 3, reps: "8"),
                                                   PlannedExercise(name: "Push-up", sets: 3, reps: "10")],
                                       context: c, engine: "test")
        let bench = plan.exercises.first { $0.name == "Barbell bench press" }
        #expect(bench?.calibrate == true)
        #expect(bench?.reps == "6-10")
        #expect(plan.exercises.first { $0.name == "Push-up" }?.calibrate == nil)
        #expect(plan.reasons.first?.contains("First Heat") == true)
    }
}
