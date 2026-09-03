import KnurlCore
import SwiftUI

// MARK: - The Hub
//
// A rail and a stage, both drawn on one lit field. This replaced a
// NavigationSplitView: the split view gave a stock macOS sidebar for free,
// but it also owned the selection pill, the row metrics and the material
// behind them, none of which could be made to look like the dial. The cost is
// that this file now has to do the keyboard work the split view did — hence
// ⌘1–⌘6 below, and the reorder commands in each row's context menu.

struct HubView: View {
    @Bindable var state: DialState
    var agents: AgentSessionManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var live: KnurlLiveliness {
        KnurlLiveliness(reduceMotion: reduceMotion, powerAllows: state.desk.allowsDecorativeMotion)
    }

    var body: some View {
        HStack(spacing: 0) {
            HubRail(state: state, agents: agents)
                .frame(width: 244)
                // The field lives behind the rail and nowhere else.
                //
                // It used to be drawn at full window size underneath
                // everything, which meant a mesh gradient the size of a
                // full-screen window was rasterised every frame so that a
                // 244-point strip of it could show through. The stage is
                // opaque; the other thousand points were pure waste.
                .background {
                    KnurlAtmosphere(
                        tint: faceTint,
                        energy: energy,
                        lively: live.lively
                    )
                }
            stage
        }
        .background(KnurlPalette.void)
        .environment(\.knurlOnScreen, state.hubVisible)
        .sheet(isPresented: $state.wantsSettings) {
            SettingsView(state: state)
        }
        .background {
            RoutePicker()
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityHidden(true)
        }
    }

    /// How hard the room glows: a running hour, live dictation or playing
    /// music all mean something is happening, and the background says so
    /// before any individual widget does.
    private var energy: Double {
        var value = 0.20
        if state.music.isPlaying { value += 0.30 }
        if state.voice.isListening { value += 0.35 }
        if state.desk.timer.running { value += 0.20 }
        return min(1, value)
    }

    private var faceTint: Color {
        HubTint.face(
            state.control,
            progress: state.controlProgress,
            muted: state.isMuted && state.control == .volume
        )
    }

    private var stage: some View {
        ZStack {
            switch state.hubPage {
            case .home: HubHome(state: state)
            case .tools: HubTools(state: state)
            case .workspace: HubWorkspace(state: state)
            case .flow: HubFlow(state: state)
            case .system: HubSystem(state: state)
            case .sessions: HubSessions(state: state, agents: agents)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .animation(live.motion(), value: state.hubPage)
        // The stage is a slab lifted off the field, so the rail reads as
        // chrome and the page reads as content.
        //
        // Opaque, deliberately. A translucent slab looked marginally richer
        // and cost the whole window: every frame of the animated field behind
        // it forced the rail, the cards, their shadows and their blurs to
        // recomposite. Opaque means the field animates behind a 244-point
        // strip instead of behind 1,180 points of content. The stage keeps a
        // face-tinted gradient of its own, which is static and free.
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: KnurlRadius.stage,
                bottomLeadingRadius: KnurlRadius.stage,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(KnurlPalette.stage)
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: KnurlRadius.stage,
                    bottomLeadingRadius: KnurlRadius.stage,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.035), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            }
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: KnurlRadius.stage,
                    bottomLeadingRadius: KnurlRadius.stage,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            faceTint.opacity(0.10 + 0.10 * energy),
                            .clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottom
                    )
                )
                .animation(.easeInOut(duration: 0.9), value: state.control)
            }
            .overlay(alignment: .leading) {
                // A lit edge where the stage meets the rail, so the page reads
                // as sitting on top of the chrome rather than beside it.
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [KnurlPalette.hairlineStrong, KnurlPalette.hairline],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 1)
            }
            .shadow(color: .black.opacity(0.45), radius: 22, x: -6)
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: KnurlRadius.stage,
                bottomLeadingRadius: KnurlRadius.stage,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
    }
}

// MARK: - Rail

struct HubRail: View {
    @Bindable var state: DialState
    var agents: AgentSessionManager

