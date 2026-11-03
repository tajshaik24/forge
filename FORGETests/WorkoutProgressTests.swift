import Testing
import Foundation
@testable import FORGE

@Suite("Workout progress")
struct WorkoutProgressTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func set(_ name: String, _ weight: Double, _ reps: Int, _ rpe: Int?, _ i: Int) -> WorkoutProgress.DoneSet {
        .init(exercise: name, weight: weight, reps: reps, rpe: rpe, date: t0.addingTimeInterval(Double(i) * 120))
    }

    private func plan(_ lifts: [PlannedExercise]) -> PlannedWorkout {
        PlannedWorkout(date: t0, focus: "Push", muscles: [.chest], minutes: 45, reasons: [], exercises: lifts,
                       restSeconds: 90, gymName: "Gym", engine: "test")
    }

    @Test func countsWorkingSetsAndMovesOnWhenALiftIsDone() {
        let p = WorkoutProgress(plan: plan([PlannedExercise(name: "Barbell bench press", sets: 2, reps: "6-10"),
                                            PlannedExercise(name: "Barbell row", sets: 3, reps: "6-10")]),
                                sets: [set("Barbell bench press", 135, 8, 8, 0), set("Barbell bench press", 135, 8, 8, 1)])
        #expect(p.lifts[0].isDone)
        #expect(p.lifts[0].nextSet == 2)   // never "3 of 2"
        #expect(p.current(from: 0) == 1)
        #expect(p.setsDone == 2 && p.setsPlanned == 5)
        #expect(!p.isComplete)
    }

    @Test func testSetsDontCountTowardTheWeightTestLift() {
        var bench = PlannedExercise(name: "Barbell bench press", sets: 3, reps: "6-10")
        bench.calibrate = true
        let p = WorkoutProgress(plan: plan([bench]), sets: [
            set("Barbell bench press", 45, 5, Effort.easy.rpe, 0),     // test
            set("Barbell bench press", 95, 5, Effort.good.rpe, 1),     // test that found the weight
            set("Barbell bench press", 115, 6, 8, 2),                  // working set 1
        ])
        #expect(p.lifts[0].tests.count == 2)
        #expect(p.lifts[0].working.count == 1)
        #expect(p.lifts[0].testFound)
        #expect(!p.lifts[0].isTesting)
    }

    @Test func aSkippedRatingCountsAsGood() {
        var bench = PlannedExercise(name: "Barbell bench press", sets: 3, reps: "6-10")
        bench.calibrate = true
        let p = WorkoutProgress(plan: plan([bench]), sets: [set("Barbell bench press", 95, 5, nil, 0)])
        #expect(p.lifts[0].testFound)
    }

    @Test func comesBackToASkippedLift() {
        let p = WorkoutProgress(plan: plan([PlannedExercise(name: "Barbell bench press", sets: 1, reps: "8"),
                                            PlannedExercise(name: "Barbell row", sets: 1, reps: "8")]),
                                sets: [set("Barbell row", 115, 8, 8, 0)])
        #expect(p.current(from: 1) == 0)
        #expect(p.current(from: 0) == 0)
    }
}

@Suite("The coach between sets")
struct NextSetTests {
    private let bench = ExerciseCatalog.named("Barbell bench press")!

    private func after(_ weight: Double, _ reps: Int, _ effort: Effort) -> NextSet.Call {
        NextSet.after(.init(exercise: bench.name, weight: weight, reps: reps, rpe: effort.rpe, date: .now),
                      exercise: bench, target: LoadTarget(weight: 135, reps: 8, note: ""), setNumber: 2,
                      goal: .buildMuscle, unit: .lb)
    }

    @Test func easyAddsWeight() { #expect(after(135, 8, .easy).weight == 140) }
    @Test func goodHolds() { #expect(after(135, 8, .good).weight == 135) }
    @Test func hardAtTheTargetDrops() { #expect(after(135, 8, .hard).weight < 135) }
    @Test func missingTheRangeDropsMore() { #expect(after(135, 4, .good).weight <= 120) }
    @Test func theNoteSaysWhy() { #expect(after(135, 8, .easy).note.contains("140 lb")) }
}

@Suite("Personal records")
struct PersonalRecordTests {
    private let day = TimeInterval(86_400)

    @Test func heavierThanEverIsARecord() {
        let history = [SetRecord(date: .init(timeIntervalSince1970: 0), weight: 135, reps: 8, rpe: 8)]
        let new = SetRecord(date: .init(timeIntervalSince1970: day), weight: 140, reps: 5, rpe: 9)
        #expect(PersonalRecords.broken(by: new, history: history) == .heaviest)
    }

    @Test func moreRepsAtTheSameWeightBeatsTheEstimatedMax() {
        let history = [SetRecord(date: .init(timeIntervalSince1970: 0), weight: 135, reps: 8, rpe: 8)]
        let new = SetRecord(date: .init(timeIntervalSince1970: day), weight: 135, reps: 10, rpe: 9)
        #expect(PersonalRecords.broken(by: new, history: history) == .estimatedMax)
    }

    @Test func theFirstTimeIsntARecord() {
        #expect(PersonalRecords.broken(by: SetRecord(date: .now, weight: 135, reps: 8, rpe: 8), history: []) == nil)
    }
}
