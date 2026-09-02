import AppKit

enum RepeatMode: String, Sendable {
    case off
    case all
    case one

    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    var symbol: String {
        switch self {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }

    var appleScript: String {
        switch self {
        case .off: "off"
        case .all: "all"
        case .one: "one"
        }
    }

    static func parse(_ raw: String) -> RepeatMode {
        let text = raw.lowercased()
        if text.contains("one") { return .one }
        if text.contains("all") { return .all }
        return .off
    }
}

@MainActor
enum MusicApp {
    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var genre: String
        var isPlaying: Bool
        var position: Double
        var duration: Double
        var shuffle: Bool
        var repeatMode: RepeatMode
    }

    private(set) static var lastError: String?

    static var isOpen: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.Music"
        }
    }

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

    private static let snapshotScript = NSAppleScript(source: """
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
        """)

    static func snapshot() -> Track? {
        guard isOpen else { return nil }
        guard let text = runCached(snapshotScript)?.stringValue else { return nil }
        let parts = text.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
        func at(_ index: Int) -> String { parts.indices.contains(index) ? parts[index] : "" }
        return Track(
            title: at(0),
            artist: at(1),
            album: at(2),
            genre: Self.cleanGenre(at(8)),
            isPlaying: at(3).lowercased().contains("play"),
            position: Double(at(4)) ?? 0,
            duration: Double(at(5)) ?? 0,
            shuffle: at(6).lowercased().contains("true"),
            repeatMode: RepeatMode.parse(at(7))
        )
    }

    static func cleanGenre(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }
        if text.lowercased() == "missing value" { return "" }
        return text
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
        runCached(NSAppleScript(source: source))
    }

    @discardableResult
    private static func runCached(_ script: NSAppleScript?) -> NSAppleEventDescriptor? {
        lastError = nil
        guard let script else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            lastError = human(error)
            return nil
        }
        return result
    }

    private static func human(_ error: NSDictionary) -> String {
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
