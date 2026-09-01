import Foundation
import KnurlCore
import Observation

@MainActor
@Observable
final class DeskContext {
    var page: HubPage = .home
    var powerMode: PowerMode = Preferences.powerMode {
        didSet { Preferences.powerMode = powerMode }
    }
    private(set) var startedAt = Date()
    private(set) var receipts: [DeskReceipt] = []
    private(set) var sessions: [AgentSession] = []
    private(set) var workspaceFlash: String?
    private(set) var lastMusicTitle = ""
    private(set) var lastHarness = ""
    private(set) var flowUses = 0
    private(set) var lastFlowCharacters = 0

    let power = PowerWatch()
    let windows = WindowCatalog()

    var workingCount: Int { sessions.filter { $0.state == .working || $0.state == .starting }.count }
    var attention: [AgentSession] { sessions.filter(\.needsHuman) }
    var projectName: String { lastHarness.isEmpty ? "Mac" : lastHarness }
    var allowsDecorativeMotion: Bool { powerMode != .battery }

    func start() {
        startedAt = Date()
        record(.sessionStarted, "Flow session started")
        power.onChange = { [weak self] snapshot in
            self?.notePower(snapshot)
        }
        power.start()
        windows.refresh()
    }

    func noteHarness(_ name: String) {
        guard name != lastHarness, !name.isEmpty else { return }
        lastHarness = name
        record(.harnessChanged, "Harness \(name)")
    }

    func noteMusic(_ title: String) {
        guard title != lastMusicTitle, !title.isEmpty else { return }
        lastMusicTitle = title
        record(.musicChanged, title)
    }

    func noteFlowStart() {
        record(.flowStarted, "Knurl Flow started → \(lastHarness.isEmpty ? "frontmost app" : lastHarness)")
    }

    func noteFlowEnd(characters: Int) {
        flowUses += 1
        lastFlowCharacters = characters
        record(.flowEnded, "Knurl Flow \(characters) characters → \(lastHarness.isEmpty ? "frontmost app" : lastHarness)")
    }

    func noteWorkspace(_ preset: WorkspacePreset) {
        workspaceFlash = preset.title
        record(.workspaceApplied, "Workspace \(preset.title)")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if workspaceFlash == preset.title {
                workspaceFlash = nil
            }
        }
    }

    func jump(to session: AgentSession) {
        _ = session
    }

    func whisper(
        listening: Bool,
        destination: String,
        musicTitle: String?,
        now: Date = Date()
    ) -> NotchWhisper {
        NotchWhisper.pick(
            listening: listening,
            destination: destination,
            attention: attention.first?.provider.title,
            thermalException: power.snapshot.thermal.isException,
            batteryPercent: power.snapshot.percent,
            powerMode: powerMode.title,
            workspaceFlash: workspaceFlash,
            musicTitle: musicTitle,
            elapsed: DialMath.sessionClock(now.timeIntervalSince(startedAt))
        )
    }

    private func notePower(_ snapshot: PowerSnapshot) {
        if snapshot.thermal.isException {
            record(.thermal, "Thermal \(snapshot.thermal.title)")
        }
        if receipts.last(where: { $0.kind == .powerSnapshot })?.summary != snapshot.percentLabel {
            record(.powerSnapshot, "Battery \(snapshot.percentLabel) · \(snapshot.chargeLabel)")
        }
    }

    private func record(_ kind: SessionEventKind, _ summary: String) {
        receipts.insert(DeskReceipt(kind: kind, summary: summary), at: 0)
        if receipts.count > 80 {
            receipts = Array(receipts.prefix(80))
        }
    }
}
