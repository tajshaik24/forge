import Foundation

/// Short, settled coaching answers for common questions, given to the chat model when a message
/// touches the topic, so open questions get specific answers instead of filler. Where FORGE does
/// something about the topic, the answer says what, so the coach describes the app it lives in.
enum CoachKnowledge {
    struct Topic {
        let words: [String]
        let facts: String
    }

    static let topics: [Topic] = [
        // First, so it's never crowded out by a second topic.
        Topic(words: ["pregnan", "postpartum", "post-partum", "gave birth", "heart condition", "heart problem", "blood pressure",
                      "hypertension", "diabet", "surgery", "hernia", "medication", "asthma", "osteopor", "concussion"], facts: """
            Whether to train, and how, with a medical condition or during pregnancy is for your doctor to say: they know \
            your situation and FORGE doesn't. Tell me anything they say to avoid, and every plan will work around it.
            """),
        Topic(words: ["period", "cramps", "menstrua", "cycle", "pms"], facts: """
            Training during a period is fine if it feels OK. On a low day, lighter weights or fewer sets are a good choice: \
            tap Hard on tough sets so the weight holds, say "only 30 min today" for a shorter session, or make it a rest day.
            """),
        Topic(words: ["burnt out", "burned out", "burnout", "unmotivated", "motivation", "no energy", "don't feel like",
                      "don’t feel like", "not feeling it", "drained"], facts: """
            Feeling burnt out is a sign to ease off for a few days, not quit: shorter sessions ("only 30 min today"), a rest day, \
            or fewer training days on the Week tab. FORGE also plans a lighter deload week every fourth week.
            """),
        Topic(words: ["creatine", "pre workout", "pre-workout", "preworkout", "supplement", "caffeine", "bcaa"], facts: """
            Creatine monohydrate (3-5 g a day) is the best-studied supplement for strength and is safe for healthy adults. \
            Pre-workout is mostly caffeine: fine in moderation if it suits you, not needed, and best avoided late in the day. \
            Most other supplements aren't needed if food and protein are in place.
            """),
        Topic(words: ["a cold", "the flu", "flu", "sick", "fever", "ill "], facts: """
            Mild symptoms above the neck (runny nose, a light cold) usually allow a lighter session. With a fever, body aches or \
            chest symptoms, rest until better. Make today a rest day by asking the coach.
            """),
        Topic(words: ["grip", "forearm", "straps", "hands give out"], facts: """
            Grip is often the first thing to give out on deadlifts and rows. Lifting straps on the heaviest sets keep the back \
            working while grip catches up, and holding the bar for time at the end of a session builds it.
            """),
        Topic(words: ["crowded", "busy gym", "gym is busy", "machine is taken", "taken", "occupied", "waiting for"], facts: """
            When the gym is busy, tap Swap on an exercise's card to pick a lift with free equipment, or do the lifts in a \
            different order. The plan's progress carries over either way.
            """),
        Topic(words: ["days a week", "longer", "shorter", "more days", "fewer days", "6 days", "5 days", "3 days", "train more"], facts: """
            Three to five training days a week suits most people. Six can work with shorter sessions if recovery keeps up. \
            Training days and session length are set on the Week tab, and plans follow them. For just today, saying \
            "I have an hour today" or "only 30 min today" rebuilds today's session.
            """),
        Topic(words: ["cardio", "running", "run ", "jog", "walk", "cycling", "bike", "conditioning", "hiit"], facts: """
            Cardio doesn't hurt strength gains. Easy cardio (walking, light cycling) helps recovery and heart health. \
            Keep hard cardio or long runs away from the day before leg training. FORGE trims a set from leg lifts after a big walking day (15,000 steps yesterday or 12,000 already today).
            """),
        // Worded carefully: mentions of thresholds and recovery readings here tripped the model's safety filter.
        Topic(words: ["sleep", "slept", "tired", "exhausted", "fatigue"], facts: """
            One night of less sleep is fine for lifting. Keep the weights and leave a rep or two more in reserve on each set.
            """),
        Topic(words: ["sore", "soreness", "doms", "stiff", "tight"], facts: """
            Muscle soreness a day or two after training is normal and not a reason to skip; a warm-up usually eases it. \
            Sharp pain or joint pain is different: tell the coach what hurts and the plan works around it.
            """),
        Topic(words: ["warm up", "warm-up", "warmup", "stretch"], facts: """
            Each FORGE workout starts with a short warm-up, and heavy lifts get lighter warm-up sets before the first working set. \
            Stretches come after the last lift.
            """),
        Topic(words: ["protein", "eat", "diet", "calorie", "nutrition", "food", "fat", "lose ", "pounds", "kilos", "post workout", "post-workout", "cut", "bulk"], facts: """
            Protein of roughly 0.7-1 g per pound of bodyweight a day supports muscle. To lose fat, eat a little less while keeping \
            protein high and training hard, so the weight lost is fat, not muscle. To gain, eat a little more and keep progressing.
            """),
        Topic(words: ["stuck", "plateau", "stall", "not progressing", "not getting stronger", "no progress", "making progress", "progress"], facts: """
            FORGE adds weight once every set reaches the top of the rep range without feeling Hard; until then it adds a rep at the \
            same weight. Falling short of the range drops the weight about 8%. Stalls usually break with sleep, enough food and honest effort taps.
            """),
        Topic(words: ["how often", "times a week", "frequency", "every day", "overtrain", "rest between", "days between", "between leg", "in a row"], facts: """
            A muscle needs about two to three days between hard sessions, so the same muscle every day is too much; \
            training each muscle about twice a week works well for most people. FORGE spreads that across your training days and \
            picks the most recovered muscles each day.
            """),
        Topic(words: ["form", "technique", "how do i do", "how to do", "cue"], facts: """
            Every exercise has a How to page with setup, the movement and common mistakes: tap How to on its card in the workout.
            """),
        Topic(words: ["wedding", "vacation", "holiday", "beach", "event", "look better", "photos"], facts: """
            Visible change in a few weeks comes from never missing a session, keeping protein high and, if losing fat, a small calorie \
            deficit. Six weeks of steady training shows; crash diets cost muscle.
            """),
        Topic(words: ["effort", "rpe", "how hard", "felt easy", "felt hard", "too easy", "felt heavy", "too heavy"], facts: """
            After each set you tap Easy (3+ reps left), Good (about 2 left) or Hard (0-1 left). Easy sets move the weight up sooner; \
            Hard sets hold it. Skipping the tap counts as Good.
            """),
        Topic(words: ["alcohol", "beer", "wine", "drink", "drinks", "drinking", "drunk", "hangover", "hungover", "party"], facts: """
            A drink or two now and then won't undo your progress. Heavy drinking slows recovery and hurts sleep, so keep big \
            nights rare, eat your protein, drink water, and train lighter the day after if you feel rough.
            """),
        Topic(words: ["heart rate", "bpm", "apple watch", "my watch", "the watch", "calories", "sync"], facts: """
            FORGE shows live heart rate and calories during a workout. With an Apple Watch, the Watch runs the workout and \
            sends them to the iPhone. If heart rate is missing: wear the Watch snugly and unlocked, open FORGE on the Watch, \
            and check Settings > Health > Data Access & Devices > FORGE allows heart rate. The plan and sets work without it.
            """),
    ]

    /// Facts for the topics a message touches, at most two. Words match from the start of a word,
    /// so "weather" isn't "eat".
    static func facts(for message: String) -> [String] {
        let lower = " " + message.lowercased().map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : " " } + " "
        return topics.filter { $0.words.contains { lower.contains(" " + $0) } }.prefix(2).map(\.facts)
    }
}
