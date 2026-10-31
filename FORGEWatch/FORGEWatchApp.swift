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
    private let link = PhoneWatchLink.shared
    private let tracker = WorkoutTracker.shared

    private var today: PlannedWorkout? {
        plans.first { $0.dayKey == DayKey.of(.now) }?.plan ?? link.todayPlan
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("FORGE").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.accent)
                if let plan = today {
                    Text(plan.focus.uppercased()).font(Theme.display(26))
                    Text("\(plan.exercises.count) moves · \(plan.minutes) min · \(plan.gymName)")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    ForEach(plan.exercises) { ex in
                        HStack {
                            Text(ex.name).font(.system(size: 13)).lineLimit(1)
                            Spacer()
                            Text("\(ex.sets)×\(ex.reps)").font(Theme.mono(12)).foregroundStyle(Theme.muted)
                        }
                    }
                    if !plan.isRestDay {
                        Button("Start") { training = true }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 6)
                    }
                } else {
                    Text("Open FORGE on your iPhone to plan today. It shows up here once your iPhone is nearby.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
            }
        }
        .navigationDestination(isPresented: $training) {
            if let plan = today { WatchWorkoutView(plan: plan) }
        }
        // Started from the iPhone: go straight to the workout.
        .onChange(of: tracker.isRunning, initial: true) {
            if tracker.isRunning, today != nil { training = true }
        }
        // Keep the complications on today's plan.
        .onChange(of: today, initial: true) { WidgetSnapshot.publish(plan: today, in: ctx) }
        .onChange(of: tracker.isRunning) { if !tracker.isRunning { WidgetSnapshot.publish(plan: today, in: ctx) } }
    }
}
