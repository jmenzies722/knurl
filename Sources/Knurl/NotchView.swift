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
                Color.clear
                    .frame(height: max(state.notchHousing.height, 1))
                content
                    .frame(height: stage.height)
                    // Grows with the shape rather than after it. The scale is
                    // small on purpose: enough that the contents feel carried
                    // out by the black, not enough to read as a zoom.
                    .scaleEffect(stage.isOpen ? 1 : 0.94, anchor: .top)
                    .opacity(stage == .rest ? 0 : 1)
            }
        }
        .animation(motion, value: state.voice.preview)
        .animation(motion, value: whisper.line)
    }

    private var motion: Animation? {
        lively ? .spring(duration: 0.26, bounce: 0.05) : .easeOut(duration: 0.12)
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .rest: Color.clear
        case .glance: glanceLine
        case .hover: hoverBar
        case .shelf: glanceShelf
        case .flow: flowShelf
        }
    }

    /// One lit line, the width of the cutout and four points tall. Enough to
    /// say "something is running" from across a desk, small enough that it
    /// reads as the bezel rather than as a widget.
    /// A progress bar the width of the notch, filling left to right.
    ///
    /// It used to be a stub capped at 42% of the tab and centre-aligned, so it
    /// grew outward from the middle in both directions — it could never span
    /// the notch, and at low progress it was a short dash floating in the
    /// centre. A progress indicator fills from one end across a track that
    /// shows you the whole distance; without the track there is nothing to
    /// read the fill against.
    private var glanceLine: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.16))
                Capsule()
                    .fill(housingTint)
                    .frame(width: max(4, geometry.size.width
                        * DialMath.clampVolume(housingProgress ?? 1)))
                    .shadow(color: housingTint.opacity(0.7), radius: 3)
            }
            .frame(height: 3)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .contentShape(Rectangle())
        .overlay(ImmediatePress { state.toggleNotch() })
        .accessibilityLabel(whisper.line)
        .accessibilityValue(housingProgress.map { "\(Int($0 * 100)) percent" } ?? "")
        .accessibilityAddTraits(.isButton)
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
    // One subject, room to breathe, and the two controls you actually reach
    // for. The version before this crammed a dial, two scrubbers, five face
    // keys and three text buttons into one box — a control panel wearing a
    // notch. The dial is gone from here entirely: the Hub and the side dial
    // are where you turn things, and a 78-point crown squeezed under a
    // camera was neither pleasant nor precise.

    private var glanceShelf: some View {
        VStack(alignment: .leading, spacing: 13) {
            subjectHeader
            if subject == .media { mediaScrubber }
            controlRow
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .accessibilityLabel("\(whisper.line). \(whisper.detail)")
    }

    /// Cover art at a size worth looking at, the title, and the transport —
    /// the shape every now-playing card has, because it is the right one.
    private var subjectHeader: some View {
        HStack(spacing: 12) {
            Group {
                if subject == .media, let cover = state.music.cover {
                    Image(nsImage: cover).resizable().scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(.white.opacity(0.07))
                        Image(systemName: compactSymbol)
                            .font(.system(size: 20, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(housingTint)
                    }
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(shelfTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(shelfDetail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if subject == .media {
                HStack(spacing: 8) {
                    shelfKey("backward.fill", "Previous", size: 30) { state.skip(-1) }
                    shelfKey(
                        state.music.isPlaying ? "pause.fill" : "play.fill",
                        state.music.isPlaying ? "Pause" : "Play",
                        size: 38,
                        prominent: true
                    ) { state.collapsedPlay() }
                    shelfKey("forward.fill", "Next", size: 30) { state.skip(1) }
                }
            } else if subject == .hour {
                shelfKey(
                    state.desk.timer.running ? "pause.fill" : "play.fill",
                    "Hour",
                    size: 44,
                    prominent: true
                ) { state.toggleHour() }
            }
        }
    }

    private var mediaScrubber: some View {
        TimelineView(.periodic(from: .now, by: state.music.isPlaying ? 1 : 3600)) { timeline in
            let progress = state.music.canSeek
                ? state.music.displayedPlayhead(at: timeline.date)
                : 0
            let elapsed = progress * state.music.duration
            // Times sit either side of the bar rather than on a line of their
            // own beneath it. They describe the bar, so they belong to it —
            // and it saves a whole row of height in a panel hanging over your
            // work.
            NotchScrubber(
                symbol: "",
                progress: progress,
                label: "Playhead",
                leading: state.music.canSeek ? DialMath.clock(elapsed) : "—",
                trailing: state.music.canSeek
                    ? "−\(DialMath.clock(max(0, state.music.duration - elapsed)))"
                    : "—"
            ) { state.music.seek(to: $0) }
        }
    }

    /// Volume and brightness, stacked.
    ///
    /// Side by side each slider got half the width, which on a control you set
    /// by pointing at a position is half the precision — the two things you
    /// most often want to nudge were the two hardest to hit. Full width each,
    /// one above the other, costs a little height and doubles the resolution.
    private var controlRow: some View {
        VStack(spacing: 8) {
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
                flowButton
                shelfKey("square.grid.2x2.fill", "Open the Hub", size: 34) {
                    state.presentHub()
                }
            }
        }
    }

    /// Hold to talk, and it shows you that it is listening rather than telling
    /// you. At rest it is a quiet pill; held, it fills with your own levels
    /// and lights, so the feedback is the thing the microphone is actually
    /// hearing rather than a label that says "recording".
    private var flowButton: some View {
        HStack(spacing: 9) {
            Image(systemName: state.voice.isActive ? "waveform" : "mic.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(state.voice.isActive ? .black : .white.opacity(0.9))
                .contentTransition(.symbolEffect(.replace))

            if state.voice.isActive {
                KnurlEqualizer(
                    levels: state.voice.levels,
                    tint: .black.opacity(0.75),
                    bars: 5,
                    active: true,
                    lively: lively,
                    height: 14
                )
                Text(state.harnessName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.7))
                    .lineLimit(1)
            } else {
                Text("Hold to talk")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("⌃⌥M")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .background {
            Capsule().fill(
                state.voice.isActive
                    ? AnyShapeStyle(KnurlPalette.live)
                    : AnyShapeStyle(Color.white.opacity(0.10))
            )
        }
        .overlay {
            Capsule().strokeBorder(
                state.voice.isActive ? .clear : .white.opacity(0.12),
                lineWidth: 1
            )
        }
        .shadow(
            color: state.voice.isActive ? KnurlPalette.live.opacity(0.5) : .clear,
            radius: 12,
            y: 2
        )
        .animation(lively ? KnurlMotion.settle : nil, value: state.voice.isActive)
        .overlay(
            ImmediateHold(
                down: { state.beginTalk(presentHUD: false) },
                up: { state.endTalk() }
            )
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(state.voice.isActive ? "Release to paste" : "Hold to talk")
    }

    private func shelfKey(
        _ symbol: String,
        _ label: String,
        size: CGFloat,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(prominent ? .black : .white.opacity(0.9))
            .frame(width: size, height: size)
            .background {
                Circle().fill(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.10)))
            }
            .contentTransition(.symbolEffect(.replace))
            .overlay(ImmediatePress(action: action))
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
    }

    private var shelfTitle: String {
        switch subject {
        case .media: state.music.title
        case .hour: state.desk.timer.readout
        case .flow: state.voice.preview.isEmpty ? "Listening…" : state.voice.preview
        case .dial: state.controlTitle
        }
    }

    private var shelfDetail: String {
        switch subject {
        case .media: state.music.artist.isEmpty ? "Music" : state.music.artist
        case .hour: "left in the hour"
        case .flow: "→ \(state.harnessName)"
        case .dial: state.collapsedLine
        }
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

    /// One colour, chosen by what is actually happening — unless you have
    /// picked one, in which case yours wins and the notch stops reporting
    /// state through colour.
    private var housingTint: Color {
        if let chosen = state.notchTint.color { return chosen }
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
