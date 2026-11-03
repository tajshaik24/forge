#if DEBUG
import SwiftUI
import SwiftData

/// Demo screens for history, progress and Today (`-screen <name>`). Nil for names it doesn't know.
///
///     history          History (add `-historyMode Lifts` for the lifts list)
///     lift / lift-bw / lift-timed   LiftProgressView: bench press / push-up / plank
///     summary          the latest past workout      summary-today   today's, with records
///     today            Today with a plan            today-done      Today after the workout
///     steps            StepsView
///
/// Long screens: add `-scroll 0.5` or `-scroll bottom` to start scrolled.
enum HistoryScreens {
    @MainActor
    static func view(_ name: String) -> AnyView? {
        switch name {
        case "history": AnyView(DemoHost { HistoryView() })
        case "lift": AnyView(DemoHost { LiftProgressView(name: "Barbell bench press") })
        case "lift-bw": AnyView(DemoHost { LiftProgressView(name: "Push-up") })
        case "lift-timed": AnyView(DemoHost { LiftProgressView(name: "Plank") })
        case "summary": AnyView(DemoHost { LatestSummary(today: false) })
        case "summary-today": AnyView(DemoHost(finishToday: true) { LatestSummary(today: true) })
        case "today": AnyView(DemoHost(needsPlan: true) { TodayView() })
        case "today-done": AnyView(DemoHost(finishToday: true) { TodayView() })
        case "steps": AnyView(DemoHost { StepsView() })
        default: nil
        }
    }
}

/// Waits for `Demo.seed` and today's plan, adds the extras these screens show (heart rate,
/// bodyweight lifts, optionally today's finished workout), then shows the screen.
private struct DemoHost<Content: View>: View {
    var needsPlan = false
    var finishToday = false
    @ViewBuilder var content: () -> Content
    @Environment(\.modelContext) private var ctx
    @Environment(CoachStore.self) private var coach
    @State private var ready = false

    var body: some View {
        NavigationStack {
            if ready { content() } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task {
            for _ in 0..<80 {
                let seeded = ((try? ctx.fetchCount(FetchDescriptor<WorkoutSession>())) ?? 0) > 0
                if seeded, !(needsPlan || finishToday) || coach.plan != nil { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            HistoryDemo.addExtras(ctx)
            if finishToday, let plan = coach.plan { HistoryDemo.finishToday(plan, ctx) }
            _ = coach.makeContext(ctx)
            ready = true
        }
    }
}

private struct LatestSummary: View {
    let today: Bool
    @Query(filter: #Predicate<WorkoutSession> { $0.endDate != nil }, sort: \WorkoutSession.date, order: .reverse)
    private var sessions: [WorkoutSession]

    var body: some View {
        if let s = sessions.first(where: { Calendar.current.isDateInToday($0.date) == today }) {
            SummaryView(session: s) {}
        } else {
            Text("No workout")
        }
    }
}

@MainActor
enum HistoryDemo {
    private static var added = false

    /// Heart rate for every demo workout, and a bodyweight and a timed lift to chart.
    static func addExtras(_ ctx: ModelContext) {
        guard !added else { return }
        added = true
        let sessions = (try? ctx.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date)]))) ?? []
        for (n, s) in sessions.enumerated() {
            if s.heartRates.isEmpty { s.heartRates = heartRates(minutes: Int(s.duration / 60), seed: n) }
            guard let end = s.endDate else { continue }
            let extra: (String, Int)? = s.focus == "Push" ? ("Push-up", 12 + n / 3) : (s.focus == "Legs" ? ("Plank", 30 + n * 2) : nil)
            if let (name, reps) = extra {
                for i in 0..<2 {
                    let e = SetEntry(exercise: name, weight: 0, reps: reps - i * 2, rpe: 8, date: end.addingTimeInterval(Double(i) * 90))
                    e.session = s
                    ctx.insert(e)
                }
                s.endDate = end.addingTimeInterval(240)
            }
        }
        try? ctx.save()
    }

    /// Today's plan, done an hour ago, a little heavier than ever on the first lift.
    static func finishToday(_ plan: PlannedWorkout, _ ctx: ModelContext) {
        let today = (try? ctx.fetch(FetchDescriptor<WorkoutSession>()))?.contains { Calendar.current.isDateInToday($0.date) } ?? false
        guard !today, !plan.exercises.isEmpty else { return }
        let start = Date.now.addingTimeInterval(-62 * 60)
        let session = WorkoutSession(date: start, focus: plan.focus, gymName: plan.gymName)
        ctx.insert(session)
        var t = start.addingTimeInterval(240)
        for (i, ex) in plan.exercises.enumerated() {
            let base = ex.target?.weight ?? (ExerciseCatalog.named(ex.name)?.equipment.isEmpty == false ? 95 : 0)
            let reps = ex.target?.reps ?? RepRange.parse(ex.reps).lowerBound
            for set in 0..<ex.sets {
                let bump = i == 0 && set == ex.sets - 1 ? SyncedSettings.unit.toPounds(SyncedSettings.unit.step) : 0
                let e = SetEntry(exercise: ex.name, weight: base + bump, reps: reps + (i == 1 && set == 0 ? 2 : 0),
                                 rpe: [8, 8, 9][set % 3], date: t)
                e.session = session
                ctx.insert(e)
                t = t.addingTimeInterval(Double(plan.restSeconds) + 45)
            }
        }
        session.endDate = t
        session.averageHeartRate = 124
        session.maxHeartRate = 167
        session.activeCalories = 312
        session.heartRates = heartRates(minutes: Int(t.timeIntervalSince(start) / 60), seed: 3)
        session.feel = "right"
        try? ctx.save()
    }

    /// Sets push it up, rests bring it down: one reading per 15 s.
    private static func heartRates(minutes: Int, seed: Int) -> [Int] {
        (0..<max(minutes, 10) * 4).map { i in
            let warm = min(1, Double(i) / 24)
            let cycle = sin(Double(i) / 3.2 + Double(seed)) * 14
            return Int(96 + warm * 30 + cycle + Double((i * 7 + seed) % 5))
        }
    }
}
#endif
