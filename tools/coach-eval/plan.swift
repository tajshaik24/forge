import Foundation

enum PlanEval {
    static func run() async {
        var contexts: [(String, CoachContext)] = []
        var base = EvalContext.make(); base.currentPlan = nil
        contexts.append(("full gym, knee note, pull-up goal", base))
        var home = base; home.gymName = "Home"; home.equipment = [.dumbbells, .bench, .bands, .pullUpBar]
        contexts.append(("home gym", home))
        var short = base; short.minutes = 30; short.notes.append(NoteSnapshot(said: "More glute work", rule: "More glute work", avoid: []))
        contexts.append(("30 min + glute preference", short))
        var dizzy = base; dizzy.notes = [NoteSnapshot(said: "deadlifts make me lightheaded", rule: "No heavy standing lifts or bar on the back after feeling dizzy.", avoid: [.standingHeavy, .axialLoading], exercises: ["Barbell deadlift"])]
        contexts.append(("dizzy note", dizzy))
        var newbie = base; newbie.experience = .new; newbie.goals = [SkillGoal(target: "Push-up"), SkillGoal(target: "Barbell bench press")]
        contexts.append(("beginner, push-up + bench goals", newbie))
        for (label, c) in contexts {
            let start = Date()
            do {
                let p = try await AppleIntelligenceCoach().plan(for: c)
                print("PLAN \(label): \(p.focus) \(p.minutes) min (\(String(format: "%.1f", Date().timeIntervalSince(start)))s)\n  " + p.exercises.map { "\($0.name) \($0.sets)x\($0.reps)\($0.goal.map { " [\($0)]" } ?? "")" }.joined(separator: "\n  ") + "\n  why: " + p.reasons.joined(separator: " | "))
            } catch {
                print("PLAN \(label): ERROR \(error)")
            }
        }
    }
}
