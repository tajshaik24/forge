import Foundation

/// Sends each message through the real chat code and prints the reply and what the app would do.
@main
struct Eval {
    static func main() async {
        if ProcessInfo.processInfo.environment["PLAN"] != nil { await PlanEval.run(); return }
        if ProcessInfo.processInfo.environment["SETS"] != nil { await SetEval.run(); return }
        let file = CommandLine.arguments.dropFirst().first
        let messages = file.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }?
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty } ?? []
        // A few at a time: the model serves requests one by one, so more just queue.
        let batch = max(1, Int(ProcessInfo.processInfo.environment["PAR"] ?? "") ?? 3)
        var failed = 0
        for start in stride(from: 0, to: messages.count, by: batch) {
            await withTaskGroup(of: String.self) { group in
                for i in start..<min(start + batch, messages.count) { group.addTask { await run(messages[i], i) } }
                for await line in group {
                    if line.contains("ERROR:") { failed += 1 }
                    print(line)
                }
            }
        }
        print("\n\(messages.count - failed) of \(messages.count) answered, \(failed) failed")
    }

    static func run(_ message: String, _ i: Int) async -> String {
        let start = Date()
        do {
            let r = try await AppleIntelligenceCoach().reply(to: message, context: EvalContext.make()) { _ in }
            let note = r.note.map { "NOTE ex=\($0.exercises.sorted()) avoid=\($0.avoid.map(\.rawValue).sorted()) rule=\($0.rule)" } ?? "no note"
            return "[\(i)] >>> \(message)\n    \(r.message)\n    \(note) | replan=\(r.shouldReplan) min=\(r.minutesOverride.map(String.init) ?? "-") day=\(r.targetDate.map { $0.formatted(.dateTime.weekday()) } ?? "today") offers=\(r.goalOffers) rest=\(r.restDay) gym=\(r.switchGym ?? "-") (\(String(format: "%.1f", Date().timeIntervalSince(start)))s)"
        } catch {
            return "[\(i)] >>> \(message)\n    ERROR: \(error)"
        }
    }
}
