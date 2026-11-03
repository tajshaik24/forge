import SwiftUI
import SwiftData
import WatchKit

/// Runs the HealthKit workout on the wrist (best heart-rate source) and logs sets with the Digital Crown.
/// Three pages, swiped sideways so the Crown stays free for weight and reps: controls, the set
/// you're on, and the whole workout. Time and heart rate sit at the top of every page.
struct WatchWorkoutView: View {
    @State private var model: WatchWorkout
    @State private var page: Page

    init(plan: PlannedWorkout, isPlaceholder: Bool = false) {
        _model = State(initialValue: WatchWorkout(plan: plan, isPlaceholder: isPlaceholder))
        _page = State(initialValue: .log)
    }

    #if DEBUG
    /// Demo screens open in a given state.
    init(model: WatchWorkout, page: Page) {
        _model = State(initialValue: model)
        _page = State(initialValue: page)
    }
    #endif

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DailyPlan.updatedAt, order: .reverse) private var plans: [DailyPlan]
    @State private var adding = false
    private let tracker = WorkoutTracker.shared

    /// Today's plan as it reaches the Watch: over iCloud, or straight from the iPhone.
    private var incoming: PlannedWorkout? {
        plans.first { $0.dayKey == DayKey.of(.now) }?.plan ?? PhoneWatchLink.shared.todayPlan
    }

    enum Page { case controls, log, list }

    var body: some View {
        Group {
            if let summary = model.summary {
                WatchSummaryView(model: model, summary: summary) { dismiss() }
            } else {
                TabView(selection: $page) {
                    WatchControlsPage(model: model, adding: $adding).tag(Page.controls)
                    logPage.tag(Page.log)
                    WatchListPage(model: model, adding: $adding) { i in
                        model.jump(to: i)
                        withAnimation { page = .log }
                    }
                    .tag(Page.list)
                }
                .tabViewStyle(.page)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { WatchVitals(model: model) }
                }
            }
        }
        .navigationBarBackButtonHidden(model.summary == nil)
        .task {
            guard !model.isDemo else { return }
            await tracker.start(focus: model.plan.focus)
            model.begin(in: ctx)
            adoptIfPlaceholder()
        }
        // The haptic at the end of rest, on any page and with the screen down. The task sleeps until the
        // rest ends and is replaced whenever the end moves (+30 s, skip, the iPhone).
        .task(id: model.restUntil) {
            guard let until = model.restUntil else { return }
            do {
                try await Task.sleep(until: .now + .seconds(max(0, until.timeIntervalSinceNow)), clock: .continuous)
            } catch { return }
            WKInterfaceDevice.current().play(.stop)
            model.restEnded()
        }
        // The effort question answers itself as Good after a few seconds, so logging never stalls.
        .task(id: model.pending) {
            guard model.pending != nil else { return }
            #if DEBUG
            if WatchDemo.isOn, WatchDemo.screen == "effort" { return }   // hold still for the screenshot
            #endif
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            model.rate(.good)
        }
        .onChange(of: tracker.remoteSets.count) { model.ingestRemote() }
        .onChange(of: tracker.remoteRest) {
            guard let change = tracker.remoteRest else { return }
            model.remoteRest(until: change.until)
        }
        .onChange(of: tracker.startDate) { model.noteStart() }
        // Lifts added or swapped on the iPhone during a shared workout, or the plan for a workout
        // started there before it had synced.
        .onChange(of: PhoneWatchLink.shared.todayPlan) {
            guard let updated = PhoneWatchLink.shared.todayPlan else { return }
            if model.isPlaceholder || (tracker.isMirrored && updated.isCustom == model.plan.isCustom) {
                model.adopt(updated)
            }
        }
        .onChange(of: incoming) { adoptIfPlaceholder() }
        .onChange(of: tracker.isRunning) {
            // Ended from the iPhone.
            guard !tracker.isRunning, model.summary == nil, !model.isDemo, !model.isFinishing else { return }
            if tracker.discarded { dismiss() } else { model.endedOnPhone() }
        }
        .sheet(isPresented: $adding) {
            NavigationStack {
                WatchAddExerciseView(existing: Set(model.plan.exercises.map(\.name))) {
                    model.add($0)
                    page = .log
                }
            }
        }
    }

    /// A workout started on the iPhone before its plan got here takes the plan once it arrives.
    private func adoptIfPlaceholder() {
        guard model.isPlaceholder, let plan = incoming, !plan.isRestDay else { return }
        model.adopt(plan)
    }

    /// The set you're on, or what comes before or after it.
    @ViewBuilder
    private var logPage: some View {
        if model.pending != nil {
            WatchEffortPage(model: model)
        } else if model.plan.exercises.isEmpty {
            WatchEmptyPage(adding: $adding)
        } else if model.showsAllDone {
            WatchAllDonePage(model: model, adding: $adding)
        } else if model.showsWarmUp {
            WatchWarmUpPage(model: model)
        } else {
            WatchLogPage(model: model)
        }
    }
}

