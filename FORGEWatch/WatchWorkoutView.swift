import SwiftUI
import SwiftData
import WatchKit

/// Runs the HealthKit workout on the wrist (best heart-rate source) and logs sets with the Digital Crown.
/// Three pages, swiped sideways so the Crown stays free for weight and reps: controls, the set
/// you're on, and the whole workout with what you've done.
struct WatchWorkoutView: View {
    let plan: PlannedWorkout

    init(plan: PlannedWorkout) { self.plan = plan }

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    private let tracker = WorkoutTracker.shared

    @State private var page = Page.log
    @State private var exerciseIndex = 0
    @State private var setNumber = 1
    /// In the user's unit; converted to pounds when saved.
    @State private var weight: Double = 0
    @State private var reps: Double = 10
    @State private var editing: Field = .reps
    @State private var restUntil: Date?
    @State private var setStarted = Date()
    @State private var done = false
    @State private var result: WorkoutTracker.Result?
    @State private var confirmEnd = false
    /// Sets done this workout, per exercise, on either device.
    @State private var logged: [String: [SetDone]] = [:]
    /// Warm-up steps done (or skipped) per exercise.
    @State private var warmedUp: [String: Int] = [:]

    enum Page { case controls, log, workout }
    enum Field { case weight, reps }
    struct SetDone: Hashable { let pounds: Double; let reps: Int }
    private let unit = SyncedSettings.unit

    private var current: PlannedExercise? {
        plan.exercises.indices.contains(exerciseIndex) ? plan.exercises[exerciseIndex] : nil
    }

    private var totalDone: Int { logged.values.reduce(0) { $0 + $1.count } }

    /// Up to two drills and the warm-up sets for each lift, the same as on the iPhone.
    private var warmUpSteps: [String: [WarmUps.Step]] { WarmUps.beforeEachLift(plan, unit: unit) }

    /// The next warm-up step for this lift, until its first working set is logged.
    private func pendingWarmUp(_ ex: PlannedExercise) -> (index: Int, total: Int, step: WarmUps.Step)? {
        guard SyncedSettings.warmUps, logged[ex.name]?.isEmpty != false,
              let steps = warmUpSteps[ex.name] else { return nil }
        let i = warmedUp[ex.name] ?? 0
        return i < steps.count ? (i, steps.count, steps[i]) : nil
    }

