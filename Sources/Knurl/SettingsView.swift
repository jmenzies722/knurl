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
                Text("The menu bar is a live island — music, Hour, and Flow. Click it for the shelf. Right-click for Hub and Quit.")
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
            Section("Tools") {
                Text("Hour lives on Tools. Turn the crown for minutes, click to start. The notch keeps the remaining time. Dim the room drops brightness and remembers where you were.")
                    .foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Text("Knurl does not record your screen, monitor your keyboard, or send your source code to a cloud AI service. Accessibility is used only after you enable Window Manager.")
                    .foregroundStyle(.secondary)
            }
            Section("About") {
                Text("Knurl runs the room — music, volume, brightness, speakers, mic, Flow, windows, Hour.")
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
}
