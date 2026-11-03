import SwiftUI

/// One lift on the workout page. Open: its warm-up, test and working sets as rows you tick off.
/// Closed: one line, a summary when it's done or the plan when it's still to come.
struct ExerciseCard: View {
    let model: WorkoutModel
    let index: Int
    let lift: WorkoutProgress.Lift
    let expanded: Bool

    private var name: String { lift.exercise.name }
    private var unit: WeightUnit { model.unit }
    private var timed: Bool { model.isTimed(name) }

    var body: some View {
        if expanded { open } else { closed }
    }

    // MARK: Closed

    private var closed: some View {
        Button { model.open(index) } label: {
            HStack(spacing: 12) {
                marker
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                    Text(lift.isDone || lift.isStarted ? WorkoutText.summary(lift, timed: timed, unit: unit)
                                                      : WorkoutText.plan(lift.exercise, unit: unit))
                        .font(Theme.mono(12)).foregroundStyle(Theme.muted)
                    if lift.isDone, let recap = model.recaps[name] {
                        Text(recap).font(.system(size: 13)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(minHeight: 60)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.hairline))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(lift.isDone ? "Done. Opens the sets." : "Opens this lift")
    }

    /// A tick when done, how many sets in when started, the lift's number otherwise.
    @ViewBuilder
    private var marker: some View {
        if lift.isDone {
            Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 30, height: 30)
                .background(Theme.accent, in: Circle())
                .accessibilityLabel("Done")
        } else {
            Text("\(index + 1)").font(Theme.mono(13)).foregroundStyle(lift.isStarted ? Theme.accentText : Theme.muted)
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(lift.isStarted ? Theme.accent : Theme.hairline, lineWidth: 1.5))
        }
    }

    // MARK: Open

    private var open: some View {
        VStack(alignment: .leading, spacing: 14) {
            title
            actions
            rows
            coachLine
            Button { model.addSet(index) } label: {
                Label("Add set", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Adds one more set to this lift")
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.accent.opacity(0.55), lineWidth: 1.5))
    }

    /// Named for whoever wrote the line: the AI Coach only when the on-device model reworded it,
    /// otherwise the built-in rules, which pick every weight. Same names as the plan on Today.
    private var coachLine: some View {
        let text = model.coachLine(lift)
        let isAI = model.aiNotes.values.contains(text) || model.recaps.values.contains(text)
        let name = isAI ? "AI Coach" : "Built-in coach"
        return CoachLine(text: text, coach: lift.isTesting ? "First Heat · \(name)" : name, isAI: isAI)
    }

    private var title: some View {
        let ex = model.catalog(name)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(WorkoutText.equipment(ex).uppercased()).font(Theme.label).tracking(1)
                        .foregroundStyle(Theme.accentText)
                    Spacer()
                    Text(lift.isTesting ? "FINDING YOUR WEIGHT" : "\(lift.working.count) OF \(lift.planned) DONE")
                        .font(Theme.mono(11)).foregroundStyle(Theme.muted)
                }
                Text(name.uppercased()).font(Theme.display(22)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let since = WorkoutText.sinceLastTime(target: lift.exercise.target, before: model.history(name),
                                                          timed: timed, unit: unit), lift.exercise.calibrate != true {
                    Text(since).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentText)
                }
                if let cue = lift.exercise.cue { NoteChip(text: cue) }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { model.sheet = .howTo(lift.exercise) } label: { Label("How to", systemImage: "book") }
            Button { model.sheet = .progress(name) } label: { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            Button { model.sheet = .swap(index) } label: { Label("Swap", systemImage: "arrow.triangle.2.circlepath") }
        }
        .buttonStyle(RaisedButtonStyle())
    }

    // MARK: Rows

