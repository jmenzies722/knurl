import KnurlCore
import SwiftUI

// MARK: - Flow
//
// Hold, speak, release. The page has one job the old one did badly: make it
// obvious, without reading anything, whether the mic is live and where the
// words are about to land. Hence a visualiser that is dead flat when nothing
// is being heard, and a destination that is stated in words rather than
// implied by an arrow in a header.

struct HubFlow: View {
    @Bindable var state: DialState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var live: KnurlLiveliness {
        KnurlLiveliness(reduceMotion: reduceMotion, powerAllows: state.desk.allowsDecorativeMotion)
    }

    private var micTint: Color {
        HubTint.face(.mic, progress: state.controlProgress, muted: state.isMicMuted)
    }

    var body: some View {
        HubPageScroll {
            header
            if !Voice.canPaste { pasteGate }
            stage
            controls
            destination
            recent
            vocabulary
        }
        .animation(live.motion(KnurlMotion.heavy), value: state.voice.isActive)
        .animation(live.motion(), value: state.voice.lastTranscript)
    }

    // MARK: Header

    private var header: some View {
        HubHallHeader(title: "Flow", whisper: "Talk it in. Keep building.") {
            HubGlassButton(
                title: state.harnessName,
                symbol: "arrow.up.forward.app",
                tint: KnurlPalette.live,
                selected: state.voice.isListening
            ) {
                state.jumpToHarness()
            }
            .help("Bring \(state.harnessName) to the front")
        }
    }

