import Testing
import Foundation
@testable import FORGE

/// The checks between the model's reading of a chat message and what the app does. The model's
/// fields here are deliberately wrong in the ways the on-device model got them wrong in testing.
@Suite("Chat decisions")
struct ChatDecisionTests {
    private func context() -> CoachContext {
        CoachContext(date: .now, isTrainingDay: true, trainingDaysThisWeek: 4, split: .coachDecides, goal: "Build muscle",
                     minutes: 45, gymName: "Gym", equipment: Set(Equipment.allCases), notes: [], recent: [], readiness: [:],
                     health: HealthSnapshot(), currentPlan: nil)
    }

    private func decide(_ message: String, kind: ChatDecision.Kind = .other, exercises: [String] = [], buildToward: [String] = [],
                        remember: Bool = false, rule: String = "", avoid: Set<MovementFlag> = [], restDay: Bool = false,
                        minutes: Int = 0, reply: String = "OK.") -> CoachReply {
        ChatDecision.make(message: message, context: context(), reply: reply,
                          fields: .init(kind: kind, exercises: exercises, buildToward: buildToward, remember: remember,
                                        rule: rule, avoid: avoid, restDay: restDay, minutes: minutes, day: nil))
    }

    @Test func questionsChangeNothing() {
        let r = decide("I've never done a barbell squat, is it safe?", kind: .limitation, exercises: ["Back squat"],
                       remember: true, rule: "Avoid heavy standing lifts", avoid: [.standingHeavy], minutes: 45)
        #expect(r.note == nil && !r.shouldReplan && r.minutesOverride == nil)
        #expect(decide("why am I doing inverted rows?", kind: .question, buildToward: ["Inverted row"]).goalOffers.isEmpty)
    }

    @Test func feelingsAndSmallTalkAreNotNotes() {
        #expect(decide("that workout was brutal", kind: .feedback, remember: true, rule: "No heavy standing lifts").note == nil)
        #expect(decide("thanks coach!", remember: true, rule: "Stick to light lifts").note == nil)
        #expect(decide("I'm traveling next week", kind: .schedule, exercises: ["Pull-up"], remember: true).note == nil)
    }

    @Test func painIsRememberedEvenWhenTheModelMissesIt() {
        let r = decide("dips hurt my shoulder", kind: .feedback)
        #expect(r.note?.exercises == ["Dip"])
        #expect(r.goalOffers.isEmpty)
        let dizzy = decide("deadlifts make me lightheaded")
        #expect(dizzy.note?.avoid == [.standingHeavy, .axialLoading])
        #expect(dizzy.note?.exercises == ["Barbell deadlift"])
        let back = decide("I tweaked my lower back yesterday", reply: "I tweaked my lower back yesterday")
        #expect(back.note?.avoid.contains(.axialLoading) == true)
        #expect(back.message != "I tweaked my lower back yesterday")   // an echo isn't a reply
    }

    @Test func notesOnlyNameLiftsTheAthleteNamed() {
        let r = decide("I can't do a pull up or chin up", kind: .limitation, exercises: ["Pull-up", "Lat pulldown", "Inverted row"])
        #expect(r.note?.exercises == ["Pull-up", "Chin-up"])
        #expect(Set(r.goalOffers) == ["Pull-up", "Chin-up"])
    }

    @Test func preferencesKeepTheAthletesWords() {
        let r = decide("can we do more glute work?", kind: .question, rule: "No adding glute work today",
                       reply: "We can't add glute work today.")
        #expect(r.note?.rule == "More glute work")
        #expect(!r.message.contains("can't"))
        #expect(decide("honestly squats bore me", kind: .feedback).note?.exercises == ["Back squat"])
        #expect(decide("I want to focus on arms more", kind: .goal).note?.rule == "Focus on arms more")
    }

    @Test func wantingALiftNeverDropsIt() {
        let bench = decide("I'd like to improve my bench press", kind: .goal, exercises: ["Barbell bench press"], remember: true)
        #expect(bench.note == nil)
        #expect(bench.goalOffers == ["Barbell bench press"])
        #expect(decide("I'd love to be able to do a proper dip one day", kind: .goal, exercises: ["Dip"], remember: true).note == nil)
        // Can't do it yet AND want it: the note keeps it out while the ladder builds toward it.
        #expect(decide("pull ups are too hard for me right now but I want to get there", kind: .limitation).note?.exercises == ["Pull-up"])
    }

    @Test func timeComesFromTheWords() {
        #expect(decide("only 30 min today", minutes: 0).minutesOverride == 30)
        #expect(decide("give me a quick 20 minute session today").minutesOverride == 20)
        #expect(decide("I have an hour").minutesOverride == 60)
        #expect(decide("I slept 5 hours", minutes: 300).minutesOverride == nil)
        #expect(decide("bench felt easy", minutes: 45).minutesOverride == nil)
        #expect(decide("only 30 min today").message.contains("30 min"))
    }

    @Test func restDaysFromTheWords() {
        #expect(decide("can you make Saturday a rest day?", kind: .question).restDay)
        #expect(decide("skip tomorrow, I have a work dinner").restDay)
        #expect(decide("make friday a rest day please", reply: "").message.contains("rest day"))
        #expect(!decide("should I do cardio on rest days?", kind: .question, restDay: true).restDay)
    }

    @Test func goalsFromAnyLift() {
        #expect(decide("I want to get stronger at deadlifts", kind: .goal, buildToward: ["deadlift"]).goalOffers == ["Barbell deadlift"])
        #expect(decide("I want to do a muscle up someday", kind: .goal).goalOffers == ["Pull-up", "Dip"])
        #expect(decide("chin ups are impossible for me, any tips?", kind: .question).goalOffers == ["Chin-up"])
        // An easier version the model names counts toward the lift the athlete named.
        #expect(decide("pull ups are too hard but I want to get there", kind: .goal, buildToward: ["Negative pull-up"]).goalOffers == ["Pull-up"])
    }

    @Test func gymChangesPointToTheGymsScreen() {
        #expect(decide("I'm at a hotel gym with just dumbbells", kind: .equipment).message.contains("Gyms screen"))
        #expect(!decide("what gym exercises hit chest?", kind: .question).message.contains("Gyms screen"))
    }

    @Test func promptLabelsNeverReachTheAthlete() {
        #expect(decide("make friday a rest day", reply: "App: Friday is now a rest day.").message == "Friday is now a rest day.")
    }
}
