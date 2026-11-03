import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The workout on the Lock Screen and in the Dynamic Island: the lift and set you're on, heart rate,
/// time into the workout, and the rest countdown while resting.
/// Timers use `Text(timerInterval:)`, so they tick without the app sending updates. Every timer has a
/// bounded range and a fixed width: an open-ended one sizes for millions of hours and pushes the rest
/// of the layout out of view.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Theme.ground)
                .activitySystemActionForegroundColor(Theme.accent)
        } dynamicIsland: { context in
            let state = context.state
            let start = context.attributes.workoutStart
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.resting ? "REST" : state.setLabel.uppercased())
                            .font(Theme.label).foregroundStyle(Theme.muted)
                        Text(state.exercise).font(.system(size: 15, weight: .heavy))
                            .lineLimit(2).minimumScaleFactor(0.75)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if state.resting, let until = state.restUntil {
                            Countdown(until: until).font(Theme.mono(26)).foregroundStyle(Theme.accent)
                        } else {
                            HeartRate(bpm: state.heartRate).font(Theme.mono(22))
                        }
                        Elapsed(since: start).font(Theme.mono(12)).foregroundStyle(Theme.muted)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if let started = state.restStarted, let until = state.restUntil, state.resting {
                            ProgressView(timerInterval: started...until, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                                .tint(Theme.accent)
                        }
                        HStack {
                            Text(state.detail).font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                            Spacer(minLength: 8)
                            if state.resting { RestButtons() }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: state.resting ? "timer" : "dumbbell.fill").foregroundStyle(Theme.accent)
            } compactTrailing: {
                Group {
                    if state.resting, let until = state.restUntil {
                        Countdown(until: until)
                    } else {
                        Elapsed(since: start)
                    }
                }
                .font(Theme.mono(14)).foregroundStyle(Theme.accent)
                .frame(width: 48)
            } minimal: {
                Image(systemName: state.resting ? "timer" : "dumbbell.fill").foregroundStyle(Theme.accent)
            }
            .keylineTint(Theme.accent)
        }
    }
}

private extension WorkoutActivityAttributes.ContentState {
    /// Resting until a time still ahead. A rest that ran out while nothing updated reads as lifting.
    var resting: Bool { restUntil.map { $0 > .now } ?? false }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        let state = context.state
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("FORGE · \(context.attributes.focus.uppercased())").font(Theme.label).tracking(1)
                    .foregroundStyle(Theme.accent).lineLimit(1)
                if state.onWatch { Image(systemName: "applewatch").font(.caption2).foregroundStyle(Theme.muted) }
                Spacer(minLength: 8)
                Image(systemName: "stopwatch").font(.caption2).foregroundStyle(Theme.muted)
                Elapsed(since: context.attributes.workoutStart)
                    .font(Theme.mono(13)).foregroundStyle(Theme.muted)
                    .frame(width: 58, alignment: .trailing)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.resting ? "REST · UP NEXT" : state.setLabel.uppercased())
                        .font(Theme.label).foregroundStyle(Theme.muted)
                    Text(state.exercise).font(.system(size: 20, weight: .heavy)).foregroundStyle(Theme.text)
                        .lineLimit(2).minimumScaleFactor(0.75)
                    Text(state.detail).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                VStack(alignment: .trailing, spacing: 2) {
                    if state.resting, let until = state.restUntil {
                        Countdown(until: until).font(Theme.mono(34)).foregroundStyle(Theme.text)
                    } else {
                        HeartRate(bpm: state.heartRate).font(Theme.mono(30))
                    }
                }
                .frame(width: 104, alignment: .trailing)
            }

            if let started = state.restStarted, let until = state.restUntil, state.resting {
                ProgressView(timerInterval: started...until, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(Theme.accent)
                HStack {
                    Spacer()
                    RestButtons()
                }
            } else {
                ProgressView(value: state.progress).tint(Theme.accent)
            }
        }
        .padding(16)
    }
}

/// "♥ 132", or "♥ --" without a Watch.
private struct HeartRate: View {
    let bpm: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "heart.fill").font(.system(size: 14)).foregroundStyle(.red)
            Text(bpm.map(String.init) ?? "--").monospacedDigit().foregroundStyle(Theme.text)
        }
        .lineLimit(1)
    }
}

/// Time since the workout started. Bounded to 6 hours so the system sizes it sensibly.
private struct Elapsed: View {
    let since: Date

    var body: some View {
        Text(timerInterval: since...since.addingTimeInterval(6 * 3600), countsDown: false)
            .monospacedDigit().multilineTextAlignment(.trailing).lineLimit(1)
    }
}

private struct Countdown: View {
    let until: Date

    var body: some View {
        Text(timerInterval: Date.now...max(until, .now), countsDown: true)
            .monospacedDigit().multilineTextAlignment(.trailing).lineLimit(1)
    }
}

private struct RestButtons: View {
    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ExtendRestIntent()) { Text("+30 s") }
                .tint(Theme.raised)
            Button(intent: SkipRestIntent()) { Text("Skip") }
                .tint(Theme.accent)
        }
        .font(.system(size: 13, weight: .heavy))
        .buttonStyle(.borderedProminent)
    }
}

#if DEBUG
#Preview("Lifting", as: .content, using: WorkoutActivityAttributes(focus: "Push", workoutStart: .now.addingTimeInterval(-1460))) {
    WorkoutLiveActivity()
} contentStates: {
    WorkoutActivityAttributes.ContentState(exercise: "Standing barbell overhead press", setLabel: "Set 2 of 3",
                                           detail: "95 lb × 8", heartRate: 132, restStarted: nil, restUntil: nil,
                                           onWatch: true, progress: 0.38)
    WorkoutActivityAttributes.ContentState(exercise: "Barbell bench press", setLabel: "Set 3 of 3",
                                           detail: "Set 3 · 135 lb × 8", heartRate: 141, restStarted: .now,
                                           restUntil: .now.addingTimeInterval(90), onWatch: true, progress: 0.5)
}
#endif
