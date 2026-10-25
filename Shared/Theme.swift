import SwiftUI

/// FORGE look ("Chalk"): chalk-white ground and ink type in light mode, chalk on slate in dark,
/// one cobalt accent, expanded display type. The Watch always uses the dark values.
enum Theme {
    static let ground = Color(light: 0xF4F2EC, dark: 0x101318)
    static let surface = Color(light: 0xFFFFFF, dark: 0x191D24)
    static let raised = Color(light: 0xE3DFD5, dark: 0x242933)
    static let hairline = Color(light: 0xDCD8CE, dark: 0x2C323C)
    static let text = Color(light: 0x16171A, dark: 0xF4F2EC)
    static let muted = Color(light: 0x5E6066, dark: 0x9EA4AF)
    static let accent = Color(light: 0x2443C9, dark: 0x4A68F2)
    static let accentText = Color(light: 0x2443C9, dark: 0x9DB0FF)   // accent-coloured copy on ground/surface
    static let accentWash = Color(light: 0xE6EAFB, dark: 0x172038)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0xFFFFFF)

    static func display(_ size: CGFloat) -> Font { Font.system(size: size, weight: .heavy).width(.expanded) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .monospaced) }
    static let label = Font.system(size: 12, weight: .bold)

    /// Recovered muscles are the strongest cobalt; fatigued ones recede into the ground
    /// (single-hue, stepped by lightness, so it reads without color vision).
    static func readiness(_ value: Double) -> Color {
        switch value {
        case 0.85...: Color(light: 0x2443C9, dark: 0xA3B4FF)
        case 0.7..<0.85: Color(light: 0x4C66D4, dark: 0x7089F5)
        case 0.55..<0.7: Color(light: 0x7F92DF, dark: 0x4A5FC4)
        default: Color(light: 0xAEBAEA, dark: 0x34428A)
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// Resolves per appearance on iOS; watchOS has no light mode, so it takes the dark value.
    init(light: UInt32, dark: UInt32) {
        #if os(watchOS)
        self.init(hex: dark)
        #else
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
        #endif
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(Theme.label).tracking(1).foregroundStyle(Theme.muted)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.hairline))
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .heavy))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
    }
}

struct NoteChip: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.accentWash, in: Capsule())
            .overlay(Capsule().stroke(Theme.accent.opacity(0.35)))
    }
}
