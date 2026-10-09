import SwiftUI
import SwiftData

@main
struct FORGEApp: App {
    @State private var coach = CoachStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(coach)
                .preferredColorScheme(.dark)
                .tint(Theme.ember)
        }
        .modelContainer(DataStore.shared)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(CoachStore.self) private var coach
    @State private var showSetup = !SyncedSettings.onboarded

    var body: some View {
        TabView {
            Tab("Today", systemImage: "flame") { NavigationStack { TodayView() } }
            Tab("Coach", systemImage: "bubble.left.and.text.bubble.right") { NavigationStack { CoachChatView() } }
            Tab("Week", systemImage: "calendar") { NavigationStack { WeekView() } }
            Tab("History", systemImage: "chart.line.uptrend.xyaxis") { NavigationStack { HistoryView() } }
            Tab("Gyms", systemImage: "dumbbell") { NavigationStack { GymsView() } }
        }
        .fullScreenCover(isPresented: $showSetup) {
            OnboardingView {
                showSetup = false
                Task { await coach.invalidate(ctx) }
            }
        }
        .task {
            Seed.ifNeeded(ctx)
            DataStore.refreshCustomExercises(in: ctx)
            guard !showSetup else { return }   // setup asks for Health access and plans once it's done
            await WorkoutTracker.shared.requestAuthorization()
            await coach.loadToday(ctx)
        }
    }
}
