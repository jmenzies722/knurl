import CoreGraphics
import Foundation

public enum NotchMath: Sendable {
    public static let shelfHeight: CGFloat = 52
    public static let shelfGap: CGFloat = 5
    public static let shelfWidth: CGFloat = 360

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

    /// Panel that keeps the camera housing where it is and grows a shelf below it.
    public static func expandedFrame(housing: CGRect, visible: CGRect) -> CGRect {
        let width = min(max(housing.width + 80, shelfWidth), max(housing.width, visible.width - 32))
        let height = housing.height + shelfGap + shelfHeight
        let x = min(max(visible.minX + 16, housing.midX - width / 2), visible.maxX - width - 16)
        return CGRect(x: x, y: housing.minY - shelfGap - shelfHeight, width: width, height: height)
    }

    public static func housingInExpanded(housing: CGRect, expanded: CGRect) -> CGRect {
        CGRect(
            x: housing.minX - expanded.minX,
            y: housing.minY - expanded.minY,
            width: housing.width,
            height: housing.height
        )
    }

    public static func shelfInExpanded(expanded: CGRect) -> CGRect {
        CGRect(
            x: 0,
            y: 0,
            width: expanded.width,
            height: shelfHeight
        )
    }
}
