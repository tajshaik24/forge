import SwiftUI
import SwiftData
import CloudKit
import UIKit

@main
struct FORGEApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
            if SyncedSettings.crewBeta, CrewService.shared.crew != nil {
                await CrewService.shared.subscribe()   // idempotent; covers your other devices too
                await CrewService.shared.postCheckIns(from: ctx)
                await CrewService.shared.refresh()
            }
        }
    }
}

// MARK: - CloudKit share acceptance + crew pushes

/// SwiftUI has no hook for "user tapped a CloudKit share link", so a scene delegate handles it.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else { return .noData }
        await CrewService.shared.refresh()
        return .newData
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// App already running when the invite link is tapped.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        join(cloudKitShareMetadata)
    }

    /// App launched by tapping the invite link.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata { join(metadata) }
    }

    private func join(_ metadata: CKShare.Metadata) {
        SyncedSettings.crewBeta = true
        Task { @MainActor in await CrewService.shared.accept(metadata) }
    }
}
