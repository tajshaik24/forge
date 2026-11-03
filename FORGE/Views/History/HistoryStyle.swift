import SwiftUI
import UIKit

/// Gold means a personal best, and only that: accent is "done", gold is "better than ever".
/// A warm yellow-gold (never orange) that keeps contrast on chalk and on slate.
enum Gold {
    /// Trophy and chart mark.
    static let fill = dynamic(light: 0xB98A12, dark: 0xE9BE48)
    /// Gold copy on ground or surface.
    static let text = dynamic(light: 0x7A5A00, dark: 0xF1CD66)
    /// Row and tag backgrounds.
    static let wash = dynamic(light: 0xFAF0D2, dark: 0x2C2614)
    static let edge = dynamic(light: 0xE9D395, dark: 0x5A4A1C)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        func rgb(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) })
    }
}

/// "PB" with a trophy, for a set or chart point that's a personal best.
struct TrophyTag: View {
    var text = "PB"
    var body: some View {
        Label(text, systemImage: "trophy.fill")
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(Gold.text)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Gold.wash, in: Capsule())
            .overlay(Capsule().stroke(Gold.edge))
            .fixedSize()
    }
}

/// A number over its label, for stat grids. The number never wraps: it shrinks first.
struct StatTile: View {
    let value: String
    let label: String
    var unit: String? = nil
    var tint: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(Theme.mono(20)).foregroundStyle(tint)
                if let unit { Text(unit).font(Theme.mono(11, .medium)).foregroundStyle(Theme.muted) }
            }
            .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension SetRecord {
    init(_ entry: SetEntry) { self.init(date: entry.date, weight: entry.weight, reps: entry.reps, rpe: entry.rpe) }
}

extension PersonalRecords.Kind {
    /// Short form for tags and rows. A timed hold's "most reps" is its longest time.
    func short(_ exercise: String) -> String {
        switch self {
        case .heaviest: "Heaviest"
        case .estimatedMax: "Best est. max"
        case .mostReps: ExerciseCatalog.named(exercise)?.isTimed == true ? "Longest" : "Most reps"
        }
    }

    func long(_ exercise: String) -> String {
        self == .mostReps && ExerciseCatalog.named(exercise)?.isTimed == true ? "Longest hold" : rawValue
    }
}

/// "135 lb × 8", "× 12", "45 s": how a set reads anywhere in History.
enum SetText {
    static func of(_ set: SetRecord, exercise: String, unit: WeightUnit) -> String {
        let timed = ExerciseCatalog.named(exercise)?.isTimed ?? false
        if set.weight == 0 { return timed ? "\(set.reps) s" : "\(set.reps) reps" }
        return "\(unit.format(pounds: set.weight)) × \(set.reps)\(timed ? " s" : "")"
    }
}
