import Testing
import Foundation
@testable import FORGE

// Run with ⌘U in Xcode, or: xcodebuild test -scheme FORGE -destination 'platform=iOS Simulator,name=iPhone 17'

private let day: TimeInterval = 86_400

private func sets(_ weight: Double, _ reps: [Int], rpe: Int? = 8, daysAgo: Double = 2) -> [SetRecord] {
    let date = Date().addingTimeInterval(-daysAgo * day)
    return reps.map { SetRecord(date: date, weight: weight, reps: $0, rpe: rpe) }
}

private let legPress = ExerciseCatalog.named("Leg press")!
private let curl = ExerciseCatalog.named("Dumbbell curl")!
private let pushUp = ExerciseCatalog.named("Push-up")!

@Suite("Progressive overload")
struct ProgressionTests {
    @Test func noHistoryMeansNoTarget() {
        #expect(Progression.target(for: legPress, history: []) == nil)
    }

    @Test func hittingTopOfRangeAddsWeight() throws {
        // Leg press is 8-12; every set hit 12 at RPE 8 -> add the lower-body jump (10 lb).
        let t = try #require(Progression.target(for: legPress, history: sets(250, [12, 12, 12])))
        #expect(t.weight == 260)
        #expect(t.reps == 8)
    }

    @Test func isolationGetsSmallerJump() throws {
        let t = try #require(Progression.target(for: curl, history: sets(30, [12, 12, 12])))
        #expect(t.weight == 35)
    }

    @Test func insideRangeHoldsWeightAndAddsARep() throws {
        let t = try #require(Progression.target(for: legPress, history: sets(250, [10, 10, 9])))
        #expect(t.weight == 250)
        #expect(t.reps == 10)
    }

    @Test func missingBottomOfRangeBacksOff() throws {
        let t = try #require(Progression.target(for: legPress, history: sets(250, [7, 6, 6])))
        #expect(t.weight < 250)
        #expect(t.reps == 8)
    }

    @Test func holdBackSignalBlocksIncrease() throws {
        let t = try #require(Progression.target(for: legPress, history: sets(250, [12, 12, 12]), signal: .holdBack))
        #expect(t.weight == 250)
    }

    @Test func maxEffortAtTopDoesNotIncreaseWithoutPush() throws {
        let t = try #require(Progression.target(for: legPress, history: sets(250, [12, 12, 12], rpe: 10)))
        #expect(t.weight == 250)
    }

    @Test func onlyMostRecentSessionCounts() throws {
        let old = sets(300, [5, 5, 5], daysAgo: 20)
        let recent = sets(250, [12, 12, 12], daysAgo: 2)
        let t = try #require(Progression.target(for: legPress, history: old + recent))
        #expect(t.weight == 260)
    }

    @Test func bodyweightProgressesReps() throws {
        let t = try #require(Progression.target(for: pushUp, history: sets(0, [20, 20])))
        #expect(t.weight == 0)
        #expect(t.reps == 21)
    }

    @Test func kilogramJumpsAreMetric() throws {
        let start = WeightUnit.kg.toPounds(100)
        let t = try #require(Progression.target(for: legPress, history: sets(start, [12, 12, 12]), unit: .kg))
        #expect(WeightUnit.kg.format(pounds: t.weight) == "105 kg")
    }

    @Test func epley() {
        #expect(Progression.estimatedOneRepMax(weight: 100, reps: 1) == 100)
        #expect(abs(Progression.estimatedOneRepMax(weight: 100, reps: 10) - 133.33) < 0.01)
    }
}

@Suite("Parsing and units")
struct ParsingTests {
    @Test(arguments: [("8-12", 8...12), ("10/leg", 10...10), ("8-10/leg", 8...10), ("12", 12...12), ("", 8...12)])
    func repRanges(text: String, expected: ClosedRange<Int>) {
        #expect(RepRange.parse(text) == expected)
    }

    @Test func unitRoundTrip() {
        let lb = WeightUnit.kg.toPounds(60)
        #expect(abs(WeightUnit.kg.fromPounds(lb) - 60) < 0.0001)
        #expect(WeightUnit.lb.format(pounds: 135) == "135 lb")
    }

