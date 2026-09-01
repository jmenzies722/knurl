import AppKit
import KnurlCore
import SwiftUI

struct HUDView: View {
    @Bindable var state: DialState

    var body: some View {
        Group {
            if state.isPresented {
                expanded
            } else {
                collapsed
            }
        }
    }

    private var collapsed: some View {
        VStack(spacing: 10) {
            Button {
                state.summon()
            } label: {
                MiniDial(state: state)
            }
            .buttonStyle(.plain)
            .focusable(false)
            Image(systemName: state.music.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 34, height: 34)
                .glassEffect(.regular, in: Circle())
                .overlay(ImmediatePress(action: { state.collapsedPlay() }))
        }
        .padding(12)
        .frame(width: 76)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .top) {
            MoveBar().frame(height: 14)
        }
    }

    private var expanded: some View {
        VStack(spacing: 16) {
            header
            CrownDial(state: state)
            controlBlock
            talkBar
            if state.control != .mic {
                transport
            }
            librarySources
            outputRoster
            roomSatellites
        }
        .padding(18)
        .frame(width: 400)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
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
            Spacer(minLength: 8)
            Color.clear
                .frame(width: 72, height: 14)
                .overlay(MoveBar())
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
    }

    private var controlBlock: some View {
        VStack(spacing: 4) {
            if state.control == .media {
                Text(state.music.hasTrack ? state.music.line : controlSubtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if !state.music.genre.isEmpty {
                    Text(state.music.genre)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .help(state.music.genre)
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

    private var controlSubtitle: String {
        switch state.control {
        case .volume:
            return state.outputName
        case .brightness:
            return "Display"
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
                    Text(state.voice.isListening ? "Release to paste" : "Hold to talk  ⌃⌥M")
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
                if state.voice.isActive {
                    state.endTalk()
                }
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 8) {
            if state.control == .media {
                transportButton("shuffle", selected: state.music.shuffleOn) {
                    state.toggleShuffle()
                }
            }
            transportButton("backward.fill") {
                state.skip(-1)
            }
            Image(systemName: state.music.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .bold))
                .frame(width: 72, height: 40)
                .glassEffect(
                    .regular.tint(DialSwatch.tint(state.control, state: state).opacity(0.5)),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(ImmediatePress(action: { state.collapsedPlay() }))
            transportButton("forward.fill") {
                state.skip(1)
            }
            if state.control == .media {
                transportButton(state.music.repeatMode.symbol, selected: state.music.repeatMode != .off) {
                    state.cycleRepeat()
                }
            }
        }
    }

    private func transportButton(_ symbol: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Image(systemName: symbol)
            .frame(width: 44, height: 40)
            .foregroundStyle(selected ? DialSwatch.media : .primary.opacity(0.9))
            .glassEffect(
                selected
                    ? .regular.tint(DialSwatch.media.opacity(0.4))
                    : .regular,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text("\(number)")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .foregroundStyle(.primary.opacity(0.9))
        .glassEffect(
            selected
                ? .regular.tint(tint.opacity(0.45))
                : .regular.tint(tint.opacity(0.12)),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(state.music.sources) { source in
                        let selected = state.music.activeSourceID == source.id
                        Text(source.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .foregroundStyle(.primary.opacity(0.9))
                            .glassEffect(
                                selected
                                    ? .regular.tint(DialSwatch.volume(state).opacity(0.45))
                                    : .regular,
                                in: Capsule()
                            )
                            .overlay(ImmediatePress(action: { state.playSource(source.id) }))
                    }
                }
            }
            .frame(height: 36)
        }
    }

    @ViewBuilder
    private var outputRoster: some View {
        if state.control == .output {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    RoutePicker()
                        .frame(width: 28, height: 28)
                    Text("AirPlay")
                        .font(.system(size: 11, weight: .medium))
                    Text("HomePods, TVs, Wi‑Fi speakers")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(state.outputDevices) { device in
                            let selected = device.uid == state.outputUID
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Text(device.transport.title)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .foregroundStyle(.primary.opacity(0.9))
                            .glassEffect(
                                selected
                                    ? .regular.tint(DialSwatch.output.opacity(0.45))
                                    : .regular,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .overlay(ImmediatePress(action: { state.selectOutput(device) }))
                        }
                    }
                }
                .frame(height: 44)
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
        case .mic: state.voice.isListening ? "Talk" : (state.isMicMuted ? "Muted" : "Mic")
        case .output: "Out"
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
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .padding(16)
                .rotationEffect(.degrees(135))
            ForEach(0 ..< 11, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(index % 5 == 0 ? 0.34 : 0.12))
                    .frame(width: 1.6, height: index % 5 == 0 ? 9 : 4)
                    .offset(y: -92)
                    .rotationEffect(.degrees(135 + Double(index) / 10 * 270))
            }
            artwork
                .frame(width: 168, height: 168)
                .allowsHitTesting(false)
        }
    }

    private func needle(progress: Double, tint: Color) -> some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75 * progress)
                .stroke(
                    AngularGradient(
                        colors: [
                            DialSwatch.color(progress: 0, muted: false),
                            tint,
                        ],
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
            VStack {
                Spacer()
                Text(wellCaption(progress: progress))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular.tint(.black.opacity(0.35)), in: Capsule())
                    .padding(.bottom, 22)
            }
            .frame(width: 168, height: 168)
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
private enum DialSwatch {
    static let bright = Color(red: 1.0, green: 0.78, blue: 0.32)
    static let mic = Color(red: 0.98, green: 0.55, blue: 0.42)
    static let output = Color(red: 0.42, green: 0.86, blue: 0.78)
    static let media = Color(red: 0.96, green: 0.40, blue: 0.52)

    static func volume(_ state: DialState) -> Color {
        color(progress: state.volumeProgress, muted: state.isMuted)
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
