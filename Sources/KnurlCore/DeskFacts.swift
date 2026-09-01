import Foundation

public enum AgentProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    case cursor
    case claudeCode
    case codex
    case xcode
    case unknown

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cursor: "Cursor"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .xcode: "Xcode"
        case .unknown: "Agent"
        }
    }

    public var support: String {
        switch self {
        case .cursor, .claudeCode: "Not configured"
        case .codex: "Not configured"
        case .xcode: "Limited support"
        case .unknown: "Unknown"
        }
    }
}

public enum AgentState: String, Codable, Sendable {
    case starting
    case working
    case waitingForInput
    case waitingForPermission
    case idle
    case completed
    case failed

    public var title: String {
        switch self {
        case .starting: "Starting"
        case .working: "Working"
        case .waitingForInput, .waitingForPermission: "Needs you"
        case .idle: "Idle"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }

    public var needsHuman: Bool {
        self == .waitingForInput || self == .waitingForPermission || self == .failed
    }
}

public enum SessionEventKind: String, Codable, Sendable {
    case sessionStarted
    case harnessChanged
    case flowStarted
    case flowEnded
    case musicChanged
    case powerSnapshot
    case thermal
    case workspaceApplied
    case agent
}

public struct DeskReceipt: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var at: Date
    public var kind: SessionEventKind
    public var summary: String
    public var simulated: Bool

    public init(
        id: UUID = UUID(),
        at: Date = Date(),
        kind: SessionEventKind,
        summary: String,
        simulated: Bool = false
    ) {
        self.id = id
        self.at = at
        self.kind = kind
        self.summary = summary
        self.simulated = simulated
    }
}

public struct AgentSession: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var provider: AgentProvider
    public var title: String
    public var projectName: String?
    public var branch: String?
    public var state: AgentState
    public var attentionMessage: String?
    public var startedAt: Date
    public var lastActivityAt: Date
    public var simulated: Bool

    public init(
        id: UUID = UUID(),
        provider: AgentProvider,
        title: String,
        projectName: String? = nil,
        branch: String? = nil,
        state: AgentState,
        attentionMessage: String? = nil,
        startedAt: Date = Date(),
        lastActivityAt: Date = Date(),
        simulated: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.title = title
        self.projectName = projectName
        self.branch = branch
        self.state = state
        self.attentionMessage = attentionMessage
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.simulated = simulated
    }

    public var needsHuman: Bool { state.needsHuman }

    public func elapsed(at now: Date) -> TimeInterval {
        now.timeIntervalSince(startedAt)
    }
}

public enum NotchWhisper: Equatable, Sendable {
    case flow(destination: String)
    case attention(name: String)
    case power(percent: Int, mode: String)
    case workspace(preset: String)
    case music(title: String)
    case session(elapsed: String)
    case parked

    public var line: String {
        switch self {
        case .flow: "Knurl Flow"
        case .attention(let name): "\(name) needs you"
        case .power(let percent, let mode): "\(percent)% · \(mode)"
        case .workspace(let preset): preset
        case .music(let title): title
        case .session(let elapsed): "Flow · \(elapsed)"
        case .parked: "Knurl"
        }
    }

    public var detail: String {
        switch self {
        case .flow(let destination): "→ \(destination)"
        case .attention: "Hold to respond"
        case .power: "Battery Coding"
        case .workspace: "Workspace"
        case .music: "Music"
        case .session: "Session"
        case .parked: ""
        }
    }

    public static func pick(
        listening: Bool,
        destination: String,
        attention: String?,
        thermalException: Bool,
        batteryPercent: Int?,
        powerMode: String,
        workspaceFlash: String?,
        musicTitle: String?,
        elapsed: String
    ) -> NotchWhisper {
        if listening { return .flow(destination: destination) }
        if let attention { return .attention(name: attention) }
        if thermalException, let batteryPercent {
            return .power(percent: batteryPercent, mode: powerMode)
        }
        if let workspaceFlash { return .workspace(preset: workspaceFlash) }
        if let musicTitle, !musicTitle.isEmpty { return .music(title: musicTitle) }
        return .session(elapsed: elapsed)
    }
}

public enum FlowLexicon {
    public static let phrases: [String] = [
        "worktree", "SwiftUI", "Swift", "actor", "concurrency",
        "PostgreSQL", "Terraform", "Kubernetes", "Bedrock",
        "SessionStore", "Accessibility", "Liquid Glass",
        "pull request", "unit test", "Xcode", "Claude Code", "Codex",
        "Cursor", "refactor", "build", "test", "commit",
    ]
}
