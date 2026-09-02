import KnurlCore
import SwiftUI

struct HubView: View {
    @Bindable var state: DialState
    var agents: AgentSessionManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            List(selection: pageSelection) {
                Section {
                    ForEach(state.hubOrder) { page in
                        railItem(page).tag(page)
                    }
                    .onMove { state.moveHubPages(from: $0, to: $1) }
                } header: {
                    railHeader
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 208, ideal: 228, max: 260)
            .safeAreaInset(edge: .bottom, spacing: 0) { settingsRow }
        } detail: {
            switch state.hubPage {
            case .home: HubHome(state: state)
            case .tools: HubTools(state: state)
            case .workspace: HubWorkspace(state: state)
            case .flow: HubFlow(state: state)
            case .system: HubSystem(state: state)
            case .sessions: HubSessions(state: state, agents: agents)
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

    // List selection is optional; the Hub is always on a page, so a nil
    // write (⌘-click to deselect) is ignored rather than blanking the detail.
    private var pageSelection: Binding<HubPage?> {
        Binding(
            get: { state.hubPage },
            set: { if let page = $0 { state.hubPage = page } }
        )
    }

    private var railHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Knurl")
                .font(.headline)
                .foregroundStyle(.primary)
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
        .textCase(nil)
        .padding(.bottom, 6)
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
        Button {
            state.wantsSettings = true
        } label: {
            Label("Settings", systemImage: "gearshape")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .keyboardShortcut(",", modifiers: .command)
        .accessibilityLabel("Settings")
    }

    private func railItem(_ page: HubPage) -> some View {
        Label(page.title, systemImage: page.symbol)
            .badge(badge(page))
            .overlay(alignment: .trailing) {
                if page == .flow, state.voice.isListening {
                    Image(systemName: "waveform")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .symbolEffect(
                            .variableColor.iterative,
                            isActive: state.desk.allowsDecorativeMotion && !reduceMotion
                        )
                        .accessibilityLabel("Listening")
                }
            }
    }

    private func badge(_ page: HubPage) -> Text? {
        guard page == .tools, state.desk.timer.running else { return nil }
        return Text(state.desk.timer.readout).monospacedDigit()
    }
}
