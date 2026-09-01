import AppKit
import KnurlCore
import SwiftUI

final class NotchChipPanel: NSPanel {
    var allowsKey = false

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        AppDelegate.shared?.state.collapseNotch()
    }

    override func keyDown(with event: NSEvent) {
        if AppDelegate.shared?.state.handleKey(event, escape: .hideHub) == true { return }
        super.keyDown(with: event)
    }
}

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        if AppDelegate.shared?.state.handleKey(event, escape: .hideHub) == true { return }
        super.keyDown(with: event)
    }
}

@MainActor
final class NotchPanel {
    static let shared = NotchPanel()

    private var panel: NotchChipPanel?
    private var observer: Any?

    private init() {}

    var isExpanded: Bool { panel?.allowsKey == true }

    func attach(_ state: DialState) {
        let panel = ensure()
        panel.contentView = NotchHostingView(rootView: NotchView(state: state))
        collapse()
        panel.orderFront(nil)
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    let expanded = AppDelegate.shared?.state.isNotchExpanded == true
                    if expanded {
                        NotchPanel.shared.expand()
                    } else {
                        NotchPanel.shared.collapse()
                    }
                }
            }
        }
    }

    func expand() {
        let panel = ensure()
        let screen = preferredScreen()
        panel.allowsKey = true
        panel.setFrame(NotchMath.deskFrame(visible: screen.visibleFrame), display: true, animate: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView)
    }

    func collapse() {
        let panel = ensure()
        let screen = preferredScreen()
        panel.allowsKey = false
        panel.resignKey()
        panel.setFrame(
            NotchMath.chipFrame(
                visible: screen.visibleFrame,
                leftAux: screen.auxiliaryTopLeftArea,
                rightAux: screen.auxiliaryTopRightArea,
                size: NotchMath.collapsedSize
            ),
            display: true,
            animate: true
        )
        panel.orderFront(nil)
    }

    private func preferredScreen() -> NSScreen {
        if let notched = NSScreen.screens.first(where: {
            $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil
        }) {
            return notched
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func ensure() -> NotchChipPanel {
        if let panel { return panel }
        let created = NotchChipPanel(
            contentRect: NSRect(origin: .zero, size: NotchMath.collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.isFloatingPanel = true
        created.level = .statusBar
        created.hidesOnDeactivate = false
        created.becomesKeyOnlyIfNeeded = true
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = false
        created.isMovable = false
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel = created
        return created
    }
}