    @ViewBuilder
    private var rows: some View {
        // Warm-ups are for before the first set; once the lift is under way they'd only be in the way.
        let warm = lift.isStarted ? [] : (model.warmUps[name] ?? [])
        let records = model.records(lift)
        let draft = model.draft(lift)
        let usesWeight = WorkoutText.usesWeight(model.catalog(name), target: model.target(lift)) || draft.weight > 0
        VStack(spacing: 6) {
            ForEach(Array(warm.enumerated()), id: \.offset) { i, step in
                WarmUpRow(step: step, done: WorkoutTracker.shared.warmUpsDone.contains(WorkoutTracker.warmUpKey(name, i)),
                          unit: unit,
                          tick: { model.tickWarmUp(lift.exercise, i, step) },
                          info: { if case .drill(let d) = step { model.sheet = .guide(d.name) } })
            }

            if lift.exercise.calibrate == true {
                ForEach(Array(lift.tests.enumerated()), id: \.offset) { i, set in
                    doneRow(label: "Test \(i + 1)", set, record: nil, isTest: true)
                }
                if lift.isTesting {
                    activeRow(label: "Test \(lift.tests.count + 1)", draft: draft, usesWeight: usesWeight, isTest: true)
                }
            }

            ForEach(0..<max(lift.planned, lift.working.count), id: \.self) { i in
                if i < lift.working.count {
                    doneRow(label: "Set \(i + 1)", lift.working[i], record: records[lift.working[i].date], isTest: false)
                } else if i == lift.working.count, !lift.isTesting {
                    activeRow(label: "Set \(i + 1)", draft: draft, usesWeight: usesWeight, isTest: false)
                } else {
                    PendingRow(label: "Set \(i + 1)", isNumber: !lift.isTesting,
                               text: lift.isTesting ? "Weight from your test"
                                   : WorkoutText.amount(weight: usesWeight ? draft.weight : 0, reps: draft.reps, timed: timed, unit: unit))
                }
            }
        }
    }

