import Foundation

// MARK: - Units (weights are always stored in pounds; only display changes)

enum WeightUnit: String, CaseIterable, Codable, Sendable, Identifiable {
    case lb, kg
    var id: String { rawValue }

    static let lbPerKg = 2.20462

    var label: String { rawValue.uppercased() }

    /// Converts a stored pound value to this unit.
    func fromPounds(_ lb: Double) -> Double { self == .lb ? lb : lb / Self.lbPerKg }
    /// Converts a value in this unit to stored pounds.
    func toPounds(_ value: Double) -> Double { self == .lb ? value : value * Self.lbPerKg }

    /// Smallest sensible jump on the stepper.
    var step: Double { self == .lb ? 5 : 2.5 }

    /// "275 lb" / "125 kg" — rounds to the unit's step so kg values don't show 124.7.
    func format(pounds lb: Double, withUnit: Bool = true) -> String {
        let v = roundToStep(fromPounds(lb))
        let n = v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
        return withUnit ? "\(n) \(rawValue)" : n
    }

    func roundToStep(_ value: Double) -> Double { (value / step).rounded() * step }
}

// MARK: - Progressive overload

/// One logged set, decoupled from SwiftData so the logic is easy to test.
struct SetRecord: Sendable, Hashable {
    let date: Date
    let weight: Double   // pounds
    let reps: Int
    let rpe: Int?
}

struct LoadTarget: Sendable, Hashable, Codable {
    /// Pounds. 0 for bodyweight moves.
    var weight: Double
    var reps: Int
    /// Short "why": "+5 lb — you hit 10 reps on every set last time".
    var note: String
}

/// Double progression: add reps inside the range, then add weight once every set hits the top
/// of the range at a manageable effort; back off when reps fall short or effort was maximal.
enum Progression {
    enum Signal: Sendable { case normal, holdBack, pushOn }

    /// - Parameters:
    ///   - history: this exercise's sets, any order.
    ///   - signal: session-level feedback (felt too hard / under-recovered -> holdBack; felt easy -> pushOn).
    static func target(for exercise: Exercise, history: [SetRecord], signal: Signal = .normal,
                       unit: WeightUnit = .lb) -> LoadTarget? {
        let range = exercise.repRange
        guard let last = lastSession(history) else { return nil }
        let isBodyweight = exercise.equipment.isEmpty || last.allSatisfy { $0.weight == 0 }

        let top = last.map(\.weight).max() ?? 0
        let working = last.filter { $0.weight == top }
        let minReps = working.map(\.reps).min() ?? 0
        let rpes = working.compactMap(\.rpe)
        let avgRPE = rpes.isEmpty ? nil : Double(rpes.reduce(0, +)) / Double(rpes.count)
        let hardEffort = (avgRPE ?? 8) >= 9.5
        let easyEffort = (avgRPE ?? 8) <= 7.5

        if isBodyweight {
            // Holds progress in 5-second steps; "reps" are seconds for them.
            let word = exercise.isTimed ? "s" : "reps"
            let more = exercise.isTimed ? 5 : 1
            if minReps >= range.upperBound, !hardEffort, signal != .holdBack {
                return LoadTarget(weight: 0, reps: minReps + more, note: "Beat last time: \(minReps + more) \(word)")
            }
            return LoadTarget(weight: 0, reps: max(minReps, range.lowerBound), note: "Match \(max(minReps, range.lowerBound)) \(word)")
        }

        let jump = increment(for: exercise, unit: unit)
        let unitText = unit.rawValue

        // Back off: missed the bottom of the range, or every set was all-out.
        if minReps < range.lowerBound || (hardEffort && signal == .holdBack) {
            let lighter = roundDown(top * 0.92, unit: unit)
            return LoadTarget(weight: lighter, reps: range.lowerBound,
                              note: "Lighter — last time fell short of \(range.lowerBound) reps")
        }

        // Add weight: every working set hit the top of the range without grinding.
        let earnedIncrease = minReps >= range.upperBound && (!hardEffort || signal == .pushOn)
        if earnedIncrease && signal != .holdBack {
            let bump = (signal == .pushOn || easyEffort) && exercise.isCompound ? jump * 2 : jump
            let shown = unit.format(pounds: bump, withUnit: false)
            return LoadTarget(weight: top + bump, reps: range.lowerBound,
                              note: "+\(shown) \(unitText) — you hit \(minReps) reps on every set")
        }

        // Hold the weight, chase one more rep.
        let nextReps = min(minReps + 1, range.upperBound)
        let why = signal == .holdBack ? "Same weight — recovery is low today" : "Same weight, aim for \(nextReps) reps"
        return LoadTarget(weight: top, reps: nextReps, note: why)
    }

    /// Estimated one-rep max (Epley). Used for progress charts.
    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        reps <= 1 ? weight : weight * (1 + Double(reps) / 30)
    }

    /// Sets from the most recent day this exercise was trained.
    static func lastSession(_ history: [SetRecord]) -> [SetRecord]? {
        guard let latest = history.max(by: { $0.date < $1.date }) else { return nil }
        let day = Calendar.current.startOfDay(for: latest.date)
        let sets = history.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
        return sets.isEmpty ? nil : sets
    }

    /// Pounds to add for one step: bigger jumps for lower-body compounds.
    static func increment(for exercise: Exercise, unit: WeightUnit) -> Double {
        let lowerBody: Set<MuscleGroup> = [.quads, .hamstrings, .glutes]
        let bigLift = exercise.isCompound && lowerBody.contains(exercise.primary)
        switch unit {
        case .lb: return bigLift ? 10 : 5
        case .kg: return WeightUnit.kg.toPounds(bigLift ? 5 : 2.5)
        }
    }

    private static func roundDown(_ lb: Double, unit: WeightUnit) -> Double {
        let v = (unit.fromPounds(lb) / unit.step).rounded(.down) * unit.step
        return unit.toPounds(v)
    }
}
