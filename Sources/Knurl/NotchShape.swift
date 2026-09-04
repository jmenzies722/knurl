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

        // Cubic curves, not quadratics.
        //
        // A quadratic has a single control point, so where the fillet meets
        // the straight edge the curvature jumps from "turning hard" to "not
        // turning at all" in one step. The eye reads that discontinuity as a
        // corner — which is why the old shape looked pointy where it should
        // have looked poured. Two control points let the curvature arrive at
        // zero gradually, which is the same trick a continuous corner uses,
        // and what makes Apple's own rounded shapes look moulded rather than
        // filleted.
        let k: CGFloat = 0.5523  // circle-to-Bézier constant, softened below

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Leading concave fillet: out of the bezel and down.
        path.addCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control1: CGPoint(x: rect.minX + top * k * 1.25, y: rect.minY),
            control2: CGPoint(x: rect.minX + top, y: rect.minY + top * (1 - k) * 0.9)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))

        // Leading bottom corner.
        path.addCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control1: CGPoint(x: rect.minX + top, y: rect.maxY - bottom * (1 - k)),
            control2: CGPoint(x: rect.minX + top + bottom * (1 - k), y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))

        // Trailing bottom corner.
        path.addCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control1: CGPoint(x: rect.maxX - top - bottom * (1 - k), y: rect.maxY),
            control2: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom * (1 - k))
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))

        // Trailing concave fillet: up and back into the bezel.
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: rect.maxX - top, y: rect.minY + top * (1 - k) * 0.9),
            control2: CGPoint(x: rect.maxX - top * k * 1.25, y: rect.minY)
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
            // One spring for the whole thing — shape, size, corners and the
            // content inside it — so it reads as a single object moving
            // rather than a box that resizes and a layout that catches up.
            //
            // A little bounce, not none. Zero bounce is a drawer sliding;
            // a small overshoot is what makes something feel like it has mass
            // and settled, which is the whole trick Apple's own expansions
            // use. It stays small because the fillets meet a bezel that does
            // not move, and anything larger makes that seam visibly wobble.
            .animation(
                lively ? .spring(duration: 0.34, bounce: 0.14) : .easeOut(duration: 0.14),
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
// A level you set by dragging along it.
//
// White on translucent, like Control Center, and deliberately not tinted per
// control. Three stacked bars in pink, blue and yellow read as a rainbow: the
// colours were carrying category, which nobody needs — the icon beside each
// one already says which is which. Colour in this panel is reserved for
// state, so the only thing that lights up is Flow when it is listening, and
// that now means something.

struct NotchScrubber: View {
    var symbol: String
    var progress: Double
    /// Kept for callers that still pass one; the bar itself does not use it.
    var tint: Color = .white
    var label: String
    var leading: String? = nil
    var trailing: String? = nil
    var onSet: (Double) -> Void

    @State private var dragging = false

    var body: some View {
        HStack(spacing: 10) {
            if !symbol.isEmpty {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(dragging ? 0.95 : 0.55))
                    .frame(width: 15)
                    .contentTransition(.symbolEffect(.replace))
            }

            if let leading {
                Text(leading)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 30, alignment: .leading)
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    Capsule()
                        .fill(.white)
                        .frame(width: max(5, width * DialMath.clampVolume(progress)))
                }
                .frame(height: dragging ? 7 : 5)
                .frame(maxHeight: .infinity, alignment: .center)
                // The bar is 5 points tall and the target is 22: you are
                // pointing at a position, not at a line.
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragging = true
                            onSet(DialMath.clampVolume(value.location.x / max(width, 1)))
                        }
                        .onEnded { _ in dragging = false }
                )
                .animation(.snappy(duration: 0.13), value: dragging)
            }
            .frame(height: 22)

            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 34, alignment: .trailing)
            } else if leading == nil {
                Text("\(Int((DialMath.clampVolume(progress) * 100).rounded()))")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 26, alignment: .trailing)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((DialMath.clampVolume(progress) * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSet(min(1, progress + 0.05))
            case .decrement: onSet(max(0, progress - 0.05))
            default: break
            }
        }
    }
}
