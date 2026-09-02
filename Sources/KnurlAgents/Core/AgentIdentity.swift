import Foundation

/// A coding agent Knurl can observe. Adding a case must never require touching
/// the analytics engine — everything downstream keys off this enum only for
/// display and grouping.
public enum AgentKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case cursor
    case claudeCode
    case codex
    case kiro
    case windsurf
    case terminalAgent
    case xcode
    case unknown

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cursor: "Cursor"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .kiro: "Kiro"
        case .windsurf: "Windsurf"
        case .terminalAgent: "Terminal agent"
        case .xcode: "Xcode"
        case .unknown: "Unknown agent"
        }
    }

    /// Bundle identifiers that mean "this agent is frontmost". Terminal agents
    /// are detected by process, not bundle, so they list the host terminals.
    public var bundleIdentifiers: [String] {
        switch self {
        case .cursor: ["com.todesktop.230313mzl4w4u92", "com.cursor.Cursor"]
        case .claudeCode: []
        case .codex: ["com.openai.codex"]
        case .kiro: ["dev.kiro.desktop", "com.amazon.kiro"]
        case .windsurf: ["com.exafunction.windsurf", "com.codeium.windsurf"]
        case .terminalAgent: ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty"]
        case .xcode: ["com.apple.dt.Xcode"]
        case .unknown: []
        }
    }

    /// How much Knurl can actually see. The UI must not promise more than this.
    public var integration: AgentIntegrationDepth {
        switch self {
        case .cursor, .claudeCode: .deep
        case .codex, .kiro, .windsurf, .terminalAgent: .basic
        case .xcode, .unknown: .basic
        }
    }
}

/// Deep = lifecycle hooks give prompts, tools, files and failures.
/// Basic = app/process presence gives duration, activity and idle only.
public enum AgentIntegrationDepth: String, Codable, Sendable {
    case deep
    case basic

    public var title: String {
        switch self {
        case .deep: "Deep integration"
        case .basic: "Basic integration"
        }
    }

    public var detail: String {
        switch self {
        case .deep: "Prompts, tools, files and failures."
        case .basic: "Session duration, activity and idle only."
        }
    }
}

/// How a session ended. `inferred` outcomes are always overridable by the user;
/// the store records which is which so the UI never claims false certainty.
public enum SessionOutcome: String, Codable, Sendable, CaseIterable, Identifiable {
    case successful
    case partiallySuccessful
    case abandoned
    case rolledBack
    case unknown

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .successful: "Successful"
        case .partiallySuccessful: "Partially successful"
        case .abandoned: "Abandoned"
        case .rolledBack: "Rolled back"
        case .unknown: "Unknown"
        }
    }
}

public enum OutcomeProvenance: String, Codable, Sendable {
    case inferred
    case userSet
}
