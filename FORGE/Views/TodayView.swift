import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(CoachStore.self) private var coach
    @Query(sort: \GymProfile.sortIndex) private var gyms: [GymProfile]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \DailyPlan.updatedAt, order: .reverse) private var planRows: [DailyPlan]
    /// The live workout screen: started here, or opened to join one running on the Watch.
    @State private var working = false
    /// The day shown below the week strip. Today unless you tap another date.
    @State private var selected = Calendar.current.startOfDay(for: .now)
    private let tracker = WorkoutTracker.shared

    private var activeGym: GymProfile? { gyms.first(where: \.isActive) ?? gyms.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if tracker.isRunning, tracker.isMirrored { liveCard }
                WeekStrip(sessions: sessions, plans: planRows, selected: selected) {
                    selected = Calendar.current.startOfDay(for: $0)
                }
                dayCard
                // Right under the day it acts on.
                if isTodaySelected, let plan = coach.plan, !plan.isRestDay {
                    Button(tracker.isRunning ? "Resume workout" : "Start workout") { working = true }
                        .buttonStyle(AccentButtonStyle())
                    if !plan.isCustom {
                        NavigationLink { PlanView() } label: {
                            Text(SyncedSettings.warmUps ? "Full plan with warm-up and cool-down" : "Full plan")
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accentText)
                                .frame(maxWidth: .infinity)
                        }
                        if !tracker.isRunning, selectedDone == nil { ownWorkoutButton("Do my own workout instead") }
                    }
                } else if isTodaySelected, !tracker.isRunning, selectedDone == nil, coach.plan != nil {
                    // A rest day: you can still train.
                    ownWorkoutButton("Start my own workout")
                } else if !isTodaySelected, selectedDone == nil, let plan = selectedPlan, !plan.isRestDay {
                    NavigationLink { PlanView(day: plan) } label: { Text("View plan") }
                        .buttonStyle(AccentButtonStyle())
                }
                if isTodaySelected { StepsCard() }
                if SyncedSettings.crewBeta { CrewCard() }
                readiness
                if let err = coach.errorText {
                    Text(err).font(.footnote).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Theme.ground)
        .refreshable { await coach.loadToday(ctx, force: true) }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $working) { ActiveWorkoutView() }
    }

    // MARK: The selected day

    private var isTodaySelected: Bool { Calendar.current.isDateInToday(selected) }
    private var isPastSelected: Bool { selected < Calendar.current.startOfDay(for: .now) }

    private var selectedPlan: PlannedWorkout? {
        isTodaySelected ? coach.plan : planRows.first { $0.dayKey == DayKey.of(selected) }?.plan
    }

    private var selectedDone: WorkoutSession? {
        sessions.first { $0.endDate != nil && Calendar.current.isDate($0.date, inSameDayAs: selected) }
    }

    @ViewBuilder
    private var dayCard: some View {
        if let done = selectedDone {
            NavigationLink { SummaryView(session: done) } label: {
                Card {
                    HStack {
                        Text("DONE · \(dayLabel)").font(Theme.mono(11)).foregroundStyle(Theme.accentText)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                    }
                    Text(done.focus.uppercased()).font(Theme.display(44))
                    Text("\(done.orderedSets.count) sets · \(done.gymName)").font(Theme.mono(13)).foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(.plain)
        } else if let plan = selectedPlan {
            pickCard(plan)
        } else if isTodaySelected {
            Card {
                ProgressView("Your coach is planning today…").tint(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        } else {
            Card {
                HStack {
                    Text("\(isPastSelected ? "NOTHING LOGGED" : "NOT PLANNED YET") · \(dayLabel)")
                        .font(Theme.mono(11)).foregroundStyle(Theme.accentText)
                    Spacer()
                    if !isPastSelected { DayActionsMenu(date: selected, plan: nil) }
                }
                Text(isPastSelected ? "REST" : "OPEN DAY").font(Theme.display(44))
                if !isPastSelected {
                    Text(coach.isPlanningWeek ? "Your coach is planning the week…" : "Use ⋯ to train this day.")
                        .font(.system(size: 14)).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    /// An empty workout you fill as you go, in place of the coach's plan for today.
    private func ownWorkoutButton(_ title: String) -> some View {
        Button {
            coach.startOwnWorkout(ctx)
            working = true
        } label: {
            Label(title, systemImage: "plus.circle")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accentText)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var dayLabel: String {
        isTodaySelected ? "TODAY" : selected.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased()
    }

    /// A workout started on the Watch is running: open it here to log on either device.
    private var liveCard: some View {
        Button { working = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "applewatch.radiowaves.left.and.right").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live on Apple Watch").font(.system(size: 15, weight: .heavy))
                    Text("Tap to log sets here too").font(.footnote).foregroundStyle(Theme.muted)
                }
                Spacer()
                Label("\(Int(tracker.heartRate))", systemImage: "heart.fill").font(Theme.mono(14))
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased())
                    .font(Theme.mono(12)).foregroundStyle(Theme.muted)
                Text("FORGE").font(Theme.display(24)).tracking(1.5)
            }
            Spacer()
            Menu {
                ForEach(gyms) { gym in
                    Button(gym.name) {
                        gyms.forEach { $0.isActive = ($0 == gym) }
                        try? ctx.save()
                        Task { await coach.invalidate(ctx) }
                    }
                }
            } label: {
                Label(activeGym?.name ?? "Gym", systemImage: "dumbbell")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(Theme.surface, in: Capsule())
                    .overlay(Capsule().stroke(Theme.hairline))
            }
            NavigationLink { SettingsView() } label: {
                Image(systemName: "gearshape").font(.system(size: 18))
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().stroke(Theme.hairline))
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    private func pickCard(_ plan: PlannedWorkout) -> some View {
        Card {
            HStack {
                Text(plan.isRestDay ? "REST DAY · \(dayLabel)"
                     : plan.isCustom ? "YOUR WORKOUT · \(dayLabel)"
                     : (isTodaySelected ? "COACH PICK" : "PLANNED · \(dayLabel)"))
                    .font(Theme.mono(11)).foregroundStyle(Theme.accentText)
                Spacer()
                Label(plan.engine, systemImage: plan.engine == "AI Coach" ? "sparkles" : "gearshape")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
                if !isPastSelected { DayActionsMenu(date: selected, plan: plan) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.focus.uppercased()).font(Theme.display(52))
                if !plan.muscles.isEmpty {
                    Text(plan.muscles.map(\.label).joined(separator: " · ")).foregroundStyle(Theme.text.opacity(0.85))
                }
            }
            if !plan.isRestDay {
                HStack(spacing: 16) {
                    Text("\(plan.minutes) MIN"); Text("\(plan.exercises.count) MOVES"); Text("\(plan.totalSets) SETS")
                }
                .font(Theme.mono(13)).foregroundStyle(Theme.muted)
                // The workout itself, so you can see it before you start.
                VStack(spacing: 0) {
                    ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { i, ex in
                        if i > 0 { Divider().overlay(Theme.hairline) }
                        NavigationLink { ExerciseDetailView(name: ex.name, planned: ex) } label: {
                            ExerciseRow(index: i + 1, exercise: ex)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Divider().overlay(Theme.hairline)
            SectionLabel(isTodaySelected ? "Why today" : "Why this day")
            ForEach(plan.reasons, id: \.self) { reason in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(Theme.accent).frame(width: 7, height: 7)
                    Text(reason).font(.system(size: 14))
                }
            }
            if coach.isThinking { ProgressView().tint(Theme.accent) }
        }
    }

    private var readiness: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Muscle readiness")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible())], spacing: 10) {
                ForEach(MuscleGroup.allCases, id: \.self) { m in
                    let v = coach.readiness[m] ?? 1
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(m.label).font(.system(size: 13))
                            Spacer()
                            Text("\(Int(v * 100))%").font(Theme.mono(12, .medium)).foregroundStyle(Theme.muted)
                        }
                        ProgressView(value: v).tint(Theme.readiness(v))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

struct WeekStrip: View {
    let sessions: [WorkoutSession]
    var plans: [DailyPlan] = []
    /// Highlighted day (defaults to today).
    var selected: Date? = nil
    var onSelect: ((Date) -> Void)?

    var body: some View {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        let training = SyncedSettings.trainingWeekdays
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let isToday = cal.isDateInToday(day)
                let isSelected = selected.map { cal.isDate($0, inSameDayAs: day) } ?? isToday
                let done = sessions.first { cal.isDate($0.date, inSameDayAs: day) }
                // A saved plan (including a moved workout or a day off) beats the usual weekly schedule.
                let saved = plans.first { $0.dayKey == DayKey.of(day) }?.plan
                let planned = saved.map { !$0.isRestDay } ?? training.contains(cal.component(.weekday, from: day))
                let label = done?.focus ?? (planned ? saved?.focus ?? "·" : "Rest")
                Button { onSelect?(day) } label: {
                    VStack(spacing: 3) {
                        Text(day.formatted(.dateTime.weekday(.narrow))).font(.system(size: 11, weight: .semibold))
                        Text(day.formatted(.dateTime.day())).font(Theme.mono(15))
                        Text(label.uppercased()).font(.system(size: 9, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .foregroundStyle(isSelected ? Theme.onAccent : (done != nil || planned ? Theme.text : Theme.muted))
                    .background(isSelected ? Theme.accent : (done != nil ? Theme.surface : .clear),
                                in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(isToday && !isSelected ? Theme.accent : .clear, lineWidth: 1.5))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(onSelect == nil)
                .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide).day())): \(label)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
