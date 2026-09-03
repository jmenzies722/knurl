import AppKit
import KnurlCore
import SwiftUI

// MARK: - Tools
//
// The desk capabilities that are not faces. Every tile here does something to
// this Mac through a public interface and no new permission: a power
// assertion, `NSWorkspace` hide, the pasteboard, an unmount. Nothing on this
// page is a placeholder — if it is drawn, it works.

struct HubTools: View {
    @Bindable var state: DialState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tools: DeskToolbox { state.desk.tools }

    private var live: KnurlLiveliness {
        KnurlLiveliness(reduceMotion: reduceMotion, powerAllows: state.desk.allowsDecorativeMotion)
    }

    var body: some View {
        HubPageScroll {
            header
            weather
            hour
            desk
            shelf
            jump
            disks
        }
        .animation(live.motion(), value: state.desk.timer.running)
        .animation(live.motion(), value: state.roomDimmed)
        .animation(live.motion(), value: state.voice.isListening)
        .animation(live.motion(), value: tools.awake)
        .animation(live.motion(), value: tools.shelf)
        .animation(live.motion(), value: tools.volumes)
        .onAppear { tools.refreshVolumes() }
    }

    // MARK: Header

    private var header: some View {
        HubHallHeader(title: "Tools", whisper: whisper) {
            if let message = tools.message {
                Text(message)
                    .font(.knurlEyebrow)
                    .foregroundStyle(KnurlPalette.inkSoft)
                    .padding(.horizontal, KnurlSpace.snug)
                    .padding(.vertical, 5)
                    .background { Capsule().fill(KnurlPalette.raised) }
                    .transition(.opacity)
            }
        }
    }

    private var whisper: String {
        if state.desk.timer.running { return "The hour is running. The notch keeps time." }
        if tools.awake { return "This Mac is being kept awake." }
        return "Turn the hour. Hold the room. Nothing here asks for a permission."
    }

    // MARK: Weather

    private var weather: some View {
        HubSection(
            title: "Weather",
            accessory: state.desk.weather.reading?.place
        ) {
            WeatherCard(desk: state.desk.weather)
        }
    }

    // MARK: The hour

