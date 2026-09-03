import AppKit
import KnurlCore
import SwiftUI

// MARK: - Workspace
//
// A scale model of your displays. The old canvas drew grey rectangles with a
// label; this one draws the actual app icon, the actual window proportions,
// and a live snap grid you drop onto. The point is that the map is the
// control — you should not have to read a list of preset names to understand
// what "Build" is going to do to your screen.

struct HubWorkspace: View {
    @Bindable var state: DialState
    @State private var hoveredZone: SnapZone?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var catalog: WindowCatalog { state.desk.windows }

    private var live: KnurlLiveliness {
        KnurlLiveliness(reduceMotion: reduceMotion, powerAllows: state.desk.allowsDecorativeMotion)
    }

    var body: some View {
        Group {
            if !catalog.enabled {
                gate(
                    title: "Window Manager is off",
                    detail: "Turn it on and Knurl can move the windows you pick. That is the first and only moment it asks for Accessibility — never Screen Recording, never keystrokes.",
                    symbol: "rectangle.split.2x2",
                    action: "Enable Window Manager"
                ) {
                    catalog.setEnabled(true)
                }
            } else if !catalog.trusted {
                gate(
                    title: "Accessibility needed",
                    detail: catalog.status ?? "Knurl needs Accessibility permission before it can move a window.",
                    symbol: "lock.shield",
                    action: "Open System Settings"
                ) {
                    catalog.openAccessibilitySettings()
                }
            } else {
                board
            }
        }
        .animation(live.motion(KnurlMotion.heavy), value: catalog.lastPreset)
        .animation(live.motion(), value: catalog.selectedID)
        .onAppear { if catalog.enabled { catalog.refresh() } }
    }

    // MARK: Board

    private var board: some View {
        HubPageScroll {
            HubHallHeader(
                title: "Workspace",
                whisper: whisper
            ) {
                HStack(spacing: KnurlSpace.tight) {
                    HubGlassButton(title: "Refresh", symbol: "arrow.clockwise") {
                        catalog.refresh()
                    }
                    HubGlassButton(title: "Restore", symbol: "arrow.uturn.backward") {
                        catalog.restore()
                    }
                }
            }

            maps
            layouts
            snapGrid
            windowList
        }
    }

    private var whisper: String {
        let count = catalog.windows.count
        let preset = catalog.lastPreset?.title ?? "Free"
        return "\(count) window\(count == 1 ? "" : "s") across \(catalog.displays.count) display\(catalog.displays.count == 1 ? "" : "s") · \(preset)"
    }

    // MARK: The maps

