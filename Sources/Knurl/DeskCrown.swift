import AppKit
import KnurlCore
import SwiftUI

// MARK: - The crown
//
// One physical object, five faces. Read outward from the middle: a lit
// readout, a machined face, a tick ring that fills as you turn, a live arc,
// a needle, and a knurled bezel you can grab. Turn by dragging, scrolling
// with the pointer over it, or the arrow keys once it has focus. Click
// confirms — which is mute, or half, or play, depending on the face.
//
// The call signature is unchanged from the first pass on purpose: the HUD and
// the notch host the same component, and the dial is the one part of Knurl
// that must feel identical everywhere it appears.

struct DeskCrown: View {
    var progress: Double
    var tint: Color
    var symbol: String
    var readout: String
    var caption: String
    var ticks: Int = 11
    var size: CGFloat = 220
    var lively: Bool = true
    /// `.adaptive` follows the Mac's appearance — silver in light, graphite in
    /// dark. `.graphite` is forced dark, which is what the HUD and the notch
    /// need: they float over whatever you were doing, so they are dark glass
    /// no matter what the system is set to, and a silver dial on dark glass
    /// reads as a hole punched in the panel.
    var metal: KnurlMetal = .adaptive
    /// Shown in the well instead of the readout. Media puts cover art here;
    /// every other face leaves it nil and gets the symbol and the number.
    var artwork: Image? = nil
    /// Live audio levels, when the caller has real ones (Flow). Nil with
    /// `pulsing` true gives the decorative playing indicator instead.
    var levels: [Float]? = nil
    /// Whether the thing this dial controls is currently making noise.
    var pulsing: Bool = false
    var onTurn: (Double) -> Void
    var onConfirm: () -> Void
    var onEnded: (() -> Void)? = nil

