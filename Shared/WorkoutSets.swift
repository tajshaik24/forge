import Foundation

/// The sets of the workout under way, gathered from everywhere they can be on one device, each counted once.
///
/// On the Watch a set can be in three places: the sets logged here this workout (`own`), the sets the
/// other device sent (`remote`), and the store (`stored`), which holds sets saved here when the iPhone
/// couldn't be reached and, once iCloud syncs, copies of sets from both devices. `own` and `remote` never
/// overlap; a stored set that matches one of them (same lift, weight and reps, saved within `tolerance`)
/// is that set again. Matching is one-to-one, so two real sets of 135×8 a minute apart both count.
enum WorkoutSets {
    static func combine(own: [WorkoutProgress.DoneSet], remote: [WorkoutProgress.DoneSet],
                        stored: [WorkoutProgress.DoneSet], since start: Date?,
                        tolerance: TimeInterval = 90) -> [WorkoutProgress.DoneSet] {
        // Sets from an earlier workout today (an open session left behind) aren't part of this one.
        let floor = start.map { $0.addingTimeInterval(-tolerance) } ?? .distantPast
        var known = (own + remote).filter { $0.date >= floor }
        var unmatched = known
        for set in stored.sorted(by: { $0.date < $1.date }) where set.date >= floor {
            let twins = unmatched.indices.filter { unmatched[$0].isSame(as: set, within: tolerance) }
            if let nearest = twins.min(by: { abs(unmatched[$0].date.timeIntervalSince(set.date))
                                             < abs(unmatched[$1].date.timeIntervalSince(set.date)) }) {
                unmatched.remove(at: nearest)
            } else {
                known.append(set)
            }
        }
        return known.sorted { $0.date < $1.date }
    }

    /// The lift to move to when skipping `index`: the next unfinished one after it, then any earlier
    /// one left undone. Nil when every other lift is done.
    static func lift(after index: Int, in progress: WorkoutProgress) -> Int? {
        let lifts = progress.lifts.indices
        return (lifts.filter { $0 > index } + lifts.filter { $0 < index }).first { !progress.lifts[$0].isDone }
    }

    /// Where to pick up a workout that's already under way: the lift of the last set logged if it still
    /// has sets to do, else the next unfinished one. Nil when everything is done.
    static func resumeLift(in progress: WorkoutProgress, sets: [WorkoutProgress.DoneSet]) -> Int? {
        let last = sets.max { $0.date < $1.date }
        let at = last.flatMap { set in progress.lifts.firstIndex { $0.exercise.name == set.exercise } } ?? 0
        return progress.current(from: at)
    }
}

extension WorkoutProgress.DoneSet {
    init(_ set: LoggedSet) {
        self.init(exercise: set.exercise, weight: set.weight, reps: set.reps, rpe: set.rpe, date: set.end)
    }

    func isSame(as other: Self, within tolerance: TimeInterval) -> Bool {
        exercise == other.exercise && abs(weight - other.weight) < 0.01 && reps == other.reps
            && abs(date.timeIntervalSince(other.date)) <= tolerance
    }
}
