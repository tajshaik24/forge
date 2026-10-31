import Foundation
import SwiftData

// CloudKit-backed SwiftData rules: every attribute has a default or is optional,
// every relationship is optional, and nothing is marked unique.

@Model
final class WorkoutSession {
    var date: Date = Date.now
    var endDate: Date?
    var focus: String = ""
    var gymName: String = ""
    @Relationship(deleteRule: .cascade, inverse: \SetEntry.session)
    var sets: [SetEntry]? = []

    // Filled in from the HealthKit workout when the session ends.
    var healthWorkoutID: UUID?
    var activeCalories: Double = 0
    var averageHeartRate: Double = 0
    var maxHeartRate: Double = 0
    /// One heart-rate reading (bpm) about every 15 seconds, JSON-encoded [Int].
    var heartRateTimeline: Data?
    /// "easy" / "right" / "hard", fed back to the coach.
    var feel: String?

    init(date: Date = .now, focus: String, gymName: String) {
        self.date = date
        self.focus = focus
        self.gymName = gymName
    }

    var orderedSets: [SetEntry] { (sets ?? []).sorted { $0.date < $1.date } }
    var duration: TimeInterval { (endDate ?? .now).timeIntervalSince(date) }
    var volume: Double { orderedSets.reduce(0) { $0 + $1.weight * Double($1.reps) } }

    /// Weeks in a row with a finished workout that has sets. An empty current week doesn't break it yet.
    static func weekStreak(_ sessions: [WorkoutSession], now: Date = .now) -> Int {
        let cal = Calendar.current
        let weeks = Set(sessions.filter { $0.endDate != nil && !($0.sets ?? []).isEmpty }
            .compactMap { cal.dateInterval(of: .weekOfYear, for: $0.date)?.start })
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start,
              var week = weeks.contains(thisWeek) ? thisWeek : cal.date(byAdding: .weekOfYear, value: -1, to: thisWeek)
        else { return 0 }
        var streak = 0
        while weeks.contains(week), let previous = cal.date(byAdding: .weekOfYear, value: -1, to: week) {
            streak += 1
            week = previous
        }
        return streak
    }

    var heartRates: [Int] {
        get { heartRateTimeline.flatMap { try? JSONDecoder().decode([Int].self, from: $0) } ?? [] }
        set { heartRateTimeline = try? JSONEncoder().encode(newValue) }
    }
}

@Model
final class SetEntry {
    var exercise: String = ""
    var weight: Double = 0
    var reps: Int = 0
    var rpe: Int?
    var date: Date = Date.now
    var session: WorkoutSession?

    init(exercise: String, weight: Double, reps: Int, rpe: Int? = nil, date: Date = .now) {
        self.exercise = exercise
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.date = date
    }
}

/// Something the user told the coach that should shape every future plan.
@Model
final class CoachNote {
    var said: String = ""
    var rule: String = ""
    var avoidRaw: [String] = []
    /// Catalog names this note is about ("Pull-up"). It applies to these, not the whole muscle.
    var exercises: [String] = []
    var createdAt: Date = Date.now

    init(said: String, rule: String, avoid: [MovementFlag], exercises: [String] = [], createdAt: Date = .now) {
        self.said = said
        self.rule = rule
        self.avoidRaw = avoid.map(\.rawValue)
        self.exercises = exercises
        self.createdAt = createdAt
    }

    var avoid: [MovementFlag] { avoidRaw.compactMap(MovementFlag.init(rawValue:)) }
}

@Model
final class GymProfile {
    var name: String = ""
    var detail: String = ""
    var equipmentRaw: [String] = []
    var isActive: Bool = false
    var sortIndex: Int = 0

    init(name: String, detail: String, equipment: Set<Equipment>, isActive: Bool = false, sortIndex: Int) {
        self.name = name
        self.detail = detail
        self.equipmentRaw = equipment.map(\.rawValue).sorted()
        self.isActive = isActive
        self.sortIndex = sortIndex
    }

    var equipment: Set<Equipment> {
        get { Set(equipmentRaw.compactMap(Equipment.init(rawValue:))) }
        set { equipmentRaw = newValue.map(\.rawValue).sorted() }
    }
}

