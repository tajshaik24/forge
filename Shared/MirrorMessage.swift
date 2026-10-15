import Foundation

/// What the iPhone and Watch tell each other during one shared (mirrored) workout.
/// Sent over `HKWorkoutSession.sendToRemoteWorkoutSession(data:)`.
enum MirrorMessage: Codable, Sendable, Hashable {
    /// A set logged on the sending device. Weight is in pounds.
    case setLogged(LoggedSet)
    /// Rest was started, extended (+30 s) or skipped (nil).
    case rest(until: Date?)
    /// iPhone → Watch: end the workout and save it to Health.
    case finish
    /// iPhone → Watch: throw the workout away.
    case discard

    func encoded() throws -> Data { try JSONEncoder().encode(self) }
    static func decode(_ data: Data) -> MirrorMessage? { try? JSONDecoder().decode(MirrorMessage.self, from: data) }
}

struct LoggedSet: Codable, Sendable, Hashable {
    var exercise: String
    var weight: Double
    var reps: Int
    var rpe: Int?
    var start: Date
    var end: Date
}