/// Screen-size tweaks: the 40/41/42 mm watches get tighter spacing so the logging screen still fits.
enum WatchScreen {
    static let isSmall = WKInterfaceDevice.current().screenBounds.height < 230
}

// MARK: - Top row

/// Elapsed time and heart rate, in the corner opposite the clock.
struct WatchVitals: View {
    let model: WatchWorkout

    var body: some View {
        HStack(spacing: 6) {
            if let start = model.startDate {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .foregroundStyle(Theme.text)
            }
            HStack(spacing: 2) {
                Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(Theme.accentText)
                Text(model.heartRate > 0 ? "\(Int(model.heartRate))" : "--")
            }
        }
        .font(Theme.mono(14))
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Logging

/// The set you're on, on one screen: the lift, where you are in it, weight and reps on two tiles the
/// Digital Crown changes, and ✓, or the rest countdown while you set up the next one.
struct WatchLogPage: View {
    @Bindable var model: WatchWorkout
    @FocusState private var field: Field?

    enum Field: Hashable { case weight, reps }

    var body: some View {
        VStack(alignment: .leading, spacing: WatchScreen.isSmall ? 3 : 5) {
            if let lift = model.lift {
                Text(lift.exercise.name)
                    .font(.system(size: WatchScreen.isSmall ? 15 : 16, weight: .bold))
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    WatchSetDots(lift: lift, extra: model.extraSet)
                    Spacer(minLength: 2)
                    Text(position(lift)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                if let line = guidance(lift) {
                    Text(line).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accentText)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                HStack(spacing: 6) {
                    tile(.weight, value: weightText, label: model.unit.label)
                        .digitalCrownRotation($model.weight, from: 0, through: model.unit == .lb ? 1000 : 450,
                                              by: model.unit.step, sensitivity: .medium, isContinuous: false,
                                              isHapticFeedbackEnabled: true)
                    tile(.reps, value: "\(Int(model.reps))", label: model.isTimed ? "SEC" : "REPS")
                        .digitalCrownRotation($model.reps, from: 0, through: model.isTimed ? 600 : 50,
                                              by: model.isTimed ? 5 : 1, sensitivity: .medium, isContinuous: false,
                                              isHapticFeedbackEnabled: true)
                }
                .frame(maxHeight: .infinity)
                bottom(lift)
            }
        }
        .padding(.horizontal, 2)
        .defaultFocus($field, .reps)
        .onAppear { field = field ?? .reps }
    }

    private var weightText: String {
        if model.isBodyweight, model.weight == 0 { return "BW" }
        return model.weight.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// "Set 2 of 3", "Test set 2", "Done", "Extra set".
    private func position(_ lift: WorkoutProgress.Lift) -> String {
        if lift.isTesting { return "Test set \(lift.tests.count + 1)" }
        if model.extraSet { return "Extra set" }
        if lift.isDone { return "Done · \(lift.working.count) of \(lift.planned)" }
        return "Set \(lift.nextSet) of \(lift.planned)"
    }

    /// The coach's line: how to do a test set, or the call for this set.
    private func guidance(_ lift: WorkoutProgress.Lift) -> String? {
        if lift.isTesting, lift.tests.isEmpty { return "\(model.testReps) reps, then rate it" }
        if lift.isTesting, model.note == nil { return "\(model.testReps) reps, then rate it" }
        return model.note
    }

    /// A value the Crown changes once it's selected. Tapping selects it (not a Button: it'd take the focus tap).
    private func tile(_ f: Field, value: String, label: String) -> some View {
        let selected = field == f
        return VStack(spacing: 0) {
            Text(value)
                .font(Theme.mono(30, .bold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(Theme.text)
            Text(label).font(.system(size: 10, weight: .heavy)).tracking(0.5)
                .foregroundStyle(selected ? Theme.accentText : Theme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: WatchScreen.isSmall ? 40 : 46)
        .background(selected ? Theme.accentWash : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 2.5 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .focusable()
        .focused($field, equals: f)
        .focusEffectDisabled()
        .onTapGesture { field = f }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
        .accessibilityHint("Turn the Digital Crown to change.")
    }

    @ViewBuilder
    private func bottom(_ lift: WorkoutProgress.Lift) -> some View {
        if let until = model.restUntil {
            WatchRestBar(model: model, until: until)
        } else if model.liftFinished {
            Button { model.addSet() } label: {
                Label("Add set", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Theme.raised, in: Capsule())
            }
            .buttonStyle(.plain)
        } else {
            Button { model.logTapped() } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: WatchScreen.isSmall ? 38 : 42)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lift.isTesting ? "Log test set" : "Log set")
        }
    }
}

/// Where you are in a lift: test sets as small squares, then a dot per planned set
/// (filled when done, a ring on the one you're on, dim still to come).
struct WatchSetDots: View {
    let lift: WorkoutProgress.Lift
    var extra = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(lift.tests.enumerated()), id: \.offset) { _, _ in
                RoundedRectangle(cornerRadius: 2).fill(Theme.accentText.opacity(0.55)).frame(width: 7, height: 7)
            }
            if lift.isTesting {
                RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.accentText, lineWidth: 1.5).frame(width: 8, height: 8)
            }
            let shown = max(lift.planned, lift.working.count + (extra ? 1 : 0))
            ForEach(0..<shown, id: \.self) { i in
                if i < lift.working.count {
                    Circle().fill(Theme.accent).frame(width: 8, height: 8)
                } else if i == lift.working.count, !lift.isTesting {
                    Circle().strokeBorder(Theme.accentText, lineWidth: 2).frame(width: 9, height: 9)
                } else {
                    Circle().fill(Theme.raised).frame(width: 8, height: 8)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Rest, in place of ✓: the time left (and a bar running down), +30 s, and skip.
struct WatchRestBar: View {
    let model: WatchWorkout
    let until: Date

    var body: some View {
        HStack(spacing: 5) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = max(0, until.timeIntervalSince(context.date))
                let share = model.restLength > 0 ? min(1, left / model.restLength) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface)
                    GeometryReader { geo in
                        Capsule().fill(Theme.accentWash)
                            .frame(width: max(geo.size.height, geo.size.width * share))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "timer").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accentText)
                        Text(clock(Int(left.rounded(.up))))
                            .font(Theme.mono(17, .bold)).monospacedDigit().foregroundStyle(Theme.text)
                    }
                    .padding(.leading, 10)
                }
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1))
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Resting")
            small("+30") { model.addRest(30) }
            small(nil, icon: "forward.end.fill") { model.stopRest() }
                .accessibilityLabel("Skip rest")
        }
        .frame(height: WatchScreen.isSmall ? 38 : 40)
    }

