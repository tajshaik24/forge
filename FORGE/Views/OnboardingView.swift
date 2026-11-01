import SwiftUI
import SwiftData

/// First-run setup: goal, experience, schedule, units, where you train, Health + notifications.
struct OnboardingView: View {
    let onDone: () -> Void

    @Environment(\.modelContext) private var ctx
    @Query(sort: \GymProfile.sortIndex) private var gyms: [GymProfile]

    @State private var step = 0
    @State private var goal: TrainingGoal = .buildMuscle
    @State private var experience: Experience = .intermediate
    @State private var days: Set<Int> = [2, 3, 5, 7]
    @State private var minutes = 45
    @State private var unit: WeightUnit = SyncedSettings.unit
    @State private var gymChoice = 0

    private let stepCount = 5
    private let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    init(onDone: @escaping () -> Void) { self.onDone = onDone }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { i in
                    Capsule().fill(i <= step ? Theme.accent : Theme.raised).frame(height: 4)
                }
            }
            .accessibilityLabel("Step \(step + 1) of \(stepCount)")

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case 0: goalStep
                    case 1: experienceStep
                    case 2: scheduleStep
                    case 3: gymStep
                    default: healthStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                if step > 0 {
                    Button("Back") { withAnimation { step -= 1 } }
                        .frame(minWidth: 88, minHeight: 54)
                        .overlay(Capsule().stroke(Theme.hairline))
                }
                Button(step == stepCount - 1 ? "Build my first workout" : "Continue") {
                    if step == stepCount - 1 { Task { await finish() } } else { withAnimation { step += 1 } }
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(step == 2 && days.isEmpty)
            }
        }
        .padding(20)
        .background(Theme.ground)
        .interactiveDismissDisabled()
    }

    // MARK: Steps

    private func title(_ text: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text.uppercased()).font(Theme.display(34))
            Text(sub).font(.system(size: 15)).foregroundStyle(Theme.muted)
        }
    }

    private func option(_ label: String, _ detail: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 16, weight: .bold))
                    if let detail { Text(detail).font(.system(size: 13)).foregroundStyle(Theme.muted) }
                }
                Spacer()
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Theme.accent : Theme.muted)
            }
            .padding(.horizontal, 16).frame(minHeight: 60)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Theme.accent : Theme.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            title("What's the goal?", "Your coach plans volume and rep ranges around it.")
            ForEach(TrainingGoal.allCases) { g in
                option(g.rawValue, nil, selected: goal == g) { goal = g }
            }
        }
    }

    private var experienceStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            title("How long have you lifted?", "Your coach uses this to choose your sets, exercises and how fast to progress.")
            ForEach(Experience.allCases) { e in
                option(e.label, nil, selected: experience == e) { experience = e }
            }
        }
    }

    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("When do you train?", "Pick your days. You can change them any time in Week.")
            HStack(spacing: 6) {
                ForEach(weekdayOrder, id: \.self) { wd in
                    let on = days.contains(wd)
                    Button { if on { days.remove(wd) } else { days.insert(wd) } } label: {
                        Text(Calendar.current.veryShortWeekdaySymbols[wd - 1])
                            .font(.system(size: 15, weight: on ? .heavy : .semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(on ? Theme.onAccent : Theme.muted)
                            .background(on ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel(Calendar.current.weekdaySymbols[wd - 1])
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Stepper("Session length: \(minutes) min", value: $minutes, in: 20...120, step: 5)
            Text("Warm-up included.").font(.system(size: 13)).foregroundStyle(Theme.muted)
            SectionLabel("Weights in")
            Picker("Units", selection: $unit) {
                ForEach(WeightUnit.allCases) { Text($0 == .lb ? "Pounds (lb)" : "Kilograms (kg)").tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var gymStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            title("Where do you train?", "The coach only plans what your gym has. Fine-tune it later in Gyms.")
            ForEach(Array(gyms.enumerated()), id: \.element.persistentModelID) { i, gym in
                option(gym.name, "\(gym.equipment.count) pieces of equipment", selected: gymChoice == i) { gymChoice = i }
            }
        }
    }

    private var healthStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Hook up Health", "FORGE saves workouts to Apple Health and Fitness, reads heart rate while you train, and uses sleep and HRV to adjust volume.")
            Label("Workouts and heart rate saved to Health", systemImage: "heart.fill")
            Label("Sleep and HRV shape how hard today is", systemImage: "bed.double.fill")
            Label("A buzz when your rest is up", systemImage: "bell.fill")
            Text("Next you'll see Apple's permission screens. You can change these later in Settings.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
        }
        .font(.system(size: 15))
    }

    // MARK: Save

    private func finish() async {
        SyncedSettings.goal = goal.rawValue
        SyncedSettings.experience = experience
        SyncedSettings.trainingWeekdays = days
        SyncedSettings.minutes = minutes
        SyncedSettings.unit = unit
        for (i, gym) in gyms.enumerated() { gym.isActive = (i == gymChoice) }
        try? ctx.save()
        await WorkoutTracker.shared.requestAuthorization()
        await RestAlerts.requestPermission()
        SyncedSettings.onboarded = true
        onDone()
    }
}

/// Everything set during onboarding, editable later.
struct SettingsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(CoachStore.self) private var coach

    @State private var goal = TrainingGoal(rawValue: SyncedSettings.goal) ?? .buildMuscle
    @State private var experience = SyncedSettings.experience
    @State private var unit = SyncedSettings.unit
    @State private var minutes = SyncedSettings.minutes
    @State private var crewBeta = SyncedSettings.crewBeta
    @State private var warmUps = SyncedSettings.warmUps
    @State private var changed = false

    var body: some View {
        Form {
            Section {
                Picker("Goal", selection: $goal) { ForEach(TrainingGoal.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Years lifting", selection: $experience) { ForEach(Experience.allCases) { Text($0.label).tag($0) } }
                Stepper("Session length: \(minutes) min, warm-up included", value: $minutes, in: 20...120, step: 5)
                Toggle("Warm up before lifting", isOn: $warmUps)
            } header: {
                Text("Training")
            } footer: {
                Text("A few minutes of drills for the day's lifts, plus lighter ramp-up sets. You can skip it on any workout.")
            }
            Section("Units") {
                Picker("Weights in", selection: $unit) { ForEach(WeightUnit.allCases) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented)
            }
            #if !PERSONAL_TEAM
            Section {
                Toggle("Crews (beta)", isOn: $crewBeta)
                if crewBeta { NavigationLink("Your crew") { CrewView() } }
            } footer: {
                Text("Weekly streaks with friends, shared through iCloud. Crews only see check-ins: workout type, sets and minutes.")
            }
            #endif
            Section {
                NavigationLink("Exercise library") { ExerciseLibraryView() }
                NavigationLink("What your coach knows") { CoachNotesView() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ground)
        .navigationTitle("Settings")
        .onChange(of: goal) { SyncedSettings.goal = goal.rawValue; changed = true }
        .onChange(of: experience) { SyncedSettings.experience = experience; changed = true }
        .onChange(of: unit) { SyncedSettings.unit = unit; changed = true }
        .onChange(of: minutes) { SyncedSettings.minutes = minutes; changed = true }
        .onChange(of: crewBeta) { SyncedSettings.crewBeta = crewBeta }
        .onChange(of: warmUps) { SyncedSettings.warmUps = warmUps; changed = true }
        .onDisappear { if changed { changed = false; Task { await coach.invalidate(ctx) } } }
    }
}
