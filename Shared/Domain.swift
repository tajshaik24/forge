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
    case machines, bike, foamRoller

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
        case .machines: "Weight machines"
        case .bike: "Exercise bike"
        case .foamRoller: "Foam roller"
        }
    }

    /// Added after the first release. Gyms that had everything before get these too.
    static let addedInLibraryV2: Set<Equipment> = [.machines, .bike, .foamRoller]
}

/// What an exercise is for. Only `.strength` counts toward volume, readiness and progression.
enum ExerciseKind: String, CaseIterable, Codable, Sendable, Hashable {
    case strength, warmUp, stretch

    var label: String {
        switch self {
        case .strength: "Strength"
        case .warmUp: "Warm-up & mobility"
        case .stretch: "Stretches"
        }
    }
}

/// The shape of a lift. A balanced week covers each pattern; a session slot asks for one.
enum MovementPattern: String, CaseIterable, Codable, Sendable, Hashable {
    case squat, lunge, hinge, horizontalPush, verticalPush, horizontalPull, verticalPull, carry, core

    var label: String {
        switch self {
        case .squat: "Squat"
        case .lunge: "Lunge"
        case .hinge: "Hinge"
        case .horizontalPush: "Push"
        case .verticalPush: "Overhead push"
        case .horizontalPull: "Row"
        case .verticalPull: "Pull-down"
        case .carry: "Carry"
        case .core: "Core"
        }
    }
}

/// Body areas for mobility, stretching and tight spots.
enum BodyArea: String, CaseIterable, Codable, Sendable, Hashable {
    case neck, shoulders, chest, upperBack, lowerBack, hips, glutes, quads, hamstrings, calves

    var label: String {
        switch self {
        case .neck: "Neck"
        case .shoulders: "Shoulders"
        case .chest: "Chest"
        case .upperBack: "Upper back"
        case .lowerBack: "Lower back"
        case .hips: "Hips"
        case .glutes: "Glutes"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .calves: "Calves & ankles"
        }
    }

