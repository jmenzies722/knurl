import AppKit
import SwiftUI

struct ImmediateHold: NSViewRepresentable {
    var down: () -> Void
    var up: () -> Void

    func makeNSView(context: Context) -> ImmediateHoldView {
        let view = ImmediateHoldView()
        view.down = down
        view.up = up
        return view
    }

    func updateNSView(_ view: ImmediateHoldView, context: Context) {
        view.down = down
        view.up = up
    }
}

final class ImmediateHoldView: NSView {
    var down: () -> Void = {}
    var up: () -> Void = {}
    private var held = false
    private var monitor: Any?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        finishIfNeeded()
        held = true
        down()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.finishIfNeeded()
            return event
        }
    }

    override func mouseUp(with event: NSEvent) {
        finishIfNeeded()
    }

    private func finishIfNeeded() {
        guard held else { return }
        held = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        up()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }
}

struct ImmediatePress: NSViewRepresentable {
    var action: () -> Void

    func makeNSView(context: Context) -> ImmediatePressView {
        let view = ImmediatePressView()
        view.action = action
        return view
    }

    func updateNSView(_ view: ImmediatePressView, context: Context) {
        view.action = action
    }
}

final class ImmediatePressView: NSView {
    var action: () -> Void = {}

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        action()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }
}

struct SelectedFaceGlass: ViewModifier {
    var active: Bool
    var namespace: Namespace.ID

    func body(content: Content) -> some View {
        if active {
            content.glassEffectID("face", in: namespace)
        } else {
            content
        }
    }
}
