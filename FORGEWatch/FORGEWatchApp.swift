import SwiftUI
import SwiftData
import HealthKit
import WatchKit

@main
struct FORGEWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    init() { PhoneWatchLink.shared.activate() }

    var body: some Scene {
        WindowGroup {
            NavigationStack { WatchPlanView() }
                .tint(Theme.accent)
        }
        .modelContainer(DataStore.shared)
    }
}

/// Starting a workout on the iPhone launches FORGE here (often in the background) to run it.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await WorkoutTracker.shared.start(focus: PhoneWatchLink.shared.todayPlan?.focus ?? "Workout")
        }
    }
}

/// Today's plan, from the iPhone over iCloud or sent directly when the phone is nearby.
struct WatchPlanView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \DailyPlan.updatedAt, order: .reverse) private var plans: [DailyPlan]
    @State private var training = false
    @State private var picking = false
    /// A workout picked here rather than planned by the coach.
    @State private var custom: PlannedWorkout?
    private let link = PhoneWatchLink.shared
    private let tracker = WorkoutTracker.shared

    private var today: PlannedWorkout? {
        plans.first { $0.dayKey == DayKey.of(.now) }?.plan ?? link.todayPlan
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let plan = today {
                    Text(dayLabel(plan)).font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.accent)
                    Text(plan.focus.uppercased()).font(Theme.display(26))
                        .lineLimit(2).minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
                    if !plan.isRestDay {
                        Text("\(plan.exercises.count) moves · \(plan.minutes) min · \(plan.gymName)")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(plan.exercises) { ex in
                        HStack(alignment: .firstTextBaseline) {
                            Text(ex.name).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Text("\(ex.sets)×\(ex.reps)").font(Theme.mono(12)).foregroundStyle(Theme.muted)
                        }
                    }
                    if !plan.isRestDay {
                        Button("Start") { training = true }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 6)
                    }
                } else {
                    Text("FORGE").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.accent)
                    Text("Open FORGE on your iPhone to plan today. It shows up here once your iPhone is nearby.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                Button("Custom workout") { picking = true }
                    .padding(.top, 2)
            }
        }
        .navigationDestination(isPresented: $training) {
            if let plan = today { WatchWorkoutView(plan: plan) }
        }
        .navigationDestination(item: $custom) { WatchWorkoutView(plan: $0) }
        .sheet(isPresented: $picking) {
            NavigationStack { WatchCustomWorkoutView { custom = $0 } }
        }
        // Started from the iPhone: go straight to the workout (not when one was just picked here).
        .onChange(of: tracker.isRunning, initial: true) {
            if tracker.isRunning, today != nil, custom == nil { training = true }
        }
        // Keep the complications on today's plan.
        .onChange(of: today, initial: true) { WidgetSnapshot.publish(plan: today, in: ctx) }
        .onChange(of: tracker.isRunning) { if !tracker.isRunning { WidgetSnapshot.publish(plan: today, in: ctx) } }
    }

    /// "TODAY · SATURDAY", or "FROM FRIDAY" when the iPhone hasn't sent today's plan yet.
    private func dayLabel(_ plan: PlannedWorkout) -> String {
        let weekday = plan.date.formatted(.dateTime.weekday(.wide)).uppercased()
        return Calendar.current.isDateInToday(plan.date) ? "TODAY · \(weekday)" : "FROM \(weekday)"
    }
}
