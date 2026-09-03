import Foundation

// MARK: - What Music.app is doing
//
// The parser lives here, away from AppKit, because a parser for another
// process's output is exactly the thing that needs tests — and a test target
// cannot import an executable target.
//
// It earned that: two AppleScripts running concurrently on different threads
// (which `NSAppleScript` does not allow) let the AirPlay roster arrive at this
// parser, which turned a speaker into a song and put "Josh-MacBook-Pro
// computer true true" on screen as the track title.

public enum RepeatMode: String, Sendable {
    case off
    case all
    case one

    public var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    public var symbol: String {
        switch self {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }

    public var appleScript: String {
        switch self {
        case .off: "off"
        case .all: "all"
        case .one: "one"
        }
    }

    public static func parse(_ raw: String) -> RepeatMode {
        let text = raw.lowercased()
        if text.contains("one") { return .one }
        if text.contains("all") { return .all }
        return .off
    }
}

public struct MusicSnapshot: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var genre: String
    public var isPlaying: Bool
    public var position: Double
    public var duration: Double
    public var shuffle: Bool
    public var repeatMode: RepeatMode

    public init(
        title: String = "",
        artist: String = "",
        album: String = "",
        genre: String = "",
        isPlaying: Bool = false,
        position: Double = 0,
        duration: Double = 0,
        shuffle: Bool = false,
        repeatMode: RepeatMode = .off
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.isPlaying = isPlaying
        self.position = position
        self.duration = duration
        self.shuffle = shuffle
        self.repeatMode = repeatMode
    }

    /// Fields are separated by the unit separator. A field containing a tab is
    /// rejected outright: the snapshot script never emits one, and the AirPlay
    /// roster uses tab as its column separator — so a tab here means this text
    /// is not a track and none of it should be shown as one.
    public static func parse(_ text: String) -> MusicSnapshot {
        let parts = text
            .split(separator: "\u{1f}", omittingEmptySubsequences: false)
            .map(String.init)

        func at(_ index: Int) -> String {
            guard parts.indices.contains(index) else { return "" }
            let field = parts[index]
            return field.contains("\t") ? "" : field
        }

        return MusicSnapshot(
            title: at(0),
            artist: at(1),
            album: at(2),
            genre: cleanGenre(at(8)),
            isPlaying: at(3).lowercased().contains("play"),
            position: Double(at(4)) ?? 0,
            duration: Double(at(5)) ?? 0,
            shuffle: at(6).lowercased().contains("true"),
            repeatMode: RepeatMode.parse(at(7))
        )
    }

    public static func cleanGenre(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }
        if text.lowercased() == "missing value" { return "" }
        return text
    }
}