    @Namespace private var rail
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var live: KnurlLiveliness {
        KnurlLiveliness(reduceMotion: reduceMotion, powerAllows: state.desk.allowsDecorativeMotion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KnurlSpace.step) {
            // Room for the traffic lights, which float over full-size content.
            Spacer().frame(height: 34)
            wordmark
            nowCard
            pages
            Spacer(minLength: KnurlSpace.room)
            faceStrip
            settingsRow
        }
        .padding(.horizontal, KnurlSpace.step)
        .padding(.bottom, KnurlSpace.step)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(live.motion(), value: state.hubPage)
        .animation(live.motion(), value: state.voice.isListening)
        .animation(live.motion(), value: state.desk.timer.running)
    }

    private var wordmark: some View {
        HStack(spacing: KnurlSpace.snug) {
            ZStack {
                Circle().fill(KnurlPalette.control)
                Circle()
                    .trim(from: 0, to: 0.75 * DialMath.clampVolume(state.controlProgress))
                    .stroke(faceTint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .padding(5)
                    .rotationEffect(.degrees(135))
            }
            .frame(width: 26, height: 26)

            Text("Knurl")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KnurlPalette.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, KnurlSpace.tight)
        .padding(.bottom, KnurlSpace.tight)
    }

    /// The one live block in the chrome. Whatever the desk is doing right now
    /// is here, and clicking it lands on the page that owns it — so the rail
    /// answers "what is happening" without you picking a page first.
    private var nowCard: some View {
        Button {
            state.hubPage = nowPage
        } label: {
            VStack(alignment: .leading, spacing: KnurlSpace.tight) {
                HStack(spacing: KnurlSpace.tight) {
                    if state.music.isPlaying && !state.voice.isListening && !state.desk.timer.running {
                        KnurlEqualizer(
                            tint: nowTint,
                            bars: 3,
                            active: true,
                            lively: live.lively,
                            height: 10
                        )
                    } else {
                        KnurlPip(tint: nowTint, live: nowIsLive, lively: live.lively, size: 6)
                    }
                    Text(nowLabel.uppercased())
                        .font(.knurlEyebrow)
                        .tracking(0.9)
                        .foregroundStyle(KnurlPalette.inkFaint)
                    Spacer(minLength: 0)
                }
                Text(nowValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KnurlPalette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.opacity)
                KnurlMeter(progress: nowProgress, tint: nowTint, height: 4)
            }
            .padding(KnurlSpace.snug + 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .knurlSurface(.card, radius: KnurlRadius.chip + 3, tint: nowTint, glow: nowIsLive ? 0.35 : 0)
        .accessibilityLabel("\(nowLabel), \(nowValue)")
    }

    private var pages: some View {
        VStack(spacing: 2) {
            ForEach(Array(state.hubOrder.enumerated()), id: \.element) { index, page in
                railRow(page, index: index)
            }
        }
        .padding(.top, KnurlSpace.tight)
    }

    private func railRow(_ page: HubPage, index: Int) -> some View {
        let selected = state.hubPage == page
        return Button {
            state.hubPage = page
        } label: {
            HStack(spacing: KnurlSpace.snug) {
                Image(systemName: page.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 20)
                    .foregroundStyle(selected ? faceTint : KnurlPalette.inkSoft)
                Text(page.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? KnurlPalette.ink : KnurlPalette.inkSoft)
                Spacer(minLength: 4)
                trailing(page)
            }
            .padding(.horizontal, KnurlSpace.snug + 2)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: KnurlRadius.chip, style: .continuous)
                        .fill(KnurlPalette.control)
                        .matchedGeometryEffect(id: "rail-pill", in: rail)
                }
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut(index), modifiers: .command)
        .contextMenu {
            Button("Move up") { state.moveHubPages(from: IndexSet(integer: index), to: max(0, index - 1)) }
                .disabled(index == 0)
            Button("Move down") { state.moveHubPages(from: IndexSet(integer: index), to: index + 2) }
                .disabled(index == state.hubOrder.count - 1)
        }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(page.title)
    }

    @ViewBuilder
    private func trailing(_ page: HubPage) -> some View {
        switch page {
        case .tools where state.desk.timer.running:
            Text(state.desk.timer.readout)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(KnurlPalette.warn)
                .contentTransition(reduceMotion ? .opacity : .numericText())
        case .tools where state.desk.tools.awake:
            Image(systemName: "eye.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(KnurlPalette.warn)
        case .flow where state.voice.isListening:
            KnurlPip(tint: KnurlPalette.live, live: true, lively: live.lively, size: 6)
        case .sessions where !agents.store.live.isEmpty:
            Text("\(agents.store.live.count)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(KnurlPalette.calm)
        case .workspace where state.desk.windows.lastPreset != nil:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(KnurlPalette.inkFaint)
        default:
            EmptyView()
        }
    }

    /// Five taps that land the dial without leaving the page you are on. The
    /// same 1–5 the crown and the HUD already answer to.
    private var faceStrip: some View {
        VStack(alignment: .leading, spacing: KnurlSpace.tight) {
            KnurlEyebrow(text: "Dial")
            HStack(spacing: 4) {
                ForEach(DialMode.allCases) { mode in
                    let selected = state.control == mode
                    Button {
                        if selected { state.confirmDial() } else { state.selectControl(mode) }
                    } label: {
                        Image(systemName: faceSymbol(mode))
                            .font(.system(size: 11, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .foregroundStyle(selected ? .white : KnurlPalette.inkSoft)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selected ? tint(mode) : KnurlPalette.control)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("\(mode.title) — \(mode.confirmTitle) on a second click")
                    .accessibilityLabel(mode.title)
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .padding(.horizontal, KnurlSpace.tight)
    }

    private var settingsRow: some View {
        Button {
            state.wantsSettings = true
        } label: {
            HStack(spacing: KnurlSpace.snug) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 20)
                Text("Settings")
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Text("⌘,")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(KnurlPalette.inkFaint)
            }
            .foregroundStyle(KnurlPalette.inkSoft)
            .padding(.horizontal, KnurlSpace.snug + 2)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(",", modifiers: .command)
        .accessibilityLabel("Settings")
    }

    // MARK: Rail facts

    private var faceTint: Color {
        tint(state.control)
    }

    private func tint(_ mode: DialMode) -> Color {
        HubTint.face(
            mode,
            progress: state.controlProgress,
            muted: (mode == .volume && state.isMuted) || (mode == .mic && state.isMicMuted)
        )
    }

    private func faceSymbol(_ mode: DialMode) -> String {
        switch mode {
        case .volume: state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        case .media: state.music.isPlaying ? "pause.fill" : "play.fill"
        case .output: "hifispeaker.fill"
        case .mic:
            if state.voice.isListening { "waveform" }
            else if state.isMicMuted { "mic.slash.fill" }
            else { "mic.fill" }
        }
    }

    private var nowIsLive: Bool {
        state.voice.isListening || state.desk.timer.running || state.music.isPlaying
    }

    private var nowLabel: String {
        if state.voice.isListening { return "Flow" }
        if state.desk.timer.running { return "Hour" }
        if state.music.hasTrack { return "Playing" }
        return state.control.title
    }

    private var nowValue: String {
        if state.voice.isListening { return "→ \(state.harnessName)" }
        if state.desk.timer.running { return state.desk.timer.readout }
        if state.music.hasTrack { return state.music.title }
        return state.controlReadout
    }

    private var nowProgress: Double {
        if state.desk.timer.running { return state.desk.timer.crownProgress }
        if state.music.hasTrack { return state.music.displayedPlayhead() }
        return state.controlProgress
    }

    private var nowTint: Color {
        if state.voice.isListening { return KnurlPalette.live }
        if state.desk.timer.running { return KnurlPalette.warn }
        return faceTint
    }

    private var nowPage: HubPage {
        if state.voice.isListening { return .flow }
        if state.desk.timer.running { return .tools }
        if state.music.hasTrack { return .system }
        return .home
    }

    private func shortcut(_ index: Int) -> KeyEquivalent {
        switch index {
        case 0: "1"
        case 1: "2"
        case 2: "3"
        case 3: "4"
        case 4: "5"
        default: "6"
        }
    }
}
