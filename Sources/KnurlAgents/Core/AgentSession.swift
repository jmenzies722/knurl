import Foundation

public enum SessionStatus: String, Codable, Sendable {
    case active
    case paused
    case ended

    public var title: String {
        switch self {
        case .active: "Active"
        case .paused: "Paused"
        case .ended: "Ended"
        }
    }
}

/// Every counter is observed, never estimated. A counter that no collector can
/// populate for a given agent stays at zero, and the UI reads
/// `AgentKind.integration` to explain why rather than showing a fake number.
public struct SessionMetrics: Codable, Sendable, Equatable {
    public var agentActiveSeconds: TimeInterval = 0
    public var humanActiveSeconds: TimeInterval = 0
    public var idleSeconds: TimeInterval = 0

    public var prompts = 0
    public var agentResponses = 0
    public var toolCalls = 0
    public var failedToolCalls = 0
    public var shellCommands = 0
    public var fileReads = 0
    public var fileEdits = 0
    public var testRuns = 0
    public var testFailures = 0
    public var retries = 0
    public var correctionLoops = 0
    public var gitCommits = 0
    public var contextSwitches = 0

    /// Distinct paths, so "7 files changed" means seven files, not seven edits.
    public var filesChanged: Set<String> = []
    public var longestAgentRunSeconds: TimeInterval = 0

    public init() {}

    public var trackedSeconds: TimeInterval {
        agentActiveSeconds + humanActiveSeconds + idleSeconds
    }

    public var idleRatio: Double {
        trackedSeconds > 0 ? idleSeconds / trackedSeconds : 0
    }

    public var toolFailureRate: Double {
        toolCalls > 0 ? Double(failedToolCalls) / Double(toolCalls) : 0
    }

    public var testFailureRate: Double {
        testRuns > 0 ? Double(testFailures) / Double(testRuns) : 0
    }
}

public struct AgentSession: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var agent: AgentKind
    public var project: String?
    public var repository: String?
    public var workingDirectory: String?
    public var branch: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var status: SessionStatus
    public var metrics: SessionMetrics
    public var outcome: SessionOutcome
    public var outcomeProvenance: OutcomeProvenance
    public var events: [AgentEvent]

    /// Bookkeeping for the phase clocks. Not shown; kept so a session survives
    /// a restart mid-flight without losing its accumulated time.
    public var phase: SessionPhase
    public var phaseStartedAt: Date
    public var currentAgentRunStartedAt: Date?

    public init(
        id: UUID = UUID(),
        agent: AgentKind,
        project: String? = nil,
        repository: String? = nil,
        workingDirectory: String? = nil,
        branch: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        status: SessionStatus = .active,
        metrics: SessionMetrics = SessionMetrics(),
        outcome: SessionOutcome = .unknown,
        outcomeProvenance: OutcomeProvenance = .inferred,
        events: [AgentEvent] = [],
        phase: SessionPhase = .waiting,
        phaseStartedAt: Date = Date(),
        currentAgentRunStartedAt: Date? = nil
    ) {
        self.id = id
        self.agent = agent
        self.project = project
        self.repository = repository
        self.workingDirectory = workingDirectory
        self.branch = branch
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.metrics = metrics
        self.outcome = outcome
        self.outcomeProvenance = outcomeProvenance
        self.events = events
        self.phase = phase
        self.phaseStartedAt = phaseStartedAt
        self.currentAgentRunStartedAt = currentAgentRunStartedAt
    }

    public func duration(at now: Date = Date()) -> TimeInterval {
        (endedAt ?? now).timeIntervalSince(startedAt)
    }

    public var isLive: Bool { status == .active }

    public var displayProject: String {
        project ?? repository ?? "No project"
    }
}
