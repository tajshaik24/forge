import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Rest countdown and current set on the Lock Screen and in the Dynamic Island.
/// Timers use `Text(timerInterval:)`, so they tick without the app sending updates.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Theme.ground)
                .activitySystemActionForegroundColor(Theme.accent)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.restUntil == nil ? "SET \(state.setNumber)/\(state.totalSets)" : "REST")
                            .font(Theme.label).foregroundStyle(Theme.muted)
                        Text(state.exercise).font(.system(size: 15, weight: .heavy)).lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ClockText(state: state, workoutStart: context.attributes.workoutStart)
                        .font(Theme.mono(28)).foregroundStyle(Theme.accent)
                        .frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if let started = state.restStarted, let until = state.restUntil {
                            ProgressView(timerInterval: started...until, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                                .tint(Theme.accent)
                        }
                        HStack {
                            Text(state.nextUp).font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                            Spacer()
                            if state.restUntil != nil { RestButtons() }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: state.restUntil == nil ? "dumbbell.fill" : "timer").foregroundStyle(Theme.accent)
            } compactTrailing: {
                ClockText(state: state, workoutStart: context.attributes.workoutStart)
                    .font(Theme.mono(14)).foregroundStyle(Theme.accent)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: state.restUntil == nil ? "dumbbell.fill" : "timer").foregroundStyle(Theme.accent)
            }
            .keylineTint(Theme.accent)
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        let state = context.state
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("FORGE · \(context.attributes.focus.uppercased())").font(Theme.label).tracking(1)
                    .foregroundStyle(Theme.accent)
                if state.onWatch { Image(systemName: "applewatch").font(.caption).foregroundStyle(Theme.muted) }
                Spacer()
                Text(state.restUntil == nil ? "SET \(state.setNumber) OF \(state.totalSets)" : "REST")
                    .font(Theme.label).foregroundStyle(Theme.muted)
            }
            HStack(alignment: .center) {
                Text(state.exercise).font(Theme.display(24)).foregroundStyle(Theme.text).lineLimit(1)
                Spacer()
                ClockText(state: state, workoutStart: context.attributes.workoutStart)
                    .font(Theme.mono(34)).foregroundStyle(Theme.text)
                    .frame(maxWidth: 130, alignment: .trailing)
            }
            if let started = state.restStarted, let until = state.restUntil {
                ProgressView(timerInterval: started...until, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(Theme.accent)
            }
            HStack {
                Text(state.nextUp).font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer()
                if state.restUntil != nil { RestButtons() }
            }
        }
        .padding(16)
    }
}

/// Rest countdown while resting, otherwise time since the workout started.
private struct ClockText: View {
    let state: WorkoutActivityAttributes.ContentState
    let workoutStart: Date

    var body: some View {
        Group {
            if let until = state.restUntil, until > .now {
                Text(timerInterval: Date.now...until, countsDown: true)
            } else {
                Text(timerInterval: workoutStart...Date.distantFuture, countsDown: false)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
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
