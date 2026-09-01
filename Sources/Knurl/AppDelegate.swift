import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    let state = DialState()
    private var ignoreHubReopen = false
    private var consumeLaunchActivation = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.regular)
        installMenu()
        HUDPanel.shared.attach(state)
        HubWindow.shared.attach(state)
        NotchPanel.shared.attach(state)
        HotkeyCenter.shared.start()
        CrownServer.shared.start()
        state.hotkeyError = HotkeyCenter.shared.lastError
        StatusBar.shared.attach(
            target: self,
            show: #selector(showDial),
            hub: #selector(openHub),
            settings: #selector(openSettings),
            quit: #selector(quit)
        )
        state.startSession()
        state.park()
        consumeLaunchActivation = true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        consumeLaunchActivation = false
        openHub()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if consumeLaunchActivation {
            consumeLaunchActivation = false
            return
        }
        if ignoreHubReopen { return }
        if state.isPresented { return }
        if !HubWindow.shared.isVisible {
            openHub()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func noteHUDActivation() {
        ignoreHubReopen = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            self.ignoreHubReopen = false
        }
    }

    @objc func statusItemClicked() {
        StatusBar.shared.handleClick()
    }

    @objc func showDial() {
        noteHUDActivation()
        state.summon()
    }

    @objc func openHub() {
        state.presentHub()
    }

    @objc func openSettings() {
        state.presentHub()
        state.wantsSettings = true
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    private func installMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Knurl", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Knurl", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Knurl", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Open Knurl", action: #selector(openHub), keyEquivalent: "")
        windowMenu.addItem(withTitle: "Show Dial  \(HotkeyCenter.shared.chord)", action: #selector(showDial), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let windowItem = NSMenuItem()
        windowItem.title = "Window"
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }
}
