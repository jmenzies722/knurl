import Foundation
import Observation

/// Owns live and historical sessions. Collectors push `AgentEvent`s in; views
/// read the published arrays out. Deliberately separate from `DialState` — the
/// session layer must not become part of that god object.
@MainActor
@Observable
public final class SessionStore {
    public private(set) var live: [AgentSession] = []
    public private(set) var history: [AgentSession] = []

    /// Gap after which a session is considered to be waiting on a human.
    public var idleThreshold: TimeInterval = 90

    private let archive: SessionArchive?

    public init(archive: SessionArchive? = nil) {
        self.archive = archive
    }

    public var all: [AgentSession] { live + history }

    public func session(_ id: UUID) -> AgentSession? {
        live.first { $0.id == id } ?? history.first { $0.id == id }
    }

    // MARK: - Lifecycle

    @discardableResult
    public func startSession(
        agent: AgentKind,
        project: String? = nil,
        repository: String? = nil,
        workingDirectory: String? = nil,
        branch: String? = nil,
        at now: Date = Date()
    ) -> AgentSession {
        // One live session per agent+project; a second start is a continuation.
        if let existing = live.first(where: { $0.agent == agent && $0.project == project }) {
            return existing
        }
        let session = AgentSession(
            agent: agent,
            project: project,
            repository: repository,
            workingDirectory: workingDirectory,
            branch: branch,
            startedAt: now,
            phase: .waiting,
            phaseStartedAt: now
        )
        live.append(session)
        return session
    }

    public func pause(_ id: UUID, at now: Date = Date()) {
        mutate(id) { session in
            guard session.status == .active else { return }
            Self.flushPhase(&session, to: now)
            session.status = .paused
        }
    }

    public func resume(_ id: UUID, at now: Date = Date()) {
        mutate(id) { session in
            guard session.status == .paused else { return }
            session.status = .active
            session.phaseStartedAt = now
        }
    }

    public func endSession(_ id: UUID, at now: Date = Date()) {
        guard let index = live.firstIndex(where: { $0.id == id }) else { return }
        var session = live[index]
        Self.flushPhase(&session, to: now)
        session.status = .ended
        session.endedAt = now
        if session.outcomeProvenance == .inferred {
            session.outcome = OutcomeInference.infer(session)
        }
        live.remove(at: index)
        history.insert(session, at: 0)
        persist(session)
    }

    /// User override always wins and is never re-inferred afterwards.
    public func setOutcome(_ outcome: SessionOutcome, for id: UUID) {
        mutate(id) { session in
            session.outcome = outcome
            session.outcomeProvenance = .userSet
        }
        if let session = session(id), session.status == .ended {
            persist(session)
        }
    }

    // MARK: - Events

    public func apply(_ event: AgentEvent) {
        mutate(event.sessionID) { session in
            guard session.status == .active else { return }
            Self.absorb(event, into: &session)
        }
    }

    /// Rolls the idle clock forward for live sessions that have gone quiet.
    /// Called by the collector's heartbeat, not by a poll inside the store.
    public func settleIdle(at now: Date = Date()) {
        for index in live.indices {
            var session = live[index]
            guard session.status == .active else { continue }
            let quiet = now.timeIntervalSince(session.events.last?.timestamp ?? session.startedAt)
            if quiet >= idleThreshold, session.phase != .waiting {
                Self.transition(&session, to: .waiting, at: now)
            }
            live[index] = session
        }
    }

    // MARK: - Internals

    private func mutate(_ id: UUID, _ body: (inout AgentSession) -> Void) {
        if let index = live.firstIndex(where: { $0.id == id }) {
            var session = live[index]
            body(&session)
            live[index] = session
            return
        }
        if let index = history.firstIndex(where: { $0.id == id }) {
            var session = history[index]
            body(&session)
            history[index] = session
        }
    }

    private func persist(_ session: AgentSession) {
        guard let archive else { return }
        Task { await archive.save(session) }
    }

    public func load() async {
        guard let archive else { return }
        history = await archive.loadAll()
    }

