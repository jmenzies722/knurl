import AppKit
import KnurlCore
import SwiftUI

// MARK: - The notch
//
// Four stages of one object. Parked, it is a compact Live Activity under
// the housing: one glyph, one line, optional progress. Hovered, the dial
// and Tahoe-glass controls drop out of the bezel. Clicked, it becomes a
// shelf. Dictating, it becomes Flow.
//
// Nothing here draws glass on the housing itself: PRODUCT.md forbids it, and
// the reason is physical — the cutout has no pixels, so any material applied
// there is material applied to a black bezel, which reads as a smudge.

struct NotchView: View {
    @Bindable var state: DialState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lively: Bool {
        !reduceMotion && state.desk.allowsDecorativeMotion
    }

    private var stage: NotchStage { state.notchStage }

    var body: some View {
        NotchStageContainer(
            housing: state.notchHousing,
            stage: stage,
            lively: lively
        ) {
            VStack(spacing: 0) {
                housingBand
                    .frame(height: max(state.notchHousing.height, 1))
                content
                    .frame(height: stage.height)
                    .opacity(stage.isOpen || stage == .glance ? 1 : 0)
                    .animation(
                        lively ? .easeOut(duration: 0.18).delay(stage.isOpen ? 0.06 : 0) : nil,
                        value: stage
                    )
            }
        }
        .animation(motion, value: stage)
        .animation(motion, value: state.voice.preview)
        .animation(motion, value: whisper.line)
    }

    private var motion: Animation? {
        lively ? .spring(duration: 0.26, bounce: 0.05) : .easeOut(duration: 0.12)
    }

    /// The row level with the cutout. On the compact stage this is where the
    /// content lives — leading and trailing, flanking the camera — because
    /// there are no pixels behind the cutout itself to draw on.
    @ViewBuilder
    private var housingBand: some View {
        if stage == .glance {
            HStack(spacing: 0) {
                compactLeading
                    .frame(width: NotchStage.glance.flare)
                Color.clear
                    .frame(width: max(state.notchHousing.width, 1))
                compactTrailing
                    .frame(width: NotchStage.glance.flare)
            }
            .contentShape(Rectangle())
            .overlay(ImmediatePress { state.toggleNotch() })
            .accessibilityLabel(whisper.line)
            .accessibilityAddTraits(.isButton)
        } else {
            Color.clear
        }
    }

