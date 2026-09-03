import AppKit
import Darwin
import Foundation
import IOKit.pwr_mgt
import KnurlCore
import Observation

// The machine-reading primitives — `MachineVitals`, `CPUSampler`,
// `NetworkSampler`, `DeskFormat`, `KeepAwakeAssertion` — live in KnurlCore.
// They touch no AppKit and no app state, so putting them there is what makes
// them testable: a test target cannot import an executable target.

// MARK: - Removable volumes

struct DeskVolume: Identifiable, Equatable {
    var id: String { url.path }
    var url: URL
    var name: String
    var free: Int64
    var total: Int64
    var ejectable: Bool

    var detail: String {
        guard total > 0 else { return ejectable ? "Removable" : "Volume" }
        return "\(DeskFormat.bytes(UInt64(max(0, free)))) free of \(DeskFormat.bytes(UInt64(total)))"
    }

    var progress: Double {
        total == 0 ? 0 : 1 - Double(free) / Double(total)
    }
}

// MARK: - Clipboard shelf

struct ShelfItem: Identifiable, Equatable {
    var id = UUID()
    var text: String
    var at: Date

    var preview: String {
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count > 120 ? String(flat.prefix(119)) + "…" : flat
    }

    var lineCount: Int { text.split(separator: "\n", omittingEmptySubsequences: false).count }
}

// MARK: - Toolbox
//
// The desk capabilities that are not one of the five faces: keep the Mac
// awake, watch the machine, hold the last few clipboard entries, clear the
// room, eject a disk. Each one is a real system call, not a placeholder.

@MainActor
@Observable
final class DeskToolbox {
    // Keep awake
    private(set) var awake = false
    private(set) var awakeUntil: Date?
    private var assertion: KeepAwakeAssertion?

    // Vitals
    private(set) var vitals = MachineVitals()
    private(set) var cpuHistory: [Double] = []
    private(set) var memoryHistory: [Double] = []
    private(set) var networkHistory: [Double] = []

    // Clipboard shelf
    var shelfEnabled = Preferences.clipboardShelf {
        didSet {
            Preferences.clipboardShelf = shelfEnabled
            if !shelfEnabled { shelf.removeAll() }
            shelfChangeCount = NSPasteboard.general.changeCount
        }
    }
    private(set) var shelf: [ShelfItem] = []
    private var shelfChangeCount = NSPasteboard.general.changeCount

    // Volumes
    private(set) var volumes: [DeskVolume] = []
    private(set) var message: String?

    private var cpuSampler = CPUSampler()
    private var networkSampler = NetworkSampler()
    private var pump: Task<Void, Never>?
    private var slowTick = 0

    private let historyLength = 60
    private let shelfLimit = 12

