import Foundation

// The numbers behind History, lift progress and the workout summary, kept free of SwiftData and
// SwiftUI so they're easy to test. Views turn `WorkoutSession` / `SetEntry` into `SetRecord`s first.

// MARK: - Training calendar

/// The last few weeks as a grid, one column per week (oldest first) and one cell per day,
/// Monday or Sunday first as the calendar says.
struct TrainingCalendar: Equatable {
    struct Day: Hashable, Identifiable {
        var id: Date { date }
        let date: Date
        let trained: Bool
        let isToday: Bool
        let isFuture: Bool
    }

    /// `weeks.count` columns of seven days each.
    let weeks: [[Day]]

    init(trainedOn dates: [Date], weeks count: Int = 12, now: Date = .now, calendar cal: Calendar = .current) {
        let trained = Set(dates.map { cal.startOfDay(for: $0) })
        let today = cal.startOfDay(for: now)
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start else { weeks = []; return }
        weeks = (0..<max(count, 1)).reversed().compactMap { back in
            guard let start = cal.date(byAdding: .weekOfYear, value: -back, to: thisWeek) else { return nil }
            return (0..<7).compactMap { offset in
                guard let day = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
                return Day(date: day, trained: trained.contains(day), isToday: day == today, isFuture: day > today)
            }
        }
    }

    var trainedDays: Int { weeks.joined().filter(\.trained).count }
}

// MARK: - Totals

enum HistoryTotals {
    /// Workouts started in the same calendar month as `now`.
    static func thisMonth(_ dates: [Date], now: Date = .now, calendar cal: Calendar = .current) -> Int {
        dates.filter { cal.isDate($0, equalTo: now, toGranularity: .month) }.count
    }

    /// Pounds lifted: weight × reps, summed. Bodyweight sets add nothing.
    static func volume(_ sets: [SetRecord]) -> Double {
        sets.reduce(0) { $0 + $1.weight * Double($1.reps) }
    }

    /// "12.4k" / "860": short enough for a stat tile.
    static func compact(_ value: Double) -> String {
        switch value {
        case 1_000_000...: String(format: "%.1fM", value / 1_000_000)
        case 10_000...: String(format: "%.0fk", value / 1000)
        case 1000...: String(format: "%.1fk", value / 1000)
        default: "\(Int(value.rounded()))"
        }
    }
}

// MARK: - Personal records over time

/// A set that beat everything before it on that lift.
struct RecordEvent: Hashable, Identifiable {
    var id: String { "\(exercise)|\(set.date.timeIntervalSince1970)" }
    let exercise: String
    let set: SetRecord
    let kind: PersonalRecords.Kind
}

enum RecordHistory {
    /// Every set that broke a record, judged against the earlier sets of the same lift
    /// (`PersonalRecords.broken(by:history:)`), oldest first.
    static func events(for exercise: String, sets: [SetRecord]) -> [RecordEvent] {
        let sorted = sets.sorted { $0.date < $1.date }
        var before: [SetRecord] = []
        var out: [RecordEvent] = []
        for set in sorted {
            if let kind = PersonalRecords.broken(by: set, history: before) {
                out.append(RecordEvent(exercise: exercise, set: set, kind: kind))
            }
            before.append(set)
        }
        return out
    }

    /// The most recent records across lifts, newest first: at most one per lift per day (the
    /// best of that day), so a good session doesn't fill the list with one lift.
    static func recent(_ byExercise: [String: [SetRecord]], limit: Int = 5, calendar cal: Calendar = .current) -> [RecordEvent] {
        var picked: [RecordEvent] = []
        for (name, sets) in byExercise {
            let events = events(for: name, sets: sets)
            let byDay = Dictionary(grouping: events) { cal.startOfDay(for: $0.set.date) }
            picked += byDay.values.compactMap { day in day.max { score($0) < score($1) } }
        }
        return Array(picked.sorted { $0.set.date > $1.set.date }.prefix(limit))
    }

    /// Records set in one workout: the best per lift, in workout order.
    static func inSession(_ sessionSets: [String: [SetRecord]], history: [String: [SetRecord]]) -> [RecordEvent] {
        var out: [RecordEvent] = []
        for (name, sets) in sessionSets {
            let mine = Set(sets)
            let hits = events(for: name, sets: history[name] ?? sets).filter { mine.contains($0.set) }
            if let best = hits.max(by: { score($0) < score($1) }) { out.append(best) }
        }
        return out.sorted { $0.set.date < $1.set.date }
    }

