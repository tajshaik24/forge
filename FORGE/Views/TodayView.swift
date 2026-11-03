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
    private let unit = SyncedSettings.unit

    private var activeGym: GymProfile? { gyms.first(where: \.isActive) ?? gyms.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if tracker.isRunning, tracker.isMirrored { liveCard }
                WeekStrip(sessions: sessions, plans: planRows, selected: selected) {
                    selected = Calendar.current.startOfDay(for: $0)
                }
                day
                if isTodaySelected { StepsCard() }
                if SyncedSettings.crewBeta { CrewCard() }
                readiness
                if let err = coach.errorText {
                    Text(err).font(.footnote).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .demoScrollAnchor()
        .background(Theme.ground)
        .refreshable { await coach.loadToday(ctx, force: true) }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $working) { ActiveWorkoutView() }
        // Readiness follows finished workouts, including ones filed from the Watch or another device.
        .onAppear { _ = coach.makeContext(ctx) }
        .onChange(of: finishedCount) { _ = coach.makeContext(ctx) }
    }

    private var finishedCount: Int { sessions.filter { $0.endDate != nil }.count }

    // MARK: The selected day

    private var isTodaySelected: Bool { Calendar.current.isDateInToday(selected) }
    private var isPastSelected: Bool { selected < Calendar.current.startOfDay(for: .now) }

    private var selectedPlan: PlannedWorkout? {
        isTodaySelected ? coach.plan : planRows.first { $0.dayKey == DayKey.of(selected) }?.plan
    }

    private var selectedDone: WorkoutSession? {
        sessions.first { $0.endDate != nil && Calendar.current.isDate($0.date, inSameDayAs: selected) }
    }

    /// Done: what you did, and a quiet way to train again. Planned: the whole workout, with Start
    /// right under its name. Nothing planned: a rest or open day.
    @ViewBuilder
    private var day: some View {
        if let done = selectedDone {
            doneCard(done)
            if isTodaySelected {
                if tracker.isRunning {
                    Button("Resume workout") { working = true }.buttonStyle(AccentButtonStyle())
                } else {
                    ownWorkoutButton("Train again")
                }
            }
        } else if let plan = selectedPlan {
            heroCard(plan)
            if !plan.isRestDay, !plan.exercises.isEmpty { planCard(plan) }
            if !plan.reasons.isEmpty, !plan.isCustom { whyCard(plan) }
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
                Text(isPastSelected ? "REST" : "OPEN DAY").font(Theme.display(40))
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
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accentText)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var dayLabel: String {
        isTodaySelected ? "TODAY" : selected.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased()
    }

    // MARK: Done

    private func doneCard(_ done: WorkoutSession) -> some View {
        NavigationLink { SummaryView(session: done) } label: {
            Card {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    Text("DONE · \(dayLabel)").font(Theme.mono(11)).foregroundStyle(Theme.accentText)
                    Spacer()
                    Text("Summary").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentText)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                }
                Text(done.focus.uppercased()).font(Theme.display(40)).lineLimit(2).minimumScaleFactor(0.6)
                HStack(spacing: 8) {
                    StatTile(value: "\(Int(done.duration / 60))", label: "Minutes")
                    StatTile(value: "\(done.orderedSets.count)", label: "Sets")
                    StatTile(value: HistoryTotals.compact(unit.fromPounds(done.volume)), label: "\(unit.rawValue) lifted")
                    let records = recordsIn(done)
                    StatTile(value: "\(records)", label: records == 1 ? "Record" : "Records", tint: records > 0 ? Gold.text : Theme.text)
                }
                Text(done.gymName).font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
        }
        .buttonStyle(.plain)
    }

    /// Lifts in this workout that set a personal record.
    private func recordsIn(_ session: WorkoutSession) -> Int {
        let sets = session.orderedSets
        let names = Set(sets.map(\.exercise))
        let mine = Dictionary(grouping: sets, by: \.exercise).mapValues { $0.map(SetRecord.init) }
        var history: [String: [SetRecord]] = [:]
        for name in names { history[name] = DataStore.history(of: name, in: ctx, days: 3650) }
        return RecordHistory.inSession(mine, history: history).count
    }

    // MARK: Planned

    private func heroCard(_ plan: PlannedWorkout) -> some View {
        let canStart = isTodaySelected && !plan.isRestDay
        return Card {
            HStack(spacing: 8) {
                Text(plan.isRestDay ? "REST DAY · \(dayLabel)"
                     : plan.isCustom ? "YOUR WORKOUT · \(dayLabel)"
                     : (isTodaySelected ? "COACH PICK · TODAY" : "PLANNED · \(dayLabel)"))
                    .font(Theme.mono(11)).foregroundStyle(Theme.accentText)
                Spacer()
                if !plan.isCustom {
                    Label(plan.engine, systemImage: plan.engine == "AI Coach" ? "sparkles" : "gearshape")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                if !isPastSelected { DayActionsMenu(date: selected, plan: plan) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.focus.uppercased()).font(Theme.display(44)).lineLimit(2).minimumScaleFactor(0.6)
                if !plan.muscles.isEmpty {
                    Text(plan.muscles.map(\.label).joined(separator: " · "))
                        .font(.system(size: 15)).foregroundStyle(Theme.text.opacity(0.8))
                }
            }
            if !plan.isRestDay, !plan.exercises.isEmpty {
                HStack(spacing: 14) {
                    Label("\(plan.minutes) min", systemImage: "clock")
                    Label("\(plan.exercises.count) lifts", systemImage: "dumbbell")
                    Label("\(plan.totalSets) sets", systemImage: "square.stack")
                }
                .labelStyle(CompactLabel())
                .font(Theme.mono(13, .medium)).foregroundStyle(Theme.muted)
                .lineLimit(1).minimumScaleFactor(0.8)
            }
            if canStart {
                Button(tracker.isRunning ? "Resume workout" : (plan.isCustom ? "Start my workout" : "Start workout")) { working = true }
                    .buttonStyle(AccentButtonStyle())
                    .padding(.top, 4)
                if !plan.isCustom, !tracker.isRunning { ownWorkoutButton("Do my own workout instead").padding(.top, -6) }
            } else if isTodaySelected, plan.isRestDay, !tracker.isRunning {
                // A rest day: you can still train.
                ownWorkoutButton("Start my own workout")
            }
            if coach.isThinking { ProgressView().tint(Theme.accent).frame(maxWidth: .infinity) }
        }
    }

    /// The whole workout, so you can see it before you start: the warm-up drills built into it,
    /// every lift with its sets and target, and the cool-down.
    private func planCard(_ plan: PlannedWorkout) -> some View {
        let drills = SyncedSettings.warmUps ? PlanView.usedDrills(plan) : []
        return Card {
            if !drills.isEmpty {
                DrillList(title: "Warm-up · built into the workout", items: drills, symbol: "flame")
                Divider().overlay(Theme.hairline)
            }
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Workout").padding(.bottom, 2)
                ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { i, ex in
                    if i > 0 { Divider().overlay(Theme.hairline).padding(.leading, 32) }
                    NavigationLink { ExerciseDetailView(name: ex.name, planned: ex) } label: {
                        ExerciseRow(index: i + 1, exercise: ex)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !plan.coolDown.isEmpty {
                Divider().overlay(Theme.hairline)
                DrillList(title: "Cool-down · optional", items: plan.coolDown, symbol: "wind")
            }
        }
    }

    private func whyCard(_ plan: PlannedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(isTodaySelected ? "Why today" : "Why this day")
            ForEach(plan.reasons, id: \.self) { reason in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
                    Text(reason).font(.system(size: 14)).foregroundStyle(Theme.text.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Header and live workout

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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                    .font(Theme.mono(12)).foregroundStyle(Theme.muted).lineLimit(1)
                Text("FORGE").font(Theme.display(22)).tracking(1.2)
            }
            Spacer(minLength: 8)
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
                    .font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
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

    // MARK: Readiness

    private var readiness: some View {
        // Most tired first, in a sentence: "Glutes, quads and hamstrings are still recovering."
        let tired = MuscleGroup.allCases.filter { (coach.readiness[$0] ?? 1) < 0.7 }
            .sorted { (coach.readiness[$0] ?? 1) < (coach.readiness[$1] ?? 1) }
        let names = ListFormatter.localizedString(byJoining: tired.prefix(3).map { $0.label.lowercased() })
        return Card {
            VStack(alignment: .leading, spacing: 3) {
                SectionLabel("Muscle readiness")
                Text(tired.isEmpty ? "Everything's recovered."
                     : names.prefix(1).uppercased() + names.dropFirst() + (tired.count == 1 ? " is" : " are") + " still recovering.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible())], spacing: 12) {
                ForEach(MuscleGroup.allCases, id: \.self) { m in
                    let v = coach.readiness[m] ?? 1
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(m.label).font(.system(size: 13))
                            Spacer()
                            Text("\(Int((v * 100).rounded()))%").font(Theme.mono(12, .medium)).foregroundStyle(Theme.muted)
                        }
                        ProgressView(value: v).tint(Theme.readiness(v))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Icon and title close together, for a row of small facts.
private struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 11, weight: .semibold))
            configuration.title
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