    private var hour: some View {
        HubSection(title: "The hour", accessory: state.desk.timer.readout) {
            HStack(alignment: .center, spacing: KnurlSpace.hall) {
                DeskCrown(
                    progress: state.desk.timer.crownProgress,
                    tint: KnurlPalette.warn,
                    symbol: state.desk.timer.running ? "pause.fill" : "play.fill",
                    readout: state.desk.timer.readout,
                    caption: state.desk.timer.running ? "Running" : "Set",
                    ticks: 13,
                    size: 240,
                    lively: state.desk.allowsDecorativeMotion,
                    onTurn: { state.setHourCrown($0) },
                    onConfirm: { state.toggleHour() }
                )

                VStack(alignment: .leading, spacing: KnurlSpace.step) {
                    Text(state.desk.timer.running
                        ? "Turning now would reset the block. Click the crown to pause."
                        : "Turn the crown or pick a length, then click it to start.")
                        .font(.knurlBody)
                        .foregroundStyle(KnurlPalette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: KnurlSpace.tight) {
                        KnurlEyebrow(text: "Length")
                        HStack(spacing: KnurlSpace.tight) {
                            ForEach(DeskTimer.presets, id: \.seconds) { preset in
                                HubGlassButton(
                                    title: preset.title,
                                    tint: KnurlPalette.warn,
                                    selected: !state.desk.timer.running
                                        && abs(state.desk.timer.duration - preset.seconds) < 1
                                ) {
                                    state.setHourDuration(preset.seconds)
                                }
                            }
                        }
                    }

                    HStack(spacing: KnurlSpace.tight) {
                        HubGlassButton(
                            title: state.desk.timer.running ? "Pause" : "Start",
                            symbol: state.desk.timer.running ? "pause.fill" : "play.fill",
                            tint: KnurlPalette.warn,
                            selected: state.desk.timer.running
                        ) {
                            state.toggleHour()
                        }
                        if state.desk.timer.remaining != state.desk.timer.duration || state.desk.timer.running {
                            HubGlassButton(title: "Reset", symbol: "arrow.counterclockwise") {
                                state.resetHour()
                            }
                        }
                        HubGlassButton(title: "Start the hour", symbol: "hourglass") {
                            state.startTheHour()
                        }
                        .help("Fifty minutes, lights down, the notch keeps time.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: The desk

    private var desk: some View {
        HubSection(title: "The desk") {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: KnurlSpace.snug), count: 3),
                spacing: KnurlSpace.snug
            ) {
                KnurlActionCard(
                    title: tools.awake ? "Staying awake" : "Keep awake",
                    detail: tools.awake
                        ? "Display sleep is held off. Click to release."
                        : "Holds a power assertion so the display never idles.",
                    symbol: tools.awake ? "eye.fill" : "eye",
                    tint: KnurlPalette.warn,
                    selected: tools.awake,
                    badge: tools.awake ? tools.awakeLabel : nil
                ) {
                    tools.toggleAwake()
                }
                .contextMenu {
                    Button("Awake for 30 minutes") { tools.setAwake(true, minutes: 30) }
                    Button("Awake for 1 hour") { tools.setAwake(true, minutes: 60) }
                    Button("Awake for 3 hours") { tools.setAwake(true, minutes: 180) }
                    Divider()
                    Button("Release") { tools.setAwake(false) }
                }

                KnurlActionCard(
                    title: state.roomDimmed ? "Restore lights" : "Dim the room",
                    detail: state.roomDimmed
                        ? "Bring the display back to where it was."
                        : "Drop brightness and remember the level.",
                    symbol: state.roomDimmed ? "sun.max.fill" : "moon.fill",
                    tint: HubTint.face(.brightness, progress: 0.7, muted: false),
                    selected: state.roomDimmed,
                    badge: "\(state.brightnessPercent)%"
                ) {
                    state.toggleRoomDim()
                }

                KnurlActionCard(
                    title: "Clear the room",
                    detail: "Hide every other app. Nothing quits, nothing closes.",
                    symbol: "rectangle.on.rectangle.slash",
                    tint: KnurlPalette.calm
                ) {
                    tools.clearTheRoom()
                }
                .contextMenu {
                    Button("Show everything again") { tools.showEverything() }
                }

                KnurlActionCard(
                    title: state.swapLabel,
                    detail: state.outputName,
                    symbol: "arrow.triangle.2.circlepath",
                    tint: HubTint.face(.output, progress: 0.6, muted: false),
                    badge: state.outputKind
                ) {
                    state.swapSpeaker()
                }

                KnurlActionCard(
                    title: state.voice.isListening ? "Release Flow" : "Hold Flow",
                    detail: "Speak, release, and the words land in \(state.harnessName).",
                    symbol: state.voice.isListening ? "waveform" : "mic.fill",
                    tint: KnurlPalette.live,
                    selected: state.voice.isListening,
                    badge: "⌃⌥M"
                ) {}
                .overlay(
                    ImmediateHold(
                        down: { state.beginTalk(presentHUD: false) },
                        up: { state.endTalk() }
                    )
                )

                KnurlActionCard(
                    title: "Snap the windows",
                    detail: state.desk.windows.enabled
                        ? "Last layout: \(state.desk.windows.lastPreset?.title ?? "Free")"
                        : "Window Manager is off. Turn it on in Workspace.",
                    symbol: "rectangle.split.2x2",
                    tint: KnurlPalette.calm,
                    selected: state.desk.windows.lastPreset != nil,
                    badge: state.desk.windows.enabled ? "\(state.desk.windows.windows.count)" : nil
                ) {
                    state.hubPage = .workspace
                }
            }
        }
    }

    // MARK: Clipboard shelf

    private var shelf: some View {
        HubSection(
            title: "Clipboard shelf",
            accessory: tools.shelfEnabled ? "\(tools.shelf.count) of 12" : "off"
        ) {
            VStack(alignment: .leading, spacing: KnurlSpace.snug) {
                HStack(spacing: KnurlSpace.tight) {
                    HubGlassButton(
                        title: tools.shelfEnabled ? "Watching" : "Start watching",
                        symbol: tools.shelfEnabled ? "doc.on.clipboard.fill" : "doc.on.clipboard",
                        tint: KnurlPalette.live,
                        selected: tools.shelfEnabled
                    ) {
                        tools.shelfEnabled.toggle()
                    }
                    if tools.shelfEnabled, !tools.shelf.isEmpty {
                        HubGlassButton(title: "Clear", symbol: "trash") {
                            tools.clearShelf()
                        }
                    }
                    Spacer(minLength: 0)
                    Text("Memory only. Never written to disk.")
                        .font(.knurlEyebrow.weight(.regular))
                        .foregroundStyle(KnurlPalette.inkFaint)
                }

                if !tools.shelfEnabled {
                    HubEmpty(
                        title: "The shelf is off",
                        detail: "Turn it on and Knurl keeps the last twelve things you copied, so a Flow paste is not lost to the next ⌘C. It holds them in memory and forgets them when Knurl quits."
                    )
                } else if tools.shelf.isEmpty {
                    HubEmpty(
                        title: "Nothing copied yet",
                        detail: "Copy something anywhere on this Mac and it appears here."
                    )
                } else {
                    VStack(spacing: 4) {
                        ForEach(tools.shelf) { item in
                            shelfRow(item)
                        }
                    }
                }
            }
        }
    }

    private func shelfRow(_ item: ShelfItem) -> some View {
        HStack(alignment: .top, spacing: KnurlSpace.snug) {
            Image(systemName: item.lineCount > 1 ? "text.alignleft" : "textformat")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(KnurlPalette.inkFaint)
                .frame(width: 18)
                .padding(.top, 1)
            Text(item.preview)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(KnurlPalette.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.at.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(KnurlPalette.inkFaint)
            Image(systemName: "doc.on.doc")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(KnurlPalette.inkFaint)
        }
        .padding(.horizontal, KnurlSpace.snug + 2)
        .padding(.vertical, KnurlSpace.snug)
        .knurlSurface(.card, radius: KnurlRadius.chip)
        .overlay(ImmediatePress { tools.copyToClipboard(item) })
        .contextMenu {
            Button("Copy") { tools.copyToClipboard(item) }
            Button("Forget") { tools.forget(item) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Copy: \(item.preview)")
    }

    // MARK: Jump

    private var jump: some View {
        HubSection(title: "Jump", accessory: state.harnessName) {
            ScrollView(.horizontal) {
                HStack(spacing: KnurlSpace.tight) {
                    ForEach(tools.deskApps.prefix(14), id: \.processIdentifier) { app in
                        appChip(app)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
        }
    }

    private func appChip(_ app: NSRunningApplication) -> some View {
        VStack(spacing: 5) {
            if let icon = tools.icon(for: app.processIdentifier) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 30, height: 30)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 20))
                    .foregroundStyle(KnurlPalette.inkFaint)
                    .frame(width: 30, height: 30)
            }
            Text(app.localizedName ?? "App")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(KnurlPalette.inkSoft)
                .lineLimit(1)
        }
        .frame(width: 68)
        .padding(.vertical, KnurlSpace.snug)
        .knurlSurface(.card, radius: KnurlRadius.chip)
        .overlay(ImmediatePress { tools.activate(app) })
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Switch to \(app.localizedName ?? "app")")
    }

    // MARK: Disks

    @ViewBuilder
    private var disks: some View {
        if !tools.volumes.isEmpty {
            HubSection(title: "Disks", accessory: "\(tools.volumes.count)") {
                VStack(spacing: 4) {
                    ForEach(tools.volumes) { volume in
                        HStack(spacing: KnurlSpace.snug) {
                            Image(systemName: volume.ejectable ? "externaldrive" : "externaldrive.connected.to.line.below")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(KnurlPalette.inkSoft)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(volume.name)
                                    .font(.knurlBody.weight(.medium))
                                    .foregroundStyle(KnurlPalette.ink)
                                Text(volume.detail)
                                    .font(.knurlEyebrow.weight(.regular))
                                    .foregroundStyle(KnurlPalette.inkFaint)
                            }
                            Spacer(minLength: KnurlSpace.snug)
                            KnurlMeter(progress: volume.progress, tint: KnurlPalette.calm, height: 4)
                                .frame(width: 100)
                            if volume.ejectable {
                                HubGlassButton(title: "Eject", symbol: "eject.fill") {
                                    tools.eject(volume)
                                }
                            }
                        }
                        .padding(.horizontal, KnurlSpace.snug + 2)
                        .padding(.vertical, KnurlSpace.snug)
                        .knurlSurface(.card, radius: KnurlRadius.chip)
                    }
                }
            }
        }
    }
}


// MARK: - Weather card
//
// Off until asked for, and honest about why. Every other tool on this page
// works with no permission and no network; this one needs both, so it says so
// on its face instead of quietly turning them on.

struct WeatherCard: View {
    @Bindable var desk: WeatherDesk

    var body: some View {
        Group {
            if let reading = desk.reading {
                report(reading)
            } else {
                gate
            }
        }
        .animation(KnurlMotion.settle, value: desk.reading)
        .animation(KnurlMotion.settle, value: desk.enabled)
    }

    private func report(_ reading: WeatherReading) -> some View {
        HStack(alignment: .center, spacing: KnurlSpace.room) {
            Image(systemName: reading.symbol)
                .font(.system(size: 40, weight: .medium))
                .symbolRenderingMode(.multicolor)
                .frame(width: 62)

            VStack(alignment: .leading, spacing: 2) {
                Text(reading.temperatureLabel)
                    .font(.knurlNumeral(38))
                    .foregroundStyle(KnurlPalette.ink)
                    .contentTransition(.numericText())
                Text(reading.summary)
                    .font(.knurlBody.weight(.medium))
                    .foregroundStyle(KnurlPalette.inkSoft)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 3) {
                if let range = reading.rangeLabel {
                    Text(range)
                        .font(.knurlLabel.monospacedDigit())
                        .foregroundStyle(KnurlPalette.inkSoft)
                }
                Text(reading.apparentLabel)
                    .font(.knurlEyebrow.weight(.regular))
                    .foregroundStyle(KnurlPalette.inkFaint)
                Text(reading.at.formatted(date: .omitted, time: .shortened))
                    .font(.knurlEyebrow.weight(.regular).monospacedDigit())
                    .foregroundStyle(KnurlPalette.inkFaint)
            }
        }
        .padding(KnurlSpace.step + 2)
        .knurlSurface(.card, tint: KnurlPalette.calm)
        .contextMenu {
            Button("Turn weather off") { desk.enabled = false }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(reading.summary), \(reading.temperatureLabel), \(reading.place)")
    }

    private var gate: some View {
        HStack(alignment: .top, spacing: KnurlSpace.step) {
            Image(systemName: "cloud.sun")
                .font(.system(size: 20, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(KnurlPalette.calm)
                .frame(width: 34, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(KnurlPalette.calm.opacity(0.16))
                }

            VStack(alignment: .leading, spacing: KnurlSpace.tight) {
                Text(desk.enabled ? "Getting the weather…" : "Local weather")
                    .font(.knurlBody.weight(.semibold))
                    .foregroundStyle(KnurlPalette.ink)
                Text(desk.message
                    ?? "The only tool here that leaves this Mac. It asks macOS roughly where you are, rounds that to about a kilometre, and sends it to Open-Meteo — no account, no key, nothing else.")
                    .font(.knurlEyebrow.weight(.regular))
                    .foregroundStyle(KnurlPalette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                if !desk.enabled {
                    HubGlassButton(
                        title: "Turn on weather",
                        symbol: "location",
                        tint: KnurlPalette.calm,
                        selected: true
                    ) {
                        desk.enabled = true
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(KnurlSpace.step)
        .knurlSurface(.sunken)
    }
}
