import Foundation
import Observation
import SwiftData

/// App-level coach state: picks an engine, builds context from SwiftData + Health,
/// and keeps today's plan plus the rest of the week.
@MainActor
@Observable
final class CoachStore {
    let engine: any CoachEngine
    private(set) var plan: PlannedWorkout? {
        didSet { if plan != oldValue { PhoneWatchLink.shared.send(plan: plan) } }
    }
    private(set) var isThinking = false
    /// The coach's reply so far, while it's being written.
    private(set) var streamingReply: String?
    /// The reply is in; the plan it asked for is being rebuilt.
    private(set) var isReplanning = false
    private(set) var isPlanningWeek = false
    private(set) var readiness: [MuscleGroup: Double] = [:]
    private(set) var health = HealthSnapshot()
    var errorText: String?
    /// The workout most recently finished, so an open workout screen can show its summary
    /// even when the Watch ended it.
    private(set) var lastFinished: WorkoutSession?
    /// Session-length overrides from chat, keyed by DayKey ("only 30 min today", "make Saturday shorter").
    private var minutesOverrides: [String: Int] = [:]
    /// Set when week planning is requested while a pass is already running (true = clear future plans first).
    private var pendingWeekPass: Bool?

    init() {
        if AppleIntelligenceCoach.isAvailable {
            engine = AppleIntelligenceCoach()
        } else {
            engine = RuleBasedCoach()
        }
    }

    var aiUnavailableReason: String? { AppleIntelligenceCoach.unavailableReason }

    // MARK: Context

    /// - Parameter assumed: planned-but-not-done workouts before `date`, so later days account for them.
    func makeContext(_ ctx: ModelContext, date: Date = .now, assumed: [PlannedWorkout] = []) -> CoachContext {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let sessions = (try? ctx.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date >= weekAgo }, sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        let summaries = sessions.map(Readiness.summarize) + assumed.map(Readiness.summarize)
        let notes = ((try? ctx.fetch(FetchDescriptor<CoachNote>())) ?? [])
            .map { NoteSnapshot(said: $0.said, rule: $0.rule, avoid: Set($0.avoid), exercises: Set($0.exercises)).checked() }
        let gym = DataStore.activeGym(in: ctx)
        let weekday = Calendar.current.component(.weekday, from: date)
        let ready = Readiness.compute(from: summaries.sorted { $0.date > $1.date }, now: date)
        let isToday = Calendar.current.isDateInToday(date)
        if isToday { readiness = ready }

        // Feedback: how the last few finished sessions felt, and how hard the last one was.
        let finished = (try? ctx.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.endDate != nil }, sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        let feel = finished.prefix(3).compactMap(\.feel)
        let lastRPEs = finished.first?.orderedSets.compactMap(\.rpe) ?? []
        let avgRPE = lastRPEs.isEmpty ? nil : Double(lastRPEs.reduce(0, +)) / Double(lastRPEs.count)

        var context = CoachContext(date: date,
                                   isTrainingDay: SyncedSettings.trainingWeekdays.contains(weekday),
                                   trainingDaysThisWeek: SyncedSettings.trainingWeekdays.count,
                                   split: SyncedSettings.split,
                                   goal: SyncedSettings.goal,
                                   minutes: minutesOverrides[DayKey.of(date)] ?? SyncedSettings.minutes,
                                   gymName: gym?.name ?? "Gym",
                                   equipment: gym?.equipment ?? Set(Equipment.allCases),
                                   notes: notes,
                                   recent: summaries.sorted { $0.date > $1.date },
                                   readiness: ready,
                                   health: isToday ? health : HealthSnapshot(),
                                   currentPlan: plan)
        context.history = allHistory(ctx)
        context.recentFeel = feel
        context.recentAvgRPE = avgRPE
        context.experience = SyncedSettings.experience
        context.unit = SyncedSettings.unit
        context.warmUps = SyncedSettings.warmUps
        return context
    }

