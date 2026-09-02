import AppKit
import Carbon

private func knurlHotkeyCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    if let event {
        _ = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
    }
    let released = event.map { GetEventKind($0) == UInt32(kEventHotKeyReleased) } ?? false
    DispatchQueue.main.async {
        switch hotKeyID.id {
        case 2:
            if !released { AppDelegate.shared?.state.nudge(1) }
        case 3:
            if !released { AppDelegate.shared?.state.nudge(-1) }
        case 4:
            if released {
                AppDelegate.shared?.state.endTalk()
            } else {
                AppDelegate.shared?.state.beginTalkFromHotkey()
            }
        default:
            if !released { AppDelegate.shared?.state.summon() }
        }
    }
    return noErr
}

@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    static let keyCode = UInt32(kVK_ANSI_K)
    static let modifiers = UInt32(controlKey | optionKey)

    private var handler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    private(set) var lastError: String?

    private init() {}

    var chord: String { "⌃⌥K" }
    var talkChord: String { "⌃⌥M" }

    func start() {
        installHandler()
        reregister()
    }

    func reregister() {
        for key in hotKeys { UnregisterEventHotKey(key) }
        hotKeys = []
        let specs: [(UInt32, UInt32, UInt32)] = [
            (UInt32(kVK_ANSI_K), Self.modifiers, 1),
            (UInt32(kVK_UpArrow), Self.modifiers, 2),
            (UInt32(kVK_RightArrow), Self.modifiers, 2),
            (UInt32(kVK_DownArrow), Self.modifiers, 3),
            (UInt32(kVK_LeftArrow), Self.modifiers, 3),
            (UInt32(kVK_ANSI_M), Self.modifiers, 4),
        ]
        var registered: Set<UInt32> = []
        for spec in specs {
            if let ref = register(keyCode: spec.0, modifiers: spec.1, id: spec.2) {
                hotKeys.append(ref)
                registered.insert(spec.2)
            }
        }
        var parts: [String] = []
        if !registered.contains(1) {
            parts.append("Could not take ⌃⌥K. Another app may already own it.")
        }
        if !registered.contains(4) {
            parts.append("Could not take ⌃⌥M. Another app may already own it.")
        }
        lastError = parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func installHandler() {
        guard handler == nil else { return }
        var specs = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            ),
        ]
        var ref: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            knurlHotkeyCallback,
            2,
            &specs,
            nil,
            &ref
        )
        if status == noErr { handler = ref }
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4B4E524C), id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        return status == noErr ? ref : nil
    }
}
