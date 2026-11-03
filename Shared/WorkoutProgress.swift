import Foundation

// MARK: - Effort

/// How a set felt, from one tap after logging it. Stored as RPE so progression and the
/// weight test keep working; skipping the question counts as Good.
enum Effort: Int, CaseIterable, Codable, Sendable, Identifiable {
    case easy = 7, good = 8, hard = 10

    var id: Int { rawValue }
    var rpe: Int { rawValue }

    var label: String {
        switch self {
        case .easy: "Easy"
        case .good: "Good"
        case .hard: "Hard"
        }
    }

    /// What the tap means, for the first time you see it.
    var detail: String {
        switch self {
        case .easy: "3+ reps left"
        case .good: "about 2 left"
        case .hard: "0–1 left"
        }
    }

    init(rpe: Int?) {
        switch rpe ?? Effort.good.rpe {
        case ..<8: self = .easy
        case 8...9: self = .good
        default: self = .hard
        }
    }
}

// MARK: - Progress through a workout

/// How far through a workout you are, worked out the same way on the iPhone and the Watch,
/// from the sets logged in this workout only. Warm-up sets aren't logged. On a "find your weight"
/// lift the test sets, up to and including the first one that felt Good or Hard, don't count
/// toward its sets: the working sets at the weight the test found come after.
struct WorkoutProgress: Equatable, Sendable {
    struct DoneSet: Hashable, Sendable {
        var exercise: String
        /// Pounds.
        var weight: Double
        var reps: Int
        var rpe: Int?
        var date: Date

        var record: SetRecord { SetRecord(date: date, weight: weight, reps: reps, rpe: rpe) }
    }

    struct Lift: Equatable, Sendable {
        let exercise: PlannedExercise
        /// Test sets on a "find your weight" lift, oldest first.
        let tests: [DoneSet]
        /// Sets that count toward the plan, oldest first. Can exceed `planned` only through "Add set".
        let working: [DoneSet]

        var planned: Int { exercise.sets }
        var isDone: Bool { working.count >= planned }
        var isStarted: Bool { !tests.isEmpty || !working.isEmpty }
        /// Still finding the weight: no test set has felt Good or Hard yet.
        var isTesting: Bool { exercise.calibrate == true && working.isEmpty && !testFound }
        /// The test is over (a set felt Good or Hard).
        var testFound: Bool { exercise.calibrate == true && (tests.last.map { Lift.ends(test: $0) } ?? false) }
        /// The working set you're on, 1-based, never past the plan.
        var nextSet: Int { min(working.count + 1, planned) }
        var all: [DoneSet] { tests + working }

        static func ends(test set: DoneSet) -> Bool {
            set.weight > 0 && (set.rpe ?? Effort.good.rpe) >= Calibration.foundAtRPE
        }
    }

    let lifts: [Lift]

    init(plan: PlannedWorkout, sets: [DoneSet]) {
        lifts = plan.exercises.map { ex in
            let mine = sets.filter { $0.exercise == ex.name }.sorted { $0.date < $1.date }
            guard ex.calibrate == true else { return Lift(exercise: ex, tests: [], working: mine) }
            guard let found = mine.firstIndex(where: Lift.ends(test:)) else {
                return Lift(exercise: ex, tests: mine, working: [])
            }
            return Lift(exercise: ex, tests: Array(mine[...found]), working: Array(mine[(found + 1)...]))
        }
    }

    var setsDone: Int { lifts.reduce(0) { $0 + min($1.working.count, $1.planned) } }
    var setsPlanned: Int { lifts.reduce(0) { $0 + $1.planned } }
    /// 0...1, for the progress bar.
    var fraction: Double { setsPlanned == 0 ? 0 : Double(setsDone) / Double(setsPlanned) }
    /// Every lift has its planned sets. False for a workout with no lifts.
    var isComplete: Bool { !lifts.isEmpty && lifts.allSatisfy(\.isDone) }

    func lift(named name: String) -> Lift? { lifts.first { $0.exercise.name == name } }

    /// The lift to do now: `index` if it isn't finished, else the next unfinished one after it,
    /// then any skipped earlier. Nil when every lift is done.
    func current(from index: Int) -> Int? {
        if lifts.indices.contains(index), !lifts[index].isDone { return index }
        let after = lifts.indices.filter { $0 > index }
        let before = lifts.indices.filter { $0 < index }
        return (after + before).first { !lifts[$0].isDone }
    }
}

// MARK: - The coach between sets

/// What to do on the next set of a lift, from how the last one went. Rules, not the model:
/// weights must be instant and predictable. The note says why in a sentence.
enum NextSet {
    struct Call: Equatable, Sendable {
        /// Pounds.
        var weight: Double
        var reps: Int
        var note: String
    }

