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
    private var snapshotPull: Task<Void, Never>?
    private var musicObserver: NSObjectProtocol?

    /// True while a surface that shows the track is on screen. Parked, Knurl
    /// still follows Music.app — just at a third of the rate, because the
    /// playhead is interpolated between snapshots and nobody is reading the
    /// title of a window that is not open.
    var attentive = false

    /// How often to ask Music.app anything.
    ///
    /// Watching a playhead move on screen is the only case that needs a
    /// sub-second answer. Otherwise the position is interpolated from the last
    /// stamp against a local clock, and every real change — track, play,
    /// pause — arrives as a notification, so a parked Knurl only polls to
    /// correct drift. Five seconds of drift on an interpolated playhead is
    /// under a frame's worth of error.
    /// Even with the Hub open, two seconds is plenty.
    ///
    /// The playhead on screen is interpolated from the last stamp against a
    /// local clock, so polling faster does not make it smoother — it just
    /// asks another process the same question more often. Track changes and
    /// play/pause arrive as notifications, and Knurl's own commands update
    /// optimistically. A profile of the open Hub had a third of the main
    /// thread's time inside an Apple Event round-trip at the old half-second
    /// rate, and Music.app burning its own core answering.
    private var pollInterval: TimeInterval { attentive ? 2 : 5 }
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
        watchMusic()
        refresh(forceArt: true)
        Task { await ensureSources() }
    }

    // MARK: - Listening instead of asking
    //
    // Music.app posts `com.apple.Music.playerInfo` on every track change and
    // every play/pause. Knurl used to ignore that and ask twice a second
    // instead, forever — which cost this process about 28% of a core and made
    // Music.app burn another 13% answering, while the track was *paused* and
    // nothing was changing. Now the notification says when to look, and the
    // timer only runs while something is actually moving.

    private func watchMusic() {
        guard musicObserver == nil else { return }
        musicObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Bypass the interval: this is a real change, not a poll.
                self.lastSnapshot = .distantPast
                self.refresh()
            }
        }
    }

    /// Whether the timer still needs to ask.
    ///
    /// While playing, a low-rate poll keeps the playhead honest and catches a
    /// seek made inside Music.app. Paused or stopped, nothing moves, so
    /// nothing is asked — the notification will say when that changes.
    var needsPoll: Bool {
        isPlaying || seeking || Date() < controlHoldUntil || Date() < quietUntil
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
        if !forceArt, !seeking, Date().timeIntervalSince(lastSnapshot) < pollInterval {
            applyClock(displayedElapsed())
            return
        }
        lastSnapshot = Date()
        // The snapshot is an Apple Event to another process. Asking for it on
        // the main thread — sixty times a minute, forever — is what put the
        // Hub behind Music.app in a profile of the running app. One request in
        // flight at a time; the answer is applied when it arrives.
        guard snapshotPull == nil else {
            applyClock(displayedElapsed())
            return
        }
        snapshotPull = Task { @MainActor [weak self] in
            let track = await MusicApp.snapshotAsync()
            guard let self else { return }
            self.snapshotPull = nil
            self.apply(track, forceArt: forceArt)
        }
    }

    private func apply(_ track: MusicApp.Track?, forceArt: Bool) {
        guard let track else {
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
