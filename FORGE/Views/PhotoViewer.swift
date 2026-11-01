import SwiftUI

/// An exercise's start and finish photos, tappable to open full screen.
struct ExercisePhotoPair: View {
    let exercise: Exercise
    var height: CGFloat? = nil
    @State private var open: Int?

    var body: some View {
        HStack(spacing: 8) {
            ForEach([0, 1], id: \.self) { frame in
                Button { open = frame } label: {
                    ExercisePhoto(exercise: exercise, frame: frame)
                        .aspectRatio(3 / 2, contentMode: .fit)
                        .frame(maxHeight: height)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .bottomLeading) {
                            Text(frame == 0 ? "START" : "FINISH").font(Theme.label).tracking(1)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.black.opacity(0.55), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(6)
                        }
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                .padding(6).background(.black.opacity(0.55), in: Circle())
                                .padding(6)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(frame == 0 ? "Start" : "Finish") position of \(exercise.name). Opens full screen.")
            }
        }
        .fullScreenCover(item: Binding(get: { open.map(PhotoPage.init) }, set: { open = $0?.frame })) { page in
            PhotoViewer(exercise: exercise, frame: page.frame)
        }
    }

    private struct PhotoPage: Identifiable {
        let frame: Int
        var id: Int { frame }
    }
}

/// Full screen: swipe between start and finish, pinch or double-tap to zoom.
struct PhotoViewer: View {
    let exercise: Exercise
    @State var frame: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $frame) {
                ForEach([0, 1], id: \.self) { f in
                    ZoomableImage { ExercisePhoto(exercise: exercise, frame: f).scaledToFit() }
                        .tag(f)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(.system(size: 17, weight: .heavy))
                Text(frame == 0 ? "Start" : "Finish").font(.system(size: 13))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 8)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.white.opacity(0.15), in: Circle())
            }
            .padding(.trailing, 16)
            .accessibilityLabel("Close")
        }
    }
}

private struct ZoomableImage<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragBase: CGSize = .zero

    var body: some View {
        content
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(MagnifyGesture()
                .onChanged { scale = min(4, max(1, base * $0.magnification)) }
                .onEnded { _ in base = scale; if scale == 1 { reset() } })
            // Panning only while zoomed, so a swipe at 1× still turns the page.
            .simultaneousGesture(scale > 1 ? DragGesture()
                .onChanged { offset = CGSize(width: dragBase.width + $0.translation.width,
                                             height: dragBase.height + $0.translation.height) }
                .onEnded { _ in dragBase = offset } : nil)
            .onTapGesture(count: 2) {
                withAnimation(.snappy) {
                    if scale > 1 { reset() } else { scale = 2.5; base = 2.5 }
                }
            }
    }

    private func reset() {
        scale = 1; base = 1; offset = .zero; dragBase = .zero
    }
}
