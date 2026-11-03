import SwiftUI

/// The last twelve weeks, a square per day: trained days in accent, today ringed.
/// Columns are weeks (oldest on the left), rows are weekdays.
struct TrainingHeatmap: View {
    let calendar: TrainingCalendar
    private let spacing: CGFloat = 4
    private let labelWidth: CGFloat = 12

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let first = calendar.weeks.first?.first.map { Calendar.current.component(.weekday, from: $0.date) } ?? 1
        VStack(alignment: .leading, spacing: spacing) {
            HStack(spacing: spacing) {
                Color.clear.frame(width: labelWidth, height: 14)
                ForEach(Array(calendar.weeks.enumerated()), id: \.offset) { i, week in monthLabel(i, week) }
            }
            ForEach(0..<7, id: \.self) { row in
                HStack(spacing: spacing) {
                    // Every other weekday, like most contribution calendars: all seven is too busy.
                    Text(row % 2 == 1 ? symbols[(first - 1 + row) % 7] : "")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.muted)
                        .frame(width: labelWidth, alignment: .leading)
                    ForEach(Array(calendar.weeks.enumerated()), id: \.offset) { _, week in
                        if week.indices.contains(row) { cell(week[row]) }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trained \(calendar.trainedDays) days in the last \(calendar.weeks.count) weeks")
    }

    /// The month's name over the week its 1st falls in. The first column is labelled too,
    /// unless a new month starts close enough that the two names would collide.
    private func monthLabel(_ i: Int, _ week: [TrainingCalendar.Day]) -> some View {
        let cal = Calendar.current
        func firstOfMonth(_ w: [TrainingCalendar.Day]) -> Date? { w.first { cal.component(.day, from: $0.date) == 1 }?.date }
        let soon = calendar.weeks.prefix(3).dropFirst().contains { firstOfMonth($0) != nil }
        let date = firstOfMonth(week) ?? (i == 0 && !soon ? week.last?.date : nil)
        return Color.clear.frame(maxWidth: .infinity).frame(height: 14)
            .overlay(alignment: .leading) {
                if let date {
                    Text(date.formatted(.dateTime.month(.abbreviated)))
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
                        .fixedSize()
                }
            }
    }

    private func cell(_ day: TrainingCalendar.Day) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(day.trained ? Theme.accent : (day.isFuture ? Theme.raised.opacity(0.3) : Theme.raised.opacity(0.75)))
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if day.isToday {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Theme.text, lineWidth: 2)
                        .padding(-2)
                }
            }
    }
}
