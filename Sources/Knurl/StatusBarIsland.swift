import KnurlCore
import SwiftUI

struct StatusBarPill: View {
    @Bindable var state: DialState

    var body: some View {
        let live = snapshot
        HStack(spacing: 6) {
            glyph(live)
            if !live.line.isEmpty {
                Text(live.line)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func glyph(_ live: MenuBarLive) -> some View {
        if live.symbol == "timer" || live.symbol == "waveform" {
            Image(systemName: live.symbol)
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 16, height: 16)
        } else if let cover = state.music.cover, state.music.hasTrack {
            Image(nsImage: cover)
                .resizable()
                .scaledToFill()
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            Image(systemName: live.symbol)
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 16, height: 16)
        }
    }

    private var snapshot: MenuBarLive {
        state.menuBarLive
    }
}

struct StatusBarShelf: View {
    @Bindable var state: DialState

    var body: some View {
        let live = state.menuBarLive
        VStack(alignment: .leading, spacing: KnurlSpace.step) {
            header(live)
            if state.music.hasTrack {
                transport
            }
            facts
            actions
        }
        .padding(KnurlSpace.step + 2)
        .frame(width: 336, alignment: .leading)
    }

    private func header(_ live: MenuBarLive) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(KnurlPalette.sunken)
                if let cover = state.music.cover, state.music.hasTrack {
                    Image(nsImage: cover)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: live.symbol)
                        .font(.title3.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .frame(width: 48, height: 48)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(KnurlPalette.hairline, lineWidth: 1)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    KnurlPip(tint: liveTint, live: isLive, size: 6)
                    Text(live.line)
                        .font(.knurlTitle)
                        .foregroundStyle(KnurlPalette.ink)
                        .lineLimit(1)
                }
                if state.music.hasTrack, !state.music.artist.isEmpty {
                    Text(state.music.artist)
                        .font(.knurlLabel)
                        .foregroundStyle(KnurlPalette.inkSoft)
                        .lineLimit(1)
                } else if !live.detail.isEmpty {
                    Text(live.detail)
                        .font(.knurlLabel)
                        .foregroundStyle(KnurlPalette.inkSoft)
                }
                if let progress = liveProgress {
                    KnurlMeter(progress: progress, tint: liveTint, height: 3)
                        .frame(maxWidth: 180)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var transport: some View {
        HStack(spacing: 8) {
            shelfButton("backward.fill") { state.skip(-1) }
            Button {
                state.collapsedPlay()
            } label: {
                Image(systemName: state.music.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 30)
                    .background {
                        Capsule().fill(HubTint.face(.media, progress: 0.6, muted: false))
                    }
                    .shadow(
                        color: HubTint.face(.media, progress: 0.6, muted: false).opacity(0.45),
                        radius: 9,
                        y: 2
                    )
            }
            .buttonStyle(.plain)
            shelfButton("forward.fill") { state.skip(1) }
            Spacer(minLength: 0)
            Text(state.music.canSeek ? state.music.timeLabel : "")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(KnurlPalette.inkFaint)
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: KnurlSpace.tight) {
            if state.desk.timer.running {
                fact("timer", "Hour · \(state.desk.timer.readout)", KnurlPalette.warn)
            }
            if !state.desk.attention.isEmpty {
                fact(
                    "exclamationmark.circle.fill",
                    "\(state.desk.attention[0].provider.title) needs you",
                    KnurlPalette.alert
                )
            }
            fact("hifispeaker.fill", state.outputName, KnurlPalette.inkSoft)
            if state.voice.isListening {
                fact("waveform", "Flow → \(state.harnessName)", KnurlPalette.live)
            }
            if state.desk.tools.awake {
                fact("eye.fill", "Awake · \(state.desk.tools.awakeLabel)", KnurlPalette.warn)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(KnurlSpace.snug + 2)
        .knurlSurface(.sunken, radius: KnurlRadius.chip)
    }

    private func fact(_ symbol: String, _ text: String, _ tint: Color) -> some View {
        HStack(spacing: KnurlSpace.tight) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(KnurlPalette.inkSoft)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var isLive: Bool {
        state.music.isPlaying || state.voice.isListening || state.desk.timer.running
    }

    private var liveTint: Color {
        if state.voice.isListening { return KnurlPalette.live }
        if state.desk.timer.running { return KnurlPalette.warn }
        return HubTint.face(.media, progress: 0.6, muted: false)
    }

    private var liveProgress: Double? {
        if state.desk.timer.running { return state.desk.timer.crownProgress }
        if state.music.hasTrack, state.music.canSeek { return state.music.displayedPlayhead() }
        return nil
    }

    private var actions: some View {
        HStack(spacing: 8) {
            HubGlassButton(
                title: state.desk.timer.running ? state.desk.timer.readout : "Hour",
                symbol: "timer",
                tint: KnurlPalette.warn,
                selected: state.desk.timer.running
            ) {
                StatusBar.shared.closeShelf()
                state.hubPage = .tools
                state.presentHub()
            }
            HubGlassButton(title: "Dial", symbol: "dial.medium") {
                StatusBar.shared.closeShelf()
                AppDelegate.shared?.noteHUDActivation()
                state.summon()
            }
            HubGlassButton(title: "Hub", symbol: "square.grid.2x2") {
                StatusBar.shared.closeShelf()
                state.presentHub()
            }
            HubGlassButton(title: "Settings", symbol: "gearshape") {
                StatusBar.shared.closeShelf()
                AppDelegate.shared?.openSettings()
            }
        }
    }

    private func shelfButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(KnurlPalette.inkSoft)
                .frame(width: 32, height: 30)
                .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}
