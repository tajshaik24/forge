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
            root.tint(Theme.accent)
        }
        .modelContainer(DataStore.shared)
    }

    @ViewBuilder
    private var root: some View {
        #if DEBUG
        if WatchDemo.isOn {
            WatchDemo.Root()
        } else {
            NavigationStack { WatchPlanView() }
        }
        #else
        NavigationStack { WatchPlanView() }
        #endif
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

/// Home: today's workout, the rest of the week, and today's steps. Plans come from the iPhone over
/// iCloud, or directly when the phone is nearby.
struct WatchPlanView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \DailyPlan.updatedAt, order: .reverse) private var plans: [DailyPlan]
    @State private var training = false
    @State private var picking = false
    /// A workout picked here rather than planned by the coach.
    @State private var custom: PlannedWorkout?
    @State private var steps = WatchSteps()
    private let link = PhoneWatchLink.shared
    private let tracker = WorkoutTracker.shared

    private var today: PlannedWorkout? {
        plans.first { $0.dayKey == DayKey.of(.now) }?.plan ?? link.todayPlan
    }

    /// The next six days: the synced plan for each, else the one the iPhone sent, else nothing planned.
    private var week: [(day: Date, plan: PlannedWorkout?)] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        let sent = link.weekPlans
        return (1...6).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = DayKey.of(day)
            let plan = plans.first { $0.dayKey == key }?.plan ?? sent.first { DayKey.of($0.date) == key }
            return (day, plan)
        }
    }

    var body: some View {
        ScrollViewReader { scroller in
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                todayCard
                WatchStepsRow(steps: steps.count)
                if !week.isEmpty {
                    Text("THIS WEEK").font(.system(size: 11, weight: .heavy)).tracking(0.5).foregroundStyle(Theme.muted)
                        .padding(.top, 4)
                        .id("week")
                    VStack(spacing: 0) {
                        ForEach(Array(week.enumerated()), id: \.offset) { i, entry in
                            if i > 0 { Divider().overlay(Theme.hairline) }
                            dayRow(entry.day, entry.plan)
                        }
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Button("Custom workout", systemImage: "plus") { picking = true }
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #if DEBUG
        .task { if WatchDemo.screen == "week" { scroller.scrollTo("week", anchor: .top) } }
        #endif
        }
        .navigationDestination(isPresented: $training) {
            if let plan = today, !plan.isRestDay {
                WatchWorkoutView(plan: plan)
            } else {
                // Started on the iPhone before its plan got here: the plan follows when it arrives.
                WatchWorkoutView(plan: .own(gymName: "", restSeconds: RepScheme.rest(for: WatchPicks.goal)),
                                 isPlaceholder: true)
            }
        }
        .navigationDestination(item: $custom) { WatchWorkoutView(plan: $0) }
        .navigationDestination(for: PlannedWorkout.self) { WatchDayView(plan: $0) }
        .sheet(isPresented: $picking) {
            NavigationStack { WatchCustomWorkoutView { custom = $0 } }
        }
        // A workout is running (started on the iPhone, or this screen came back mid-workout): go to it.
        .onChange(of: tracker.isRunning, initial: true) {
            if tracker.isRunning, custom == nil, !training { training = true }
        }
        // Keep the complications on today's plan.
        .onChange(of: today, initial: true) { WidgetSnapshot.publish(plan: today, in: ctx) }
        .onChange(of: tracker.isRunning) { if !tracker.isRunning { WidgetSnapshot.publish(plan: today, in: ctx) } }
        // Steps: now, then every couple of minutes while the screen is up.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await steps.authorize()
            while !Task.isCancelled {
                await steps.refresh()
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }

    // MARK: Today

    @ViewBuilder
    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let plan = today {
                Text(dayLabel(plan)).font(.system(size: 11, weight: .heavy)).tracking(0.5).foregroundStyle(Theme.accentText)
                Text(plan.isRestDay ? "REST DAY" : plan.focus.uppercased()).font(Theme.display(22))
                    .lineLimit(2).minimumScaleFactor(0.6).fixedSize(horizontal: false, vertical: true)
                if plan.isRestDay {
                    Text(restLine).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // The lifts are a tap away; Start is the big target.
                    NavigationLink(value: plan) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(meta(plan)) \(Image(systemName: "chevron.right"))")
                            if !plan.gymName.isEmpty { Text(plan.gymName).lineLimit(1) }
                        }
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Button { training = true } label: {
                        Label(tracker.isRunning ? "Resume" : "Start", systemImage: "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Theme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            } else {
                Text("FORGE").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.accentText)
                Text("Open FORGE on your iPhone to plan today. It shows up here once your iPhone is nearby.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "5 lifts · 45 min"
    private func meta(_ plan: PlannedWorkout) -> String {
        let n = plan.exercises.count
        return "\(n) \(n == 1 ? "lift" : "lifts") · \(plan.minutes) min"
    }

    /// "Next: Tue · Pull"
    private var restLine: String {
        guard let next = week.first(where: { $0.plan.map { !$0.isRestDay } ?? false }), let plan = next.plan else {
            return "Recover today."
        }
        return "Recover today. Next: \(next.day.formatted(.dateTime.weekday(.abbreviated))) · \(plan.focus)"
    }

    /// "TODAY · SATURDAY", or "FROM FRIDAY" when the iPhone hasn't sent today's plan yet.
    private func dayLabel(_ plan: PlannedWorkout) -> String {
        let weekday = plan.date.formatted(.dateTime.weekday(.wide)).uppercased()
        return Calendar.current.isDateInToday(plan.date) ? "TODAY · \(weekday)" : "FROM \(weekday)"
    }

    // MARK: The week

    @ViewBuilder
    private func dayRow(_ day: Date, _ plan: PlannedWorkout?) -> some View {
        let label = HStack(spacing: 8) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(Theme.mono(11, .bold)).foregroundStyle(Theme.muted)
                .frame(width: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(title(plan, day)).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(plan.map { $0.isRestDay } ?? true ? Theme.muted : Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.75)
                if let plan, !plan.isRestDay {
                    Text("\(plan.exercises.count) lifts · \(plan.minutes) min").font(.system(size: 11)).foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let plan, !plan.isRestDay {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .contentShape(Rectangle())

        if let plan, !plan.isRestDay {
            NavigationLink(value: plan) { label }.buttonStyle(.plain)
        } else {
            label
        }
    }

    private func title(_ plan: PlannedWorkout?, _ day: Date) -> String {
        if let plan { return plan.isRestDay ? "Rest" : plan.focus }
        let weekday = Calendar.current.component(.weekday, from: day)
        return SyncedSettings.trainingWeekdays.contains(weekday) ? "Not planned yet" : "Rest"
    }
}

/// One day's lifts, from the week list.
struct WatchDayView: View {
    let plan: PlannedWorkout
    private let unit = SyncedSettings.unit

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(plan.date.formatted(.dateTime.weekday(.wide)).uppercased())
                    .font(.system(size: 11, weight: .heavy)).tracking(0.5).foregroundStyle(Theme.accentText)
                Text(plan.focus.uppercased()).font(Theme.display(20))
                    .lineLimit(2).minimumScaleFactor(0.6).fixedSize(horizontal: false, vertical: true)
                Text("\(plan.minutes) min · \(plan.totalSets) sets").font(.system(size: 12)).foregroundStyle(Theme.muted)
                ForEach(plan.exercises) { ex in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ex.name).font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        Text(detail(ex)).font(Theme.mono(11)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .navigationTitle(plan.date.formatted(.dateTime.weekday(.abbreviated)))
    }

    /// "3 × 6-10 · 135 lb", or "3 × 5 · find your weight".
    private func detail(_ ex: PlannedExercise) -> String {
        var s = "\(ex.sets) × \(ex.reps)"
        if ex.calibrate == true { s += " · find weight" }
        else if let t = ex.target, t.weight > 0 { s += " · \(unit.format(pounds: t.weight))" }
        return s
    }
}

// MARK: - Steps

/// Today's step count on the Watch, from Health.
@MainActor
@Observable
final class WatchSteps {
    static let goal = 10_000
    private(set) var count: Int?
    private let store = WorkoutTracker.shared.store

    func authorize() async {
        #if DEBUG
        if WatchDemo.isOn { return }
        #endif
        await WorkoutTracker.shared.requestAuthorization()
    }

    func refresh() async {
        #if DEBUG
        if WatchDemo.isOn { count = WatchDemo.steps; return }
        #endif
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let start = Calendar.current.startOfDay(for: .now)
        // The async form of an HKStatisticsQuery: one cumulative sum for today, deduplicated across devices.
        let query = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.stepCount),
                                       predicate: HKQuery.predicateForSamples(withStart: start, end: nil)),
            options: .cumulativeSum)
        do {
            let stats = try await query.result(for: store)
            count = Int(stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
        } catch {
            // No data yet today, or no permission: leave the last count.
        }
    }
}

/// "6,240 steps", with a bar toward the day's goal.
struct WatchStepsRow: View {
    let steps: Int?

    var body: some View {
        let share = min(1, Double(steps ?? 0) / Double(WatchSteps.goal))
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "figure.walk").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accentText)
                Text(steps.map { $0.formatted(.number) } ?? "--").font(Theme.mono(16, .bold)).monospacedDigit()
                Text("steps").font(.system(size: 12)).foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
                Text("of \((WatchSteps.goal / 1000))k").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.raised)
                    Capsule().fill(Theme.accent).frame(width: max(share > 0 ? 6 : 0, geo.size.width * share))
                }
            }
            .frame(height: 5)
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(steps ?? 0) steps of \(WatchSteps.goal)")
    }
}
