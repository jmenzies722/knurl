import AppKit
import KnurlCore

// MARK: - Off-main script execution
//
// `NSAppleScript` is not thread-safe, and an Apple Event round-trip to
// Music.app takes tens of milliseconds — occasionally far longer if Music is
// busy. The meters loop asked for a track snapshot every 400 ms and an AirPlay
// roster every 2 s, both synchronously on the main thread, so the Hub was
// blocked waiting on another process for a large slice of every second. That
// is what a profile of the running app showed at the top of the main thread,
// and it is why the dial could feel like it was catching.
//
// Every script now runs on one serial queue: never concurrently (which
// `NSAppleScript` does not allow) and never on the main thread (which is what
// made it visible).

enum MusicScript {
    private static let queue = DispatchQueue(
        label: "com.shualabs.knurl.applescript",
        qos: .userInitiated
    )

    struct Outcome: Sendable {
        var text: String?
        var error: String?
    }

    /// Compiled scripts, reused across calls. Only ever touched from `queue`,
    /// which is what makes the unchecked annotation true rather than hopeful.
    private nonisolated(unsafe) static var compiled: [String: NSAppleScript] = [:]

    /// Runs a script off the main thread and hands the result back.
    static func run(_ source: String) async -> Outcome {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: executeOnQueue(source))
            }
        }
    }

    /// Fire-and-forget, for commands whose result nobody reads.
    static func send(_ source: String) {
        queue.async { _ = executeOnQueue(source) }
    }

    /// Blocking, for the callers that need a descriptor back — artwork data,
    /// genre lists, and the commands whose success is checked inline.
    ///
    /// It still runs on the queue. That is the whole point: `NSAppleScript`
    /// is not thread-safe, and the corruption it produces is not a crash but
    /// a *wrong answer* — one script returning another's result. That is
    /// exactly what happened here. The background queue was added for the two
    /// polling reads and every other call was left on the main thread, so a
    /// track snapshot came back holding the AirPlay device list and the Hub
    /// cheerfully displayed a speaker as the song title.
    ///
    /// One queue, every script, no exceptions.
    static func descriptor(_ source: String) -> NSAppleEventDescriptor? {
        queue.sync { executeDescriptorOnQueue(source).0 }
    }

    static func descriptorWithError(_ source: String) -> (NSAppleEventDescriptor?, String?) {
        queue.sync { executeDescriptorOnQueue(source) }
    }

    private static func executeDescriptorOnQueue(
        _ source: String
    ) -> (NSAppleEventDescriptor?, String?) {
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else {
            guard let made = NSAppleScript(source: source) else {
                return (nil, "Couldn’t build that Music command.")
            }
            compiled[source] = made
            script = made
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error { return (nil, MusicApp.human(error)) }
        return (result, nil)
    }

    private static func executeOnQueue(_ source: String) -> Outcome {
        let (descriptor, error) = executeDescriptorOnQueue(source)
        return Outcome(text: descriptor?.stringValue, error: error)
    }
}

extension MusicAirPlayDevice {
    var asAudioDevice: AudioDevice {
        AudioDevice(id: 0, uid: uid, name: name, transport: .airPlay)
    }
}

@MainActor
enum MusicApp {
    public typealias Track = MusicSnapshot

    private(set) static var lastError: String?

