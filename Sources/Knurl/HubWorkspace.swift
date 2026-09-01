import KnurlCore
import SwiftUI

struct HubWorkspace: View {
    @Bindable var state: DialState

    var body: some View {
        HubPageScroll {
            Text("Workspace")
                .font(.largeTitle.weight(.semibold))
            Text("Arrange the desk. Not a screenshot.")
                .font(.title3)
                .foregroundStyle(.secondary)

            if !state.desk.windows.enabled {
                HubSection(title: "Window manager") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Off until you ask. Knurl then uses Accessibility to move windows you choose — never Screen Recording.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HubGlassButton(title: "Enable Window Manager", symbol: "rectangle.split.2x2") {
                            state.desk.windows.setEnabled(true)
                        }
                    }
                }
            } else if !state.desk.windows.trusted {
                HubSection(title: "Accessibility") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(state.desk.windows.status ?? "Knurl needs Accessibility to move windows.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HubGlassButton(title: "Open System Settings", symbol: "gearshape") {
                            state.desk.windows.openAccessibilitySettings()
                        }
                    }
                }
            } else {
                canvases
                HubDivider()
                presets
                HubDivider()
                snaps
            }
        }
        .onAppear {
            if state.desk.windows.enabled {
                state.desk.windows.refresh()
            }
        }
    }

    private var canvases: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(state.desk.windows.displays) { display in
                HubSection(
                    title: display.name,
                    accessory: "\(state.desk.windows.windows.filter { $0.displayID == display.id }.count) windows"
                ) {
                    WorkspaceCanvas(
                        display: display,
                        windows: state.desk.windows.windows.filter { $0.displayID == display.id },
                        selectedID: state.desk.windows.selectedID,
                        onSelect: { state.desk.windows.selectedID = $0 },
                        onMove: { id, frame in
                            state.desk.windows.move(id, to: frame)
                        }
                    )
                    HubGlassButton(title: "Move selected here", symbol: "display") {
                        state.desk.windows.moveSelected(to: display)
                    }
                }
            }
        }
    }

    private var presets: some View {
        HubSection(title: "Presets") {
            FlowLayout {
                ForEach(WorkspacePreset.allCases) { preset in
                    HubGlassButton(
                        title: preset.title,
                        selected: state.desk.windows.lastPreset == preset
                    ) {
                        state.desk.windows.apply(preset)
                        state.desk.noteWorkspace(preset)
                    }
                    .help(preset.summary)
                }
                HubGlassButton(title: "Restore", symbol: "arrow.uturn.backward") {
                    state.desk.windows.restore()
                }
            }
        }
    }

    private var snaps: some View {
        HubSection(title: "Snap") {
            FlowLayout {
                ForEach(SnapZone.allCases) { zone in
                    HubGlassButton(title: zone.title) {
                        state.desk.windows.snap(zone)
                    }
                }
            }
        }
    }
}

struct WorkspaceCanvas: View {
    var display: DeskDisplay
    var windows: [DeskWindow]
    var selectedID: String?
    var onSelect: (String) -> Void
    var onMove: (String, CGRect) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(0.35))
                ForEach(windows) { window in
                    let rect = WorkspaceMath.canvasRect(
                        window.frame,
                        in: display.visible,
                        canvas: geometry.size
                    )
                    windowTile(window, rect: rect, canvas: geometry.size)
                }
            }
        }
        .aspectRatio(max(display.visible.width / max(display.visible.height, 1), 1.4), contentMode: .fit)
        .frame(maxHeight: 220)
        .accessibilityLabel("\(display.name) canvas")
    }

    private func windowTile(_ window: DeskWindow, rect: CGRect, canvas: CGSize) -> some View {
        let selected = window.id == selectedID
        return VStack(alignment: .leading, spacing: 2) {
            Text(window.appName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
            Text(window.title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .frame(width: max(rect.width, 36), height: max(rect.height, 28), alignment: .topLeading)
        .background(.background.opacity(0.92), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1)
        )
        .offset(x: rect.minX, y: rect.minY)
        .gesture(
            DragGesture()
                .onChanged { value in
                    onSelect(window.id)
                    let origin = WorkspaceMath.screenPoint(
                        from: CGPoint(x: rect.minX + value.translation.width, y: rect.minY + value.translation.height),
                        visible: display.visible,
                        canvasSize: canvas
                    )
                    var frame = window.frame
                    frame.origin = origin
                    onMove(window.id, frame)
                }
        )
        .overlay(ImmediatePress(action: { onSelect(window.id) }))
    }
}

struct FlowLayout<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
