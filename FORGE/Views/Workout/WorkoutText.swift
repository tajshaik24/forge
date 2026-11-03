import Foundation

/// The words and numbers on the workout screen, kept apart from the views so they're easy to test.
enum WorkoutText {
    /// What you hold or load, for the small label above an exercise's name.
    static func equipment(_ ex: Exercise?) -> String {
        guard let ex else { return "Exercise" }
        let e = ex.equipment
        if e.contains(.barbell) { return "Barbell" }
        if e.contains(.smithMachine) { return "Smith machine" }
        if e.contains(.dumbbells) { return "Dumbbells" }
        if e.contains(.kettlebell) { return "Kettlebell" }
        if e.contains(.cableStack) { return "Cable" }
        if !e.isDisjoint(with: [.machines, .legPress, .legCurl, .legExtension]) { return "Machine" }
        if e.contains(.bands) { return "Band" }
        return "Bodyweight"
    }

    /// Takes a weight you can change. Pull-ups, dips, push-ups, holds with nothing in hand don't.
    static func usesWeight(_ ex: Exercise?, target: LoadTarget? = nil) -> Bool {
        if let target, target.weight > 0 { return true }
        guard let ex else { return true }
        return !ex.isBodyweight
    }

    /// "8 reps", "30 s", "1 min".
    static func reps(_ reps: Int, timed: Bool) -> String {
        timed ? Dose.label(reps) : "\(reps) rep\(reps == 1 ? "" : "s")"
    }

    /// "135 lb × 8", "135 lb × 30 s", or just "12 reps" / "45 s" without a weight.
    static func amount(weight: Double, reps: Int, timed: Bool, unit: WeightUnit) -> String {
        guard weight > 0 else { return self.reps(reps, timed: timed) }
        return "\(unit.format(pounds: weight)) × \(timed ? Dose.label(reps) : "\(reps)")"
    }

    /// "6–10", "30–45 s": the plan's range with a proper dash.
    static func range(_ reps: String) -> String { reps.replacingOccurrences(of: "-", with: "–") }

    /// An upcoming lift in one line: "3 × 6–10 · 135 lb".
    static func plan(_ lift: PlannedExercise, unit: WeightUnit) -> String {
        var text = "\(lift.sets) × \(range(lift.reps))"
        if lift.calibrate == true {
            text += " · find your weight"
        } else if let t = lift.target, t.weight > 0 {
            text += " · \(unit.format(pounds: t.weight))"
        }
        return text
    }

    /// The best set in a list: heaviest (then most reps), or most reps / longest without a weight.
    static func best(_ sets: [WorkoutProgress.DoneSet]) -> WorkoutProgress.DoneSet? {
        sets.max { ($0.weight, $0.reps) < ($1.weight, $1.reps) }
    }

    /// A finished lift in one line: "3/3 · best 140 lb × 8".
    static func summary(_ lift: WorkoutProgress.Lift, timed: Bool, unit: WeightUnit) -> String {
        var text = "\(lift.working.count)/\(lift.planned)"
        if let best = best(lift.working.isEmpty ? lift.tests : lift.working) {
            text += " · best \(amount(weight: best.weight, reps: best.reps, timed: timed, unit: unit))"
        }
        return text
    }

    /// How today's target compares with the last time you did the lift: "+5 lb since last time".
    /// Nil without a target or any earlier sets.
    static func sinceLastTime(target: LoadTarget?, before: [SetRecord], timed: Bool, unit: WeightUnit) -> String? {
        guard let target, let last = Progression.lastSession(before) else { return nil }
        let top = last.map(\.weight).max() ?? 0
        let bestReps = last.filter { $0.weight == top }.map(\.reps).max() ?? 0
        if target.weight > 0, top > 0 {
            let shownTarget = unit.roundToStep(unit.fromPounds(target.weight))
            let shownTop = unit.roundToStep(unit.fromPounds(top))
            let diff = unit.format(pounds: abs(target.weight - top))
            if shownTarget > shownTop { return "+\(diff) since last time" }
            if shownTarget < shownTop { return "\(diff) lighter than last time" }
            if target.reps > bestReps {
                let more = target.reps - bestReps
                return "Same weight, \(more) more rep\(more == 1 ? "" : "s") than last time"
            }
            return "Same as last time"
        }
        if target.reps > bestReps {
            return timed ? "+\(target.reps - bestReps) s since last time" : "+\(target.reps - bestReps) reps since last time"
        }
        return "Same as last time"
    }

    /// For each set in order, the personal record it broke, if any. Each set is compared with your
    /// history before this workout plus the sets before it today, so a best is celebrated once.
    /// The first time you do a lift there's nothing to beat, so nothing is a record.
    static func records(_ sets: [WorkoutProgress.DoneSet], before: [SetRecord]) -> [PersonalRecords.Kind?] {
        guard !before.isEmpty else { return sets.map { _ in nil } }
        var history = before
        return sets.map { set in
            let kind = PersonalRecords.broken(by: set.record, history: history)
            history.append(set.record)
            return kind
        }
    }

    /// "Heaviest weight" → "heaviest weight", for "New best: heaviest weight".
    static func record(_ kind: PersonalRecords.Kind) -> String {
        kind.rawValue.prefix(1).lowercased() + kind.rawValue.dropFirst()
    }

    /// The test-set guide on a "find your weight" lift, in plain words.
    static func testGuide(tests: Int, testReps: Int) -> String {
        tests == 0
            ? "First time on this lift. Do \(testReps) reps with a weight you're sure about, then say how it felt. We'll suggest the next weight until a set feels Good: about two reps left."
            : "Do \(testReps) reps at the suggested weight and rate it honestly. Good means you could have done two more."
    }
}
