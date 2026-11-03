import Testing
import Foundation
@testable import FORGE

@Suite("History stats")
struct HistoryStatsTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2   // Monday
        return c
    }

    /// Wed 4 Nov 2026, noon UTC.
    private var now: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))! }

    private func day(_ back: Int, hour: Int = 18) -> Date {
        cal.date(byAdding: .hour, value: hour - 12, to: cal.date(byAdding: .day, value: -back, to: now)!)!
    }

    private func set(_ back: Int, _ weight: Double, _ reps: Int, minute: Int = 0) -> SetRecord {
        SetRecord(date: day(back).addingTimeInterval(Double(minute) * 60), weight: weight, reps: reps, rpe: 8)
    }

    // MARK: Calendar

    @Test func calendarHasTwelveWeeksEndingThisWeek() {
        let grid = TrainingCalendar(trainedOn: [day(0), day(2), day(2, hour: 7), day(80)], now: now, calendar: cal)
        #expect(grid.weeks.count == 12)
        #expect(grid.weeks.allSatisfy { $0.count == 7 })
        // Mondays down the first row.
        #expect(grid.weeks.allSatisfy { cal.component(.weekday, from: $0[0].date) == 2 })
        let days = grid.weeks.joined()
        #expect(days.filter(\.isToday).count == 1)
        #expect(days.first(where: \.isToday)?.trained == true)
        // Two workouts on one day count once; 80 days ago is off the grid.
        #expect(grid.trainedDays == 2)
        // Thursday to Sunday of this week haven't happened yet.
        #expect(grid.weeks.last?.filter(\.isFuture).count == 4)
    }

    @Test func thisMonthCountsOnlyThisMonth() {
        #expect(HistoryTotals.thisMonth([day(0), day(3), day(4), day(40)], now: now, calendar: cal) == 2)
    }

    @Test func compactNumbers() {
        #expect(HistoryTotals.compact(860) == "860")
        #expect(HistoryTotals.compact(8_140) == "8.1k")
        #expect(HistoryTotals.compact(283_400) == "283k")
        #expect(HistoryTotals.compact(1_250_000) == "1.2M" || HistoryTotals.compact(1_250_000) == "1.3M")
    }

    // MARK: Records

    @Test func recordsAreJudgedAgainstEarlierSetsOnly() {
        let sets = [set(14, 135, 8), set(7, 140, 8), set(7, 140, 8, minute: 3), set(0, 135, 12)]
        let events = RecordHistory.events(for: "Barbell bench press", sets: sets)
        // First time: nothing to beat. 140 is heavier; the same set again isn't a record;
        // 135 × 12 beats the estimated max of 140 × 8.
        #expect(events.map(\.kind) == [.heaviest, .estimatedMax])
        #expect(events.first?.set == sets[1])
    }

    @Test func bodyweightRecordsCountReps() {
        let sets = [SetRecord(date: day(9), weight: 0, reps: 12, rpe: 8), SetRecord(date: day(2), weight: 0, reps: 15, rpe: 8),
                    SetRecord(date: day(1), weight: 0, reps: 14, rpe: 8)]
        #expect(RecordHistory.events(for: "Push-up", sets: sets).map(\.kind) == [.mostReps])
    }

    @Test func recentRecordsKeepOnePerLiftPerDayNewestFirst() {
        let bench = [set(14, 135, 8), set(7, 140, 8), set(0, 145, 8), set(0, 145, 10, minute: 3)]
        let row = [set(10, 115, 8), set(3, 120, 8)]
        let recent = RecordHistory.recent(["Bench": bench, "Row": row], calendar: cal)
        #expect(recent.map(\.exercise) == ["Bench", "Row", "Bench"])
        // Today's best bench record is the 145 × 10, not both sets.
        #expect(recent.first?.set.reps == 10)
        #expect(RecordHistory.recent(["Bench": bench, "Row": row], limit: 1, calendar: cal).count == 1)
    }

    @Test func sessionRecordsAndMarkedSets() {
        let history = [set(7, 140, 8), set(0, 145, 8), set(0, 145, 6, minute: 3)]
        let today = Array(history.suffix(2))
        let marked = RecordHistory.brokenSets(["Bench": today], history: ["Bench": history])
        #expect(marked == [today[0]: .heaviest])
        #expect(RecordHistory.inSession(["Bench": today], history: ["Bench": history]).count == 1)
    }

    // MARK: Lift series

    @Test func seriesGroupsByDayAndFindsBestAndChange() {
        let sets = [set(70, 100, 8), set(35, 120, 8), set(28, 125, 8), set(28, 125, 6, minute: 3), set(0, 135, 8)]
        let series = LiftSeries(sets, calendar: cal)
        #expect(series.points.count == 4)
        #expect(series.isWeighted)
        #expect(series.points[2].sets.count == 2)
        #expect(series.points[2].volume == 125 * 14)
        #expect(series.best(.topWeight)?.topWeight == 135)
        #expect(series.change(.topWeight, overWeeks: 4, now: now, calendar: cal) == Double(10))
        #expect(series.change(.topWeight, overWeeks: 8, now: now, calendar: cal) == Double(35))
        #expect(series.change(.topWeight, overWeeks: 12, now: now, calendar: cal) == nil)
    }

    @Test func bodyweightSeriesChartsReps() {
        let series = LiftSeries([SetRecord(date: day(3), weight: 0, reps: 30, rpe: nil),
                                 SetRecord(date: day(3).addingTimeInterval(60), weight: 0, reps: 40, rpe: nil)], calendar: cal)
        #expect(!series.isWeighted)
        #expect(LiftMetric.options(weighted: series.isWeighted) == [.bestReps, .totalReps])
        #expect(series.latest?.value(.bestReps) == 40)
        #expect(series.latest?.value(.totalReps) == 70)
        #expect(series.latest?.topSet?.reps == 40)
    }

    @Test func bestTiesGoToTheFirstTime() {
        let series = LiftSeries([set(10, 135, 8), set(3, 135, 8)], calendar: cal)
        #expect(series.best(.topWeight)?.day == cal.startOfDay(for: day(10)))
    }
}
