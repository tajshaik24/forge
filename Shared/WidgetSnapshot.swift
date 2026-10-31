import Foundation
import WidgetKit

/// What the widgets and Watch complications show. The app writes it to the shared App Group
/// whenever today's plan or your history changes; the widget extensions only read it.
struct WidgetSnapshot: Codable, Equatable {
    /// Start of the day the plan is for. An older snapshot means the app hasn't planned today yet.
    var day: Date
    var focus: String
    var minutes: Int
    var lifts: [String]
    var isRestDay: Bool
    var weekStreak: Int
    /// Start of the last week that counted toward the streak.
    var streakWeek: Date?
    var nextTraining: Date?

    static let appGroup = "group.com.taj.forge"
    private static let key = "widgetSnapshot"

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Saves and redraws the widgets, only when something changed.
    func save() {
        guard self != Self.load(), let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
        WidgetCenter.shared.reloadAllTimelines()
    }

    var isToday: Bool { Calendar.current.isDateInToday(day) }

    /// The streak as of `date`: it ends once a whole week passes with no workout, even if the app isn't opened.
    func streak(on date: Date) -> Int {
        let cal = Calendar.current
        guard let streakWeek, let thisWeek = cal.dateInterval(of: .weekOfYear, for: date)?.start,
              let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeek) else { return 0 }
        return streakWeek >= lastWeek ? weekStreak : 0
    }

    /// "6 lifts · 45 min"
    var summary: String { "\(lifts.count) \(lifts.count == 1 ? "lift" : "lifts") · \(minutes) min" }

    /// "Next: Tue", or nil when no training day is set.
    var nextLabel: String? {
        nextTraining.map { "Next: " + $0.formatted(.dateTime.weekday(.abbreviated)) }
    }

    /// Shown in the widget gallery and before the app has written anything.
    static let sample = WidgetSnapshot(day: .now, focus: "Pull", minutes: 45,
                                       lifts: ["Pull-up", "Chest-supported row", "Face pull", "Hammer curl"],
                                       isRestDay: false, weekStreak: 6, streakWeek: .now, nextTraining: nil)
}