    @State private var dragging = false
    @State private var hovering = false
    @State private var scrollCarry: Double = 0
    @State private var grabOffset: Double = 0
    @State private var lastRaw: Double = 0
    @State private var modifiers = EventModifiers()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.knurlOnScreen) private var onScreen

    private var animates: Bool { lively && !reduceMotion }
    private var clamped: Double { DialMath.clampVolume(progress) }

    var body: some View {
        // No idle timeline. The bloom used to breathe on a clock, which meant
        // five crowns on Home each ran their own twelve-frame-a-second blur
        // for a six-percent change in opacity nobody could see — and the open
        // Hub sat above thirty percent CPU doing it. The dial now moves when
        // the value moves, which is the only time it has anything to say.
        ZStack {
            bloom
            well
            track
            arc
            handle
            centre
        }
        .frame(width: size, height: size)
        .scaleEffect(dragging ? 0.985 : 1)
        .animation(animates ? KnurlMotion.snap : nil, value: dragging)
        .contentShape(Circle())
        .onHover { hovering = $0 }
        .onModifierKeysChanged { _, next in modifiers = next }
        .gesture(turnGesture)
        .onTapGesture(perform: onConfirm)
        .modifier(CrownScroll(active: hovering) { delta in
            scrollCarry += delta
            let step = 1.0 / Double(max(ticks - 1, 1))
            while abs(scrollCarry) >= step {
                let direction: Double = scrollCarry > 0 ? 1 : -1
                scrollCarry -= step * direction
                onTurn(DialMath.clampVolume(clamped + step * direction))
            }
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue(readout)
        .accessibilityAddTraits(.isButton)
        .accessibilityAdjustableAction { direction in
            let step = ticks > 1 ? 1.0 / Double(max(ticks - 1, 1)) : 0.05
            switch direction {
            case .increment: onTurn(min(1, clamped + step))
            case .decrement: onTurn(max(0, clamped - step))
            default: break
            }
        }
    }

    // MARK: Scrubbing
    //
    // One rule: the value follows your pointer exactly, offset by wherever you
    // grabbed it. Put your pointer on the handle and the handle stays under
    // your pointer for the whole drag.
    //
    // The previous version scaled precision by how far out you dragged, which
    // sounded clever and felt broken: the mapping changed under your hand
    // mid-gesture, so the same movement meant different amounts at different
    // moments and nothing ever landed where you aimed. Fine control is now an
    // explicit modifier — hold ⌥ for quarter-speed — which you can feel and
    // predict instead of discovering by accident.

    private var ringRadius: CGFloat { size * 0.5 - inset }
    private var inset: CGFloat { size * 0.11 }
    private var lineWidth: CGFloat { size * 0.085 }

    private var turnGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dx = value.location.x - size / 2
                let dy = value.location.y - size / 2
                // Ignore movement inside the hub of the dial: down there a
                // pixel of travel is a huge swing in angle, which is what
                // makes a circular control feel twitchy.
                guard sqrt(dx * dx + dy * dy) > size * 0.16 else { return }
                let degrees = atan2(dx, -dy) * 180 / .pi
                guard let raw = DialMath.ringProgress(clockwiseFromNoon: degrees) else { return }

                if !dragging {
                    dragging = true
                    grabOffset = raw - clamped
                    lastRaw = raw
                }

                let step = fine ? (raw - lastRaw) * 0.25 : (raw - lastRaw)
                lastRaw = raw
                let next = DialMath.clampVolume(clamped + step)
                grabOffset = raw - next
                onTurn(next)
            }
            .onEnded { _ in
                dragging = false
                grabOffset = 0
                onEnded?()
            }
    }

    /// Hold ⌥ while dragging for quarter-speed.
    private var fine: Bool { modifiers.contains(.option) }

    // MARK: Layers

    /// The colour the dial throws onto the page. Soft, wide and low — this is
    /// what makes the control feel lit rather than drawn.
    private var bloom: some View {
        Circle()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: tint.opacity(0.50), location: 0.30),
                        .init(color: tint.opacity(0.22), location: 0.58),
                        .init(color: tint.opacity(0), location: 1),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.70
                )
            )
            .opacity(0.30 + 0.34 * clamped + (hovering ? 0.10 : 0))
            // No blur. A radial gradient is already a soft edge; blurring one
            // is doing the same job twice, and the second time costs an
            // offscreen pass the size of the dial — which the media crown then
            // paid every time the playhead moved. Widening the gradient's
            // falloff gets the same softness for nothing.
            .scaleEffect(1.14)
            .animation(animates ? KnurlMotion.settle : nil, value: clamped)
            .allowsHitTesting(false)
    }

    /// A barely-there disc so the readout has something to sit on.
    private var well: some View {
        Circle()
            .fill(metal.well)
            .padding(inset + lineWidth * 0.5)
    }

    private var track: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(metal.track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .padding(inset)
            .rotationEffect(.degrees(135))
            .overlay {
                // A hairline along the groove. One line, top-lit, is the whole
                // difference between a flat ring and a channel the arc sits in.
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(metal.isDark ? 0.10 : 0.55), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round)
                    )
                    .padding(inset + lineWidth / 2 - 0.5)
                    .rotationEffect(.degrees(135))
            }
            .allowsHitTesting(false)
    }

    /// The lit sweep. The gradient runs along the arc rather than across the
    /// box, so the colour travels with the value instead of sitting still
    /// behind it.
    private var arc: some View {
        Circle()
            .trim(from: 0, to: 0.75 * clamped)
            .stroke(
                AngularGradient(
                    stops: [
                        .init(color: tint.opacity(0.60), location: 0),
                        .init(color: tint, location: 0.55),
                        .init(color: tint.opacity(0.95), location: 1),
                    ],
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(270)
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .padding(inset)
            .rotationEffect(.degrees(135))
            .shadow(color: tint.opacity(0.45), radius: size * 0.045)
            .animation(animates ? valueMotion : nil, value: clamped)
            .allowsHitTesting(false)
    }

    /// While you are dragging, the arc must not lag your pointer — anything
    /// with settle time reads as the dial resisting you. Once you let go, or
    /// when the value arrives from somewhere else, it can afford to glide.
    private var valueMotion: Animation {
        dragging ? .interactiveSpring(duration: 0.12) : .smooth(duration: 0.32)
    }

    /// The thing you grab. A dial without a visible handle is a dial you have
    /// to guess at — this one says where the value is and where to put your
    /// pointer, and it grows while you hold it.
    private var handle: some View {
        Circle()
            .fill(metal.handle)
            .frame(width: lineWidth * 0.86, height: lineWidth * 0.86)
            .overlay {
                Circle().strokeBorder(metal.handleEdge, lineWidth: 0.5)
            }
            .overlay {
                Circle()
                    .fill(tint)
                    .frame(width: lineWidth * 0.30, height: lineWidth * 0.30)
            }
            .shadow(color: .black.opacity(0.22), radius: size * 0.018, y: size * 0.006)
            .scaleEffect(dragging ? 1.22 : (hovering ? 1.08 : 1))
            .offset(y: -(size / 2 - inset))
            .rotationEffect(.degrees(DialMath.ringAngle(progress: clamped)))
            .animation(animates ? valueMotion : nil, value: clamped)
            .animation(animates ? KnurlMotion.snap : nil, value: dragging)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var centre: some View {
        if let artwork {
            artwork
                .resizable()
                .scaledToFill()
                .frame(width: size * 0.56, height: size * 0.56)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.10), lineWidth: 1) }
                .shadow(color: .black.opacity(0.35), radius: size * 0.04)
                .overlay(alignment: .bottom) {
                    Text(readout)
                        .font(.system(size: size * 0.048, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(.bottom, size * 0.05)
                }
                .allowsHitTesting(false)
        } else {
            readoutStack
        }
    }

    private var readoutStack: some View {
        VStack(spacing: size * 0.014) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.11, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
            Text(readout)
                .font(.knurlNumeral(readoutSize))
                .minimumScaleFactor(0.35)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(metal.ink)
                .contentTransition(animates ? .numericText() : .opacity)
            if pulsing || levels != nil {
                KnurlEqualizer(
                    levels: levels,
                    tint: tint,
                    bars: 5,
                    active: pulsing || !(levels?.isEmpty ?? true),
                    lively: animates,
                    height: max(10, size * 0.055)
                )
                .padding(.top, size * 0.006)
            } else {
                Text(caption.uppercased())
                    .font(.system(size: max(8, size * 0.040), weight: .semibold))
                    .tracking(size * 0.006)
                    .foregroundStyle(metal.ink.opacity(0.40))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, size * 0.22)
        .allowsHitTesting(false)
    }

    private var readoutSize: CGFloat {
        let base = size * 0.155
        if readout.count > 10 { return base * 0.52 }
        if readout.count > 6 { return base * 0.70 }
        return min(base, 44)
    }
}

// MARK: - Scroll to turn
//
// SwiftUI has no scroll-wheel hook on macOS, and putting an NSView in the way
// would eat the drag and the click. A local monitor that only runs while the
// pointer is over the dial costs nothing and leaves hit testing alone.

private struct CrownScroll: ViewModifier {
    var active: Bool
    var onScroll: (Double) -> Void

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onChange(of: active) { _, isActive in
                if isActive { install() } else { remove() }
            }
            .onDisappear(perform: remove)
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let raw = event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaY / 220
                : event.scrollingDeltaY / 12
            if raw != 0 { onScroll(Double(raw)) }
            return nil
        }
    }

    private func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

