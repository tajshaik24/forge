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
    @Guide(description: "Exact exercise name copied from the findExercises tool output")
    var name: String
    @Guide(description: "Working sets", .range(2...5))
    var sets: Int
    @Guide(description: "Rep target, e.g. \"8-10\" or \"12\"")
    var reps: String
    @Guide(description: "Optional short technique or safety cue tied to the athlete's notes. Empty if none.")
    var cue: String
}

@Generable
struct GeneratedDayPlan {
    @Guide(description: "Name of the session focus, copied from the candidate list, e.g. Pull")
    var focus: String
    @Guide(description: "Muscle groups this session trains")
    var muscles: [GenMuscle]
    @Guide(description: "Two or three reasons for this choice, each under 14 words, citing recovery, schedule or notes", .count(2...3))
    var reasons: [String]
    @Guide(description: "Exercises in order, big compound lifts first", .count(4...7))
    var exercises: [GeneratedExercise]
}

@Generable
struct GeneratedReply {
    @Guide(description: "Reply to the athlete in 1-3 short, practical sentences. If they report dizziness, lightheadedness, chest pain or sharp pain, also suggest checking with a doctor.")
    var message: String
    @Guide(description: "True only if the athlete shared a lasting limitation, preference or feedback that should change future workouts")
    var shouldRemember: Bool
    @Guide(description: "If remembering: one rule you will follow, e.g. \"No heavy standing squats; use supported leg movements\". Otherwise empty.")
    var rule: String
    @Guide(description: "Movement types to rule out because of this feedback. Empty if none apply.")
    var avoid: [GenMovementFlag]
    @Guide(description: "True if the current plan should be rebuilt because of this message")
    var replan: Bool
    @Guide(description: "New session length in minutes if they asked for a shorter or longer workout, otherwise 0")
    var minutesToday: Int
    @Guide(description: "Which day the change is about. Use today unless they name another day.")
    var day: GenTargetDay
}

// MARK: - Tool: the model looks up exercises, already filtered by gym + notes

struct FindExercisesTool: Tool {
    let name = "findExercises"
    let description = "Lists exercises the athlete can do right now for one muscle group. Already filtered to their current gym's equipment and their coach notes. Only program exercises returned by this tool."

    let pool: [Exercise]

    @Generable
    struct Arguments {
        @Guide(description: "Muscle group to look up")
        var muscle: GenMuscle
    }

