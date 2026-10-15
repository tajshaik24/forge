import Testing
import Foundation
import SwiftData
@testable import FORGE

@MainActor
@Suite("Moving workouts between days")
struct MoveDayTests {
    private let cal = Calendar.current

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: .now))!
    }

    private func workout(_ focus: String, on date: Date) -> PlannedWorkout {
        PlannedWorkout(date: date, focus: focus, muscles: [.back], minutes: 45, reasons: [],
                       exercises: [PlannedExercise(name: "Lat pulldown", sets: 3, reps: "8-12")],
                       restSeconds: 90, gymName: "Home", engine: "test")
    }

    private func store() throws -> (CoachStore, ModelContext) {
        let config = ModelConfiguration(schema: DataStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: DataStore.schema, configurations: [config])
        return (CoachStore(), ModelContext(container))
    }

    private func plan(on date: Date, _ ctx: ModelContext) -> PlannedWorkout? {
        DataStore.todayPlan(in: ctx, date: date)?.plan
    }

    @Test func movingToAnEmptyDayLeavesARestDayBehind() throws {
        let (coach, ctx) = try store()
        DataStore.save(workout("Pull", on: day(1)), in: ctx)
        coach.move(from: day(1), to: day(2), ctx)
        #expect(plan(on: day(2), ctx)?.focus == "Pull")
        #expect(plan(on: day(1), ctx)?.isRestDay == true)   // so week planning won't refill it
    }

    @Test func movingOntoAWorkoutSwapsThem() throws {
        let (coach, ctx) = try store()
        DataStore.save(workout("Pull", on: day(1)), in: ctx)
        DataStore.save(workout("Legs", on: day(2)), in: ctx)
        coach.move(from: day(1), to: day(2), ctx)
        #expect(plan(on: day(2), ctx)?.focus == "Pull")
        #expect(plan(on: day(1), ctx)?.focus == "Legs")
    }

    @Test func movedPlansCarryTheirNewDate() throws {
        let (coach, ctx) = try store()
        DataStore.save(workout("Pull", on: day(1)), in: ctx)
        coach.move(from: day(1), to: day(3), ctx)
        #expect(plan(on: day(3), ctx).map { cal.isDate($0.date, inSameDayAs: day(3)) } == true)
    }

    @Test func restDayReplacesTheWorkout() throws {
        let (coach, ctx) = try store()
        DataStore.save(workout("Pull", on: day(1)), in: ctx)
        coach.makeRestDay(day(1), ctx)
        #expect(plan(on: day(1), ctx)?.isRestDay == true)
        #expect(DataStore.upcomingPlans(in: ctx).contains { $0.isRestDay })   // counts as "planned" for the week pass
    }
}
