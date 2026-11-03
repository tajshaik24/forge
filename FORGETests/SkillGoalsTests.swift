import Testing
import Foundation
@testable import FORGE

@Suite("Skill goals")
struct SkillGoalsTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let fullGym = Set(Equipment.allCases)

    private func sets(_ name: String, reps: [Int], rpe: Int? = 8, day: Int) -> [WorkoutProgress.DoneSet] {
        reps.enumerated().map { i, r in
            .init(exercise: name, weight: 0, reps: r, rpe: rpe, date: t0.addingTimeInterval(Double(day) * 86_400 + Double(i) * 120))
        }
    }

    private func day(_ n: Int) -> Date { t0.addingTimeInterval(Double(n) * 86_400 + 3_600) }

    @Test func chatFindsLiftsWithALadder() {
        #expect(Set(SkillLadder.targets(in: "I can't do a pull up or a chin up")) == ["Pull-up", "Chin-up"])
        #expect(SkillLadder.targets(in: "I love pull-ups").isEmpty)
        #expect(SkillLadder.targets(in: "squats hurt my knee").isEmpty)
    }

    @Test func everyLadderStepIsInTheCatalog() {
        for ladder in SkillLadder.all {
            #expect(ExerciseCatalog.named(ladder.target) != nil)
            for step in ladder.steps { for name in step.options { #expect(ExerciseCatalog.named(name) != nil, "\(name)") } }
            #expect(ladder.steps.last?.options == [ladder.target])
        }
    }

    @Test func movesUpAfterTwoGoodSessions() {
        var goal = SkillGoal(target: "Pull-up", started: t0)
        #expect(goal.record(sets("Inverted row", reps: [12, 12, 12], day: 1), on: day(1)) == .progress(passes: 1, needed: 2))
        #expect(goal.step == 0)
        #expect(goal.record(sets("Inverted row", reps: [12, 13, 12], day: 3), on: day(3)) == .movedUp(to: "Band-assisted pull-up"))
        #expect(goal.step == 1 && goal.passes == 0)
    }

    @Test func shortOrHardSetsDontCount() {
        var goal = SkillGoal(target: "Pull-up", started: t0)
        _ = goal.record(sets("Inverted row", reps: [12, 12, 10], day: 1), on: day(1))
        _ = goal.record(sets("Inverted row", reps: [12, 12, 12], rpe: 10, day: 2), on: day(2))
        _ = goal.record(sets("Inverted row", reps: [12, 12], day: 3), on: day(3))
        #expect(goal.step == 0 && goal.passes == 0)
    }

    @Test func aWorkoutCountsOnce() {
        var goal = SkillGoal(target: "Pull-up", started: t0)
        let s = sets("Inverted row", reps: [12, 12, 12], day: 1)
        _ = goal.record(s, on: day(1))
        #expect(goal.record(s, on: day(1)) == .unchanged)
        #expect(goal.passes == 1)
    }

    @Test func aRealRepJumpsToTheLastStepAndFinishingAchieves() {
        var goal = SkillGoal(target: "Pull-up", step: 1, started: t0)
        #expect(goal.record(sets("Pull-up", reps: [1], day: 1), on: day(1)) == .firstRep)
        #expect(goal.isOnTarget)
        #expect(goal.record(sets("Pull-up", reps: [5, 5, 5], day: 2), on: day(2)) == .achieved)
    }

    @Test func planLeadsWithTheStepOnBackDaysOnly() {
        let goal = SkillGoal(target: "Pull-up", step: 2, started: t0)
        var pull = [PlannedExercise(name: "Lat pulldown", sets: 3, reps: "8-12"),
                    PlannedExercise(name: "Seated cable row", sets: 3, reps: "10-12")]
        let why = SkillGoal.apply([goal], to: &pull, muscles: [.back, .biceps], gym: fullGym, avoiding: []) { _ in nil }
        #expect(pull.map(\.name) == ["Negative pull-up", "Lat pulldown", "Seated cable row"])
        #expect(pull[0].goal == "Step 3 of 4 toward a pull-up")
        #expect(why.count == 1)

        // Step one is a row: it leads, and the planner's own pull-up stand-ins make way.
        var early = [PlannedExercise(name: "Band-assisted pull-up", sets: 3, reps: "5-8"),
                     PlannedExercise(name: "Negative pull-up", sets: 3, reps: "3-5"),
                     PlannedExercise(name: "Lat pulldown", sets: 3, reps: "8-12")]
        _ = SkillGoal.apply([SkillGoal(target: "Pull-up", started: t0)], to: &early, muscles: [.back], gym: fullGym, avoiding: []) { _ in nil }
        #expect(early.map(\.name) == ["Inverted row", "Lat pulldown"])

        var push = [PlannedExercise(name: "Barbell bench press", sets: 3, reps: "6-10")]
        #expect(SkillGoal.apply([goal], to: &push, muscles: [.chest, .triceps], gym: fullGym, avoiding: []) { _ in nil }.isEmpty)
        #expect(push.map(\.name) == ["Barbell bench press"])
    }

    @Test func usesWhatTheGymHas() {
        let goal = SkillGoal(target: "Pull-up", step: 0, started: t0)
        let noRack: Set<Equipment> = [.cableStack, .pullUpBar, .dumbbells, .bench]
        #expect(goal.exercise(gym: noRack, avoiding: [])?.name == "Lat pulldown")
        #expect(goal.exercise(gym: [.dumbbells], avoiding: []) == nil)
    }

    @Test func bodyweightBarLiftsDontRunAWeightTest() {
        for name in ["Pull-up", "Negative pull-up", "Band-assisted chin-up", "Inverted row", "Dip", "Bench dip"] {
            let ex = ExerciseCatalog.named(name)!
            #expect(ex.isBodyweight, "\(name)")
            #expect(!Calibration.applies(to: ex), "\(name)")
        }
        #expect(!ExerciseCatalog.named("Lat pulldown")!.isBodyweight)
    }
}
