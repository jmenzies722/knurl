import AppKit
import AudioToolbox
import KnurlCore

enum Preferences {
    private static let soundKey = "knurl.tick.sound"
    private static let hapticKey = "knurl.tick.haptic"
    private static let modeKey = "knurl.last.mode"
    private static let outputKey = "knurl.output.memory"
    private static let airPlayKey = "knurl.airplay.memory"
    private static let hubFrameKey = "knurl.hub.frame"
    private static let windowManagerKey = "knurl.window.manager"
    private static let powerModeKey = "knurl.power.mode"
    private static let hubOrderKey = "knurl.hub.order"
    private static let clipboardShelfKey = "knurl.clipboard.shelf"
    private static let weatherKey = "knurl.weather.enabled"

    static var sound: TickSound {
        get { TickSound(rawValue: UserDefaults.standard.string(forKey: soundKey) ?? "") ?? .tink }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: soundKey) }
    }

    static var haptic: Bool {
        get {
            if UserDefaults.standard.object(forKey: hapticKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: hapticKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: hapticKey) }
    }

    static var lastMode: DialMode {
        get { DialMode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .media }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    static var hubFrame: NSRect? {
        get {
            guard let stored = UserDefaults.standard.string(forKey: hubFrameKey) else { return nil }
            let frame = NSRectFromString(stored)
            return frame.width > 0 && frame.height > 0 ? frame : nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(NSStringFromRect(newValue), forKey: hubFrameKey)
            }
        }
    }

    static var windowManagerEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: windowManagerKey) }
        set { UserDefaults.standard.set(newValue, forKey: windowManagerKey) }
    }

    /// The clipboard shelf is off until asked for. It only ever lives in
    /// memory, so this flag is the single place that decides whether Knurl
    /// looks at the pasteboard at all.
    static var clipboardShelf: Bool {
        get { UserDefaults.standard.bool(forKey: clipboardShelfKey) }
        set { UserDefaults.standard.set(newValue, forKey: clipboardShelfKey) }
    }

    /// Weather is the only tool that leaves this Mac and the only one that
    /// needs Location, so it stays off until it is asked for.
    static var weatherEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: weatherKey) }
        set { UserDefaults.standard.set(newValue, forKey: weatherKey) }
    }

    static var powerMode: PowerMode {
        get { PowerMode(rawValue: UserDefaults.standard.string(forKey: powerModeKey) ?? "") ?? .balanced }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: powerModeKey) }
    }

    /// The order the six Hub pages sit in the rail. Unknown or missing cases
    /// fall back to declaration order, so adding a page never strands it.
    static var hubOrder: [HubPage] {
        get {
            let stored = (UserDefaults.standard.array(forKey: hubOrderKey) as? [String]) ?? []
            var pages = stored.compactMap(HubPage.init(rawValue:))
            var seen = Set(pages)
            for page in HubPage.allCases where !seen.contains(page) {
                pages.append(page)
                seen.insert(page)
            }
            return pages
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue), forKey: hubOrderKey)
        }
    }

    static var outputMemory: OutputMemory {
        get {
            guard let data = UserDefaults.standard.data(forKey: outputKey),
                  let memory = try? JSONDecoder().decode(OutputMemory.self, from: data)
            else { return OutputMemory() }
            return memory
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: outputKey)
        }
    }

    static var airPlayMemory: AirPlayMemory {
        get {
            guard let data = UserDefaults.standard.data(forKey: airPlayKey),
                  let memory = try? JSONDecoder().decode(AirPlayMemory.self, from: data)
            else { return AirPlayMemory() }
            return memory
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: airPlayKey)
        }
    }
}

@MainActor
enum DialTick {
    private static var lastPlay = Date.distantPast
    private static let gap: TimeInterval = 0.08

    static func play(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastPlay) >= gap else { return }
        lastPlay = now
        if Preferences.haptic { haptic() }
        click()
    }

    private static func haptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private static func click() {
        guard let name = Preferences.sound.fileName else { return }
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        if let sound = NSSound(contentsOf: url, byReference: true) {
            sound.volume = 0.55
            sound.play()
            return
        }
        AudioServicesPlaySystemSound(1104)
    }
}

enum HardwareKeys {
    static func soundUp() { post(0) }
    static func soundDown() { post(1) }
    static func soundMute() { post(7) }
    static func brightnessUp() { post(2) }
    static func brightnessDown() { post(3) }
    static func play() { postMedia(16) }
    static func nextTrack() { postMedia(17) }
    static func previousTrack() { postMedia(18) }

    @discardableResult
    static func post(_ key: Int32, sessionOnly: Bool = false) -> Bool {
        let down = pulse(key, down: true, sessionOnly: sessionOnly)
        Thread.sleep(forTimeInterval: 0.012)
        let up = pulse(key, down: false, sessionOnly: sessionOnly)
        return down && up
    }

    /// One HID pulse. Both taps after resign made Music see play twice (no-op)
    /// and skip two tracks.
    @discardableResult
    static func postMedia(_ key: Int32) -> Bool {
        let down = pulse(key, down: true, hidOnly: true)
        let up = pulse(key, down: false, hidOnly: true)
        return down && up
    }

    private static func pulse(
        _ key: Int32,
        down: Bool,
        sessionOnly: Bool = false,
        hidOnly: Bool = false
    ) -> Bool {
        let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
        let data1 = Int((Int(key) << 16) | (Int(down ? 0xA : 0xB) << 8))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ), let cgEvent = event.cgEvent else { return false }
        if hidOnly {
            cgEvent.post(tap: .cghidEventTap)
            return true
        }
        if !sessionOnly {
            cgEvent.post(tap: .cghidEventTap)
        }
        cgEvent.post(tap: .cgSessionEventTap)
        return true
    }
}
