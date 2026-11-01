import SwiftUI
import SwiftData

struct ExerciseDetailView: View {
    let name: String
    var planned: PlannedExercise?

    @Query private var history: [SetEntry]
    @Query private var notes: [CoachNote]

    init(name: String, planned: PlannedExercise? = nil) {
        self.name = name
        self.planned = planned
        _history = Query(filter: #Predicate<SetEntry> { $0.exercise == name }, sort: \SetEntry.date, order: .reverse)
    }

    private var exercise: Exercise? { ExerciseCatalog.named(name) }
    private var guide: FormGuide? { FormGuides.guide(for: name) }
    private var best: SetEntry? { history.max { $0.weight * Double($0.reps) < $1.weight * Double($1.reps) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(name.uppercased()).font(Theme.display(34))
                if let ex = exercise, ex.photo != nil { photos(ex) }
                if let guide {
                    Text(guide.summary).font(.system(size: 15)).foregroundStyle(Theme.text.opacity(0.9))
                } else if let notes = exercise?.customNotes {
                    Text(notes).font(.system(size: 15)).foregroundStyle(Theme.text.opacity(0.9))
                }
                if let ex = exercise { atAGlance(ex) }
                // Personal first: the one thing on this page written for you.
                if let cue = planned?.cue ?? relevantNote {
                    callout("person.fill", "Your cue", cue, tint: Theme.accentWash)
                }
                if let key = FormGuides.keyCue(for: name) {
                    callout("lightbulb.fill", "Remember", key, tint: Theme.surface)
                }
                if let guide { howTo(guide) }
                if !history.isEmpty {
                    SectionLabel("Your history")
                    HStack(spacing: 24) {
                        if let best { stat("Best", "\(SyncedSettings.unit.format(pounds: best.weight)) × \(best.reps)") }
                        if let last = history.first { stat("Last", "\(SyncedSettings.unit.format(pounds: last.weight)) × \(last.reps)") }
                        stat("Sets logged", "\(history.count)")
                    }
                    if let ex = exercise { yourNumbers(ex) }
                }
            }
            .padding(20)
        }
        .background(Theme.ground)
    }

    /// What it works, what you need, how many, and how big a lift it is.
    private func atAGlance(_ ex: Exercise) -> some View {
        Card {
            glanceRow(ex.kind == .strength ? "Works" : "Feel it") {
                if ex.kind != .strength, !ex.areas.isEmpty {
                    return Text(BodyArea.allCases.filter(ex.areas.contains).map(\.label).joined(separator: ", "))
                }
                let others = ex.secondary.isEmpty ? "" : " + " + ex.secondary.map(\.label).joined(separator: ", ")
                return Text("\(Text(ex.primary.label).bold().foregroundStyle(Theme.accent))\(others)")
            }
            glanceRow("Needs") {
                Text(ex.equipment.isEmpty ? "Nothing, just you" : ex.equipment.map(\.label).sorted().joined(separator: ", "))
            }
            glanceRow("Do") { Text(dose(ex)) }
            glanceRow("Type") { Text(typeText(ex)) }
            if ex.helpsPosture { NoteChip(text: "Helps posture") }
            if let r = planned?.replaces { NoteChip(text: "Easier stand-in for \(r.lowercased())") }
        }
    }

    /// Start and finish positions, side by side. Tap one to see it full screen.
    private func photos(_ ex: Exercise) -> some View {
        ExercisePhotoPair(exercise: ex)
    }

    private func typeText(_ ex: Exercise) -> String {
        switch ex.kind {
        case .warmUp: ex.isGeneralWarmUp ? "Warm-up: gets your heart rate up" : "Warm-up: loosens you up for the lifts"
        case .stretch: "Stretch: hold it, breathe, don't bounce"
        case .strength: ex.isCompound ? "Big lift: works several muscles at once" : "Focused: targets one muscle"
        }
    }

    private func glanceRow(_ label: String, @ViewBuilder _ value: () -> Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label.uppercased()).font(Theme.label).tracking(1).foregroundStyle(Theme.muted)
                .frame(width: 58, alignment: .leading)
            value().font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "3 sets × 8-12 · aim for 135 lb × 10", or the catalog's rep range when browsing.
    private func dose(_ ex: Exercise) -> String {
        guard let planned else { return ex.isTimed ? ex.reps : "\(ex.reps) reps per set" }
        var text = "\(planned.sets) sets × \(planned.reps) reps"
        if let t = planned.target {
            text += t.weight > 0 ? " · aim for \(SyncedSettings.unit.format(pounds: t.weight)) × \(t.reps)" : " · aim for \(t.reps) reps"
        }
        return text
    }

    private func callout(_ icon: String, _ title: String, _ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.accentText).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased()).font(Theme.label).tracking(1).foregroundStyle(Theme.accentText)
                Text(text).font(.system(size: 15, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Setup, the rep and the mistakes as one card: a single numbered sequence, then "!" lines to avoid.
    private func howTo(_ guide: FormGuide) -> some View {
        Card {
            SectionLabel("How to do it")
            ForEach(Array((guide.setup + guide.movement).enumerated()), id: \.offset) { i, step in
                stepRow(marker: "\(i + 1)", step, warning: false)
            }
            if !guide.mistakes.isEmpty {
                Divider().overlay(Theme.hairline)
                ForEach(Array(guide.mistakes.enumerated()), id: \.offset) { _, mistake in
                    stepRow(marker: "!", "Avoid: " + mistake.prefix(1).lowercased() + mistake.dropFirst(), warning: true)
                }
            }
        }
    }

    private func stepRow(marker: String, _ text: String, warning: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(marker)
                .font(Theme.mono(12))
                .foregroundStyle(warning ? Theme.accentText : Theme.text)
                .frame(width: 24, height: 24)
                .background(warning ? Theme.accentWash : Theme.raised, in: Circle())
            Text(text).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A coach note about this exercise, the lift it stands in for, or one of its movement types.
    private var relevantNote: String? {
        guard let ex = exercise else { return nil }
        let harder = ExerciseCatalog.harderVersion(of: ex.name)
        return notes.first { note in
            note.exercises.contains(ex.name) || harder.map(note.exercises.contains) == true
                || !Set(note.avoid).isDisjoint(with: ex.flags)
        }?.rule
    }

    /// Estimated max from your latest session, and what it means for your goal.
    @ViewBuilder
    private func yourNumbers(_ ex: Exercise) -> some View {
        let unit = SyncedSettings.unit
        let records = history.map { SetRecord(date: $0.date, weight: $0.weight, reps: $0.reps, rpe: $0.rpe) }
        if Calibration.applies(to: ex), let max = Strength.estimatedMax(from: records) {
            let goal = TrainingGoal(rawValue: SyncedSettings.goal) ?? .buildMuscle
            let range = RepScheme.range(for: ex, goal: goal)
            Card {
                SectionLabel("Your numbers")
                Text("Estimated max: \(unit.format(pounds: max))").font(Theme.mono(15))
                Text("\(goal.rawValue): \(unit.format(pounds: Strength.weight(forReps: range.lowerBound, max: max, unit: unit))) × \(range.lowerBound) up to \(unit.format(pounds: Strength.weight(forReps: range.upperBound, max: max, unit: unit))) × \(range.upperBound), with two reps left in the tank.")
                    .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.mono(17))
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
    }
}
