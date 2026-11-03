import Foundation
import FoundationModels

// MARK: - Model-facing mirrors of the shared enums
// (Shared code can't import FoundationModels because the Watch target has no Apple Intelligence.)

@Generable
enum GenMuscle: CaseIterable {
    case chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes, calves, core

    var muscle: MuscleGroup {
        switch self {
        case .chest: .chest
        case .back: .back
        case .shoulders: .shoulders
        case .biceps: .biceps
        case .triceps: .triceps
        case .quads: .quads
        case .hamstrings: .hamstrings
        case .glutes: .glutes
        case .calves: .calves
        case .core: .core
        }
    }
    init(_ m: MuscleGroup) { self = Self.allCases.first { $0.muscle == m } ?? .core }
}

@Generable
enum GenMovementFlag: CaseIterable {
    /// Bar on the spine: back squat, front squat, standing barbell press.
    case axialLoading
    /// Heavy standing compound lift (squat, deadlift, standing press).
    case standingHeavy
    /// Pressing or holding weight overhead.
    case overhead
    /// Deep knee bend under load.
    case deepKneeBend
    /// Jumps and plyometrics.
    case jumping
    /// Getting down to and up from the floor.
    case floorTransitions

    var flag: MovementFlag? {
        switch self {
        case .axialLoading: .axialLoading
        case .standingHeavy: .standingHeavy
        case .overhead: .overhead
        case .deepKneeBend: .deepKneeBend
        case .jumping: .jumping
        case .floorTransitions: .floorTransitions
        }
    }
}

@Generable
enum GenTargetDay: CaseIterable {
    case today, tomorrow, monday, tuesday, wednesday, thursday, friday, saturday, sunday

    /// nil = today.
    var date: Date? {
        let cal = Calendar.current
        switch self {
        case .today: return nil
        case .tomorrow: return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now))
        case .sunday: return DayMatcher.next(weekday: 1)
        case .monday: return DayMatcher.next(weekday: 2)
        case .tuesday: return DayMatcher.next(weekday: 3)
        case .wednesday: return DayMatcher.next(weekday: 4)
        case .thursday: return DayMatcher.next(weekday: 5)
        case .friday: return DayMatcher.next(weekday: 6)
        case .saturday: return DayMatcher.next(weekday: 7)
        }
    }
}

// MARK: - Structured outputs the on-device model must fill in

@Generable
struct GeneratedExercise {
    @Guide(description: "Exact exercise name copied from the candidate list")
    var name: String
    @Guide(description: "Working sets", .range(2...5))
    var sets: Int
    @Guide(description: "Rep target, e.g. \"8-10\" or \"12\"")
    var reps: String
    @Guide(description: "Optional short technique or safety cue specific to this exercise. Empty if none. Never the same cue on several exercises.")
    var cue: String
}

@Generable
struct GeneratedDayPlan {
    @Guide(description: "Two or three reasons for this session, each under 14 words, using only the numbers given", .count(2...3))
    var reasons: [String]
    @Guide(description: "Exercises in order, big compound lifts first, copied exactly from the candidates", .count(4...7))
    var exercises: [GeneratedExercise]
}

@Generable
enum GenMessageKind: CaseIterable {
    /// Asking something: answer it, change nothing.
    case question
    /// Can't do something yet, or something hurts or feels wrong.
    case limitation
    /// Wants to work up to a lift or get better at one.
    case goal
    /// Less or more time, or a different day.
    case schedule
    /// A different gym or kit.
    case equipment
    /// How training felt: too easy, too hard, enjoyed it.
    case feedback
    /// Not about training, recovery, nutrition, health or this app: trivia, jokes, code, news, money.
    case offTopic
    /// Anything else, including small talk like thanks or hello.
    case other

    var kind: ChatDecision.Kind {
        switch self {
        case .question: .question
        case .limitation: .limitation
        case .goal: .goal
        case .schedule: .schedule
        case .equipment: .equipment
        case .feedback: .feedback
        case .offTopic: .offTopic
        case .other: .other
        }
    }
}

