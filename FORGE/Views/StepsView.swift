import SwiftUI
import Charts

/// Today's steps from Apple Health, toward a 10,000-step day. Tap for the hour-by-hour and the week.
struct StepsCard: View {
    @State private var steps: Int?
    @State private var yesterday: Int?

    private var goal: Int { HealthService.stepGoal }
    private var fraction: Double { min(1, Double(steps ?? 0) / Double(goal)) }

    var body: some View {
        NavigationLink { StepsView() } label: {
            Card {
                HStack {
                    Text("STEPS · TODAY").font(Theme.mono(11)).foregroundStyle(Theme.accentText)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                }
                // The count gets the row to itself and shrinks rather than wrap ("11,80" / "1").
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text((steps ?? 0).formatted())
                            .font(Theme.display(34)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Text(steps.map { $0 >= goal ? "Goal reached" : "of \(goal.formatted())" } ?? "of \(goal.formatted())")
                            .font(.system(size: 13)).foregroundStyle((steps ?? 0) >= goal ? Theme.accentText : Theme.muted)
                            .lineLimit(1)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                    if let yesterday {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(yesterday.formatted()).font(Theme.mono(15)).foregroundStyle(Theme.text.opacity(0.85))
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text("Yesterday").font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                ProgressView(value: fraction).tint(Theme.accent)
                if steps == nil {
                    Text("No steps yet today. If that's wrong, allow FORGE to read Steps in the Health app.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        // Counts keep coming in from the iPhone and the Watch: refresh every minute while it's on screen.
        .task {
            while !Task.isCancelled {
                async let today = StepData.steps(on: .now)
                async let before = StepData.steps(on: Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
                (steps, yesterday) = await (today, before)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}

struct StepsView: View {
    @State private var hours: [(start: Date, steps: Int)] = []
    @State private var days: [(start: Date, steps: Int)] = []

    private var today: Int { hours.reduce(0) { $0 + $1.steps } }
    private var goal: Int { HealthService.stepGoal }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(today.formatted()).font(Theme.display(52)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(today >= goal ? "Goal reached" : "\((goal - today).formatted()) to \(goal.formatted())")
                        .foregroundStyle(today >= goal ? Theme.accentText : Theme.muted)
                }

                Card {
                    SectionLabel("Today by hour")
                    Chart(hours, id: \.start) { hour in
                        BarMark(x: .value("Hour", hour.start, unit: .hour), y: .value("Steps", hour.steps))
                            .foregroundStyle(Theme.accent)
                            .cornerRadius(2)
                    }
                    .chartXScale(domain: Calendar.current.startOfDay(for: .now)...Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .hour, count: 6)) {
                            AxisGridLine().foregroundStyle(Theme.hairline)
                            AxisValueLabel(format: .dateTime.hour()).foregroundStyle(Theme.muted)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                            AxisGridLine().foregroundStyle(Theme.hairline)
                            AxisValueLabel().foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(height: 160)
                }

                Card {
                    SectionLabel("Last 7 days")
                    Chart {
                        ForEach(days, id: \.start) { day in
                            BarMark(x: .value("Day", day.start, unit: .day), y: .value("Steps", day.steps))
                                .foregroundStyle(day.steps >= goal ? Theme.accent : Theme.accent.opacity(0.4))
                                .cornerRadius(3)
                        }
                        RuleMark(y: .value("Goal", goal))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(Theme.muted)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) {
                            AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true).foregroundStyle(Theme.muted)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                            AxisGridLine().foregroundStyle(Theme.hairline)
                            AxisValueLabel().foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(height: 160)
                    let average = days.isEmpty ? 0 : days.reduce(0) { $0 + $1.steps } / days.count
                    Text("Average \(average.formatted()) a day").font(.system(size: 13)).foregroundStyle(Theme.muted)
                }

                Text("After a long walking day (15,000+ steps, or 12,000 before you train), the coach trims a set from each leg lift.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .background(Theme.ground)
        .navigationTitle("Steps")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                let cal = Calendar.current
                let start = cal.startOfDay(for: .now)
                let tomorrow = cal.date(byAdding: .day, value: 1, to: start)!
                hours = await StepData.buckets(from: start, to: tomorrow, every: DateComponents(hour: 1))
                days = await StepData.buckets(from: cal.date(byAdding: .day, value: -6, to: start)!, to: tomorrow,
                                              every: DateComponents(day: 1))
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}

/// Steps from Health, or made-up but plausible numbers on a `-demo` launch (the simulator has none).
private enum StepData {
    static func steps(on day: Date) async -> Int? {
        #if DEBUG
        if Demo.isOn { return Calendar.current.isDateInToday(day) ? 11_801 : 9_420 }
        #endif
        return await HealthService.steps(on: day)
    }

    static func buckets(from start: Date, to end: Date, every interval: DateComponents) async -> [(start: Date, steps: Int)] {
        #if DEBUG
        if Demo.isOn {
            let cal = Calendar.current
            if interval.hour != nil {
                let shape = [0, 0, 0, 0, 0, 0, 120, 640, 1300, 420, 380, 900, 1500, 600, 350, 420, 980, 1700, 1250, 640, 380, 150, 71, 0]
                return shape.enumerated().compactMap { i, n in cal.date(byAdding: .hour, value: i, to: start).map { ($0, n) } }
            }
            let week = [8200, 12_400, 6900, 10_300, 9420, 7600, 11_801]
            return week.enumerated().compactMap { i, n in cal.date(byAdding: .day, value: i, to: start).map { ($0, n) } }
        }
        #endif
        return await HealthService.stepBuckets(from: start, to: end, every: interval)
    }
}