    func start() {
        guard pump == nil else { return }
        _ = cpuSampler.sample()
        _ = networkSampler.sample()
        refreshVolumes()
        refreshApps()
        pump = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.tick()
            }
        }
    }

    func stop() {
        pump?.cancel()
        pump = nil
    }

    private func tick() {
        // The clipboard has to be watched at 1 Hz to feel instant. Vitals do
        // not: a CPU readout that steps every two seconds reads the same to a
        // person and halves how often the pages that show it are invalidated.
        captureClipboardIfNeeded()
        expireAwakeIfNeeded()
        slowTick += 1
        if slowTick % 2 == 0 { sampleVitals() }
        if slowTick % 5 == 0 { refreshApps() }
        if slowTick % 10 == 0 {
            refreshVolumes()
            iconCache = iconCache.filter { pid, _ in
                NSRunningApplication(processIdentifier: pid) != nil
            }
        }
    }

    // MARK: Vitals

    private func sampleVitals() {
        var next = vitals
        let cpu = cpuSampler.sample()
        next.cpu = cpu.overall
        next.cores = cpu.cores

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let memoryResult = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if memoryResult == KERN_SUCCESS {
            let page = UInt64(sysconf(_SC_PAGESIZE))
            // What macOS calls "memory used": resident, wired and compressed.
            // Free plus inactive is available to the system, not consumed.
            let used = UInt64(stats.active_count)
                + UInt64(stats.wire_count)
                + UInt64(stats.compressor_page_count)
            next.memoryUsed = used * page
            next.memoryTotal = ProcessInfo.processInfo.physicalMemory
        }

        if let values = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        ) {
            next.diskFree = values.volumeAvailableCapacityForImportantUsage ?? 0
            next.diskTotal = Int64(values.volumeTotalCapacity ?? 0)
        }

        let network = networkSampler.sample()
        next.networkIn = network.0
        next.networkOut = network.1
        next.uptime = ProcessInfo.processInfo.systemUptime

        vitals = next
        push(&cpuHistory, next.cpu)
        push(&memoryHistory, next.memoryProgress)
        // Network has no ceiling, so the sparkline is scaled against a rolling
        // 8 MB/s reference rather than a true maximum.
        push(&networkHistory, min(1, (next.networkIn + next.networkOut) / (8 * 1024 * 1024)))
    }

    private func push(_ series: inout [Double], _ value: Double) {
        series.append(value)
        if series.count > historyLength {
            series.removeFirst(series.count - historyLength)
        }
    }

    // MARK: Keep awake

    /// Holds a power-management assertion so the display does not idle-sleep.
    /// This is the same mechanism `caffeinate` uses; releasing the assertion
    /// hands the decision straight back to the system.
    @discardableResult
    func setAwake(_ on: Bool, minutes: Int? = nil) -> Bool {
        if on {
            if awake { releaseAssertion() }
            guard let held = KeepAwakeAssertion() else {
                message = "macOS refused the keep-awake assertion."
                return false
            }
            assertion = held
            awake = true
            awakeUntil = minutes.map { Date().addingTimeInterval(TimeInterval($0) * 60) }
            message = nil
            return true
        }
        releaseAssertion()
        return true
    }

    func toggleAwake(minutes: Int? = nil) {
        setAwake(!awake, minutes: minutes)
    }

    var awakeLabel: String {
        guard awake else { return "Off" }
        guard let awakeUntil else { return "On" }
        let remaining = max(0, awakeUntil.timeIntervalSinceNow)
        return DialMath.sessionClock(remaining)
    }

    private func releaseAssertion() {
        assertion = nil
        awake = false
        awakeUntil = nil
    }

    private func expireAwakeIfNeeded() {
        guard awake, let awakeUntil, awakeUntil <= Date() else { return }
        releaseAssertion()
    }

    // MARK: Clipboard shelf
    //
    // Opt-in and memory only. Nothing is written to disk and nothing leaves
    // the process — the shelf exists because Knurl Flow already lands text on
    // the clipboard, and losing the last paste to the next copy is the most
    // common way that flow breaks.

    private func captureClipboardIfNeeded() {
        guard shelfEnabled else { return }
        let board = NSPasteboard.general
        guard board.changeCount != shelfChangeCount else { return }
        shelfChangeCount = board.changeCount
        guard let text = board.string(forType: .string) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        shelf.removeAll { $0.text == text }
        shelf.insert(ShelfItem(text: text, at: Date()), at: 0)
        if shelf.count > shelfLimit {
            shelf = Array(shelf.prefix(shelfLimit))
        }
    }

    func copyToClipboard(_ item: ShelfItem) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(item.text, forType: .string)
        shelfChangeCount = board.changeCount
        if let index = shelf.firstIndex(of: item), index != 0 {
            shelf.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
        }
        message = "Copied."
    }

    func forget(_ item: ShelfItem) {
        shelf.removeAll { $0.id == item.id }
    }

    func clearShelf() {
        shelf.removeAll()
    }

    // MARK: The room

    /// Hides every other app. Public `NSWorkspace`, no Accessibility — this is
    /// the ⌥⌘H the Finder already offers, put on a tile.
    func clearTheRoom() {
        NSWorkspace.shared.hideOtherApplications()
        message = "Room cleared."
    }

    func showEverything() {
        NSApp.unhideAllApplications(nil)
        message = "Everything back."
    }

    // MARK: Volumes

    func refreshVolumes() {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsInternalKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
        ]
        let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []
        volumes = mounted.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let ejectable = (values.volumeIsEjectable ?? false) || (values.volumeIsRemovable ?? false)
            // The boot volume is already on the vitals tile; the interesting
            // rows here are the ones a person can physically unplug.
            guard ejectable || (values.volumeIsInternal == false) else { return nil }
            return DeskVolume(
                url: url,
                name: values.volumeName ?? url.lastPathComponent,
                free: Int64(values.volumeAvailableCapacity ?? 0),
                total: Int64(values.volumeTotalCapacity ?? 0),
                ejectable: ejectable
            )
        }
    }

    func eject(_ volume: DeskVolume) {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
            message = "Ejected \(volume.name)."
            refreshVolumes()
        } catch {
            message = "\(volume.name) is busy — \(error.localizedDescription)"
        }
    }

    // MARK: Running apps

    /// The regular apps with a Dock presence, front-most first. Used by the
    /// jump strip so the Hub can put you back in the editor without ⌘-tab.
    ///
    /// Stored rather than computed: as a computed property this walked every
    /// running process on the machine on every SwiftUI body evaluation, which
    /// on a page that also animates is dozens of full scans a second.
    private(set) var deskApps: [NSRunningApplication] = []

    func refreshApps() {
        let mine = ProcessInfo.processInfo.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        deskApps = NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular
                    && !$0.isTerminated
                    && $0.processIdentifier != mine
            }
            .sorted { lhs, rhs in
                if lhs.processIdentifier == front { return true }
                if rhs.processIdentifier == front { return false }
                return (lhs.localizedName ?? "") < (rhs.localizedName ?? "")
            }
    }

    func activate(_ app: NSRunningApplication) {
        app.activate(options: [.activateAllWindows])
    }

    /// App icons, kept by pid. `NSRunningApplication.icon` hits the icon
    /// services every call, and the workspace map asks for one per window per
    /// frame while a tile is being dragged.
    private var iconCache: [pid_t: NSImage] = [:]

    func icon(for pid: pid_t) -> NSImage? {
        if let cached = iconCache[pid] { return cached }
        guard let icon = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        iconCache[pid] = icon
        return icon
    }
}
