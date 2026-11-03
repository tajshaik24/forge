import SwiftUI
import UIKit

/// Colours and controls only the workout screen uses, on top of `Theme`.
enum WorkoutStyle {
    /// Personal records: a warm gold, never orange. Text and wash pass 4.5:1 in both appearances.
    static let gold = Color(lightHex: 0x7A5A00, darkHex: 0xEBC85A)
    static let goldIcon = Color(lightHex: 0xA67C00, darkHex: 0xEBC85A)
    static let goldWash = Color(lightHex: 0xFBF0C9, darkHex: 0x2B2410)
    /// The tick on a gold circle: white on the deep gold, near-black on the bright one.
    static let onGold = Color(lightHex: 0xFFFFFF, darkHex: 0x2B2410)
    static let heart = Color(lightHex: 0xD12C44, darkHex: 0xFF6175)
}

extension Color {
    /// Resolves per appearance, like Theme's colours.
    init(lightHex: UInt32, darkHex: UInt32) {
        func color(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? color(darkHex) : color(lightHex) })
    }
}

/// A secondary action: ink on the raised chalk, a full 44 pt tall.
struct RaisedButtonStyle: ButtonStyle {
    var fill: Color = Theme.raised

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 8)
            .background(fill.opacity(configuration.isPressed ? 0.6 : 1), in: Capsule())
            .contentShape(Capsule())
    }
}

// MARK: - Header

/// Pinned above the cards: what you're doing, how long, your heart rate, how far through, and the way out.
struct WorkoutHeader: View {
    let title: String
    let start: Date
    let heartRate: Double
    let onWatch: Bool
    let startingOnWatch: Bool
    let progress: WorkoutProgress
    let finishing: Bool
    let onCancel: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 44, height: 44)
                        .background(Theme.raised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel workout")

                VStack(spacing: 3) {
                    Text(title.uppercased()).font(Theme.display(17)).foregroundStyle(Theme.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    stats
                }
                .frame(maxWidth: .infinity)

                Button(action: onFinish) {
                    ZStack {
                        Text("Finish").opacity(finishing ? 0 : 1)
                        if finishing { ProgressView().tint(Theme.onAccent) }
                    }
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.onAccent)
                    .frame(minWidth: 84, minHeight: 44)
                    .background(Theme.accent, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(finishing)
                .accessibilityLabel(finishing ? "Saving workout" : "Finish workout")
            }

            if progress.setsPlanned > 0 {
                HStack(spacing: 10) {
                    bar
                Text("\(progress.setsDone)/\(progress.setsPlanned) sets · \(Int((progress.fraction * 100).rounded()))%")
                    .font(Theme.mono(12)).foregroundStyle(Theme.muted)
                    .fixedSize()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(progress.setsDone) of \(progress.setsPlanned) sets done")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(Theme.ground)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private var stats: some View {
        HStack(spacing: 12) {
            Text(timerInterval: start...start.addingTimeInterval(6 * 3600), countsDown: false)
                .monospacedDigit().fixedSize()
                .accessibilityLabel("Time")
            HStack(spacing: 4) {
                Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(WorkoutStyle.heart)
                Text(heartRate > 0 ? "\(Int(heartRate.rounded()))" : "--").monospacedDigit()
                    .foregroundStyle(heartRate > 0 ? Theme.text : Theme.muted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(heartRate > 0 ? "Heart rate \(Int(heartRate.rounded()))" : "No heart rate")
            if startingOnWatch {
                Label("Starting…", systemImage: "applewatch").labelStyle(.titleAndIcon)
            } else if onWatch {
                Image(systemName: "applewatch").foregroundStyle(Theme.accentText)
                    .accessibilityLabel("Shared with Apple Watch")
            }
        }
        .font(Theme.mono(13))
        .foregroundStyle(Theme.muted)
        .lineLimit(1)
    }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.raised)
                Capsule().fill(Theme.accent)
                    .frame(width: progress.setsDone == 0 ? 0 : max(6, geo.size.width * progress.fraction))
            }
        }
        .frame(height: 6)
        .animation(.snappy, value: progress.fraction)
    }
}

// MARK: - Rest

/// The rest countdown as a capsule floating over the bottom of the list, so the sets stay in view.
struct RestBar: View {
    let until: Date
    let next: String
    let extend: () -> Void
    let skip: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("REST").font(Theme.label).tracking(1).foregroundStyle(Theme.accentText)
                    Text(timerInterval: Date.now...max(until, .now), countsDown: true)
                        .font(Theme.mono(24)).monospacedDigit().foregroundStyle(Theme.text)
                        .fixedSize()
                }
                Text(next).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button("+30 s", action: extend)
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                .frame(width: 64, height: 44)
                .background(Theme.raised, in: Capsule())
                .contentShape(Capsule())
                .accessibilityLabel("Add 30 seconds of rest")
            Button("Skip", action: skip)
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.onAccent)
                .frame(width: 64, height: 44)
                .background(Theme.accent, in: Capsule())
                .contentShape(Capsule())
                .accessibilityLabel("Skip rest")
        }
        .padding(.leading, 20).padding(.trailing, 8).padding(.vertical, 8)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.hairline))
        .shadow(color: .black.opacity(0.14), radius: 16, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Toast

struct RecordToast: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "trophy.fill")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(WorkoutStyle.gold)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(WorkoutStyle.goldWash, in: Capsule())
            .overlay(Capsule().stroke(WorkoutStyle.goldIcon.opacity(0.4)))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.updatesFrequently)
    }
}
