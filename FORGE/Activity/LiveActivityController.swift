import ActivityKit
import Foundation

/// Starts, updates and ends the workout Live Activity. Updates are local (no push), which is
/// enough: the app stays running in the background during a HealthKit workout.
@MainActor
enum LiveActivityController {
    private static var activity: Activity<WorkoutActivityAttributes>?
    private static var shown: WorkoutActivityAttributes.ContentState?
    private static var lastUpdate: Date = .distantPast

    /// Heart rate changes every few seconds; iOS limits how often an activity can update, so a
    /// heart-rate-only change goes out at most every 10 s. Anything else goes out at once.
    static func show(_ state: WorkoutActivityAttributes.ContentState, focus: String, workoutStart: Date) {
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity, activity.activityState == .active {
            guard state != shown else { return }
            var sameButHeart = state
            sameButHeart.heartRate = shown?.heartRate
            if sameButHeart == shown, Date().timeIntervalSince(lastUpdate) < 10 { return }
            shown = state
            lastUpdate = .now
            Task { await activity.update(content) }
            return
        }
        shown = state
        lastUpdate = .now
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
        shown = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
