import AppKit
import KnurlCore
import SwiftUI

@MainActor
final class StatusBar {
    static let shared = StatusBar()

    private var item: NSStatusItem?
    private var menu: NSMenu?
    private var host: NSHostingView<StatusBarPill>?
    private var popover: NSPopover?
    private var lastWidth: CGFloat = 0

    private init() {}

    private var attachment: (target: AnyObject, show: Selector, hub: Selector, settings: Selector, quit: Selector)?

    /// Adds or removes the status item to match the preference.
    func setVisible(_ visible: Bool) {
        if visible {
            guard item == nil, let a = attachment else { return }
            attach(target: a.target, show: a.show, hub: a.hub, settings: a.settings, quit: a.quit)
        } else {
            closeShelf()
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            host = nil
        }
    }

    func attach(target: AnyObject, show: Selector, hub: Selector, settings: Selector, quit: Selector) {
        attachment = (target, show, hub, settings, quit)
        guard Preferences.menuBarItem else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }
        button.image = nil
        button.title = ""
        button.imagePosition = .noImage
        button.target = target
        button.action = #selector(AppDelegate.statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Knurl"
        if let state = AppDelegate.shared?.state {
            let host = NSHostingView(rootView: StatusBarPill(state: state))
            host.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                host.topAnchor.constraint(equalTo: button.topAnchor),
                host.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
            self.host = host
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Dial  \(HotkeyCenter.shared.chord)", action: show, keyEquivalent: "d")
        menu.addItem(withTitle: "Open Knurl", action: hub, keyEquivalent: "h")
        menu.addItem(withTitle: "Settings…", action: settings, keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Knurl", action: quit, keyEquivalent: "q")
        menu.items.forEach { $0.target = target }
        self.item = item
        self.menu = menu
        if let state = AppDelegate.shared?.state {
            refresh(state)
        }
    }

    func handleClick() {
        guard let event = NSApp.currentEvent else {
            toggleShelf()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            closeShelf()
            item?.menu = menu
            item?.button?.performClick(nil)
            item?.menu = nil
            return
        }
        toggleShelf()
    }

    func toggleShelf() {
        if popover?.isShown == true {
            closeShelf()
            return
        }
        guard let button = item?.button, let state = AppDelegate.shared?.state else { return }
        AppDelegate.shared?.noteHUDActivation()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let controller = NSHostingController(rootView: StatusBarShelf(state: state))
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 320, height: 220)
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func closeShelf() {
        popover?.performClose(nil)
        popover = nil
    }

    func refresh(_ state: DialState) {
        let live = state.menuBarLive
        let width = live.pillWidth
        if abs(width - lastWidth) > 0.5 {
            lastWidth = width
            item?.length = width
        }
        item?.button?.toolTip = [live.line, live.detail].filter { !$0.isEmpty }.joined(separator: " — ")
    }
}