    func call(arguments: Arguments) async throws -> String {
        let muscle = arguments.muscle.muscle
        let matches = pool.filter { $0.primary == muscle || $0.secondary.contains(muscle) }
            .sorted { $0.primary == muscle && $1.primary != muscle }
        guard !matches.isEmpty else { return "No \(muscle.label.lowercased()) exercises available here." }
        return matches.prefix(8).map { "\($0.name) (\($0.isCompound ? "compound" : "isolation"), \($0.reps) reps)" }
            .joined(separator: "\n")
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
    You are FORGE, a strength coach. Choose the session from the candidate focuses and build it.
    Rules:
    - Prefer the focus whose muscles are most recovered, unless the split says otherwise.
    - Call findExercises for each muscle you train. Only use names it returns, copied exactly.
    - Respect every coach note. Never work around a note.
    - Fit the session length: about 8 minutes per exercise.
    - Keep reasons short and specific to the numbers you were given.
    """

    private static let chatInstructions = """
    You are FORGE, a supportive, concise strength coach in a workout app.
    The athlete may report how movements feel, limitations, schedule changes or equipment changes.
    Decide whether it is lasting feedback to remember, which movement types to avoid, and whether to rebuild the plan.
    You are not a doctor: for symptoms like dizziness, lightheadedness, chest pain or sharp pain, adapt the training and suggest they check with a doctor.
    """

    func plan(for context: CoachContext) async throws -> PlannedWorkout {
        guard context.isTrainingDay else { return PlanFinisher.restDay(context, engine: displayName) }

        let session = LanguageModelSession(tools: [FindExercisesTool(pool: context.pool)],
                                           instructions: Self.planInstructions)
        let response = try await session.respond(to: CoachPrompts.plan(context), generating: GeneratedDayPlan.self)
        let draft = response.content

        let exercises = draft.exercises.map {
            PlannedExercise(name: $0.name, sets: $0.sets, reps: $0.reps, cue: $0.cue)
        }
        // Fall back to the template's muscles if the model returned none.
        let template = context.rankedTemplates.first { $0.name.lowercased() == draft.focus.lowercased() }
        let modelMuscles = draft.muscles.map(\.muscle)
        let muscles = modelMuscles.isEmpty ? (template?.muscles ?? []) : modelMuscles
        return PlanFinisher.finish(focus: template?.name ?? draft.focus, muscles: muscles, reasons: draft.reasons,
                                   exercises: exercises, context: context, engine: displayName)
    }

    func reply(to message: String, context: CoachContext) async throws -> CoachReply {
        let session = LanguageModelSession(instructions: Self.chatInstructions)
        let prompt = CoachPrompts.chat(message, context)
        let out = try await session.respond(to: prompt, generating: GeneratedReply.self).content
        let note = out.shouldRemember
            ? NoteSnapshot(said: message, rule: out.rule.isEmpty ? message : out.rule, avoid: Set(out.avoid.compactMap(\.flag)))
            : nil
        // Trust an explicit day name in the message over the model's pick.
        let target = DayMatcher.date(in: message) ?? out.day.date
        return CoachReply(message: out.message, note: note,
                          shouldReplan: out.replan || note != nil,
                          minutesOverride: out.minutesToday > 0 ? out.minutesToday : nil,
                          targetDate: target)
    }
}

// MARK: - Prompts: compact, because the on-device context window is small

enum CoachPrompts {   // not "PromptBuilder": that name is a FoundationModels result builder
    static func plan(_ c: CoachContext) -> String {
        var lines: [String] = []
        let day = c.isToday ? "today" : c.date.formatted(.dateTime.weekday(.wide))
        lines.append("Planning for \(day). Goal: \(c.goal). Experience: \(c.experience.label). Session length: \(c.minutes) min. Split: \(c.split.label). Gym: \(c.gymName).")
        lines.append("Use \(c.experience.setRange.lowerBound)-\(c.experience.setRange.upperBound) working sets per exercise.")
        lines.append("Candidate focuses (muscle readiness, 100 = fully recovered):")
        for t in c.rankedTemplates.prefix(4) {
            let detail = t.muscles.map { "\($0.label) \(Int((c.readiness[$0] ?? 1) * 100))" }.joined(separator: ", ")
            lines.append("- \(t.name): \(detail)")
        }
        if !c.recent.isEmpty {
            let f = DateFormatter(); f.dateFormat = "EEE"
            lines.append("Recent sessions: " + c.recent.prefix(4).map { "\(f.string(from: $0.date)) \($0.focus)" }.joined(separator: ", "))
        }
        if let feedback = c.feedbackSummary { lines.append("Feedback: \(feedback)") }
        if c.isToday, let s = c.health.sleepHours { lines.append(String(format: "Sleep last night: %.1f h.", s)) }
        if c.isToday, let h = c.health.hrv, let b = c.health.hrvBaseline { lines.append("HRV \(Int(h)) ms vs baseline \(Int(b)) ms.") }
        if !c.notes.isEmpty {
            lines.append("Coach notes to respect:")
            for n in c.notes { lines.append("- \(n.rule)") }
        }
        lines.append("Build the session.")
        return lines.joined(separator: "\n")
    }

    static func chat(_ message: String, _ c: CoachContext) -> String {
        var lines: [String] = []
        if let p = c.currentPlan, !p.isRestDay {
            lines.append("Today's plan: \(p.focus) at \(p.gymName) — " + p.exercises.map(\.name).joined(separator: ", ") + ".")
        }
        if !c.notes.isEmpty { lines.append("Existing notes: " + c.notes.map(\.rule).joined(separator: "; ")) }
        lines.append("Athlete says: \"\(message)\"")
        return lines.joined(separator: "\n")
    }
}
