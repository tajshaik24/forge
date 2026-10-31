import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.endDate != nil }, sort: \WorkoutSession.date, order: .reverse)
    private var sessions: [WorkoutSession]
    @Query(sort: \SetEntry.date) private var allSets: [SetEntry]
    @State private var mode: Mode = .workouts

    enum Mode: String, CaseIterable { case workouts = "Workouts", lifts = "Lifts" }

    private let unit = SyncedSettings.unit

    var body: some View {
        Group {
            if sessions.isEmpty {
                // Nothing to chart yet: an empty chart and picker under the message just collide with it.
                ContentUnavailableView("No workouts yet", systemImage: "dumbbell",
                                       description: Text("Finished workouts and your progress on each lift show up here."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        overview
                        Picker("View", selection: $mode) {
                            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        switch mode {
                        case .workouts: workouts
                        case .lifts: lifts
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground)
        .navigationTitle("History")
    }

    // MARK: Overview: last 8 weeks of volume + streak

    private var weeklyVolume: [(week: Date, volume: Double)] {
        let cal = Calendar.current
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return (0..<8).reversed().compactMap { offset in
            guard let start = cal.date(byAdding: .weekOfYear, value: -offset, to: thisWeek),
                  let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let v = sessions.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.volume }
            return (week: start, volume: unit.fromPounds(v))
        }
    }

    private var weekStreak: Int { WorkoutSession.weekStreak(sessions) }

    private var overview: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(sessions.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }.count)")
                        .font(Theme.mono(28))
                    Text("workouts this month").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(weekStreak)").font(Theme.mono(28))
                    Text("week streak").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
            SectionLabel("Weekly volume (\(unit.rawValue))")
            Chart(weeklyVolume, id: \.week) { w in
                BarMark(x: .value("Week", w.week, unit: .weekOfYear), y: .value("Volume", w.volume))
                    .foregroundStyle(Calendar.current.isDate(w.week, equalTo: .now, toGranularity: .weekOfYear) ? Theme.accent : Theme.readiness(0.6))
                    .cornerRadius(3)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
            .frame(height: 120)
        }
    }

    // MARK: Workouts

    private var workouts: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(sessions) { s in
                NavigationLink { SummaryView(session: s) } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.date.formatted(.dateTime.weekday(.abbreviated))).font(Theme.mono(12)).foregroundStyle(Theme.muted)
                            Text(s.date.formatted(.dateTime.month(.abbreviated).day())).font(Theme.mono(14))
                        }
                        .frame(width: 56, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.focus.uppercased()).font(.system(size: 16, weight: .heavy).width(.condensed))
                            Text("\(s.orderedSets.count) sets · \(unit.format(pounds: s.volume)) · \(Int(s.duration / 60)) min")
                                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if s.healthWorkoutID != nil {
                            Image(systemName: "heart.fill").foregroundStyle(Theme.accent).accessibilityLabel("Saved to Health")
                        }
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().overlay(Theme.hairline)
            }
        }
    }

    // MARK: Lifts: every exercise you've logged, with its best

    private struct LiftSummary: Identifiable {
        var id: String { name }
        let name: String
        let sessions: Int
        let bestE1RM: Double
        let lastDate: Date
    }

    private var liftSummaries: [LiftSummary] {
        Dictionary(grouping: allSets, by: \.exercise).map { name, sets in
            let days = Set(sets.map { Calendar.current.startOfDay(for: $0.date) })
            let best = sets.map { Progression.estimatedOneRepMax(weight: $0.weight, reps: $0.reps) }.max() ?? 0
            return LiftSummary(name: name, sessions: days.count, bestE1RM: best, lastDate: sets.map(\.date).max() ?? .distantPast)
        }
        .sorted { $0.lastDate > $1.lastDate }
    }

    private var lifts: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(liftSummaries) { lift in
                NavigationLink { LiftProgressView(name: lift.name) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lift.name).font(.system(size: 16, weight: .bold))
                            Text("\(lift.sessions) sessions · last \(lift.lastDate.formatted(.relative(presentation: .named)))")
                                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if lift.bestE1RM > 0 {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(unit.format(pounds: lift.bestE1RM)).font(Theme.mono(14))
                                Text("est. 1-rep max").font(.system(size: 10)).foregroundStyle(Theme.muted)
                            }
                        }
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().overlay(Theme.hairline)
            }
        }
    }
}

/// One lift over time: estimated 1-rep max and top set per session.
struct LiftProgressView: View {
    let name: String
    @Query private var sets: [SetEntry]
    private let unit = SyncedSettings.unit

    init(name: String) {
        self.name = name
        _sets = Query(filter: #Predicate<SetEntry> { $0.exercise == name }, sort: \SetEntry.date)
    }

    private struct Point: Identifiable {
        var id: Date { day }
        let day: Date
        let e1rm: Double
        let top: SetEntry
    }

    private var points: [Point] {
        Dictionary(grouping: sets) { Calendar.current.startOfDay(for: $0.date) }
            .compactMap { day, daySets in
                guard let top = daySets.max(by: {
                    Progression.estimatedOneRepMax(weight: $0.weight, reps: $0.reps) < Progression.estimatedOneRepMax(weight: $1.weight, reps: $1.reps)
                }) else { return nil }
                return Point(day: day, e1rm: unit.fromPounds(Progression.estimatedOneRepMax(weight: top.weight, reps: top.reps)), top: top)
            }
            .sorted { $0.day < $1.day }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(name.uppercased()).font(Theme.display(30))
                if let first = points.first, let last = points.last, points.count > 1 {
                    let change = last.e1rm - first.e1rm
                    Text("\(change >= 0 ? "+" : "")\(Int(change)) \(unit.rawValue) estimated 1-rep max since \(first.day.formatted(.dateTime.month().day()))")
                        .font(.system(size: 14)).foregroundStyle(change >= 0 ? Theme.accentText : Theme.muted)
                }
                Card {
                    SectionLabel("Estimated 1-rep max (\(unit.rawValue))")
                    Chart(points) { p in
                        LineMark(x: .value("Date", p.day), y: .value("e1RM", p.e1rm))
                            .foregroundStyle(Theme.accent)
                        PointMark(x: .value("Date", p.day), y: .value("e1RM", p.e1rm))
                            .foregroundStyle(Theme.accent)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 180)
                }
                SectionLabel("Top set each session")
                ForEach(points.reversed()) { p in
                    HStack {
                        Text(p.day.formatted(.dateTime.month(.abbreviated).day())).font(Theme.mono(13)).foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(unit.format(pounds: p.top.weight)) × \(p.top.reps)").font(Theme.mono(14))
                    }
                    Divider().overlay(Theme.hairline)
                }
                NavigationLink("How to do it") { ExerciseDetailView(name: name) }
            }
            .padding(20)
        }
        .background(Theme.ground)
    }
}