/// Today's plan, stored so the Watch and Siri see exactly what the iPhone coach built.
@Model
final class DailyPlan {
    var dayKey: String = ""
    var planData: Data?
    var updatedAt: Date = Date.now

    init(plan: PlannedWorkout) {
        self.dayKey = DayKey.of(plan.date)
        self.planData = try? JSONEncoder().encode(plan)
    }

    var plan: PlannedWorkout? {
        get { planData.flatMap { try? JSONDecoder().decode(PlannedWorkout.self, from: $0) } }
        set { planData = try? JSONEncoder().encode(newValue); updatedAt = .now }
    }
}

/// A message in the coach chat, kept so the conversation survives relaunches and syncs.
@Model
final class ChatEntry {
    var date: Date = Date.now
    var fromUser: Bool = false
    var text: String = ""
    var savedNote: String?
    /// DayKey of a plan this reply rebuilt, so the chat can show it.
    var replannedDayKey: String?

    init(fromUser: Bool, text: String, savedNote: String? = nil, replannedDayKey: String? = nil) {
        self.fromUser = fromUser
        self.text = text
        self.savedNote = savedNote
        self.replannedDayKey = replannedDayKey
    }
}

/// An exercise the user added. Merged into `ExerciseCatalog.custom` at runtime.
@Model
final class CustomExercise {
    var name: String = ""
    var primaryRaw: String = MuscleGroup.chest.rawValue
    var secondaryRaw: [String] = []
    var equipmentRaw: [String] = []
    var flagsRaw: [String] = []
    var reps: String = "8-12"
    var isCompound: Bool = false
    var notes: String = ""
    var createdAt: Date = Date.now

    init(name: String, primary: MuscleGroup, secondary: [MuscleGroup], equipment: Set<Equipment>,
         flags: Set<MovementFlag>, reps: String, isCompound: Bool, notes: String) {
        self.name = name
        self.primaryRaw = primary.rawValue
        self.secondaryRaw = secondary.map(\.rawValue)
        self.equipmentRaw = equipment.map(\.rawValue).sorted()
        self.flagsRaw = flags.map(\.rawValue).sorted()
        self.reps = reps
        self.isCompound = isCompound
        self.notes = notes
    }

    var exercise: Exercise {
        Exercise(name: name,
                 primary: MuscleGroup(rawValue: primaryRaw) ?? .chest,
                 secondary: secondaryRaw.compactMap(MuscleGroup.init(rawValue:)),
                 equipment: Set(equipmentRaw.compactMap(Equipment.init(rawValue:))),
                 flags: Set(flagsRaw.compactMap(MovementFlag.init(rawValue:))),
                 reps: reps, isCompound: isCompound, isCustom: true,
                 customNotes: notes.isEmpty ? nil : notes)
    }
}

enum DataStore {
    static let cloudContainerID = "iCloud.com.taj.forge"
    static let schema = Schema([WorkoutSession.self, SetEntry.self, CoachNote.self, GymProfile.self, DailyPlan.self,
                                ChatEntry.self, CustomExercise.self])