@Generable
struct GeneratedReply {
    @Guide(description: "Your reply in 1-3 short, practical sentences. Answer exactly what they said or asked, using the facts given.")
    var message: String
    @Guide(description: "What kind of message this is")
    var kind: GenMessageKind
    @Guide(description: "Exercises named in the athlete's message that they can't do, want to avoid, or that hurt. Empty if they named none.")
    var exercises: [String]
    @Guide(description: "Exercises named in the athlete's message that they want to work up to, learn or get better at. Never one that hurts. Empty if they named none.")
    var buildToward: [String]
    @Guide(description: "True only for a lasting limitation or preference in this message that should change future workouts. False for questions, goals, one-off days, time and travel.")
    var shouldRemember: Bool
    @Guide(description: "If remembering: what the athlete said, as a short rule in your own words, about only what they said. Otherwise empty.")
    var rule: String
    @Guide(description: """
        Movement types to rule out across ALL exercises. Usually empty. Only include a type the athlete's words clearly point to: \
        axialLoading = bar resting on the spine (back squat, front squat); standingHeavy = heavy standing lifts (squat, deadlift), \
        for dizziness or balance trouble; overhead = pressing overhead, for shoulder pain; deepKneeBend = deep squats and lunges, \
        for knee pain; jumping = plyometrics; floorTransitions = getting down to and up from the floor. \
        A problem with one exercise goes in exercises, not here.
        """)
    var avoid: [GenMovementFlag]
    @Guide(description: "True only if they asked to skip training or rest on a day")
    var restDay: Bool
    @Guide(description: "Session length in minutes if they gave one or asked for a shorter or longer workout, otherwise 0")
    var minutesToday: Int
    @Guide(description: "Which day the change is about. Use today unless they name another day.")
    var day: GenTargetDay
}

// MARK: - Facts about one exercise, for answering questions about it

enum ExerciseFacts {
    static func facts(about ex: Exercise, _ c: CoachContext) -> String {
        let muscles = ([ex.primary] + ex.secondary).map { $0.label.lowercased() }
        let muscleText = muscles.count > 1 ? muscles.dropLast().joined(separator: ", ") + " and " + muscles.last! : muscles[0]
        var lines = ["\(ex.name): works \(muscleText), \(ex.reps) reps."]
        if !ex.equipment.isSubset(of: c.equipment) {
            lines.append("Not possible at \(c.gymName): needs \(ex.equipment.subtracting(c.equipment).map(\.label).sorted().joined(separator: ", ")).")
        }
        if c.limitedExercises.contains(ex.name) { lines.append("A coach note keeps it out of the plan for now.") }
        let history = c.history[ex.name] ?? []
        if let last = Progression.lastSession(history) {
            let sets = last.map { WorkoutSetText.amount($0, unit: c.unit, timed: ex.isTimed) }.joined(separator: ", ")
            lines.append("Last time: \(sets).")
            if let t = Progression.target(for: ex, history: history, signal: c.signal, unit: c.unit, goal: c.trainingGoal) {
                lines.append("Next target: \(t.weight > 0 ? c.unit.format(pounds: t.weight) + " × " : "")\(t.reps)\(ex.isTimed ? " s" : " reps") (\(t.note)).")
            }
            if ex.equipment.isEmpty == false, let best = Strength.estimatedMax(from: history) {
                lines.append("Estimated one-rep max: \(c.unit.format(pounds: best)).")
            }
        } else {
            lines.append("Never logged. \(Calibration.applies(to: ex) ? "The first session uses light test sets to find a starting weight." : "")")
        }
        if let goal = c.goals.first(where: { $0.target == ex.name || ($0.ladder?.steps.contains { $0.options.contains(ex.name) } ?? false) }),
           let ladder = goal.ladder {
            let steps = ladder.steps.map { $0.options.first ?? "" }
            let now = goal.exercise(gym: c.equipment, avoiding: c.avoid)?.name ?? steps[min(goal.step, steps.count - 1)]
            lines.append("Goal: \(goal.label). Current step: \(now), \(goal.passes) of \(SkillGoal.passesToMoveUp) qualifying sessions done. All steps: \(steps.joined(separator: " → ")).")
        }
        if let easier = ExerciseCatalog.easierVersions[ex.name] { lines.append("Easier versions: \(easier.joined(separator: ", ")).") }
        if let harder = ExerciseCatalog.harderVersion(of: ex.name) { lines.append("Builds toward: \(harder).") }
        let alternatives = c.pool.filter { $0.primary == ex.primary && $0.name != ex.name && $0.kind == .strength }.prefix(4).map(\.name)
        if !alternatives.isEmpty { lines.append("Alternatives here for \(ex.primary.label.lowercased()): \(alternatives.joined(separator: ", ")).") }
        return lines.joined(separator: "\n")
    }
}

