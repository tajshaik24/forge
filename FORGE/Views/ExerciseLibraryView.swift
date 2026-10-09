import SwiftUI
import SwiftData

/// Every exercise the coach can use: built-in plus your own.
struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(CoachStore.self) private var coach
    @Query(sort: \CustomExercise.createdAt) private var custom: [CustomExercise]
    @State private var search = ""
    @State private var creating = false

    var body: some View {
        List {
            if !custom.isEmpty {
                Section("Yours") {
                    ForEach(custom) { item in
                        NavigationLink { ExerciseDetailView(name: item.name) } label: { row(item.exercise) }
                    }
                    .onDelete { idx in
                        idx.map { custom[$0] }.forEach { ctx.delete($0) }
                        try? ctx.save()
                        DataStore.refreshCustomExercises(in: ctx)
                        Task { await coach.invalidate(ctx) }
                    }
                }
            }
            ForEach(MuscleGroup.allCases, id: \.self) { m in
                let items = ExerciseCatalog.builtIn.filter {
                    $0.primary == m && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
                }
                if !items.isEmpty {
                    Section(m.label) {
                        ForEach(items, id: \.name) { ex in
                            NavigationLink { ExerciseDetailView(name: ex.name) } label: { row(ex) }
                        }
                    }
                }
            }
        }
        .searchable(text: $search)
        .scrollContentBackground(.hidden)
        .background(Theme.ground)
        .navigationTitle("Exercises")
        .toolbar { Button("New exercise", systemImage: "plus") { creating = true } }
        .sheet(isPresented: $creating) { CustomExerciseEditor() }
    }

    private func row(_ ex: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ex.name).font(.system(size: 15, weight: .semibold))
            Text(ex.equipment.isEmpty ? "Bodyweight" : ex.equipment.map(\.label).sorted().joined(separator: ", "))
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
    }
}

struct CustomExerciseEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(CoachStore.self) private var coach

    @State private var name = ""
    @State private var primary: MuscleGroup = .chest
    @State private var secondary: Set<MuscleGroup> = []
    @State private var equipment: Set<Equipment> = []
    @State private var flags: Set<MovementFlag> = []
    @State private var lowReps = 8
    @State private var highReps = 12
    @State private var isCompound = false
    @State private var notes = ""

    private var nameTaken: Bool { ExerciseCatalog.named(name) != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    if nameTaken { Text("There's already an exercise with this name.").font(.footnote).foregroundStyle(Theme.emberSoft) }
                    Picker("Main muscle", selection: $primary) {
                        ForEach(MuscleGroup.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Toggle("Big compound lift", isOn: $isCompound)
                    Stepper("Reps from \(lowReps)", value: $lowReps, in: 1...highReps)
                    Stepper("Reps up to \(highReps)", value: $highReps, in: lowReps...30)
                }
                Section("Also works") {
                    chips(MuscleGroup.allCases.filter { $0 != primary }, selection: $secondary) { $0.label }
                }
                Section("Needs (leave empty for bodyweight)") {
                    chips(Equipment.allCases, selection: $equipment) { $0.label }
                }
                Section {
                    chips(MovementFlag.allCases, selection: $flags) { $0.label }
                } header: {
                    Text("Movement type")
                } footer: {
                    Text("Lets the coach skip this when a note rules that kind of movement out.")
                }
                Section("How to do it (optional)") {
                    TextField("Setup and cues", text: $notes, axis: .vertical).lineLimit(3...8)
                }
            }
            .navigationTitle("New exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || nameTaken)
                }
            }
        }
    }

    private func chips<T: Hashable>(_ items: [T], selection: Binding<Set<T>>, label: @escaping (T) -> String) -> some View {
        FlowRow {
            ForEach(items, id: \.self) { item in
                let on = selection.wrappedValue.contains(item)
                Button {
                    if on { selection.wrappedValue.remove(item) } else { selection.wrappedValue.insert(item) }
                } label: {
                    Text(label(item)).font(.system(size: 13, weight: on ? .bold : .regular))
                        .padding(.horizontal, 12).frame(height: 32)
                        .foregroundStyle(on ? Theme.emberSoft : Theme.muted)
                        .background(on ? Theme.emberWash : .clear, in: Capsule())
                        .overlay(Capsule().stroke(on ? Theme.ember : Theme.hairline))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        let reps = lowReps == highReps ? "\(lowReps)" : "\(lowReps)-\(highReps)"
        ctx.insert(CustomExercise(name: name.trimmingCharacters(in: .whitespaces), primary: primary,
                                  secondary: Array(secondary), equipment: equipment, flags: flags,
                                  reps: reps, isCompound: isCompound, notes: notes))
        try? ctx.save()
        DataStore.refreshCustomExercises(in: ctx)
        Task { await coach.invalidate(ctx) }
        dismiss()
    }
}
