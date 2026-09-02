import AppKit
import Foundation
import KnurlAgents
import Observation
import os

/// Orchestrates collection. Owns the store, the bridge, the activity monitor
/// and the adapters, and is the only place that decides when a session starts
/// or ends. Deliberately not part of `DialState`.
@MainActor
@Observable
final class AgentSessionManager {
    let store: SessionStore
    var consent: TelemetryConsent {
        didSet { AgentPreferences.consent = consent }
    }

    private let log = Logger(subsystem: "Knurl.Agent", category: "Manager")
    private let bridge = EventBridge()
    private let activity = ActivityMonitor()
    private let archive: SessionArchive

    /// Maps an agent's own session id onto ours, so repeated hook events for
    /// the same Cursor session land on one Knurl session.
    private var externalIDs: [String: UUID] = [:]
    /// The session a basic-integration agent is running under, keyed by agent.
    private var presenceSessions: [AgentKind: UUID] = [:]
    private var heartbeat: Task<Void, Never>?

    var bridgeIsRunning: Bool { bridge.isRunning }
    var bridgeError: String? { bridge.lastError }

    init() {
        let archive = SessionArchive(directory: SessionArchive.defaultDirectory())
        self.archive = archive
        self.store = SessionStore(archive: archive)
        self.consent = AgentPreferences.consent
    }

