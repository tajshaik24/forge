import Testing
import Foundation
@testable import FORGE

@Suite("Workout screen text")
struct WorkoutTextTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func set(_ weight: Double, _ reps: Int, _ i: Int) -> WorkoutProgress.DoneSet {
        .init(exercise: "Barbell bench press", weight: weight, reps: reps, rpe: 8, date: t0.addingTimeInterval(Double(i) * 120))
    }

    @Test func amountsReadNaturally() {
        #expect(WorkoutText.amount(weight: 135, reps: 8, timed: false, unit: .lb) == "135 lb × 8")
        #expect(WorkoutText.amount(weight: 0, reps: 12, timed: false, unit: .lb) == "12 reps")
        #expect(WorkoutText.amount(weight: 0, reps: 45, timed: true, unit: .lb) == "45 s")
        #expect(WorkoutText.amount(weight: 0, reps: 1, timed: false, unit: .lb) == "1 rep")
    }

    @Test func equipmentLabels() {
        #expect(WorkoutText.equipment(ExerciseCatalog.named("Barbell bench press")) == "Barbell")
        #expect(WorkoutText.equipment(ExerciseCatalog.named("Pec deck")) == "Machine")
        #expect(WorkoutText.equipment(ExerciseCatalog.named("Push-up")) == "Bodyweight")
        #expect(!WorkoutText.usesWeight(ExerciseCatalog.named("Pull-up")))
        #expect(WorkoutText.usesWeight(ExerciseCatalog.named("Cable fly")))
    }

    @Test func upcomingLiftInOneLine() {
        let lift = PlannedExercise(name: "Barbell bench press", sets: 3, reps: "6-10",
                                   target: LoadTarget(weight: 135, reps: 8, note: ""))
        #expect(WorkoutText.plan(lift, unit: .lb) == "3 × 6–10 · 135 lb")
    }

    @Test func finishedLiftSummaryShowsTheBestSet() {
        let p = WorkoutProgress(plan: PlannedWorkout(date: t0, focus: "Push", muscles: [], minutes: 0, reasons: [],
                                                     exercises: [PlannedExercise(name: "Barbell bench press", sets: 3, reps: "6-10")],
                                                     restSeconds: 90, gymName: "", engine: ""),
                                sets: [set(135, 8, 0), set(140, 8, 1), set(140, 6, 2)])
        #expect(WorkoutText.summary(p.lifts[0], timed: false, unit: .lb) == "3/3 · best 140 lb × 8")
    }

    @Test func sinceLastTime() {
        let last = [SetRecord(date: t0, weight: 135, reps: 8, rpe: 8)]
        let heavier = LoadTarget(weight: 140, reps: 6, note: "")
        let moreReps = LoadTarget(weight: 135, reps: 9, note: "")
        #expect(WorkoutText.sinceLastTime(target: heavier, before: last, timed: false, unit: .lb) == "+5 lb since last time")
        #expect(WorkoutText.sinceLastTime(target: moreReps, before: last, timed: false, unit: .lb)
                == "Same weight, 1 more rep than last time")
        #expect(WorkoutText.sinceLastTime(target: heavier, before: [], timed: false, unit: .lb) == nil)
    }

    @Test func aRecordIsCelebratedOnce() {
        let before = [SetRecord(date: t0.addingTimeInterval(-day), weight: 135, reps: 8, rpe: 8)]
        let kinds = WorkoutText.records([set(140, 8, 0), set(140, 8, 1)], before: before)
        #expect(kinds[0] == .heaviest)
        #expect(kinds[1] == nil)
    }

    @Test func theFirstTimeOnALiftHasNoRecords() {
        #expect(WorkoutText.records([set(100, 8, 0), set(105, 8, 1)], before: []).allSatisfy { $0 == nil })
    }
}

@Suite("AI coach wording")
struct SetCoachTests {
    @Test func keepsTheRulesNumbers() {
        let rule = "Easy at 8 reps: try 140 lb for set 2."
        #expect(SetCoach.keepsNumbers("That looked easy at 8, so go for 140 lb on set 2.", of: rule))
        #expect(!SetCoach.keepsNumbers("Try 145 lb for set 2 after those 8 reps.", of: rule))
        #expect(!SetCoach.keepsNumbers("Go heavier next set.", of: rule))
        // Leaving out how the last set went is fine; the next set's numbers are what matter.
        #expect(SetCoach.keepsNumbers("Go for 140 lb on set 2, that one looked easy.", of: rule))
        #expect(!SetCoach.keepsNumbers("Go for 140 lb on set 3.", of: rule))
    }

    @Test func tidiesReplies() {
        #expect(SetCoach.tidy("\"Nice work.\"\nSecond line") == "Nice work.")
        #expect(SetCoach.tidy("   ") == nil)
    }
}
