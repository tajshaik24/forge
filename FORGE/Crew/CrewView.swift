import SwiftUI
import SwiftData

struct CrewView: View {
    @Environment(\.modelContext) private var ctx
    @State private var crew = CrewService.shared
    @State private var newCrewName = ""
    @State private var name = CrewService.shared.displayName
    @State private var nudged: Set<String> = []
    @State private var confirmLeave = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("CREWS · BETA").font(Theme.mono(11)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .overlay(Capsule().stroke(Theme.hairline))
                if crew.crew == nil {
                    startOrJoin
                } else if crew.displayName.isEmpty {
                    namePrompt
                } else {
                    board
                }
                if let err = crew.errorText { Text(err).font(.footnote).foregroundStyle(Theme.muted) }
            }
            .padding(20)
        }
        .background(Theme.ground)
        .navigationTitle(crew.crew?.name ?? "Crew")
        .toolbar {
            if crew.crew != nil {
                Menu {
                    if let url = crew.shareURL {
                        ShareLink(item: url, subject: Text("Join my FORGE crew"),
                                  message: Text("Join \(crew.crew?.name ?? "my crew") on FORGE and keep each other showing up.")) {
                            Label("Invite friends", systemImage: "person.badge.plus")
                        }
                    }
                    Button(crew.crew?.isOwner == true ? "End crew for everyone" : "Leave crew",
                           systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmLeave = true }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Crew options")
            }
        }
        .confirmationDialog("Leave \(crew.crew?.name ?? "crew")?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button(crew.crew?.isOwner == true ? "End crew" : "Leave", role: .destructive) { Task { await crew.leave() } }
        } message: {
            Text(crew.crew?.isOwner == true ? "You created this crew, so it ends for everyone." : "Your check-ins stay with the crew.")
        }
        .refreshable { await sync() }
        .task { await sync() }
    }

    private func sync() async {
        await crew.postCheckIns(from: ctx)
        await crew.refresh()
    }

    // MARK: No crew yet

    private var startOrJoin: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("START A CREW").font(Theme.display(40))
            Text("A small group that keeps each other showing up. Hit your training days every week to keep the streak alive. Rest days never break it.")
                .font(.system(size: 15)).foregroundStyle(Theme.muted)
            TextField("Crew name", text: $newCrewName)
                .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            TextField("Your name in the crew", text: $name)
                .textContentType(.givenName)
                .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            LabeledContent("Weekly goal", value: "\(crew.weeklyGoal) days (your training days)")
                .font(.system(size: 14))
            privacyNote
            Button("Create crew") {
                crew.displayName = name.trimmingCharacters(in: .whitespaces)
                Task { await crew.createCrew(named: newCrewName.trimmingCharacters(in: .whitespaces)) }
            }
            .buttonStyle(EmberButtonStyle())
            .disabled(newCrewName.trimmingCharacters(in: .whitespaces).isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty || crew.isLoading)
            Text("Got an invite? Tap the link on this iPhone and you'll join automatically.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
        }
    }

    private var namePrompt: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("YOU'RE IN").font(Theme.display(40))
            Text("What should \(crew.crew?.name ?? "your crew") call you?").foregroundStyle(Theme.muted)
            TextField("Your name", text: $name)
                .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            privacyNote
            Button("Join crew") {
                crew.displayName = name.trimmingCharacters(in: .whitespaces)
                Task {
                    try? await crew.joinAsMember()
                    await sync()
                }
            }
            .buttonStyle(EmberButtonStyle())
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var privacyNote: some View {
        Label("Crews see check-ins only: workout type, sets and minutes. Never weights, heart rate, sleep or your coach notes.",
              systemImage: "lock")
            .font(.system(size: 13)).foregroundStyle(Theme.muted)
            .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Streak board

    private var board: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                HStack(spacing: 16) {
                    VStack(spacing: 0) {
                        Text("\(crew.crewStreak)").font(Theme.mono(44)).foregroundStyle(Theme.emberSoft)
                        Text("weeks").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    .frame(width: 76)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Crew streak").font(.system(size: 16, weight: .heavy))
                        let onTrack = crew.standings.filter { !$0.atRisk }.count
                        Text("Weeks in a row everyone hit their days. \(onTrack) of \(crew.standings.count) on track this week.")
                            .font(.system(size: 13)).foregroundStyle(Theme.text.opacity(0.85))
                    }
                }
            }
            .accessibilityElement(children: .combine)

            ForEach(crew.nudgesForMe.prefix(1)) { n in
                Label("\(n.fromName) nudged you · \(n.date.formatted(.relative(presentation: .named)))", systemImage: "bell")
                    .font(.system(size: 13)).foregroundStyle(Theme.emberSoft)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.emberWash, in: RoundedRectangle(cornerRadius: 14))
            }

            HStack {
                SectionLabel("This week")
                Spacer()
                HStack(spacing: 4) {
                    ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                        Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(Theme.mono(9)).foregroundStyle(Theme.muted).frame(width: 14)
                    }
                }
                .padding(.trailing, 76)
            }
            ForEach(crew.standings) { s in memberRow(s) }

            if crew.members.count < 2, let url = crew.shareURL {
                ShareLink(item: url, subject: Text("Join my FORGE crew")) {
                    Label("Invite your crew", systemImage: "person.badge.plus")
                }
                .buttonStyle(EmberButtonStyle())
            }

            SectionLabel("Activity")
            ForEach(crew.checkIns.prefix(15)) { c in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(c.userID == crew.myUserID ? "You" : c.name).font(.system(size: 13, weight: .bold))
                    Text("\(c.focus) · \(c.sets) sets · \(c.minutes) min\(c.verified ? " · Health verified" : "")")
                        .font(.system(size: 13)).foregroundStyle(Theme.text.opacity(0.85))
                    Spacer()
                    Text(c.date.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))
                        .font(Theme.mono(11, .medium)).foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 6)
                Divider().overlay(Theme.hairline)
            }
        }
    }

    private func memberRow(_ s: CrewStanding) -> some View {
        let isMe = s.member.id == crew.myUserID
        let today = CrewStreaks.calendar.dateComponents([.day], from: CrewStreaks.weekStart(.now),
                                                        to: CrewStreaks.calendar.startOfDay(for: .now)).day ?? 0
        return HStack(spacing: 10) {
            Text(String(s.member.name.prefix(1)).uppercased())
                .font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.onEmber)
                .frame(width: 34, height: 34).background(isMe ? Theme.ember : Theme.emberSoft, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(isMe ? "You" : s.member.name).font(.system(size: 15, weight: .bold))
                Text(s.atRisk ? "At risk · needs \(s.needed) in \(s.daysLeft) days"
                     : (s.metGoal ? "Week done · \(s.weekStreak)-week streak" : "\(s.count) of \(s.member.weeklyGoal) · \(s.weekStreak)-week streak"))
                    .font(.system(size: 12, weight: s.atRisk ? .semibold : .regular))
                    .foregroundStyle(s.atRisk ? Theme.emberSoft : Theme.muted)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(s.daysThisWeek.contains(i) ? Theme.ember : (i > today ? Color.clear : Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .stroke(s.daysThisWeek.contains(i) ? .clear : Theme.hairline,
                                    style: StrokeStyle(lineWidth: 1, dash: i > today ? [3] : [])))
                        .frame(width: 14, height: 14)
                }
            }
            .accessibilityLabel("\(s.count) of \(s.member.weeklyGoal) days this week")
            Group {
                if s.atRisk && !isMe {
                    Button(nudged.contains(s.member.id) ? "Sent" : "Nudge") {
                        nudged.insert(s.member.id)
                        Task { await crew.nudge(s.member) }
                    }
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(nudged.contains(s.member.id) ? Theme.emberSoft : Theme.onEmber)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(nudged.contains(s.member.id) ? Color.clear : Theme.ember, in: Capsule())
                    .disabled(nudged.contains(s.member.id))
                } else {
                    Text("\(s.count)/\(s.member.weeklyGoal)").font(Theme.mono(14))
                }
            }
            .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(s.atRisk ? Theme.emberWash : Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(s.atRisk ? Theme.ember.opacity(0.4) : Theme.hairline))
    }
}

/// Small card on Today that opens the crew.
struct CrewCard: View {
    @State private var crew = CrewService.shared

    var body: some View {
        NavigationLink { CrewView() } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.3.fill").foregroundStyle(Theme.ember)
                VStack(alignment: .leading, spacing: 2) {
                    Text(crew.crew?.name ?? "Start a crew").font(.system(size: 15, weight: .bold))
                    if crew.crew != nil, let me = crew.standings.first(where: { $0.member.id == crew.myUserID }) {
                        Text("You \(me.count)/\(me.member.weeklyGoal) this week · crew streak \(crew.crewStreak) wk")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    } else {
                        Text("Keep each other showing up · beta").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline))
        }
        .buttonStyle(.plain)
        .task { await crew.refresh() }
    }
}
