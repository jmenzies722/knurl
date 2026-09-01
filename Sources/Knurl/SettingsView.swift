import KnurlCore
import SwiftUI

struct SettingsView: View {
    @Bindable var state: DialState

    var body: some View {
        Form {
            Section("General") {
                Picker("Tick sound", selection: Binding(
                    get: { state.tickSound },
                    set: { state.setSound($0) }
                )) {
                    ForEach(TickSound.allCases) { sound in
                        Text(sound.title).tag(sound)
                    }
                }
                Toggle("Haptic tick", isOn: Binding(
                    get: { state.hapticOn },
                    set: { state.setHaptic($0) }
                ))
                Toggle("Launch at Login", isOn: Binding(
                    get: { state.launchesAtLogin },
                    set: { state.setLaunchesAtLogin($0) }
                ))
                if let login = state.loginItemError {
                    Text(login).foregroundStyle(.secondary)
                }
                if let error = state.hotkeyError {
                    Text(error).foregroundStyle(.red)
                }
            }
            Section("Desk") {
                Text("1–5 switch faces. Turn for level. Click to confirm. \(HotkeyCenter.shared.chord) is the dial. Closing the Hub does not quit.")
                    .foregroundStyle(.secondary)
                Picker("Power", selection: Binding(
                    get: { state.desk.powerMode },
                    set: { state.desk.powerMode = $0 }
                )) {
                    ForEach(PowerMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }
            Section("Window Manager") {
                Toggle("Enable Window Manager", isOn: Binding(
                    get: { state.desk.windows.enabled },
                    set: { state.desk.windows.setEnabled($0) }
                ))
                Text("Uses Accessibility to move windows you ask to move. Off by default. Never requires Screen Recording.")
                    .foregroundStyle(.secondary)
                if let status = state.desk.windows.status {
                    Text(status).foregroundStyle(.secondary)
                }
            }
            Section("Flow") {
                Text("Hold \(HotkeyCenter.shared.talkChord). Speech stays on this Mac. Words land in \(state.harnessName).")
                    .foregroundStyle(.secondary)
            }
            Section("Agents") {
                labeled("Cursor", "Not configured")
                labeled("Claude Code", "Not configured")
                labeled("Codex", "Not configured")
                labeled("Xcode", "Limited support")
            }
            Section("Privacy") {
                Text("Knurl does not record your screen, monitor your keyboard, or send your source code to a cloud AI service. Accessibility is used only after you enable Window Manager. Agent hooks, when installed, send local lifecycle events only.")
                    .foregroundStyle(.secondary)
            }
            Section("About") {
                Text("Knurl is the workstation layer for agentic engineering on macOS. The harness does the coding.")
                    .foregroundStyle(.secondary)
                Text(CrownServer.shared.ready
                     ? "iPhone crown is on the local network."
                     : "iPhone crown is still starting.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 520)
    }

    private func labeled(_ name: String, _ status: String) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(status)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
