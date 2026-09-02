import KnurlCore
import SwiftUI

struct HubView: View {
    @Bindable var state: DialState
    @Namespace private var rail
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                railHeader
                GlassEffectContainer(spacing: 6) {
                    VStack(spacing: 6) {
                        ForEach(HubPage.allCases) { page in
                            railItem(page)
                        }
                    }
                }
                Spacer(minLength: 12)
                settingsRow
            }
            .padding(12)
            .navigationSplitViewColumnWidth(min: 208, ideal: 228, max: 260)
            .backgroundExtensionEffect()
        } detail: {
            switch state.hubPage {
            case .home: HubHome(state: state)
            case .tools: HubTools(state: state)
            case .workspace: HubWorkspace(state: state)
            case .flow: HubFlow(state: state)
            case .system: HubSystem(state: state)
            case .sessions: HubSessions(state: state)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .animation(motion, value: state.hubPage)
        .animation(motion, value: state.voice.isListening)
        .animation(motion, value: state.desk.timer.running)
        .animation(motion, value: state.desk.timer.readout)
        .sheet(isPresented: $state.wantsSettings) {
            SettingsView(state: state)
        }
    }

    private var motion: Animation? {
        HubMotion.spring(reduceMotion: reduceMotion, allowed: state.desk.allowsDecorativeMotion)
    }

    private var railHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Knurl")
                .font(.headline)
            Text(railWhisper)
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(
                    state.desk.allowsDecorativeMotion && !reduceMotion
                        ? .numericText()
                        : .opacity
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Knurl, \(railWhisper)")
    }

    private var railWhisper: String {
        if state.desk.timer.running {
            return "Hour · \(state.desk.timer.readout)"
        }
        if state.voice.isListening {
            return "Flow → \(state.harnessName)"
        }
        if state.music.hasTrack {
            return state.music.title
        }
        return state.outputName
    }

    private var settingsRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "gearshape")
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 18)
            Text("Settings")
                .font(.callout)
            Spacer(minLength: 4)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(ImmediatePress(action: { state.wantsSettings = true }))
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Settings")
    }

    private func railItem(_ page: HubPage) -> some View {
        let selected = state.hubPage == page
        return HStack(spacing: 10) {
            Image(systemName: page.symbol)
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 18)
            Text(page.title)
                .font(.callout.weight(selected ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 4)
            if page == .tools, state.desk.timer.running {
                Text(state.desk.timer.readout)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .accessibilityLabel("Hour \(state.desk.timer.readout)")
            }
            if page == .flow, state.voice.isListening {
                Image(systemName: "waveform")
                    .font(.caption.weight(.semibold))
                    .symbolEffect(
                        .variableColor.iterative,
                        isActive: state.desk.allowsDecorativeMotion && !reduceMotion
                    )
                    .accessibilityLabel("Listening")
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .glassEffect(
            selected
                ? .regular.tint(Color.primary.opacity(0.16)).interactive()
                : .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .modifier(HubSelectedGlass(active: selected, id: "hub-rail", namespace: rail))
        .overlay(ImmediatePress(action: { state.hubPage = page }))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityLabel(page.title)
    }
}
