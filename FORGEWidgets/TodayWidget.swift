import SwiftUI
import WidgetKit

// Shared by the iPhone widgets and the Watch complications. Both read the snapshot their app
// writes to the App Group; tapping one opens FORGE.

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    /// The snapshot, if it's for this entry's day. At midnight yesterday's plan stops counting.
    var today: WidgetSnapshot? {
        snapshot.flatMap { Calendar.current.isDate($0.day, inSameDayAs: date) ? $0 : nil }
    }
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .sample : WidgetSnapshot.load() ?? .sample))
    }

    /// Now, then again at midnight (a new day, and maybe a new week for the streak). The app also
    /// reloads the timeline whenever the plan or your history changes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        completion(Timeline(entries: [SnapshotEntry(date: .now, snapshot: snapshot),
                                      SnapshotEntry(date: midnight, snapshot: snapshot)],
                            policy: .after(midnight)))
    }
}

// MARK: - Today

/// Today's workout: focus, lifts and length, or a rest day and when you train next.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Today", provider: SnapshotProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's workout")
        .description("What the coach planned for today.")
        #if os(watchOS)
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .accessoryCorner])
        #else
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
        #endif
    }
}

struct TodayWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var title: String {
        guard let today = entry.today else { return "Plan today" }
        return today.isRestDay ? "Rest day" : today.focus
    }

    private var detail: String {
        guard let today = entry.today else { return "Open FORGE" }
        return today.isRestDay ? (today.nextLabel ?? "Recover today") : today.summary
    }

    var body: some View {
        content.containerBackground(Theme.ground, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Label(entry.today.map { $0.isRestDay ? "Rest day" : "\($0.focus) · \($0.minutes) min" } ?? "Plan today",
                  systemImage: "dumbbell.fill")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("FORGE", systemImage: "dumbbell.fill").font(.system(size: 12, weight: .heavy))
                    .widgetAccentable()
                Text(title).font(.headline).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "dumbbell.fill").font(.system(size: 15)).widgetAccentable()
                    if let today = entry.today, !today.isRestDay {
                        Text("\(today.minutes)m").font(.system(size: 12, weight: .bold))
                    }
                }
            }
        #if os(watchOS)
        case .accessoryCorner:
            Image(systemName: "dumbbell.fill").font(.system(size: 20)).widgetAccentable()
                .widgetLabel(title)
        #endif
        case .systemMedium:
            HStack(alignment: .top, spacing: 16) {
                summary
                if let lifts = entry.today?.lifts, !lifts.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(lifts.prefix(4), id: \.self) { lift in
                            Text(lift).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        }
                        if lifts.count > 4 {
                            Text("+\(lifts.count - 4) more").font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        default:
            summary
        }
    }

    /// The small widget, and the left half of the medium one.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TODAY").font(Theme.label).foregroundStyle(Theme.muted)
            Text(title.uppercased()).font(Theme.display(22)).foregroundStyle(Theme.text)
                .lineLimit(2).minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
            if let streak = entry.snapshot?.streak(on: entry.date), streak > 0 {
                Label("\(streak)-week streak", systemImage: "flame.fill")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accentText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Streak

/// Weeks in a row you've trained, as a round Lock Screen or watch-face badge.
struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Streak", provider: SnapshotProvider()) { entry in
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -2) {
                    Text("\(entry.snapshot?.streak(on: entry.date) ?? 0)").font(.system(size: 22, weight: .heavy)).widgetAccentable()
                    Text("WK").font(.system(size: 9, weight: .bold))
                }
            }
            .containerBackground(Theme.ground, for: .widget)
        }
        .configurationDisplayName("Week streak")
        .description("Weeks in a row with at least one workout.")
        .supportedFamilies([.accessoryCircular])
    }
}
