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
        VStack(alignment: .leading, spacing: 14) {
            header(live)
            if state.music.hasTrack {
                transport
            }
            facts
            actions
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }

    private func header(_ live: MenuBarLive) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.black.opacity(0.16))
                if let cover = state.music.cover, state.music.hasTrack {
                    Image(nsImage: cover)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Image(systemName: live.symbol)
                        .font(.title3.weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(live.line)
                    .font(.headline)
                    .lineLimit(1)
                if state.music.hasTrack, !state.music.artist.isEmpty {
                    Text(state.music.artist)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !live.detail.isEmpty {
                    Text(live.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
                    .frame(width: 44, height: 30)
                    .glassEffect(
                        .regular.tint(HubTint.face(.media, progress: 0.6, muted: false).opacity(0.5)).interactive(),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            shelfButton("forward.fill") { state.skip(1) }
            Spacer(minLength: 0)
            Text(state.music.canSeek ? state.music.timeLabel : "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 4) {
            if state.desk.timer.running {
                Text("Hour · \(state.desk.timer.readout)")
                    .font(.caption.weight(.semibold).monospacedDigit())
            }
            if !state.desk.attention.isEmpty {
                Text("\(state.desk.attention[0].provider.title) needs you")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Text(state.outputName)
                .font(.caption)
                .foregroundStyle(.secondary)
            if state.voice.isListening {
                Text("Flow → \(state.harnessName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            HubGlassButton(
                title: state.desk.timer.running ? state.desk.timer.readout : "Hour",
                symbol: "timer",
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
                .frame(width: 30, height: 30)
                .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}
