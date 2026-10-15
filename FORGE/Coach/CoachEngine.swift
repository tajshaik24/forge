import Foundation

// MARK: - What every coach engine gets

struct HealthSnapshot: Codable, Sendable, Hashable {
    var sleepHours: Double?
    var hrv: Double?
    var hrvBaseline: Double?

    var isUnderRecovered: Bool {
        if let s = sleepHours, s < 6.5 { return true }
        if let h = hrv, let b = hrvBaseline, b > 0, h < b * 0.9 { return true }
        return false
    }
}

struct SessionSummary: Sendable, Hashable {
    let date: Date
    let focus: String
    let setsByMuscle: [MuscleGroup: Double]
}

struct NoteSnapshot: Sendable, Hashable {
    let said: String
    let rule: String
    let avoid: Set<MovementFlag>
    /// Specific exercises the note rules out; easier versions take their place.
    var exercises: Set<String> = []

    /// Keeps only what the athlete's words support, so one bad model call can't rule out
    /// half the catalog. Also repairs notes saved before exercises were tracked.
    func checked() -> NoteSnapshot {
        let named = exercises.isEmpty ? Set(ExerciseCatalog.limited(in: said)) : exercises
        return NoteSnapshot(said: said, rule: rule, avoid: MovementFlag.supported(avoid, by: said), exercises: named)
    }
}

struct CoachContext: Sendable {
    var date: Date
    var isTrainingDay: Bool
    var trainingDaysThisWeek: Int
    var split: SplitStyle
    var goal: String
    var minutes: Int
    var gymName: String
    var equipment: Set<Equipment>
    var notes: [NoteSnapshot]
    var recent: [SessionSummary]
    var readiness: [MuscleGroup: Double]
    var health: HealthSnapshot
    /// The plan currently shown, so chat can reason about "today's workout".
    var currentPlan: PlannedWorkout?
    /// Logged sets per exercise name (last ~60 days), for progressive overload.
    var history: [String: [SetRecord]] = [:]
    /// "easy" / "right" / "hard" from the most recent finished sessions, newest first.
    var recentFeel: [String] = []
    /// Average RPE across the most recent session's sets.
    var recentAvgRPE: Double?
    var experience: Experience = .intermediate
    var unit: WeightUnit = .lb
    /// Plans open with a warm-up, which takes a few minutes out of the lifting time.
    var warmUps = true

    var isToday: Bool { Calendar.current.isDateInToday(date) }

    var trainingGoal: TrainingGoal { TrainingGoal(rawValue: goal) ?? .buildMuscle }

    /// Session-level feedback that nudges load and volume.
    var signal: Progression.Signal {
        if (isToday && health.isUnderRecovered) || recentFeel.first == "hard" || (recentAvgRPE ?? 0) >= 9.3 {
            return .holdBack
        }
        if recentFeel.prefix(2).count == 2 && recentFeel.prefix(2).allSatisfy({ $0 == "easy" }) { return .pushOn }
        if recentFeel.first == "easy" && (recentAvgRPE ?? 8) <= 7.5 { return .pushOn }
        return .normal
    }

    /// Plain-language version of `signal` for prompts and "why today".
    var feedbackSummary: String? {
        switch signal {
        case .holdBack:
            if recentFeel.first == "hard" { return "Last session felt too hard, so load and volume are eased." }
            if (recentAvgRPE ?? 0) >= 9.3 { return "Last session was near max effort (RPE \(String(format: "%.1f", recentAvgRPE ?? 0))), so this one is eased." }
            return "Recovery is below your baseline, so volume is trimmed."
        case .pushOn: return "Recent sessions felt easy, so you'll push a little harder."
        case .normal: return nil
        }
    }

