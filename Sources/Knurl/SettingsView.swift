import KnurlCore
import SwiftUI

struct SettingsView: View {
    @Bindable var state: DialState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Knurl")
                .font(.title2.weight(.semibold))
            Text("Knurl is the engineer desk. The notch chip expands into the full desk. \(HotkeyCenter.shared.chord) opens the side dial. \(HotkeyCenter.shared.talkChord) is hold-to-talk. Agent later. Tick sounds live here.")
                .foregroundStyle(.secondary)
            if let error = state.hotkeyError {
                Text(error).foregroundStyle(.red)
            }
            Divider()
            Text("Tick sound")
                .font(.headline)
            Picker("Tick sound", selection: Binding(
                get: { state.tickSound },
                set: { state.setSound($0) }
            )) {
                ForEach(TickSound.allCases) { sound in
                    Text(sound.title).tag(sound)
                }
            }
            .pickerStyle(.segmented)
            Toggle("Haptic tick", isOn: Binding(
                get: { state.hapticOn },
                set: { state.setHaptic($0) }
            ))
            Divider()
            Text(CrownServer.shared.ready
                 ? "iPhone: Knurl is on the local network. Open Knurl on your phone."
                 : "iPhone: still starting the local listener.")
                .foregroundStyle(.secondary)
            Text("If Music is already playing, Knurl follows that track. Talk stays on this Mac. Closing the card does not stop the song.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(22)
        .frame(width: 440, height: 380, alignment: .topLeading)
    }
}
