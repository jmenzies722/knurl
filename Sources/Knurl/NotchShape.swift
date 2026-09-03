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

// MARK: - Compact ring
//
// The trailing indicator for a countdown: a ring that closes as the hour runs
// down. Sixteen points, so it has to say one thing and say it without a label.

struct NotchRing: View {
    var progress: Double
    var tint: Color
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.16), lineWidth: size * 0.16)
            Circle()
                .trim(from: 0, to: DialMath.clampVolume(progress))
                .stroke(tint, style: StrokeStyle(lineWidth: size * 0.16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.6), radius: 2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Scrubber
//
// A level you set by dragging along it. The notch already has a dial, and a
// dial is the right control when you want to feel your way to a value — but
// when you know you want "about a third" the shortest path is a bar you touch
// at the third. Both, rather than an argument about which is better.

struct NotchScrubber: View {
    var symbol: String
    var progress: Double
    var tint: Color
    var label: String
    var onSet: (Double) -> Void

    @State private var dragging = false

    var body: some View {
        HStack(spacing: 8) {
            if !symbol.isEmpty {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(dragging ? tint : .white.opacity(0.6))
                    .frame(width: 16)
                    .contentTransition(.symbolEffect(.replace))
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(6, width * DialMath.clampVolume(progress)))
                        .shadow(color: tint.opacity(0.5), radius: 3)
                }
                .frame(height: dragging ? 8 : 6)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragging = true
                            onSet(DialMath.clampVolume(value.location.x / max(width, 1)))
                        }
                        .onEnded { _ in dragging = false }
                )
                .animation(.snappy(duration: 0.14), value: dragging)
            }
            .frame(height: 18)

            if !symbol.isEmpty {
                Text("\(Int((DialMath.clampVolume(progress) * 100).rounded()))")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 22, alignment: .trailing)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((DialMath.clampVolume(progress) * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let step = 0.05
            switch direction {
            case .increment: onSet(min(1, progress + step))
            case .decrement: onSet(max(0, progress - step))
            default: break
            }
        }
    }
}
