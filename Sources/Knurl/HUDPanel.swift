import AppKit
import SwiftUI

final class DialHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private var hoverArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// `.activeAlways` matters: Knurl is usually the background app while you
    /// work, and the default tracking mode only fires in the key window, so
    /// SwiftUI's .onHover never sees the pointer over the pill.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        HUDPanel.shared.setPillHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        HUDPanel.shared.setPillHover(false)
    }

    override func keyDown(with event: NSEvent) {
        if AppDelegate.shared?.state.handleKey(event) == true { return }
        super.keyDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        if event.knurlIsHorizontal {
            super.scrollWheel(with: event)
            return
        }
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
        if event.knurlIsHorizontal {
            super.scrollWheel(with: event)
            return
        }
        AppDelegate.shared?.state.handleScroll(event)
    }
}

private extension NSEvent {
    var knurlIsHorizontal: Bool {
        abs(scrollingDeltaX) > abs(scrollingDeltaY) && abs(scrollingDeltaX) > 0.4
    }
}

@MainActor
final class HUDPanel {
    static let shared = HUDPanel()

    private static let xKey = "knurl.dock.x"
    private static let dialOriginKey = "knurl.dial.origin"
    private var panel: DialPanel?
    private var monitors: [Any] = []
    private var suppressMove = false
    private let pillSize = NSSize(width: 172, height: 52)
    private let pillHoveredSize = NSSize(width: 288, height: 52)
    private let pillListeningSize = NSSize(width: 330, height: 56)
    private let pillPagesSize = NSSize(width: 300, height: 52)
    /// Gap between the pill and the top of the Dock.
    private let dockGap: CGFloat = 10
    private var pillIsHovered = false
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
            if event.knurlIsHorizontal { return event }
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
            contentRect: NSRect(origin: .zero, size: pillSize),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Without this a borderless non-activating panel never delivers
        // mouse-moved events, so SwiftUI's .onHover never fires on the pill.
        created.acceptsMouseMovedEvents = true
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
        // The dial goes wherever you put it and stays there. Only the parked
        // pill is pinned to the rail above the Dock.
        if AppDelegate.shared?.state.isPresented == true {
            rememberDialOrigin()
            return
        }
        rememberDock()
        guard NSEvent.pressedMouseButtons == 0 else { return }
        snapToEdge()
    }

    private func rememberDialOrigin() {
        guard let panel else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: Self.dialOriginKey)
    }

    /// Forget the dial's parked position so it grows out of the pill again.
    func resetDialPosition() {
        UserDefaults.standard.removeObject(forKey: Self.dialOriginKey)
        guard let panel, AppDelegate.shared?.state.isPresented == true else { return }
        dock(panel, expanded: true)
    }

    private func redock() {
        guard let panel else { return }
        dock(panel, expanded: AppDelegate.shared?.state.isPresented == true)
    }

    /// The pill lives on the bottom rail. Dragging slides it along that rail;
    /// releasing settles it back above the Dock rather than flying to a side.
    private func snapToEdge() {
        guard let panel, AppDelegate.shared?.state.isPresented != true else { return }
        let screen = screen(containing: panel.frame)
        rememberDock()
        dock(panel, expanded: false, screen: screen)
    }

    /// Grows the pill when the pointer is over it, so the resting footprint
    /// stays as small as possible.
    /// Re-docks the pill after a state change that alters its width, such as
    /// Flow starting or stopping.
    func refreshPill() {
        guard let panel, AppDelegate.shared?.state.isPresented != true else { return }
        dock(panel, expanded: false)
    }

    func setPillHover(_ hovering: Bool) {
        guard pillIsHovered != hovering else { return }
        guard AppDelegate.shared?.state.isPresented != true else { return }
        pillIsHovered = hovering
        AppDelegate.shared?.state.pillHovered = hovering
        guard let panel else { return }
        dock(panel, expanded: false)
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
        UserDefaults.standard.set(panel.frame.midX, forKey: Self.xKey)
    }

    private func dockedFrame(expanded: Bool, screen: NSRect? = nil) -> NSRect {
        let visible = screen ?? dockScreen()
        let listening = AppDelegate.shared?.state.voice.isListening == true
        let pages = AppDelegate.shared?.state.pillShowsPages == true
        let parkedSize: NSSize = if listening {
            pillListeningSize
        } else if pages {
            pillPagesSize
        } else if pillIsHovered {
            pillHoveredSize
        } else {
            pillSize
        }
        let size = expanded ? expandedContentSize() : parkedSize

        // visibleFrame already excludes the Dock, so its minY is the Dock's top
        // edge on any Dock size, position or autohide setting. Both states share
        // that bottom anchor, so the dial grows up out of the pill rather than
        // jumping somewhere else on screen.
        let storedMidX = UserDefaults.standard.object(forKey: Self.xKey) as? CGFloat
        let midX = storedMidX ?? visible.midX
        let inset: CGFloat = expanded ? 16 : 8
        let x = min(max(visible.minX + inset, midX - size.width / 2), visible.maxX - size.width - inset)
        let height = min(size.height, visible.height - dockGap - 16)

        // A dial the user has moved keeps its own position; only its first
        // appearance grows out of the pill.
        if expanded, let stored = UserDefaults.standard.string(forKey: Self.dialOriginKey) {
            let origin = NSPointFromString(stored)
            let clampedX = min(max(visible.minX, origin.x), visible.maxX - size.width)
            let clampedY = min(max(visible.minY, origin.y), visible.maxY - height)
            return NSRect(x: clampedX, y: clampedY, width: size.width, height: height)
        }
        return NSRect(x: x, y: visible.minY + dockGap, width: size.width, height: height)
    }

    /// The dial panel should be exactly as tall as the dial, so it sits on the
    /// pill rather than floating inside a fixed 800pt window.
    private func expandedContentSize() -> NSSize {
        guard let content = panel?.contentView else { return expandedSize }
        let fitting = content.fittingSize
        guard fitting.height > 100 else { return expandedSize }
        return NSSize(width: expandedSize.width, height: fitting.height)
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