/// "135 lb × 8", "BW × 10", "45 s".
enum WorkoutSetText {
    static func amount(_ set: SetRecord, unit: WeightUnit, timed: Bool) -> String {
        if timed { return "\(set.reps) s" }
        return set.weight > 0 ? "\(unit.format(pounds: set.weight)) × \(set.reps)" : "\(set.reps) reps"
    }
}

// MARK: - The engine

/// Runs entirely on the Apple Intelligence on-device model via the Foundation Models framework.
struct AppleIntelligenceCoach: CoachEngine {
    let displayName = "AI Coach"

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "This iPhone can't run the AI Coach, so FORGE is using the built-in coach."
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings to unlock the AI Coach."
        case .unavailable(.modelNotReady): return "The AI Coach is still getting ready on this iPhone."
        case .unavailable: return "The AI Coach isn't available right now."
        }
    }

    private static let planInstructions = """
    You are FORGE, a strength coach. Build today's session from the candidate exercises.
    Rules:
    - Use only candidate names, copied exactly. Cover every muscle listed, big compound lifts first.
    - Respect every coach note. Never work around a note.
    - No more than two exercises of the same movement, e.g. two vertical pulls.
    - Fit the session length, warm-up included: about 8 minutes per exercise.
    - Leave cue empty unless it's specific to that exercise. Don't repeat a note as a cue.
    - Keep reasons short and use only the numbers you were given.
    """

    private static let chatInstructions = """
    You are FORGE, a friendly, concise strength coach inside a workout app, talking with one athlete.
    - You only discuss training, recovery, nutrition, health and this app. For anything else, mark it off topic and say briefly that you can only help with training.
    - Answer questions directly and specifically, using the facts given.
    - Use only weights, reps and rest times that appear in the facts. Never invent numbers.
    - Coach notes are already applied to every plan. Bring one up only if the message is about it.
    - Don't list the whole plan unless they ask for it.
    - Lines starting "App:" say what the app is doing about this message. Confirm them in your own words.
    - Most lifts are safe when learned light with good form. Be encouraging.
    - If they mention pregnancy, a medical condition, dizziness, fainting, chest pain or sharp pain, suggest they check with their doctor. Never say a plan is medically safe.
    - If the app can't do something they ask, say where in the app they can do it, using the facts given.
    """

    func plan(for context: CoachContext) async throws -> PlannedWorkout {
        guard context.isTrainingDay else { return PlanFinisher.restDay(context, engine: displayName) }

        // The rules pick the focus (recovery and split); the model picks lifts from a short list for it.
        // No tool: tool round trips overflow the small context window, and the list is short anyway.
        let template = context.rankedTemplates.first ?? .fullBody
        let session = LanguageModelSession(instructions: Self.planInstructions)
        let response = try await session.respond(to: CoachPrompts.plan(context, template: template), generating: GeneratedDayPlan.self)
        let draft = response.content
        let exercises = draft.exercises.map {
            PlannedExercise(name: $0.name, sets: $0.sets, reps: $0.reps, cue: $0.cue)
        }
        return PlanFinisher.finish(focus: template.name, muscles: template.muscles, reasons: draft.reasons,
                                   exercises: exercises, context: context, engine: displayName)
    }

    private func respond(_ prompt: String, onText: @escaping @MainActor @Sendable (String) -> Void) async throws -> GeneratedReply {
        let session = LanguageModelSession(instructions: Self.chatInstructions)
        // `message` is GeneratedReply's first property, so it streams in before the bookkeeping fields.
        let stream = session.streamResponse(to: prompt, generating: GeneratedReply.self)
        for try await snapshot in stream {
            if let text = snapshot.content.message, !text.isEmpty { await onText(text) }
        }
        return try await stream.collect().content
    }

    func reply(to message: String, context: CoachContext,
               onText: @escaping @MainActor @Sendable (String) -> Void) async throws -> CoachReply {
        // No tools here: facts about the lifts named in the message go straight into the prompt. A tool
        // call costs a round trip, and the safety filter rejects many harmless tool transcripts.
        // The safety filter is inconsistent: if it blocks the full prompt, try once more with only the
        // plan, the app's own lines and the message, before the built-in coach takes over.
        // Plainly off topic: answer without the model, so nothing off topic streams in first.
        if ChatDecision.isOffTopic(message, context: context) { return ChatDecision.offTopicReply() }
        var out: GeneratedReply
        do {
            out = try await respond(CoachPrompts.chat(message, context), onText: onText)
        } catch LanguageModelSession.GenerationError.guardrailViolation {
            out = try await respond(CoachPrompts.chat(message, context, minimal: true), onText: onText)
        }
        return ChatDecision.make(message: message, context: context, reply: out.message,
                                 fields: .init(kind: out.kind.kind, exercises: out.exercises, buildToward: out.buildToward,
                                               remember: out.shouldRemember, rule: out.rule,
                                               avoid: Set(out.avoid.compactMap(\.flag)), restDay: out.restDay,
                                               minutes: out.minutesToday, day: out.day.date))
    }
}

