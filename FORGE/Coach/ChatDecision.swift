import Foundation

/// Turns what the model made of a chat message into what the app does: a note to remember, goals to
/// offer, a new session length, a rest day, a replan. The model's fields are checked against the
/// athlete's own words, so a small model can't save a note nobody asked for, offer a goal for a lift
/// they never named, or change today's length when they asked a question.
enum ChatDecision {
    enum Kind: Sendable { case question, limitation, goal, schedule, equipment, feedback, other }

    /// The model's reading of the message, before checking.
    struct Fields: Sendable {
        var kind: Kind
        var exercises: [String]
        var buildToward: [String]
        var remember: Bool
        var rule: String
        var avoid: Set<MovementFlag>
        var restDay: Bool
        var minutes: Int
        /// Nil = today.
        var day: Date?
    }

    static let timeWords = ["min", "hour", "hr", "short", "quick", "long", "less time", "more time", "rushed", "busy"]
    static let restWords = ["rest", "day off", "off day", "skip", "take off", "break", "no workout", "can't train",
                            "can’t train", "won't make it", "won’t make it", "not train"]
    static let preferenceWords = ["more", "less", "prefer", "focus", "hate", "love", "like", "don't want", "don’t want",
                                  "avoid", "never", "always", "rather", "bore", "boring", "dislike", "not a fan", "sick of",
                                  "tired of", "enjoy"]
    static let dislikeWords = ["hate", "bore", "boring", "dislike", "not a fan", "sick of", "tired of", "don't want", "don’t want",
                               "avoid", "never want"]
    static let symptomWords = ["dizzy", "lightheaded", "light-headed", "faint", "blacked out"]
    static let questionStarts = ["how ", "what ", "why ", "when ", "where ", "which ", "should ", "is it ", "is that ",
                                 "can i ", "could i ", "do i ", "does ", "am i ", "are ", "will "]

    static let requestStarts = ["can you", "could you", "would you", "will you", "can we", "could we", "please", "pls",
                                "make ", "move ", "change ", "let's", "lets "]
    static let muscleWords = ["arm", "leg", "chest", "back", "shoulder", "glute", "core", "abs", "bicep", "tricep", "quad", "hamstring", "calf", "calves"]

    static let gymWords = ["hotel", "at home", "home gym", "travel", "traveling", "travelling", "different gym", "new gym",
                           "dumbbells only", "only dumbbells", "just dumbbells", "no barbell", "no equipment"]

    /// "Make Saturday a rest day", "take tomorrow off", "skip today", "no workout Friday".
    static func asksForRestDay(_ text: String) -> Bool {
        let lower = text.lowercased()
        if ["rest day", "day off", "off day", "no workout", "can't train", "can’t train", "won't make it", "won’t make it"].contains(where: lower.contains) { return true }
        let saysDay = DayMatcher.date(in: text) != nil || ["today", "tomorrow"].contains(where: lower.contains)
        return saysDay && (lower.contains("skip") || (lower.contains("take") && lower.contains(" off")))
    }

    static func isRequest(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return requestStarts.contains(where: lower.hasPrefix)
    }

    /// The day a change is about, in words: "Friday", "Tomorrow", "Today".
    static func dayName(_ text: String) -> String {
        if let d = DayMatcher.date(in: text) {
            return Calendar.current.isDateInTomorrow(d) ? "Tomorrow" : d.formatted(.dateTime.weekday(.wide))
        }
        return text.lowercased().contains("tomorrow") ? "Tomorrow" : "Today"
    }

