import KnurlCore
import SwiftUI

struct DeskCrown: View {
    var progress: Double
    var tint: Color
    var symbol: String
    var readout: String
    var caption: String
    var ticks: Int = 11
    var size: CGFloat = 220
    var lively: Bool = true
    var onTurn: (Double) -> Void
    var onConfirm: () -> Void
    var onEnded: (() -> Void)? = nil

    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: !shouldBreathe)) { timeline in
            let pulse = shouldBreathe
                ? 0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 1.35)
                : 0
            ZStack {
                well(pulse: pulse)
                needle(pulse: pulse)
            }
        }
        .frame(width: size, height: size)
        .glassEffect(.regular.tint(tint.opacity(0.18)).interactive(), in: Circle())
        .scaleEffect(dragging ? 0.975 : 1)
        .animation(reduceMotion || !lively ? nil : .spring(duration: 0.28, bounce: 0.22), value: dragging)
        .animation(dragging || reduceMotion || !lively ? nil : .spring(duration: 0.46, bounce: 0.16), value: progress)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    dragging = true
                    let dx = value.location.x - size / 2
                    let dy = value.location.y - size / 2
                    let degrees = atan2(dx, -dy) * 180 / .pi
                    if let next = DialMath.ringProgress(clockwiseFromNoon: degrees) {
                        onTurn(next)
                    }
                }
                .onEnded { _ in
                    dragging = false
                    onEnded?()
                }
        )
        .onTapGesture(perform: onConfirm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue(readout)
        .accessibilityAddTraits(.isButton)
        .accessibilityAdjustableAction { direction in
            let step = ticks > 1 ? 1.0 / Double(max(ticks - 1, 1)) : 0.05
            switch direction {
            case .increment: onTurn(min(1, progress + step))
            case .decrement: onTurn(max(0, progress - step))
            default: break
            }
        }
    }

    private var shouldBreathe: Bool {
        lively && !reduceMotion && !dragging
    }

    private var activeTick: Int {
        DialMath.detentIndex(progress: progress, count: ticks)
    }

    private func well(pulse: Double) -> some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.28))
            Circle()
                .fill(tint.opacity(0.10 + 0.08 * pulse))
                .blur(radius: size * 0.06)
                .padding(size * 0.12)
            Circle()
                .stroke(.white.opacity(0.08 + 0.04 * pulse), lineWidth: size * 0.08)
                .padding(size * 0.03)
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.white.opacity(0.14), style: StrokeStyle(lineWidth: size * 0.044, lineCap: .round))
                .padding(size * 0.064)
                .rotationEffect(.degrees(135))
            ForEach(0 ..< ticks, id: \.self) { index in
                let lit = index == activeTick
                Capsule()
                    .fill(lit ? tint.opacity(0.95) : .white.opacity(index % 5 == 0 ? 0.38 : 0.14))
                    .frame(width: lit ? 2.2 : 1.6, height: (lit ? size * 0.048 : size * 0.02) + (index % 5 == 0 ? size * 0.012 : 0))
                    .offset(y: -size * 0.365)
                    .rotationEffect(.degrees(135 + Double(index) / Double(max(ticks - 1, 1)) * 270))
                    .shadow(color: lit ? tint.opacity(0.55) : .clear, radius: lit ? 4 : 0)
            }
            VStack(spacing: size * 0.018) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.94))
                    .symbolEffect(.bounce, value: reduceMotion ? "" : symbol)
                    .symbolEffect(.variableColor.iterative, isActive: shouldBreathe && dragging == false)
                Text(readout)
                    .font(.system(size: min(34, size * 0.13), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.35)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                Text(caption)
                    .font(.system(size: size * 0.045, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
            .padding(size * 0.18)
            .allowsHitTesting(false)
        }
    }

    private func needle(pulse: Double) -> some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75 * DialMath.clampVolume(progress))
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: size * 0.044, lineCap: .round)
                )
                .padding(size * 0.064)
                .rotationEffect(.degrees(135))
                .shadow(color: tint.opacity(0.28 + 0.28 * pulse), radius: 8 + 4 * pulse)
            Capsule()
                .fill(.white)
                .frame(width: 5, height: size * 0.09)
                .offset(y: -size * 0.365)
                .rotationEffect(.degrees(DialMath.ringAngle(progress: progress)))
                .shadow(color: tint.opacity(0.55), radius: 7)
        }
        .allowsHitTesting(false)
    }
}

