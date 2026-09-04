import KnurlCore
import SwiftUI

// MARK: - Settings
//
// A sheet on the Hub, not a separate preferences window, and drawn in the
// same language as the rest of the desk. Grouped into what you feel, what the
// desk is allowed to touch, and what Knurl promises never to touch.

struct SettingsView: View {
    @Bindable var state: DialState
    @Environment(\.dismiss) private var dismiss

    private var tools: DeskToolbox { state.desk.tools }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: KnurlSpace.room) {
                    feel
                    notch
                    flow
                    weather
                    desk
                    windowManager
                    shelf
                    keys
                    privacy
                }
                .padding(KnurlSpace.room)
            }
            .scrollIndicators(.never)
            footer
        }
        .frame(width: 560, height: 640)
        .background {
            ZStack {
                KnurlPalette.void
                KnurlAtmosphere(
                    tint: HubTint.face(state.control, progress: state.controlProgress, muted: false),
                    energy: 0.2,
                    lively: false
                )
            }
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.knurlHall)
                    .foregroundStyle(KnurlPalette.ink)
                Text("Knurl runs the room. You decide how much of it.")
                    .font(.knurlBody)
                    .foregroundStyle(KnurlPalette.inkSoft)
            }
            Spacer()
        }
        .padding(.horizontal, KnurlSpace.room)
        .padding(.top, KnurlSpace.room)
        .padding(.bottom, KnurlSpace.snug)
    }

    // MARK: Feel

    private var feel: some View {
        card(title: "Feel") {
            VStack(alignment: .leading, spacing: KnurlSpace.step) {
                labelled("Tick sound") {
                    FlowLayout {
                        ForEach(TickSound.allCases) { sound in
                            HubGlassButton(
                                title: sound.title,
                                tint: HubTint.face(state.control, progress: 0.6, muted: false),
                                selected: state.tickSound == sound
                            ) {
                                state.setSound(sound)
                            }
                        }
                    }
                }
                toggle(
                    "Haptic tick",
                    detail: "A detent you can feel on a Force Touch trackpad.",
                    isOn: state.hapticOn
                ) { state.setHaptic($0) }
                toggle(
                    "Show in the menu bar",
                    detail: state.hasNotchHousing
                        ? "Off by default on this Mac: the notch is already the parked Knurl, and a status item beside it says the same things twice."
                        : "This Mac has no notch, so the menu bar is where Knurl parks.",
                    isOn: state.showsMenuBarItem
                ) { state.setShowsMenuBarItem($0) }
                toggle(
                    "Launch at login",
                    detail: "The desk is parked at cold start — nothing pops on the screen.",
                    isOn: state.launchesAtLogin
                ) { state.setLaunchesAtLogin($0) }
                if let login = state.loginItemError {
                    note(login, tint: KnurlPalette.warn)
                }
                if let error = state.hotkeyError {
                    note(error, tint: KnurlPalette.alert)
                }
            }
        }
    }

    // MARK: Notch

    @ViewBuilder
    private var notch: some View {
        if state.hasNotchHousing {
            card(title: "Notch") {
                VStack(alignment: .leading, spacing: KnurlSpace.step) {
                    labelled("Colour") {
                        HStack(spacing: KnurlSpace.snug) {
                            ForEach(NotchTint.allCases) { tint in
                                swatch(tint)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    toggle(
                        "Wrap playback around the notch",
                        detail: "A line traces the cutout's outline as a track plays. It is the one thing the notch does on its own, so it is also the one thing worth being able to switch off.",
                        isOn: state.notchWrap
                    ) { state.setNotchWrap($0) }
                    note(state.notchTint == .automatic
                        ? "Automatic follows what is happening: green while dictating, amber for the hour, the track's own hue while music plays."
                        : "\(state.notchTint.title) always. The notch stops reporting state through colour — which is the trade.")
                }
            }
        }
    }

    private func swatch(_ tint: NotchTint) -> some View {
        let selected = state.notchTint == tint
        return Circle()
            .fill(tint.swatch)
            .frame(width: 24, height: 24)
            .overlay {
                Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1)
            }
            .overlay {
                // The selection ring sits outside the swatch so it never
                // covers the colour you are trying to judge.
                Circle()
                    .strokeBorder(KnurlPalette.ink, lineWidth: 2)
                    .padding(-4)
                    .opacity(selected ? 1 : 0)
            }
            .scaleEffect(selected ? 1.05 : 1)
            .animation(KnurlMotion.snap, value: selected)
            .contentShape(Circle())
            .overlay(ImmediatePress { state.setNotchTint(tint) })
            .help(tint.title)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel(tint.title)
    }

    // MARK: Flow

    private var flow: some View {
        card(title: "Flow") {
            VStack(alignment: .leading, spacing: KnurlSpace.step) {
                HubFact(
                    label: "Hold",
                    value: HotkeyCenter.shared.talkChord,
                    secondary: "Speak, release, and the words land where you were"
                )
                if Voice.canPaste {
                    note("Knurl can paste for you. Speech never leaves this Mac.", tint: KnurlPalette.live)
                } else {
                    note(
                        "Knurl can hear you but cannot type for you: landing dictation in another app is a synthetic ⌘V, and macOS only delivers that to a trusted process. Until then your words are copied and you press ⌘V yourself. macOS quits and reopens Knurl when you grant it — that is expected.",
                        tint: KnurlPalette.warn
                    )
                    HStack(spacing: KnurlSpace.tight) {
                        HubGlassButton(
                            title: "Allow Knurl",
                            symbol: "checkmark.shield",
                            tint: KnurlPalette.warn,
                            selected: true
                        ) {
                            Voice.requestPastePermission()
                        }
                        HubGlassButton(title: "Open Settings", symbol: "gearshape") {
                            Voice.openAccessibilitySettings()
                        }
                    }
                }
            }
        }
    }

    // MARK: Weather

    private var weather: some View {
        card(title: "Weather") {
            VStack(alignment: .leading, spacing: KnurlSpace.step) {
                toggle(
                    "Show local weather",
                    detail: "The only part of Knurl that uses the network or your location. Your coordinate is rounded to about a kilometre and sent to Open-Meteo — no account, no key, nothing else, once every half hour.",
                    isOn: state.desk.weather.enabled
                ) { state.desk.weather.enabled = $0 }
                if let message = state.desk.weather.message {
                    note(message, tint: KnurlPalette.warn)
                }
            }
        }
    }

    // MARK: Desk

    private var desk: some View {
        card(title: "Desk") {
            VStack(alignment: .leading, spacing: KnurlSpace.step) {
                labelled("Power") {
                    FlowLayout {
                        ForEach(PowerMode.allCases) { mode in
                            HubGlassButton(
                                title: mode.title,
                                tint: KnurlPalette.warn,
                                selected: state.desk.powerMode == mode
                            ) {
                                state.desk.powerMode = mode
                            }
                            .help(mode.summary)
                        }
                    }
                }
                note("Battery mode parks decorative motion. The room stops breathing and the Mac lasts longer.")
                toggle(
                    "Keep this Mac awake",
                    detail: "Holds a power assertion so the display never idles. Released the moment you turn it off or quit.",
                    isOn: tools.awake
                ) { tools.setAwake($0) }
            }
        }
    }

    // MARK: Window Manager

    private var windowManager: some View {
        card(title: "Window Manager") {
            VStack(alignment: .leading, spacing: KnurlSpace.step) {
                toggle(
                    "Let Knurl move windows",
                    detail: "Asks for Accessibility the moment you turn it on. Flow's paste uses the same permission — granting it once covers both.",
                    isOn: state.desk.windows.enabled
                ) { state.desk.windows.setEnabled($0) }
                if let status = state.desk.windows.status {
                    note(status, tint: KnurlPalette.warn)
                }
                note("Public move and resize only. Never Screen Recording, never keystroke tiling.")
            }
        }
    }

    // MARK: Shelf

    private var shelf: some View {
        card(title: "Clipboard shelf") {
            VStack(alignment: .leading, spacing: KnurlSpace.step) {
                toggle(
                    "Keep the last twelve copies",
                    detail: "Held in memory only, never written to disk, gone when Knurl quits.",
                    isOn: tools.shelfEnabled
                ) { tools.shelfEnabled = $0 }
                if tools.shelfEnabled, !tools.shelf.isEmpty {
                    HubGlassButton(title: "Clear the shelf now", symbol: "trash") {
                        tools.clearShelf()
                    }
                }
            }
        }
    }

    // MARK: Keys

    private var keys: some View {
        card(title: "Keys") {
            VStack(spacing: 0) {
                HubFact(label: "Dial", value: HotkeyCenter.shared.chord, secondary: "Summon the last face")
                HubFact(label: "Flow", value: HotkeyCenter.shared.talkChord, secondary: "Hold to talk, release to paste")
                HubFact(label: "Volume", value: "⌃⌥↑ / ⌃⌥↓", secondary: "From anywhere")
                HubFact(label: "Faces", value: "1 – 5", secondary: "Media, Volume, Bright, Output, Mic")
                HubFact(label: "Hub pages", value: "⌘1 – ⌘6", secondary: "In rail order")
                HubFact(label: "Settings", value: "⌘,")
            }
        }
    }

    // MARK: Privacy

    private var privacy: some View {
        card(title: "What Knurl never does") {
            VStack(alignment: .leading, spacing: KnurlSpace.snug) {
                ForEach(promises, id: \.self) { promise in
                    HStack(alignment: .top, spacing: KnurlSpace.snug) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(KnurlPalette.alert)
                            .frame(width: 14, height: 14)
                            .background { Circle().fill(KnurlPalette.alert.opacity(0.16)) }
                        Text(promise)
                            .font(.knurlBody)
                            .foregroundStyle(KnurlPalette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                note(
                    CrownServer.shared.ready
                        ? "The iPhone crown is on the local network."
                        : "The iPhone crown is still starting."
                )
            }
        }
    }

    private var promises: [String] {
        [
            "Record your screen or take screenshots.",
            "Monitor or store keystrokes. It posts exactly one synthetic ⌘V, to land a Flow dictation, and reads none.",
            "Send your speech, your clipboard, or your source to any cloud service.",
            "Keep the microphone open when you are not holding Flow.",
        ]
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("Knurl · macOS 26 · Apple Silicon")
                .font(.knurlEyebrow.weight(.regular))
                .foregroundStyle(KnurlPalette.inkFaint)
            Spacer()
            HubGlassButton(
                title: "Done",
                tint: HubTint.face(state.control, progress: 0.6, muted: false),
                selected: true
            ) {
                state.dismissSettings()
                dismiss()
            }
        }
        .padding(KnurlSpace.room)
        .background {
            Rectangle()
                .fill(KnurlPalette.stage.opacity(0.9))
                .overlay(alignment: .top) {
                    Rectangle().fill(KnurlPalette.hairline).frame(height: 1)
                }
        }
    }

    // MARK: Parts

    private func card<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: KnurlSpace.step) {
            KnurlEyebrow(text: title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(KnurlSpace.step)
        .knurlSurface()
    }

    private func labelled<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: KnurlSpace.tight) {
            Text(title)
                .font(.knurlBody.weight(.medium))
                .foregroundStyle(KnurlPalette.ink)
            content()
        }
    }

    private func toggle(
        _ title: String,
        detail: String,
        isOn: Bool,
        set: @escaping (Bool) -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: KnurlSpace.step) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.knurlBody.weight(.medium))
                    .foregroundStyle(KnurlPalette.ink)
                Text(detail)
                    .font(.knurlEyebrow.weight(.regular))
                    .foregroundStyle(KnurlPalette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: KnurlSpace.snug)
            Toggle("", isOn: Binding(get: { isOn }, set: set))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(title)
        }
    }

    private func note(_ text: String, tint: Color = KnurlPalette.inkFaint) -> some View {
        Text(text)
            .font(.knurlEyebrow.weight(.regular))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
