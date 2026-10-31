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
        return await HealthSnapshot(sleepHours: sleep, hrv: hrv, hrvBaseline: baseline)
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
