import SwiftUI
import UIKit

/// iPhone Duo: how far the hinge is open, published at the root so any screen can lay out around the fold.
/// On other iPhones (and before iOS 27.1) the hinge is `.none` and nothing changes.
enum Hinge: Equatable {
    case none, closed, partlyOpen, open
}

extension EnvironmentValues {
    @Entry var hinge: Hinge = .none
}

extension View {
    /// Watches the hinge and puts its state in the environment.
    func readsHinge() -> some View { modifier(HingeReader()) }
}

private struct HingeReader: ViewModifier {
    @State private var hinge: Hinge = .none

    func body(content: Content) -> some View {
        content
            .background(HingeObserver(hinge: $hinge).allowsHitTesting(false))
            .environment(\.hinge, hinge)
    }
}

/// SwiftUI has no hinge API, so a UIKit interaction reports it.
private struct HingeObserver: UIViewRepresentable {
    @Binding var hinge: Hinge

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        if #available(iOS 27.1, *) {
            let binding = $hinge
            view.addInteraction(UIHingeInteraction { _, update in
                binding.wrappedValue = switch update.hinge?.status {
                case .closed: .closed
                case .partiallyOpen: .partlyOpen
                case .fullyOpen: .open
                default: .none
                }
            })
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

extension GeometryProxy {
    /// Where the screen folds, in this view's coordinates, or nil when it doesn't cross this view.
    var fold: CGRect? {
        guard #available(iOS 27.1, *) else { return nil }
        return reservedRegions(kind: .division).first(where: \.isActive)?.frame
    }
}

/// Two parts that sit on either side of the fold: top and bottom when the phone stands half-open on a bench,
/// left and right when it's open like a book. Anywhere else, `single` is shown.
struct FoldSplit<First: View, Second: View, Single: View>: View {
    @Environment(\.hinge) private var hinge
    /// Only split when the phone is half-open (not flat), e.g. a workout screen propped up.
    var onlyWhenPartlyOpen = false
    @ViewBuilder var first: First
    @ViewBuilder var second: Second
    @ViewBuilder var single: Single

    var body: some View {
        GeometryReader { geo in
            if let fold = geo.fold, hinge != .closed, !onlyWhenPartlyOpen || hinge == .partlyOpen {
                if fold.width >= fold.height {   // a horizontal crease: top and bottom halves
                    VStack(spacing: 0) {
                        first.frame(height: max(0, fold.minY))
                        Color.clear.frame(height: fold.height)
                        second.frame(maxHeight: .infinity)
                    }
                } else {
                    HStack(spacing: 0) {
                        first.frame(width: max(0, fold.minX))
                        Color.clear.frame(width: fold.width)
                        second.frame(maxWidth: .infinity)
                    }
                }
            } else {
                single
            }
        }
    }
}
