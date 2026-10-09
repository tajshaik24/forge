import SwiftUI

/// FORGE look: dark iron ground, one ember accent, condensed display type.
enum Theme {
    static let ground = Color(red: 0.055, green: 0.059, blue: 0.067)       // #0E0F11
    static let surface = Color(red: 0.102, green: 0.110, blue: 0.122)      // #1A1C1F
    static let raised = Color(red: 0.149, green: 0.161, blue: 0.180)       // #26292E
    static let hairline = Color(red: 0.165, green: 0.176, blue: 0.196)     // #2A2D32
    static let text = Color(red: 0.949, green: 0.941, blue: 0.922)         // #F2F0EB
    static let muted = Color(red: 0.639, green: 0.655, blue: 0.682)        // #A3A7AE
    static let ember = Color(red: 1.0, green: 0.420, blue: 0.173)          // #FF6B2C
    static let emberSoft = Color(red: 1.0, green: 0.690, blue: 0.514)      // #FFB083
    static let emberWash = Color(red: 0.133, green: 0.094, blue: 0.059)    // #22180F
    static let onEmber = Color(red: 0.067, green: 0.071, blue: 0.078)      // #111214

    static func display(_ size: CGFloat) -> Font { Font.system(size: size, weight: .black).width(.compressed) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .monospaced) }
    static let label = Font.system(size: 12, weight: .bold)

    /// Recovered muscles glow brighter; fatigued ones go dark (single-hue so it reads without color vision).
    static func readiness(_ value: Double) -> Color {
        switch value {
        case 0.85...: Color(red: 1.0, green: 0.541, blue: 0.298)
        case 0.7..<0.85: Color(red: 0.878, green: 0.459, blue: 0.208)
        case 0.55..<0.7: Color(red: 0.710, green: 0.396, blue: 0.180)
        default: Color(red: 0.541, green: 0.306, blue: 0.165)
        }
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

struct EmberButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .heavy))
            .foregroundStyle(Theme.onEmber)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.ember.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
    }
}

struct NoteChip: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.emberSoft)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.emberWash, in: Capsule())
            .overlay(Capsule().stroke(Theme.ember.opacity(0.35)))
    }
}
