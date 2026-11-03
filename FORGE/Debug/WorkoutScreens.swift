#if DEBUG
import SwiftUI

/// Demo screens for the workout flow (`-screen <name>`). Nil for names it doesn't know.
enum WorkoutScreens {
    @MainActor
    static func view(_ name: String) -> AnyView? {
        switch name {
        default: nil
        }
    }
}
#endif