    /// Which of a workout's sets broke a record, to mark them where they're listed.
    static func brokenSets(_ sessionSets: [String: [SetRecord]], history: [String: [SetRecord]]) -> [SetRecord: PersonalRecords.Kind] {
        var out: [SetRecord: PersonalRecords.Kind] = [:]
        for (name, sets) in sessionSets {
            let mine = Set(sets)
            for e in events(for: name, sets: history[name] ?? sets) where mine.contains(e.set) { out[e.set] = e.kind }
        }
        return out
    }

    private static func score(_ e: RecordEvent) -> Double {
        e.set.weight > 0 ? Strength.estimatedMax(weight: e.set.weight, reps: e.set.reps, rpe: nil) : Double(e.set.reps)
    }
}

// MARK: - One lift over time

/// What a lift's chart can plot. Bodyweight and timed moves have no weight, so they plot reps.
enum LiftMetric: String, CaseIterable, Identifiable {
    case estimatedMax = "Est. max"
    case topWeight = "Top weight"
    case volume = "Volume"
    case bestReps = "Best set"
    case totalReps = "Total"

    var id: String { rawValue }

    static func options(weighted: Bool) -> [LiftMetric] {
        weighted ? [.estimatedMax, .topWeight, .volume] : [.bestReps, .totalReps]
    }
}

/// A lift's sessions, one point per day trained.
struct LiftSeries {
    struct Point: Identifiable, Hashable {
        var id: Date { day }
        let day: Date
        let sets: [SetRecord]

        /// Pounds, the day's best Epley estimate (no RPE, like `PersonalRecords`).
        var estimatedMax: Double {
            sets.filter { $0.weight > 0 }.map { Strength.estimatedMax(weight: $0.weight, reps: $0.reps, rpe: nil) }.max() ?? 0
        }
        var topWeight: Double { sets.map(\.weight).max() ?? 0 }
        var volume: Double { HistoryTotals.volume(sets) }
        var bestReps: Int { sets.map(\.reps).max() ?? 0 }
        var totalReps: Int { sets.reduce(0) { $0 + $1.reps } }
        /// The set that made the day's estimated max (or most reps, without weight).
        var topSet: SetRecord? {
            sets.max { a, b in
                a.weight > 0 || b.weight > 0
                    ? (Strength.estimatedMax(weight: a.weight, reps: a.reps, rpe: nil), a.weight) < (Strength.estimatedMax(weight: b.weight, reps: b.reps, rpe: nil), b.weight)
                    : a.reps < b.reps
            }
        }

        func value(_ metric: LiftMetric) -> Double {
            switch metric {
            case .estimatedMax: estimatedMax
            case .topWeight: topWeight
            case .volume: volume
            case .bestReps: Double(bestReps)
            case .totalReps: Double(totalReps)
            }
        }
    }

    /// Oldest first.
    let points: [Point]
    /// Any set with weight: chart weight. None: chart reps (or seconds).
    let isWeighted: Bool

    init(_ sets: [SetRecord], calendar cal: Calendar = .current) {
        points = Dictionary(grouping: sets) { cal.startOfDay(for: $0.date) }
            .map { Point(day: $0.key, sets: $0.value.sorted { $0.date < $1.date }) }
            .sorted { $0.day < $1.day }
        isWeighted = sets.contains { $0.weight > 0 }
    }

    var latest: Point? { points.last }

    /// The point with the highest value: the personal best on the chart.
    func best(_ metric: LiftMetric) -> Point? {
        // Ties go to the earliest, the day the record was first set.
        points.reduce(nil) { best, p in (best.map { p.value(metric) > $0.value(metric) } ?? true) ? p : best }
    }

    /// Latest value minus the value on the last day trained at least `weeks` weeks before it.
    /// Nil without a session that far back.
    func change(_ metric: LiftMetric, overWeeks weeks: Int, now: Date = .now, calendar cal: Calendar = .current) -> Double? {
        guard let latest, let cutoff = cal.date(byAdding: .day, value: -7 * weeks, to: cal.startOfDay(for: now)),
              let then = points.last(where: { $0.day <= cutoff }) else { return nil }
        return latest.value(metric) - then.value(metric)
    }
}
