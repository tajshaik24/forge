import SwiftUI
import SwiftData

struct CoachChatView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(CoachStore.self) private var coach
    @Query private var notes: [CoachNote]
    @Query(sort: \ChatEntry.date) private var messages: [ChatEntry]
    @Query(sort: \DailyPlan.updatedAt, order: .reverse) private var plans: [DailyPlan]
    @State private var draft = ""
    @FocusState private var focused: Bool

    private let suggestions = ["Only 30 min today", "I'm at a hotel gym", "Make Saturday shorter", "Squats make me lightheaded"]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if messages.isEmpty { intro }
                    ForEach(messages) { message in
                        bubble(message).id(message.persistentModelID)
                    }
                    if coach.isThinking {
                        ProgressView().tint(Theme.ember).padding(.leading, 4)
                    }
                }
                .padding(20)
            }
            .onChange(of: messages.count) {
                if let last = messages.last { withAnimation { proxy.scrollTo(last.persistentModelID, anchor: .bottom) } }
            }
            .onAppear {
                if let last = messages.last { proxy.scrollTo(last.persistentModelID, anchor: .bottom) }
            }
        }
        .background(Theme.ground)
        .navigationTitle("AI Coach")
        .toolbar {
            NavigationLink { CoachNotesView() } label: { Label("Notes · \(notes.count)", systemImage: "doc.text") }
            if !messages.isEmpty {
                Menu {
                    Button("Clear conversation", systemImage: "trash", role: .destructive) { coach.clearChat(ctx) }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("More")
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            if coach.engine.displayName != "AI Coach", let reason = coach.aiUnavailableReason {
                Text(reason).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            Text("Tell me how training feels, what hurts, how long you have, or where you are. I'll remember what matters and rebuild your plan.")
                .font(.system(size: 15)).foregroundStyle(Theme.text.opacity(0.85))
        }
    }

    @ViewBuilder
    private func bubble(_ m: ChatEntry) -> some View {
        if m.fromUser {
            Text(m.text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.onEmber)
                .padding(12)
                .background(Theme.ember, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 4, topTrailingRadius: 18))
                .frame(maxWidth: 300, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(m.text)
                    .font(.system(size: 15))
                    .padding(12)
                    .background(Theme.surface, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4, bottomTrailingRadius: 18, topTrailingRadius: 18))
                if let key = m.replannedDayKey, let plan = plans.first(where: { $0.dayKey == key })?.plan {
                    NavigationLink { PlanView(day: plan) } label: {
                        Card {
                            SectionLabel("Updated · \(dayName(plan.date)) · \(plan.focus) · \(plan.gymName)")
                            ForEach(plan.exercises.prefix(4)) { ex in
                                HStack {
                                    if let r = ex.replaces {
                                        Text(r).strikethrough().foregroundStyle(Theme.muted)
                                        Image(systemName: "arrow.right").foregroundStyle(Theme.emberSoft)
                                    }
                                    Text(ex.name).bold()
                                }
                                .font(.system(size: 14))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if let note = m.savedNote {
                    Label("Saved to notes: \(note)", systemImage: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.emberSoft)
                }
            }
            .frame(maxWidth: 330, alignment: .leading)
        }
    }

    private func dayName(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.weekday(.wide))
    }

    private var composer: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { s in
                        Button(s) { send(s) }
                            .font(.system(size: 13))
                            .padding(.horizontal, 12).frame(height: 34)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().stroke(Theme.hairline))
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Tell your coach anything…", text: $draft, axis: .vertical)
                    .focused($focused)
                    .lineLimit(1...4)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 23))
                    .onSubmit { send(draft) }
                Button { send(draft) } label: {
                    Image(systemName: "arrow.up").font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.onEmber)
                        .frame(width: 46, height: 46).background(Theme.ember, in: Circle())
                }
                .accessibilityLabel("Send")
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || coach.isThinking)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.ground)
    }

    private func send(_ text: String) {
        draft = ""
        focused = false
        Task { await coach.send(text, ctx) }
    }
}

struct CoachNotesView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(CoachStore.self) private var coach
    @Query(sort: \CoachNote.createdAt, order: .reverse) private var notes: [CoachNote]

    var body: some View {
        List {
            Section {
                Label("Synced through your iCloud and used in every plan. Swipe to remove.", systemImage: "lock")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            Section("Limits + feedback") {
                if notes.isEmpty {
                    Text("Nothing yet. Tell the coach how movements feel.").foregroundStyle(Theme.muted)
                }
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("“\(note.said)”").font(.system(size: 15, weight: .semibold))
                        Text(note.rule).font(.system(size: 13)).foregroundStyle(Theme.emberSoft)
                        if !note.avoid.isEmpty {
                            Text("Avoids: " + note.avoid.map(\.label).joined(separator: ", "))
                                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                        Text(note.createdAt.formatted(date: .abbreviated, time: .omitted).uppercased())
                            .font(Theme.mono(11, .medium)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { idx in
                    idx.map { notes[$0] }.forEach { ctx.delete($0) }
                    try? ctx.save()
                    Task { await coach.invalidate(ctx) }
                }
            }
            Section("Goals") {
                LabeledContent("Focus", value: SyncedSettings.goal)
                LabeledContent("Session length", value: "\(SyncedSettings.minutes) min")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ground)
        .navigationTitle("What your coach knows")
    }
}
