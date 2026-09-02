import KnurlCore
import SwiftUI

struct HubWorkspace: View {
    @Bindable var state: DialState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !state.desk.windows.enabled {
                offState
            } else if !state.desk.windows.trusted {
                untrustedState
            } else {
                board
            }
        }
        .animation(
            HubMotion.lively(
                reduceMotion: reduceMotion,
                allowed: state.desk.allowsDecorativeMotion
            ),
            value: state.desk.windows.lastPreset
        )
        .onAppear {
            if state.desk.windows.enabled {
                state.desk.windows.refresh()
            }
        }
    }

    private var board: some View {
        HubPageScroll {
            HubHallHeader(
                title: "Workspace",
                whisper: "Snap the room. Stay in the work."
            ) {
                Text(state.desk.windows.lastPreset?.title ?? "Free")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            canvases
            HubDivider()
            presets
            HubDivider()
            snaps
        }
    }

    private var offState: some View {
        ContentUnavailableView {
            Label("Window Manager is off", systemImage: "rectangle.split.2x2")
        } description: {
            Text("Turn it on and Knurl can snap the windows you pick. It asks for Accessibility then — never Screen Recording.")
        } actions: {
            Button("Enable Window Manager") {
                state.desk.windows.setEnabled(true)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var untrustedState: some View {
        ContentUnavailableView {
            Label("Accessibility needed", systemImage: "lock.shield")
        } description: {
            Text(state.desk.windows.status ?? "Knurl needs Accessibility permission before it can move windows.")
        } actions: {
            Button("Open System Settings") {
                state.desk.windows.openAccessibilitySettings()
            }
            .buttonStyle(.borderedProminent)
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
            GlassEffectContainer(spacing: 8) {
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
        .onTapGesture { onSelect(window.id) }
        .gesture(
            DragGesture(minimumDistance: 4)
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
    }
}

/// Wraps chips onto as many rows as the column needs. The previous version was
/// an HStack, so a narrow Hub squeezed every preset onto one line.
struct FlowLayout<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        WrapLayout(spacing: spacing) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(subviews: subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, widest), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, next > width {
                rows.append(row)
                row = Row()
                row.indices = [index]
                row.width = size.width
                row.height = size.height
            } else {
                row.indices.append(index)
                row.width = next
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
