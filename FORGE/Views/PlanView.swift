import SwiftUI
import SwiftData

struct PlanView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(CoachStore.self) private var coach
    @Query private var notes: [CoachNote]
    @State private var training = false
    /// A specific day's plan (from the Week tab). Nil = today's live plan.
    var day: PlannedWorkout?

    init(day: PlannedWorkout? = nil) { self.day = day }

    private var shown: PlannedWorkout? { day ?? coach.plan }
    private var isToday: Bool { shown.map { Calendar.current.isDateInToday($0.date) } ?? false }

    var body: some View {
        ScrollView {
            if let plan = shown {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        if !isToday {
                            Text(plan.date.formatted(.dateTime.weekday(.wide).month().day()).uppercased())
                                .font(Theme.mono(12)).foregroundStyle(Theme.muted)
                        }
                        Text(plan.focus.uppercased()).font(Theme.display(52))
                        Text(plan.muscles.map(\.label).joined(separator: " · ")).foregroundStyle(Theme.muted)
                    }
                    FlowRow {
                        ForEach(notes.prefix(2)) { NoteChip(text: $0.rule) }
                        Text("\(plan.minutes) MIN · \(plan.totalSets) SETS · \(plan.gymName.uppercased())")
                            .font(Theme.mono(12)).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Theme.surface, in: Capsule())
                    }
                    if SyncedSettings.warmUps, !plan.warmUp.isEmpty {
                        drills("Warm-up", plan.warmUp)
                    }
                    if !plan.exercises.isEmpty { SectionLabel("Workout") }
                    VStack(spacing: 0) {
                        ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { i, ex in
                            NavigationLink { ExerciseDetailView(name: ex.name, planned: ex) } label: {
                                ExerciseRow(index: i + 1, exercise: ex)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(Theme.hairline)
                        }
                    }
                    if !plan.coolDown.isEmpty { drills("Cool-down · optional", plan.coolDown) }
                }
                .padding(20)
            }
        }
        .background(Theme.ground)
        .safeAreaInset(edge: .bottom) {
            if isToday, shown?.isRestDay == false {
                Button("Start \(shown?.focus.lowercased() ?? "workout")") { training = true }
                    .buttonStyle(EmberButtonStyle())
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Theme.ground)
            }
        }
        .toolbar {
            NavigationLink("Edit with coach") { CoachChatView() }
        }
        .fullScreenCover(isPresented: $training) { ActiveWorkoutView() }
    }
}

extension PlanView {
    /// Warm-up or cool-down as a compact list: name and dose, tap for the form guide.
    func drills(_ title: String, _ items: [PlannedExercise]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title)
            ForEach(items) { item in
                NavigationLink { ExerciseDetailView(name: item.name) } label: {
                    HStack {
                        Text(item.name).font(.system(size: 15))
                        Spacer()
                        Text(item.reps).font(Theme.mono(13)).foregroundStyle(Theme.muted)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ExerciseRow: View {
    let index: Int
    let exercise: PlannedExercise

    private var isTimed: Bool { ExerciseCatalog.named(exercise.name)?.isTimed ?? false }
    private var isBodyweight: Bool { ExerciseCatalog.named(exercise.name)?.equipment.isEmpty ?? false }

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", index)).font(Theme.mono(13)).foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name).font(.system(size: 16, weight: .bold))
                if let replaced = exercise.replaces {
                    Text("Replaces \(replaced.lowercased())").font(.system(size: 12)).foregroundStyle(Theme.emberSoft)
                } else if let note = exercise.target?.note {
                    Text(note).font(.system(size: 12)).foregroundStyle(Theme.emberSoft).lineLimit(1)
                } else if let cue = exercise.cue {
                    Text(cue).font(.system(size: 12)).foregroundStyle(Theme.emberSoft).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(exercise.sets) × \(exercise.target.map { "\($0.reps)\(isTimed ? " s" : "")" } ?? exercise.reps)").font(Theme.mono(14))
                if let t = exercise.target, t.weight > 0 {
                    Text(SyncedSettings.unit.format(pounds: t.weight)).font(Theme.mono(12, .medium)).foregroundStyle(Theme.muted)
                } else if exercise.target == nil {
                    Text(isBodyweight ? "First time" : "Find your weight").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// Wraps children onto new lines.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
