import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(CoachStore.self) private var coach
    @Query(sort: \GymProfile.sortIndex) private var gyms: [GymProfile]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    private var activeGym: GymProfile? { gyms.first(where: \.isActive) ?? gyms.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                WeekStrip(sessions: sessions)
                if let plan = coach.plan {
                    pickCard(plan)
                } else {
                    Card { ProgressView("Your coach is planning today…").tint(Theme.ember) }
                }
                if SyncedSettings.crewBeta { CrewCard() }
                readiness
                if let plan = coach.plan, !plan.isRestDay {
                    NavigationLink { PlanView() } label: { Text("Start workout") }
                        .buttonStyle(EmberButtonStyle())
                }
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
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased())
                    .font(Theme.mono(12)).foregroundStyle(Theme.muted)
                Text("FORGE").font(Theme.display(28)).tracking(1.5)
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
                Text(plan.isRestDay ? "REST DAY" : "COACH PICK").font(Theme.mono(11)).foregroundStyle(Theme.emberSoft)
                Spacer()
                Label(plan.engine, systemImage: plan.engine == "AI Coach" ? "sparkles" : "gearshape")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.focus.uppercased()).font(Theme.display(64))
                if !plan.muscles.isEmpty {
                    Text(plan.muscles.map(\.label).joined(separator: " · ")).foregroundStyle(Theme.text.opacity(0.85))
                }
            }
            if !plan.isRestDay {
                HStack(spacing: 16) {
                    Text("\(plan.minutes) MIN"); Text("\(plan.exercises.count) MOVES"); Text("\(plan.totalSets) SETS")
                }
                .font(Theme.mono(13)).foregroundStyle(Theme.muted)
            }
            Divider().overlay(Theme.hairline)
            SectionLabel("Why today")
            ForEach(plan.reasons, id: \.self) { reason in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(Theme.ember).frame(width: 7, height: 7)
                    Text(reason).font(.system(size: 14))
                }
            }
            if coach.isThinking { ProgressView().tint(Theme.ember) }
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

    var body: some View {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        let training = SyncedSettings.trainingWeekdays
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let isToday = cal.isDateInToday(day)
                let done = sessions.first { cal.isDate($0.date, inSameDayAs: day) }
                let planned = training.contains(cal.component(.weekday, from: day))
                VStack(spacing: 3) {
                    Text(day.formatted(.dateTime.weekday(.narrow))).font(.system(size: 11, weight: .semibold))
                    Text(day.formatted(.dateTime.day())).font(Theme.mono(15))
                    Text(done?.focus.uppercased() ?? (planned ? "·" : "REST")).font(.system(size: 9, weight: .bold)).lineLimit(1)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .foregroundStyle(isToday ? Theme.onEmber : (done != nil || planned ? Theme.text : Theme.muted))
                .background(isToday ? Theme.ember : (done != nil ? Theme.surface : .clear),
                            in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}
