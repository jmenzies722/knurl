import AppKit
import SwiftUI

final class DialHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        if AppDelegate.shared?.state.handleKey(event) == true { return }
        super.keyDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        AppDelegate.shared?.state.handleScroll(event)
    }
}

final class DialPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        AppDelegate.shared?.state.dismiss()
    }

    override func keyDown(with event: NSEvent) {
        if AppDelegate.shared?.state.handleKey(event) == true { return }
        super.keyDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        AppDelegate.shared?.state.handleScroll(event)
    }
}

@MainActor
final class HUDPanel {
    static let shared = HUDPanel()

    private static let edgeKey = "knurl.dock.trailing"
    private static let yKey = "knurl.dock.y"
    private var panel: DialPanel?
    private var monitors: [Any] = []
    private var suppressMove = false
    private let collapsedSize = NSSize(width: 92, height: 220)
    private let expandedSize = NSSize(width: 436, height: 800)

    private init() {}

    func attach(_ state: DialState) {
        let panel = ensurePanel()
        panel.contentView = DialHostingView(rootView: HUDView(state: state))
    }

    func parkCollapsed() {
        let panel = ensurePanel()
        dock(panel, expanded: false)
        panel.orderFront(nil)
        panel.resignKey()
        removeMonitors()
    }

    func show() {
        AppDelegate.shared?.noteHUDActivation()
        let panel = ensurePanel()
        dock(panel, expanded: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView)
        installMonitors()
    }

    func makeKey() {
        guard let panel else { return }
        AppDelegate.shared?.noteHUDActivation()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView)
        installMonitors()
    }

    func hide() {
        removeMonitors()
        rememberDock()
        panel?.orderOut(nil)
    }

    func resignForTarget() {
        panel?.resignKey()
    }

    func handOffMedia(_ work: () -> Void) {
        guard let panel else {
            work()
            return
        }
        panel.resignKey()
        work()
        panel.orderFront(nil)
        panel.makeFirstResponder(panel.contentView)
    }

    func revealWithoutKey() {
        panel?.orderFront(nil)
    }

    var frame: NSRect {
        panel?.frame ?? .zero
    }

    private func installMonitors() {
        removeMonitors()
        let panel = self.panel
        if let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { event in
            guard AppDelegate.shared?.state.isPresented == true else { return event }
            if let window = event.window, window != panel { return event }
            AppDelegate.shared?.state.handleScroll(event)
            return nil
        }) {
            monitors.append(scroll)
        }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            guard AppDelegate.shared?.state.isPresented == true else { return event }
            if let window = event.window, window != panel { return event }
            if AppDelegate.shared?.state.handleKey(event) == true { return nil }
            return event
        }) {
            monitors.append(keys)
        }
        if let hardware = NSEvent.addLocalMonitorForEvents(matching: .systemDefined, handler: { event in
            AppDelegate.shared?.state.handleSystemDefined(event)
            return event
        }) {
            monitors.append(hardware)
        }
    }

    private func removeMonitors() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
    }

    private func ensurePanel() -> DialPanel {
        if let panel { return panel }
        let created = DialPanel(
            contentRect: NSRect(origin: .zero, size: collapsedSize),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
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
        created.isMovableByWindowBackground = false
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        created.animationBehavior = .utilityWindow
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: created,
            queue: .main
        ) { _ in
            Task { @MainActor in
                HUDPanel.shared.handleMoved()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                HUDPanel.shared.redock()
            }
        }
        panel = created
        return created
    }

    private func handleMoved() {
        guard !suppressMove else { return }
        rememberDock()
        guard NSEvent.pressedMouseButtons == 0 else { return }
        snapToEdge()
    }

    private func redock() {
        guard let panel else { return }
        dock(panel, expanded: AppDelegate.shared?.state.isPresented == true)
    }

    private func snapToEdge() {
        guard let panel else { return }
        let screen = screen(containing: panel.frame)
        UserDefaults.standard.set(panel.frame.midX > screen.midX, forKey: Self.edgeKey)
        rememberDock()
        dock(panel, expanded: AppDelegate.shared?.state.isPresented == true, screen: screen)
    }

    private func dock(_ panel: DialPanel, expanded: Bool, screen: NSRect? = nil) {
        suppressMove = true
        panel.setFrame(dockedFrame(expanded: expanded, screen: screen), display: true, animate: true)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            suppressMove = false
        }
    }

    private func rememberDock() {
        guard let panel else { return }
        UserDefaults.standard.set(panel.frame.midY, forKey: Self.yKey)
        UserDefaults.standard.set(panel.frame.midX > screen(containing: panel.frame).midX, forKey: Self.edgeKey)
    }

    private func dockedFrame(expanded: Bool, screen: NSRect? = nil) -> NSRect {
        let visible = screen ?? dockScreen()
        let size = expanded ? expandedSize : collapsedSize
        let trailing = UserDefaults.standard.object(forKey: Self.edgeKey) as? Bool ?? true
        let x = trailing ? visible.maxX - size.width : visible.minX
        let storedY = UserDefaults.standard.object(forKey: Self.yKey) as? CGFloat
        let midY = storedY ?? visible.midY
        let y = min(max(visible.minY + 24, midY - size.height / 2), visible.maxY - size.height - 24)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func dockScreen() -> NSRect {
        if let panel {
            return screen(containing: panel.frame)
        }
        return NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
    }

    private func screen(containing rect: NSRect) -> NSRect {
        let match = NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(rect).width * lhs.frame.intersection(rect).height
                < rhs.frame.intersection(rect).width * rhs.frame.intersection(rect).height
        }
        return match?.visibleFrame ?? NSScreen.main?.visibleFrame ?? rect
    }
}