    var body: some View {
        Group {
            if done {
                summary
            } else {
                TabView(selection: $page) {
                    controls.tag(Page.controls)
                    Group {
                        if let restUntil {
                            rest(until: restUntil)
                        } else if let ex = current, let warm = pendingWarmUp(ex) {
                            warmUp(ex, warm.index, warm.total, warm.step)
                        } else if let ex = current {
                            log(ex)
                        }
                    }
                    .tag(Page.log)
                    overview.tag(Page.workout)
                }
                .tabViewStyle(.page)
            }
        }
        .navigationBarBackButtonHidden(!done)
        .task {
            await tracker.start(focus: plan.focus)
            resume()
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

    // MARK: Pages

    private func log(_ ex: PlannedExercise) -> some View {
        // Holds and carries log seconds in place of reps.
        let timed = ExerciseCatalog.named(ex.name)?.isTimed ?? false
        return ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(ex.name).font(.system(size: 15, weight: .heavy))
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Text("Set \(min(setNumber, ex.sets)) of \(ex.sets)")
                    if let t = ex.target, t.weight > 0 {
                        Text("· \(unit.format(pounds: t.weight)) × \(t.reps)").foregroundStyle(Theme.accentText)
                    }
                }
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                .lineLimit(1).minimumScaleFactor(0.7)
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
            }
        }
    }

    /// One warm-up step at a time: a drill, or a lighter set followed by a short rest.
    private func warmUp(_ ex: PlannedExercise, _ index: Int, _ total: Int, _ step: WarmUps.Step) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("WARM-UP \(index + 1) OF \(total)").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent)
                Text("Before \(ex.name)").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                switch step {
                case .drill(let d):
                    Text(d.name).font(.system(size: 17, weight: .heavy)).fixedSize(horizontal: false, vertical: true)
                    Text(d.reps).font(Theme.mono(15)).foregroundStyle(Theme.accentText)
                case .ramp(let r):
                    Text("\(unit.format(pounds: r.weight)) × \(r.reps)").font(Theme.mono(24)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("Warm-up set · rest \(Dose.label(r.rest))").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Button("Done") { completeWarmUp(ex, step) }
                    .buttonStyle(.borderedProminent)
                Button("Skip warm-up") {
                    warmedUp[ex.name] = total
                    setStarted = .now
                }
                .font(.footnote)
            }
        }
    }

    private func valueBox(_ value: String, _ unit: String, _ field: Field) -> some View {
        Button { editing = field } label: {
            VStack(spacing: 0) {
                Text(value).font(Theme.mono(22)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(editing == field ? Theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value) \(unit). Turn the Digital Crown to change.")
    }

    private func rest(until: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = max(0, Int(until.timeIntervalSince(context.date)))
            ScrollView {
                VStack(spacing: 6) {
                    Text("REST").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
                    Text(String(format: "%d:%02d", left / 60, left % 60)).font(Theme.mono(34)).monospacedDigit()
                    Label("\(Int(tracker.heartRate))", systemImage: "heart.fill").font(Theme.mono(14))
                    if let ex = current {
                        Text(pendingWarmUp(ex) != nil ? "Next: \(ex.name) warm-up" : "Next: \(ex.name), set \(setNumber)")
                            .font(.system(size: 12))
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Skip rest") { restUntil = nil; setStarted = .now; tracker.shareRest(until: nil) }
                }
                .frame(maxWidth: .infinity)
            }
            .onChange(of: left) {
                if left == 0 { WKInterfaceDevice.current().play(.stop); restUntil = nil; setStarted = .now }
            }
        }
    }

    /// Every exercise with the sets done so far. Tap one to do it next.
    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(plan.focus.uppercased()) · \(totalDone) SETS")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
                ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { i, ex in
                    let sets = logged[ex.name] ?? []
                    Button { jump(to: i) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(ex.name).font(.system(size: 13, weight: .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 4)
                                Text("\(sets.count)/\(ex.sets)").font(Theme.mono(12))
                                    .foregroundStyle(sets.count >= ex.sets ? Theme.accentText : Theme.muted)
                            }
                            if !sets.isEmpty {
                                Text(sets.map(describe).joined(separator: ", "))
                                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(i == exerciseIndex ? Theme.accentWash : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var controls: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let start = tracker.startDate {
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                        .font(Theme.mono(28)).monospacedDigit().foregroundStyle(Theme.accent)
                }
                HStack(spacing: 12) {
                    Label("\(Int(tracker.heartRate))", systemImage: "heart.fill")
                    Label("\(Int(tracker.activeCalories))", systemImage: "flame.fill")
                }
                .font(Theme.mono(13))
                if let ex = current, exerciseIndex + 1 < plan.exercises.count {
                    Button("Skip \(ex.name)") { jump(to: exerciseIndex + 1) }
                        .lineLimit(2).minimumScaleFactor(0.8)
                }
                Button("End workout", role: .destructive) { confirmEnd = true }
            }
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog("End workout?", isPresented: $confirmEnd) {
            Button("End and save", role: .destructive) { Task { await finish() } }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("\(totalDone) sets logged.")
        }
    }

    /// The end screen: the headline numbers, then each exercise's sets.
    private var summary: some View {
        let volume = logged.values.joined().reduce(0) { $0 + $1.pounds * Double($1.reps) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    Text("WORKOUT SAVED").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
                }
                Text(plan.focus.uppercased()).font(Theme.display(22))
                    .lineLimit(2).minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    if let r = result {
                        stat(Duration.seconds(r.end.timeIntervalSince(r.start)).formatted(.time(pattern: .hourMinute)), "TIME")
                    }
                    stat("\(totalDone)", "SETS")
                    if volume > 0 {
                        stat(unit.fromPounds(volume).formatted(.number.notation(.compactName).precision(.fractionLength(0...1))),
                             "\(unit.label) LIFTED")
                    }
                    if let r = result, r.averageHeartRate > 0 { stat("\(Int(r.averageHeartRate))", "AVG BPM") }
                    if let r = result, r.activeCalories > 0 { stat("\(Int(r.activeCalories))", "KCAL") }
                }
                ForEach(plan.exercises.filter { logged[$0.name]?.isEmpty == false }) { ex in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ex.name).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        Text((logged[ex.name] ?? []).map(describe).joined(separator: ", "))
                            .font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Theme.mono(18)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
        }
    }

    /// "135×8", or "×12" for bodyweight.
    private func describe(_ set: SetDone) -> String {
        guard set.pounds > 0 else { return "×\(set.reps)" }
        return unit.fromPounds(set.pounds).formatted(.number.precision(.fractionLength(0...1))) + "×\(set.reps)"
    }

    // MARK: Actions

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
        logged[ex.name, default: []].append(SetDone(pounds: unit.toPounds(weight), reps: Int(reps)))
        WKInterfaceDevice.current().play(.success)
        advance(ex)
    }

    private func completeWarmUp(_ ex: PlannedExercise, _ step: WarmUps.Step) {
        warmedUp[ex.name, default: 0] += 1
        WKInterfaceDevice.current().play(.click)
        if case .ramp(let r) = step {
            let until = Date().addingTimeInterval(TimeInterval(r.rest))
            restUntil = until
            tracker.shareRest(until: until)
        } else {
            setStarted = .now
        }
    }

    /// A set logged on the iPhone: move on as if it was logged here.
    private func loggedOnPhone(_ set: LoggedSet) {
        logged[set.exercise, default: []].append(SetDone(pounds: set.weight, reps: set.reps))
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

    /// Picks up at an exercise from the workout list.
    private func jump(to index: Int) {
        guard plan.exercises.indices.contains(index) else { return }
        exerciseIndex = index
        setNumber = min((logged[plan.exercises[index].name]?.count ?? 0) + 1, plan.exercises[index].sets)
        restUntil = nil
        setStarted = .now
        prefill()
        withAnimation { page = .log }
    }

    /// Reopened mid-workout: count the sets already saved here and carry on from the first unfinished lift.
    private func resume() {
        guard let start = tracker.startDate else { return }
        let names = Set(plan.exercises.map(\.name))
        let d = FetchDescriptor<SetEntry>(predicate: #Predicate { $0.date >= start }, sortBy: [SortDescriptor(\.date)])
        for set in (try? ctx.fetch(d)) ?? [] where names.contains(set.exercise) {
            logged[set.exercise, default: []].append(SetDone(pounds: set.weight, reps: set.reps))
        }
        if let i = plan.exercises.firstIndex(where: { (logged[$0.name]?.count ?? 0) < $0.sets }) {
            exerciseIndex = i
            setNumber = (logged[plan.exercises[i].name]?.count ?? 0) + 1
        }
    }

    private func finish() async {
        let shared = tracker.isMirrored
        let result = await tracker.finish()
        self.result = result
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