    private var maps: some View {
        VStack(alignment: .leading, spacing: KnurlSpace.room) {
            ForEach(catalog.displays) { display in
                let windows = catalog.windows.filter { $0.displayID == display.id }
                HubSection(
                    title: display.name,
                    accessory: "\(Int(display.frame.width))×\(Int(display.frame.height))"
                ) {
                    WorkspaceCanvas(
                        display: display,
                        windows: windows,
                        icon: { state.desk.tools.icon(for: $0) },
                        selectedID: catalog.selectedID,
                        hoveredZone: $hoveredZone,
                        lively: live.lively,
                        onSelect: { catalog.selectedID = $0 },
                        onMove: { catalog.move($0, to: $1) },
                        onDropZone: { id, zone in
                            catalog.selectedID = id
                            catalog.snap(zone)
                        }
                    )

                    HStack(spacing: KnurlSpace.tight) {
                        ForEach(WorkspacePreset.allCases) { preset in
                            HubGlassButton(
                                title: preset.title,
                                tint: KnurlPalette.calm,
                                selected: catalog.lastPreset == preset
                            ) {
                                catalog.apply(preset, on: display)
                                state.desk.noteWorkspace(preset)
                            }
                            .help(preset.summary)
                        }
                        Spacer(minLength: 0)
                        if catalog.displays.count > 1 {
                            HubGlassButton(title: "Move here", symbol: "display") {
                                catalog.moveSelected(to: display)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Layouts

    private var layouts: some View {
        HubSection(title: "Layouts", accessory: catalog.lastPreset?.title) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: KnurlSpace.snug), count: 3),
                spacing: KnurlSpace.snug
            ) {
                ForEach(WorkspacePreset.allCases) { preset in
                    PresetCard(
                        preset: preset,
                        selected: catalog.lastPreset == preset,
                        tint: KnurlPalette.calm
                    ) {
                        catalog.apply(preset)
                        state.desk.noteWorkspace(preset)
                    }
                }
            }
        }
    }

    // MARK: Snap grid
    //
    // Thirteen zones as a picture instead of thirteen chips reading "⅓ Left".
    // A snap target is a shape; naming it was always the workaround.

    private var snapGrid: some View {
        HubSection(
            title: "Snap",
            accessory: catalog.selected.map { "\($0.appName)" }
        ) {
            HStack(spacing: KnurlSpace.snug) {
                ForEach(SnapZone.allCases) { zone in
                    SnapChip(zone: zone, tint: KnurlPalette.calm) {
                        catalog.snap(zone)
                    }
                }
            }
        }
    }

    // MARK: Window list

    private var windowList: some View {
        HubSection(title: "Windows", accessory: "\(catalog.windows.count)") {
            if catalog.windows.isEmpty {
                HubEmpty(
                    title: "No windows found",
                    detail: "Knurl only sees standard windows of regular apps. Open something and hit Refresh."
                )
            } else {
                VStack(spacing: 3) {
                    ForEach(catalog.windows) { window in
                        WindowRow(
                            window: window,
                            icon: state.desk.tools.icon(for: window.pid),
                            selected: window.id == catalog.selectedID,
                            onSelect: { catalog.selectedID = window.id }
                        )
                    }
                }
            }
        }
    }

    // MARK: Gate

    private func gate(
        title: String,
        detail: String,
        symbol: String,
        action: String,
        run: @escaping () -> Void
    ) -> some View {
        VStack(spacing: KnurlSpace.room) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(KnurlPalette.inkSoft)
            VStack(spacing: KnurlSpace.snug) {
                Text(title)
                    .font(.knurlHall)
                    .foregroundStyle(KnurlPalette.ink)
                Text(detail)
                    .font(.knurlBody)
                    .foregroundStyle(KnurlPalette.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HubGlassButton(title: action, symbol: "arrow.right", tint: KnurlPalette.calm, selected: true, action: run)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(KnurlSpace.stage)
    }
}

// MARK: - The canvas

struct WorkspaceCanvas: View {
    var display: DeskDisplay
    var windows: [DeskWindow]
    var icon: (pid_t) -> NSImage?
    var selectedID: String?
    @Binding var hoveredZone: SnapZone?
    var lively: Bool
    var onSelect: (String) -> Void
    var onMove: (String, CGRect) -> Void
    var onDropZone: (String, SnapZone) -> Void

    @State private var dragging: String?

    /// The zones the drop overlay offers. Deliberately the six a person
    /// actually reaches for while dragging — the full thirteen are one row of
    /// chips below, where a precise choice belongs.
    private let dropZones: [SnapZone] = [.leftHalf, .maximize, .rightHalf, .topLeft, .center, .bottomRight]

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                screen
                if dragging != nil {
                    dropOverlay(canvas: geometry.size)
                        .transition(.opacity)
                }
                ForEach(windows) { window in
                    let rect = WorkspaceMath.canvasRect(
                        window.frame,
                        in: display.visible,
                        canvas: geometry.size
                    )
                    tile(window, rect: rect, canvas: geometry.size)
                }
                if windows.isEmpty {
                    Text("No windows on this display")
                        .font(.knurlLabel)
                        .foregroundStyle(KnurlPalette.inkFaint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .animation(lively ? KnurlMotion.snap : nil, value: dragging)
            .animation(lively ? KnurlMotion.snap : nil, value: hoveredZone)
        }
        .aspectRatio(display.visible.width / max(display.visible.height, 1), contentMode: .fit)
        .frame(maxHeight: 300)
        .accessibilityLabel("\(display.name), \(windows.count) windows")
    }

    /// The display itself: a dark glass panel in a bezel, with a menu-bar
    /// sliver at the top so the model reads as a Mac screen at a glance.
    private var screen: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: KnurlRadius.card, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [KnurlPalette.sunken, KnurlPalette.void],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Rectangle()
                .fill(KnurlPalette.hairline)
                .frame(height: 12)
                .mask {
                    RoundedRectangle(cornerRadius: KnurlRadius.card, style: .continuous)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: KnurlRadius.card, style: .continuous)
                .strokeBorder(KnurlPalette.hairlineStrong, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }

    private func dropOverlay(canvas: CGSize) -> some View {
        ForEach(dropZones) { zone in
            let target = WorkspaceMath.canvasRect(
                WorkspaceMath.snap(zone, in: display.visible),
                in: display.visible,
                canvas: canvas
            )
            let hot = hoveredZone == zone
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(KnurlPalette.calm.opacity(hot ? 0.28 : 0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            KnurlPalette.calm.opacity(hot ? 0.9 : 0.30),
                            style: StrokeStyle(lineWidth: hot ? 2 : 1, dash: hot ? [] : [4, 4])
                        )
                }
                .frame(width: max(target.width - 4, 8), height: max(target.height - 4, 8))
                .offset(x: target.minX + 2, y: target.minY + 2)
                .allowsHitTesting(false)
        }
    }

    private func tile(_ window: DeskWindow, rect: CGRect, canvas: CGSize) -> some View {
        let selected = window.id == selectedID
        let isDragging = dragging == window.id
        let appIcon = icon(window.pid)
        let compact = rect.width < 120 || rect.height < 64

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: compact ? 14 : 18, height: compact ? 14 : 18)
                }
                Text(window.appName)
                    .font(.system(size: compact ? 9 : 11, weight: .semibold))
                    .foregroundStyle(KnurlPalette.ink)
                    .lineLimit(1)
            }
            if !compact {
                Text(window.title)
                    .font(.system(size: 9))
                    .foregroundStyle(KnurlPalette.inkFaint)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(compact ? 5 : 8)
        .frame(width: max(rect.width, 40), height: max(rect.height, 30), alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(KnurlPalette.raised.opacity(isDragging ? 0.98 : 0.92))
            // Traffic lights. Three dots is all it takes for a rectangle to
            // stop being a rectangle and start being a window.
            if !compact {
                HStack(spacing: 3) {
                    Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34))
                    Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.20))
                    Circle().fill(Color(red: 0.24, green: 0.79, blue: 0.29))
                }
                .frame(width: 20, height: 5)
                .opacity(0.75)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(6)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    selected ? KnurlPalette.calm : KnurlPalette.hairline,
                    lineWidth: selected ? 2 : 1
                )
        }
        .shadow(color: .black.opacity(isDragging ? 0.6 : 0.35), radius: isDragging ? 18 : 8, y: isDragging ? 8 : 3)
        .scaleEffect(isDragging ? 1.04 : 1)
        .zIndex(selected || isDragging ? 1 : 0)
        .offset(x: rect.minX, y: rect.minY)
        .onTapGesture { onSelect(window.id) }
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    if dragging != window.id {
                        dragging = window.id
                        onSelect(window.id)
                    }
                    let point = CGPoint(
                        x: rect.midX + value.translation.width,
                        y: rect.midY + value.translation.height
                    )
                    hoveredZone = zone(at: point, canvas: canvas)
                    let origin = WorkspaceMath.screenPoint(
                        from: CGPoint(
                            x: rect.minX + value.translation.width,
                            y: rect.minY + value.translation.height
                        ),
                        visible: display.visible,
                        canvasSize: canvas
                    )
                    var frame = window.frame
                    frame.origin = origin
                    onMove(window.id, frame)
                }
                .onEnded { _ in
                    // A drop inside a zone snaps; a drop anywhere else keeps
                    // the free position the drag already applied.
                    if let hoveredZone {
                        onDropZone(window.id, hoveredZone)
                    }
                    dragging = nil
                    hoveredZone = nil
                }
        )
        .accessibilityLabel("\(window.appName), \(window.title)")
    }

    /// Which drop zone a canvas point falls in, nearest-centre first so
    /// overlapping zones (centre inside maximize) resolve predictably.
    private func zone(at point: CGPoint, canvas: CGSize) -> SnapZone? {
        var best: (SnapZone, CGFloat)?
        for zone in dropZones {
            let rect = WorkspaceMath.canvasRect(
                WorkspaceMath.snap(zone, in: display.visible),
                in: display.visible,
                canvas: canvas
            )
            guard rect.contains(point) else { continue }
            let dx = point.x - rect.midX
            let dy = point.y - rect.midY
            let distance = sqrt(dx * dx + dy * dy)
            if best == nil || distance < best!.1 {
                best = (zone, distance)
            }
        }
        return best?.0
    }
}

