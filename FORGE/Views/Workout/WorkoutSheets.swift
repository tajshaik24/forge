import SwiftUI
import SwiftData

/// Swap and Add: the coach's suggestions first, then every strength exercise in the library
/// (yours included), searchable. Ones your gym lacks or your notes rule out say so but stay pickable:
/// you know what's in front of you.
struct ExercisePickerSheet: View {
    let title: String
    /// Under the title: the lift being swapped.
    var subtitle: String? = nil
    let suggestedTitle: String
    let suggested: [Exercise]
    /// Names already in the workout (and the lift being swapped), left out.
    let excluding: Set<String>
    let gym: GymProfile?
    let avoiding: Set<MovementFlag>
    /// Debug screenshots: start with something typed in the search field.
    var initialSearch = ""
    let onPick: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var everything: [Exercise] {
        ExerciseCatalog.all.filter { $0.kind == .strength && !excluding.contains($0.name) }
    }

    private func matches(_ ex: Exercise) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return ex.name.localizedCaseInsensitiveContains(q) || ex.primary.label.localizedCaseInsensitiveContains(q)
            || ex.equipment.contains { $0.label.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        // A handful of suggestions, so the whole library is a short scroll away.
        let top = Array(suggested.filter { !excluding.contains($0.name) && matches($0) }.prefix(6))
        let all = everything.filter(matches)
        NavigationStack {
            List {
                if !top.isEmpty {
                    Section(suggestedTitle) { ForEach(top, id: \.name, content: row) }
                }
                ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                    let items = all.filter { $0.primary == muscle }.sorted { $0.name < $1.name }
                    if !items.isEmpty {
                        Section(search.isEmpty ? muscle.label : "\(muscle.label) · \(items.count)") {
                            ForEach(items, id: \.name, content: row)
                        }
                    }
                }
            }
            .overlay {
                if top.isEmpty && all.isEmpty { ContentUnavailableView.search(text: search) }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Exercise, muscle or equipment")
            .onAppear { if search.isEmpty { search = initialSearch } }
            .navigationTitle(title)
            .navigationSubtitle(subtitle ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    private func row(_ ex: Exercise) -> some View {
        let missing = gym.map { !ex.equipment.isSubset(of: $0.equipment) } ?? false
        let ruledOut = !ex.flags.isDisjoint(with: avoiding)
        return Button { onPick(ex); dismiss() } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ex.name).font(.body.weight(.semibold)).foregroundStyle(missing ? Theme.muted : Theme.text)
                    Text(ex.equipment.isEmpty ? "Bodyweight" : ex.equipment.map(\.label).sorted().joined(separator: ", "))
                        .font(.footnote).foregroundStyle(Theme.muted)
                    // Plain stacks, not Labels: a List lays Labels out like row icons, with a wide gap.
                    if missing, let gym {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                            Text("Not at \(gym.name)")
                        }
                        .font(.footnote).foregroundStyle(Theme.muted)
                    }
                    if ruledOut {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle")
                            Text("Your coach notes say to avoid this")
                        }
                        .font(.footnote).foregroundStyle(Theme.accentText)
                    }
                }
                Spacer(minLength: 8)
                if ex.isCustom {
                    Text("Yours").font(.caption.weight(.bold)).foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.accentWash, in: Capsule())
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.surface)
    }
}

/// Fixes a logged set: weight, reps, how it felt, or deletes it.
struct EditSetSheet: View {
    @Bindable var entry: SetEntry
    let unit: WeightUnit
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var weight: Double = 0

    init(entry: SetEntry, unit: WeightUnit) {
        self.entry = entry
        self.unit = unit
    }

    private var timed: Bool { ExerciseCatalog.named(entry.exercise)?.isTimed ?? false }

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: $weight, in: 0...1000, step: unit.step) {
                    LabeledContent("Weight", value: weight == 0 ? "None" : "\(weight.formatted(.number.precision(.fractionLength(0...1)))) \(unit.rawValue)")
                }
                Stepper(value: $entry.reps, in: 0...(timed ? 600 : 100), step: timed ? 5 : 1) {
                    LabeledContent(timed ? "Time" : "Reps", value: timed ? Dose.label(entry.reps) : "\(entry.reps)")
                }
                Picker("How it felt", selection: Binding(get: { Effort(rpe: entry.rpe) }, set: { entry.rpe = $0.rpe })) {
                    ForEach(Effort.allCases) { Text($0.label).tag($0) }
                }
                Section {
                    Button("Delete set", role: .destructive) {
                        ctx.delete(entry)
                        try? ctx.save()
                        dismiss()
                    }
                }
            }
            .navigationTitle(entry.exercise)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        entry.weight = unit.toPounds(weight)
                        try? ctx.save()
                        dismiss()
                    }
                }
            }
            .onAppear { weight = unit.roundToStep(unit.fromPounds(entry.weight)) }
        }
        .presentationDetents([.medium])
    }
}
