import SwiftUI
import SwiftData

struct WeekView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(CoachStore.self) private var coach
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \DailyPlan.dayKey) private var planRows: [DailyPlan]

    @State private var days = SyncedSettings.trainingWeekdays
    @State private var split = SyncedSettings.split
    @State private var minutes = SyncedSettings.minutes
    @State private var minutesChanged = false

    private let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]   // Mon…Sun

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Training days · tap to change")
                    HStack(spacing: 6) {
                        ForEach(weekdayOrder, id: \.self) { wd in
                            let on = days.contains(wd)
                            Button {
                                if on { days.remove(wd) } else { days.insert(wd) }
                            } label: {
                                Text(Calendar.current.veryShortWeekdaySymbols[wd - 1])
                                    .font(.system(size: 15, weight: on ? .heavy : .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(on ? Theme.onEmber : Theme.muted)
                                    .background(on ? Theme.ember : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Split")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(SplitStyle.allCases) { style in splitTile(style) }
                    }
                    Stepper("Session length: \(minutes) min", value: $minutes, in: 20...120, step: 5)
                }

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        SectionLabel("This week")
                        Spacer()
                        if coach.isPlanningWeek { ProgressView().controlSize(.small).tint(Theme.ember) }
                    }
                    .padding(.bottom, 8)
                    ForEach(rows) { row in
                        if let plan = row.plan {
                            NavigationLink { PlanView(day: plan) } label: { rowView(row) }.buttonStyle(.plain)
                        } else if let session = row.session {
                            NavigationLink { SummaryView(session: session) } label: { rowView(row) }.buttonStyle(.plain)
                        }
                        Divider().overlay(Theme.hairline)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Weekly sets by muscle")
                    if setsByMuscle.isEmpty {
                        Text("Log a workout this week to see how much each muscle got.")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    ForEach(MuscleGroup.allCases.filter { (setsByMuscle[$0] ?? 0) > 0 }, id: \.self) { m in
                        let n = setsByMuscle[m] ?? 0
                        HStack {
                            Text(m.label).font(.system(size: 13)).frame(width: 90, alignment: .leading)
                            ProgressView(value: min(n / 14, 1)).tint(Theme.ember)
                            Text("\(Int(n))/14").font(Theme.mono(12, .medium)).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.ground)
        .navigationTitle("Your week")
        .onChange(of: days) { SyncedSettings.trainingWeekdays = days; replan() }
        .onChange(of: split) { SyncedSettings.split = split; replan() }
        // The stepper fires on every tap, so rebuild once when you leave the screen.
        .onChange(of: minutes) { SyncedSettings.minutes = minutes; minutesChanged = true }
        .onDisappear { if minutesChanged { minutesChanged = false; replan() } }
    }

    private func splitTile(_ style: SplitStyle) -> some View {
        let on = split == style
        return Button { split = style } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(style.label)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(on ? Theme.text : Theme.text.opacity(0.85))
                Text(style.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(on ? Theme.emberSoft : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            .padding(12)
            .background(on ? Theme.emberWash : Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Theme.ember : Theme.hairline, lineWidth: on ? 2 : 1))
            .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Rows: finished sessions this week, then today's and upcoming plans

    private struct Row: Identifiable {
        let id: String
        let date: Date
        let focus: String
        let detail: String
        let badge: String
        var plan: PlannedWorkout?
        var session: WorkoutSession?
    }

    private var rows: [Row] {
        let cal = Calendar.current
        var out: [Row] = thisWeek.map { s in
            Row(id: "s-\(s.persistentModelID.hashValue)", date: s.date, focus: s.focus,
                detail: "\(s.orderedSets.count) sets · \(s.gymName)",
                badge: s.healthWorkoutID != nil ? "DONE ♥" : "DONE", session: s)
        }
        let doneDays = Set(thisWeek.map { DayKey.of($0.date) })
        var seen = Set<String>()
        for row in planRows where row.dayKey >= DayKey.of(.now) && !doneDays.contains(row.dayKey) && !seen.contains(row.dayKey) {
            guard let plan = row.plan, !plan.isRestDay else { continue }
            seen.insert(row.dayKey)
            let isToday = cal.isDateInToday(plan.date)
            let swapped = plan.exercises.contains { $0.replaces != nil }
            out.append(Row(id: "p-\(row.dayKey)", date: plan.date, focus: plan.focus,
                           detail: plan.muscles.prefix(3).map(\.label).joined(separator: " · "),
                           badge: isToday ? "TODAY" : (swapped ? "ADJUSTED" : "PLANNED"), plan: plan))
        }
        return out.sorted { $0.date < $1.date }
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 14) {
            Text(row.date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(Theme.mono(13)).foregroundStyle(Theme.muted).frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.focus.uppercased()).font(.system(size: 16, weight: .heavy).width(.condensed))
                Text(row.detail).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Text(row.badge)
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 10).frame(height: 26)
                .foregroundStyle(row.badge == "TODAY" ? Theme.onEmber : (row.badge == "ADJUSTED" ? Theme.emberSoft : Theme.muted))
                .background(row.badge == "TODAY" ? Theme.ember : (row.badge == "ADJUSTED" ? Theme.emberWash : Theme.surface), in: Capsule())
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var thisWeek: [WorkoutSession] {
        guard let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        return sessions.filter { $0.date >= start && $0.endDate != nil }.reversed()
    }

    private var setsByMuscle: [MuscleGroup: Double] {
        thisWeek.map(Readiness.summarize).reduce(into: [:]) { acc, s in
            for (m, n) in s.setsByMuscle { acc[m, default: 0] += n }
        }
    }

    private func replan() { Task { await coach.invalidate(ctx) } }
}
