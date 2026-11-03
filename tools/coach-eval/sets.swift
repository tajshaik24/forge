import Foundation

/// The between-set coach: rewording the rules' note during rest, and the recap after a lift.
enum SetEval {
    static let notes = [
        ("Barbell bench press", "Easy at 8 reps: try 160 lb for set 2."),
        ("Barbell bench press", "Hard at 6 reps: 145 lb for set 3."),
        ("Inverted row", "Same again on set 2."),
        ("Back squat", "5 reps is short of 6: 185 lb for set 3."),
        ("Lat pulldown", "Right on target: 110 lb again for set 3."),
        ("Pull-up", "Easy: go for 7 reps on set 2."),
        ("Plank", "Easy: go for 50s on set 2."),
        ("Dumbbell curl", "Hard but you got 12: hold 25 lb for set 3."),
    ]

    @MainActor
    static func run() async {
        SetCoach.shared.prewarm()
        var kept = 0
        for (lift, note) in notes {
            let start = Date()
            let text = await SetCoach.shared.reword(note, lift: lift, within: 60)
            if text != nil { kept += 1 }
            print("REWORD \(lift): \(note)\n   -> \(text ?? "(rule text kept)") (\(String(format: "%.1f", Date().timeIntervalSince(start)))s)")
        }
        print("\(kept) of \(notes.count) rewordings used")
        let recap = await SetCoach.shared.recap(lift: "Barbell bench press", sets: ["155 lb × 8, Good", "160 lb × 8, Hard", "160 lb × 7, Hard"], within: 60)
        print("RECAP -> \(recap ?? "(none)")")
    }
}
