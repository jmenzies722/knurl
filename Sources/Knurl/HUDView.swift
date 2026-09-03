import AppKit
import KnurlCore
import SwiftUI

struct HUDView: View {
    @Bindable var state: DialState
    @Namespace private var faces

    var body: some View {
        Group {
            if state.isPresented {
                expanded
            } else {
                collapsed
            }
        }
        .environment(\.knurlOnScreen, state.hudVisible)
    }

    /// Parked state: a pill above the Dock, in three sizes.
    ///
    /// Rest is three live controls and nothing else, dimmed so it reads as
    /// furniture. Hover adds the label. Listening takes over entirely — the
    /// waveform, the words as they land, and where they are going. Every
    /// control works at rest, so hover is a bonus and never a requirement.
    private var collapsed: some View {
        HStack(spacing: 7) {
            Button {
                state.summon()
            } label: {
                MiniDial(state: state)
            }
            .buttonStyle(.plain)
            .focusable(false)

            if state.voice.isActive {
                flowLane
                    .transition(.opacity)
            } else if state.pillShowsPages {
                pageLane
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            } else {
                if state.pillHovered {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.controlTitle.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                        Text(state.collapsedLine)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                        KnurlMeter(
                            progress: state.controlProgress,
                            tint: DialSwatch.tint(state.control, state: state),
                            height: 2.5,
                            showsTrack: false
                        )
                    }
                    .frame(width: 108, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
                pillButton(
                    symbol: "square.grid.2x2.fill",
                    tint: .secondary,
                    label: "Show Hub pages"
                ) {
                    state.pillShowsPages = true
                    HUDPanel.shared.refreshPill()
                }
                pillButton(
                    symbol: "mic.fill",
                    tint: .secondary,
                    label: "Start Knurl Flow"
                ) {
                    state.toggleTalk(presentHUD: false)
                }
                pillButton(
                    symbol: state.music.isPlaying ? "pause.fill" : "play.fill",
                    tint: .secondary,
                    label: state.music.isPlaying ? "Pause" : "Play"
                ) {
                    state.collapsedPlay()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .glassEffect(
            .regular.tint(DialSwatch.tint(state.control, state: state).opacity(0.12)).interactive(),
            in: Capsule()
        )
        .overlay {
            Capsule().strokeBorder(
                DialSwatch.tint(state.control, state: state)
                    .opacity(state.pillHovered || state.voice.isActive ? 0.55 : 0.22),
                lineWidth: 1
            )
        }
        .shadow(
            color: DialSwatch.tint(state.control, state: state)
                .opacity(state.voice.isActive ? 0.45 : 0.18),
            radius: 18,
            y: 5
        )
        .overlay(alignment: .leading) {
            if state.pillHovered, !state.voice.isActive {
                MoveBar().frame(width: 12).transition(.opacity)
            }
        }
        .opacity(state.pillHovered || state.voice.isActive ? 1 : 0.62)
        .animation(.spring(duration: 0.26, bounce: 0.1), value: state.pillHovered)
        .animation(.spring(duration: 0.3, bounce: 0.12), value: state.voice.isActive)
        .animation(.spring(duration: 0.28, bounce: 0.12), value: state.pillShowsPages)
        .onChange(of: state.voice.isActive) { HUDPanel.shared.refreshPill() }
    }

    /// The six Hub pages, inline. Picking one opens the Hub on that page, so
    /// the pill navigates without becoming a second window.
    private var pageLane: some View {
        HStack(spacing: 4) {
            ForEach(state.hubOrder) { page in
                let selected = state.hubPage == page
                Image(systemName: page.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .frame(width: 32, height: 30)
                    .glassEffect(
                        selected ? .regular.tint(DialSwatch.stable(state.control).opacity(0.4)) : .regular,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay(ImmediatePress {
                        state.hubPage = page
                        state.pillShowsPages = false
                        HUDPanel.shared.refreshPill()
                        state.presentHub()
                    })
                    .help(page.title)
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityLabel(page.title)
            }
            pillButton(symbol: "xmark", tint: .secondary, label: "Back to controls") {
                state.pillShowsPages = false
                HUDPanel.shared.refreshPill()
            }
        }
    }

    /// What the pill becomes while Flow is listening: level, words, destination,
    /// and one obvious way to stop.
    private var flowLane: some View {
        HStack(spacing: 8) {
            FlowWaveform(levels: state.voice.levels, tint: DialSwatch.mic, bars: 12)
                .frame(width: 52)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.voice.preview.isEmpty ? "Listening…" : state.voice.preview)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .contentTransition(.opacity)
                Text("→ \(state.harnessName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .overlay(ImmediatePress(action: { state.jumpToHarness() }))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Jump to \(state.harnessName)")
            }
            .frame(width: 132, alignment: .leading)

            pillButton(symbol: "xmark", tint: .secondary, label: "Cancel Flow") {
                state.cancelTalk()
            }
            pillButton(symbol: "stop.fill", tint: .accentColor, label: "Stop and paste") {
                state.endTalk()
            }
        }
    }

    private func pillButton(
        symbol: String,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(
                tint == .secondary ? AnyShapeStyle(Color.white.opacity(0.62)) : AnyShapeStyle(tint)
            )
            .frame(width: 30, height: 30)
            .glassEffect(.regular, in: Circle())
            .overlay { Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1) }
            .overlay(ImmediatePress(action: action))
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
    }

    /// The dial panel. Glass, because it floats over whatever you were doing
    /// — but glass tinted by the live face, with a rim that carries the same
    /// colour, so the panel belongs to the dial inside it rather than being a
    /// neutral tray the dial happens to sit on.
    private var expanded: some View {
        let tint = DialSwatch.tint(state.control, state: state)
        return VStack(spacing: 15) {
            header
            if !state.desk.attention.isEmpty {
                HStack(spacing: 6) {
                    KnurlPip(tint: KnurlPalette.warn, live: true, size: 6)
                    Text("\(state.desk.attention[0].provider.title) needs you")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(KnurlPalette.warn)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background { Capsule().fill(KnurlPalette.warn.opacity(0.14)) }
            }
            if state.activeTool != nil {
                ToolCrown(state: state)
                toolBlock
            } else {
                CrownDial(state: state)
                controlBlock
            }
            if state.activeTool == nil {
                talkBar
                if state.control != .mic {
                    transport
                }
                librarySources
                outputRoster
                inputRoster
            } else {
                if state.voice.isActive {
                    toolFlowStrip
                }
                toolControls
            }
            toolsRow
            deskStrip
            roomSatellites
        }
        .padding(18)
        .frame(width: 404)
        .glassEffect(
            .regular.tint(tint.opacity(0.10)).interactive(),
            in: RoundedRectangle(cornerRadius: 34, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [tint.opacity(0.45), .white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: tint.opacity(0.22), radius: 34, y: 10)
        .shadow(color: .black.opacity(0.45), radius: 26, y: 14)
        // One curve for everything that changes the panel's height, so the
        // window and its contents move together rather than the content
        // snapping and the frame catching up behind it.
        .animation(KnurlMotion.settle, value: state.control)
        .animation(KnurlMotion.settle, value: state.activeTool)
        .animation(KnurlMotion.settle, value: state.voice.isActive)
        .animation(KnurlMotion.settle, value: state.desk.tools.awake)
        .animation(KnurlMotion.settle, value: state.roomDimmed)
        .onChange(of: state.control) { HUDPanel.shared.resizeExpanded() }
        .onChange(of: state.activeTool) { HUDPanel.shared.resizeExpanded() }
        .onChange(of: state.voice.isActive) { HUDPanel.shared.resizeExpanded() }
        .onChange(of: state.inputDevices.count) { HUDPanel.shared.resizeExpanded() }
        .onChange(of: state.outputDevices.count) { HUDPanel.shared.resizeExpanded() }
    }

    /// One chip per tool. Adding a tool adds a case to DeskTool, not a face.
    /// The desk tools, on the surface you summon without leaving your work.
    ///
    /// These lived only on the Hub's Tools page, which means reaching them
    /// meant opening a window — the exact thing the side dial exists to avoid.
    /// Every one is a real system call and none of them asks for a permission:
    /// a power assertion, a brightness write, an NSWorkspace hide, a Core
    /// Audio swap.
    private var deskStrip: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                deskKey(
                    state.desk.tools.awake ? "eye.fill" : "eye",
                    "Keep awake",
                    on: state.desk.tools.awake,
                    tint: DialSwatch.bright
                ) { state.desk.tools.toggleAwake() }

                deskKey(
                    state.roomDimmed ? "sun.max.fill" : "moon.fill",
                    state.roomDimmed ? "Restore lights" : "Dim the room",
                    on: state.roomDimmed,
                    tint: DialSwatch.bright
                ) { state.toggleRoomDim() }

                deskKey(
                    "rectangle.on.rectangle.slash",
                    "Clear the room",
                    on: false,
                    tint: DialSwatch.output
                ) { state.desk.tools.clearTheRoom() }

                deskKey(
                    "arrow.triangle.2.circlepath",
                    state.swapLabel,
                    on: false,
                    tint: DialSwatch.output
                ) { state.swapSpeaker() }

                deskKey(
                    "rectangle.split.2x2",
                    "Snap the windows",
                    on: state.desk.windows.lastPreset != nil,
                    tint: DialSwatch.output
                ) {
                    state.hubPage = .workspace
                    state.presentHub()
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deskKey(
        _ symbol: String,
        _ label: String,
        on: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.62)))
            .frame(width: 38, height: 32)
            .glassEffect(on ? .regular.tint(tint.opacity(0.5)) : .regular, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(on ? tint.opacity(0.7) : .clear, lineWidth: 1)
            }
            .contentTransition(.symbolEffect(.replace))
            .overlay(ImmediatePress(action: action))
            .help(label)
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel(label)
    }

    private var toolsRow: some View {
        HStack(spacing: 6) {
            ForEach(DeskTool.allCases) { tool in
                let active = state.activeTool == tool
                HStack(spacing: 5) {
                    Image(systemName: tool.symbol)
                        .font(.caption.weight(.semibold))
                        .symbolRenderingMode(.monochrome)
                    Text(tool == .hour && state.desk.timer.running
                         ? state.desk.timer.readout
                         : tool.title)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                }
                .foregroundStyle(active ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.6)))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .glassEffect(
                    active ? .regular.tint(tool.tint.opacity(0.5)) : .regular,
                    in: Capsule()
                )
                .overlay {
                    Capsule().strokeBorder(active ? tool.tint.opacity(0.7) : .clear, lineWidth: 1)
                }
                .shadow(color: active ? tool.tint.opacity(0.4) : .clear, radius: 9, y: 2)
                .overlay(ImmediatePress {
                    state.selectTool(active ? nil : tool)
                })
                .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
                .accessibilityLabel(tool.title)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.2), value: state.activeTool)
    }

    private var toolBlock: some View {
        VStack(spacing: 4) {
            Text(state.toolReadout)
                .font(.title3.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
            Text(state.toolCaption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var toolControls: some View {
        switch state.activeTool {
        case .hour:
            HStack(spacing: 8) {
                ForEach([15, 25, 50, 90], id: \.self) { minutes in
                    let selected = !state.desk.timer.running
                        && abs(state.desk.timer.duration - Double(minutes) * 60) < 1
                    Text("\(minutes)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .frame(width: 40, height: 32)
                        .glassEffect(
                            selected ? .regular.tint(DialSwatch.bright.opacity(0.4)) : .regular,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                        .overlay(ImmediatePress { state.setHourDuration(Double(minutes) * 60) })
                        .accessibilityLabel("\(minutes) minutes")
                }
                if state.desk.timer.isArmed || state.desk.timer.running {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 32)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(ImmediatePress { state.resetHour() })
                        .accessibilityLabel("Reset the Hour")
                }
                Image(systemName: state.roomDimmed ? "sun.max.fill" : "moon.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(state.roomDimmed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .frame(width: 40, height: 32)
                    .glassEffect(
                        state.roomDimmed ? .regular.tint(DialSwatch.bright.opacity(0.4)) : .regular,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                    .overlay(ImmediatePress { state.toggleRoomDim() })
                    .accessibilityLabel(state.roomDimmed ? "Restore lights" : "Dim the room")
            }
        case .power:
            HStack(spacing: 8) {
                ForEach(PowerMode.allCases) { mode in
                    let selected = state.desk.powerMode == mode
                    Text(mode.title)
                        .font(.caption.weight(.semibold))
                        .frame(height: 32)
                        .frame(maxWidth: .infinity)
                        .glassEffect(
                            selected ? .regular.tint(DialSwatch.output.opacity(0.4)) : .regular,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                        .overlay(ImmediatePress { state.desk.powerMode = mode })
                        .help(mode.summary)
                        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityLabel(mode.title)
                }
            }
        case nil:
            EmptyView()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            KnurlPip(
                tint: DialSwatch.tint(state.control, state: state),
                live: state.music.isPlaying || state.voice.isActive || state.desk.timer.running,
                size: 7
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(state.controlTitle.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                if state.control == .media, !state.music.line.isEmpty {
                    Text(state.music.line)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            // In front of the text, not behind it: as a .background the drag
            // surface only caught the empty gap, so grabbing the title did
            // nothing.
            .overlay(MoveBar())
            Spacer(minLength: 8)
            if state.control == .media {
                Image(systemName: "music.note")
                    .font(.caption.weight(.semibold))
                    .padding(8)
                    .glassEffect(.regular, in: Circle())
                    .help("Open Music")
                    .overlay(ImmediatePress(action: { state.revealMusic() }))
            }
            Image(systemName: "xmark")
                .font(.caption.weight(.semibold))
                .padding(8)
                .glassEffect(.regular, in: Circle())
                .overlay(ImmediatePress(action: { state.dismiss() }))
        }
        // The whole header is the grab area, the way a title bar is. The old
        // handle was an invisible 72pt strip nobody could find.
        .background(MoveBar())
        .overlay(alignment: .top) {
            Capsule()
                .fill(.secondary.opacity(0.35))
                .frame(width: 34, height: 4)
                .padding(.top, -6)
                .allowsHitTesting(false)
        }
        .accessibilityLabel("Drag to move the dial")
    }

    private var controlBlock: some View {
        VStack(spacing: 4) {
            if state.control == .media {
                // The header already names the track and artist, and the genre
                // is a chip below. Only the clock is new information here.
                if state.music.hasTrack, state.music.canSeek {
                    Text(mediaClock)
                        .font(.knurlNumeral(15))
                        .contentTransition(.numericText())
                        .foregroundStyle(.white.opacity(0.9))
                } else {
                    Text(controlSubtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            } else {
                Text(state.controlReadout)
                    .font(.knurlNumeral(19))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(.white.opacity(0.95))
                    .contentTransition(.numericText())
                Text(controlSubtitle.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.18), value: state.controlReadout)
    }

    private var mediaClock: String {
        let elapsed = state.music.displayedPlayhead() * state.music.duration
        return "\(DialMath.clock(elapsed))  −\(DialMath.clock(max(0, state.music.duration - elapsed)))"
    }

    private var controlSubtitle: String {
        switch state.control {
        case .volume:
            return state.outputName
        case .brightness:
            return "Built-in display"
        case .mic:
            if state.voice.isActive { return "Listening" }
            return state.inputName
        case .output:
            return state.outputKind
        case .media:
            if let message = state.music.message, !state.music.hasTrack { return message }
            return state.music.cardArtist
        }
    }

    @ViewBuilder
    private var talkBar: some View {
        if state.control == .mic {
            VStack(spacing: 8) {
                Text("→ \(state.harnessName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .overlay(ImmediatePress(action: { state.jumpToHarness() }))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Words land in \(state.harnessName)")
                if state.voice.isActive || !state.voice.preview.isEmpty || !state.voice.lastTranscript.isEmpty {
                    Text(flowLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity)
                }
                HStack(spacing: 8) {
                    Image(systemName: state.voice.isActive ? "waveform" : "mic.fill")
                        .symbolEffect(.variableColor.iterative, isActive: state.voice.isActive)
                    Text(state.voice.isActive ? "Release to paste" : "Hold Flow  ⌃⌥M")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.white.opacity(0.95))
                .glassEffect(
                    .regular.tint(DialSwatch.mic.opacity(state.voice.isActive ? 0.55 : 0.24)),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(
                            DialSwatch.mic.opacity(state.voice.isActive ? 0.8 : 0.25),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: DialSwatch.mic.opacity(state.voice.isActive ? 0.45 : 0),
                    radius: 16,
                    y: 3
                )
                .overlay(
                    ImmediateHold(
                        down: { state.beginTalk() },
                        up: { state.endTalk() }
                    )
                )
                HStack(spacing: 8) {
                    if state.voice.isActive {
                        Text("Cancel")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassEffect(.regular, in: Capsule())
                            .overlay(ImmediatePress(action: { state.cancelTalk() }))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel("Cancel Flow")
                    } else if !state.voice.lastTranscript.isEmpty {
                        Text("Resend")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassEffect(.regular, in: Capsule())
                            .overlay(ImmediatePress(action: { state.resendTalk() }))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel("Resend last Flow")
                    }
                }
                if let message = state.voice.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var toolFlowStrip: some View {
        HStack(spacing: 8) {
            Text(flowLine)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.head)
            Text("→ \(state.harnessName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .overlay(ImmediatePress(action: { state.jumpToHarness() }))
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Jump to \(state.harnessName)")
            Spacer(minLength: 0)
            Text("Cancel")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: Capsule())
                .overlay(ImmediatePress(action: { state.cancelTalk() }))
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Cancel Flow")
            Text("Release")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular.tint(DialSwatch.mic.opacity(0.4)), in: Capsule())
                .overlay(ImmediatePress(action: { state.endTalk() }))
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Stop and paste")
        }
    }

    private var flowLine: String {
        if !state.voice.preview.isEmpty { return state.voice.preview }
        if state.voice.isActive { return "Listening…" }
        if !state.voice.lastTranscript.isEmpty { return state.voice.lastTranscript }
        return ""
    }

    /// Three tiers, so the eye lands on play first: mode toggles are small and
    /// only carry colour when they are on, skip is medium, play is primary.
    private var transport: some View {
        HStack(spacing: 8) {
            if state.control == .media {
                transportButton("shuffle", tier: .toggle, selected: state.music.shuffleOn) {
                    state.toggleShuffle()
                }
            }
            transportButton("backward.fill", tier: .secondary) {
                state.skip(-1)
            }
            Image(systemName: state.music.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 17, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 88, height: 46)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    DialSwatch.stable(state.control),
                                    DialSwatch.stable(state.control).opacity(0.72),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(.white.opacity(0.35))
                        .frame(height: 1)
                        .padding(.horizontal, 12)
                        .blendMode(.plusLighter)
                }
                .shadow(color: DialSwatch.stable(state.control).opacity(0.5), radius: 14, y: 4)
                .overlay(ImmediatePress(action: { state.collapsedPlay() }))
            transportButton("forward.fill", tier: .secondary) {
                state.skip(1)
            }
            if state.control == .media {
                transportButton(
                    state.music.repeatMode.symbol,
                    tier: .toggle,
                    selected: state.music.repeatMode != .off
                ) {
                    state.cycleRepeat()
                }
            }
        }
    }

    private enum TransportTier {
        case secondary
        case toggle

        var size: CGSize {
            switch self {
            case .secondary: CGSize(width: 48, height: 40)
            case .toggle: CGSize(width: 38, height: 34)
            }
        }

        var glyph: CGFloat {
            switch self {
            case .secondary: 13
            case .toggle: 11
            }
        }
    }

    private func transportButton(
        _ symbol: String,
        tier: TransportTier,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: tier.glyph, weight: .semibold))
            // shuffle and repeat ship multicolour variants; without this the
            // off state renders red and reads as an error.
            .symbolRenderingMode(.monochrome)
            .frame(width: tier.size.width, height: tier.size.height)
            .foregroundStyle(
                selected
                    ? AnyShapeStyle(DialSwatch.stable(state.control))
                    : AnyShapeStyle(Color.white.opacity(0.6))
            )
            .glassEffect(
                selected ? .regular.tint(DialSwatch.stable(state.control).opacity(0.34)) : .regular,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        selected ? DialSwatch.stable(state.control).opacity(0.55) : .clear,
                        lineWidth: 1
                    )
            }
            .overlay(ImmediatePress(action: action))
    }

    private var roomSatellites: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(DialMode.allCases.enumerated()), id: \.element.id) { index, mode in
                    satellite(mode, number: index + 1)
                }
            }
        }
    }

    private func satellite(_ mode: DialMode, number: Int) -> some View {
        let selected = state.control == mode
        let tint = DialSwatch.tint(mode, state: state)
        return VStack(spacing: 4) {
            Image(systemName: satelliteSymbol(mode))
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.bounce, value: selected)
                .foregroundStyle(tint)
            Text(satelliteLabel(mode))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(selected ? 0.95 : 0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // A hairline of the face's own level. Five identical chips could
            // not tell you that Volume was at 12% without being clicked.
            KnurlMeter(
                progress: satelliteProgress(mode),
                tint: selected ? tint : tint.opacity(0.5),
                height: 2.5,
                showsTrack: false
            )
            .padding(.horizontal, 8)
        }
        .help("\(mode.title) · press \(number)")
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .glassEffect(
            selected
                ? .regular.tint(tint.opacity(0.45)).interactive()
                : .regular.tint(tint.opacity(0.10)).interactive(),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? tint.opacity(0.65) : .clear, lineWidth: 1)
        }
        .shadow(color: selected ? tint.opacity(0.4) : .clear, radius: 10, y: 2)
        .modifier(SelectedFaceGlass(active: selected, namespace: faces))
        .overlay(
            ImmediatePress {
                if selected {
                    state.confirmDial()
                } else {
                    state.selectControl(mode)
                }
            }
        )
    }

    private func satelliteProgress(_ mode: DialMode) -> Double {
        switch mode {
        case .volume: state.volumeProgress
        case .brightness: Double(state.brightnessPercent) / 100
        case .mic: Double(state.micPercent) / 100
        case .output: state.outputProgress
        case .media: state.music.displayedPlayhead()
        }
    }

    private func satelliteSymbol(_ mode: DialMode) -> String {
        switch mode {
        case .volume: state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .brightness: "sun.max.fill"
        case .mic:
            if state.voice.isActive { "waveform" }
            else if state.isMicMuted { "mic.slash.fill" }
            else { "mic.fill" }
        case .output: "hifispeaker.fill"
        case .media: state.music.isPlaying ? "pause.fill" : "play.fill"
        }
    }

    @ViewBuilder
    private var librarySources: some View {
        if state.control == .media {
            MusicLibraryStrip(state: state, compact: true)
        }
    }

    @ViewBuilder
    private var inputRoster: some View {
        if state.control == .mic, !state.inputDevices.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(state.inputDevices) { device in
                        let selected = device.uid == state.inputUID
                        HStack(spacing: 6) {
                            Image(systemName: device.transport.symbol)
                                .font(.system(size: 11, weight: .semibold))
                            Text(device.name)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .glassEffect(
                            selected
                                ? .regular.tint(DialSwatch.mic.opacity(0.36))
                                : .regular,
                            in: Capsule()
                        )
                        .overlay(ImmediatePress { state.selectInput(device) })
                        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityLabel(device.name)
                    }
                }
            }
            .frame(height: 36)
        }
    }

    @ViewBuilder
    private var outputRoster: some View {
        if state.control == .output {
            OutputDestinationRail(state: state, compact: true)
        }
    }

    private var mediaChipLabel: String {
        let title = state.music.title
        if !title.isEmpty { return title }
        return "Music"
    }

    private func satelliteLabel(_ mode: DialMode) -> String {
        switch mode {
        case .volume: state.isMuted ? "Muted" : "\(state.volumePercent)"
        case .brightness: "\(state.brightnessPercent)"
        case .mic: state.voice.isActive ? "Flow" : (state.isMicMuted ? "Muted" : "Mic")
        case .output: state.outputKind
        case .media: mediaChipLabel
        }
    }
}

/// The HUD's crown.
///
/// This used to be a second, hand-maintained copy of the dial — its own
/// bezel, its own tick ring, its own needle, drifting from the Hub's version
/// every time either changed. It is now the same `DeskCrown`, forced to the
/// graphite skin because the HUD floats over your work, with cover art handed
/// in for Media.
private struct CrownDial: View {
    @Bindable var state: DialState
    private let size: CGFloat = 252

    var body: some View {
        DeskCrown(
            progress: liveProgress,
            tint: DialSwatch.tint(state.control, state: state),
            symbol: state.control.symbol,
            readout: readout,
            caption: state.controlTitle,
            ticks: state.control == .output ? max(state.outputDevices.count, 2) : 11,
            size: size,
            lively: state.desk.allowsDecorativeMotion,
            metal: .graphite,
            artwork: artwork,
            levels: state.control == .mic && state.voice.isActive ? state.voice.levels : nil,
            pulsing: (state.control == .media && state.music.isPlaying)
                || (state.control == .mic && state.voice.isActive),
            onTurn: { state.applyControl($0, settleOutput: false) },
            onConfirm: { state.confirmDial() },
            onEnded: { if state.control == .output { state.finishOutputTurn() } }
        )
    }

    private var liveProgress: Double {
        if state.control == .media {
            return state.music.canSeek ? state.music.displayedPlayhead() : 0
        }
        return state.usesRingGauge ? state.controlProgress : max(state.controlProgress, 0.12)
    }

    private var readout: String {
        if state.control == .media, state.music.canSeek {
            let elapsed = liveProgress * state.music.duration
            return "\(DialMath.clock(elapsed))  −\(DialMath.clock(max(0, state.music.duration - elapsed)))"
        }
        return state.controlReadout
    }

    private var artwork: Image? {
        guard state.control == .media, let cover = state.music.cover else { return nil }
        return Image(nsImage: cover)
    }
}

/// The parked pill's dial. A 52-point crown has room for a bezel, a ring and
/// a glyph and nothing else — so it drops the ticks rather than drawing them
/// at a size where they become noise.
private struct MiniDial: View {
    @Bindable var state: DialState

    var body: some View {
        let tint = DialSwatch.tint(state.control, state: state)
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [.white.opacity(0.18), .white.opacity(0.03), .white.opacity(0.14), .white.opacity(0.18)],
                        center: .center,
                        angle: .degrees(-60)
                    )
                )
            Circle().fill(.black.opacity(0.82)).padding(2)
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.black.opacity(0.5), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .padding(6)
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * (state.usesRingGauge ? state.controlProgress : 0.6))
                .stroke(tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .padding(6)
                .rotationEffect(.degrees(135))
                .shadow(color: tint.opacity(0.6), radius: 4)
            Image(systemName: state.control.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 52, height: 52)
    }
}

@MainActor
enum DialSwatch {
    static let bright = Color(red: 1.0, green: 0.78, blue: 0.32)
    static let mic = Color(red: 0.98, green: 0.55, blue: 0.42)
    static let output = Color(red: 0.42, green: 0.86, blue: 0.78)
    static let media = Color(red: 0.96, green: 0.40, blue: 0.52)

    static func volume(_ state: DialState) -> Color {
        color(progress: state.volumeProgress, muted: state.isMuted)
    }

    /// A fixed sample of a face's hue, for controls. The ring shows progress
    /// through its length; buttons must not change colour as a track plays.
    static func stable(_ mode: DialMode) -> Color {
        let rgb = DialTint.rgb(progress: 0.6, muted: false, mode: mode)
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    static func tint(_ mode: DialMode, state: DialState) -> Color {
        let rgb = DialTint.rgb(
            progress: state.controlProgress,
            muted: (mode == .volume && state.isMuted) || (mode == .mic && state.isMicMuted),
            mode: mode
        )
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    static func color(progress: Double, muted: Bool) -> Color {
        let rgb = DialTint.rgb(progress: progress, muted: muted, mode: .volume)
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
}

private struct MoveBar: NSViewRepresentable {
    func makeNSView(context: Context) -> MoveBarView { MoveBarView() }
    func updateNSView(_ view: MoveBarView, context: Context) {}
}

final class MoveBarView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }
}


/// The crown for whichever tool is active. Turn to set, click to run.
private struct ToolCrown: View {
    @Bindable var state: DialState

    var body: some View {
        DeskCrown(
            progress: state.toolProgress,
            tint: state.activeTool?.tint ?? DialSwatch.bright,
            symbol: state.toolSymbol,
            readout: state.toolReadout,
            caption: state.toolCaption,
            ticks: 10,
            size: 252,
            lively: state.desk.allowsDecorativeMotion,
            metal: .graphite,
            onTurn: { state.turnTool($0) },
            onConfirm: { state.confirmTool() }
        )
        .frame(maxWidth: .infinity)
    }
}