    @Test func dayMatcherFindsWeekdays() throws {
        let saturday = try #require(DayMatcher.date(in: "make saturday shorter"))
        #expect(Calendar.current.component(.weekday, from: saturday) == 7)
        #expect(saturday > Date())
        #expect(DayMatcher.date(in: "only 30 minutes") == nil)
    }
}

@Suite("Readiness")
struct ReadinessTests {
    @Test func freshMusclesAreReady() {
        let r = Readiness.compute(from: [])
        #expect(MuscleGroup.allCases.allSatisfy { r[$0] == 1 })
    }

    @Test func recentHardSessionLowersReadinessThenRecovers() {
        let s = SessionSummary(date: Date().addingTimeInterval(-6 * 3600), focus: "Legs", setsByMuscle: [.quads: 12])
        let now = Readiness.compute(from: [s])
        let later = Readiness.compute(from: [s], now: Date().addingTimeInterval(3 * day))
        #expect((now[.quads] ?? 1) < 0.3)
        #expect(later[.quads] == 1)
        #expect(now[.chest] == 1)
    }
}

@Suite("Plan finishing")
struct PlanFinisherTests {
    private func context(equipment: Set<Equipment>, notes: [NoteSnapshot] = [], experience: Experience = .intermediate,
                         feel: [String] = []) -> CoachContext {
        var c = CoachContext(date: .now, isTrainingDay: true, trainingDaysThisWeek: 4, split: .coachDecides,
                             goal: "Build muscle", minutes: 48, gymName: "Test", equipment: equipment,
                             notes: notes, recent: [], readiness: [:], health: HealthSnapshot(), currentPlan: nil)
        c.experience = experience
        c.recentFeel = feel
        return c
    }

    @Test func dropsExercisesTheGymCantDo() {
        let c = context(equipment: [.dumbbells, .bench])
        let plan = PlanFinisher.finish(focus: "Legs", muscles: [.quads, .hamstrings],
                                       reasons: ["x"], exercises: [PlannedExercise(name: "Leg press", sets: 3, reps: "8-12")],
                                       context: c, engine: "test")
        #expect(!plan.exercises.contains { $0.name == "Leg press" })
        #expect(!plan.exercises.isEmpty)
        #expect(plan.exercises.allSatisfy { ExerciseCatalog.named($0.name)!.equipment.isSubset(of: [.dumbbells, .bench]) })
    }

    @Test func respectsNotes() {
        let note = NoteSnapshot(said: "Squats make me lightheaded", rule: "No heavy standing squats", avoid: [.axialLoading, .standingHeavy])
        let c = context(equipment: Set(Equipment.allCases), notes: [note])
        let plan = PlanFinisher.finish(focus: "Legs", muscles: [.quads, .hamstrings, .glutes],
                                       reasons: [], exercises: [PlannedExercise(name: "Back squat", sets: 4, reps: "5-8")],
                                       context: c, engine: "test")
        #expect(!plan.exercises.contains { $0.name == "Back squat" })
        #expect(plan.restSeconds > 90)
    }

    @Test func clampsSetsToExperience() {
        let c = context(equipment: Set(Equipment.allCases), experience: .new)
        let plan = PlanFinisher.finish(focus: "Push", muscles: [.chest],
                                       reasons: [], exercises: [PlannedExercise(name: "Dumbbell bench press", sets: 5, reps: "8-10")],
                                       context: c, engine: "test")
        #expect(plan.exercises.allSatisfy { Experience.new.setRange.contains($0.sets) })
    }

    @Test func hardFeelingAddsReason() {
        let c = context(equipment: Set(Equipment.allCases), feel: ["hard"])
        #expect(c.signal == .holdBack)
        let plan = PlanFinisher.finish(focus: "Push", muscles: [.chest, .triceps], reasons: ["Chest is recovered."],
                                       exercises: [], context: c, engine: "test")
        #expect(plan.reasons.contains { $0.contains("too hard") })
    }
}
