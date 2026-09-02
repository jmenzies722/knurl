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

@MainActor
final class NotchPanel {
    static let shared = NotchPanel()

    private var panel: NotchChipPanel?
    private var observer: Any?
    private var escapeLocal: Any?
    private var escapeGlobal: Any?

    var hasHousing: Bool { notchedScreen() != nil }

    private init() {}

    func attach(_ state: DialState) {
        let panel = ensure()
        panel.contentView = NSHostingView(rootView: NotchView(state: state))
        collapse()
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    if AppDelegate.shared?.state.isNotchExpanded == true {
                        NotchPanel.shared.expand(
                            flow: AppDelegate.shared?.state.voice.isActive == true
                        )
                    } else {
                        NotchPanel.shared.collapse()
                    }
                }
            }
        }
    }

    func expand(flow: Bool = false) {
        guard let screen = notchedScreen(),
              let housing = housing(on: screen)
        else {
            ignoreEscape()
            panel?.orderOut(nil)
            return
        }
        let panel = ensure()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        let frame = expandedFrame(housing: housing, visible: screen.visibleFrame, flow: flow)
        AppDelegate.shared?.state.notchHousing = housing
        AppDelegate.shared?.state.notchExpanded = frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.38
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
        panel.orderFront(nil)
    }

    func collapse() {
        guard let screen = notchedScreen(),
              let housing = housing(on: screen)
        else {
            ignoreEscape()
            panel?.orderOut(nil)
            return
        }
        let panel = ensure()
        panel.resignKey()
        ignoreEscape()
        AppDelegate.shared?.state.notchHousing = housing
        AppDelegate.shared?.state.notchExpanded = housing
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(housing, display: true)
        } completionHandler: {
            Task { @MainActor in
                panel.isOpaque = true
                panel.backgroundColor = .black
            }
        }
        panel.orderFront(nil)
    }

    func watchFlowEscape() {
        guard escapeLocal == nil else { return }
        escapeLocal = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, AppDelegate.shared?.state.voice.isActive == true else {
                return event
            }
            AppDelegate.shared?.state.escapeNotch()
            return nil
        }
        escapeGlobal = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in
                guard AppDelegate.shared?.state.voice.isActive == true else { return }
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

    private func expandedFrame(housing: CGRect, visible: CGRect, flow: Bool) -> CGRect {
        let shelf = flow ? NotchMath.flowShelfHeight : NotchMath.shelfHeight
        return NotchMath.expandedFrame(housing: housing, visible: visible, shelf: shelf)
    }

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
            contentRect: NSRect(origin: .zero, size: CGSize(width: 160, height: 32)),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.isFloatingPanel = true
        created.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        created.hidesOnDeactivate = false
        created.becomesKeyOnlyIfNeeded = true
        created.isOpaque = true
        created.backgroundColor = .black
        created.hasShadow = false
        created.isMovable = false
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel = created
        return created
    }
}
