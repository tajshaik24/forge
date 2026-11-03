import SwiftUI

extension View {
    /// Debug builds launched with `-scroll <0...1 | bottom>` start long screens scrolled that far,
    /// so the simulator can screenshot parts you'd otherwise have to swipe to. No effect otherwise.
    @ViewBuilder
    func demoScrollAnchor() -> some View {
        #if DEBUG
        if let raw = DemoArgs.value("-scroll") {
            defaultScrollAnchor(raw == "bottom" ? .bottom : UnitPoint(x: 0.5, y: Double(raw) ?? 0))
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if DEBUG
enum DemoArgs {
    /// The argument after `flag` on a `-demo` launch.
    static func value(_ flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-demo"), let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }
}
#endif