    var avoid: Set<MovementFlag> { notes.reduce(into: []) { $0.formUnion($1.avoid) } }
    var limitedExercises: Set<String> { notes.reduce(into: []) { $0.formUnion($1.exercises) } }
    /// Strength exercises allowed here: the gym has the kit, no note rules them out, and they're
    /// at most one level above the athlete (no front squats in week one).
    var pool: [Exercise] {
        ExerciseCatalog.available(gym: equipment, avoiding: avoid, excluding: limitedExercises)
            .filter { $0.level.rank <= experience.rank + 1 }
    }

    func readiness(of template: FocusTemplate) -> Double {
        let values = template.muscles.map { readiness[$0] ?? 1 }
        return values.reduce(0, +) / Double(max(values.count, 1))
    }

    /// Templates allowed by the split, best-recovered first. For fixed splits, rotate after the last focus.
    var rankedTemplates: [FocusTemplate] {
        let allowed = split.templates
        if split != .coachDecides, allowed.count > 1,
           let last = recent.first?.focus,
           let i = allowed.firstIndex(where: { $0.name == last }) {
            let next = allowed[(i + 1) % allowed.count]
            return [next] + allowed.filter { $0 != next }
        }
        return allowed.sorted { readiness(of: $0) > readiness(of: $1) }
    }
}

struct CoachReply: Sendable {
    var message: String
    var note: NoteSnapshot?
    var shouldReplan: Bool
    var minutesOverride: Int?
    /// The day a change applies to (nil = today).
    var targetDate: Date? = nil
}

enum DayMatcher {
    /// Finds "tomorrow" or a weekday name in text and returns the next such date (today excluded).
    static func date(in text: String, from now: Date = .now) -> Date? {
        let lower = text.lowercased()
        let cal = Calendar.current
        if lower.contains("tomorrow") { return cal.date(byAdding: .day, value: 1, to: now) }
        for (i, name) in cal.weekdaySymbols.enumerated() where lower.contains(name.lowercased()) {
            return next(weekday: i + 1, from: now)
        }
        return nil
    }

    static func next(weekday: Int, from now: Date = .now) -> Date? {
        let cal = Calendar.current
        for offset in 1...7 {
            if let d = cal.date(byAdding: .day, value: offset, to: now), cal.component(.weekday, from: d) == weekday {
                return cal.startOfDay(for: d)
            }
        }
        return nil
    }
}

protocol CoachEngine: Sendable {
    var displayName: String { get }
    func plan(for context: CoachContext) async throws -> PlannedWorkout
    /// `onText` receives the reply text so far while it's being generated (engines that can't stream never call it).
    func reply(to message: String, context: CoachContext,
               onText: @escaping @MainActor @Sendable (String) -> Void) async throws -> CoachReply
}

extension CoachEngine {
    func reply(to message: String, context: CoachContext) async throws -> CoachReply {
        try await reply(to: message, context: context, onText: { _ in })
    }
}

// MARK: - Readiness from logged sets

enum Readiness {
    /// 1.0 = fully recovered. Each muscle takes ~72 h to recover from ~12 hard sets.
    static func compute(from sessions: [SessionSummary], now: Date = .now) -> [MuscleGroup: Double] {
        var fatigue: [MuscleGroup: Double] = [:]
        for s in sessions {
            let hours = now.timeIntervalSince(s.date) / 3600
            let remaining = max(0, 1 - hours / 72)
            for (muscle, sets) in s.setsByMuscle {
                fatigue[muscle, default: 0] += (sets / 12) * remaining
            }
        }
        var result: [MuscleGroup: Double] = [:]
        for m in MuscleGroup.allCases { result[m] = max(0, min(1, 1 - (fatigue[m] ?? 0))) }
        return result
    }

    static func summarize(_ session: WorkoutSession) -> SessionSummary {
        var counts: [MuscleGroup: Double] = [:]
        for set in session.sets ?? [] {
            guard let ex = ExerciseCatalog.named(set.exercise), ex.kind == .strength else { continue }
            counts[ex.primary, default: 0] += 1
            for m in ex.secondary { counts[m, default: 0] += 0.5 }
        }
        return SessionSummary(date: session.date, focus: session.focus, setsByMuscle: counts)
    }

