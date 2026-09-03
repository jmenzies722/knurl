import CoreGraphics
import Foundation

/// How much of itself the notch is currently showing.
///
/// The notch is one continuous black shape that grows downward out of the
/// camera housing. It is not four different panels — that was the first pass,
/// and a separate chip plus a gapped shelf never looked like one object.
public enum NotchStage: String, Sendable, CaseIterable {
    /// Idle: nothing at all. The shape is exactly the cutout, so there is
    /// nothing to see — which is the point. A permanent black island hanging
    /// under the housing is not "in the notch", it is a bar below the notch
    /// wearing the notch's colour.
    case rest
    /// Something is genuinely happening: one lit line, exactly the width of
    /// the cutout.
    ///
    /// It does not widen. Widening put a black rectangle around the notch with
    /// two small things floating in it — an obvious bar rather than the notch,
    /// and it covered menu titles besides. An iPhone can widen because there
    /// is nothing under there; a Mac cannot.
    case glance
    /// The pointer is on the housing: the dial and the controls drop out.
    case hover
    /// Clicked: the shelf.
    case shelf
    /// Dictating: levels, words, destination.
    case flow

    public var height: CGFloat {
        switch self {
        case .rest: 0
        case .glance: 4
        case .hover: 60
        // The shelf carries the whole desk: what is playing, a dial you can
        // actually turn, the five faces, and the way out. It is the notch's
        // answer to a menu bar item, so it has to hold what one holds.
        case .shelf: 186
        case .flow: 132
        }
    }

    /// Extra width beyond the housing, per side.
    ///
    /// Zero at rest and a hair at glance, so the silhouette *is* the cutout.
    /// Opening flares out over the menu bar, but less than it used to — the
    /// old 150 points a side made a 520-point slab appear from a 220-point
    /// notch, which read as a panel arriving rather than the notch growing.
    public var flare: CGFloat {
        switch self {
        case .rest: 0
        // Zero: the silhouette stays the cutout. This is the whole reason it
        // reads as the notch rather than as something stuck to it.
        case .glance: 0
        case .hover: 96
        // Wider than hover: the shelf carries cover art, a title, three
        // transport keys and two more besides. Sized to its content rather
        // than to a round number.
        case .shelf: 156
        case .flow: 104
        }
    }

    /// The concave fillet where the shape leaves the housing.
    public var topCornerRadius: CGFloat {
        switch self {
        case .rest, .glance: 0
        case .hover, .shelf, .flow: 12
        }
    }

    /// The ordinary rounded corners along the bottom.
    public var bottomCornerRadius: CGFloat {
        switch self {
        case .rest: 0
        case .glance: 2
        case .hover: 16
        case .shelf, .flow: 20
        }
    }

    /// Whether this stage shows controls. `glance` is still just bezel.
    public var isOpen: Bool { self == .hover || self == .shelf || self == .flow }
}

public enum NotchMath: Sendable {
    // Kept: the HUD and older call sites still read these.
    public static let shelfHeight: CGFloat = NotchStage.shelf.height
    public static let flowShelfHeight: CGFloat = NotchStage.flow.height
    public static let shelfGap: CGFloat = 0
    public static let shelfWidth: CGFloat = 360

    /// The camera housing, in screen coordinates, or nil on a Mac without one.
    ///
    /// `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` are the menu-bar
    /// strips either side of the cutout, so the gap between them is the notch.
    /// This is the supported way to ask; SkyLight is not.
    public static func housingFrame(
        screen: CGRect,
        visible: CGRect,
        leftAux: CGRect?,
        rightAux: CGRect?
    ) -> CGRect? {
        guard let left = leftAux, let right = rightAux, right.minX > left.maxX + 24 else {
            return nil
        }
        let height = screen.maxY - visible.maxY
        guard height > 10 else { return nil }
        return CGRect(
            x: left.maxX,
            y: visible.maxY,
            width: right.minX - left.maxX,
            height: height
        )
    }

    /// The window frame, which never changes.
    ///
    /// This is the part that took two attempts. Animating the panel's frame
    /// meant the window server and the shape animation were racing, and the
    /// black flickered at every edge. Instead the panel is created once at the
    /// largest size any stage needs, anchored to the top of the screen, and
    /// only the masked content inside it resizes — so the growth is one
    /// SwiftUI animation with nothing to race against.
    public static func panelFrame(screen: CGRect, housing: CGRect) -> CGRect {
        let width = maxContentWidth(housing: housing)
        let height = housing.height + maxStageHeight + overshoot
        return CGRect(
            x: housing.midX - width / 2,
            y: screen.maxY - height,
            width: width,
            height: height
        )
    }

    /// Room for the spring to overshoot without clipping the black.
    public static let overshoot: CGFloat = 60

    public static var maxStageHeight: CGFloat {
        NotchStage.allCases.map(\.height).max() ?? 0
    }

    public static func maxContentWidth(housing: CGRect) -> CGFloat {
        housing.width + 2 * (NotchStage.allCases.map(\.flare).max() ?? 0)
    }

    /// The shape's size for a stage: the housing plus its flare, and the
    /// housing's own height plus whatever is hanging below it.
    public static func contentSize(housing: CGRect, stage: NotchStage) -> CGSize {
        CGSize(
            width: housing.width + 2 * stage.flare,
            height: housing.height + stage.height
        )
    }

    /// Where the pointer has to be for the notch to open. Wider and taller
    /// than the cutout itself, because a target you have to hit exactly is a
    /// target you miss.
    public static func hoverTarget(housing: CGRect) -> CGRect {
        // Generous sideways, because the cutout's edges are the easiest thing
        // on the screen to overshoot, and a little below it, because that is
        // the direction a pointer arrives from. Not so far below that moving
        // toward the menu bar opens it by accident.
        CGRect(
            x: housing.minX - 20,
            y: housing.minY - 10,
            width: housing.width + 40,
            height: housing.height + 10
        )
    }

    /// While the notch is open the pointer is allowed to roam the whole shape
    /// without it snapping shut under the cursor.
    public static func openTarget(housing: CGRect, stage: NotchStage) -> CGRect {
        let size = contentSize(housing: housing, stage: stage)
        return CGRect(
            x: housing.midX - size.width / 2,
            y: housing.maxY - size.height,
            width: size.width,
            height: size.height
        )
        .insetBy(dx: -12, dy: -12)
    }

    // Kept for the older two-piece call sites.
    public static func expandedFrame(
        housing: CGRect,
        visible: CGRect,
        shelf: CGFloat = shelfHeight
    ) -> CGRect {
        let width = min(max(housing.width + 80, shelfWidth), max(housing.width, visible.width - 32))
        let height = housing.height + shelf
        let x = min(max(visible.minX + 16, housing.midX - width / 2), visible.maxX - width - 16)
        return CGRect(x: x, y: housing.minY - shelf, width: width, height: height)
    }

    public static func housingInExpanded(housing: CGRect, expanded: CGRect) -> CGRect {
        CGRect(
            x: housing.minX - expanded.minX,
            y: housing.minY - expanded.minY,
            width: housing.width,
            height: housing.height
        )
    }

    public static func shelfInExpanded(expanded: CGRect, shelf: CGFloat = shelfHeight) -> CGRect {
        CGRect(x: 0, y: 0, width: expanded.width, height: shelf)
    }
}