// MARK: - Prompts: compact, because the on-device context window is small

enum CoachPrompts {   // not "PromptBuilder": that name is a FoundationModels result builder
    static func plan(_ c: CoachContext, template: FocusTemplate) -> String {
        var lines: [String] = []
        let day = c.isToday ? "today" : c.date.formatted(.dateTime.weekday(.wide))
        lines.append("Planning \(template.name) for \(day). Goal: \(c.goal) (\(RepScheme.summary(for: c.trainingGoal))). Experience: \(c.experience.promptLabel). Session length: \(c.minutes) min.")
        lines.append("Working sets per exercise: \(c.experience.setRange.lowerBound)-\(c.experience.setRange.upperBound), by experience, goal and recovery.")
        lines.append("Candidates by muscle (readiness, 100 = fully recovered):")
        for m in template.muscles {
            let names = PlanFinisher.candidates(for: m, in: template, context: c).prefix(5).map(\.name)
            guard !names.isEmpty else { continue }
            lines.append("- \(m.label) \(Int((c.readiness[m] ?? 1) * 100)): \(names.joined(separator: ", "))")
        }
        if let feedback = c.feedbackSummary { lines.append("Feedback: \(feedback)") }
        if c.isToday, let s = c.health.sleepHours { lines.append(String(format: "Sleep last night: %.1f h.", s)) }
        if c.isToday, let h = c.health.hrv, let b = c.health.hrvBaseline { lines.append("HRV \(Int(h)) ms vs baseline \(Int(b)) ms.") }
        if !c.notes.isEmpty {
            lines.append("Coach notes to respect:")
            for n in c.notes {
                lines.append(n.exercises.isEmpty ? "- \(n.rule)" : "- Only about \(n.exercises.sorted().joined(separator: ", ")): \(n.rule)")
            }
        }
        for goal in c.goals {
            if let ex = goal.exercise(gym: c.equipment, avoiding: c.avoid),
               let lift = ExerciseCatalog.named(goal.target), template.muscles.contains(lift.primary) {
                lines.append("The app adds \(ex.name) first (\(goal.label)). Don't pick it or \(goal.target).")
            }
        }
        lines.append("Build the session.")
        return lines.joined(separator: "\n")
    }

