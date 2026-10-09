import SwiftUI
import SwiftData

@main
struct FORGEWatchApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack { WatchPlanView() }
                .tint(Theme.ember)
        }
        .modelContainer(DataStore.shared)
    }
}

/// Today's plan, synced from the iPhone coach through iCloud.
struct WatchPlanView: View {
    @Query(sort: \DailyPlan.updatedAt, order: .reverse) private var plans: [DailyPlan]
    @State private var training = false

    private var today: PlannedWorkout? {
        plans.first { $0.dayKey == DayKey.of(.now) }?.plan
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("FORGE").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ember)
                if let plan = today {
                    Text(plan.focus.uppercased()).font(Theme.display(32))
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
                    Text("Open FORGE on your iPhone to plan today. It syncs here through iCloud.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
            }
        }
        .navigationDestination(isPresented: $training) {
            if let plan = today { WatchWorkoutView(plan: plan) }
        }
    }
}
