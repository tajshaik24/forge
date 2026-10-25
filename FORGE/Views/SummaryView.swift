import SwiftUI
import SwiftData
import Charts

struct SummaryView: View {
    @Bindable var session: WorkoutSession
    var onDone: () -> Void = {}
    @Environment(\.modelContext) private var ctx
    @Environment(CoachStore.self) private var coach
    @State private var editing: SetEntry?
    private let unit = SyncedSettings.unit

    init(session: WorkoutSession, onDone: @escaping () -> Void = {}) {
        self.session = session
        self.onDone = onDone
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(session.date.formatted(.dateTime.weekday().month().day())) · \(session.gymName)".uppercased())
                        .font(Theme.mono(12)).foregroundStyle(Theme.muted)
                    Text("\(session.focus.uppercased()) DONE").font(Theme.display(36))
                }

                Label(session.healthWorkoutID != nil
                      ? "Saved to Apple Health as Strength Training. Shows in Fitness."
                      : "Sets saved. Health workout wasn't recorded this time.",
                      systemImage: session.healthWorkoutID != nil ? "checkmark" : "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))

                HStack(spacing: 8) {
                    tile(durationText, "Time")
                    tile("\(Int(session.activeCalories))", "Active cal")
                    tile("\(session.orderedSets.count)", "Sets")
                    tile(volumeText, "\(unit.rawValue) moved")
                }

                if !session.heartRates.isEmpty {
                    Card {
                        HStack {
                            SectionLabel("Heart rate")
                            Spacer()
                            Text("AVG \(Int(session.averageHeartRate)) · MAX \(Int(session.maxHeartRate))")
                                .font(Theme.mono(12)).foregroundStyle(Theme.muted)
                        }
                        Chart(Array(session.heartRates.enumerated()), id: \.offset) { i, bpm in
                            BarMark(x: .value("Time", Double(i) * 15 / 60), y: .value("BPM", bpm))
                                .foregroundStyle(bpm >= 145 ? Theme.accent : (bpm >= 125 ? Theme.readiness(0.6) : Theme.readiness(0.3)))
                        }
                        .chartXAxisLabel("minutes")
                        .frame(height: 90)
                    }
                }

                SectionLabel("What you did · tap a set to fix it")
                ForEach(groupedSets, id: \.name) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.name).font(.system(size: 15, weight: .bold))
                        ForEach(group.sets, id: \.persistentModelID) { set in
                            Button { editing = set } label: {
                                HStack {
                                    Text("\(unit.format(pounds: set.weight)) × \(set.reps)")
                                    if let rpe = set.rpe { Text("RPE \(rpe)").foregroundStyle(Theme.muted) }
                                    Spacer()
                                    Image(systemName: "pencil").foregroundStyle(Theme.muted)
                                }
                                .font(Theme.mono(13))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Divider().overlay(Theme.hairline)
                }

                SectionLabel("How did it feel? (tells the coach)")
                Picker("Feel", selection: Binding(get: { session.feel ?? "right" }, set: { session.feel = $0 })) {
                    Text("Too easy").tag("easy"); Text("Just right").tag("right"); Text("Too hard").tag("hard")
                }
                .pickerStyle(.segmented)
            }
            .padding(20)
        }
        .background(Theme.ground)
        .safeAreaInset(edge: .bottom) {
            Button("Done", action: onDone).buttonStyle(AccentButtonStyle()).padding(20)
        }
        .sheet(item: $editing) { EditSetSheet(entry: $0, unit: unit) }
        // How it felt shapes the rest of the week's plans.
        .onChange(of: session.feel) {
            try? ctx.save()
            Task { await coach.planWeek(ctx, force: true) }
        }
    }

    private var durationText: String {
        let s = Int(session.duration)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var volumeText: String {
        let v = unit.fromPounds(session.volume)
        return v >= 1000 ? String(format: "%.1fk", v / 1000) : "\(Int(v))"
    }

    private var groupedSets: [(name: String, sets: [SetEntry])] {
        var order: [String] = []
        var byName: [String: [SetEntry]] = [:]
        for s in session.orderedSets {
            if byName[s.exercise] == nil { order.append(s.exercise) }
            byName[s.exercise, default: []].append(s)
        }
        return order.map { ($0, byName[$0] ?? []) }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.mono(17)).minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}