    static func absorb(_ event: AgentEvent, into session: inout AgentSession) {
        session.events.append(event)

        switch event.kind {
        case .promptSubmitted: session.metrics.prompts += 1
        case .agentResponse: session.metrics.agentResponses += 1
        case .toolStarted: session.metrics.toolCalls += 1
        case .toolFailed:
            session.metrics.failedToolCalls += 1
        case .shellCommand: session.metrics.shellCommands += 1
        case .fileRead: session.metrics.fileReads += 1
        case .fileEdited:
            session.metrics.fileEdits += 1
            if let path = event.metadata["path"] {
                session.metrics.filesChanged.insert(path)
            }
        case .testStarted: session.metrics.testRuns += 1
        case .testFailed: session.metrics.testFailures += 1
        case .gitCommit: session.metrics.gitCommits += 1
        case .contextSwitch: session.metrics.contextSwitches += 1
        default: break
        }

        // A correction loop is agent work that resumes after a failure. Counting
        // it this way means it is observed, not guessed from response counts.
        if event.kind == .toolStarted || event.kind == .agentResponse {
            if failurePending(session) { session.metrics.correctionLoops += 1 }
        }
        // A retry is the same tool re-run after that tool failed.
        if event.kind == .toolStarted, let tool = event.metadata["tool"], lastFailedTool(session) == tool {
            session.metrics.retries += 1
        }

        if let phase = event.kind.phase {
            transition(&session, to: phase, at: event.timestamp)
        }
    }

    /// True when the most recent meaningful event was a failure that has not
    /// yet been followed by agent work.
    private static func failurePending(_ session: AgentSession) -> Bool {
        for event in session.events.dropLast().reversed() {
            if event.kind.isFailure { return true }
            if event.kind == .toolStarted || event.kind == .agentResponse { return false }
        }
        return false
    }

    private static func lastFailedTool(_ session: AgentSession) -> String? {
        for event in session.events.dropLast().reversed() where event.kind == .toolFailed {
            return event.metadata["tool"]
        }
        return nil
    }

    static func transition(_ session: inout AgentSession, to phase: SessionPhase, at now: Date) {
        guard phase != session.phase else { return }
        flushPhase(&session, to: now)
        session.phase = phase
        session.phaseStartedAt = now
        if phase == .agentRunning {
            session.currentAgentRunStartedAt = now
        }
    }

    /// Adds the wall time since the last transition to the bucket for the phase
    /// we are leaving, so the three clocks always sum to tracked time.
    static func flushPhase(_ session: inout AgentSession, to now: Date) {
        let elapsed = max(0, now.timeIntervalSince(session.phaseStartedAt))
        switch session.phase {
        case .agentRunning:
            session.metrics.agentActiveSeconds += elapsed
            if let start = session.currentAgentRunStartedAt {
                let run = now.timeIntervalSince(start)
                session.metrics.longestAgentRunSeconds = max(session.metrics.longestAgentRunSeconds, run)
                session.currentAgentRunStartedAt = nil
            }
        case .humanWorking:
            session.metrics.humanActiveSeconds += elapsed
        case .waiting:
            session.metrics.idleSeconds += elapsed
        }
        session.phaseStartedAt = now
    }
}

/// Infers an outcome from what was actually observed. Returns `.unknown` rather
/// than guessing when the evidence does not support a call.
public enum OutcomeInference {
    public static func infer(_ session: AgentSession) -> SessionOutcome {
        let metrics = session.metrics
        let reverted = session.events.contains { $0.kind == .gitCommit && $0.metadata["revert"] == "true" }
        if reverted { return .rolledBack }

        let lastTestPassed = lastTestOutcome(session)
        let committed = metrics.gitCommits > 0
        let touchedAnything = metrics.fileEdits > 0

        if committed, lastTestPassed != false { return .successful }
        if lastTestPassed == true, touchedAnything { return .successful }
        if !touchedAnything, metrics.prompts <= 1 { return .abandoned }
        if lastTestPassed == false { return .partiallySuccessful }
        if touchedAnything { return .partiallySuccessful }
        return .unknown
    }

    /// nil when no tests ran at all.
    private static func lastTestOutcome(_ session: AgentSession) -> Bool? {
        for event in session.events.reversed() {
            if event.kind == .testPassed { return true }
            if event.kind == .testFailed { return false }
        }
        return nil
    }
}
