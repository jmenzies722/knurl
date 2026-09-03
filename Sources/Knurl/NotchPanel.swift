import AppKit
import CoreGraphics
import KnurlCore
import QuartzCore
import SwiftUI

final class NotchChipPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        AppDelegate.shared?.state.escapeNotch()
    }
}

// MARK: - The notch panel
//
// One borderless panel, created once at the largest size any stage needs and
// never resized. Everything that moves is inside SwiftUI.
//
// The earlier version animated the window frame on every state change, which
// meant the window server was resizing while the content was laying out — the
// black edges tore, and a fast hover in and out could leave the panel the
// wrong size. A fixed frame removes the race entirely; the cost is that the
// panel is transparent over a larger area, which is why hover is detected
// from a mouse monitor against the housing rect rather than from the window.

@MainActor
final class NotchPanel {
    static let shared = NotchPanel()

    private var panel: NotchChipPanel?
    private var screenObserver: Any?
    private var escapeLocal: Any?
    private var escapeGlobal: Any?
    private var hoverLocal: Any?
    private var hoverGlobal: Any?
    private var closeWork: Task<Void, Never>?

    var hasHousing: Bool { notchedScreen() != nil }

    private init() {}

    func attach(_ state: DialState) {
        guard let screen = notchedScreen(), let housing = housing(on: screen) else { return }
        let panel = ensure()
        panel.contentView = NSHostingView(rootView: NotchView(state: state))
        state.notchHousing = housing
        state.notchExpanded = NotchMath.panelFrame(screen: screen.frame, housing: housing)
        panel.setFrame(state.notchExpanded, display: true)
        panel.orderFront(nil)
        watchHover()

        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in NotchPanel.shared.reposition() }
            }
        }
    }

    /// Display arrangement changed — a lid opened, a monitor arrived. The
    /// housing may have moved or stopped existing.
    func reposition() {
        guard let state = AppDelegate.shared?.state else { return }
        guard let screen = notchedScreen(), let housing = housing(on: screen) else {
            panel?.orderOut(nil)
            return
        }
        let frame = NotchMath.panelFrame(screen: screen.frame, housing: housing)
        state.notchHousing = housing
        state.notchExpanded = frame
        let panel = ensure()
        panel.setFrame(frame, display: true)
        panel.orderFront(nil)
    }

    func expand(flow: Bool = false) {
        _ = flow
        watchEscape()
        reposition()
    }

    func collapse() {
        if AppDelegate.shared?.state.voice.isActive != true {
            ignoreEscape()
        }
        reposition()
    }

    // MARK: Hover
    //
    // A pointer monitor rather than a tracking area: the panel is mostly
    // transparent and does not take key focus, so it cannot be relied on to
    // receive mouse-moved events for the region a person actually aims at.

    private func watchHover() {
        guard hoverGlobal == nil else { return }
        hoverGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { _ in
            Task { @MainActor in NotchPanel.shared.pointerMoved() }
        }
        hoverLocal = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            Task { @MainActor in NotchPanel.shared.pointerMoved() }
            return event
        }
    }

    private func pointerMoved() {
        guard let state = AppDelegate.shared?.state else { return }
        let housing = state.notchHousing
        guard housing.width > 1 else { return }
        let point = NSEvent.mouseLocation

        let inside: Bool
        if state.notchStage.isOpen {
            // Once open, the whole shape is a safe place for the pointer, so
            // crossing from the housing down onto a control does not close it.
            inside = NotchMath.openTarget(housing: housing, stage: state.notchStage).contains(point)
        } else {
            inside = NotchMath.hoverTarget(housing: housing).contains(point)
        }

        if inside {
            closeWork?.cancel()
            closeWork = nil
            if !state.notchHovered {
                state.notchHovered = true
                DialTick.play()
            }
        } else if state.notchHovered {
            // A short grace period, because the fastest way to make a hover
            // target feel broken is to close it the instant the pointer
            // clips a corner on the way to a button inside it.
            closeWork?.cancel()
            closeWork = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                AppDelegate.shared?.state.notchHovered = false
                if AppDelegate.shared?.state.isNotchExpanded == true,
                   AppDelegate.shared?.state.voice.isActive != true {
                    AppDelegate.shared?.state.collapseNotch()
                }
            }
        }
    }

    // MARK: Escape

    func watchFlowEscape() {
        watchEscape()
    }

    func watchEscape() {
        guard escapeLocal == nil else { return }
        escapeLocal = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            AppDelegate.shared?.state.escapeNotch()
            return nil
        }
        escapeGlobal = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in
                AppDelegate.shared?.state.escapeNotch()
            }
        }
    }

    func ignoreEscape() {
        if let escapeLocal {
            NSEvent.removeMonitor(escapeLocal)
            self.escapeLocal = nil
        }
        if let escapeGlobal {
            NSEvent.removeMonitor(escapeGlobal)
            self.escapeGlobal = nil
        }
    }

    // MARK: Geometry

    private func housing(on screen: NSScreen) -> CGRect? {
        NotchMath.housingFrame(
            screen: screen.frame,
            visible: screen.visibleFrame,
            leftAux: screen.auxiliaryTopLeftArea,
            rightAux: screen.auxiliaryTopRightArea
        )
    }

    private func notchedScreen() -> NSScreen? {
        NSScreen.screens.first {
            NotchMath.housingFrame(
                screen: $0.frame,
                visible: $0.visibleFrame,
                leftAux: $0.auxiliaryTopLeftArea,
                rightAux: $0.auxiliaryTopRightArea
            ) != nil
        }
    }

    private func ensure() -> NotchChipPanel {
        if let panel { return panel }
        let created = NotchChipPanel(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 520, height: 240)),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.isFloatingPanel = true
        // Above the menu bar, so the shape can flare out over it.
        created.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        created.hidesOnDeactivate = false
        created.becomesKeyOnlyIfNeeded = true
        // Clear and shadowless: the black belongs to the shape, not the
        // window. An opaque window would paint a rectangle behind the fillets
        // and undo the whole effect.
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = false
        created.isMovable = false
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel = created
        return created
    }
}
