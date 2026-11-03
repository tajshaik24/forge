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
        Topic(words: ["cardio", "running", "run ", "jog", "walk", "cycling", "bike", "conditioning", "hiit"], facts: """
            Easy cardio (walking, light cycling) on rest days helps recovery and heart health and won't hurt strength. \
            Keep hard cardio or long runs away from the day before leg training. FORGE trims a set from leg lifts after a big walking day (15,000 steps yesterday or 12,000 already today).
            """),
        // Worded carefully: mentions of thresholds and recovery readings here tripped the model's safety filter.
        Topic(words: ["sleep", "slept", "tired", "exhausted", "fatigue"], facts: """
            One night of less sleep is fine for lifting. Keep the weights and leave a rep or two more in reserve on each set.
            """),
        Topic(words: ["sore", "soreness", "doms", "stiff"], facts: """
            Muscle soreness a day or two after training is normal and not a reason to skip; a warm-up usually eases it. \
            Sharp pain or joint pain is different: tell the coach what hurts and the plan works around it.
            """),
        Topic(words: ["warm up", "warm-up", "warmup", "stretch"], facts: """
            Each FORGE workout starts with a short warm-up, and heavy lifts get lighter warm-up sets before the first working set. \
            Stretches come after the last lift.
            """),
        Topic(words: ["protein", "eat", "diet", "calorie", "nutrition", "food", "fat", "lose weight", "cut", "bulk"], facts: """
            Protein of roughly 0.7-1 g per pound of bodyweight a day supports muscle. To lose fat, eat a little less while keeping \
            protein high and training hard, so the weight lost is fat, not muscle. To gain, eat a little more and keep progressing.
            """),
        Topic(words: ["stuck", "plateau", "stall", "not progressing", "not getting stronger", "no progress"], facts: """
            FORGE adds weight once every set reaches the top of the rep range without feeling Hard; until then it adds a rep at the \
            same weight. Falling short of the range drops the weight about 8%. Stalls usually break with sleep, enough food and honest effort taps.
            """),
        Topic(words: ["how often", "times a week", "days a week", "frequency", "every day", "overtrain"], facts: """
            Training each muscle about twice a week works well for most people. FORGE spreads that across your training days and \
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
    ]

    /// Facts for the topics a message touches, at most two.
    static func facts(for message: String) -> [String] {
        let lower = " " + message.lowercased() + " "
        return topics.filter { $0.words.contains(where: lower.contains) }.prefix(2).map(\.facts)
    }
}
