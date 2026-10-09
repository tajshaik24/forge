import SwiftUI
import SwiftData

struct ExerciseDetailView: View {
    let name: String
    var planned: PlannedExercise?

    @Query private var history: [SetEntry]
    @Query private var notes: [CoachNote]
    @State private var tab: FormTab = .setup

    enum FormTab: String, CaseIterable { case setup = "Setup", movement = "Movement", mistakes = "Mistakes" }

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
                Text(name.uppercased()).font(Theme.display(40))
                if let ex = exercise {
                    FlowRow {
                        ForEach([ex.primary] + ex.secondary, id: \.self) { m in
                            Text(m.label).font(.system(size: 12))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Theme.surface, in: Capsule())
                                .overlay(Capsule().stroke(Theme.hairline))
                        }
                        if let r = planned?.replaces { NoteChip(text: "Replaces \(r.lowercased())") }
                    }
                    if !ex.equipment.isEmpty {
                        Text("Needs: " + ex.equipment.map(\.label).sorted().joined(separator: ", "))
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                }
                if let guide {
                    Text(guide.summary).font(.system(size: 15)).foregroundStyle(Theme.text.opacity(0.9))

                    Picker("Form", selection: $tab) {
                        ForEach(FormTab.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)

                    let formSteps = steps(guide)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(formSteps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text(tab == .mistakes ? "!" : "\(i + 1)")
                                    .font(Theme.mono(12))
                                    .foregroundStyle(tab == .mistakes ? Theme.emberSoft : Theme.text)
                                    .frame(width: 24, height: 24)
                                    .background(Theme.raised, in: Circle())
                                Text(step).font(.system(size: 15))
                            }
                        }
                    }
                }
                if guide == nil, let notes = exercise?.customNotes {
                    Text(notes).font(.system(size: 15)).foregroundStyle(Theme.text.opacity(0.9))
                }
                if let cue = planned?.cue ?? relevantNote {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.emberSoft)
                        Text("Your cue: \(cue)").font(.system(size: 14))
                    }
                    .padding(14)
                    .background(Theme.emberWash, in: RoundedRectangle(cornerRadius: 14))
                }
                if !history.isEmpty {
                    SectionLabel("Your history")
                    HStack(spacing: 24) {
                        if let best { stat("Best", "\(SyncedSettings.unit.format(pounds: best.weight)) × \(best.reps)") }
                        if let last = history.first { stat("Last", "\(SyncedSettings.unit.format(pounds: last.weight)) × \(last.reps)") }
                        stat("Sets logged", "\(history.count)")
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.ground)
    }

    private func steps(_ guide: FormGuide) -> [String] {
        switch tab {
        case .setup: guide.setup
        case .movement: guide.movement
        case .mistakes: guide.mistakes
        }
    }

    /// Show a coach note that touches this exercise's movement flags.
    private var relevantNote: String? {
        guard let ex = exercise else { return nil }
        let touchesNote = notes.first { !Set($0.avoid).isDisjoint(with: [.axialLoading, .standingHeavy, .deepKneeBend]) }
        return ex.primary == .quads || ex.primary == .hamstrings ? touchesNote?.rule : nil
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.mono(17))
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
    }
}
