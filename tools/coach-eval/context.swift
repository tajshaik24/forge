import Foundation

/// An intermediate lifter mid-way through a pull-up goal, with a knee note and some history.
enum EvalContext {
    static func make() -> CoachContext {
        var c = CoachContext(date: .now, isTrainingDay: true, trainingDaysThisWeek: 4, split: .coachDecides,
                             goal: "Build muscle", minutes: 45, gymName: "Commercial gym", equipment: Set(Equipment.allCases),
                             notes: [NoteSnapshot(said: "My left knee aches on deep squats", rule: "No deep knee bends under load", avoid: [.deepKneeBend])],
                             recent: [], readiness: [:], health: HealthSnapshot(), currentPlan: nil)
        c.goals = [SkillGoal(target: "Pull-up", step: 0, passes: 1)]
        let d = Date.now
        func day(_ n: Int) -> Date { d.addingTimeInterval(Double(-n) * 86_400) }
        c.history = [
            "Barbell bench press": [SetRecord(date: day(3), weight: 155, reps: 8, rpe: 8), SetRecord(date: day(3), weight: 155, reps: 8, rpe: 8), SetRecord(date: day(3), weight: 155, reps: 7, rpe: 9)],
            "Barbell deadlift": [SetRecord(date: day(5), weight: 225, reps: 5, rpe: 8), SetRecord(date: day(5), weight: 225, reps: 5, rpe: 8)],
            "Inverted row": [SetRecord(date: day(2), weight: 0, reps: 12, rpe: 8), SetRecord(date: day(2), weight: 0, reps: 11, rpe: 8), SetRecord(date: day(2), weight: 0, reps: 10, rpe: 9)],
        ]
        c.currentPlan = PlannedWorkout(date: .now, focus: "Pull", muscles: [.back, .biceps], minutes: 45,
            reasons: [], exercises: [
                PlannedExercise(name: "Inverted row", sets: 3, reps: "6-12", target: LoadTarget(weight: 0, reps: 12, note: "Match 12 reps"), goal: "Step 1 of 4 toward a pull-up"),
                PlannedExercise(name: "Lat pulldown", sets: 3, reps: "8-12", target: LoadTarget(weight: 110, reps: 10, note: "Same as last time")),
                PlannedExercise(name: "Seated cable row", sets: 3, reps: "10-12", target: LoadTarget(weight: 100, reps: 10, note: "Same as last time")),
                PlannedExercise(name: "Dumbbell curl", sets: 3, reps: "10-15", target: LoadTarget(weight: 25, reps: 12, note: "Same as last time")),
            ], restSeconds: 90, gymName: "Commercial gym", engine: "AI Coach")
        return c
    }
}

/// Stand-ins for the SwiftData models the coach code mentions; the eval never builds them.
final class SetEntry { var exercise = ""; var weight = 0.0; var reps = 0; var rpe: Int?; var date = Date.now }
final class WorkoutSession { var sets: [SetEntry]? = []; var date = Date.now; var focus = "" }