    func start() {
        Task { await store.load() }

        if consent.allows(.agentHook) {
            bridge.start { [weak self] payload in
                self?.receive(payload)
            }
        }
        if consent.allows(.frontmostApp) {
            activity.onSwitch = { [weak self] agent, _, name in
                self?.noteSwitch(agent: agent, appName: name)
            }
            activity.start()
        }
        // One heartbeat, shared, to settle idle clocks. Not a per-session poll.
        heartbeat = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                self?.store.settleIdle()
            }
        }
    }

    func stop() {
        heartbeat?.cancel()
        heartbeat = nil
        bridge.stop()
        activity.stop()
    }

    // MARK: - Hook events (deep integration)

    private func receive(_ payload: EventBridge.HookPayload) {
        guard consent.allows(.agentHook) else { return }
        guard let agent = Self.agent(named: payload.provider) else { return }
        guard let kind = Self.kind(named: payload.kind) else { return }

        // A hook can name a directory; refuse sealed ones outright.
        if let directory = payload.workingDirectory, RepositoryMonitor.isSealed(directory) {
            log.info("Ignored event from a sealed directory")
            return
        }

        let sessionID = resolveSession(for: payload, agent: agent, kind: kind)

        if kind == .sessionEnded {
            store.endSession(sessionID)
            externalIDs.removeValue(forKey: Self.key(payload.provider, payload.sessionID))
            return
        }

        var metadata: [String: String] = [:]
        if let tool = payload.tool { metadata["tool"] = tool }
        if let path = payload.path { metadata["path"] = path }

        store.apply(AgentEvent(
            sessionID: sessionID,
            kind: kind,
            source: .agentHook,
            summary: payload.summary ?? Self.defaultSummary(kind, payload: payload),
            metadata: metadata
        ))
    }

    private func resolveSession(
        for payload: EventBridge.HookPayload,
        agent: AgentKind,
        kind: AgentEventKind
    ) -> UUID {
        let key = Self.key(payload.provider, payload.sessionID)
        if let existing = externalIDs[key] { return existing }

        let repository = payload.workingDirectory.flatMap { RepositoryMonitor.repository(at: $0) }
        let session = store.startSession(
            agent: agent,
            project: payload.project ?? repository?.name,
            repository: payload.repository ?? repository?.root,
            workingDirectory: payload.workingDirectory,
            branch: payload.branch ?? repository?.branch
        )
        externalIDs[key] = session.id
        _ = kind
        return session.id
    }

    // MARK: - Frontmost app (basic integration)

    private func noteSwitch(agent: AgentKind?, appName: String) {
        // Every switch is a context switch for whatever session is live.
        for session in store.live {
            store.apply(AgentEvent(
                sessionID: session.id,
                kind: .contextSwitch,
                source: .frontmostApp,
                summary: "Switched to \(appName)"
            ))
        }

        guard let agent, consent.allows(.processActivity) else { return }
        // Deep-integration agents get their session from hooks; do not double up.
        guard agent.integration == .basic else { return }
        if presenceSessions[agent] == nil {
            let session = store.startSession(agent: agent)
            presenceSessions[agent] = session.id
        }
        if let id = presenceSessions[agent] {
            store.apply(AgentEvent(
                sessionID: id,
                kind: .userActivity,
                source: .frontmostApp,
                summary: "Working in \(appName)"
            ))
        }
    }

    // MARK: - Manual control

    func endSession(_ id: UUID) {
        store.endSession(id)
        presenceSessions = presenceSessions.filter { $0.value != id }
        externalIDs = externalIDs.filter { $0.value != id }
    }

    func pause(_ id: UUID) { store.pause(id) }
    func resume(_ id: UUID) { store.resume(id) }

    /// Reconciles a finished session against its repository so commits and
    /// reverts made during the session are reflected in the outcome.
    func reconcileGit(for id: UUID) {
        guard consent.allows(.gitActivity), let session = store.session(id) else { return }
        guard let root = session.repository, !RepositoryMonitor.isSealed(root) else { return }
        for commit in RepositoryMonitor.commits(in: root, since: session.startedAt) {
            store.apply(AgentEvent(
                sessionID: id,
                kind: .gitCommit,
                source: .gitActivity,
                summary: commit.subject,
                metadata: [
                    "hash": commit.hash,
                    "revert": RepositoryMonitor.isRevert(commit.subject) ? "true" : "false",
                ]
            ))
        }
    }

    // MARK: - Mapping

    static func agent(named raw: String) -> AgentKind? {
        switch raw.lowercased() {
        case "cursor": .cursor
        case "claude", "claude-code", "claudecode": .claudeCode
        case "codex": .codex
        case "kiro": .kiro
        case "windsurf": .windsurf
        case "terminal", "terminal-agent": .terminalAgent
        default: nil
        }
    }

    static func kind(named raw: String) -> AgentEventKind? {
        let mapped = AgentEventKind(rawValue: raw)
        if let mapped, mapped != .unrecognised { return mapped }
        // Accept the agents' own hook names as well as Knurl's.
        return switch raw.lowercased() {
        case "sessionstart": .sessionStarted
        case "sessionend", "stop": .sessionEnded
        case "pretooluse": .toolStarted
        case "posttooluse": .toolCompleted
        case "posttoolusefailure": .toolFailed
        case "afterfileedit": .fileEdited
        case "beforeshellexecution": .shellCommand
        default: nil
        }
    }

    private static func key(_ provider: String, _ session: String) -> String {
        "\(provider.lowercased())#\(session)"
    }

    private static func defaultSummary(_ kind: AgentEventKind, payload: EventBridge.HookPayload) -> String {
        switch kind {
        case .toolStarted: payload.tool.map { "Started \($0)" } ?? "Tool started"
        case .toolCompleted: payload.tool.map { "Finished \($0)" } ?? "Tool completed"
        case .toolFailed: payload.tool.map { "\($0) failed" } ?? "Tool failed"
        case .fileEdited: payload.path.map { "Edited \(URL(fileURLWithPath: $0).lastPathComponent)" } ?? "File edited"
        case .fileRead: payload.path.map { "Read \(URL(fileURLWithPath: $0).lastPathComponent)" } ?? "File read"
        case .shellCommand: "Shell command"
        case .sessionStarted: "Session started"
        default: kind.rawValue
        }
    }
}

enum AgentPreferences {
    private static let consentKey = "knurl.agents.consent"

    static var consent: TelemetryConsent {
        get {
            guard let data = UserDefaults.standard.data(forKey: consentKey),
                  let value = try? JSONDecoder().decode(TelemetryConsent.self, from: data)
            else { return .default }
            return value
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: consentKey)
        }
    }
}
