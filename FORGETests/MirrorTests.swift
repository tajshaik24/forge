import Testing
import Foundation
@testable import FORGE

@Suite("Watch ↔ iPhone messages")
struct MirrorTests {
    private let set = LoggedSet(exercise: "Leg press", weight: 225, reps: 10, rpe: 8,
                                start: Date(timeIntervalSince1970: 1_000), end: Date(timeIntervalSince1970: 1_045))

    @Test(arguments: [
        MirrorMessage.setLogged(LoggedSet(exercise: "Push-up", weight: 0, reps: 15, rpe: nil,
                                          start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 30))),
        .rest(until: Date(timeIntervalSince1970: 2_000)),
        .rest(until: nil),
        .finish,
        .discard,
    ])
    func roundTrips(_ message: MirrorMessage) throws {
        #expect(MirrorMessage.decode(try message.encoded()) == message)
    }

    @Test func setKeepsEveryField() throws {
        guard case .setLogged(let decoded) = MirrorMessage.decode(try MirrorMessage.setLogged(set).encoded()) else {
            Issue.record("didn't decode a set"); return
        }
        #expect(decoded == set)
    }

    @Test func garbageIsIgnored() {
        #expect(MirrorMessage.decode(Data("not json".utf8)) == nil)
        #expect(MirrorMessage.decode(Data(#"{"somethingNew":{}}"#.utf8)) == nil)
    }

    @Test func workoutResultRoundTrips() throws {
        let result = WorkoutTracker.Result(workoutID: UUID(), start: .init(timeIntervalSince1970: 0),
                                           end: .init(timeIntervalSince1970: 3_600), activeCalories: 310,
                                           averageHeartRate: 118, maxHeartRate: 162, timeline: [90, 120, 140])
        let decoded = try JSONDecoder().decode(WorkoutTracker.Result.self, from: JSONEncoder().encode(result))
        #expect(decoded.workoutID == result.workoutID)
        #expect(decoded.timeline == result.timeline)
        #expect(decoded.maxHeartRate == 162)
    }

    @Test func watchContextCarriesPlanAndUnit() throws {
        let plan = PlannedWorkout(date: .now, focus: "Legs", muscles: [.quads], minutes: 45, reasons: [],
                                  exercises: [PlannedExercise(name: "Leg press", sets: 3, reps: "8-12")],
                                  restSeconds: 90, gymName: "Home", engine: "rules")
        let context = PhoneWatchLink.Context(plan: plan, unit: .kg)
        let decoded = try JSONDecoder().decode(PhoneWatchLink.Context.self, from: JSONEncoder().encode(context))
        #expect(decoded == context)
    }
}