    @ViewBuilder
    private func doneRow(label: String, _ set: WorkoutProgress.DoneSet, record: PersonalRecords.Kind?, isTest: Bool) -> some View {
        let entry = model.entry(for: set)
        DoneRow(label: label, text: WorkoutText.amount(weight: set.weight, reps: set.reps, timed: timed, unit: unit),
                effort: Effort(rpe: set.rpe), record: record, isTest: isTest) {
            if let entry { model.sheet = .edit(entry) }
        }
        if let entry, model.askingEffort == entry.persistentModelID {
            EffortPicker(title: "How did that feel?", selected: Effort(rpe: entry.rpe)) { model.setEffort(entry, $0) }
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private func activeRow(label: String, draft: WorkoutModel.Draft, usesWeight: Bool, isTest: Bool) -> some View {
        let rating = isTest && model.ratingTest == name
        ActiveRow(name: name, label: label, draft: draft, usesWeight: usesWeight, timed: timed, unit: unit,
                  editing: model.editing?.exercise == name ? model.editing : nil,
                  isTest: isTest, isRating: rating,
                  edit: { field in
                      withAnimation(.snappy) { model.editing = model.editing == field ? nil : field }
                  },
                  log: {
                      withAnimation(.snappy) {
                          if isTest { model.ratingTest = rating ? nil : name } else { model.logWorking(index) }
                      }
                  })
        if let field = model.editing, field.exercise == name {
            ValueEditor(field: field, draft: draft, timed: timed, unit: unit) { model.setDraft(lift, $0) }
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
        if rating {
            EffortPicker(title: "How did that feel? Tap to log it.", selected: nil) { effort in
                withAnimation(.snappy) { model.logTest(index, effort: effort) }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - Rows

private let labelWidth: CGFloat = 62

/// A drill or a lighter set before the lift: lighter than a working set, ticked off when done.
private struct WarmUpRow: View {
    let step: WarmUps.Step
    let done: Bool
    let unit: WeightUnit
    let tick: () -> Void
    let info: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("Warm-up").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                    .frame(width: labelWidth, alignment: .leading)
                switch step {
                case .drill(let d):
                    Text(d.name).font(.system(size: 15)).foregroundStyle(done ? Theme.muted : Theme.text)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Text(d.reps).font(Theme.mono(12)).foregroundStyle(Theme.muted)
                case .ramp(let r):
                    Text("\(unit.format(pounds: r.weight)) × \(r.reps)").font(Theme.mono(15))
                        .foregroundStyle(done ? Theme.muted : Theme.text)
                    Spacer(minLength: 4)
                    Text("rest \(Dose.label(r.rest))").font(Theme.mono(12)).foregroundStyle(Theme.muted)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: tick)
            .accessibilityElement(children: .combine)

            if case .drill = step {
                Button(action: info) {
                    Image(systemName: "info.circle").font(.system(size: 17)).foregroundStyle(Theme.muted)
                        .frame(width: 32, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("How to do it")
            }
            Button(action: tick) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26))
                    .foregroundStyle(done ? Theme.accent : Theme.hairline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue(done ? "Done" : "Not done")
            .accessibilityHint("Ticks off this warm-up step")
        }
        .padding(.leading, 10).padding(.trailing, 4)
        .frame(minHeight: 48)
    }

    private var label: String {
        switch step {
        case .drill(let d): "Warm-up: \(d.name), \(d.reps)"
        case .ramp(let r): "Warm-up set: \(unit.format(pounds: r.weight)) for \(r.reps)"
        }
    }
}

/// A logged set: filled in, gold with a trophy when it beat your best. Tap to fix it.
private struct DoneRow: View {
    let label: String
    let text: String
    let effort: Effort
    let record: PersonalRecords.Kind?
    let isTest: Bool
    let edit: () -> Void

    var body: some View {
        Button(action: edit) {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    if record != nil {
                        Image(systemName: "trophy.fill").foregroundStyle(WorkoutStyle.goldIcon)
                    }
                    Text(label).foregroundStyle(record != nil ? WorkoutStyle.gold : (isTest ? Theme.muted : Theme.text))
                }
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)

                Text(text).font(Theme.mono(17)).foregroundStyle(record != nil ? WorkoutStyle.gold : Theme.text)
                Spacer(minLength: 4)
                Text(record == nil ? effort.label : "New best")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(record != nil ? WorkoutStyle.gold : Theme.muted)
                Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(record != nil ? WorkoutStyle.onGold : Theme.onAccent)
                    .frame(width: 32, height: 32)
                    .background(record != nil ? WorkoutStyle.goldIcon : Theme.accent, in: Circle())
                    .frame(width: 44, height: 44)
            }
            .padding(.leading, 10)
            .frame(minHeight: 52)
            .background(record != nil ? WorkoutStyle.goldWash : Theme.accentWash,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(text), \(effort.label)\(record.map { ", new best: \($0.rawValue)" } ?? "")")
        .accessibilityHint("Edit this set")
    }
}

/// The set to do now: its numbers, each tappable to change, and the tick that logs it.
private struct ActiveRow: View {
    let name: String
    let label: String
    let draft: WorkoutModel.Draft
    let usesWeight: Bool
    let timed: Bool
    let unit: WeightUnit
    let editing: WorkoutModel.Field?
    let isTest: Bool
    let isRating: Bool
    let edit: (WorkoutModel.Field) -> Void
    let log: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accentText)
                .frame(width: labelWidth, alignment: .leading)
            if usesWeight {
                pill(unit.format(pounds: draft.weight), field: .weight(name), a11y: "Weight")
                Text("×").font(Theme.mono(15)).foregroundStyle(Theme.muted)
            }
            pill(timed ? Dose.label(draft.reps) : (usesWeight ? "\(draft.reps)" : WorkoutText.reps(draft.reps, timed: false)),
                 field: .reps(name), a11y: timed ? "Seconds" : "Reps")
            Spacer(minLength: 0)
            Button(action: log) {
                Image(systemName: isRating ? "xmark" : "checkmark").font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(isRating ? Theme.text : Theme.onAccent)
                    .frame(width: 44, height: 44)
                    .background(isRating ? Theme.raised : Theme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRating ? "Not yet" : (isTest ? "Done, then rate it" : "Log \(label.lowercased())"))
        }
        .padding(.leading, 10).padding(.trailing, 4).padding(.vertical, 4)
        .frame(minHeight: 56)
        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.accent, lineWidth: 1.5))
    }

    private func isEditing(_ field: WorkoutModel.Field) -> Bool { editing == field }

    private func pill(_ text: String, field: WorkoutModel.Field, a11y: String) -> some View {
        Button { edit(field) } label: {
            Text(text).font(Theme.mono(17)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 12)
                .frame(minWidth: 52, minHeight: 44)
                .background(isEditing(field) ? Theme.accentWash : Theme.raised,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isEditing(field) ? Theme.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11y)
        .accessibilityValue(text)
        .accessibilityHint("Change it")
    }
}

/// A set still to come, at the numbers it'll start from.
private struct PendingRow: View {
    let label: String
    var isNumber = true
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                .frame(width: labelWidth, alignment: .leading)
            Text(text).font(isNumber ? Theme.mono(15) : .system(size: 14)).foregroundStyle(Theme.muted)
            Spacer(minLength: 4)
            Circle().stroke(Theme.hairline, lineWidth: 1.5).frame(width: 32, height: 32).frame(width: 44, height: 44)
        }
        .padding(.leading, 10)
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }
}