// MARK: - Preset card
//
// Each preset draws its own layout. Six named buttons required you to
// remember what "Review" meant; six pictures do not.

struct PresetCard: View {
    var preset: WorkspacePreset
    var selected: Bool
    var tint: Color
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: KnurlSpace.snug) {
            diagram
                .frame(height: 54)
            Text(preset.title)
                .font(.knurlBody.weight(.semibold))
                .foregroundStyle(KnurlPalette.ink)
            Text(preset.summary)
                .font(.knurlEyebrow.weight(.regular))
                .foregroundStyle(KnurlPalette.inkFaint)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(KnurlSpace.step)
        .knurlSurface(
            selected || hovering ? .raised : .card,
            tint: selected ? tint : nil,
            glow: selected ? 0.35 : 0
        )
        .onHover { hovering = $0 }
        .animation(KnurlMotion.snap, value: hovering)
        .overlay(ImmediatePress(action: action))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(preset.title). \(preset.summary)")
    }

    /// The preset's frames, drawn against a unit screen. This asks
    /// WorkspaceMath for the same numbers it will apply to the real windows,
    /// so the picture cannot drift away from the behaviour.
    private var diagram: some View {
        GeometryReader { geometry in
            let unit = CGRect(x: 0, y: 0, width: geometry.size.width, height: geometry.size.height)
            let frames = WorkspaceMath.frames(for: preset, visible: unit, count: 3)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(KnurlPalette.sunken)
                ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                    if frame != .null {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(tint.opacity(selected ? 0.85 - Double(index) * 0.22 : 0.36 - Double(index) * 0.09))
                            .frame(width: max(frame.width - 3, 2), height: max(frame.height - 3, 2))
                            // WorkspaceMath speaks AppKit, whose origin is the
                            // bottom-left; SwiftUI's is the top-left.
                            .offset(
                                x: frame.minX + 1.5,
                                y: geometry.size.height - frame.maxY + 1.5
                            )
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(KnurlPalette.hairline, lineWidth: 1)
            }
        }
    }
}

