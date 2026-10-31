import Foundation
import SwiftData

extension WidgetSnapshot {
    /// Builds the snapshot from today's plan and your workouts, and saves it for the widgets.
    @MainActor
    static func publish(plan: PlannedWorkout?, in ctx: ModelContext) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let todays = plan.flatMap { cal.isDate($0.date, inSameDayAs: today) ? $0 : nil }
        let finished = finishedSessions(in: ctx)
        let streak = WorkoutSession.weekStreak(finished)
        let latest = finished.filter { !($0.sets ?? []).isEmpty }.map(\.date).max()
        WidgetSnapshot(day: todays == nil ? .distantPast : today,
                       focus: todays?.focus ?? "",
                       minutes: todays?.minutes ?? 0,
                       lifts: todays?.exercises.map(\.name) ?? [],
                       isRestDay: todays?.isRestDay ?? false,
                       weekStreak: streak,
                       streakWeek: streak > 0 ? latest.flatMap { cal.dateInterval(of: .weekOfYear, for: $0)?.start } : nil,
                       nextTraining: nextTrainingDay(after: today))
            .save()
    }

    /// Finished workouts from the last year, enough for any streak.
    @MainActor
    private static func finishedSessions(in ctx: ModelContext) -> [WorkoutSession] {
        let since = Calendar.current.date(byAdding: .weekOfYear, value: -53, to: .now) ?? .distantPast
        return (try? ctx.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endDate != nil && $0.date >= since }))) ?? []
    }

    /// The next of your training days after today, within a week.
    private static func nextTrainingDay(after today: Date) -> Date? {
        let cal = Calendar.current
        let days = SyncedSettings.trainingWeekdays
        return (1...7).lazy
            .compactMap { cal.date(byAdding: .day, value: $0, to: today) }
            .first { days.contains(cal.component(.weekday, from: $0)) }
    }
}
