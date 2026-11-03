#if DEBUG
import SwiftUI

/// Demo screens for history, progress and Today (`-screen <name>`). Nil for names it doesn't know.
enum HistoryScreens {
    @MainActor
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: nil
        }
    }
}
#endif
