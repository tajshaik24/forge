import Testing
import Foundation
@testable import FORGE

@Suite("Sets of the workout under way")
struct WorkoutSetsTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func set(_ name: String, _ weight: Double, _ reps: Int, at minute: Double, rpe: Int? = 8) -> WorkoutProgress.DoneSet {
        .init(exercise: name, weight: weight, reps: reps, rpe: rpe, date: start.addingTimeInterval(minute * 60))
    }

    private func plan(_ lifts: [PlannedExercise]) -> PlannedWorkout {
        PlannedWorkout(date: start, focus: "Push", muscles: [.chest], minutes: 45, reasons: [], exercises: lifts,
                       restSeconds: 90, gymName: "Gym", engine: "test")
    }

    @Test func aStoredCopyOfASetLoggedHereCountsOnce() {
        let mine = set("Barbell bench press", 135, 8, at: 5)
        // Saved here when the iPhone couldn't be reached, a second later.
        let copy = set("Barbell bench press", 135, 8, at: 5.02)
        let all = WorkoutSets.combine(own: [mine], remote: [], stored: [copy], since: start)
        #expect(all.count == 1)
    }

    @Test func iCloudCopiesOfBothDevicesSetsCountOnce() {
        let mine = set("Barbell bench press", 135, 8, at: 5)
        let phone = set("Barbell row", 115, 8, at: 9)
        let synced = [set("Barbell bench press", 135, 8, at: 5.1), set("Barbell row", 115, 8, at: 9.05)]
        let all = WorkoutSets.combine(own: [mine], remote: [phone], stored: synced, since: start)
        #expect(all.count == 2)
    }

    @Test func twoRealSetsOfTheSameWeightBothCount() {
        let own = [set("Barbell bench press", 135, 8, at: 5), set("Barbell bench press", 135, 8, at: 6)]
        // Both stored too: each copy matches one set, not both copies the first.
        let stored = [set("Barbell bench press", 135, 8, at: 5.05), set("Barbell bench press", 135, 8, at: 6.05)]
        #expect(WorkoutSets.combine(own: own, remote: [], stored: stored, since: start).count == 2)
        // After a relaunch only the stored sets are left: both still count.
        #expect(WorkoutSets.combine(own: [], remote: [], stored: stored, since: start).count == 2)
    }

    @Test func aSetOnlyInTheStoreCounts() {
        let all = WorkoutSets.combine(own: [set("Barbell bench press", 135, 8, at: 5)], remote: [],
                                      stored: [set("Barbell bench press", 135, 6, at: 5.05)], since: start)
        #expect(all.count == 2)   // different reps: a different set
    }

    @Test func setsFromAnEarlierWorkoutTodayDontCount() {
        let earlier = set("Barbell bench press", 135, 8, at: -120)
        let all = WorkoutSets.combine(own: [], remote: [], stored: [earlier, set("Barbell row", 115, 8, at: 3)], since: start)
        #expect(all.map(\.exercise) == ["Barbell row"])
    }

    @Test func aBurstFromTheIPhoneAllCounts() {
        let burst = (0..<3).map { set("Barbell row", 115, 8, at: 4 + Double($0) * 0.2) }
        let p = WorkoutProgress(plan: plan([PlannedExercise(name: "Barbell row", sets: 3, reps: "8")]),
                                sets: WorkoutSets.combine(own: [], remote: burst, stored: [], since: start))
        #expect(p.lifts[0].isDone)
    }

    @Test func skippingMovesOnAndComesBack() {
        let p = WorkoutProgress(plan: plan([PlannedExercise(name: "A", sets: 1, reps: "8"),
                                            PlannedExercise(name: "B", sets: 1, reps: "8"),
                                            PlannedExercise(name: "C", sets: 1, reps: "8")]),
                                sets: [set("B", 0, 8, at: 1)])
        #expect(WorkoutSets.lift(after: 0, in: p) == 2)   // B is done
        #expect(WorkoutSets.lift(after: 2, in: p) == 0)   // back to the skipped one
    }

    @Test func resumesAtTheLiftOfTheLastSetOrAllDone() {
        let lifts = [PlannedExercise(name: "A", sets: 2, reps: "8"), PlannedExercise(name: "B", sets: 1, reps: "8")]
        let midB = [set("B", 0, 8, at: 1), set("A", 0, 8, at: 2)]
        let p = WorkoutProgress(plan: plan(lifts), sets: midB)
        #expect(WorkoutSets.resumeLift(in: p, sets: midB) == 0)
        let all = midB + [set("A", 0, 8, at: 3)]
        #expect(WorkoutSets.resumeLift(in: WorkoutProgress(plan: plan(lifts), sets: all), sets: all) == nil)
    }

    @Test func aSetFromTheOtherDeviceKeepsItsEffort() {
        let logged = LoggedSet(exercise: "Barbell row", weight: 115, reps: 8, rpe: Effort.hard.rpe,
                               start: start, end: start.addingTimeInterval(40))
        let done = WorkoutProgress.DoneSet(logged)
        #expect(done.rpe == 10 && done.date == logged.end)
    }
}

@Suite("Watch context")
struct WatchContextTests {
    @Test func contextsFromOlderIPhonesHaveNoWeek() throws {
        let old = #"{"unit":"lb"}"#.data(using: .utf8)!
        let context = try JSONDecoder().decode(PhoneWatchLink.Context.self, from: old)
        #expect(context.week.isEmpty && context.plan == nil)
    }

    @Test func theWeekRoundTrips() throws {
        let day = PlannedWorkout.rest(on: .now, gymName: "Gym", engine: "test")
        let data = try JSONEncoder().encode(PhoneWatchLink.Context(plan: nil, unit: .kg, week: [day]))
        let back = try JSONDecoder().decode(PhoneWatchLink.Context.self, from: data)
        #expect(back.week.count == 1 && back.unit == .kg)
    }
}