struct DeskCrownBank: View {
    @Bindable var state: DialState
    var hero: DialMode
    var compact: Bool = false
    @Namespace private var desk
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            VStack(spacing: 22) {
                crown(hero, size: compact ? 204 : 248)
                if hero == .output {
                    outputSatellites
                }
                HStack(spacing: 18) {
                    ForEach(DialMode.allCases.filter { $0 != hero && $0 != .media }) { mode in
                        VStack(spacing: 8) {
                            crown(mode, size: compact ? 100 : 118)
                            Text(mode.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(motion, value: hero)
        .animation(motion, value: state.outputUID)
        .animation(motion, value: state.volumePercent)
        .animation(motion, value: state.brightnessPercent)
        .animation(motion, value: state.micPercent)
    }

    private var motion: Animation? {
        reduceMotion || !state.desk.allowsDecorativeMotion
            ? nil
            : .spring(duration: 0.48, bounce: 0.18)
    }

    private func crown(_ mode: DialMode, size: CGFloat) -> some View {
        DeskCrown(
            progress: progress(mode),
            tint: tint(mode),
            symbol: symbol(mode),
            readout: size < 160 ? shortReadout(mode) : readout(mode),
            caption: mode == .output ? state.outputKind : mode.title,
            ticks: mode == .output ? max(state.outputDevices.count, 2) : 11,
            size: size,
            lively: state.desk.allowsDecorativeMotion,
            onTurn: { turn(mode, $0) },
            onConfirm: {
                if state.control == mode {
                    confirm(mode)
                } else {
                    state.selectControl(mode)
                }
            },
            onEnded: mode == .output ? { state.finishOutputTurn() } : nil
        )
        .glassEffectID(mode.rawValue, in: desk)
        .matchedGeometryEffect(id: mode.rawValue, in: desk)
    }

    private var outputSatellites: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomePodRouteButton(nearby: OutputWatch.shared.airPlayNearby)
            HStack(spacing: 8) {
                HubGlassButton(
                    title: state.swapLabel,
                    symbol: "arrow.triangle.2.circlepath",
                    tint: tint(.output)
                ) {
                    state.swapSpeaker()
                }
                HubGlassButton(title: "Bluetooth", symbol: "antenna.radiowaves.left.and.right") {
                    state.openBluetoothSettings()
                }
                HubGlassButton(title: "Sound", symbol: "slider.horizontal.3") {
                    state.openSoundSettings()
                }
            }
            if let memory = state.outputMemoryLine {
                Text(memory)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func progress(_ mode: DialMode) -> Double {
        switch mode {
        case .volume: state.volumeProgress
        case .brightness: Double(state.brightnessPercent) / 100
        case .mic: Double(state.micPercent) / 100
        case .output: state.outputProgress
        case .media: state.music.displayedPlayhead()
        }
    }

    private func readout(_ mode: DialMode) -> String {
        switch mode {
        case .volume: state.isMuted ? "Muted" : "\(state.volumePercent)"
        case .brightness: "\(state.brightnessPercent)"
        case .mic: state.isMicMuted ? "Muted" : "\(state.micPercent)"
        case .output: state.outputName
        case .media: state.music.cardTitle
        }
    }

    private func shortReadout(_ mode: DialMode) -> String {
        switch mode {
        case .output:
            let name = state.outputName
            return name.count > 10 ? String(name.prefix(9)) + "…" : name
        default:
            return readout(mode)
        }
    }

    private func symbol(_ mode: DialMode) -> String {
        switch mode {
        case .volume: state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        case .mic: state.isMicMuted ? "mic.slash.fill" : "mic.fill"
        case .output:
            state.outputDevices.first { $0.uid == state.outputUID }?.transport.symbol
                ?? "hifispeaker.fill"
        case .media: state.music.isPlaying ? "pause.fill" : "play.fill"
        }
    }

    private func tint(_ mode: DialMode) -> Color {
        HubTint.face(
            mode,
            progress: progress(mode),
            muted: (mode == .volume && state.isMuted) || (mode == .mic && state.isMicMuted)
        )
    }

    private func turn(_ mode: DialMode, _ value: Double) {
        if state.control != mode {
            state.selectControl(mode)
        }
        switch mode {
        case .volume: state.setRoomVolume(value)
        case .brightness: state.setRoomBrightness(value)
        case .mic: state.setRoomMic(value)
        case .output: state.setOutputProgress(value)
        case .media: state.music.seek(to: value)
        }
    }

    private func confirm(_ mode: DialMode) {
        if state.control != mode {
            state.selectControl(mode)
            return
        }
        state.confirmDial()
    }
}