    private func allHistory(_ ctx: ModelContext) -> [String: [SetRecord]] {
        let since = Calendar.current.date(byAdding: .day, value: -60, to: .now)!
        let sets = (try? ctx.fetch(FetchDescriptor<SetEntry>(predicate: #Predicate { $0.date >= since }))) ?? []
        var byName: [String: [SetRecord]] = [:]
        for set in sets {
            byName[set.exercise, default: []].append(SetRecord(date: set.date, weight: set.weight, reps: set.reps, rpe: set.rpe))
        }
        return byName
    }

    // MARK: Plans

    /// Uses the synced plan for today if another device already built one, unless `force`.
    func loadToday(_ ctx: ModelContext, force: Bool = false) async {
        DataStore.refreshCustomExercises(in: ctx)
        var force = force
        if repairNotes(ctx) {
            // Plans built from the bad notes rule out the wrong things: build them again.
            DataStore.clearFuturePlans(in: ctx)
            force = true
        }
        addWarmUps(ctx)
        if !force, let synced = DataStore.todayPlan(in: ctx)?.plan {
            plan = synced
            _ = makeContext(ctx)   // refresh readiness for the UI
        } else {
            isThinking = true
            health = await HealthService.snapshot()
            plan = await build(makeContext(ctx))
            if let plan { DataStore.save(plan, in: ctx) }
            isThinking = false
        }
        await planWeek(ctx)
    }

    /// Plans saved before warm-ups existed get them added, without rebuilding the lifts.
    private func addWarmUps(_ ctx: ModelContext) {
        for var saved in DataStore.upcomingPlans(in: ctx)
        where !saved.isRestDay && saved.warmUp.isEmpty && saved.coolDown.isEmpty {
            let context = makeContext(ctx, date: saved.date)
            saved.warmUp = WarmUps.warmUp(for: saved.exercises, context: context)
            saved.coolDown = WarmUps.coolDown(for: saved.muscles, context: context)
            DataStore.save(saved, in: ctx)
        }
    }

    /// Re-checks saved notes (movement types the athlete's words don't support, exercises not
    /// yet named). True if any changed.
    private func repairNotes(_ ctx: ModelContext) -> Bool {
        var changed = false
        for note in (try? ctx.fetch(FetchDescriptor<CoachNote>())) ?? [] {
            let checked = NoteSnapshot(said: note.said, rule: note.rule, avoid: Set(note.avoid),
                                       exercises: Set(note.exercises)).checked()
            let avoid = checked.avoid.map(\.rawValue).sorted()
            let exercises = checked.exercises.sorted()
            if avoid != note.avoidRaw.sorted() || exercises != note.exercises.sorted() {
                note.avoidRaw = avoid
                note.exercises = exercises
                changed = true
            }
        }
        if changed { try? ctx.save() }
        return changed
    }

    /// Plans every upcoming training day this week that doesn't have a plan yet.
    func planWeek(_ ctx: ModelContext, force: Bool = false) async {
        // A pass is in flight (the model can take a while per day): queue another so later
        // settings/notes changes aren't dropped or overwritten by plans built from stale settings.
        guard !isPlanningWeek else { pendingWeekPass = (pendingWeekPass ?? false) || force; return }
        isPlanningWeek = true
        defer { isPlanningWeek = false }
        var clearFirst = force
        while true {
            if clearFirst { DataStore.clearFuturePlans(in: ctx) }
            await planWeekPass(ctx)
            guard let again = pendingWeekPass else { break }
            pendingWeekPass = nil
            clearFirst = again
        }
    }

    private func planWeekPass(_ ctx: ModelContext) async {
        let existing = Dictionary(DataStore.upcomingPlans(in: ctx).map { (DayKey.of($0.date), $0) },
                                  uniquingKeysWith: { a, _ in a })
        var assumed: [PlannedWorkout] = plan.map { [$0] } ?? []
        let cal = Calendar.current
        for offset in 1...6 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: .now)) else { continue }
            guard SyncedSettings.trainingWeekdays.contains(cal.component(.weekday, from: day)) else { continue }
            if let already = existing[DayKey.of(day)] {
                assumed.append(already)
                continue
            }
            let built = await build(makeContext(ctx, date: day, assumed: assumed))
            if let built {
                DataStore.save(built, in: ctx)
                assumed.append(built)
            }
        }
    }

    /// Rebuilds one specific day (today or later).
    func replan(day: Date, _ ctx: ModelContext) async -> PlannedWorkout? {
        if Calendar.current.isDateInToday(day) {
            await loadToday(ctx, force: true)
            return plan
        }
        isThinking = true
        defer { isThinking = false }
        let earlier = DataStore.upcomingPlans(in: ctx).filter { $0.date < Calendar.current.startOfDay(for: day) }
        guard let built = await build(makeContext(ctx, date: day, assumed: earlier)) else { return nil }
        DataStore.save(built, in: ctx)
        return built
    }

    // MARK: Moving days around (calendar)

    /// Moves a planned workout to another day this week. If that day has a workout, the two swap;
    /// otherwise the day it left becomes a rest day (so week planning doesn't refill it).
    func move(from: Date, to: Date, _ ctx: ModelContext) {
        guard var moving = DataStore.todayPlan(in: ctx, date: from)?.plan, !moving.isRestDay else { return }
        let displaced = DataStore.todayPlan(in: ctx, date: to)?.plan
        moving.date = Calendar.current.startOfDay(for: to)
        DataStore.save(moving, in: ctx)
        if var other = displaced, !other.isRestDay {
            other.date = Calendar.current.startOfDay(for: from)
            DataStore.save(other, in: ctx)
        } else {
            DataStore.save(.rest(on: from, gymName: moving.gymName, engine: moving.engine), in: ctx)
        }
        refreshToday(ctx)
    }

    /// Takes a day off this week only; your training days stay as they are.
    func makeRestDay(_ day: Date, _ ctx: ModelContext) {
        let gym = DataStore.activeGym(in: ctx)?.name ?? "Gym"
        DataStore.save(.rest(on: day, gymName: gym, engine: engine.displayName), in: ctx)
        refreshToday(ctx)
    }