    /// Where a trained muscle wants stretching afterwards.
    static func stretched(by muscle: MuscleGroup) -> Set<BodyArea> {
        switch muscle {
        case .chest: [.chest, .shoulders]
        case .back: [.upperBack]
        case .shoulders: [.shoulders]
        case .biceps, .triceps: [.shoulders]
        case .quads: [.quads, .hips]
        case .hamstrings: [.hamstrings]
        case .glutes: [.glutes, .hips]
        case .calves: [.calves]
        case .core: [.lowerBack]
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

    /// Words that point at this movement type. A flag the model picks only sticks if the
    /// athlete's own words mention one of these (it once ruled out all six for "I can't do a pull-up").
    private var cues: [String] {
        switch self {
        case .axialLoading: ["squat", "spine", "back pain", "lower back", "barbell on", "dizzy", "lightheaded", "light-headed", "faint"]
        case .standingHeavy: ["squat", "deadlift", "standing", "balance", "dizzy", "lightheaded", "light-headed", "faint", "blood pressure"]
        case .overhead: ["overhead", "shoulder", "above my head", "military press", "ohp"]
        case .deepKneeBend: ["knee", "squat", "lunge", "deep"]
        case .jumping: ["jump", "plyo", "impact", "box"]
        case .floorTransitions: ["floor", "ground", "kneel", "get up", "getting up", "lie down", "lying down"]
        }
    }

    static func supported(_ flags: some Sequence<MovementFlag>, by text: String) -> Set<MovementFlag> {
        let lower = text.lowercased()
        return Set(flags.filter { flag in flag.cues.contains { lower.contains($0) } })
    }
}

enum Experience: String, CaseIterable, Codable, Sendable, Identifiable {
    case new, intermediate, advanced
    var id: String { rawValue }

    /// 0 = new … 2 = advanced.
    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    var label: String {
        switch self {
        case .new: "Less than a year"
        case .intermediate: "1–3 years"
        case .advanced: "3+ years"
        }
    }

    /// How the coach hears it.
    var promptLabel: String {
        switch self {
        case .new: "under 1 year of lifting"
        case .intermediate: "1–3 years of lifting"
        case .advanced: "3+ years of lifting"
        }
    }

    /// Safe limits on the working sets per exercise the coach chooses. Never shown: the coach
    /// decides the sets, this only stops a beginner getting five.
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

    /// What the split means, and the week it suits.
    var detail: String {
        switch self {
        case .coachDecides: "Picks each day from what's recovered"
        case .pushPullLegs: "Chest & arms, back, legs · 3 or 6 days"
        case .upperLower: "Alternates upper and lower · 2 or 4 days"
        case .fullBody: "Whole body every session · 2–3 days"
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
    /// First time on a weighted lift: start with test sets to find your weight.
    var calibrate: Bool? = nil
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
    /// Drills before the first lift. Not logged or counted as volume.
    var warmUp: [PlannedExercise] = []
    /// Stretches after the last lift. Optional, also not logged.
    var coolDown: [PlannedExercise] = []

    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets } }
    /// Made by you rather than the coach: your own workout on the iPhone, or one picked on the Watch.
    static let customEngine = "Custom"
    var isCustom: Bool { engine == Self.customEngine }
    /// Your own workout starts with no lifts and isn't a day off.
    var isRestDay: Bool { exercises.isEmpty && !isCustom }

    private enum CodingKeys: String, CodingKey {
        case date, focus, muscles, minutes, reasons, exercises, restSeconds, gymName, engine, warmUp, coolDown
    }

    /// Plans saved before warm-ups existed decode with empty warm-up and cool-down.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(Date.self, forKey: .date)
        focus = try c.decode(String.self, forKey: .focus)
        muscles = try c.decode([MuscleGroup].self, forKey: .muscles)
        minutes = try c.decode(Int.self, forKey: .minutes)
        reasons = try c.decode([String].self, forKey: .reasons)
        exercises = try c.decode([PlannedExercise].self, forKey: .exercises)
        restSeconds = try c.decode(Int.self, forKey: .restSeconds)
        gymName = try c.decode(String.self, forKey: .gymName)
        engine = try c.decode(String.self, forKey: .engine)
        warmUp = try c.decodeIfPresent([PlannedExercise].self, forKey: .warmUp) ?? []
        coolDown = try c.decodeIfPresent([PlannedExercise].self, forKey: .coolDown) ?? []
    }

    init(date: Date, focus: String, muscles: [MuscleGroup], minutes: Int, reasons: [String],
         exercises: [PlannedExercise], restSeconds: Int, gymName: String, engine: String,
         warmUp: [PlannedExercise] = [], coolDown: [PlannedExercise] = []) {
        self.date = date
        self.focus = focus
        self.muscles = muscles
        self.minutes = minutes
        self.reasons = reasons
        self.exercises = exercises
        self.restSeconds = restSeconds
        self.gymName = gymName
        self.engine = engine
        self.warmUp = warmUp
        self.coolDown = coolDown
    }

    /// A day off. Saved as a plan so week planning leaves the day alone.
    static func rest(on day: Date, gymName: String, engine: String) -> PlannedWorkout {
        PlannedWorkout(date: Calendar.current.startOfDay(for: day), focus: "Rest", muscles: [], minutes: 0,
                       reasons: ["Rest day. Walk, stretch, sleep."], exercises: [], restSeconds: 0,
                       gymName: gymName, engine: engine)
    }

    /// Your own workout for today: starts empty, and you add lifts as you go.
    static func own(gymName: String, restSeconds: Int) -> PlannedWorkout {
        PlannedWorkout(date: Calendar.current.startOfDay(for: .now), focus: ownFocus, muscles: [], minutes: 0,
                       reasons: ["Your own workout. Add lifts as you go."], exercises: [], restSeconds: restSeconds,
                       gymName: gymName, engine: customEngine)
    }

    static let ownFocus = "Own workout"

    /// "Chest + Back", with a trailing "+" for three or more muscles.
    static func focus(for muscles: [MuscleGroup]) -> String {
        guard !muscles.isEmpty else { return ownFocus }
        return muscles.prefix(2).map(\.label).joined(separator: " + ") + (muscles.count > 2 ? " +" : "")
    }

    /// A custom workout's name, muscles and length follow the lifts in it.
    mutating func retitle(unit: WeightUnit, warmUps: Bool) {
        var seen: [MuscleGroup] = []
        for ex in exercises {
            if let m = ExerciseCatalog.named(ex.name)?.primary, !seen.contains(m) { seen.append(m) }
        }
        muscles = seen
        focus = Self.focus(for: seen)
        minutes = exercises.isEmpty ? 0 : estimatedMinutes(unit: unit, warmUps: warmUps)
    }
}

enum DayKey {
    static func of(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Settings live in iCloud key-value storage so the Watch and iPad see the same schedule.
enum SyncedSettings {
    #if PERSONAL_TEAM
    /// Free Apple teams can't sign iCloud key-value storage, so settings stay on this device.
    private static let kv = LocalSettingsStore()
    #else
    private static var kv: NSUbiquitousKeyValueStore { .default }
    #endif

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

    /// Warm-up drills before each workout. On by default; any single workout can skip them.
    static var warmUps: Bool {
        get { kv.object(forKey: "warmUps") as? Bool ?? true }
        set { kv.set(newValue, forKey: "warmUps"); kv.synchronize() }
    }

    static var experience: Experience {
        get { Experience(rawValue: kv.string(forKey: "experience") ?? "") ?? .intermediate }
        set { kv.set(newValue.rawValue, forKey: "experience"); kv.synchronize() }
    }

    /// Crews (beta): shared weekly streaks with friends over CloudKit.
    static var crewBeta: Bool {
        get {
            #if PERSONAL_TEAM
            false   // Crews run on CloudKit
            #else
            kv.bool(forKey: "crewBeta")
            #endif
        }
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

#if PERSONAL_TEAM
/// The slice of `NSUbiquitousKeyValueStore` that `SyncedSettings` uses, backed by `UserDefaults`.
struct LocalSettingsStore {
    private var defaults: UserDefaults { .standard }
    func array(forKey key: String) -> [Any]? { defaults.array(forKey: key) }
    func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    func bool(forKey key: String) -> Bool { defaults.bool(forKey: key) }
    func longLong(forKey key: String) -> Int64 { Int64(defaults.integer(forKey: key)) }
    func object(forKey key: String) -> Any? { defaults.object(forKey: key) }
    func set(_ value: Any?, forKey key: String) { defaults.set(value, forKey: key) }
    @discardableResult func synchronize() -> Bool { true }
}
#endif
