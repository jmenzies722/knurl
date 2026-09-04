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
    @State private var readiness = Voice.readiness

    private var live: KnurlLiveliness {
        KnurlLiveliness(reduceMotion: reduceMotion, powerAllows: state.desk.allowsDecorativeMotion)
    }

    private var micTint: Color {
        HubTint.face(.mic, progress: state.controlProgress, muted: state.isMicMuted)
    }

    var body: some View {
        HubPageScroll {
            header
            if !readiness.isReady { setupCard }
            stage
            controls
            destination
            recent
            vocabulary
        }
        .animation(live.motion(KnurlMotion.heavy), value: state.voice.isActive)
        .animation(live.motion(), value: state.voice.lastTranscript)
        .animation(live.motion(), value: readiness)
        .onAppear {
            readiness = Voice.readiness
            // Ask the moment you open the page, not the moment you hold the
            // key. Opening Flow *is* the intent, the app is frontmost, and you
            // are looking at the thing the prompt is about — which is why the
            // permissions had never been granted: they were only ever asked
            // for from the background, mid-gesture, behind another window.
            if Voice.needsListeningPrompt {
                Task { readiness = await Voice.requestListening() }
            }
        }
        // The Accessibility grant restarts the app, but microphone and speech
        // do not — so the card has to notice when you come back from Settings.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            readiness = Voice.readiness
        }
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

    /// What Flow needs, one line each, with the button that fixes it.
    ///
    /// This replaced a paragraph about Accessibility that was both incomplete
    /// and unactionable. Flow needs three separate permissions and was asking
    /// for all of them mid-gesture while the app was in the background, so the
    /// prompts landed behind whatever you were working in. On this Mac the
    /// microphone and speech permissions were still `notDetermined` after
    /// weeks: nobody had ever seen them, and Flow just quietly did nothing.
    private var setupCard: some View {
        VStack(alignment: .leading, spacing: KnurlSpace.step) {
            HStack(spacing: KnurlSpace.snug) {
                Image(systemName: "waveform.badge.exclamationmark")
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(KnurlPalette.warn)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Flow needs three things")
                        .font(.knurlBody.weight(.semibold))
                        .foregroundStyle(KnurlPalette.ink)
                    Text("Speech never leaves this Mac. Nothing here is on until you turn it on.")
                        .font(.knurlEyebrow.weight(.regular))
                        .foregroundStyle(KnurlPalette.inkSoft)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 1) {
                readyRow(
                    "Microphone",
                    detail: "To hear you at all.",
                    ok: readiness.microphone
                ) { Task { readiness = await Voice.requestListening() } }

                readyRow(
                    "Speech recognition",
                    detail: "On-device transcription. No cloud, no upload.",
                    ok: readiness.speech
                ) { Task { readiness = await Voice.requestListening() } }

                readyRow(
                    "Accessibility",
                    detail: "To paste for you. Without it the words stop on the clipboard.",
                    ok: readiness.paste
                ) { Voice.requestPastePermission() }
            }

            if !readiness.isReady {
                HStack(spacing: KnurlSpace.tight) {
                    HubGlassButton(
                        title: "Set up Flow",
                        symbol: "checkmark.shield",
                        tint: KnurlPalette.live,
                        selected: true
                    ) {
                        Task {
                            readiness = await Voice.requestListening()
                            if !readiness.paste { Voice.requestPastePermission() }
                        }
                    }
                    HubGlassButton(title: "Privacy Settings", symbol: "gearshape") {
                        Voice.openPrivacySettings("Privacy_Microphone")
                    }
                    Text("macOS restarts Knurl when you grant Accessibility.")
                        .font(.knurlEyebrow.weight(.regular))
                        .foregroundStyle(KnurlPalette.inkFaint)
                }
            }
        }
        .padding(KnurlSpace.step)
        .knurlSurface(.card, tint: readiness.isReady ? KnurlPalette.live : KnurlPalette.warn, glow: 0.25)
    }

    private func readyRow(
        _ title: String,
        detail: String,
        ok: Bool,
        fix: @escaping () -> Void
    ) -> some View {
        HStack(spacing: KnurlSpace.snug) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dotted")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ok ? KnurlPalette.live : KnurlPalette.inkFaint)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.knurlBody.weight(.medium))
                    .foregroundStyle(KnurlPalette.ink)
                Text(detail)
                    .font(.knurlEyebrow.weight(.regular))
                    .foregroundStyle(KnurlPalette.inkFaint)
            }
            Spacer(minLength: KnurlSpace.snug)
            if !ok {
                HubGlassButton(title: "Allow", tint: KnurlPalette.warn, action: fix)
            }
        }
        .padding(.horizontal, KnurlSpace.snug)
        .padding(.vertical, KnurlSpace.tight)
    }

    // MARK: Stage
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
                    detail: readiness.paste
                        ? "Release pastes here with one synthetic ⌘V."
                        : "Not yet — allow Knurl in Accessibility and it will paste for you.",
                    symbol: "arrow.up.forward.app",
                    tint: readiness.paste ? KnurlPalette.live : KnurlPalette.warn,
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