    /// Flow's one hard dependency, stated plainly.
    ///
    /// Speech recognition is on-device and needs nothing. Putting the words
    /// into another app is a synthetic ⌘V, and macOS only delivers that to a
    /// process it trusts. Without it Flow still transcribes — the text just
    /// stops on the clipboard instead of arriving where you were typing.
    private var pasteGate: some View {
        HStack(alignment: .top, spacing: KnurlSpace.step) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(KnurlPalette.warn)
            VStack(alignment: .leading, spacing: KnurlSpace.tight) {
                Text("Flow can hear you, but it cannot type for you yet")
                    .font(.knurlBody.weight(.semibold))
                    .foregroundStyle(KnurlPalette.ink)
                Text("Landing dictation in another app is a synthetic ⌘V, and macOS only delivers that to a trusted process. Until you allow Knurl in Accessibility, your words are copied and you press ⌘V yourself.\n\nmacOS quits and reopens Knurl the moment you flip that switch — that is expected, not a crash.")
                    .font(.knurlEyebrow.weight(.regular))
                    .foregroundStyle(KnurlPalette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: KnurlSpace.tight) {
                    HubGlassButton(title: "Allow Knurl", symbol: "checkmark.shield", tint: KnurlPalette.warn, selected: true) {
                        Voice.requestPastePermission()
                    }
                    HubGlassButton(title: "Open Settings", symbol: "gearshape") {
                        Voice.openAccessibilitySettings()
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(KnurlSpace.step)
        .knurlSurface(.card, tint: KnurlPalette.warn, glow: 0.3)
    }

    // MARK: Stage

    /// The one big thing on the page. A ring that closes as levels rise, a
    /// mirrored bar field, and the live text under it — all driven by the same
    /// `voice.levels` buffer, so if the meter moves, the mic is genuinely open.
    private var stage: some View {
        VStack(spacing: KnurlSpace.room) {
            ZStack {
                Circle()
                    .fill(micTint)
                    .blur(radius: 60)
                    .opacity(state.voice.isActive ? 0.30 : 0.06)
                    .frame(width: 260, height: 260)

                FlowVisualiser(
                    levels: state.voice.levels,
                    tint: micTint,
                    listening: state.voice.isActive,
                    lively: live.lively
                )
                .frame(width: 260, height: 260)
            }
            .frame(maxWidth: .infinity)

            Text(liveLine)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(state.voice.isActive ? KnurlPalette.ink : KnurlPalette.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .contentTransition(.opacity)

            if let message = state.voice.message {
                Text(message)
                    .font(.knurlEyebrow)
                    .foregroundStyle(KnurlPalette.warn)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, KnurlSpace.room)
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: KnurlSpace.snug) {
            Spacer(minLength: 0)
            HubGlassButton(
                title: state.voice.isActive ? "Release to send" : "Hold to talk",
                symbol: state.voice.isActive ? "waveform" : "mic.fill",
                tint: micTint,
                selected: state.voice.isActive
            ) {}
            .overlay(
                ImmediateHold(
                    down: { state.beginTalk(presentHUD: false) },
                    up: { state.endTalk() }
                )
            )

            HubGlassButton(
                title: state.voice.isListening ? "Stop" : "Toggle",
                symbol: "record.circle",
                tint: micTint
            ) {
                state.toggleTalk(presentHUD: false)
            }

            if state.voice.isActive {
                HubGlassButton(title: "Cancel", symbol: "xmark", tint: KnurlPalette.alert) {
                    state.cancelTalk()
                }
            }
            if !state.voice.lastTranscript.isEmpty, !state.voice.isActive {
                HubGlassButton(title: "Send again", symbol: "arrow.uturn.up") {
                    state.resendTalk()
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Destination

    private var destination: some View {
        HubSection(title: "Where the words go") {
            HStack(spacing: KnurlSpace.snug) {
                KnurlActionCard(
                    title: state.harnessName,
                    detail: Voice.canPaste
                        ? "Release pastes here with one synthetic ⌘V."
                        : "Not yet — allow Knurl in Accessibility and it will paste for you.",
                    symbol: "arrow.up.forward.app",
                    tint: Voice.canPaste ? KnurlPalette.live : KnurlPalette.warn,
                    selected: true,
                    badge: "⌃⌥M"
                ) {
                    state.jumpToHarness()
                }
                KnurlActionCard(
                    title: "On this Mac",
                    detail: "SpeechAnalyzer on-device. No cloud, no always-on mic, no stored audio.",
                    symbol: "lock.shield",
                    tint: KnurlPalette.calm,
                    badge: state.voice.languageName
                ) {}
                KnurlActionCard(
                    title: state.desk.tools.shelfEnabled ? "Shelf is on" : "Keep a shelf",
                    detail: state.desk.tools.shelfEnabled
                        ? "The last twelve copies are held on Tools, so a paste is never lost."
                        : "Turn on the clipboard shelf and Flow's text survives the next ⌘C.",
                    symbol: "doc.on.clipboard",
                    tint: KnurlPalette.warn,
                    selected: state.desk.tools.shelfEnabled,
                    badge: state.desk.tools.shelfEnabled ? "\(state.desk.tools.shelf.count)" : nil
                ) {
                    state.desk.tools.shelfEnabled.toggle()
                }
            }
        }
    }

    // MARK: Recent

    private var recent: some View {
        HubSection(
            title: "Last dictation",
            accessory: state.voice.lastTranscript.isEmpty ? nil : "\(state.voice.lastTranscript.count) characters"
        ) {
            if state.voice.lastTranscript.isEmpty {
                HubEmpty(
                    title: "Nothing dictated yet",
                    detail: "The last transcript stays here until Knurl quits. The audio is never kept at all."
                )
            } else {
                Text(state.voice.lastTranscript)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(KnurlPalette.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(KnurlSpace.step)
                    .knurlSurface(.sunken)
            }
        }
    }

    // MARK: Vocabulary

    private var vocabulary: some View {
        HubSection(title: "Developer vocabulary", accessory: "\(FlowLexicon.phrases.count) hints") {
            VStack(alignment: .leading, spacing: KnurlSpace.snug) {
                FlowLayout {
                    ForEach(FlowLexicon.phrases.prefix(18), id: \.self) { phrase in
                        Text(phrase)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(KnurlPalette.inkSoft)
                            .padding(.horizontal, KnurlSpace.snug)
                            .padding(.vertical, 5)
                            .background { Capsule().fill(KnurlPalette.sunken) }
                            .overlay { Capsule().strokeBorder(KnurlPalette.hairline, lineWidth: 1) }
                    }
                }
                Text("On-device contextual hints only. Nothing is downloaded and nothing is trained.")
                    .font(.knurlEyebrow.weight(.regular))
                    .foregroundStyle(KnurlPalette.inkFaint)
            }
        }
    }

    private var liveLine: String {
        if state.voice.isActive || !state.voice.preview.isEmpty {
            return state.voice.preview.isEmpty ? "Listening…" : state.voice.preview
        }
        if !state.voice.lastTranscript.isEmpty {
            return state.voice.lastTranscript
        }
        return "Hold ⌃⌥M anywhere on the Mac, speak, release."
    }
}

// MARK: - Visualiser
//
// Bars radiating from a ring. Each bar is one level sample, mirrored around
// the circle so the field stays symmetric — an asymmetric ring reads as a
// glitch rather than as sound.

struct FlowVisualiser: View {
    var levels: [Float]
    var tint: Color
    var listening: Bool
    var lively: Bool

    private let bars = 56

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !(lively && listening))) { timeline in
            let phase = lively ? timeline.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                Circle()
                    .stroke(KnurlPalette.hairline, lineWidth: 1)
                    .padding(46)

                Canvas { context, size in
                    let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                    let inner = min(size.width, size.height) / 2 - 82
                    for index in 0 ..< bars {
                        let angle = Double(index) / Double(bars) * 2 * .pi - .pi / 2
                        let level = Double(sample(index, phase: phase))
                        let length = 6 + level * 62
                        var path = Path()
                        path.move(to: CGPoint(
                            x: centre.x + cos(angle) * inner,
                            y: centre.y + sin(angle) * inner
                        ))
                        path.addLine(to: CGPoint(
                            x: centre.x + cos(angle) * (inner + length),
                            y: centre.y + sin(angle) * (inner + length)
                        ))
                        context.stroke(
                            path,
                            with: .color(tint.opacity(0.22 + level * 0.78)),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                    }
                }

                VStack(spacing: 4) {
                    Image(systemName: listening ? "waveform" : "mic.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(listening ? tint : KnurlPalette.inkFaint)
                        .contentTransition(.symbolEffect(.replace))
                    Text(listening ? "LISTENING" : "READY")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(listening ? tint : KnurlPalette.inkFaint)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Mirrors the newest samples around the circle. With no signal the ring
    /// settles to a barely-alive idle so the control does not look broken —
    /// but the idle amplitude is a twentieth of a real voice, which is the
    /// difference you actually need to see.
    private func sample(_ index: Int, phase: Double) -> Float {
        let half = bars / 2
        let mirrored = index < half ? index : bars - index - 1
        guard listening, !levels.isEmpty else {
            return Float(0.03 + 0.02 * sin(phase * 1.2 + Double(mirrored) * 0.3))
        }
        let slice = levels.suffix(half)
        guard !slice.isEmpty else { return 0.05 }
        let position = mirrored % slice.count
        let value = slice[slice.index(slice.startIndex, offsetBy: position)]
        return min(1, max(0.04, value))
    }
}
