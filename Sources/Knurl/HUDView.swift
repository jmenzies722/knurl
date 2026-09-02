import AppKit
import KnurlCore
import SwiftUI

struct HUDView: View {
    @Bindable var state: DialState
    @Namespace private var faces

    var body: some View {
        Group {
            if state.isPresented {
                expanded
            } else {
                collapsed
            }
        }
    }

    /// Parked state: a pill above the Dock, in three sizes.
    ///
    /// Rest is three live controls and nothing else, dimmed so it reads as
    /// furniture. Hover adds the label. Listening takes over entirely — the
    /// waveform, the words as they land, and where they are going. Every
    /// control works at rest, so hover is a bonus and never a requirement.
    private var collapsed: some View {
        HStack(spacing: 7) {
            Button {
                state.summon()
            } label: {
                MiniDial(state: state)
            }
            .buttonStyle(.plain)
            .focusable(false)

            if state.voice.isListening {
                flowLane
                    .transition(.opacity)
            } else if state.pillShowsPages {
                pageLane
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            } else {
                if state.pillHovered {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(state.controlTitle)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(state.collapsedLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(width: 108, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
                pillButton(
                    symbol: "square.grid.2x2.fill",
                    tint: .secondary,
                    label: "Show Hub pages"
                ) {
                    state.pillShowsPages = true
                    HUDPanel.shared.refreshPill()
                }
                pillButton(
                    symbol: "mic.fill",
                    tint: .secondary,
                    label: "Start Knurl Flow"
                ) {
                    state.toggleTalk(presentHUD: false)
                }
                pillButton(
                    symbol: state.music.isPlaying ? "pause.fill" : "play.fill",
                    tint: .secondary,
                    label: state.music.isPlaying ? "Pause" : "Play"
                ) {
                    state.collapsedPlay()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .glassEffect(.regular.interactive(), in: Capsule())
        .overlay(alignment: .leading) {
            if state.pillHovered, !state.voice.isListening {
                MoveBar().frame(width: 12).transition(.opacity)
            }
        }
        .opacity(state.pillHovered || state.voice.isListening ? 1 : 0.62)
        .animation(.spring(duration: 0.26, bounce: 0.1), value: state.pillHovered)
        .animation(.spring(duration: 0.3, bounce: 0.12), value: state.voice.isListening)
        .animation(.spring(duration: 0.28, bounce: 0.12), value: state.pillShowsPages)
        .onChange(of: state.voice.isListening) { HUDPanel.shared.refreshPill() }
    }

    /// The six Hub pages, inline. Picking one opens the Hub on that page, so
    /// the pill navigates without becoming a second window.
    private var pageLane: some View {
        HStack(spacing: 4) {
            ForEach(state.hubOrder) { page in
                let selected = state.hubPage == page
                Image(systemName: page.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .frame(width: 32, height: 30)
                    .glassEffect(
                        selected ? .regular.tint(DialSwatch.stable(state.control).opacity(0.4)) : .regular,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay(ImmediatePress {
                        state.hubPage = page
                        state.pillShowsPages = false
                        HUDPanel.shared.refreshPill()
                        state.presentHub()
                    })
                    .help(page.title)
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityLabel(page.title)
            }
            pillButton(symbol: "xmark", tint: .secondary, label: "Back to controls") {
                state.pillShowsPages = false
                HUDPanel.shared.refreshPill()
            }
        }
    }

    /// What the pill becomes while Flow is listening: level, words, destination,
    /// and one obvious way to stop.
    private var flowLane: some View {
        HStack(spacing: 10) {
            FlowWaveform(levels: state.voice.levels, tint: .accentColor, bars: 12)
                .frame(width: 56)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.voice.preview.isEmpty ? "Listening…" : state.voice.preview)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .contentTransition(.opacity)
                Text("→ \(state.harnessName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)

            pillButton(symbol: "stop.fill", tint: .accentColor, label: "Stop and paste") {
                state.toggleTalk(presentHUD: false)
            }
        }
    }

    private func pillButton(
        symbol: String,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(tint == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
            .frame(width: 30, height: 30)
            .glassEffect(.regular, in: Circle())
            .overlay(ImmediatePress(action: action))
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
    }

    private var expanded: some View {
        VStack(spacing: 16) {
            header
            if !state.desk.attention.isEmpty {
                Text("\(state.desk.attention[0].provider.title) needs you")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            CrownDial(state: state)
            controlBlock
            talkBar
            if state.control != .mic {
                transport
            }
            librarySources
            outputRoster
            hourStrip
            roomSatellites
        }
        .padding(18)
        .frame(width: 400)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    /// The Hour, in the dial menu. Deliberately not a sixth face: the five-face
    /// grammar, the 1-5 keys and the phone wire format all stay as they are.
    private var hourStrip: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(state.desk.timer.running ? AnyShapeStyle(DialSwatch.bright) : AnyShapeStyle(.secondary))
            Text(state.desk.timer.readout)
                .font(.callout.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
                .frame(width: 56, alignment: .leading)

            ForEach([15, 25, 50, 90], id: \.self) { minutes in
                Text("\(minutes)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .frame(width: 32, height: 28)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(ImmediatePress { state.setHourDuration(Double(minutes) * 60) })
                    .accessibilityLabel("\(minutes) minutes")
            }

            Spacer(minLength: 4)

            Image(systemName: state.desk.timer.running ? "pause.fill" : "play.fill")
                .font(.caption.weight(.bold))
                .frame(width: 34, height: 28)
                .glassEffect(
                    state.desk.timer.running
                        ? .regular.tint(DialSwatch.bright.opacity(0.4))
                        : .regular,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay(ImmediatePress { state.toggleHour() })
                .accessibilityLabel(state.desk.timer.running ? "Pause the Hour" : "Start the Hour")

            if state.desk.timer.isArmed {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 28)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(ImmediatePress { state.resetHour() })
                    .accessibilityLabel("Reset the Hour")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.2), value: state.desk.timer.running)
        .animation(.snappy(duration: 0.2), value: state.desk.timer.readout)
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.controlTitle)
                    .font(.headline)
                    .foregroundStyle(.primary.opacity(0.92))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                if state.control == .media, !state.music.line.isEmpty {
                    Text(state.music.line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            // In front of the text, not behind it: as a .background the drag
            // surface only caught the empty gap, so grabbing the title did
            // nothing.
            .overlay(MoveBar())
            Spacer(minLength: 8)
            if state.control == .media {
                Image(systemName: "music.note")
                    .font(.caption.weight(.semibold))
                    .padding(8)
                    .glassEffect(.regular, in: Circle())
                    .help("Open Music")
                    .overlay(ImmediatePress(action: { state.revealMusic() }))
            }
            Image(systemName: "xmark")
                .font(.caption.weight(.semibold))
                .padding(8)
                .glassEffect(.regular, in: Circle())
                .overlay(ImmediatePress(action: { state.dismiss() }))
        }
        // The whole header is the grab area, the way a title bar is. The old
        // handle was an invisible 72pt strip nobody could find.
        .background(MoveBar())
        .overlay(alignment: .top) {
            Capsule()
                .fill(.secondary.opacity(0.35))
                .frame(width: 34, height: 4)
                .padding(.top, -6)
                .allowsHitTesting(false)
        }
        .accessibilityLabel("Drag to move the dial")
    }

    private var controlBlock: some View {
        VStack(spacing: 4) {
            if state.control == .media {
                // The header already names the track and artist, and the genre
                // is a chip below. Only the clock is new information here.
                if state.music.hasTrack, state.music.canSeek {
                    Text(mediaClock)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.primary.opacity(0.9))
                } else {
                    Text(controlSubtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text(state.controlReadout)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .contentTransition(.numericText())
                Text(controlSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.18), value: state.controlReadout)
    }

    private var mediaClock: String {
        let elapsed = state.music.displayedPlayhead() * state.music.duration
        return "\(DialMath.clock(elapsed))  −\(DialMath.clock(max(0, state.music.duration - elapsed)))"
    }

    private var controlSubtitle: String {
        switch state.control {
        case .volume:
            return state.outputName
        case .brightness:
            return "Built-in display"
        case .mic:
            if state.voice.isListening { return "Listening" }
            return state.inputName
        case .output:
            return state.outputKind
        case .media:
            if let message = state.music.message, !state.music.hasTrack { return message }
            return state.music.cardArtist
        }
    }

    @ViewBuilder
    private var talkBar: some View {
        if state.control == .mic {
            VStack(spacing: 8) {
                if state.voice.isListening || !state.voice.preview.isEmpty {
                    Text(state.voice.preview.isEmpty ? "Listening…" : state.voice.preview)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity)
                }
                HStack(spacing: 8) {
                    Image(systemName: state.voice.isListening ? "waveform" : "mic.fill")
                        .symbolEffect(.variableColor.iterative, isActive: state.voice.isListening)
                    Text(state.voice.isListening ? "Release to paste" : "Hold Flow  ⌃⌥M")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(.primary.opacity(0.92))
                .glassEffect(
                    .regular.tint(DialSwatch.mic.opacity(state.voice.isListening ? 0.5 : 0.22)),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    ImmediateHold(
                        down: { state.beginTalk() },
                        up: { state.endTalk() }
                    )
                )
                if let message = state.voice.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .onDisappear {
                if state.flowOrigin == .hud {
                    state.endTalk()
                }
            }
        }
    }

    /// Three tiers, so the eye lands on play first: mode toggles are small and
    /// only carry colour when they are on, skip is medium, play is primary.
    private var transport: some View {
        HStack(spacing: 8) {
            if state.control == .media {
                transportButton("shuffle", tier: .toggle, selected: state.music.shuffleOn) {
                    state.toggleShuffle()
                }
            }
            transportButton("backward.fill", tier: .secondary) {
                state.skip(-1)
            }
            Image(systemName: state.music.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 17, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
                .frame(width: 84, height: 44)
                .glassEffect(
                    .regular.tint(DialSwatch.stable(state.control).opacity(0.62)),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
                .overlay(ImmediatePress(action: { state.collapsedPlay() }))
            transportButton("forward.fill", tier: .secondary) {
                state.skip(1)
            }
            if state.control == .media {
                transportButton(
                    state.music.repeatMode.symbol,
                    tier: .toggle,
                    selected: state.music.repeatMode != .off
                ) {
                    state.cycleRepeat()
                }
            }
        }
    }

    private enum TransportTier {
        case secondary
        case toggle

        var size: CGSize {
            switch self {
            case .secondary: CGSize(width: 48, height: 40)
            case .toggle: CGSize(width: 38, height: 34)
            }
        }

        var glyph: CGFloat {
            switch self {
            case .secondary: 13
            case .toggle: 11
            }
        }
    }

    private func transportButton(
        _ symbol: String,
        tier: TransportTier,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: tier.glyph, weight: .semibold))
            // shuffle and repeat ship multicolour variants; without this the
            // off state renders red and reads as an error.
            .symbolRenderingMode(.monochrome)
            .frame(width: tier.size.width, height: tier.size.height)
            .foregroundStyle(selected ? AnyShapeStyle(DialSwatch.stable(state.control)) : AnyShapeStyle(.secondary))
            .glassEffect(
                selected ? .regular.tint(DialSwatch.stable(state.control).opacity(0.34)) : .regular,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(ImmediatePress(action: action))
    }

    private var roomSatellites: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(DialMode.allCases.enumerated()), id: \.element.id) { index, mode in
                    satellite(mode, number: index + 1)
                }
            }
        }
    }

    private func satellite(_ mode: DialMode, number: Int) -> some View {
        let selected = state.control == mode
        let tint = DialSwatch.tint(mode, state: state)
        return VStack(spacing: 3) {
            Image(systemName: satelliteSymbol(mode))
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.bounce, value: selected)
                .foregroundStyle(tint)
            Text(satelliteLabel(mode))
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .help("\(mode.title) · press \(number)")
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .foregroundStyle(.primary.opacity(0.9))
        .glassEffect(
            selected
                ? .regular.tint(tint.opacity(0.45)).interactive()
                : .regular.tint(tint.opacity(0.12)).interactive(),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .modifier(SelectedFaceGlass(active: selected, namespace: faces))
        .overlay(
            ImmediatePress {
                if selected {
                    state.confirmDial()
                } else {
                    state.selectControl(mode)
                }
            }
        )
    }

    private func satelliteSymbol(_ mode: DialMode) -> String {
        switch mode {
        case .volume: state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        case .mic:
            if state.voice.isListening { "waveform" }
            else if state.isMicMuted { "mic.slash.fill" }
            else { "mic.fill" }
        case .output: "hifispeaker.fill"
        case .media: state.music.isPlaying ? "pause.fill" : "play.fill"
        }
    }

    @ViewBuilder
    private var librarySources: some View {
        if state.control == .media {
            MusicLibraryStrip(state: state, compact: true)
        }
    }

    @ViewBuilder
    private var outputRoster: some View {
        if state.control == .output {
            VStack(alignment: .leading, spacing: 8) {
                HomePodRouteButton(nearby: OutputWatch.shared.airPlayNearby)
                HStack(spacing: 8) {
                    Text(state.swapLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .glassEffect(
                            .regular.tint(DialSwatch.output.opacity(0.36)).interactive(),
                            in: Capsule()
                        )
                        .overlay(ImmediatePress(action: { state.swapSpeaker() }))
                    if let memory = state.outputMemoryLine {
                        Text(memory)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var mediaChipLabel: String {
        let title = state.music.title
        if !title.isEmpty { return title }
        return "Music"
    }

    private func satelliteLabel(_ mode: DialMode) -> String {
        switch mode {
        case .volume: state.isMuted ? "Muted" : "\(state.volumePercent)"
        case .brightness: "\(state.brightnessPercent)"
        case .mic: state.voice.isListening ? "Flow" : (state.isMicMuted ? "Muted" : "Mic")
        case .output: state.outputKind
        case .media: mediaChipLabel
        }
    }
}

private struct CrownDial: View {
    @Bindable var state: DialState
    private let size: CGFloat = 252

    var body: some View {
        let tint = DialSwatch.tint(state.control, state: state)
        ZStack {
            well(tint: tint)
            TimelineView(.periodic(from: .now, by: 0.2)) { timeline in
                let progress = liveProgress(at: timeline.date)
                needle(progress: progress, tint: tint)
            }
        }
        .frame(width: size, height: size)
        .glassEffect(.regular.tint(tint.opacity(0.18)).interactive(), in: Circle())
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    state.turnDial(at: value.location, size: CGSize(width: size, height: size))
                }
                .onEnded { _ in
                    if state.control == .output {
                        state.finishOutputTurn()
                    }
                }
        )
        .onTapGesture {
            state.confirmDial()
        }
        .animation(.snappy(duration: 0.16), value: state.controlReadout)
        .animation(.easeInOut(duration: 0.28), value: state.control)
    }

    private func liveProgress(at date: Date) -> Double {
        if state.control == .media {
            return state.music.canSeek
                ? state.music.displayedPlayhead(at: date)
                : 0
        }
        return state.usesRingGauge ? state.controlProgress : max(state.controlProgress, 0.12)
    }

    private func well(tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.22))
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    .init(0, 0), .init(0.5, 0), .init(1, 0),
                    .init(0, 0.5), .init(0.5, 0.5), .init(1, 0.5),
                    .init(0, 1), .init(0.5, 1), .init(1, 1),
                ],
                colors: [
                    tint.opacity(0.55), .clear, DialSwatch.bright.opacity(0.28),
                    .clear, tint.opacity(0.18), .clear,
                    DialSwatch.mic.opacity(0.22), .clear, DialSwatch.output.opacity(0.28),
                ]
            )
            .clipShape(Circle())
            .opacity(0.85)
            Circle()
                .stroke(.white.opacity(0.07), lineWidth: 20)
                .padding(8)
            // Dark track, not a light one: the fill has to win against a tinted
            // well, and two similar values made the playhead unreadable.
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.black.opacity(0.38), style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .padding(16)
                .rotationEffect(.degrees(135))
            ForEach(0 ..< 11, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(index % 5 == 0 ? 0.34 : 0.12))
                    .frame(width: 1.6, height: index % 5 == 0 ? 9 : 4)
                    .offset(y: -92)
                    .rotationEffect(.degrees(135 + Double(index) / 10 * 270))
            }
            if state.voice.isListening {
                FlowWaveform(levels: state.voice.levels, tint: .white, bars: 16)
                    .frame(width: 140)
            } else {
                artwork
                    .frame(width: 168, height: 168)
                    .allowsHitTesting(false)
            }
        }
    }

    private func needle(progress: Double, tint: Color) -> some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75 * progress)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.75), tint],
                        center: .center,
                        startAngle: .degrees(135),
                        endAngle: .degrees(135 + 270 * max(progress, 0.001))
                    ),
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .padding(16)
                .rotationEffect(.degrees(135))
                .shadow(color: tint.opacity(state.music.isPlaying ? 0.55 : 0.2), radius: state.music.isPlaying ? 12 : 4)
            Capsule()
                .fill(.white)
                .frame(width: 5, height: 24)
                .offset(y: -92)
                .rotationEffect(.degrees(DialMath.ringAngle(progress: progress)))
                .shadow(color: tint.opacity(0.5), radius: 7)
        }
        .allowsHitTesting(false)
    }

    private func wellCaption(progress: Double) -> String {
        if state.control == .media, state.music.canSeek {
            let elapsed = progress * state.music.duration
            return "\(DialMath.clock(elapsed))  −\(DialMath.clock(max(0, state.music.duration - elapsed)))"
        }
        return state.controlReadout
    }

    @ViewBuilder
    private var artwork: some View {
        ZStack {
            Circle().fill(.black.opacity(0.35))
            if state.control == .media, let cover = state.music.cover {
                Image(nsImage: cover)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 168, height: 168)
                    .clipShape(Circle())
                    .id(state.music.title)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: state.control.symbol)
                        .font(.system(size: 28, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.9))
                    Text(state.controlReadout)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                }
                .padding(20)
            }
        }
    }
}

private struct MiniDial: View {
    @Bindable var state: DialState