    /// Builds a workout for a day that isn't one of your training days (this week only).
    func train(on day: Date, _ ctx: ModelContext) async {
        isThinking = true
        defer { isThinking = false }
        let earlier = DataStore.upcomingPlans(in: ctx).filter { $0.date < Calendar.current.startOfDay(for: day) }
        var context = makeContext(ctx, date: day, assumed: earlier)
        context.isTrainingDay = true
        guard let built = await build(context) else { return }
        DataStore.save(built, in: ctx)
        refreshToday(ctx)
    }

    private func refreshToday(_ ctx: ModelContext) {
        if let today = DataStore.todayPlan(in: ctx)?.plan { plan = today }
    }

    /// Notes, gym or schedule changed: rebuild today and the rest of the week.
    func invalidate(_ ctx: ModelContext) async {
        DataStore.clearFuturePlans(in: ctx)
        // Plans an in-flight week pass is still building use the old settings: clear and redo them.
        if isPlanningWeek { pendingWeekPass = true }
        await loadToday(ctx, force: true)
    }

    private func build(_ context: CoachContext) async -> PlannedWorkout? {
        do {
            return try await engine.plan(for: context)
        } catch {
            // Model errors (guardrails, context size, not ready) fall back to the rule-based coach.
            errorText = "Coach fell back to built-in rules: \(error.localizedDescription)"
            return try? await RuleBasedCoach().plan(for: context)
        }
    }

    /// Mid-workout edits (swap / add / skip) become today's plan, so the Watch sees them too.
    func replaceTodayExercises(_ exercises: [PlannedExercise], _ ctx: ModelContext) {
        guard var updated = plan else { return }
        updated.exercises = exercises
        plan = updated
        DataStore.save(updated, in: ctx)
    }

    /// Weight + reps to aim for on one exercise (used when swapping or adding mid-workout).
    func target(for name: String, _ ctx: ModelContext) -> LoadTarget? {
        guard let ex = ExerciseCatalog.named(name) else { return nil }
        let context = makeContext(ctx)
        return Progression.target(for: ex, history: DataStore.history(of: ex.name, in: ctx),
                                  signal: context.signal, unit: context.unit)
    }

    // MARK: Chat (saved in SwiftData as ChatEntry, so it syncs and survives relaunch)

    func send(_ text: String, _ ctx: ModelContext) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ctx.insert(ChatEntry(fromUser: true, text: trimmed))
        try? ctx.save()
        isThinking = true
        streamingReply = nil

        let context = makeContext(ctx)
        let reply: CoachReply
        do {
            reply = try await engine.reply(to: trimmed, context: context) { [weak self] text in
                self?.streamingReply = text
            }
        } catch {
            reply = (try? await RuleBasedCoach().reply(to: trimmed, context: context))
                ?? CoachReply(message: "Sorry, I couldn't process that.", note: nil, shouldReplan: false, minutesOverride: nil)
        }
        // Nothing streamed (built-in coach, or the model failed): type the reply out so it reads the same way.
        if streamingReply == nil { await typeOut(reply.message) }

        // Show the reply now; a replan can take a while and attaches to it when done.
        let entry = ChatEntry(fromUser: false, text: reply.message)
        if let note = reply.note {
            let note = note.checked()
            ctx.insert(CoachNote(said: note.said, rule: note.rule, avoid: Array(note.avoid), exercises: note.exercises.sorted()))
            entry.savedNote = note.rule
        }
        ctx.insert(entry)
        try? ctx.save()
        streamingReply = nil
        isThinking = false

        let day = reply.targetDate ?? .now
        if let minutes = reply.minutesOverride { minutesOverrides[DayKey.of(day)] = minutes }
        isReplanning = true
        defer { isReplanning = false }
        if reply.note != nil && reply.targetDate == nil {
            // A lasting note changes every upcoming plan.
            await invalidate(ctx)
            entry.replannedDayKey = DayKey.of(.now)
        } else if reply.shouldReplan || reply.targetDate != nil || reply.minutesOverride != nil {
            if let rebuilt = await replan(day: day, ctx) { entry.replannedDayKey = DayKey.of(rebuilt.date) }
        }
        try? ctx.save()
    }

    /// Reveals a finished reply a few words at a time, like a streamed one.
    private func typeOut(_ text: String) async {
        var shown = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            shown += shown.isEmpty ? String(word) : " " + word
            streamingReply = shown
            try? await Task.sleep(for: .milliseconds(28))
        }
    }

    func clearChat(_ ctx: ModelContext) {
        for row in (try? ctx.fetch(FetchDescriptor<ChatEntry>())) ?? [] { ctx.delete(row) }
        try? ctx.save()
    }

    // MARK: Finishing

    /// Ends the Health workout, copies its stats onto the session, and clears the open session.
    func finishWorkout(_ ctx: ModelContext) async -> WorkoutSession? {
        let result = await WorkoutTracker.shared.finish()
        let session = SetLogger.openSession(focus: plan?.focus ?? "Workout", gymName: plan?.gymName ?? "", in: ctx)
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
        minutesOverrides[DayKey.of(.now)] = nil
        RestAlerts.cancel()
        if SyncedSettings.crewBeta { Task { await CrewService.shared.postCheckIns(from: ctx) } }
        lastFinished = session
        return session
    }
}