    /// Syncs through the user's private iCloud database. Falls back to on-device storage
    /// if iCloud isn't set up (e.g. a simulator not signed in), so the app still runs.
    @MainActor static let shared: ModelContainer = {
        // Unit tests host the app unsigned, without the iCloud entitlement CloudKit mirroring requires.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: [memory])
        }
        #if PERSONAL_TEAM
        // Free Apple teams can't sign iCloud, and SwiftData traps if asked for CloudKit without it.
        do { return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, cloudKitDatabase: .none)]) }
        catch { fatalError("Could not create ModelContainer: \(error)") }
        #else
        do {
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudContainerID))
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("FORGE: iCloud store unavailable (\(error)); using local store.")
            let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            do { return try ModelContainer(for: schema, configurations: [local]) }
            catch { fatalError("Could not create ModelContainer: \(error)") }
        }
        #endif
    }()

    @MainActor
    static func todayPlan(in context: ModelContext, date: Date = .now) -> DailyPlan? {
        let key = DayKey.of(date)
        var d = FetchDescriptor<DailyPlan>(predicate: #Predicate { $0.dayKey == key },
                                           sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    @MainActor
    static func save(_ plan: PlannedWorkout, in context: ModelContext) {
        if let existing = todayPlan(in: context, date: plan.date) {
            existing.plan = plan
        } else {
            context.insert(DailyPlan(plan: plan))
        }
        try? context.save()
    }

    /// Plans for today and later, earliest first.
    @MainActor
    static func upcomingPlans(in context: ModelContext, from date: Date = .now) -> [PlannedWorkout] {
        let key = DayKey.of(date)
        // String range comparisons aren't reliably supported by SwiftData predicates: filter in Swift.
        let d = FetchDescriptor<DailyPlan>(sortBy: [SortDescriptor(\.dayKey), SortDescriptor(\.updatedAt, order: .reverse)])
        var seen = Set<String>()
        return ((try? context.fetch(d)) ?? []).compactMap { row in
            guard row.dayKey >= key, !seen.contains(row.dayKey), let plan = row.plan else { return nil }
            seen.insert(row.dayKey)
            return plan
        }
    }

    /// Drops plans after today so they get rebuilt with new notes, gyms or settings.
    @MainActor
    static func clearFuturePlans(in context: ModelContext) {
        let key = DayKey.of(.now)
        let d = FetchDescriptor<DailyPlan>()
        for row in (try? context.fetch(d)) ?? [] where row.dayKey > key { context.delete(row) }
        try? context.save()
    }

    /// Loads user-created exercises into the catalog.
    @MainActor
    static func refreshCustomExercises(in context: ModelContext) {
        let rows = (try? context.fetch(FetchDescriptor<CustomExercise>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        ExerciseCatalog.custom = rows.map(\.exercise)
    }

    /// This exercise's logged sets as plain records, for progression and charts.
    @MainActor
    static func history(of exercise: String, in context: ModelContext, days: Int = 60) -> [SetRecord] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        let d = FetchDescriptor<SetEntry>(predicate: #Predicate { $0.exercise == exercise && $0.date >= since },
                                          sortBy: [SortDescriptor(\.date)])
        return ((try? context.fetch(d)) ?? []).map { SetRecord(date: $0.date, weight: $0.weight, reps: $0.reps, rpe: $0.rpe) }
    }

    @MainActor
    static func activeGym(in context: ModelContext) -> GymProfile? {
        let gyms = (try? context.fetch(FetchDescriptor<GymProfile>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        return gyms.first(where: \.isActive) ?? gyms.first
    }
}

enum Seed {
    /// First launch: three gym profiles so the equipment logic is visible immediately.
    /// Also removes duplicate gyms that appear when two devices seed before iCloud syncs.
    @MainActor
    static func ifNeeded(_ context: ModelContext) {
        let gyms = (try? context.fetch(FetchDescriptor<GymProfile>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        if gyms.isEmpty {
            context.insert(GymProfile(name: "Home gym", detail: "Garage · DBs to 50 lb",
                                      equipment: [.dumbbells, .bench, .pullUpBar, .bands, .kettlebell],
                                      isActive: true, sortIndex: 0))
            context.insert(GymProfile(name: "Commercial gym", detail: "Full equipment",
                                      equipment: Set(Equipment.allCases), sortIndex: 1))
            context.insert(GymProfile(name: "Travel", detail: "Hotel gym",
                                      equipment: [.dumbbells, .bench], sortIndex: 2))
        } else {
            var seen = Set<String>()
            for g in gyms {
                if seen.contains(g.name) { context.delete(g) } else { seen.insert(g.name) }
            }
            // A gym that had every piece of equipment before library v2 gets the new kinds too.
            let before = Set(Equipment.allCases).subtracting(Equipment.addedInLibraryV2)
            for g in gyms where g.equipment.isSuperset(of: before) && !g.equipment.isSuperset(of: Equipment.addedInLibraryV2) {
                g.equipment.formUnion(Equipment.addedInLibraryV2)
            }
        }
        try? context.save()
    }
}