// MARK: - The bank
//
// The hero crown plus its satellites. The satellites are the same component
// at a third of the size, so the room reads as one instrument cluster rather
// than a big dial with some buttons under it. Tapping a satellite promotes it.

struct DeskCrownBank: View {
    @Bindable var state: DialState
    var hero: DialMode
    var compact: Bool = false
    var metal: KnurlMetal = .adaptive
    @Namespace private var desk
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.knurlWide) private var wide

    private var live: KnurlLiveliness {
        KnurlLiveliness(reduceMotion: reduceMotion, powerAllows: state.desk.allowsDecorativeMotion)
    }

    /// The hero is deliberately large. This is the control the whole app is
    /// named after, and a 226-point dial in the middle of a 1,280-point page
    /// looked like a widget rather than the instrument. On a wide window it
    /// grows again and the satellites move beside it instead of under it, so
    /// a full-screen Hub reads as one console rather than a tall column with
    /// air on both sides.
    private var heroSize: CGFloat {
        if compact { return wide ? 300 : 250 }
        return wide ? 340 : 286
    }

    private var satelliteSize: CGFloat { wide ? 108 : 96 }

    var body: some View {
        Group {
            if wide {
                HStack(alignment: .center, spacing: KnurlSpace.stage) {
                    heroColumn
                    VStack(alignment: .leading, spacing: KnurlSpace.room) {
                        hint
                        satellites(columns: 2)
                        if hero == .output {
                            OutputDestinationRail(state: state)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: KnurlSpace.room) {
                    heroColumn
                    hint
                    if hero == .output {
                        OutputDestinationRail(state: state).frame(maxWidth: 540)
                    }
                    satellites(columns: 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(live.motion(KnurlMotion.heavy), value: hero)
        .animation(live.motion(), value: wide)
        .animation(live.motion(), value: state.volumePercent)
        .animation(live.motion(), value: state.brightnessPercent)
        .animation(live.motion(), value: state.micPercent)
    }

    private var heroColumn: some View {
        crown(hero, size: heroSize)
            .id(hero)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
    }

    private var hint: some View {
        Text(state.control.hint)
            .font(.knurlLabel)
            .foregroundStyle(KnurlPalette.inkFaint)
            .multilineTextAlignment(wide ? .leading : .center)
            .frame(maxWidth: wide ? .infinity : 420, alignment: wide ? .leading : .center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func satellites(columns: Int) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: KnurlSpace.step),
                count: columns
            ),
            spacing: KnurlSpace.step
        ) {
            ForEach(DialMode.allCases.filter { $0 != hero }) { mode in
                VStack(spacing: KnurlSpace.tight) {
                    crown(mode, size: satelliteSize)
                    Text(mode.title)
                        .font(.knurlEyebrow)
                        .foregroundStyle(
                            state.control == mode ? KnurlPalette.ink : KnurlPalette.inkFaint
                        )
                }
            }
        }
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
            metal: metal,
            artwork: mode == .media ? cover : nil,
            // Mic shows the microphone itself; Media shows that something is
            // playing. Every other face has nothing to pulse about.
            levels: mode == .mic && state.voice.isActive ? state.voice.levels : nil,
            pulsing: (mode == .media && state.music.isPlaying)
                || (mode == .mic && state.voice.isActive),
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
        .matchedGeometryEffect(id: mode.rawValue, in: desk)
    }

    /// Cover art only on the hero: a 96-point satellite is too small to show
    /// an album and still show what it is.
    private var cover: Image? {
        guard hero == .media, let cover = state.music.cover else { return nil }
        return Image(nsImage: cover)
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
        case .output, .media:
            let name = readout(mode)
            return name.count > 9 ? String(name.prefix(8)) + "…" : name
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
        case .output: state.setOutputProgress(value, settle: false)
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
