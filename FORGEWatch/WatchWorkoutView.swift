import SwiftUI
import SwiftData
import WatchKit

/// Runs the HealthKit workout on the wrist (best heart-rate source) and logs sets with the Digital Crown.
struct WatchWorkoutView: View {
    let plan: PlannedWorkout

    init(plan: PlannedWorkout) { self.plan = plan }

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    private let tracker = WorkoutTracker.shared

    @State private var exerciseIndex = 0
    @State private var setNumber = 1
    /// In the user's unit; converted to pounds when saved.
    @State private var weight: Double = 0
    @State private var reps: Double = 10
    @State private var editing: Field = .reps
    @State private var restUntil: Date?
    @State private var setStarted = Date()
    @State private var done = false

    enum Field { case weight, reps }
    private let unit = SyncedSettings.unit

    private var current: PlannedExercise? {
        plan.exercises.indices.contains(exerciseIndex) ? plan.exercises[exerciseIndex] : nil
    }

    var body: some View {
        Group {
            if done {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(Theme.ember)
                    Text("Saved to Health").font(.headline)
                    Button("Done") { dismiss() }
                }
            } else if let restUntil {
                rest(until: restUntil)
            } else if let ex = current {
                log(ex)
            }
        }
        .navigationBarBackButtonHidden(!done)
        .task {
            await tracker.start(focus: plan.focus)
            prefill()
        }
        .onChange(of: tracker.remoteSets.count) { if let set = tracker.remoteSets.last { loggedOnPhone(set) } }
        .onChange(of: tracker.remoteRest) {
            guard let change = tracker.remoteRest else { return }
            restUntil = change.until
            if change.until == nil { setStarted = .now }
        }
        .onChange(of: tracker.isRunning) {
            // Ended from the iPhone.
            guard !tracker.isRunning, !done else { return }
            if tracker.discarded { dismiss() } else { done = true }
        }
    }

    private func log(_ ex: PlannedExercise) -> some View {
        // Holds and carries log seconds in place of reps.
        let timed = ExerciseCatalog.named(ex.name)?.isTimed ?? false
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(ex.name) · \(setNumber)/\(ex.sets)").font(.system(size: 13, weight: .heavy)).lineLimit(1)
                Spacer()
                Label("\(Int(tracker.heartRate))", systemImage: "heart.fill")
                    .font(Theme.mono(12)).labelStyle(.titleAndIcon)
            }
            if let t = ex.target, t.weight > 0 {
                Text("Target \(unit.format(pounds: t.weight)) × \(t.reps)")
                    .font(.system(size: 11)).foregroundStyle(Theme.emberSoft)
            }
            HStack(spacing: 6) {
                valueBox(weight.formatted(.number.precision(.fractionLength(0...1))), unit.label, .weight)
                valueBox("\(Int(reps))", timed ? "SEC" : "REPS", .reps)
            }
            .focusable()
            .digitalCrownRotation(editing == .weight ? $weight : $reps,
                                  from: editing == .weight ? 0 : 1,
                                  through: editing == .weight ? 1000 : (timed ? 300 : 50),
                                  by: editing == .weight ? unit.step : (timed ? 5 : 1),
                                  sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
            Button("Log set") { logSet(ex) }
                .buttonStyle(.borderedProminent)
            Button("End workout", role: .destructive) { Task { await finish() } }
                .font(.footnote)
        }
    }

    private func valueBox(_ value: String, _ unit: String, _ field: Field) -> some View {
        Button { editing = field } label: {
            VStack(spacing: 2) {
                Text(value).font(Theme.mono(26)).monospacedDigit()
                Text(unit).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(editing == field ? Theme.ember : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value) \(unit). Turn the Digital Crown to change.")
    }

    private func rest(until: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = max(0, Int(until.timeIntervalSince(context.date)))
            VStack(spacing: 6) {
                Text("REST").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
                Text(String(format: "%d:%02d", left / 60, left % 60)).font(Theme.mono(34)).monospacedDigit()
                Label("\(Int(tracker.heartRate))", systemImage: "heart.fill").font(Theme.mono(14))
                if let ex = current { Text("Next: \(ex.name) set \(setNumber)").font(.system(size: 12)).lineLimit(1) }
                Button("Skip rest") { restUntil = nil; setStarted = .now; tracker.shareRest(until: nil) }
            }
            .onChange(of: left) {
                if left == 0 { WKInterfaceDevice.current().play(.stop); restUntil = nil; setStarted = .now }
            }
        }
    }

    private func logSet(_ ex: PlannedExercise) {
        if tracker.isMirrored {
            // The iPhone keeps the history; this adds the Health segment and sends it over.
            let set = LoggedSet(exercise: ex.name, weight: unit.toPounds(weight), reps: Int(reps), rpe: nil,
                                start: setStarted, end: .now)
            Task { await tracker.recordSet(set) }
        } else {
            SetLogger.log(exercise: ex.name, weight: unit.toPounds(weight), reps: Int(reps),
                          focus: plan.focus, gymName: plan.gymName, setStarted: setStarted, in: ctx)
        }
        WKInterfaceDevice.current().play(.success)
        advance(ex)
    }

    /// A set logged on the iPhone: move on as if it was logged here.
    private func loggedOnPhone(_ set: LoggedSet) {
        guard let ex = current else { return }
        if set.exercise != ex.name {
            guard let i = plan.exercises.firstIndex(where: { $0.name == set.exercise }) else { return }
            exerciseIndex = i
            setNumber = 1
        }
        WKInterfaceDevice.current().play(.click)
        advance(plan.exercises[exerciseIndex])
    }

    private func advance(_ ex: PlannedExercise) {
        if setNumber < ex.sets {
            setNumber += 1
        } else if exerciseIndex + 1 < plan.exercises.count {
            exerciseIndex += 1
            setNumber = 1
            prefill()
        } else {
            Task { await finish() }
            return
        }
        restUntil = Date().addingTimeInterval(TimeInterval(plan.restSeconds))
    }

    private func finish() async {
        let shared = tracker.isMirrored
        let result = await tracker.finish()
        guard !shared else { done = true; return }   // the iPhone files it from the result
        let session = SetLogger.openSession(focus: plan.focus, gymName: plan.gymName, in: ctx)
        session.endDate = result?.end ?? .now
        if let r = result {
            session.date = min(session.date, r.start)
            session.healthWorkoutID = r.workoutID
            session.activeCalories = r.activeCalories
            session.averageHeartRate = r.averageHeartRate
            session.maxHeartRate = r.maxHeartRate
            session.heartRates = r.timeline
        }
        try? ctx.save()
        done = true
    }

    private func prefill() {
        guard let name = current?.name else { return }
        if let t = current?.target {
            weight = unit.roundToStep(unit.fromPounds(t.weight))
            reps = Double(t.reps)
            return
        }
        var d = FetchDescriptor<SetEntry>(predicate: #Predicate { $0.exercise == name },
                                          sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = 1
        if let last = try? ctx.fetch(d).first {
            weight = unit.roundToStep(unit.fromPounds(last.weight))
            reps = Double(last.reps)
        } else {
            weight = 0
            reps = Double(current?.reps.split(separator: "-").first ?? "10") ?? 10
        }
    }
}