    /// Cover art while music plays, otherwise the glyph for whatever is
    /// running. Small, round, and hard against the cutout.
    @ViewBuilder
    private var compactLeading: some View {
        HStack {
            Spacer(minLength: 0)
            Group {
                if subject == .media, let cover = state.music.cover {
                    Image(nsImage: cover)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(systemName: compactSymbol)
                        .font(.system(size: 12, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(housingTint)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.trailing, 8)
        }
    }

    /// The live indicator: bars while a track plays, a closing ring for the
    /// hour, levels while dictating.
    @ViewBuilder
    private var compactTrailing: some View {
        HStack {
            Group {
                switch subject {
                case .media:
                    KnurlEqualizer(
                        tint: housingTint,
                        bars: 4,
                        active: state.music.isPlaying,
                        lively: lively,
                        height: 14
                    )
                case .flow:
                    KnurlEqualizer(
                        levels: state.voice.levels,
                        tint: KnurlPalette.live,
                        bars: 4,
                        active: true,
                        lively: lively,
                        height: 14
                    )
                case .hour:
                    NotchRing(
                        progress: state.desk.timer.crownProgress,
                        tint: housingTint,
                        size: 16
                    )
                case .dial:
                    KnurlPip(tint: housingTint, live: false, lively: lively, size: 6)
                }
            }
            .padding(.leading, 8)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .rest, .glance: Color.clear
        case .hover: hoverBar
        case .shelf: glanceShelf
        case .flow: flowShelf
        }
    }

    // MARK: Subject
    //
    // The notch shows whichever thing is actually happening, in this order:
    // dictation, then music, then the hour, then the dial. That order is the
    // design. The previous version showed one fixed menu — a mini dial, a
    // label and three buttons — no matter what was going on, so while a track
    // played it offered you a play button and no idea what was playing, and
    // while the hour ran it said nothing about the hour. A notch is a glance,
    // and a glance that shows the same thing always is a glance you stop
    // taking.

    private enum Subject {
        case flow
        case media
        case hour
        case dial
    }

    private var subject: Subject {
        if state.voice.isActive { return .flow }
        if state.music.hasTrack { return .media }
        if state.desk.timer.running { return .hour }
        return .dial
    }

    // MARK: Hover

    private var hoverBar: some View {
        HStack(spacing: 12) {
            switch subject {
            case .flow: flowLead
            case .media: mediaLead(art: 34)
            case .hour: hourLead
            case .dial: dialLead
            }

            Spacer(minLength: 4)

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    switch subject {
                    case .media:
                        notchGlassButton("backward.fill", "Previous") { state.skip(-1) }
                        notchGlassButton(
                            state.music.isPlaying ? "pause.fill" : "play.fill",
                            state.music.isPlaying ? "Pause" : "Play"
                        ) { state.collapsedPlay() }
                        notchGlassButton("forward.fill", "Next") { state.skip(1) }
                    case .hour:
                        notchGlassButton(
                            state.desk.timer.running ? "pause.fill" : "play.fill",
                            "Hour"
                        ) { state.toggleHour() }
                        notchGlassButton("square.grid.2x2.fill", "Open the Hub") { state.presentHub() }
                    case .flow, .dial:
                        notchGlassButton("dial.medium", "Open the dial") { state.summon() }
                        notchGlassButton(
                            state.voice.isActive ? "waveform" : "mic.fill",
                            "Knurl Flow"
                        ) { state.toggleTalk(presentHUD: false) }
                        notchGlassButton("square.grid.2x2.fill", "Open the Hub") { state.presentHub() }
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    /// Cover art, title, artist and a moving equaliser: the same four things
    /// every music app puts in a now-playing strip, because they are the four
    /// that answer "what is this".
    private func mediaLead(art: CGFloat) -> some View {
        HStack(spacing: 10) {
            Group {
                if let cover = state.music.cover {
                    Image(nsImage: cover).resizable().scaledToFill()
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: art * 0.42, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: art, height: art)
            .clipShape(RoundedRectangle(cornerRadius: art * 0.24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: art * 0.24, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(state.music.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    KnurlEqualizer(
                        tint: DialSwatch.media,
                        bars: 3,
                        active: state.music.isPlaying,
                        lively: lively,
                        height: 9
                    )
                    Text(state.music.artist.isEmpty ? "Music" : state.music.artist)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
        .overlay(ImmediatePress { state.expandNotch() })
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(state.music.title), \(state.music.artist)")
    }

    private var hourLead: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KnurlPalette.warn)
            VStack(alignment: .leading, spacing: 1) {
                Text(state.desk.timer.readout)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.95))
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                Text("left in the hour")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .contentShape(Rectangle())
        .overlay(ImmediatePress { state.expandNotch() })
    }

    private var flowLead: some View {
        HStack(spacing: 10) {
            KnurlEqualizer(
                levels: state.voice.levels,
                tint: KnurlPalette.live,
                bars: 5,
                active: true,
                lively: lively,
                height: 20
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(state.voice.preview.isEmpty ? "Listening…" : state.voice.preview)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .truncationMode(.head)
                Text("→ \(state.harnessName)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(KnurlPalette.live)
                    .lineLimit(1)
            }
        }
    }

    private var dialLead: some View {
        HStack(spacing: 10) {
            NotchMiniDial(state: state)
                .glassEffect(.regular.interactive(), in: Circle())
                .onTapGesture { state.summon() }
                .accessibilityLabel("Open the dial")
            VStack(alignment: .leading, spacing: 1) {
                Text(state.controlTitle.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.1)
                    .foregroundStyle(housingTint)
                Text(state.collapsedLine)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .overlay(ImmediatePress { state.expandNotch() })
    }

    private func notchGlassButton(
        _ symbol: String,
        _ label: String,
        action: @escaping () -> Void
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 32, height: 32)
            .glassEffect(.regular.interactive(), in: Circle())
            .contentTransition(.symbolEffect(.replace))
            .overlay(ImmediatePress(action: action))
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
    }

    // MARK: Shelf
    //
    // The click state, and the reason the menu bar item can go away on a
    // notched Mac. Everything a status item holds — what is playing, the
    // controls, the way into the Hub and the way out of the app — plus the one
    // thing no other notch has: a dial you can actually turn, on the five
    // faces, without opening anything.

    private var glanceShelf: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                switch subject {
                case .flow: flowLead
                case .media: mediaLead(art: 40)
                case .hour: hourLead
                case .dial: dialLead
                }
                Spacer(minLength: 4)
                if subject == .media {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            notchGlassButton("backward.fill", "Previous") { state.skip(-1) }
                            notchGlassButton(
                                state.music.isPlaying ? "pause.fill" : "play.fill",
                                state.music.isPlaying ? "Pause" : "Play"
                            ) { state.collapsedPlay() }
                            notchGlassButton("forward.fill", "Next") { state.skip(1) }
                        }
                    }
                }
            }

            if let progress = housingProgress {
                KnurlMeter(progress: progress, tint: housingTint, height: 3, showsTrack: true)
            }

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)

            deskRow
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .accessibilityLabel("\(whisper.line). \(whisper.detail)")
    }

    /// A working crown, the five faces, and the exits.
    private var deskRow: some View {
        HStack(spacing: 14) {
            DeskCrown(
                progress: state.controlProgress,
                tint: DialSwatch.tint(state.control, state: state),
                symbol: state.control.symbol,
                readout: state.controlReadout,
                caption: state.control.title,
                ticks: state.control == .output ? max(state.outputDevices.count, 2) : 11,
                size: 78,
                lively: state.desk.allowsDecorativeMotion,
                metal: .graphite,
                onTurn: { state.applyControl($0, settleOutput: false) },
                onConfirm: { state.confirmDial() },
                onEnded: { if state.control == .output { state.finishOutputTurn() } }
            )

            VStack(alignment: .leading, spacing: 7) {
                NotchScrubber(
                    symbol: state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    progress: state.volumeProgress,
                    tint: DialSwatch.tint(.volume, state: state),
                    label: "Volume"
                ) { state.setRoomVolume($0) }

                NotchScrubber(
                    symbol: "sun.max.fill",
                    progress: Double(state.brightnessPercent) / 100,
                    tint: DialSwatch.bright,
                    label: "Brightness"
                ) { state.setRoomBrightness($0) }

                HStack(spacing: 8) {
                    notchTextButton("Hub") { state.presentHub() }
                    notchTextButton("Settings") { AppDelegate.shared?.openSettings() }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func notchTextButton(_ title: String, action: @escaping () -> Void) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: Capsule())
            .overlay(ImmediatePress(action: action))
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title)
    }

    // MARK: Flow

    private var flowShelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                flowLead
                Spacer(minLength: 8)
                if state.voice.isActive {
                    notchCapsule("Cancel") { state.cancelTalk() }
                } else if !state.voice.lastTranscript.isEmpty {
                    notchCapsule("Resend") { state.resendTalk() }
                }
                holdCapsule
            }
            Text(flowLine)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .accessibilityLabel("\(flowLine). \(state.harnessName)")
    }

    private var holdCapsule: some View {
        Text(state.voice.isActive ? "Release" : "Hold")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule().fill(KnurlPalette.live.opacity(state.voice.isActive ? 0.55 : 0.18))
            }
            .overlay { Capsule().strokeBorder(KnurlPalette.live.opacity(0.5), lineWidth: 1) }
            .overlay(
                ImmediateHold(
                    down: { state.beginTalk(presentHUD: false) },
                    up: { state.endTalk() }
                )
            )
            .accessibilityLabel(state.voice.isActive ? "Release Flow" : "Hold Flow")
            .accessibilityAddTraits(.isButton)
    }

    private func notchCapsule(_ title: String, action: @escaping () -> Void) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background { Capsule().fill(.white.opacity(0.10)) }
            .overlay { Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 1) }
            .overlay(ImmediatePress(action: action))
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title)
    }