    private func clock(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

    private func small(_ text: String?, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let text { Text(text).font(.system(size: 13, weight: .bold)) }
                else if let icon { Image(systemName: icon).font(.system(size: 13, weight: .bold)) }
            }
            .foregroundStyle(Theme.text)
            .frame(width: WatchScreen.isSmall ? 38 : 40, height: WatchScreen.isSmall ? 38 : 40)
            .background(Theme.raised, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - How it felt

/// One tap after ✓. Saved as RPE with the set; no answer in a few seconds counts as Good.
struct WatchEffortPage: View {
    let model: WatchWorkout
    @State private var countdown = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let set = model.pending {
                HStack(alignment: .firstTextBaseline) {
                    Text(set.isTest ? "Test: how was it?" : "How was it?")
                        .font(.system(size: 15, weight: .bold))
                    Spacer(minLength: 4)
                    Text(header(set)).font(Theme.mono(12)).foregroundStyle(Theme.muted)
                }
                .lineLimit(1).minimumScaleFactor(0.7)
            }
            ForEach(Effort.allCases) { effort in
                Button { model.rate(effort) } label: { row(effort) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
        .frame(maxHeight: .infinity)
        .onAppear { withAnimation(.linear(duration: 4)) { countdown = 1 } }
    }

    private func header(_ set: WatchWorkout.Pending) -> String {
        model.describe(.init(exercise: set.exercise, weight: set.weight, reps: set.reps, date: set.end))
    }

    private func row(_ effort: Effort) -> some View {
        let isDefault = effort == .good
        return HStack(alignment: .firstTextBaseline) {
            Text(effort.label).font(.system(size: 17, weight: .bold))
            Spacer(minLength: 4)
            Text(effort.detail).font(.system(size: 11, weight: .medium))
                .foregroundStyle(isDefault ? Theme.onAccent.opacity(0.85) : Theme.muted)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(isDefault ? Theme.onAccent : Theme.text)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: WatchScreen.isSmall ? 38 : 42, maxHeight: 52)
        .background {
            if isDefault {
                // Fills as the question times out into Good.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Theme.accent
                        Color.white.opacity(0.14).frame(width: geo.size.width * countdown)
                    }
                }
            } else {
                Theme.surface
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel("\(effort.label), \(effort.detail)")
    }
}

// MARK: - Warm-up

/// The warm-up before a lift's first set: drills and lighter sets to tick off (shared with the iPhone).
struct WatchWarmUpPage: View {
    let model: WatchWorkout
    private let tracker = WorkoutTracker.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                if let lift = model.lift {
                    Text("WARM-UP").font(.system(size: 11, weight: .heavy)).tracking(0.5).foregroundStyle(Theme.accentText)
                    Text(lift.exercise.name).font(.system(size: 16, weight: .bold))
                        .lineLimit(2).minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
                    if let until = model.restUntil { WatchRestBar(model: model, until: until) }
                    ForEach(Array(model.warmUpSteps.enumerated()), id: \.offset) { i, step in
                        row(lift.exercise.name, i, step)
                    }
                    Button("Start lift") {
                        for i in model.warmUpSteps.indices where !model.isWarmUpDone(lift.exercise.name, i) {
                            tracker.setWarmUp(WorkoutTracker.warmUpKey(lift.exercise.name, i), done: true)
                        }
                        model.stopRest()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 2)
                }
            }
        }
    }

    private func row(_ exercise: String, _ i: Int, _ step: WarmUps.Step) -> some View {
        let done = model.isWarmUpDone(exercise, i)
        return Button {
            tracker.setWarmUp(WorkoutTracker.warmUpKey(exercise, i), done: !done)
            guard !done else { return }
            WKInterfaceDevice.current().play(.click)
            // A lighter set gets a short rest before the next step.
            if case .ramp(let r) = step { model.startRest(TimeInterval(r.rest)) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20)).foregroundStyle(done ? Theme.accent : Theme.muted)
                VStack(alignment: .leading, spacing: 0) {
                    switch step {
                    case .drill(let d):
                        Text(d.name).font(.system(size: 14, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.8)
                        Text(d.reps).font(.system(size: 11)).foregroundStyle(Theme.muted)
                    case .ramp(let r):
                        Text("\(model.unit.format(pounds: r.weight)) × \(r.reps)").font(Theme.mono(15, .bold)).monospacedDigit()
                        Text("Lighter set · rest \(Dose.label(r.rest))").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                }
                .foregroundStyle(done ? Theme.muted : Theme.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Before the first lift, after the last

/// Your own workout before its first lift.
struct WatchEmptyPage: View {
    @Binding var adding: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR WORKOUT").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.accentText)
            Text("Add lifts as you go. Weights come from your history.")
                .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Add exercise", systemImage: "plus") { adding = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// Every lift has its sets. The workout only ends when you say so.
struct WatchAllDonePage: View {
    let model: WatchWorkout
    @Binding var adding: Bool

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.accent)
                Text("ALL DONE").font(Theme.display(19))
            }
            Text("\(model.setsDone) sets · \(model.plan.exercises.count) lifts")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
            Spacer(minLength: 4)
            Button { Task { await model.finish() } } label: {
                Text("End workout").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            Button { adding = true } label: {
                Label("Add exercise", systemImage: "plus").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - The workout list

/// Every lift with its sets so far. Tap one to do it next.
struct WatchListPage: View {
    let model: WatchWorkout
    @Binding var adding: Bool
    let onPick: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(model.plan.focus.uppercased()) · \(model.progress.setsDone) OF \(model.progress.setsPlanned)")
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
                ForEach(Array(model.progress.lifts.enumerated()), id: \.offset) { i, lift in
                    Button { onPick(i) } label: { row(lift, current: i == model.index && !model.isAllDone) }
                        .buttonStyle(.plain)
                }
                Button("Add exercise", systemImage: "plus") { adding = true }
                    .padding(.top, 2)
            }
        }
    }

    private func row(_ lift: WorkoutProgress.Lift, current: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: lift.isDone ? "checkmark.circle.fill" : current ? "smallcircle.filled.circle" : "circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(lift.isDone || current ? Theme.accentText : Theme.muted)
                Text(lift.exercise.name).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(lift.isDone ? Theme.muted : Theme.text)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(count(lift)).font(Theme.mono(12)).foregroundStyle(lift.isDone ? Theme.accentText : Theme.muted)
            }
            if !lift.all.isEmpty {
                Text(sets(lift)).font(.system(size: 11)).foregroundStyle(Theme.muted)
                    .lineLimit(2).padding(.leading, 16)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(current ? Theme.accentWash : Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(current ? Theme.accent.opacity(0.7) : .clear, lineWidth: 1))
    }

    /// "2/3", or "3/3+1" with an extra set: never more than the plan before the plus.
    private func count(_ lift: WorkoutProgress.Lift) -> String {
        let extra = lift.working.count - lift.planned
        return "\(min(lift.working.count, lift.planned))/\(lift.planned)" + (extra > 0 ? "+\(extra)" : "")
    }

    /// "Test 45×5, 65×5 · 115×6, 115×6"
    private func sets(_ lift: WorkoutProgress.Lift) -> String {
        let tests = lift.tests.isEmpty ? nil : "Test " + lift.tests.map(model.describe).joined(separator: ", ")
        let working = lift.working.isEmpty ? nil : lift.working.map(model.describe).joined(separator: ", ")
        return [tests, working].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Controls

/// The workout's numbers and what you can do to it.
struct WatchControlsPage: View {
    let model: WatchWorkout
    @Binding var adding: Bool
    @State private var confirmEnd = false

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                HStack(spacing: 14) {
                    stat("\(Int(model.calories))", "KCAL")
                    stat("\(model.setsDone)/\(model.progress.setsPlanned)", "SETS")
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 2)
                Button("End workout", systemImage: "xmark") { confirmEnd = true }
                    .tint(.red)
                if model.canSkip, let lift = model.lift {
                    Button { model.skipLift() } label: {
                        Label("Skip \(lift.exercise.name)", systemImage: "forward.fill")
                            .lineLimit(2).minimumScaleFactor(0.8)
                    }
                }
                Button("Add exercise", systemImage: "plus") { adding = true }
            }
        }
        .confirmationDialog("End workout?", isPresented: $confirmEnd) {
            Button("End and save") { Task { await model.finish() } }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text(model.isAllDone ? "Every lift is done." : "\(model.setsDone) of \(model.progress.setsPlanned) sets done.")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(Theme.mono(20, .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.muted)
        }
    }
}

// MARK: - Summary

/// The end screen: the headline numbers, then each lift's sets.
struct WatchSummaryView: View {
    let model: WatchWorkout
    let summary: WatchWorkout.Summary
    let onDone: () -> Void

    var body: some View {
        let unit = model.unit
        let volume = summary.sets.reduce(0) { $0 + $1.weight * Double($1.reps) }
        let progress = WorkoutProgress(plan: model.plan, sets: summary.sets)
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    Text("WORKOUT SAVED").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.muted)
                }
                Text(model.plan.focus.uppercased()).font(Theme.display(20))
                    .lineLimit(2).minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    stat(duration(summary.end.timeIntervalSince(summary.start)), "TIME")
                    stat("\(progress.setsDone)", "SETS")
                    if volume > 0 {
                        stat(unit.fromPounds(volume).formatted(.number.notation(.compactName).precision(.fractionLength(0...1))),
                             "\(unit.label) LIFTED")
                    }
                    if summary.averageHeartRate > 0 { stat("\(Int(summary.averageHeartRate))", "AVG BPM") }
                    if summary.calories > 0 { stat("\(Int(summary.calories))", "KCAL") }
                    if summary.maxHeartRate > 0 { stat("\(Int(summary.maxHeartRate))", "MAX BPM") }
                }
                ForEach(Array(progress.lifts.enumerated()).filter { !$0.element.all.isEmpty }, id: \.offset) { _, lift in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(lift.exercise.name).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        Text(lift.all.map(model.describe).joined(separator: ", "))
                            .font(.system(size: 11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
    }

    /// "48m", "1h 05m".
    private func duration(_ seconds: TimeInterval) -> String {
        let m = Int(max(0, seconds) / 60)
        return m < 60 ? "\(m)m" : String(format: "%dh %02dm", m / 60, m % 60)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Theme.mono(18, .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.muted)
        }
    }
}
