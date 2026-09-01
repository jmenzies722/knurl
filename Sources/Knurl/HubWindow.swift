import AppKit
import SwiftUI

final class HubPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        AppDelegate.shared?.state.hideHub()
    }

    override func keyDown(with event: NSEvent) {
        if AppDelegate.shared?.state.handleKey(event, escape: .hideHub) == true { return }
        super.keyDown(with: event)
    }
}

final class HubHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if AppDelegate.shared?.state.handleKey(event, escape: .hideHub) == true { return }
        super.keyDown(with: event)
    }
}

@MainActor
final class HubWindow {
    static let shared = HubWindow()

    private var window: HubPanel?

    private init() {}

    var isVisible: Bool { window?.isVisible == true }

    func attach(_ state: DialState) {
        let window = ensure()
        window.contentView = HubHostingView(rootView: HubView(state: state))
    }

    func show() {
        let window = ensure()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func ensure() -> HubPanel {
        if let window { return window }
        let created = HubPanel(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        created.title = "Knurl"
        created.minSize = NSSize(width: 800, height: 640)
        created.isReleasedWhenClosed = false
        created.titlebarAppearsTransparent = true
        created.titleVisibility = .visible
        created.backgroundColor = NSColor.windowBackgroundColor
        created.center()
        window = created
        return created
    }
}