/// Big minus and plus either side of the number: quick with one thumb, and they repeat when held.
private struct ValueEditor: View {
    let field: WorkoutModel.Field
    let draft: WorkoutModel.Draft
    let timed: Bool
    let unit: WeightUnit
    let change: (WorkoutModel.Draft) -> Void

    var body: some View {
        HStack(spacing: 12) {
            step("minus", by: -1)
            VStack(spacing: 0) {
                Text(value).font(Theme.mono(30)).foregroundStyle(Theme.text).monospacedDigit()
                    .contentTransition(.numericText())
                Text(caption).font(Theme.label).tracking(1).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
            step("plus", by: 1)
        }
        .padding(10)
        .background(Theme.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue(value)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: bump(1)
            case .decrement: bump(-1)
            @unknown default: break
            }
        }
    }

    private var isWeight: Bool { if case .weight = field { true } else { false } }

    private var value: String {
        isWeight ? unit.format(pounds: draft.weight, withUnit: false) : (timed ? "\(draft.reps)" : "\(draft.reps)")
    }

    private var caption: String {
        isWeight ? unit.label : (timed ? "SECONDS" : "REPS")
    }

    private func step(_ icon: String, by direction: Int) -> some View {
        Button { bump(direction) } label: {
            Image(systemName: icon).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.text)
                .frame(width: 56, height: 56)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.hairline))
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(direction > 0 ? "More" : "Less")
    }

    private func bump(_ direction: Int) {
        var d = draft
        if isWeight {
            let shown = unit.roundToStep(unit.fromPounds(d.weight)) + Double(direction) * unit.step
            d.weight = unit.toPounds(min(1000, max(0, shown)))
        } else {
            d.reps = min(timed ? 600 : 100, max(timed ? 5 : 1, d.reps + direction * (timed ? 5 : 1)))
        }
        withAnimation(.snappy) { change(d) }
    }
}

/// Easy / Good / Hard, one tap.
struct EffortPicker: View {
    let title: String
    let selected: Effort?
    let pick: (Effort) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                ForEach(Effort.allCases) { effort in
                    let on = effort == selected
                    Button { pick(effort) } label: {
                        VStack(spacing: 2) {
                            Text(effort.label).font(.system(size: 15, weight: .bold))
                            Text(effort.detail).font(.system(size: 11))
                                .foregroundStyle(on ? Theme.onAccent.opacity(0.85) : Theme.muted)
                        }
                        .foregroundStyle(on ? Theme.onAccent : Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(on ? Theme.accent : Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(effort.label), \(effort.detail)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// The coach's call under the sets, and which coach is talking.
struct CoachLine: View {
    let text: String
    let coach: String
    let isAI: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isAI ? "sparkles" : "lightbulb.fill")
                .font(.system(size: 14)).foregroundStyle(Theme.accentText)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(text).font(.system(size: 14)).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                Text(coach.uppercased()).font(Theme.label).tracking(1).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Theme.accentWash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .animation(.easeInOut, value: text)
    }
}