    // MARK: Facts

    private var whisper: NotchWhisper {
        state.desk.whisper(
            listening: state.voice.isActive,
            destination: state.harnessName,
            musicTitle: state.music.hasTrack ? state.music.title : nil
        )
    }

    private var compactSymbol: String {
        if case .music = whisper {
            return state.music.isPlaying ? "pause.fill" : "play.fill"
        }
        return whisper.symbol
    }

    private var compactIsLive: Bool {
        state.voice.isActive || state.desk.timer.running || state.music.isPlaying
            || !state.desk.attention.isEmpty
    }

    /// One colour, chosen by what is actually happening.
    private var housingTint: Color {
        if state.voice.isActive { return KnurlPalette.live }
        if !state.desk.attention.isEmpty { return KnurlPalette.alert }
        if state.desk.timer.running { return KnurlPalette.warn }
        if state.music.isPlaying { return DialSwatch.media }
        return DialSwatch.tint(state.control, state: state)
    }

    private var housingProgress: Double? {
        if state.desk.timer.running { return state.desk.timer.crownProgress }
        if state.music.isPlaying, state.music.canSeek { return state.music.displayedPlayhead() }
        return nil
    }

    private var flowLine: String {
        if let message = state.voice.message, !message.isEmpty { return message }
        if !state.voice.preview.isEmpty { return state.voice.preview }
        if state.voice.isActive { return "Listening…" }
        if !state.voice.lastTranscript.isEmpty { return state.voice.lastTranscript }
        return "Hold to talk"
    }
}

// MARK: - The notch's dial
//
// A 34-point crown. Too small for ticks or a readout, so it keeps only the
// two things that still read at that size: the knurled edge and the arc.

struct NotchMiniDial: View {
    @Bindable var state: DialState

    private var tint: Color { DialSwatch.tint(state.control, state: state) }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            .white.opacity(0.20), .white.opacity(0.04),
                            .white.opacity(0.16), .white.opacity(0.20),
                        ],
                        center: .center,
                        angle: .degrees(-60)
                    )
                )
            Circle().fill(.black).padding(1.5)
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.white.opacity(0.10), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                .padding(5)
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * DialMath.clampVolume(
                    state.usesRingGauge ? state.controlProgress : 0.6
                ))
                .stroke(tint, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                .padding(5)
                .rotationEffect(.degrees(135))
                .shadow(color: tint.opacity(0.7), radius: 4)
            Image(systemName: state.control.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 34, height: 34)
        .contentShape(Circle())
    }
}
