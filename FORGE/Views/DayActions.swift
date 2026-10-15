import SwiftUI
import SwiftData

/// The ⋯ menu on a day in Today: move its workout, take it off, or train on a rest day.
/// Changes are for this week only; the usual training days stay the same.
struct DayActionsMenu: View {
    let date: Date
    let plan: PlannedWorkout?

    @Environment(\.modelContext) private var ctx
    @Environment(CoachStore.self) private var coach
    @Query(sort: \DailyPlan.updatedAt, order: .reverse) private var planRows: [DailyPlan]
    @Query(filter: #Predicate<WorkoutSession> { $0.endDate != nil }) private var sessions: [WorkoutSession]

    private var cal: Calendar { .current }

    /// Today and the rest of this week, other than this day and days already trained.
    private var moveTargets: [Date] {
        let start = cal.startOfDay(for: .now)
        let weekEnd = cal.dateInterval(of: .weekOfYear, for: .now)?.end ?? start
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
            .filter { $0 < weekEnd && !cal.isDate($0, inSameDayAs: date) }
            .filter { day in !sessions.contains { cal.isDate($0.date, inSameDayAs: day) } }
    }

    var body: some View {
        Menu {
            if let plan, !plan.isRestDay {
                Menu("Move to…", systemImage: "arrow.left.arrow.right") {
                    ForEach(moveTargets, id: \.self) { target in
                        Button(label(for: target)) { coach.move(from: date, to: target, ctx) }
                    }
                }
                .disabled(moveTargets.isEmpty)
                Button("Make it a rest day", systemImage: "moon.zzz") { coach.makeRestDay(date, ctx) }
            } else {
                Button("Train this day", systemImage: "dumbbell") { Task { await coach.train(on: date, ctx) } }
            }
            Text("Changes this week only")
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 20)).frame(width: 44, height: 44)
        }
        .tint(Theme.muted)
        .accessibilityLabel("Change this day")
    }

    private func label(for target: Date) -> String {
        let name = cal.isDateInToday(target) ? "Today" : target.formatted(.dateTime.weekday(.wide))
        if let other = planRows.first(where: { $0.dayKey == DayKey.of(target) })?.plan, !other.isRestDay {
            return "\(name) (swap with \(other.focus))"
        }
        return name
    }
}