    /// A planned (not yet done) workout, so later days in the week account for it.
    static func summarize(_ plan: PlannedWorkout) -> SessionSummary {
        var counts: [MuscleGroup: Double] = [:]
        for e in plan.exercises {
            guard let ex = ExerciseCatalog.named(e.name), ex.kind == .strength else { continue }
            counts[ex.primary, default: 0] += Double(e.sets)
            for m in ex.secondary { counts[m, default: 0] += Double(e.sets) / 2 }
        }
        return SessionSummary(date: plan.date, focus: plan.focus, setsByMuscle: counts)
    }
}

// MARK: - Shared post-processing: every engine's output passes through here

enum PlanFinisher {
    /// Fixes up a draft so it is always valid: only doable exercises, sensible size,
    /// recovery-based volume trim, and "replaces X" labels.
    static func finish(focus: String, muscles: [MuscleGroup], reasons: [String],
                       exercises: [PlannedExercise], context: CoachContext, engine: String) -> PlannedWorkout {
        let pool = context.pool
        let poolNames = Set(pool.map(\.name))
        var picked: [PlannedExercise] = []
        for var e in exercises {
            guard let canonical = ExerciseCatalog.named(e.name), poolNames.contains(canonical.name),
                  !picked.contains(where: { $0.name == canonical.name }) else { continue }
            e.name = canonical.name
            e.sets = min(max(e.sets, context.experience.setRange.lowerBound), context.experience.setRange.upperBound)
            if e.reps.isEmpty { e.reps = canonical.reps }
            if e.cue?.isEmpty == true { e.cue = nil }
            picked.append(e)
        }

        // Top up from the pool if the draft came back thin. About 8 minutes per exercise,
        // after the warm-up has taken its share.
        let liftingMinutes = context.minutes - (context.warmUps ? 6 : 0)
        let target = max(4, min(7, liftingMinutes / 8))
        for m in muscles where picked.count < target {
            if let extra = pool.first(where: { $0.primary == m && !picked.map(\.name).contains($0.name) }) {
                picked.append(PlannedExercise(name: extra.name, sets: min(3, context.experience.setRange.upperBound), reps: extra.reps))
            }
        }
        picked = Array(picked.prefix(target))
        picked.sort { (ExerciseCatalog.named($0.name)?.isCompound ?? false) && !(ExerciseCatalog.named($1.name)?.isCompound ?? false) }

        // A cue copied onto several exercises is boilerplate (e.g. a note restated), not coaching.
        let cueCounts = Dictionary(picked.compactMap(\.cue).map { ($0, 1) }, uniquingKeysWith: +)
        for i in picked.indices where (cueCounts[picked[i].cue ?? ""] ?? 0) >= 3 { picked[i].cue = nil }

        // An easier version standing in for a lift a note ruled out: "Band-assisted pull-up · replaces Pull-up".
        var labelled = Set<MuscleGroup>()
        for i in picked.indices {
            guard let harder = ExerciseCatalog.harderVersion(of: picked[i].name),
                  context.limitedExercises.contains(harder),
                  let ex = ExerciseCatalog.named(picked[i].name), !labelled.contains(ex.primary) else { continue }
            picked[i].replaces = harder
            labelled.insert(ex.primary)
        }

        // Label swaps for the muscles where a staple was ruled out.
        for i in picked.indices {
            guard let ex = ExerciseCatalog.named(picked[i].name), ex.isCompound, !labelled.contains(ex.primary),
                  let blocked = ExerciseCatalog.blockedStaple(for: ex.primary, gym: context.equipment, avoiding: context.avoid)
            else { continue }
            picked[i].replaces = blocked.name
            labelled.insert(ex.primary)
        }

        // Feedback: how recent sessions felt, effort (RPE) and recovery.
        var why = reasons
        let minSets = context.experience.setRange.lowerBound
        let maxSets = context.experience.setRange.upperBound
        switch context.signal {
        case .holdBack:
            for i in picked.indices where picked[i].sets > minSets && i % 2 == 1 { picked[i].sets -= 1 }
        case .pushOn:
            if let i = picked.indices.first(where: { picked[$0].sets < maxSets }) { picked[i].sets += 1 }
        case .normal:
            break
        }
        if let summary = context.feedbackSummary { why.insert(summary, at: min(1, why.count)) }

        // The goal sets the rep range; progressive overload sets weight + reps on every lift you've
        // done before. A weighted lift you haven't done gets "find your weight" test sets.
        let goal = context.trainingGoal
        for i in picked.indices {
            guard let ex = ExerciseCatalog.named(picked[i].name) else { continue }
            picked[i].reps = RepScheme.reps(for: ex, goal: goal)
            picked[i].target = Progression.target(for: ex, history: context.history[ex.name] ?? [],
                                                  signal: context.signal, unit: context.unit, goal: goal)
            picked[i].calibrate = picked[i].target == nil && Calibration.applies(to: ex) ? true : nil
        }
        let testing = picked.filter { $0.calibrate == true }.count
        if testing > 0, testing * 2 >= picked.count {
            why.insert("New lifts: test sets find your starting weights.", at: 0)
        }

        let cautious = context.avoid.contains(.standingHeavy) || context.avoid.contains(.axialLoading)
        return PlannedWorkout(date: context.date, focus: focus, muscles: muscles, minutes: context.minutes,
                              reasons: Array(why.prefix(3)), exercises: picked,
                              restSeconds: cautious ? max(150, RepScheme.rest(for: goal)) : RepScheme.rest(for: goal), gymName: context.gymName, engine: engine,
                              warmUp: WarmUps.warmUp(for: picked, context: context),
                              coolDown: WarmUps.coolDown(for: muscles, context: context))
    }

