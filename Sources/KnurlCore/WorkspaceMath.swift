import CoreGraphics
import Foundation

public enum SnapZone: String, CaseIterable, Sendable, Identifiable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case leftThird
    case centerThird
    case rightThird
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case maximize
    case center

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .leftHalf: "Left"
        case .rightHalf: "Right"
        case .topHalf: "Top"
        case .bottomHalf: "Bottom"
        case .leftThird: "⅓ Left"
        case .centerThird: "⅓ Center"
        case .rightThird: "⅓ Right"
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        case .maximize: "Maximize"
        case .center: "Center"
        }
    }
}

public enum WorkspacePreset: String, CaseIterable, Sendable, Identifiable {
    case focus
    case build
    case debug
    case review
    case agentStack
    case presentation

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .focus: "Focus"
        case .build: "Build"
        case .debug: "Debug"
        case .review: "Review"
        case .agentStack: "Agent Stack"
        case .presentation: "Presentation"
        }
    }

    public var summary: String {
        switch self {
        case .focus: "Editor fills the display."
        case .build: "Editor left, terminal right."
        case .debug: "Editor above, console below."
        case .review: "Editor left, browser right, terminal bottom."
        case .agentStack: "Editor 60%, agents 40%, stacked."
        case .presentation: "Frontmost centered and large."
        }
    }
}

public enum WorkspaceMath: Sendable {
    public static func snap(_ zone: SnapZone, in visible: CGRect) -> CGRect {
        let third = visible.width / 3
        let halfW = visible.width / 2
        let halfH = visible.height / 2
        switch zone {
        case .leftHalf:
            return CGRect(x: visible.minX, y: visible.minY, width: halfW, height: visible.height)
        case .rightHalf:
            return CGRect(x: visible.minX + halfW, y: visible.minY, width: halfW, height: visible.height)
        case .topHalf:
            return CGRect(x: visible.minX, y: visible.minY + halfH, width: visible.width, height: halfH)
        case .bottomHalf:
            return CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: halfH)
        case .leftThird:
            return CGRect(x: visible.minX, y: visible.minY, width: third, height: visible.height)
        case .centerThird:
            return CGRect(x: visible.minX + third, y: visible.minY, width: third, height: visible.height)
        case .rightThird:
            return CGRect(x: visible.maxX - third, y: visible.minY, width: third, height: visible.height)
        case .topLeft:
            return CGRect(x: visible.minX, y: visible.minY + halfH, width: halfW, height: halfH)
        case .topRight:
            return CGRect(x: visible.minX + halfW, y: visible.minY + halfH, width: halfW, height: halfH)
        case .bottomLeft:
            return CGRect(x: visible.minX, y: visible.minY, width: halfW, height: halfH)
        case .bottomRight:
            return CGRect(x: visible.minX + halfW, y: visible.minY, width: halfW, height: halfH)
        case .maximize:
            return visible
        case .center:
            let width = min(visible.width * 0.72, visible.width - 48)
            let height = min(visible.height * 0.72, visible.height - 48)
            return CGRect(
                x: visible.midX - width / 2,
                y: visible.midY - height / 2,
                width: width,
                height: height
            )
        }
    }

    /// Frontmost-first frames for a named preset on one display.
    public static func frames(for preset: WorkspacePreset, visible: CGRect, count: Int) -> [CGRect] {
        guard count > 0 else { return [] }
        switch preset {
        case .focus, .presentation:
            return [snap(preset == .presentation ? .center : .maximize, in: visible)]
                + Array(repeating: CGRect.null, count: max(0, count - 1))
        case .build:
            if count == 1 { return [snap(.leftHalf, in: visible)] }
            return [snap(.leftHalf, in: visible), snap(.rightHalf, in: visible)]
                + Array(repeating: CGRect.null, count: max(0, count - 2))
        case .debug:
            if count == 1 { return [snap(.topHalf, in: visible)] }
            return [snap(.topHalf, in: visible), snap(.bottomHalf, in: visible)]
                + Array(repeating: CGRect.null, count: max(0, count - 2))
        case .review:
            return review(visible: visible, count: count)
        case .agentStack:
            return agentStack(visible: visible, count: count)
        }
    }

    public static func displayContaining(_ point: CGPoint, screens: [CGRect]) -> CGRect? {
        screens.first { $0.contains(point) } ?? screens.first { $0.intersects(CGRect(origin: point, size: CGSize(width: 1, height: 1))) }
    }

    public static func canvasRect(_ frame: CGRect, in visible: CGRect, canvas: CGSize, inset: CGFloat = 10) -> CGRect {
        guard visible.width > 1, visible.height > 1, canvas.width > 1, canvas.height > 1 else {
            return .zero
        }
        let inner = CGRect(x: inset, y: inset, width: canvas.width - inset * 2, height: canvas.height - inset * 2)
        let sx = inner.width / visible.width
        let sy = inner.height / visible.height
        return CGRect(
            x: inner.minX + (frame.minX - visible.minX) * sx,
            y: inner.minY + (visible.maxY - frame.maxY) * sy,
            width: frame.width * sx,
            height: frame.height * sy
        )
    }

    public static func screenPoint(from canvas: CGPoint, visible: CGRect, canvasSize: CGSize, inset: CGFloat = 10) -> CGPoint {
        let inner = CGRect(x: inset, y: inset, width: canvasSize.width - inset * 2, height: canvasSize.height - inset * 2)
        guard inner.width > 1, inner.height > 1 else { return CGPoint(x: visible.midX, y: visible.midY) }
        let sx = visible.width / inner.width
        let sy = visible.height / inner.height
        return CGPoint(
            x: visible.minX + (canvas.x - inner.minX) * sx,
            y: visible.maxY - (canvas.y - inner.minY) * sy
        )
    }

    private static func review(visible: CGRect, count: Int) -> [CGRect] {
        let bottom = visible.height * 0.32
        let top = visible.height - bottom
        let half = visible.width / 2
        let editor = CGRect(x: visible.minX, y: visible.minY + bottom, width: half, height: top)
        let browser = CGRect(x: visible.minX + half, y: visible.minY + bottom, width: half, height: top)
        let terminal = CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: bottom)
        switch count {
        case 1: return [snap(.leftHalf, in: visible)]
        case 2: return [snap(.leftHalf, in: visible), snap(.rightHalf, in: visible)]
        default: return [editor, browser, terminal] + Array(repeating: CGRect.null, count: count - 3)
        }
    }

    private static func agentStack(visible: CGRect, count: Int) -> [CGRect] {
        let lead = visible.width * 0.6
        let trail = visible.width - lead
        let editor = CGRect(x: visible.minX, y: visible.minY, width: lead, height: visible.height)
        switch count {
        case 1:
            return [editor]
        case 2:
            return [editor, CGRect(x: visible.minX + lead, y: visible.minY, width: trail, height: visible.height)]
        default:
            let half = visible.height / 2
            return [
                editor,
                CGRect(x: visible.minX + lead, y: visible.minY + half, width: trail, height: half),
                CGRect(x: visible.minX + lead, y: visible.minY, width: trail, height: half),
            ] + Array(repeating: CGRect.null, count: count - 3)
        }
    }
}
