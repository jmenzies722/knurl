import KnurlCore
import SwiftUI

struct HubView: View {
    @Bindable var state: DialState

    var body: some View {
        NavigationSplitView {
            List(selection: $state.hubPage) {
                Section("Knurl") {
                    ForEach(HubPage.allCases) { page in
                        Label(page.title, systemImage: page.symbol)
                            .tag(page)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 196, ideal: 216, max: 248)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    state.wantsSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        } detail: {
            switch state.hubPage {
            case .home: HubHome(state: state)
            case .agents: HubAgents(state: state)
            case .workspace: HubWorkspace(state: state)
            case .flow: HubFlow(state: state)
            case .system: HubSystem(state: state)
            case .sessions: HubSessions(state: state)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $state.wantsSettings) {
            SettingsView(state: state)
        }
    }
}