// MARK: - Snap chip

struct SnapChip: View {
    var zone: SnapZone
    var tint: Color
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geometry in
                let unit = CGRect(origin: .zero, size: geometry.size)
                let frame = WorkspaceMath.snap(zone, in: unit)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(KnurlPalette.sunken)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint.opacity(hovering ? 0.95 : 0.55))
                        .frame(width: max(frame.width - 2, 2), height: max(frame.height - 2, 2))
                        .offset(x: frame.minX + 1, y: geometry.size.height - frame.maxY + 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(KnurlPalette.hairline, lineWidth: 1)
                }
            }
            .frame(height: 30)
            Text(zone.title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(hovering ? KnurlPalette.ink : KnurlPalette.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, KnurlSpace.tight)
        .padding(.horizontal, 4)
        .background {
            RoundedRectangle(cornerRadius: KnurlRadius.chip, style: .continuous)
                .fill(hovering ? KnurlPalette.raised : .clear)
        }
        .onHover { hovering = $0 }
        .animation(KnurlMotion.snap, value: hovering)
        .overlay(ImmediatePress(action: action))
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Snap \(zone.title)")
    }
}

// MARK: - Window row

struct WindowRow: View {
    var window: DeskWindow
    var icon: NSImage?
    var selected: Bool
    var onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: KnurlSpace.snug) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            Text(window.appName)
                .font(.knurlBody.weight(.medium))
                .foregroundStyle(KnurlPalette.ink)
            Text(window.title)
                .font(.knurlEyebrow.weight(.regular))
                .foregroundStyle(KnurlPalette.inkFaint)
                .lineLimit(1)
            Spacer(minLength: KnurlSpace.snug)
            Text("\(Int(window.frame.width))×\(Int(window.frame.height))")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(KnurlPalette.inkFaint)
            if selected {
                KnurlPip(tint: KnurlPalette.calm, live: false, size: 6)
            }
        }
        .padding(.horizontal, KnurlSpace.snug + 2)
        .padding(.vertical, KnurlSpace.tight + 1)
        .background {
            RoundedRectangle(cornerRadius: KnurlRadius.chip, style: .continuous)
                .fill(selected || hovering ? KnurlPalette.raised : .clear)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .overlay(ImmediatePress(action: onSelect))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(window.appName), \(window.title)")
    }
}

// MARK: - Layout helper
//
// Kept because other pages still wrap chips with it.

struct FlowLayout<Content: View>: View {
    var spacing: CGFloat = KnurlSpace.tight
    @ViewBuilder var content: () -> Content

    var body: some View {
        WrapLayout(spacing: spacing) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WrapLayout: Layout {
    var spacing: CGFloat = KnurlSpace.tight

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
