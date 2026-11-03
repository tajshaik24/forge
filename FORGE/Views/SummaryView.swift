import SwiftUI
import SwiftData
import Charts

/// A finished workout: the headline numbers, records broken, muscles worked, heart rate,
/// every set by lift (tap to fix one), and how it felt, which the coach plans from.
struct SummaryView: View {
    @Bindable var session: WorkoutSession
    /// Set when shown at the end of a workout: adds a Done button. Nil when opened from History.
    var onDone: (() -> Void)?
    @Environment(\.modelContext) private var ctx
    @Environment(CoachStore.self) private var coach
    @Query(sort: \SetEntry.date) private var allSets: [SetEntry]
    @State private var editing: SetEntry?
    private let unit = SyncedSettings.unit

    init(session: WorkoutSession, onDone: (() -> Void)? = nil) {
        self.session = session
        self.onDone = onDone
    }

    var body: some View {
        let groups = groupedSets
        let mine = Dictionary(uniqueKeysWithValues: groups.map { ($0.name, $0.sets.map(SetRecord.init)) })
        let history = historyByLift(Set(mine.keys))
        let broken = RecordHistory.brokenSets(mine, history: history)
        let records = RecordHistory.inSession(mine, history: history)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                stats
                if !records.isEmpty { recordsCard(records) }
                if !muscles.isEmpty { musclesCard }
                if !session.heartRates.isEmpty { heartRateCard }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        SectionLabel("Sets")
                        Spacer()
                        Text("Tap a set to fix it").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    ForEach(groups, id: \.name) { group in liftCard(group.name, group.sets, broken) }
                }
                feelCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .demoScrollAnchor()
        .background(Theme.ground)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let onDone {
                Button("Done", action: onDone).buttonStyle(AccentButtonStyle())
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Theme.ground)
            }
        }
        .sheet(item: $editing) { EditSetSheet(entry: $0, unit: unit) }
        // How it felt shapes the rest of the week's plans.
        .onChange(of: session.feel) {
            try? ctx.save()
            Task { await coach.planWeek(ctx, force: true) }
        }
    }

    // MARK: Header and numbers

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(session.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) · \(session.gymName)".uppercased())
                .font(Theme.mono(12)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
            Text(session.focus.uppercased()).font(Theme.display(40)).lineLimit(2).minimumScaleFactor(0.6)
            HStack(spacing: 14) {
                if let end = session.endDate {
                    Label("\(session.date.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))",
                          systemImage: "clock")
                }
                Label(session.healthWorkoutID != nil ? "In Apple Health" : "Not in Apple Health",
                      systemImage: session.healthWorkoutID != nil ? "heart.fill" : "heart.slash")
            }
            .font(.system(size: 13)).foregroundStyle(Theme.muted)
            .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private var stats: some View {
        Card {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    StatTile(value: durationText, label: "Time")
                    StatTile(value: "\(session.orderedSets.count)", label: "Sets")
                    StatTile(value: HistoryTotals.compact(unit.fromPounds(session.volume)), label: "Volume", unit: unit.rawValue)
                }
                Divider().overlay(Theme.hairline).gridCellColumns(3)
                GridRow {
                    StatTile(value: session.averageHeartRate > 0 ? "\(Int(session.averageHeartRate))" : "–", label: "Avg heart rate",
                             unit: session.averageHeartRate > 0 ? "bpm" : nil)
                    StatTile(value: session.maxHeartRate > 0 ? "\(Int(session.maxHeartRate))" : "–", label: "Max heart rate",
                             unit: session.maxHeartRate > 0 ? "bpm" : nil)
                    StatTile(value: session.activeCalories > 0 ? "\(Int(session.activeCalories))" : "–", label: "Active",
                             unit: session.activeCalories > 0 ? "kcal" : nil)
                }
            }
        }
    }

    private var durationText: String {
        let minutes = Int(session.duration / 60)
        return minutes >= 60 ? String(format: "%d:%02d", minutes / 60, minutes % 60) : "\(minutes) min"
    }

    // MARK: Records

    private func recordsCard(_ records: [RecordEvent]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill").foregroundStyle(Gold.fill)
                Text(records.count == 1 ? "New personal record" : "\(records.count) new personal records")
                    .font(.system(size: 16, weight: .heavy))
            }
            ForEach(records) { r in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.exercise).font(.system(size: 15, weight: .bold)).lineLimit(1)
                        Text(r.kind.long(r.exercise)).font(.system(size: 12)).foregroundStyle(Gold.text)
                    }
                    Spacer(minLength: 8)
                    Text(SetText.of(r.set, exercise: r.exercise, unit: unit))
                        .font(Theme.mono(15)).foregroundStyle(Gold.text).fixedSize()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Gold.wash, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Gold.edge))
    }

    // MARK: Muscles

    /// Working sets per muscle: a full set for the main muscle, half for helpers.
    private var muscles: [(muscle: MuscleGroup, sets: Double)] {
        Readiness.summarize(session).setsByMuscle.map { ($0.key, $0.value) }
            .sorted { $0.sets != $1.sets ? $0.sets > $1.sets : $0.muscle.label < $1.muscle.label }
    }

    private var musclesCard: some View {
        let top = muscles.first?.sets ?? 1
        return Card {
            SectionLabel("Muscles worked")
            VStack(spacing: 8) {
                ForEach(muscles, id: \.muscle) { m in
                    HStack(spacing: 10) {
                        Text(m.muscle.label).font(.system(size: 14)).frame(width: 92, alignment: .leading)
                        GeometryReader { geo in
                            Capsule().fill(Theme.raised.opacity(0.6))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Theme.readiness(m.sets >= top * 0.75 ? 1 : (m.sets >= top * 0.4 ? 0.75 : 0.6)))
                                        .frame(width: max(8, geo.size.width * m.sets / top))
                                }
                        }
                        .frame(height: 8)
                        Text(m.sets.formatted(.number.precision(.fractionLength(0...1))))
                            .font(Theme.mono(12, .medium)).foregroundStyle(Theme.muted)
                            .frame(width: 30, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(m.muscle.label): \(m.sets.formatted()) sets")
                }
            }
            Text("Sets, counting half for muscles that help.").font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
    }

    // MARK: Heart rate

    private var heartRateCard: some View {
        let rates = session.heartRates
        return Card {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Heart rate")
                Spacer()
                Text("AVG \(Int(session.averageHeartRate)) · MAX \(Int(session.maxHeartRate))")
                    .font(Theme.mono(12)).foregroundStyle(Theme.muted)
            }
            Chart(Array(rates.enumerated()), id: \.offset) { i, bpm in
                AreaMark(x: .value("Minutes", Double(i) * 15 / 60), yStart: .value("Low", (rates.min() ?? 60) - 10),
                         yEnd: .value("BPM", bpm))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.25), Theme.accent.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Minutes", Double(i) * 15 / 60), y: .value("BPM", bpm))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .foregroundStyle(Theme.accent)
            }
            .chartYScale(domain: ((rates.min() ?? 60) - 10)...((rates.max() ?? 180) + 8))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { v in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel { if let m = v.as(Double.self) { Text("\(Int(m)) min").foregroundStyle(Theme.muted) } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel().foregroundStyle(Theme.muted)
                }
            }
            .frame(height: 120)
            .accessibilityLabel("Heart rate, average \(Int(session.averageHeartRate)), max \(Int(session.maxHeartRate))")
        }
    }

    // MARK: Sets by lift

    private var groupedSets: [(name: String, sets: [SetEntry])] {
        var order: [String] = []
        var byName: [String: [SetEntry]] = [:]
        for s in session.orderedSets {
            if byName[s.exercise] == nil { order.append(s.exercise) }
            byName[s.exercise, default: []].append(s)
        }
        return order.map { ($0, byName[$0] ?? []) }
    }

    /// Every finished set of these lifts, plus this workout's, for judging records.
    private func historyByLift(_ names: Set<String>) -> [String: [SetRecord]] {
        let id = session.persistentModelID
        return Dictionary(grouping: allSets.filter {
            names.contains($0.exercise) && ($0.session?.endDate != nil || $0.session?.persistentModelID == id)
        }, by: \.exercise).mapValues { $0.map(SetRecord.init) }
    }

    private func liftCard(_ name: String, _ sets: [SetEntry], _ broken: [SetRecord: PersonalRecords.Kind]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink { LiftProgressView(name: name) } label: {
                HStack(spacing: 8) {
                    Text(name).font(.system(size: 16, weight: .bold)).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    let volume = HistoryTotals.volume(sets.map(SetRecord.init))
                    if volume > 0 {
                        Text("\(HistoryTotals.compact(unit.fromPounds(volume))) \(unit.rawValue)")
                            .font(Theme.mono(12, .medium)).foregroundStyle(Theme.muted).fixedSize()
                    }
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .accessibilityLabel("Progress")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            VStack(spacing: 4) {
                ForEach(Array(sets.enumerated()), id: \.element.persistentModelID) { i, set in
                    let kind = broken[SetRecord(set)]
                    Button { editing = set } label: {
                        HStack(spacing: 12) {
                            Text("\(i + 1)").font(Theme.mono(12, .medium)).foregroundStyle(Theme.muted)
                                .frame(width: 18, alignment: .leading)
                            Text(SetText.of(SetRecord(set), exercise: name, unit: unit)).font(Theme.mono(15))
                                .foregroundStyle(kind != nil ? Gold.text : Theme.text)
                            Spacer(minLength: 6)
                            if let kind {
                                Label(kind.short(name), systemImage: "trophy.fill")
                                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Gold.text)
                                    .lineLimit(1)
                            } else if let rpe = set.rpe {
                                Text(Effort(rpe: rpe).label).font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 9)
                        .background(kind != nil ? Gold.wash : Theme.ground.opacity(0.7),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit this set")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.hairline))
    }

    // MARK: Feel

    private var feelCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 2) {
                Text("How did it feel?").font(.system(size: 16, weight: .heavy))
                Text("Your coach uses this to plan the rest of the week.").font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            Picker("Feel", selection: Binding(get: { session.feel ?? "right" }, set: { session.feel = $0 })) {
                Text("Too easy").tag("easy"); Text("Just right").tag("right"); Text("Too hard").tag("hard")
            }
            .pickerStyle(.segmented)
        }
    }
}
