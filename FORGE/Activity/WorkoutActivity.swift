import ActivityKit
import AppIntents
import Foundation

/// The Lock Screen / Dynamic Island workout, shared by the app (starts and updates it)
/// and the FORGEWidgets extension (draws it).
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exercise: String
        var setNumber: Int
        var totalSets: Int
        /// Set while resting.
        var restStarted: Date?
        var restUntil: Date?
        var nextUp: String
        var onWatch: Bool
    }

    var focus: String
    var workoutStart: Date
}

/// Commands from the Live Activity buttons. The intents run in the app's process and post
/// this so the open workout screen can act on it.
enum RestCommand: String {
    case skip, extend

    static let notification = Notification.Name("forge.restCommand")
}

struct SkipRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip Rest"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await MainActor.run { NotificationCenter.default.post(name: RestCommand.notification, object: RestCommand.skip) }
        return .result()
    }
}

struct ExtendRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add 30 Seconds of Rest"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await MainActor.run { NotificationCenter.default.post(name: RestCommand.notification, object: RestCommand.extend) }
        return .result()
    }
}
