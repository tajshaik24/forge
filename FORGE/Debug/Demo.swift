#if DEBUG
import SwiftUI
import SwiftData

/// Debug-only: launch with `-demo` for an in-memory store full of realistic history (nothing touches
/// iCloud), and `-screen <name>` to open one screen straight away for simulator screenshots.
///
///     xcrun simctl launch <sim> com.taj.forge -demo -screen workout
///
/// Each area registers its own screens: see `WorkoutScreens`, `HistoryScreens`.
enum Demo {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screen"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    @MainActor @ViewBuilder
    static func view(for screen: String) -> some View {
        if let v = WorkoutScreens.view(screen) {
            v
        } else if let v = HistoryScreens.view(screen) {
            v
        } else {
            Text("No demo screen named \"\(screen)\"").padding()
        }
    }

    /// Eight weeks of push / pull / legs, three or four days a week, with steady progress,
    /// a few hard days and some personal records.
    @MainActor
    static func seed(_ ctx: ModelContext) {
        Seed.ifNeeded(ctx)
        // Train at the full gym, where every lift in the history below is available.
        let gyms = (try? ctx.fetch(FetchDescriptor<GymProfile>())) ?? []
        let full = gyms.max { $0.equipment.count < $1.equipment.count }
        gyms.forEach { $0.isActive = $0 == full }
        let gymName = full?.name ?? "Gym"
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let days: [(focus: String, lifts: [(String, Double, String)])] = [
            ("Push", [("Barbell bench press", 135, "6-10"), ("Standing barbell overhead press", 85, "6-10"),
                      ("Incline dumbbell press", 45, "8-12"), ("Cable lateral raise", 15, "10-15")]),
            ("Pull", [("Barbell row", 115, "6-10"), ("Lat pulldown", 110, "8-12"),
                      ("Cable face pull", 35, "10-15"), ("Dumbbell curl", 25, "10-15")]),
            ("Legs", [("Back squat", 165, "6-10"), ("Barbell Romanian deadlift", 135, "6-10"),
                      ("Leg press", 230, "8-12"), ("Seated leg curl", 70, "10-15")]),
        ]
        var n = 0
        for back in (1...56).reversed() {
            guard let start = cal.date(byAdding: .day, value: -back, to: today) else { continue }
            let weekday = cal.component(.weekday, from: start)
            // Mon / Wed / Fri, plus every other Saturday.
            guard [2, 4, 6].contains(weekday) || (weekday == 7 && (back / 7) % 2 == 0) else { continue }
            let weekBack = back / 7
            let day = days[n % days.count]
            n += 1
            let begin = cal.date(bySettingHour: 18, minute: 5, second: 0, of: start)!
            let session = WorkoutSession(date: begin, focus: day.focus, gymName: gymName)
            ctx.insert(session)
            var t = begin.addingTimeInterval(300)
            let progress = Double(7 - weekBack)
            for (name, base, _) in day.lifts {
                let weight = (base + progress * (base >= 100 ? 5 : 2.5)).rounded()
                for set in 0..<3 {
                    let reps = 8 - (set == 2 && weekBack % 3 == 0 ? 2 : 0)
                    let entry = SetEntry(exercise: name, weight: weight, reps: reps,
                                         rpe: set == 2 ? 9 : 8, date: t)
                    entry.session = session
                    ctx.insert(entry)
                    t = t.addingTimeInterval(150)
                }
                t = t.addingTimeInterval(60)
            }
            session.endDate = t
            session.averageHeartRate = Double(118 + n % 12)
            session.maxHeartRate = Double(158 + n % 15)
            session.activeCalories = Double(260 + (n * 37) % 120)
            session.feel = ["right", "right", "hard", "easy"][n % 4]
        }
        try? ctx.save()
    }
}
#endif
