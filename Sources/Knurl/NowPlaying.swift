import AppKit
import Foundation
import KnurlCore
@preconcurrency import MusicKit
import Observation

struct MusicSource: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case genre, playlist }

    let id: String
    let title: String
    let kind: Kind

    static func genre(_ name: String) -> MusicSource {
        MusicSource(id: "genre:\(name)", title: name, kind: .genre)
    }

    static func playlist(_ name: String) -> MusicSource {
        MusicSource(id: "playlist:\(name)", title: name, kind: .playlist)
    }
}

@MainActor
@Observable
final class NowPlaying {
    var title = ""
    var artist = ""
    var album = ""
    var genre = ""
    var cover: NSImage?
    var isPlaying = false
    var playhead = 0.0
    var timeLabel = "0:00"
    var remainingLabel = "0:00"
    var durationLabel = "0:00"
    var message: String?
    var sources: [MusicSource] = []
    var activeSourceID: String?
    var shuffleOn = false
    var repeatMode = RepeatMode.off
    var duration = 0.0

    private var lastArtTitle = ""
    private var lastSourcePull = Date.distantPast
    private var lastSnapshot = Date.distantPast
    private var stampedPosition = 0.0
    private var stampedAt = Date()
    private var seeking = false
    private var seekHoldUntil = Date.distantPast
    private var seekTask: Task<Void, Never>?
    private var quietUntil = Date.distantPast
    private var controlHoldUntil = Date.distantPast
    private var stoppedOwnPlayer = false

    var hasTrack: Bool { !title.isEmpty }
    var canSeek: Bool { duration > 1 }
    var line: String {
        [artist, album].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    var cardTitle: String {
        if !title.isEmpty { return title }
        if MusicApp.isOpen { return "Music" }
        return "Apple Music"
    }

    var cardArtist: String {
        if !line.isEmpty { return line }
        if let message { return message }
        if MusicApp.isOpen { return "Turn the dial to seek" }
        return "Opens Music.app"
    }

    func displayedPlayhead(at now: Date = Date()) -> Double {
        guard canSeek else { return 0 }
        if seeking { return playhead }
        let elapsed = isPlaying ? stampedPosition + now.timeIntervalSince(stampedAt) : stampedPosition
        return DialMath.clampVolume(elapsed / duration)
    }

    func prepare() {
        stopOwnPlayer()
        refresh(forceArt: true)
        Task { await ensureSources() }
    }

    func authorizeIfNeeded() async {
        await MusicApp.ensureOpen()
        await ensureSources()
        refresh(forceArt: true)
    }

    func playSource(_ id: String) async {
        if !MusicApp.isOpen { await MusicApp.ensureOpen() }
        activeSourceID = id
        let played: Bool
        if id.hasPrefix("genre:") {
            played = MusicApp.playGenre(String(id.dropFirst(6)))
        } else {
            let name = id.hasPrefix("playlist:") ? String(id.dropFirst(9)) : id
            played = MusicApp.playPlaylist(name)
        }
        if played {
            message = nil
            quietUntil = Date().addingTimeInterval(0.45)
            return
        }
        message = MusicApp.lastError ?? "Couldn’t start that in Music."
    }

    func toggle() async {
        let now = Date()
        if canSeek {
            stampedPosition = displayedPlayhead(at: now) * duration
            playhead = DialMath.clampVolume(stampedPosition / duration)
            applyClock(stampedPosition)
        }
        stampedAt = now
        isPlaying.toggle()
        message = nil
        await commandMusic {
            MusicApp.playPause()
        }
    }

    func skip(_ direction: Int) async {
        message = nil
        await commandMusic {
            if direction < 0 {
                MusicApp.previousTrack()
            } else {
                MusicApp.nextTrack()
            }
        }
    }

    func toggleShuffle() {
        shuffleOn.toggle()
        controlHoldUntil = Date().addingTimeInterval(0.45)
        MusicApp.setShuffle(shuffleOn)
    }

    func cycleRepeat() {
        repeatMode = repeatMode.next
        controlHoldUntil = Date().addingTimeInterval(0.45)
        MusicApp.setRepeat(repeatMode)
    }

    func seek(to progress: Double) {
        guard canSeek else { return }
        let clamped = DialMath.clampVolume(progress)
        playhead = clamped
        stampedPosition = clamped * duration
        stampedAt = Date()
        applyClock(stampedPosition)
        seeking = true
        seekHoldUntil = Date().addingTimeInterval(0.55)
        seekTask?.cancel()
        seekTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            MusicApp.setPosition(self.stampedPosition)
            let remain = self.seekHoldUntil.timeIntervalSinceNow
            if remain > 0 {
                try? await Task.sleep(for: .seconds(remain))
            }
            guard !Task.isCancelled else { return }
            self.seeking = false
        }
    }