    var body: some View {
        let tint = DialSwatch.volume(state)
        ZStack {
            Circle().fill(.black.opacity(0.2))
            Circle()
                .trim(from: 0, to: 0.75 * (state.usesRingGauge ? state.controlProgress : 0.6))
                .stroke(tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .padding(3)
                .rotationEffect(.degrees(135))
            Image(systemName: state.control.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 52, height: 52)
    }
}

@MainActor
enum DialSwatch {
    static let bright = Color(red: 1.0, green: 0.78, blue: 0.32)
    static let mic = Color(red: 0.98, green: 0.55, blue: 0.42)
    static let output = Color(red: 0.42, green: 0.86, blue: 0.78)
    static let media = Color(red: 0.96, green: 0.40, blue: 0.52)

    static func volume(_ state: DialState) -> Color {
        color(progress: state.volumeProgress, muted: state.isMuted)
    }

    /// A fixed sample of a face's hue, for controls. The ring shows progress
    /// through its length; buttons must not change colour as a track plays.
    static func stable(_ mode: DialMode) -> Color {
        let rgb = DialTint.rgb(progress: 0.6, muted: false, mode: mode)
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    static func tint(_ mode: DialMode, state: DialState) -> Color {
        let rgb = DialTint.rgb(
            progress: state.controlProgress,
            muted: (mode == .volume && state.isMuted) || (mode == .mic && state.isMicMuted),
            mode: mode
        )
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    static func color(progress: Double, muted: Bool) -> Color {
        let rgb = DialTint.rgb(progress: progress, muted: muted, mode: .volume)
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
}

private struct MoveBar: NSViewRepresentable {
    func makeNSView(context: Context) -> MoveBarView { MoveBarView() }
    func updateNSView(_ view: MoveBarView, context: Context) {}
}

final class MoveBarView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }
}
