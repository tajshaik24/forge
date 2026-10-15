import Testing
import Foundation
@testable import FORGE

@Suite("Coach notes stay specific")
struct CoachNoteTests {
    private func context(notes: [NoteSnapshot]) -> CoachContext {
        CoachContext(date: .now, isTrainingDay: true, trainingDaysThisWeek: 4, split: .coachDecides,
                     goal: "Build muscle", minutes: 48, gymName: "Test", equipment: Set(Equipment.allCases),
                     notes: notes, recent: [], readiness: [:], health: HealthSnapshot(), currentPlan: nil)
    }

    /// The note the model actually saved on a real device for this message.
    private let pullUpNote = NoteSnapshot(said: "I can’t do a pull up, and would love to work towards it",
                                          rule: "No heavy pulling; use assisted support to build confidence.",
                                          avoid: Set(MovementFlag.allCases))

    @Test func pullUpNoteRulesOutOnlyPullUps() {
        let checked = pullUpNote.checked()
        #expect(checked.avoid.isEmpty)
        #expect(checked.exercises == ["Pull-up"])
    }

    @Test func realLimitsKeepTheirFlags() {
        let note = NoteSnapshot(said: "Squats make me lightheaded", rule: "No heavy standing squats",
                                avoid: [.axialLoading, .standingHeavy, .jumping]).checked()
        #expect(note.avoid == [.axialLoading, .standingHeavy])
    }

    @Test func positiveMentionsDontRuleAnythingOut() {
        #expect(ExerciseCatalog.limited(in: "I love pull-ups").isEmpty)
        #expect(ExerciseCatalog.limited(in: "Lat pulldowns hurt my shoulder") == ["Lat pulldown"])
    }

    @Test(arguments: ["pull ups", "Pullup", "pull-up", "PULL UPS"])
    func matchesLooseNames(_ text: String) {
        #expect(ExerciseCatalog.match(text)?.name == "Pull-up")
    }

    @Test func longerNamesWin() {
        #expect(ExerciseCatalog.mentioned(in: "band assisted pull ups are hard") == ["Band-assisted pull-up"])
    }

    @Test func easierVersionsReplaceTheLimitedLift() {
        let c = context(notes: [pullUpNote.checked()])
        #expect(!c.pool.contains { $0.name == "Pull-up" })
        #expect(c.pool.contains { $0.name == "Band-assisted pull-up" })
        #expect(c.pool.contains { $0.name == "Lat pulldown" })   // the rest of the back is untouched

        let plan = PlanFinisher.finish(focus: "Pull", muscles: [.back, .biceps], reasons: [],
                                       exercises: [PlannedExercise(name: "Pull-up", sets: 3, reps: "5-10"),
                                                   PlannedExercise(name: "Negative pull-up", sets: 3, reps: "3-5"),
                                                   PlannedExercise(name: "Lat pulldown", sets: 3, reps: "8-12")],
                                       context: c, engine: "test")
        #expect(!plan.exercises.contains { $0.name == "Pull-up" })
        #expect(plan.exercises.first { $0.name == "Negative pull-up" }?.replaces == "Pull-up")
        #expect(plan.restSeconds == 90)   // no cautious rest for a pull-up note
    }

    @Test func boilerplateCuesAreDropped() {
        let cue = "Use assisted support as coach notes require."
        let plan = PlanFinisher.finish(focus: "Pull", muscles: [.back], reasons: [],
                                       exercises: [PlannedExercise(name: "Lat pulldown", sets: 3, reps: "8-12", cue: cue),
                                                   PlannedExercise(name: "Seated cable row", sets: 3, reps: "10-12", cue: cue),
                                                   PlannedExercise(name: "One-arm dumbbell row", sets: 3, reps: "8-12", cue: cue),
                                                   PlannedExercise(name: "Chest-supported dumbbell row", sets: 3, reps: "8-12",
                                                                   cue: "Keep your chest on the pad")],
                                       context: context(notes: []), engine: "test")
        #expect(plan.exercises.filter { $0.cue == cue }.isEmpty)
        #expect(plan.exercises.contains { $0.cue == "Keep your chest on the pad" })
    }

    @Test func everyCatalogExerciseHasAFormGuide() {
        for ex in ExerciseCatalog.builtIn { #expect(FormGuides.guide(for: ex.name) != nil, "\(ex.name)") }
    }
}
