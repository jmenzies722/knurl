import AppKit
import CoreGraphics
import KnurlCore
import QuartzCore
import SwiftUI

final class NotchChipPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        AppDelegate.shared?.state.collapseNotch()
    }
}

@MainActor
final class NotchPanel {
    static let shared = NotchPanel()

    private var panel: NotchChipPanel?
    private var observer: Any?

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
                        NotchPanel.shared.expand()
                    } else {
                        NotchPanel.shared.collapse()
                    }
                }
            }
        }
    }

    func expand() {
        guard let screen = notchedScreen(),
              let housing = housing(on: screen)
        else {
            panel?.orderOut(nil)
            return
        }
        let panel = ensure()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.38
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(
                NotchMath.expandedFrame(housing: housing, visible: screen.visibleFrame),
                display: true
            )
        }
        panel.orderFront(nil)
    }

    func collapse() {
        guard let screen = notchedScreen(),
              let housing = housing(on: screen)
        else {
            panel?.orderOut(nil)
            return
        }
        let panel = ensure()
        panel.resignKey()
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