    /// "Can we do more glute work?" -> "More glute work", for the note the planner reads.
    static func plainPreference(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "?!.")))
        for lead in ["can we do ", "could we do ", "can we ", "could we ", "can you ", "could you ", "please ", "i want to ", "i want ",
                     "i'd like to ", "i'd like ", "i would like to ", "i would like ", "let's do ", "lets do ", "let's ", "honestly "] where s.lowercased().hasPrefix(lead) {
            s = String(s.dropFirst(lead.count))
        }
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// A lasting like or dislike about lifts or muscles ("squats bore me", "more glute work"), not a question.
    static func isPreference(_ text: String) -> Bool {
        let lower = text.lowercased()
        return !isQuestion(text) && preferenceWords.contains(where: lower.contains)
            && (!ExerciseCatalog.mentioned(in: text).isEmpty || muscleWords.contains(where: lower.contains))
    }

    /// A question by its words, whatever the model thought. "Can you make Saturday a rest day?" is a request.
    static func isQuestion(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if isRequest(text) { return false }
        return lower.hasSuffix("?") || questionStarts.contains { lower.hasPrefix($0) }
    }

    /// A session length the words give: "30 min", "only 40 minutes", "an hour", "half an hour", "1.5 hours".
    static func minutes(in text: String) -> Int? {
        let lower = text.lowercased()
        // "I slept 5 hours" is about sleep, not the session.
        guard !lower.contains("sleep"), !lower.contains("slept") else { return nil }
        if lower.contains("half an hour") || lower.contains("half hour") { return 30 }
        if let m = lower.firstMatch(of: #/(\d{1,3})\s*-?\s*(?:min|mins|minute|minutes|m\b)/#), let n = Int(m.1) { return n }
        if let m = lower.firstMatch(of: #/(\d(?:\.\d)?)\s*(?:hour|hours|hr|hrs)/#), let h = Double(m.1) { return Int(h * 60) }
        if lower.contains("an hour") || lower.contains("one hour") { return 60 }
        return nil
    }

    static func make(message: String, context: CoachContext, reply: String, fields f: Fields) -> CoachReply {
        let lower = message.lowercased()
        let isQuestion = !Self.isRequest(message) && (f.kind == .question || Self.isQuestion(message))
        let named = Set(ExerciseCatalog.mentioned(in: message))
        // A lift counts only if the athlete named it (or an easier version of it).
        func inMessage(_ raw: String) -> String? {
            guard let ex = ExerciseCatalog.match(raw) else { return nil }
            if named.contains(ex.name) { return ex.name }
            if let harder = ExerciseCatalog.harderVersion(of: ex.name), named.contains(harder) { return harder }
            return nil
        }
        let hurts = GoalWords.pain.contains(where: lower.contains)
        let symptom = symptomWords.contains(where: lower.contains)

        // Remember limitations, pain and lasting preferences. Never questions, goals, one-off days or how a
        // session felt (that's what the effort taps are for).
        // Wanting to get better at a lift ("I'd like to improve my bench") is a goal, never a reason to drop it.
        let dislikes = dislikeWords.contains(where: lower.contains)
        let cant = GoalWords.cant.contains(where: lower.contains)
        let aspires = (GoalWords.aspire + ["love to", "like to", "want to", "able to"]).contains(where: lower.contains)
        let onlyAGoal = aspires && !named.isEmpty && !hurts && !symptom && !dislikes && !cant
        var limited = Set(f.exercises.compactMap(inMessage))
        if f.kind == .limitation { limited.formUnion(ExerciseCatalog.limited(in: message)) }
        // A lift named with pain, a symptom or a dislike ("squats bore me") is the one to leave out.
        if hurts || symptom || dislikes { limited.formUnion(named) }
        // Movement types only for pain or symptoms, and only those the words point to.
        var avoid = hurts ? MovementFlag.supported(f.avoid, by: message) : []
        // Pain with no lift named ("I tweaked my lower back"): the movement types its words point to.
        if hurts, avoid.isEmpty, named.isEmpty { avoid = MovementFlag.supported(MovementFlag.allCases, by: message) }
        if symptom { avoid.formUnion([.standingHeavy, .axialLoading]) }
        let preference = isPreference(message) && !onlyAGoal
        let lasting = !isQuestion && !onlyAGoal && (preference || (f.kind != .goal && (hurts || symptom || f.kind == .limitation)))
        var note: NoteSnapshot?
        if lasting, !limited.isEmpty || !avoid.isEmpty || preference {
            // A symptom gets a plain rule the planner can follow, whatever the model wrote.
            // A preference keeps the athlete's own words: a small model can turn "more glute work" into its opposite.
            let rule = symptom ? "No heavy standing lifts or bar on the back after feeling dizzy."
                : preference && !hurts ? Self.plainPreference(message)
                : (f.rule.isEmpty ? message : f.rule)
            note = NoteSnapshot(said: message, rule: rule, avoid: avoid, exercises: limited).checked()
        }

        // Goals: lifts they named and want to work toward, plus any the words make plain. Never one that hurts.
        // A question ("why am I doing inverted rows?") isn't asking for a goal unless its words say so.
        let heard = hurts || isQuestion ? [] : f.buildToward.compactMap(inMessage)
        let offers = (heard + SkillLadder.targets(in: message)).reduce(into: [String]()) { list, name in
            if SkillLadder.named(name) != nil, !list.contains(name) { list.append(name) }
        }

        // Time, day and rest changes only when the words ask for them.
        let saidMinutes = minutes(in: message)
        let modelMinutes = timeWords.contains(where: lower.contains) && f.minutes >= 10 && f.minutes <= 180 ? f.minutes : nil
        let minutes = isQuestion ? nil : (saidMinutes ?? modelMinutes).flatMap { (10...180).contains($0) && $0 != context.minutes ? $0 : nil }
        let restDay = !isQuestion && (asksForRestDay(message) || (f.restDay && restWords.contains(where: lower.contains)))
        let namedDay = DayMatcher.date(in: message)
        let day = isQuestion ? nil : (namedDay ?? ((f.kind == .schedule || restDay) ? f.day : nil))

        // The app's own changes, confirmed in words the athlete can trust even if the model's wording drifts.
        // Prompt labels never reach the athlete, and an echo of their own words isn't a reply.
        var reply = reply.replacingOccurrences(of: "App: ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if reply.isEmpty || reply.lowercased() == message.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
            reply = note != nil ? "Got it. Your plan will work around that." : "Got it."
        }
        func confirm(_ sentence: String, unless marker: String) {
            if !reply.lowercased().contains(marker.lowercased()) { reply += (reply.isEmpty ? "" : " ") + sentence }
        }
        let dayName = day.map { Calendar.current.isDateInToday($0) ? "Today" : $0.formatted(.dateTime.weekday(.wide)) } ?? "Today"
        if restDay { confirm("\(dayName) is now a rest day.", unless: "rest day") }
        if let minutes { confirm("\(dayName)'s session is being rebuilt to fit \(minutes) min.", unless: "\(minutes) min") }
        if note != nil, preference {
            // A reply that refuses what the app just saved would be wrong; say what happened instead.
            if ["can't", "can’t", "cannot", "won't", "won’t", "not add", "keeping the", "stick to", "sticking", "same plan"].contains(where: reply.lowercased().contains) {
                reply = "Got it."
            }
            confirm("Saved to your notes, and upcoming plans will follow it.", unless: "notes")
        }
        if !isQuestion, gymWords.contains(where: lower.contains) {
            confirm("Pick or add that gym on the Gyms screen and your plan will use its equipment.", unless: "Gyms screen")
        }

        reply = reply.prefix(1).uppercased() + reply.dropFirst()
        return CoachReply(message: reply, note: note,
                          shouldReplan: note != nil || minutes != nil || (f.kind == .schedule && day != nil && !restDay),
                          minutesOverride: minutes, targetDate: day, goalOffers: offers, restDay: restDay)
    }
}
