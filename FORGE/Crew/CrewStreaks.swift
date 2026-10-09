import Foundation

// Pure streak math for Crews, kept free of CloudKit so it's easy to test.

struct CrewMember: Identifiable, Hashable, Sendable {
    let id: String          // CloudKit user record name
    var name: String
    var weeklyGoal: Int
}

struct CrewCheckIn: Identifiable, Hashable, Sendable {
    let id: String
    let userID: String
    let name: String
    let date: Date
    let focus: String
    let sets: Int
    let minutes: Int
    /// The workout was recorded in Apple Health.
    let verified: Bool
}

struct CrewNudge: Identifiable, Hashable, Sendable {
    let id: String
    let fromName: String
    let toUserID: String
    let date: Date
}

struct CrewStanding: Identifiable, Hashable {
    var id: String { member.id }
    let member: CrewMember
    /// Monday-first indexes (0…6) of days trained this week.
    let daysThisWeek: Set<Int>
    let weekStreak: Int
    let atRisk: Bool
    let needed: Int
    let daysLeft: Int

    var count: Int { daysThisWeek.count }
    var metGoal: Bool { count >= member.weeklyGoal }
}

/// Streaks are weekly: hit your number of training days each week. Rest days never break a streak.
enum CrewStreaks {
    static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2   // Monday
        return c
    }()

    static func weekStart(_ date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Distinct training days per week start.
    static func daysByWeek(_ checkIns: [CrewCheckIn]) -> [Date: Set<Date>] {
        var out: [Date: Set<Date>] = [:]
        for c in checkIns { out[weekStart(c.date), default: []].insert(calendar.startOfDay(for: c.date)) }
        return out
    }

    /// Consecutive weeks hitting `goal`, counting back from last week, plus this week once it's met.
    static func streak(_ checkIns: [CrewCheckIn], goal: Int, now: Date = .now) -> Int {
        guard goal > 0 else { return 0 }
        let byWeek = daysByWeek(checkIns)
        let thisWeek = weekStart(now)
        var streak = (byWeek[thisWeek]?.count ?? 0) >= goal ? 1 : 0
        var week = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek)!
        while (byWeek[week]?.count ?? 0) >= goal && streak < 520 {
            streak += 1
            week = calendar.date(byAdding: .weekOfYear, value: -1, to: week)!
        }
        return streak
    }

    static func standing(for member: CrewMember, checkIns: [CrewCheckIn], now: Date = .now) -> CrewStanding {
        let mine = checkIns.filter { $0.userID == member.id }
        let start = weekStart(now)
        let days = Set(mine.filter { $0.date >= start }.compactMap { c -> Int? in
            calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: c.date)).day
        }.filter { (0...6).contains($0) })
        let today = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: now)).day ?? 0
        // Days left including today, unless they've already trained today.
        let daysLeft = max(0, 7 - today - (days.contains(today) ? 1 : 0))
        let needed = max(0, member.weeklyGoal - days.count)
        let atRisk = needed > 0 && needed >= daysLeft - 1   // one bad day away from missing the week
        return CrewStanding(member: member, daysThisWeek: days, weekStreak: streak(mine, goal: member.weeklyGoal, now: now),
                            atRisk: atRisk, needed: needed, daysLeft: daysLeft)
    }

    /// Weeks in a row where every member hit their goal (this week counts once everyone has).
    static func crewStreak(members: [CrewMember], checkIns: [CrewCheckIn], now: Date = .now) -> Int {
        guard !members.isEmpty, members.allSatisfy({ $0.weeklyGoal > 0 }) else { return 0 }
        let byMember = Dictionary(grouping: checkIns, by: \.userID).mapValues(daysByWeek)
        func everyoneHit(_ week: Date) -> Bool {
            members.allSatisfy { m in (byMember[m.id]?[week]?.count ?? 0) >= m.weeklyGoal }
        }
        let thisWeek = weekStart(now)
        var streak = everyoneHit(thisWeek) ? 1 : 0
        var week = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek)!
        while everyoneHit(week) && streak < 520 {
            streak += 1
            week = calendar.date(byAdding: .weekOfYear, value: -1, to: week)!
        }
        return streak
    }
}