    /// - Parameter minimal: only the plan, the app's own lines and the message (a retry after the safety filter).
    static func chat(_ message: String, _ c: CoachContext, minimal: Bool = false) -> String {
        var lines: [String] = []
        let lower = message.lowercased()
        let named = Array(ExerciseCatalog.mentioned(in: message).prefix(3))
        // The lifts only when the message is about today's workout, so replies don't recite the plan.
        let switching = !ChatDecision.isQuestion(message) && ChatDecision.gymNow(in: message, gyms: c.gyms).map { !$0.isActive } == true
        let aboutToday = ChatDecision.isAboutToday(message, plan: c.currentPlan) && !switching
        // Small talk gets a short, warm reply, not a briefing.
        let smallTalk = ChatDecision.isSmallTalk(message)
        if smallTalk {
            lines.append("App: this is small talk. Reply warmly in one short sentence. Don't describe the plan or any numbers.")
        }
        if let p = c.currentPlan, !p.isRestDay, !switching, !smallTalk {
            // Only the focus unless the message is about today, so a reply has no session numbers to recite.
            lines.append(aboutToday ? "Today's plan: \(p.focus) at \(p.gymName), about \(p.minutes) min, \(p.restSeconds) s rest between sets. Lifts:"
                                    : "Today is a \(p.focus) day.")
            if aboutToday {
                for e in p.exercises {
                    let reps = e.target.map { "\($0.reps)" } ?? e.reps
                    let weight = e.target.flatMap { $0.weight > 0 ? " at \(c.unit.format(pounds: $0.weight))" : nil } ?? ""
                    lines.append("- \(e.name): \(e.sets) sets of \(reps)\(weight)" + (e.goal.map { " (\($0))" } ?? ""))
                }
                if !p.muscles.isEmpty { lines.append("It trains: \(p.muscles.map { $0.label.lowercased() }.joined(separator: ", ")).") }
                lines.append("Total: \(p.exercises.count) lifts, \(p.totalSets) working sets.")
            }
        } else if let p = c.currentPlan, p.isRestDay {
            lines.append("Today is a rest day.")
        }
        if !smallTalk { lines.append("Athlete: goal \(c.goal.lowercased()), \(c.experience.promptLabel), training \(c.trainingDaysThisWeek) days a week at \(c.gymName).") }
        // Notes only when the message touches them, so they don't creep into unrelated answers.
        let relevantNotes = c.notes.filter { note in
            !note.exercises.isDisjoint(with: named) || ["why", "note", "avoid", "can't", "hurt", "pain", "knee", "back", "shoulder"].contains(where: lower.contains)
        }
        if !relevantNotes.isEmpty, !minimal {
            lines.append("Coach notes, already applied to every plan: " + relevantNotes.map(\.rule).joined(separator: "; ") + ".")
        }
        // Goals only when the message is about them or today's training.
        let aboutGoals = aboutToday || ["goal", "progress", "step", "pull-up", "pull up", "chin", "push-up", "push up", "dip", "how am i doing"]
            .contains(where: lower.contains) || c.goals.contains { lower.contains($0.target.lowercased()) }
        for goal in c.goals where !minimal && aboutGoals {
            lines.append("Goal \(goal.target): \(goal.label), \(goal.passes) of \(SkillGoal.passesToMoveUp) sessions done on this step.")
        }
        // Facts about the lifts they named, so answers use their real numbers and the app's library.
        if !named.isEmpty, !minimal {
            lines.append("Facts about the exercises they mentioned:")
            for name in named { if let ex = ExerciseCatalog.named(name) { lines.append(ExerciseFacts.facts(about: ex, c)) } }
        }
        for move in ExerciseCatalog.notInLibrary(in: message) {
            let closest = ExerciseCatalog.closestTo[move] ?? []
            lines.append("App: \(move) isn't in FORGE's library, so the coach can't program it." + (closest.isEmpty ? "" : " Closest lifts it has: \(closest.joined(separator: ", "))."))
        }
        // What the app does on its own, so the reply agrees with it.
        if !ChatDecision.isQuestion(message), let minutes = ChatDecision.minutes(in: message), minutes != c.minutes {
            lines.append("App: \(ChatDecision.dayName(message))'s session is being rebuilt to fit \(minutes) min.")
        }
        if ChatDecision.isPreference(message) {
            lines.append("App: this preference is saved to the coach's notes, and upcoming plans will follow it.")
        }
        if ChatDecision.asksForRestDay(message) {
            lines.append("App: \(ChatDecision.dayName(message)) is now a rest day.")
        }
        if !ChatDecision.isQuestion(message), let gym = ChatDecision.gymNow(in: message, gyms: c.gyms) {
            let kit = gym.equipment.map(\.label).sorted().joined(separator: ", ")
            lines.append(gym.isActive ? "App: you're already set to \(gym.name)."
                : "App: FORGE moved you to \(gym.name), which has \(kit.isEmpty ? "no equipment" : kit.lowercased()), and is building a new plan for it. Say something short and encouraging about training there.")
        } else if ChatDecision.gymWords.contains(where: lower.contains) {
            lines.append("App: to train somewhere else, they pick or add that gym on the Gyms screen, and the plan follows its equipment.")
        }
        if ["swap", "replace", "instead of", "substitute", "switch"].contains(where: lower.contains) {
            lines.append("App: in a workout, the Swap button on an exercise's card replaces it with any lift they search for.")
        }
        let knowledge = minimal ? [] : CoachKnowledge.facts(for: message)
        if !knowledge.isEmpty { lines.append("Coaching facts to answer from: " + knowledge.joined(separator: " ")) }
        let declined = SyncedSettings.skillGoalsDeclined
        for target in SkillLadder.targets(in: message)
        where !c.goals.contains(where: { $0.target == target }) && !declined.contains(target) {
            let ladder = SkillLadder.named(target)
            lines.append(ladder?.isPriority == true
                ? "The app shows a button under your reply to make \(target) a priority lift. End by asking if they'd like that."
                : "The app shows a button under your reply to build up to \(target) step by step. End by asking if they'd like that.")
        }
        lines.append("Athlete says: \"\(message)\"")
        return lines.joined(separator: "\n")
    }
}
