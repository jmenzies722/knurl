import Foundation

/// Everything the collectors can report. Extending this list must not break
/// stored sessions: decoding an unknown kind yields `.unrecognised` rather
/// than failing the whole archive.
public enum AgentEventKind: String, Codable, Sendable, CaseIterable {
    case sessionStarted
    case sessionEnded
    case promptSubmitted
    case agentResponse
    case toolStarted
    case toolCompleted
    case toolFailed
    case shellCommand
    case fileRead
    case fileEdited
    case testStarted
    case testPassed
    case testFailed
    case gitCommit
    case userActivity
    case idleStarted
    case idleEnded
    case contextSwitch
    case unrecognised

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AgentEventKind(rawValue: raw) ?? .unrecognised
    }

    /// Which phase the session is in while this kind is the most recent signal.
    public var phase: SessionPhase? {
        switch self {
        case .promptSubmitted, .agentResponse, .toolStarted, .toolCompleted,
             .toolFailed, .shellCommand, .fileRead, .fileEdited,
             .testStarted, .testPassed, .testFailed:
            .agentRunning
        case .userActivity, .gitCommit, .contextSwitch:
            .humanWorking
        case .idleStarted:
            .waiting
        case .sessionStarted, .sessionEnded, .idleEnded, .unrecognised:
            nil
        }
    }

    public var isFailure: Bool {
        self == .toolFailed || self == .testFailed
    }
}

/// Where a signal came from. Used for provenance in the UI and to gate
/// collection against the user's privacy settings.
public enum TelemetrySource: String, Codable, Sendable, CaseIterable, Identifiable {
    case agentHook
    case processActivity
    case frontmostApp
    case gitActivity
    case fileSystem
    case manual
    case simulated

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .agentHook: "Agent hooks"
        case .processActivity: "Process detection"
        case .frontmostApp: "Frontmost application"
        case .gitActivity: "Git activity"
        case .fileSystem: "Repository file changes"
        case .manual: "Manual"
        case .simulated: "Simulated"
        }
    }

    public var detail: String {
        switch self {
        case .agentHook: "Lifecycle events the agent sends to Knurl. No prompt text."
        case .processActivity: "Whether a known agent process is running."
        case .frontmostApp: "Which app is in front, to separate your time from the agent's."
        case .gitActivity: "Commits and reverts in the session's repository."
        case .fileSystem: "Paths that changed in the repository. Never file contents."
        case .manual: "Sessions you start or end yourself."
        case .simulated: "Fixture data for testing the UI."
        }
    }
}

/// One observation. `metadata` is deliberately `[String: String]` — it keeps
/// the archive schema-stable and makes it impossible to accidentally persist a
/// prompt body or file contents through a typed payload.
public struct AgentEvent: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var sessionID: UUID
    public var timestamp: Date
    public var kind: AgentEventKind
    public var source: TelemetrySource
    /// Short human-readable line for the timeline. Never prompt or file content.
    public var summary: String
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        timestamp: Date = Date(),
        kind: AgentEventKind,
        source: TelemetrySource,
        summary: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.kind = kind
        self.source = source
        self.summary = summary
        self.metadata = metadata
    }
}

/// Which of the three clocks is running. The store accumulates wall time into
/// the matching bucket on every phase transition, so the three always sum to
/// the session duration rather than being estimated after the fact.
public enum SessionPhase: String, Codable, Sendable {
    case agentRunning
    case humanWorking
    case waiting

    public var title: String {
        switch self {
        case .agentRunning: "Agent active"
        case .humanWorking: "You working"
        case .waiting: "Waiting"
        }
    }
}
