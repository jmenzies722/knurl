import KnurlCore
import SwiftUI

// MARK: - The shape
//
// The one drawing that makes a panel under the menu bar read as the notch
// itself growing. Two things do the work:
//
//   • The top corners curve *inward*. A normal rounded rectangle under the
//     notch looks like a rectangle under the notch. A concave fillet looks
//     like liquid leaving the bezel, because that is the silhouette you get
//     where a wide shape meets a narrow one.
//   • The bottom corners curve outward as usual, so the thing still reads as
//     a panel and not as a hole.
//
// The top edge is drawn flat and full width and is then positioned behind the
// real cutout, which has no pixels — so the seam is never visible and the two
// blacks are the same black.

struct KnurlNotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    /// Animating the radii alongside the frame is what keeps the flare
    /// smooth: the corners have to open at the same rate the shape widens, or
    /// the fillet visibly pops at the end of the spring.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = max(0, min(topCornerRadius, rect.width / 2))
        let bottom = max(0, min(bottomCornerRadius, rect.width / 2 - top))

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Leading concave fillet: down and inward.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        // Trailing concave fillet: up and outward.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - The stage container
//
// Everything the notch shows sits in here: a black slab masked to the shape,
// sized for the current stage, pinned to the top of the panel so it grows
// downward out of the housing.

struct NotchStageContainer<Content: View>: View {
    var housing: CGRect
    var stage: NotchStage
    var lively: Bool
    @ViewBuilder var content: () -> Content

    private var size: CGSize {
        NotchMath.contentSize(housing: housing, stage: stage)
    }

    var body: some View {
        content()
            .frame(width: size.width, height: size.height, alignment: .bottom)
            .background {
                // Padded far beyond the shape so a spring that overshoots
                // still lands on black rather than on a torn edge.
                Rectangle()
                    .fill(.black)
                    .padding(-NotchMath.overshoot)
            }
            .mask(alignment: .top) {
                KnurlNotchShape(
                    topCornerRadius: stage.topCornerRadius,
                    bottomCornerRadius: stage.bottomCornerRadius
                )
                .frame(width: size.width, height: size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Tight, barely-bouncy, and fast. A notch that springs open with
            // 22% bounce reads as a toy: the shape overshoots past the width
            // it is going to settle at, so the fillets visibly wobble against
            // a bezel that does not move. Precision here means arriving once.
            .animation(
                lively ? .spring(duration: 0.28, bounce: 0.06) : .easeOut(duration: 0.14),
                value: stage
            )
    }
}
