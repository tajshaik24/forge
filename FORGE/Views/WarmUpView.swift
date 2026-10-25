import SwiftUI

/// The drills before the first lift (warm-up) or after the last (cool-down): one at a time,
/// with a timer for holds, and a skip that's always one tap away.
struct DrillsView: View {
    enum Mode { case warmUp, coolDown }

    let mode: Mode
    let drills: [PlannedExercise]
    /// Lighter sets for the first lift, shown after the drills (warm-up only).
    var rampFor: String? = nil
    var ramp: [RampUp.Step] = []
    let onDone: () -> Void

    @State private var index = 0
    @State private var timerEnds: Date?
    @State private var rampDone: Set<Int> = []
    @State private var form: String?
    @State private var buzz = 0

    private let unit = SyncedSettings.unit
    private var current: PlannedExercise? { drills.indices.contains(index) ? drills[index] : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode == .warmUp ? "WARM-UP" : "COOL-DOWN").font(Theme.display(36))
                        Text("About \(minutes) min · \(mode == .warmUp ? "gets you ready to lift" : "optional, eases you out")")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button("Skip", action: onDone)
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityLabel(mode == .warmUp ? "Skip warm-up" : "Skip cool-down")
                }

                if let current { currentCard(current) }

                VStack(spacing: 0) {
                    ForEach(Array(drills.enumerated()), id: \.offset) { i, drill in
                        Button { form = drill.name } label: { row(i, drill) }.buttonStyle(.plain)
                        Divider().overlay(Theme.hairline)
                    }
                }

                if let rampFor, !ramp.isEmpty { rampCard(rampFor) }

                Button(mode == .warmUp ? "Start lifting" : "Finish workout", action: onDone)
                    .buttonStyle(AccentButtonStyle())
            }
            .padding(20)
        }
        .background(Theme.ground)
        .sensoryFeedback(.success, trigger: buzz)
        .sheet(item: Binding(get: { form.map(FormSheetItem.init) }, set: { form = $0?.name })) { item in
            NavigationStack { ExerciseDetailView(name: item.name) }
        }
    }

    private var minutes: Int {
        let seconds = drills.reduce(0) { total, d in
            let dose = Dose(d.reps)
            return total + (dose.seconds.map { $0 * dose.sides } ?? 45)
        }
        return max(2, Int((Double(seconds) / 60).rounded()) + (ramp.isEmpty ? 0 : 3))
    }

    private func currentCard(_ drill: PlannedExercise) -> some View {
        let ex = ExerciseCatalog.named(drill.name)
        let dose = Dose(drill.reps)
        return Card {
            if let ex, ex.photo != nil {
                ExercisePhoto(exercise: ex, frame: 1)
                    .aspectRatio(3 / 2, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(drill.name).font(.system(size: 22, weight: .bold))
                Spacer()
                Text(drill.reps).font(Theme.mono(15)).foregroundStyle(Theme.accentText)
            }
            if let cue = FormGuides.keyCue(for: drill.name) {
                Text(cue).font(.system(size: 14)).foregroundStyle(Theme.text.opacity(0.85))
            }
            if let seconds = dose.seconds {
                timer(seconds: seconds, sides: dose.sides)
            } else {
                Button("Done") { next() }.buttonStyle(AccentButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func timer(seconds: Int, sides: Int) -> some View {
        if let timerEnds {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = max(0, Int(timerEnds.timeIntervalSince(context.date).rounded(.up)))
                let switchAt = sides > 1 ? seconds : nil
                VStack(spacing: 8) {
                    Text(String(format: "%d:%02d", left / 60, left % 60)).font(Theme.mono(48)).monospacedDigit()
                        .frame(maxWidth: .infinity)
                    if let switchAt {
                        Text(left > switchAt ? "First side" : "Switch sides").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accentText).frame(maxWidth: .infinity)
                    }
                    Button("Next") { next() }.buttonStyle(AccentButtonStyle())
                }
                .onChange(of: left == switchAt) { _, isSwitch in if isSwitch { buzz += 1 } }
                .onChange(of: left == 0) { _, isZero in if isZero { next() } }
            }
        } else {
            HStack {
                Button("Start \(sides > 1 ? "\(seconds) s each side" : Dose.label(seconds))") {
                    timerEnds = .now.addingTimeInterval(TimeInterval(seconds * sides))
                }
                .buttonStyle(AccentButtonStyle())
                Button("Done") { next() }
                    .frame(width: 88, height: 52)
                    .overlay(Capsule().stroke(Theme.hairline))
            }
        }
    }

    private func row(_ i: Int, _ drill: PlannedExercise) -> some View {
        HStack(spacing: 12) {
            Image(systemName: i < index ? "checkmark.circle.fill" : (i == index ? "circle.inset.filled" : "circle"))
                .foregroundStyle(i <= index ? Theme.accent : Theme.muted)
            Text(drill.name).font(.system(size: 15, weight: i == index ? .bold : .regular))
                .foregroundStyle(i < index ? Theme.muted : Theme.text)
            Spacer()
            Text(drill.reps).font(Theme.mono(13)).foregroundStyle(Theme.muted)
            Image(systemName: "info.circle").foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func rampCard(_ lift: String) -> some View {
        Card {
            SectionLabel("Ramp-up sets · \(lift)")
            Text("Lighter sets to groove the movement. They don't count toward your workout.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
            ForEach(Array(ramp.enumerated()), id: \.offset) { i, step in
                Button {
                    if rampDone.contains(i) { rampDone.remove(i) } else { rampDone.insert(i) }
                } label: {
                    HStack {
                        Image(systemName: rampDone.contains(i) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(rampDone.contains(i) ? Theme.accent : Theme.muted)
                        Text("\(unit.format(pounds: step.weight)) × \(step.reps)").font(Theme.mono(15))
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func next() {
        timerEnds = nil
        buzz += 1
        if index < drills.count { index += 1 }
    }
}

private struct FormSheetItem: Identifiable {
    let name: String
    var id: String { name }
}

/// "30 s", "30 s/side", "3 min", "10/side": how long one round takes and how many sides it has.
struct Dose {
    /// Nil when it's a rep count.
    let seconds: Int?
    let sides: Int

    init(_ text: String) {
        let lower = text.lowercased()
        sides = lower.contains("/side") || lower.contains("/leg") || lower.contains("/arm") ? 2 : 1
        let number = Int(lower.split(whereSeparator: { !$0.isNumber }).first ?? "") ?? 0
        if lower.contains("min") {
            seconds = number * 60
        } else if lower.contains(" s") {
            seconds = number
        } else {
            seconds = nil
        }
    }

    static func label(_ seconds: Int) -> String {
        seconds >= 60 && seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) s"
    }
}
