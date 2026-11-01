import SwiftUI
import Charts

/// Today's steps from Apple Health, toward a 10,000-step day. Tap for the hour-by-hour and the week.
struct StepsCard: View {
    @State private var steps: Int?
    @State private var yesterday: Int?

    private var goal: Int { HealthService.stepGoal }

    var body: some View {
        NavigationLink { StepsView() } label: {
            Card {
                HStack {
                    Text("STEPS · TODAY").font(Theme.mono(11)).foregroundStyle(Theme.accentText)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text((steps ?? 0).formatted()).font(Theme.display(36)).monospacedDigit()
                    Text("of \(goal.formatted())").font(.system(size: 14)).foregroundStyle(Theme.muted)
                    Spacer()
                    if let yesterday {
                        Text("Yesterday \(yesterday.formatted())").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                }
                ProgressView(value: min(1, Double(steps ?? 0) / Double(goal))).tint(Theme.accent)
                if steps == nil {
                    Text("No steps yet today. If that's wrong, allow FORGE to read Steps in the Health app.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
        }
        .buttonStyle(.plain)
        // Counts keep coming in from the iPhone and the Watch: refresh every minute while it's on screen.
        .task {
            while !Task.isCancelled {
                async let today = HealthService.steps(on: .now)
                async let before = HealthService.steps(on: Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
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
                    Text(today >= goal ? "Goal reached" : "\((goal - today).formatted()) to \(goal.formatted())")
                        .foregroundStyle(Theme.muted)
                }

                Card {
                    SectionLabel("Today by hour")
                    Chart(hours, id: \.start) { hour in
                        BarMark(x: .value("Hour", hour.start, unit: .hour), y: .value("Steps", hour.steps))
                            .foregroundStyle(Theme.accent)
                    }
                    .chartXScale(domain: Calendar.current.startOfDay(for: .now)...Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!)
                    .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { AxisValueLabel(format: .dateTime.hour()) } }
                    .frame(height: 160)
                }

                Card {
                    SectionLabel("Last 7 days")
                    Chart {
                        ForEach(days, id: \.start) { day in
                            BarMark(x: .value("Day", day.start, unit: .day), y: .value("Steps", day.steps))
                                .foregroundStyle(day.steps >= goal ? Theme.accent : Theme.accent.opacity(0.45))
                        }
                        RuleMark(y: .value("Goal", goal))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(Theme.muted)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .day)) { AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                    .frame(height: 160)
                    let average = days.isEmpty ? 0 : days.reduce(0) { $0 + $1.steps } / days.count
                    Text("Average \(average.formatted()) a day").font(.system(size: 13)).foregroundStyle(Theme.muted)
                }

                Text("After a long walking day (15,000+ steps, or 12,000 before you train), the coach trims a set from each leg lift.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
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
                hours = await HealthService.stepBuckets(from: start, to: tomorrow, every: DateComponents(hour: 1))
                days = await HealthService.stepBuckets(from: cal.date(byAdding: .day, value: -6, to: start)!, to: tomorrow,
                                                       every: DateComponents(day: 1))
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}
