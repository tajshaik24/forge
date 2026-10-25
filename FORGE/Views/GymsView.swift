import SwiftUI
import SwiftData

struct GymsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(CoachStore.self) private var coach
    @Query(sort: \GymProfile.sortIndex) private var gyms: [GymProfile]
    @State private var adding = false
    @State private var newName = ""

    private var active: GymProfile? { gyms.first(where: \.isActive) ?? gyms.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 8) {
                    ForEach(gyms) { gym in
                        Button { select(gym) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(gym.name).font(.system(size: 16, weight: .heavy))
                                    Text(gym.detail.isEmpty ? "\(gym.equipment.count) pieces of equipment" : gym.detail)
                                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Image(systemName: gym == active ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(gym == active ? Theme.accent : Theme.muted)
                            }
                            .padding(.horizontal, 16).frame(minHeight: 60)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(gym == active ? Theme.accent : Theme.hairline))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(gym == active ? .isSelected : [])
                    }
                }

                if let gym = active {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionLabel("At \(gym.name)")
                            Spacer()
                            Text("\(gym.equipment.count) OF \(Equipment.allCases.count)").font(Theme.mono(12)).foregroundStyle(Theme.muted)
                        }
                        FlowRow {
                            ForEach(Equipment.allCases) { item in
                                let has = gym.equipment.contains(item)
                                Button { toggle(item, in: gym) } label: {
                                    Text(item.label)
                                        .font(.system(size: 14, weight: has ? .bold : .regular))
                                        .strikethrough(!has)
                                        .padding(.horizontal, 14).frame(height: 38)
                                        .foregroundStyle(has ? Theme.accentText : Theme.muted)
                                        .background(has ? Theme.accentWash : .clear, in: Capsule())
                                        .overlay(Capsule().stroke(has ? Theme.accent : Theme.hairline,
                                                                  style: StrokeStyle(lineWidth: 1, dash: has ? [] : [4])))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(has ? .isSelected : [])
                            }
                        }
                        Text("The coach only programs moves this gym can do and swaps the rest — a leg press becomes bench step-ups at home.")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.ground)
        .navigationTitle("Gyms")
        .toolbar {
            NavigationLink { ExerciseLibraryView() } label: { Label("Exercises", systemImage: "list.bullet") }
            Button("Add gym", systemImage: "plus") { adding = true }
        }
        .alert("New gym", isPresented: $adding) {
            TextField("Name", text: $newName)
            Button("Add") { addGym() }
            Button("Cancel", role: .cancel) { newName = "" }
        }
    }

    private func select(_ gym: GymProfile) {
        gyms.forEach { $0.isActive = ($0 == gym) }
        gym.isActive = true   // a just-inserted gym isn't in `gyms` until the query refreshes
        try? ctx.save()
        Task { await coach.invalidate(ctx) }
    }

    private func toggle(_ item: Equipment, in gym: GymProfile) {
        var set = gym.equipment
        if set.contains(item) { set.remove(item) } else { set.insert(item) }
        gym.equipment = set
        try? ctx.save()
        Task { await coach.invalidate(ctx) }
    }

    private func addGym() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        newName = ""
        guard !name.isEmpty else { return }
        let gym = GymProfile(name: name, detail: "", equipment: [.dumbbells, .bench], sortIndex: gyms.count)
        ctx.insert(gym)
        select(gym)
    }
}