    /// Whether Music.app is running.
    ///
    /// Cached for a second. This is checked before every script, and the
    /// uncached version walks every running process on the machine — at the
    /// rate the meters loop asks, that was showing up in a profile on its own.
    static var isOpen: Bool {
        if let checked = openCheckedAt, Date().timeIntervalSince(checked) < 1 {
            return openCache
        }
        openCache = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.Music"
        }
        openCheckedAt = Date()
        return openCache
    }

    private static var openCache = false
    private static var openCheckedAt: Date?

    static func ensureOpen() async {
        lastError = nil
        if isOpen { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else {
            lastError = "Music.app isn’t installed."
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        do {
            try await NSWorkspace.shared.openApplication(at: url, configuration: config)
            try await Task.sleep(for: .milliseconds(700))
        } catch {
            lastError = "Couldn’t open Music."
        }
    }

    static func reveal() {
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.Music"
        }) {
            app.activate()
            return
        }
        Task { await ensureOpen() }
    }

    nonisolated static let snapshotSource = """
        tell application "Music"
            try
                set stateText to player state as string
                set pos to player position
                set shuf to shuffle enabled as string
                set rept to song repeat as string
                if not (exists current track) then
                    return (character id 31) & (character id 31) & (character id 31) & stateText & (character id 31) & pos & (character id 31) & "0" & (character id 31) & shuf & (character id 31) & rept & (character id 31)
                end if
                set dur to 0
                set gen to ""
                try
                    set dur to duration of current track
                end try
                try
                    set gen to genre of current track as string
                end try
                return (name of current track) & (character id 31) & (artist of current track) & (character id 31) & (album of current track) & (character id 31) & stateText & (character id 31) & pos & (character id 31) & dur & (character id 31) & shuf & (character id 31) & rept & (character id 31) & gen
            on error
                return (character id 31) & (character id 31) & (character id 31) & "stopped" & (character id 31) & "0" & (character id 31) & "0" & (character id 31) & "false" & (character id 31) & "off" & (character id 31)
            end try
        end tell
        """

    /// The polling read, off the main thread. This is the one the meters loop
    /// uses; the synchronous `snapshot()` remains for the few callers that
    /// genuinely need an answer before they return.
    static func snapshotAsync() async -> Track? {
        guard isOpen else { return nil }
        let outcome = await MusicScript.run(snapshotSource)
        lastError = outcome.error
        guard let text = outcome.text else { return nil }
        return parseSnapshot(text)
    }

    static func snapshot() -> Track? {
        guard isOpen else { return nil }
        guard let text = runDescriptor(snapshotSource)?.stringValue else { return nil }
        return parseSnapshot(text)
    }

    nonisolated static func parseSnapshot(_ text: String) -> Track {
        MusicSnapshot.parse(text)
    }

    nonisolated static func cleanGenre(_ raw: String) -> String {
        MusicSnapshot.cleanGenre(raw)
    }

    static func recentGenres() -> [String] {
        guard isOpen else { return [] }
        let source = """
        tell application "Music"
            try
                if exists user playlist "Recently Played" then
                    return genre of every track of user playlist "Recently Played"
                end if
            end try
            return {}
        end tell
        """
        guard let desc = runDescriptor(source) else { return [] }
        var names: [String] = []
        var seen = Set<String>()
        func add(_ raw: String) {
            let name = cleanGenre(raw)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { return }
            names.append(name)
        }
        if desc.numberOfItems > 0 {
            for index in 1 ... desc.numberOfItems {
                if let name = desc.atIndex(index)?.stringValue { add(name) }
            }
        } else if let name = desc.stringValue {
            add(name)
        }
        return names
    }

    static func playGenre(_ name: String) -> Bool {
        let source = """
        tell application "Music"
            try
                play (every track of library playlist 1 whose genre is \(quote(name)))
            on error
                play (every file track whose genre is \(quote(name)))
            end try
        end tell
        """
        return runDescriptor(source) != nil
    }

    static func artwork() -> NSImage? {
        guard isOpen else { return nil }
        let source = """
        tell application "Music"
            try
                if not (exists current track) then return
                if (count of artworks of current track) < 1 then return
                return raw data of artwork 1 of current track
            on error
                return
            end try
        end tell
        """
        guard let data = runDescriptor(source)?.data, !data.isEmpty else { return nil }
        return NSImage(data: data)
    }

    static func userPlaylists() -> [String] {
        guard isOpen else { return [] }
        let source = """
        tell application "Music"
            try
                get name of every user playlist
            on error
                return {}
            end try
        end tell
        """
        guard let desc = runDescriptor(source) else { return [] }
        var names: [String] = []
        if desc.numberOfItems > 0 {
            for index in 1 ... desc.numberOfItems {
                if let name = desc.atIndex(index)?.stringValue, !name.isEmpty {
                    names.append(name)
                }
            }
        } else if let name = desc.stringValue, !name.isEmpty {
            names.append(name)
        }
        return names.filter { !Self.hiddenPlaylists.contains($0) }
    }

    static func playPause() {
        _ = runDescriptor("""
        tell application "Music"
            try
                playpause
            end try
        end tell
        """)
    }

    static func nextTrack() {
        _ = runDescriptor("""
        tell application "Music"
            try
                next track
            end try
        end tell
        """)
    }

    static func previousTrack() {
        _ = runDescriptor("""
        tell application "Music"
            try
                previous track
            end try
        end tell
        """)
    }

    static func playPlaylist(_ name: String) -> Bool {
        let source = """
        tell application "Music"
            play (first user playlist whose name is \(quote(name)))
        end tell
        """
        return runDescriptor(source) != nil
    }

    static func setPosition(_ seconds: Double) {
        let value = String(format: "%.2f", max(0, seconds))
        _ = runDescriptor("""
        tell application "Music"
            try
                set player position to \(value)
            end try
        end tell
        """)
    }

    static func setShuffle(_ on: Bool) {
        _ = runDescriptor("""
        tell application "Music"
            try
                set shuffle enabled to \(on ? "true" : "false")
            end try
        end tell
        """)
    }

    static func airPlayDevicesAsync() async -> [MusicAirPlayDevice] {
        guard isOpen else { return [] }
        let outcome = await MusicScript.run(airPlaySource)
        lastError = outcome.error
        guard let text = outcome.text else { return [] }
        return MusicAirPlayDevice.parseList(text)
    }

    nonisolated static let airPlaySource = """
        tell application "Music"
            try
                set out to ""
                repeat with d in AirPlay devices
                    if (supports audio of d) then
                        set out to out & name of d & tab & (kind of d as string) & tab & (selected of d as string) & tab & (available of d as string) & (character id 31)
                    end if
                end repeat
                return out
            on error
                return ""
            end try
        end tell
        """

    static func airPlayDevices() -> [MusicAirPlayDevice] {
        guard isOpen else { return [] }
        guard let text = runDescriptor(airPlaySource)?.stringValue else { return [] }
        return MusicAirPlayDevice.parseList(text)
    }

    @discardableResult
    static func selectAirPlay(_ name: String) -> Bool {
        let source = """
        tell application "Music"
            set current AirPlay devices to {AirPlay device \(quote(name))}
        end tell
        """
        return runDescriptor(source) != nil
    }

    @discardableResult
    static func selectComputerAirPlay() -> Bool {
        let source = """
        tell application "Music"
            try
                set current AirPlay devices to {first AirPlay device whose kind is computer}
                return true
            on error
                return false
            end try
        end tell
        """
        return runDescriptor(source) != nil
    }

    static func setAirPlayVolume(_ name: String, percent: Int) {
        let level = min(100, max(0, percent))
        _ = runDescriptor("""
        tell application "Music"
            try
                set sound volume of AirPlay device \(quote(name)) to \(level)
            end try
        end tell
        """)
    }

    static func setRepeat(_ mode: RepeatMode) {
        _ = runDescriptor("""
        tell application "Music"
            try
                set song repeat to \(mode.appleScript)
            end try
        end tell
        """)
    }

    private static let hiddenPlaylists: Set<String> = [
        "Library", "Music", "Downloaded", "Genius", "Music Videos",
    ]

    private static func quote(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    @discardableResult
    private static func runDescriptor(_ source: String) -> NSAppleEventDescriptor? {
        let (descriptor, error) = MusicScript.descriptorWithError(source)
        lastError = error
        return descriptor
    }

    nonisolated static func human(_ error: NSDictionary) -> String {
        let code = error[NSAppleScript.errorNumber] as? Int ?? 0
        if code == -1743 {
            return "Allow Knurl to control Music in Settings → Privacy → Automation."
        }
        if let message = error[NSAppleScript.errorMessage] as? String, !message.isEmpty {
            return message
        }
        return "Music didn’t accept that command."
    }
}
