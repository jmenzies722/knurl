import KnurlCore
import SwiftUI

// MARK: - Home
//
// The live room. Reading order is deliberately the order you care about: what
// time it is, what the desk is doing, where the dial is, what is playing, and
// only then how the machine is holding up.

struct HubHome: View {
    @Bindable var state: DialState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.knurlOnScreen) private var onScreen

    private var live: KnurlLiveliness {
        KnurlLiveliness(reduceMotion: reduceMotion, powerAllows: state.desk.allowsDecorativeMotion)
    }

    var body: some View {
        HubPageScroll {
            atmosphere
            crown
            nowPlaying
            vitals
        }
        .animation(live.motion(), value: state.volumePercent)
        .animation(live.motion(), value: state.brightnessPercent)
        .animation(live.motion(), value: state.outputUID)
        .animation(live.motion(KnurlMotion.heavy), value: state.control)
        .animation(live.motion(), value: state.desk.timer.running)
        .animation(live.motion(), value: state.music.title)
        .animation(live.motion(), value: state.voice.isListening)
    }

    // MARK: Header

    @ViewBuilder
    private var atmosphere: some View {
        if onScreen {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                header(at: timeline.date)
            }
        } else {
            header(at: Date())
        }
    }

    private func header(at date: Date) -> some View {
        Group {
            HubHallHeader(title: clock(date), whisper: whisper) {
                HStack(spacing: KnurlSpace.tight) {
                    HubGlassButton(
                        title: state.desk.timer.running ? state.desk.timer.readout : "Hour",
                        symbol: "timer",
                        tint: KnurlPalette.warn,
                        selected: state.desk.timer.running
                    ) {
                        state.hubPage = .tools
                    }
                    HubGlassButton(
                        title: state.voice.isListening ? "Listening" : "Flow",
                        symbol: state.voice.isListening ? "waveform" : "mic.fill",
                        tint: KnurlPalette.live,
                        selected: state.voice.isListening
                    ) {
                        state.hubPage = .flow
                    }
                    if state.desk.tools.awake {
                        HubGlassButton(
                            title: state.desk.tools.awakeLabel,
                            symbol: "eye.fill",
                            tint: KnurlPalette.warn,
                            selected: true
                        ) {
                            state.hubPage = .tools
                        }
                    }
                }
            }
        }
    }

    // MARK: The five faces

    // MARK: The crown

    private var crown: some View {
        DeskCrownBank(state: state, hero: state.control, compact: true)
            .padding(.vertical, KnurlSpace.snug)
    }

    // MARK: Now playing

    @ViewBuilder
    private var nowPlaying: some View {
        if !state.music.hasTrack {
            HubSection(title: "Playing") {
                HStack(spacing: KnurlSpace.step) {
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(KnurlPalette.inkFaint)
                        .frame(width: 52, height: 52)
                        .background {
                            RoundedRectangle(cornerRadius: KnurlRadius.chip, style: .continuous)
                                .fill(KnurlPalette.sunken)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nothing playing")
                            .font(.knurlBody.weight(.semibold))
                            .foregroundStyle(KnurlPalette.inkSoft)
                        Text("Knurl follows Music.app. Start something and the dial becomes the playhead.")
                            .font(.knurlEyebrow.weight(.regular))
                            .foregroundStyle(KnurlPalette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    HubGlassButton(
                        title: "Open Music",
                        symbol: "play.fill",
                        tint: HubTint.face(.media, progress: 0.6, muted: false)
                    ) {
                        state.revealMusic()
                    }
                }
                .padding(KnurlSpace.step)
                .knurlSurface(.sunken)
            }
        } else {
            HubSection(title: "Playing", accessory: state.music.genre.isEmpty ? nil : state.music.genre) {
                VStack(spacing: KnurlSpace.step) {
                    HStack(alignment: .top, spacing: KnurlSpace.step) {
                        artwork
                        VStack(alignment: .leading, spacing: KnurlSpace.hair) {
                            HStack(spacing: KnurlSpace.snug) {
                                KnurlEqualizer(
                                    tint: HubTint.face(.media, progress: 0.6, muted: false),
                                    bars: 4,
                                    active: state.music.isPlaying,
                                    lively: live.lively,
                                    height: 14
                                )
                                Text(state.music.isPlaying ? "Playing" : "Paused")
                                    .font(.knurlEyebrow)
                                    .foregroundStyle(KnurlPalette.inkFaint)
                            }
                            .padding(.bottom, 2)
                            Text(state.music.title)
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(KnurlPalette.ink)
                                .lineLimit(2)
                            if !state.music.artist.isEmpty {
                                Text(state.music.artist)
                                    .font(.knurlBody)
                                    .foregroundStyle(KnurlPalette.inkSoft)
                                    .lineLimit(1)
                            }
                            if !state.music.album.isEmpty {
                                Text(state.music.album)
                                    .font(.knurlEyebrow.weight(.regular))
                                    .foregroundStyle(KnurlPalette.inkFaint)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: KnurlSpace.snug)
                            transport
                        }
                        Spacer(minLength: 0)
                    }
                    playhead
                }
                .padding(KnurlSpace.step)
                .knurlSurface(
                    .card,
                    tint: HubTint.face(.media, progress: state.music.displayedPlayhead(), muted: false),
                    glow: state.music.isPlaying ? 0.3 : 0
                )
            }
        }
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: KnurlRadius.chip, style: .continuous)
                .fill(KnurlPalette.sunken)
            if let cover = state.music.cover, state.music.hasTrack {
                Image(nsImage: cover)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(KnurlPalette.inkFaint)
            }
        }
        .frame(width: 104, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: KnurlRadius.chip, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KnurlRadius.chip, style: .continuous)
                .strokeBorder(KnurlPalette.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
        .overlay(ImmediatePress { state.revealMusic() })
        .accessibilityLabel("Open in Music")
    }

    private var transport: some View {
        HStack(spacing: KnurlSpace.tight) {
            transportButton("shuffle", selected: state.music.shuffleOn) { state.toggleShuffle() }
            transportButton("backward.fill") { state.skip(-1) }
            Image(systemName: state.music.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 32)
                .background {
                    Capsule().fill(HubTint.face(.media, progress: 0.6, muted: false))
                }
                .shadow(color: HubTint.face(.media, progress: 0.6, muted: false).opacity(0.5), radius: 10, y: 2)
                .overlay(ImmediatePress { state.collapsedPlay() })
                .accessibilityLabel(state.music.isPlaying ? "Pause" : "Play")
            transportButton("forward.fill") { state.skip(1) }
            transportButton(state.music.repeatMode.symbol, selected: state.music.repeatMode != .off) {
                state.cycleRepeat()
            }
        }
    }

    private func transportButton(
        _ symbol: String,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(selected ? HubTint.face(.media, progress: 0.6, muted: false) : KnurlPalette.inkSoft)
            .frame(width: 32, height: 32)
            .background {
                Circle().fill(KnurlPalette.control)
            }
            .overlay {
                Circle().strokeBorder(KnurlPalette.hairline, lineWidth: 1)
            }
            .overlay(ImmediatePress(action: action))
            .accessibilityLabel(symbol)
    }

    @ViewBuilder
    private var playhead: some View {
        // Only worth a quarter-second timeline while it is both visible and
        // actually moving.
        if onScreen, state.music.isPlaying {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                playheadBody(at: timeline.date)
            }
        } else {
            playheadBody(at: Date())
        }
    }

    private func playheadBody(at now: Date) -> some View {
        Group {
            let progress = state.music.canSeek ? state.music.displayedPlayhead(at: now) : 0
            let elapsed = progress * state.music.duration
            VStack(spacing: KnurlSpace.tight) {
                KnurlMeter(
                    progress: progress,
                    tint: HubTint.face(.media, progress: progress, muted: false),
                    height: 5
                )
                HStack {
                    Text(state.music.canSeek ? DialMath.clock(elapsed) : "—")
                    Spacer()
                    Text(state.music.canSeek ? "−\(DialMath.clock(max(0, state.music.duration - elapsed)))" : "—")
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(KnurlPalette.inkFaint)
            }
        }
    }

    // MARK: Vitals

    private var vitals: some View {
        HubSection(title: "This Mac", accessory: nil) {
            HubVitalsRow(state: state)
        }
    }

    // MARK: Facts

    private var whisper: String {
        if state.voice.isListening { return "Listening. Words land in \(state.harnessName)." }
        if state.desk.timer.running { return "The hour is running. \(state.desk.timer.readout) left." }
        if state.music.hasTrack, state.music.isPlaying { return "\(state.music.line) · \(state.outputName)" }
        return "\(Date().formatted(.dateTime.weekday(.wide).month().day())) · \(state.outputName)"
    }

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func shortName(_ name: String) -> String {
        name.count > 12 ? String(name.prefix(11)) + "…" : name
    }
}
