import SwiftUI
import WidgetKit

/// Watch-face complications: today's workout and your week streak.
@main
struct FORGEWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        StreakWidget()
    }
}
