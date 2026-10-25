import SwiftUI
import SwiftData

/// Every exercise the coach can use: built-in plus your own.
struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(CoachStore.self) private var coach
    @Query(sort: \CustomExercise.createdAt) private var custom: [CustomExercise]
    @State private var search = ""
    @State private var creating = false
    @State private var shelf: Shelf = .strength

    /// The library's tabs: the three kinds of exercise, plus posture work across all of them.
    enum Shelf: String, CaseIterable, Identifiable {
        case strength = "Strength", warmUp = "Warm-ups", stretch = "Stretches", posture = "Posture"
        var id: String { rawValue }

        func includes(_ ex: Exercise) -> Bool {
            switch self {
            case .strength: ex.kind == .strength
            case .warmUp: ex.kind == .warmUp
            case .stretch: ex.kind == .stretch
            case .posture: ex.helpsPosture
            }
        }
    }

    private var shown: [Exercise] {
        ExerciseCatalog.builtIn.filter {
            shelf.includes($0) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $shelf) {
                    ForEach(Shelf.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                if shelf == .posture {
                    Text("Moves that undo desk posture: they strengthen your upper back and deep core, and open tight chests and hips.")
                }
            }
            if shelf == .strength, !custom.isEmpty {
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
            if shelf == .strength {
                ForEach(MuscleGroup.allCases, id: \.self) { m in
                    section(m.label, shown.filter { $0.primary == m })
                }
            } else {
                // Warm-ups, stretches and posture work are grouped by where you feel them.
                section("Get moving", shown.filter(\.isGeneralWarmUp))
                ForEach(BodyArea.allCases, id: \.self) { area in
                    section(area.label, shown.filter { !$0.isGeneralWarmUp && primaryArea(of: $0) == area })
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

    @ViewBuilder
    private func section(_ title: String, _ items: [Exercise]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items, id: \.name) { ex in
                    NavigationLink { ExerciseDetailView(name: ex.name) } label: { row(ex) }
                }
            }
        }
    }

    /// One area per exercise so nothing is listed twice: the first that applies, in body order.
    private func primaryArea(of ex: Exercise) -> BodyArea {
        BodyArea.allCases.first(where: ex.areas.contains) ?? BodyArea.stretched(by: ex.primary).first ?? .upperBack
    }

    private func row(_ ex: Exercise) -> some View {
        HStack(spacing: 12) {
            ExercisePhoto(exercise: ex, frame: 1).frame(width: 52, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name).font(.system(size: 15, weight: .semibold))
                Text(detail(ex)).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
    }

    private func detail(_ ex: Exercise) -> String {
        let kit = ex.equipment.isEmpty ? "Bodyweight" : ex.equipment.map(\.label).sorted().joined(separator: ", ")
        return ex.kind == .strength ? kit : "\(ex.reps) · \(kit)"
    }
}

/// A start or finish photo from the library, or a quiet placeholder when there isn't one.
struct ExercisePhoto: View {
    let exercise: Exercise
    var frame = 0

    var body: some View {
        if let name = exercise.photo, let image = UIImage(named: "\(name)-\(frame).jpg") {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                Theme.surface
                Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Theme.muted)
            }
        }
    }

    private var icon: String {
        switch exercise.kind {
        case .strength: "dumbbell"
        case .warmUp: "figure.flexibility"
        case .stretch: "figure.cooldown"
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
                    if nameTaken { Text("There's already an exercise with this name.").font(.footnote).foregroundStyle(Theme.accentText) }
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
                        .foregroundStyle(on ? Theme.accentText : Theme.muted)
                        .background(on ? Theme.accentWash : .clear, in: Capsule())
                        .overlay(Capsule().stroke(on ? Theme.accent : Theme.hairline))
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
