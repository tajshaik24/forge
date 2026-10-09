import Foundation

// Shared by the iPhone app, the Watch app and the coach engines.
// No FoundationModels import here: the Watch target has no Apple Intelligence.

enum MuscleGroup: String, CaseIterable, Codable, Sendable, Hashable {
    case chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes, calves, core

    var label: String { rawValue.capitalized }
}

/// Equipment a gym profile can have. An exercise needs *all* of its listed equipment.
enum Equipment: String, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case dumbbells, bench, pullUpBar, bands, kettlebell, barbell, squatRack
    case cableStack, legPress, legCurl, legExtension, smithMachine, dipStation, rower

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dumbbells: "Dumbbells"
        case .bench: "Adjustable bench"
        case .pullUpBar: "Pull-up bar"
        case .bands: "Bands"
        case .kettlebell: "Kettlebell"
        case .barbell: "Barbell"
        case .squatRack: "Squat rack"
        case .cableStack: "Cable stack"
        case .legPress: "Leg press"
        case .legCurl: "Leg curl"
        case .legExtension: "Leg extension"
        case .smithMachine: "Smith machine"
        case .dipStation: "Dip station"
        case .rower: "Rower"
        }
    }
}

/// Movement characteristics a coach note can rule out
/// (e.g. "squats make me lightheaded" -> no bar on the spine, no heavy standing lifts).
enum MovementFlag: String, CaseIterable, Codable, Sendable, Hashable {
    case axialLoading, standingHeavy, overhead, deepKneeBend, jumping, floorTransitions

    var label: String {
        switch self {
        case .axialLoading: "Bar on spine"
        case .standingHeavy: "Heavy standing lifts"
        case .overhead: "Overhead pressing"
        case .deepKneeBend: "Deep knee bends"
        case .jumping: "Jumping"
        case .floorTransitions: "Floor-to-standing"
        }
    }
}

enum Experience: String, CaseIterable, Codable, Sendable, Identifiable {
    case new, intermediate, advanced
    var id: String { rawValue }

    var label: String {
        switch self {
        case .new: "New to lifting"
        case .intermediate: "1–3 years"
        case .advanced: "3+ years"
        }
    }

    /// Working sets per exercise the coach may prescribe.
    var setRange: ClosedRange<Int> {
        switch self {
        case .new: 2...3
        case .intermediate: 2...4
        case .advanced: 3...5
        }
    }
}

enum TrainingGoal: String, CaseIterable, Codable, Sendable, Identifiable {
    case buildMuscle = "Build muscle"
    case getStronger = "Get stronger"
    case generalFitness = "General fitness"
    case loseFat = "Lose fat, keep muscle"
    var id: String { rawValue }
}

enum SplitStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case coachDecides, pushPullLegs, upperLower, fullBody
    var id: String { rawValue }

    var label: String {
        switch self {
        case .coachDecides: "Coach decides"
        case .pushPullLegs: "Push · Pull · Legs"
        case .upperLower: "Upper · Lower"
        case .fullBody: "Full body"
        }
    }

    var templates: [FocusTemplate] {
        switch self {
        case .coachDecides: FocusTemplate.all
        case .pushPullLegs: [.push, .pull, .legs]
        case .upperLower: [.upper, .lower]
        case .fullBody: [.fullBody]
        }
    }
}

struct FocusTemplate: Codable, Sendable, Hashable {
    let name: String
    let muscles: [MuscleGroup]

    static let push = FocusTemplate(name: "Push", muscles: [.chest, .shoulders, .triceps])
    static let pull = FocusTemplate(name: "Pull", muscles: [.back, .biceps, .shoulders])
    static let legs = FocusTemplate(name: "Legs", muscles: [.quads, .hamstrings, .glutes, .calves])
    static let upper = FocusTemplate(name: "Upper", muscles: [.chest, .back, .shoulders, .biceps, .triceps])
    static let lower = FocusTemplate(name: "Lower", muscles: [.quads, .hamstrings, .glutes, .calves, .core])
    static let fullBody = FocusTemplate(name: "Full body", muscles: [.chest, .back, .quads, .hamstrings, .shoulders, .core])
    static let all: [FocusTemplate] = [.push, .pull, .legs, .upper, .lower, .fullBody]
}

// MARK: - A planned workout (engine output, UI input, synced via DailyPlan)

struct PlannedExercise: Codable, Sendable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var sets: Int
    var reps: String
    var cue: String?
    /// Set when the coach swapped this in for something the notes or gym ruled out.
    var replaces: String?
    /// Weight + reps to aim for, from progressive overload. Nil the first time you do a move.
    var target: LoadTarget?
}

struct PlannedWorkout: Codable, Sendable, Hashable {
    var date: Date
    var focus: String
    var muscles: [MuscleGroup]
    var minutes: Int
    var reasons: [String]
    var exercises: [PlannedExercise]
    var restSeconds: Int
    var gymName: String
    var engine: String

    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets } }
    var isRestDay: Bool { exercises.isEmpty }
}

enum DayKey {
    static func of(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Settings live in iCloud key-value storage so the Watch and iPad see the same schedule.
enum SyncedSettings {
    private static var kv: NSUbiquitousKeyValueStore { .default }

    static var trainingWeekdays: Set<Int> {   // 1 = Sunday … 7 = Saturday (Calendar weekday)
        get {
            let raw = (kv.array(forKey: "trainingWeekdays") as? [Int]) ?? [2, 3, 5, 7]
            return Set(raw)
        }
        set { kv.set(Array(newValue).sorted(), forKey: "trainingWeekdays"); kv.synchronize() }
    }

    static var split: SplitStyle {
        get { SplitStyle(rawValue: kv.string(forKey: "split") ?? "") ?? .coachDecides }
        set { kv.set(newValue.rawValue, forKey: "split"); kv.synchronize() }
    }

    static var goal: String {
        get { kv.string(forKey: "goal") ?? "Build muscle" }
        set { kv.set(newValue, forKey: "goal"); kv.synchronize() }
    }

    static var minutes: Int {
        get { let m = Int(kv.longLong(forKey: "minutes")); return m == 0 ? 45 : m }
        set { kv.set(Int64(newValue), forKey: "minutes"); kv.synchronize() }
    }

    static var unit: WeightUnit {
        get {
            if let raw = kv.string(forKey: "unit"), let u = WeightUnit(rawValue: raw) { return u }
            return Locale.current.measurementSystem == .us ? .lb : .kg
        }
        set { kv.set(newValue.rawValue, forKey: "unit"); kv.synchronize() }
    }

    static var experience: Experience {
        get { Experience(rawValue: kv.string(forKey: "experience") ?? "") ?? .intermediate }
        set { kv.set(newValue.rawValue, forKey: "experience"); kv.synchronize() }
    }

    /// Crews (beta): shared weekly streaks with friends over CloudKit.
    static var crewBeta: Bool {
        get { kv.bool(forKey: "crewBeta") }
        set { kv.set(newValue, forKey: "crewBeta"); kv.synchronize() }
    }

    /// Set at the end of first-run setup. Also read locally so a new device with no
    /// iCloud yet doesn't flash the setup again after it's been done there.
    static var onboarded: Bool {
        get { kv.bool(forKey: "onboarded") || UserDefaults.standard.bool(forKey: "onboarded") }
        set {
            kv.set(newValue, forKey: "onboarded"); kv.synchronize()
            UserDefaults.standard.set(newValue, forKey: "onboarded")
        }
    }
}
