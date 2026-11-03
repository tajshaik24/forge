import Foundation
import FoundationModels

/// The AI coach's voice between sets. The rules (`NextSet`) pick every number; this only rewords
/// their note and sums up a finished lift, on the on-device model, while you rest. The rule text is
/// shown first and stays unless a reply comes back in time and keeps every number exactly.
@MainActor
final class SetCoach {
    static let shared = SetCoach()

    var isAvailable: Bool { AppleIntelligenceCoach.isAvailable }

    private static let instructions = """
    You are FORGE, a friendly strength coach talking to someone resting between sets.
    Reply with one short sentence, under 20 words, in plain English.
    Keep every number and unit exactly as given. Never add a new number, weight or rep count.
    No medical advice, no emoji, no quotes.
    """

    /// Loaded at the start of a workout so the first reply is quick.
    private var warmed: LanguageModelSession?

    func prewarm() {
        guard isAvailable, warmed == nil else { return }
        let session = LanguageModelSession(instructions: Self.instructions)
        session.prewarm()
        warmed = session
    }

    /// The rule's note in a coach's words, or nil if the model is slow, unavailable, or changed a number.
    func reword(_ note: String, lift: String, within seconds: TimeInterval) async -> String? {
        let prompt = "Lift: \(lift). Say this to the athlete in your own words: \(note)"
        guard let reply = await ask(prompt, within: seconds) else { return nil }
        return Self.keepsNumbers(reply, of: note) ? reply : nil
    }

    /// One sentence on how a lift went, from its sets ("135 lb × 8, Good"). Nil if it can't in time.
    func recap(lift: String, sets: [String], within seconds: TimeInterval) async -> String? {
        let prompt = "The athlete just finished \(lift): \(sets.joined(separator: "; ")). Give a one-sentence recap without numbers."
        guard let reply = await ask(prompt, within: seconds) else { return nil }
        return Self.numbers(in: reply).isEmpty ? reply : nil
    }

    /// One fresh session per question (the transcript would outgrow the small context window), raced
    /// against the time left. Never throws: any failure means the rule text stays.
    private func ask(_ prompt: String, within seconds: TimeInterval) async -> String? {
        guard isAvailable, seconds > 2 else { return nil }
        let session = warmed ?? LanguageModelSession(instructions: Self.instructions)
        warmed = nil
        let work = Task { () -> String? in
            try? await session.respond(to: prompt, options: GenerationOptions(temperature: 0.4)).content
        }
        let timeout = Task {
            try? await Task.sleep(for: .seconds(seconds - 1))
            work.cancel()
        }
        let reply = await work.value
        timeout.cancel()
        prewarm()
        return reply.flatMap(Self.tidy)
    }

    /// One line, no wrapping quotes, a sensible length.
    nonisolated static func tidy(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”")))
        return trimmed.isEmpty || trimmed.count > 160 ? nil : trimmed
    }

    /// The model may say it differently but must not change the coach's numbers.
    nonisolated static func keepsNumbers(_ reply: String, of rule: String) -> Bool {
        numbers(in: reply) == numbers(in: rule)
    }

    nonisolated static func numbers(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isNumber && $0 != "." }).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty }.sorted()
    }
}