    func revealMusic() {
        MusicApp.reveal()
    }

    func refresh(forceArt: Bool = false) {
        if Date() < quietUntil {
            applyClock(displayedElapsed())
            return
        }
        if !forceArt, !seeking, Date().timeIntervalSince(lastSnapshot) < 0.45 {
            applyClock(displayedElapsed())
            return
        }
        lastSnapshot = Date()
        guard let track = MusicApp.snapshot() else {
            if !MusicApp.isOpen {
                clearTrack()
            }
            if let error = MusicApp.lastError {
                message = error
            }
            return
        }
        title = track.title
        artist = track.artist
        album = track.album
        genre = track.genre
        promoteGenre(track.genre)
        if Date() >= quietUntil {
            isPlaying = track.isPlaying
        }
        duration = max(0, track.duration)
        if Date() >= controlHoldUntil {
            shuffleOn = track.shuffle
            repeatMode = track.repeatMode
        }
        let holdingSeek = seeking || Date() < seekHoldUntil
        if !holdingSeek {
            stampedPosition = max(0, track.position)
            stampedAt = Date()
            playhead = displayedPlayhead()
            applyClock(stampedPosition)
        }
        if track.title != lastArtTitle {
            lastArtTitle = track.title
            cover = track.title.isEmpty ? nil : MusicApp.artwork()
        } else if forceArt, cover == nil, !track.title.isEmpty {
            cover = MusicApp.artwork()
        }
        if let error = MusicApp.lastError, title.isEmpty {
            message = error
        }
    }

    private func commandMusic(_ work: () -> Void) async {
        if !MusicApp.isOpen { await MusicApp.ensureOpen() }
        work()
        quietUntil = Date().addingTimeInterval(0.35)
    }

    private func clearTrack() {
        title = ""
        artist = ""
        album = ""
        genre = ""
        cover = nil
        lastArtTitle = ""
        duration = 0
        playhead = 0
        isPlaying = false
        stampedPosition = 0
        timeLabel = "0:00"
        remainingLabel = "0:00"
        durationLabel = "0:00"
    }

    private func displayedElapsed() -> Double {
        guard canSeek else { return stampedPosition }
        return displayedPlayhead() * duration
    }

    private func applyClock(_ elapsed: Double) {
        timeLabel = DialMath.clock(elapsed)
        remainingLabel = DialMath.clock(max(0, duration - elapsed))
        durationLabel = DialMath.clock(duration)
    }

    private func ensureSources() async {
        await MusicApp.ensureOpen()
        guard Date().timeIntervalSince(lastSourcePull) > 8 || sources.isEmpty else { return }
        lastSourcePull = Date()
        var seen = Set<String>()
        var next: [MusicSource] = []
        func addGenre(_ raw: String) {
            let name = MusicApp.cleanGenre(raw)
            guard !name.isEmpty, seen.insert("genre:\(name.lowercased())").inserted else { return }
            next.append(.genre(name))
        }
        addGenre(genre)
        for name in MusicApp.recentGenres() { addGenre(name) }
        for name in MusicApp.userPlaylists() {
            next.append(.playlist(name))
        }
        sources = next
        if sources.isEmpty, let error = MusicApp.lastError {
            message = error
        }
    }

    private func promoteGenre(_ raw: String) {
        let name = MusicApp.cleanGenre(raw)
        guard !name.isEmpty else { return }
        let chip = MusicSource.genre(name)
        if let index = sources.firstIndex(where: { $0.id == chip.id }) {
            if index > 0 {
                sources.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
            }
            return
        }
        sources = [chip] + sources
    }

    private func stopOwnPlayer() {
        guard !stoppedOwnPlayer else { return }
        stoppedOwnPlayer = true
        let player = ApplicationMusicPlayer.shared
        if player.state.playbackStatus == .playing {
            player.pause()
        }
        player.stop()
    }
}
