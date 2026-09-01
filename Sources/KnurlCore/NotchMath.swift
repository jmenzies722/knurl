import CoreGraphics
import Foundation

public enum NotchMath: Sendable {
    public static let collapsedSize = CGSize(width: 360, height: 38)

    public static func chipFrame(
        visible: CGRect,
        leftAux: CGRect?,
        rightAux: CGRect?,
        size: CGSize
    ) -> CGRect {
        let midX: CGFloat
        if let left = leftAux, let right = rightAux, right.minX > left.maxX {
            midX = (left.maxX + right.minX) / 2
        } else {
            midX = visible.midX
        }
        let minX = visible.minX + 8
        let maxX = visible.maxX - size.width - 8
        let x = maxX >= minX ? min(max(minX, midX - size.width / 2), maxX) : visible.minX + 8
        return CGRect(x: x, y: visible.maxY - size.height, width: size.width, height: size.height)
    }

    public static func deskFrame(visible: CGRect) -> CGRect {
        visible
    }
}