    static func restDay(_ context: CoachContext, engine: String) -> PlannedWorkout {
        PlannedWorkout(date: context.date, focus: "Rest", muscles: [], minutes: 0,
                       reasons: ["Not one of your training days. Walk, stretch, sleep."],
                       exercises: [], restSeconds: 0, gymName: context.gymName, engine: engine)
    }
}

// MARK: - Fallback when Apple Intelligence is off or unsupported

struct RuleBasedCoach: CoachEngine {
    let displayName = "Built-in coach"

    func plan(for context: CoachContext) async throws -> PlannedWorkout {
        guard context.isTrainingDay else { return PlanFinisher.restDay(context, engine: displayName) }
        let template = context.rankedTemplates.first ?? .fullBody
        let pool = context.pool
        var drafts: [PlannedExercise] = []
        for m in template.muscles {
            let options = pool.filter { $0.primary == m }.sorted { $0.isCompound && !$1.isCompound }
            if let first = options.first { drafts.append(PlannedExercise(name: first.name, sets: 3, reps: first.reps)) }
        }
        for m in template.muscles {
            let options = pool.filter { $0.primary == m && !drafts.map(\.name).contains($0.name) }
            if let second = options.first { drafts.append(PlannedExercise(name: second.name, sets: 3, reps: second.reps)) }
        }
        let pct = Int(context.readiness(of: template) * 100)
        let reasons = ["\(template.name) muscles are the most recovered (\(pct)%)."]
        return PlanFinisher.finish(focus: template.name, muscles: template.muscles, reasons: reasons,
                                   exercises: drafts, context: context, engine: displayName)
    }

    func reply(to message: String, context: CoachContext,
               onText: @escaping @MainActor @Sendable (String) -> Void) async throws -> CoachReply {
        CoachReply(message: "Saved that as a note. Turn on the AI Coach to have your plan adapt to it.",
                   note: NoteSnapshot(said: message, rule: message, avoid: [],
                                      exercises: Set(ExerciseCatalog.limited(in: message))),
                   shouldReplan: false, minutesOverride: nil, targetDate: DayMatcher.date(in: message))
    }
}
