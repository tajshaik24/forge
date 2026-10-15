import ActivityKit
import Foundation

/// Starts, updates and ends the workout Live Activity. Updates are local (no push), which is
/// enough: the app stays running in the background during a HealthKit workout.
@MainActor
enum LiveActivityController {
    private static var activity: Activity<WorkoutActivityAttributes>?

    static func show(_ state: WorkoutActivityAttributes.ContentState, focus: String, workoutStart: Date) {
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity, activity.activityState == .active {
            Task { await activity.update(content) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // A leftover from a crash or relaunch: start clean.
        for old in Activity<WorkoutActivityAttributes>.activities { Task { await old.end(nil, dismissalPolicy: .immediate) } }
        do {
            activity = try Activity.request(attributes: WorkoutActivityAttributes(focus: focus, workoutStart: workoutStart),
                                            content: content)
        } catch {
            print("FORGE: couldn't start the Live Activity: \(error.localizedDescription)")
        }
    }

    static func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
