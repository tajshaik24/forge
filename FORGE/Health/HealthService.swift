import Foundation
import HealthKit

/// Reads the recovery signals the coach uses. Everything stays on device.
enum HealthService {
    @MainActor
    static func snapshot(store: HKHealthStore? = nil) async -> HealthSnapshot {
        guard HKHealthStore.isHealthDataAvailable() else { return HealthSnapshot() }
        let store = store ?? WorkoutTracker.shared.store
        async let sleep = lastNightSleepHours(store)
        async let hrv = hrvToday(store)
        async let baseline = hrvBaseline(store)
        async let today = steps(on: .now, store: store)
        async let yesterday = steps(on: Calendar.current.date(byAdding: .day, value: -1, to: .now)!, store: store)
        return await HealthSnapshot(sleepHours: sleep, hrv: hrv, hrvBaseline: baseline,
                                    stepsToday: today, stepsYesterday: yesterday)
    }

    // MARK: Steps

    static let stepGoal = 10_000

    /// Total steps on one day (so far, for today). Nil when Health has none, or no access.
    static func steps(on day: Date, store: HKHealthStore? = nil) async -> Int? {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let total = await stepBuckets(from: start, to: end, every: DateComponents(day: 1), store: store)
            .reduce(0) { $0 + $1.steps }
        return total > 0 ? total : nil
    }

    /// Steps per interval: per hour for a day's chart, per day for the week. Health merges
    /// the iPhone's and the Watch's counts so a step is only counted once.
    static func stepBuckets(from start: Date, to end: Date, every interval: DateComponents,
                            store: HKHealthStore? = nil) async -> [(start: Date, steps: Int)] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let store = store ?? WorkoutTracker.shared.store
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.stepCount),
                                       predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .cumulativeSum, anchorDate: start, intervalComponents: interval)
        guard let collection = try? await query.result(for: store) else { return [] }
        var buckets: [(start: Date, steps: Int)] = []
        collection.enumerateStatistics(from: start, to: end) { stats, _ in
            buckets.append((stats.startDate, Int(stats.sumQuantity()?.doubleValue(for: .count()) ?? 0)))
        }
        return buckets
    }

    private static func lastNightSleepHours(_ store: HKHealthStore) async -> Double? {
        let end = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -20, to: end)!
        let predicate = HKSamplePredicate.categorySample(
            type: HKCategoryType(.sleepAnalysis),
            predicate: HKQuery.predicateForSamples(withStart: start, end: end))
        let query = HKSampleQueryDescriptor(predicates: [predicate], sortDescriptors: [])
        guard let samples = try? await query.result(for: store), !samples.isEmpty else { return nil }
        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        // A Watch, the iPhone and sleep apps can all record the same night: merge overlaps so it counts once.
        let intervals = samples.filter { asleep.contains($0.value) }
            .map { ($0.startDate, $0.endDate) }
            .sorted { $0.0 < $1.0 }
        var seconds = 0.0
        var current: (start: Date, end: Date)?
        for (start, end) in intervals {
            if let c = current, start <= c.end {
                current = (c.start, max(c.end, end))
            } else {
                if let c = current { seconds += c.end.timeIntervalSince(c.start) }
                current = (start, end)
            }
        }
        if let c = current { seconds += c.end.timeIntervalSince(c.start) }
        return seconds > 0 ? seconds / 3600 : nil
    }

    private static func hrvToday(_ store: HKHealthStore) async -> Double? {
        await averageHRV(store, days: 1)
    }

    private static func hrvBaseline(_ store: HKHealthStore) async -> Double? {
        await averageHRV(store, days: 30)
    }

    private static func averageHRV(_ store: HKHealthStore, days: Int) async -> Double? {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end)!
        let predicate = HKSamplePredicate.quantitySample(
            type: HKQuantityType(.heartRateVariabilitySDNN),
            predicate: HKQuery.predicateForSamples(withStart: start, end: end))
        let query = HKSampleQueryDescriptor(predicates: [predicate], sortDescriptors: [])
        guard let samples = try? await query.result(for: store), !samples.isEmpty else { return nil }
        let ms = HKUnit.secondUnit(with: .milli)
        return samples.map { $0.quantity.doubleValue(for: ms) }.reduce(0, +) / Double(samples.count)
    }
}