    /// - Parameters:
    ///   - last: the set just logged.
    ///   - target: the plan's target for this lift (nil the first time).
    ///   - setNumber: the working set coming up, 1-based.
    static func after(_ last: WorkoutProgress.DoneSet, exercise: Exercise, target: LoadTarget?,
                      setNumber: Int, goal: TrainingGoal, unit: WeightUnit) -> Call {
        let range = RepScheme.range(for: exercise, goal: goal)
        let aim = target?.reps ?? range.lowerBound
        let effort = Effort(rpe: last.rpe)
        let word = exercise.isTimed ? "s" : " reps"
        let isBodyweight = last.weight == 0 || exercise.equipment.isEmpty
        let next = "set \(setNumber)"

        if isBodyweight {
            switch effort {
            case .hard where last.reps < aim:
                return Call(weight: 0, reps: last.reps, note: "Hard at \(last.reps)\(word): match it on \(next).")
            case .easy:
                let more = exercise.isTimed ? 5 : 2
                return Call(weight: 0, reps: last.reps + more, note: "Easy: go for \(last.reps + more)\(word) on \(next).")
            default:
                return Call(weight: 0, reps: max(last.reps, aim), note: "Same again on \(next).")
            }
        }

        let jump = Progression.increment(for: exercise, unit: unit)
        // Missed the reps, or nothing left: lighten so the next set stays in the range with good form.
        if last.reps < range.lowerBound || (effort == .hard && last.reps <= aim) {
            let lighter = Progression.roundDown(last.weight * (last.reps < range.lowerBound ? 0.9 : 0.95), unit: unit)
            let why = last.reps < range.lowerBound ? "\(last.reps)\(word) is short of \(range.lowerBound)" : "Hard at \(last.reps)\(word)"
            return Call(weight: lighter, reps: aim, note: "\(why): \(unit.format(pounds: lighter)) for \(next).")
        }
        // Easy and you got the reps: a little heavier.
        if effort == .easy, last.reps >= aim {
            let heavier = last.weight + jump
            return Call(weight: heavier, reps: aim, note: "Easy at \(last.reps)\(word): try \(unit.format(pounds: heavier)) for \(next).")
        }
        // Hard but you beat the target: hold the weight, don't chase more.
        if effort == .hard {
            return Call(weight: last.weight, reps: aim, note: "Hard but you got \(last.reps): hold \(unit.format(pounds: last.weight)) for \(next).")
        }
        return Call(weight: last.weight, reps: max(aim, min(last.reps, range.upperBound)),
                    note: "Right on target: \(unit.format(pounds: last.weight)) again for \(next).")
    }
}

// MARK: - Personal records

/// Your bests on a lift, to celebrate a set that beats them.
enum PersonalRecords {
    enum Kind: String, Sendable {
        case heaviest = "Heaviest weight"
        case estimatedMax = "Best estimated max"
        case mostReps = "Most reps"
    }

    /// The record `set` breaks against everything before it, if any. Bodyweight lifts count reps.
    /// No record on the first time you do a lift: there's nothing to beat.
    static func broken(by set: SetRecord, history: [SetRecord]) -> Kind? {
        let before = history.filter { $0.date < set.date }
        guard !before.isEmpty else { return nil }
        if set.weight == 0 {
            let best = before.filter { $0.weight == 0 }.map(\.reps).max() ?? 0
            return set.reps > best ? .mostReps : nil
        }
        let weighted = before.filter { $0.weight > 0 }
        guard !weighted.isEmpty else { return nil }
        if set.weight > weighted.map(\.weight).max() ?? 0 { return .heaviest }
        let bestMax = weighted.map { Strength.estimatedMax(weight: $0.weight, reps: $0.reps, rpe: nil) }.max() ?? 0
        return Strength.estimatedMax(weight: set.weight, reps: set.reps, rpe: nil) > bestMax + 0.5 ? .estimatedMax : nil
    }

    struct Best: Hashable, Sendable {
        let heaviest: SetRecord?
        let estimatedMax: Double?
        let mostReps: SetRecord?
    }

    static func best(in history: [SetRecord]) -> Best {
        let weighted = history.filter { $0.weight > 0 }
        return Best(heaviest: weighted.max { ($0.weight, $0.reps) < ($1.weight, $1.reps) },
                    estimatedMax: weighted.map { Strength.estimatedMax(weight: $0.weight, reps: $0.reps, rpe: nil) }.max(),
                    mostReps: history.max { $0.reps < $1.reps })
    }
}
