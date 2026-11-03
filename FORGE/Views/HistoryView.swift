import SwiftUI
import SwiftData
import Charts

/// Streaks and the training calendar, recent personal records, then every workout by week
/// or every lift with its progress.
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
                let model = HistoryModel(sessions: sessions, sets: allSets)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        streakCard(model)
                        if !model.recentRecords.isEmpty { records(model) }
                        VStack(alignment: .leading, spacing: 14) {
                            Picker("View", selection: $mode) {
                                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                            }
                            .pickerStyle(.segmented)
                            switch mode {
                            case .workouts: workouts(model)
                            case .lifts: lifts(model)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .demoScrollAnchor()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground)
        .navigationTitle("History")
        .onAppear {
            #if DEBUG
            if let m = DemoArgs.value("-historyMode").flatMap(Mode.init(rawValue:)) { mode = m }
            #endif
        }
    }

    // MARK: Streak, calendar, totals

    private func streakCard(_ model: HistoryModel) -> some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(model.weekStreak)").font(Theme.display(48)).monospacedDigit()
                VStack(alignment: .leading, spacing: 0) {
                    Text("week streak").font(.system(size: 16, weight: .bold))
                    Text(model.weekStreak == 0 ? "Train this week to start one" : "in a row with a workout")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            TrainingHeatmap(calendar: model.calendar)
                .padding(.top, 2)
            Divider().overlay(Theme.hairline)
            HStack(spacing: 8) {
                StatTile(value: "\(model.thisMonth)", label: "This month")
                StatTile(value: "\(sessions.count)", label: "Workouts")
                StatTile(value: model.totalSets.formatted(), label: "Sets")
                StatTile(value: HistoryTotals.compact(unit.fromPounds(model.totalVolume)), label: "\(unit.rawValue) lifted")
            }
        }
    }

    // MARK: Personal records

    private func records(_ model: HistoryModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Recent personal records")
            VStack(spacing: 0) {
                ForEach(Array(model.recentRecords.enumerated()), id: \.element.id) { i, record in
                    if i > 0 { Divider().overlay(Theme.hairline).padding(.leading, 52) }
                    NavigationLink { LiftProgressView(name: record.exercise) } label: { recordRow(record) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.hairline))
        }
    }

    private func recordRow(_ record: RecordEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Gold.fill)
                .frame(width: 30, height: 30)
                .background(Gold.wash, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(record.exercise).font(.system(size: 15, weight: .bold)).lineLimit(2)
                Text("\(record.kind.short(record.exercise)) · \(record.set.date.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            Text(SetText.of(record.set, exercise: record.exercise, unit: unit))
                .font(Theme.mono(14)).foregroundStyle(Gold.text).lineLimit(1).fixedSize()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    // MARK: Workouts, by week

    private func workouts(_ model: HistoryModel) -> some View {
        LazyVStack(alignment: .leading, spacing: 20) {
            ForEach(model.weeks, id: \.start) { week in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        SectionLabel(weekTitle(week.start))
                        Spacer()
                        Text("\(week.sessions.count) \(week.sessions.count == 1 ? "workout" : "workouts") · \(HistoryTotals.compact(unit.fromPounds(week.volume))) \(unit.rawValue)")
                            .font(Theme.mono(11, .medium)).foregroundStyle(Theme.muted)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(week.sessions.enumerated()), id: \.element.persistentModelID) { i, s in
                            if i > 0 { Divider().overlay(Theme.hairline).padding(.leading, 62) }
                            NavigationLink { SummaryView(session: s) } label: {
                                workoutRow(s, records: model.recordCount[s.persistentModelID] ?? 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.hairline))
                }
            }
        }
    }

    private func weekTitle(_ start: Date) -> String {
        let cal = Calendar.current
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start
        if start == thisWeek { return "This week" }
        if let thisWeek, cal.date(byAdding: .weekOfYear, value: -1, to: thisWeek) == start { return "Last week" }
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        let sameMonth = cal.isDate(start, equalTo: end, toGranularity: .month)
        return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(sameMonth ? end.formatted(.dateTime.day()) : end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func workoutRow(_ s: WorkoutSession, records: Int) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(s.date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
                Text(s.date.formatted(.dateTime.day())).font(Theme.mono(18))
            }
            .frame(width: 40, height: 44)
            .background(Theme.ground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(s.focus.uppercased()).font(.system(size: 16, weight: .heavy).width(.condensed)).lineLimit(1)
                Text("\(s.orderedSets.count) sets · \(HistoryTotals.compact(unit.fromPounds(s.volume))) \(unit.rawValue) · \(Int(s.duration / 60)) min")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 6)
            if records > 0 { TrophyTag(text: records == 1 ? "PB" : "\(records) PB") }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: Lifts

    private func lifts(_ model: HistoryModel) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(model.lifts.enumerated()), id: \.element.name) { i, lift in
                if i > 0 { Divider().overlay(Theme.hairline) }
                NavigationLink { LiftProgressView(name: lift.name) } label: { liftRow(lift) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.hairline))
    }

    private func liftRow(_ lift: HistoryModel.Lift) -> some View {
        let metric: LiftMetric = lift.series.isWeighted ? .estimatedMax : .bestReps
        let recent = Array(lift.series.points.suffix(12))
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(lift.name).font(.system(size: 15, weight: .bold)).lineLimit(2)
                Text("\(lift.series.points.count) \(lift.series.points.count == 1 ? "session" : "sessions") · \(lift.lastDate.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            if recent.count > 1 {
                Chart(recent) { p in
                    LineMark(x: .value("Day", p.day), y: .value("Value", p.value(metric)))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(Theme.accent)
                }
                .chartXAxis(.hidden).chartYAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(width: 48, height: 26)
                .accessibilityHidden(true)
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(lift.series.isWeighted ? unit.format(pounds: lift.series.best(.estimatedMax)?.estimatedMax ?? 0)
                     : "\(lift.series.best(.bestReps)?.bestReps ?? 0)\(lift.isTimed ? " s" : "")")
                    .font(Theme.mono(14)).lineLimit(1).fixedSize()
                Text(lift.series.isWeighted ? "best est. max" : (lift.isTimed ? "longest" : "most reps"))
                    .font(.system(size: 10)).foregroundStyle(Theme.muted).fixedSize()
            }
            // Same width on every row, so the sparklines line up.
            .frame(minWidth: 76, alignment: .trailing)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// Everything History shows, worked out once per render from the queried sessions and sets.
private struct HistoryModel {
    struct Week { let start: Date; let sessions: [WorkoutSession]; let volume: Double }
    struct Lift { let name: String; let series: LiftSeries; let lastDate: Date; let isTimed: Bool }

    let weekStreak: Int
    let calendar: TrainingCalendar
    let thisMonth: Int
    let totalSets: Int
    let totalVolume: Double
    let recentRecords: [RecordEvent]
    let weeks: [Week]
    let lifts: [Lift]
    /// Records broken in each workout.
    let recordCount: [PersistentIdentifier: Int]

    init(sessions: [WorkoutSession], sets: [SetEntry]) {
        let cal = Calendar.current
        weekStreak = WorkoutSession.weekStreak(sessions)
        calendar = TrainingCalendar(trainedOn: sessions.map(\.date))
        thisMonth = HistoryTotals.thisMonth(sessions.map(\.date))
        let finished = sets.filter { $0.session?.endDate != nil }
        totalSets = finished.count
        totalVolume = HistoryTotals.volume(finished.map(SetRecord.init))

        let byExercise = Dictionary(grouping: finished, by: \.exercise).mapValues { $0.map(SetRecord.init) }
        recentRecords = RecordHistory.recent(byExercise)
        var broken = Set<String>()
        for (name, records) in byExercise {
            for e in RecordHistory.events(for: name, sets: records) { broken.insert("\(name)|\(e.set.date.timeIntervalSince1970)") }
        }
        var counts: [PersistentIdentifier: Int] = [:]
        for s in sessions {
            // One per lift: three heavier sets of bench is one record, not three.
            let lifts = Set((s.sets ?? []).filter { broken.contains("\($0.exercise)|\($0.date.timeIntervalSince1970)") }.map(\.exercise))
            if !lifts.isEmpty { counts[s.persistentModelID] = lifts.count }
        }
        recordCount = counts

        weeks = Dictionary(grouping: sessions) { cal.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date }
            .map { Week(start: $0.key, sessions: $0.value.sorted { $0.date > $1.date }, volume: $0.value.reduce(0) { $0 + $1.volume }) }
            .sorted { $0.start > $1.start }
        lifts = byExercise.map { name, records in
            Lift(name: name, series: LiftSeries(records), lastDate: records.map(\.date).max() ?? .distantPast,
                 isTimed: ExerciseCatalog.named(name)?.isTimed ?? false)
        }
        .sorted { $0.lastDate > $1.lastDate }
    }
}

// MARK: - One lift

/// One lift over time: the chart with your best marked, best sets, and every session's sets.
struct LiftProgressView: View {
    let name: String
    @Query private var sets: [SetEntry]
    @State private var metric: LiftMetric?
    @State private var selectedDay: Date?
    @State private var expanded: Set<Date> = []
    private let unit = SyncedSettings.unit

    init(name: String) {
        self.name = name
        _sets = Query(filter: #Predicate<SetEntry> { $0.exercise == name }, sort: \SetEntry.date)
    }

    private var exercise: Exercise? { ExerciseCatalog.named(name) }
    private var isTimed: Bool { exercise?.isTimed ?? false }

    var body: some View {
        let records = sets.filter { $0.session?.endDate != nil }.map(SetRecord.init)
        let series = LiftSeries(records)
        let chosen = metric ?? LiftMetric.options(weighted: series.isWeighted)[0]
        let events = RecordHistory.events(for: name, sets: records)
        let recordKinds = Dictionary(events.map { ($0.set, $0.kind) }, uniquingKeysWith: { a, _ in a })
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if series.points.isEmpty {
                    ContentUnavailableView("No sets yet", systemImage: "chart.line.uptrend.xyaxis",
                                           description: Text("Log this lift in a workout to see your progress."))
                } else {
                    chartCard(series, chosen)
                    bests(records, series)
                    activity(series, recordKinds)
                }
                NavigationLink { ExerciseDetailView(name: name) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .foregroundStyle(Theme.accentText).frame(width: 30, height: 30)
                            .background(Theme.accentWash, in: Circle())
                        Text("How to do it").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                    }
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.hairline))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .demoScrollAnchor()
        .background(Theme.ground)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if expanded.isEmpty, let last = series.latest?.day { expanded = [last] } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name.uppercased()).font(Theme.display(28)).lineLimit(3).minimumScaleFactor(0.7)
            if let ex = exercise {
                Text(([ex.primary] + ex.secondary).map(\.label).joined(separator: " · "))
                    .font(.system(size: 14)).foregroundStyle(Theme.muted)
            }
        }
    }

    // MARK: Chart

    private func display(_ value: Double, _ metric: LiftMetric) -> String {
        switch metric {
        case .estimatedMax, .topWeight: unit.format(pounds: value, withUnit: false)
        case .volume: HistoryTotals.compact(unit.fromPounds(value))
        case .bestReps, .totalReps: "\(Int(value))"
        }
    }

    private func suffix(_ metric: LiftMetric) -> String {
        switch metric {
        case .estimatedMax, .topWeight, .volume: unit.rawValue
        case .bestReps, .totalReps: isTimed ? "s" : "reps"
        }
    }

    private func title(_ metric: LiftMetric) -> String {
        switch metric {
        case .estimatedMax: "Estimated max"
        case .topWeight: "Top weight"
        case .volume: "Volume"
        case .bestReps: isTimed ? "Longest set" : "Most reps in a set"
        case .totalReps: isTimed ? "Total time" : "Total reps"
        }
    }

    private func chartCard(_ series: LiftSeries, _ chosen: LiftMetric) -> some View {
        let options = LiftMetric.options(weighted: series.isWeighted)
        let selected = selectedDay.flatMap { day in
            series.points.min { abs($0.day.timeIntervalSince(day)) < abs($1.day.timeIntervalSince(day)) }
        }
        let shown = selected ?? series.latest
        let best = series.best(chosen)
        let values = series.points.map { $0.value(chosen) }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.15, hi * 0.03, 1)
        return Card {
            Picker("Metric", selection: Binding(get: { chosen }, set: { metric = $0 })) {
                ForEach(options) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(selected != nil ? "\(title(chosen)) · \(selected!.day.formatted(.dateTime.month(.abbreviated).day()))"
                             : title(chosen))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(shown.map { display($0.value(chosen), chosen) } ?? "–")
                        .font(Theme.display(44)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    Text(suffix(chosen)).font(Theme.mono(15, .medium)).foregroundStyle(Theme.muted)
                    if let shown, shown == best, series.points.count > 1 { TrophyTag() }
                    Spacer(minLength: 0)
                }
                if selected == nil {
                    HStack(spacing: 8) {
                        change(series.change(chosen, overWeeks: 4), chosen, "4 wk")
                        change(series.change(chosen, overWeeks: 12), chosen, "12 wk")
                    }
                } else if let top = selected?.topSet {
                    Text("Top set \(SetText.of(top, exercise: name, unit: unit)) · \(selected!.sets.count) sets")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
            }

            Chart {
                ForEach(series.points) { p in
                    AreaMark(x: .value("Date", p.day), yStart: .value("Base", lo - pad), yEnd: .value(title(chosen), p.value(chosen)))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.0)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", p.day), y: .value(title(chosen), p.value(chosen)))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(Theme.accent)
                }
                if let best {
                    PointMark(x: .value("Date", best.day), y: .value(title(chosen), best.value(chosen)))
                        .symbol { trophyMark }
                        .annotation(position: .top, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            TrophyTag(text: display(best.value(chosen), chosen))
                        }
                }
                if let selected {
                    RuleMark(x: .value("Date", selected.day))
                        .foregroundStyle(Theme.muted.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    PointMark(x: .value("Date", selected.day), y: .value(title(chosen), selected.value(chosen)))
                        .foregroundStyle(Theme.accent)
                        .symbolSize(60)
                }
            }
            .chartYScale(domain: (lo - pad)...(hi + pad * 2.2))
            .chartXSelection(value: $selectedDay)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(Theme.muted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel {
                        if let d = v.as(Double.self) { Text(display(d, chosen)).foregroundStyle(Theme.muted) }
                    }
                }
            }
            .frame(height: 200)
            .accessibilityLabel("\(title(chosen)) over time")
        }
    }

    private var trophyMark: some View {
        Image(systemName: "trophy.circle.fill")
            .font(.system(size: 18))
            .symbolRenderingMode(.palette)
            .foregroundStyle(Theme.onAccent, Gold.fill)
    }

    @ViewBuilder
    private func change(_ delta: Double?, _ metric: LiftMetric, _ span: String) -> some View {
        if let delta {
            let up = delta > 0.5
            let flat = abs(delta) <= 0.5
            let magnitude = metric == .volume ? HistoryTotals.compact(unit.fromPounds(abs(delta)))
                : (metric == .bestReps || metric == .totalReps ? "\(Int(abs(delta).rounded()))" : unit.format(pounds: abs(delta), withUnit: false))
            Label(flat ? "Same as \(span) ago" : "\(magnitude) \(suffix(metric)) vs \(span) ago",
                  systemImage: flat ? "equal" : (up ? "arrow.up.right" : "arrow.down.right"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(up ? Theme.accentText : Theme.muted)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(up ? Theme.accentWash : Theme.raised.opacity(0.6), in: Capsule())
                .lineLimit(1)
        }
    }

    // MARK: Bests

    private func bests(_ records: [SetRecord], _ series: LiftSeries) -> some View {
        let best = PersonalRecords.best(in: records)
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Personal bests")
            HStack(spacing: 8) {
                if series.isWeighted {
                    bestTile("Heaviest", best.heaviest.map { SetText.of($0, exercise: name, unit: unit) }, best.heaviest?.date)
                    bestTile("Est. max", best.estimatedMax.map { unit.format(pounds: $0) }, series.best(.estimatedMax)?.day)
                    bestTile("Most reps", best.mostReps.map { "\($0.reps)" }, best.mostReps?.date)
                } else {
                    bestTile(isTimed ? "Longest" : "Most reps", best.mostReps.map { "\($0.reps)\(isTimed ? " s" : "")" }, best.mostReps?.date)
                    bestTile(isTimed ? "Best day" : "Best day", series.best(.totalReps).map { "\($0.totalReps)\(isTimed ? " s" : "")" },
                             series.best(.totalReps)?.day)
                    bestTile("Sessions", "\(series.points.count)", nil)
                }
            }
        }
    }

    private func bestTile(_ label: String, _ value: String?, _ date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(Theme.muted)
            Text(value ?? "–").font(Theme.mono(15)).lineLimit(1).minimumScaleFactor(0.6)
            Text(date?.formatted(.dateTime.month(.abbreviated).day()) ?? " ")
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.hairline))
        .accessibilityElement(children: .combine)
    }

    // MARK: Activity

    private func activity(_ series: LiftSeries, _ recordKinds: [SetRecord: PersonalRecords.Kind]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Activity")
            VStack(spacing: 0) {
                ForEach(Array(series.points.reversed().enumerated()), id: \.element.id) { i, p in
                    if i > 0 { Divider().overlay(Theme.hairline) }
                    activityRow(p, recordKinds)
                }
            }
            .padding(.horizontal, 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.hairline))
        }
    }

    private func activityRow(_ p: LiftSeries.Point, _ recordKinds: [SetRecord: PersonalRecords.Kind]) -> some View {
        let open = expanded.contains(p.day)
        let hasRecord = p.sets.contains { recordKinds[$0] != nil }
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    if open { expanded.remove(p.day) } else { expanded.insert(p.day) }
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(.system(size: 15, weight: .semibold))
                        Text("\(p.sets.count) \(p.sets.count == 1 ? "set" : "sets")\(p.topSet.map { " · top \(SetText.of($0, exercise: name, unit: unit))" } ?? "")")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if hasRecord { TrophyTag() }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Hides the sets" : "Shows the sets")
            if open {
                VStack(spacing: 6) {
                    ForEach(Array(p.sets.enumerated()), id: \.offset) { i, set in
                        let kind = recordKinds[set]
                        HStack(spacing: 12) {
                            Text("\(i + 1)").font(Theme.mono(12, .medium)).foregroundStyle(Theme.muted).frame(width: 18, alignment: .leading)
                            Text(SetText.of(set, exercise: name, unit: unit)).font(Theme.mono(14))
                                .foregroundStyle(kind != nil ? Gold.text : Theme.text)
                            Spacer()
                            if let kind {
                                Label(kind.short(name), systemImage: "trophy.fill")
                                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Gold.text)
                            } else if let rpe = set.rpe {
                                Text(Effort(rpe: rpe).label).font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(kind != nil ? Gold.wash : Theme.ground.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
    }
}
