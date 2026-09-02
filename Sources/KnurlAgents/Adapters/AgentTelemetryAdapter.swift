import Foundation

/// One adapter per agent. Adapters only emit events — they never compute
/// metrics or scores, so the analytics engine keeps working unchanged when a
/// new agent is added.
public protocol AgentTelemetryAdapter: AnyObject, Sendable {
    var agent: AgentKind { get }
    var integration: AgentIntegrationDepth { get }

    /// Returns a descriptor when this adapter can see an active session.
    func detectSession() async -> DetectedSession?

    /// Begin emitting events for `sessionID` through `emit`.
    func startMonitoring(sessionID: UUID, emit: @escaping @Sendable (AgentEvent) -> Void) async
    func stopMonitoring() async
}

/// What an adapter knows at detection time, before a session exists.
public struct DetectedSession: Sendable, Equatable {
    public var agent: AgentKind
    public var project: String?
    public var repository: String?
    public var workingDirectory: String?
    public var branch: String?
    public var externalID: String?

    public init(
        agent: AgentKind,
        project: String? = nil,
        repository: String? = nil,
        workingDirectory: String? = nil,
        branch: String? = nil,
        externalID: String? = nil
    ) {
        self.agent = agent
        self.project = project
        self.repository = repository
        self.workingDirectory = workingDirectory
        self.branch = branch
        self.externalID = externalID
    }
}

/// Which telemetry sources the user has allowed. Collection must check this
/// before emitting; defaults are the privacy-preserving set.
public struct TelemetryConsent: Codable, Sendable, Equatable {
    public var enabled: Set<TelemetrySource>
    /// Off by default. When false, prompts are counted but never stored.
    public var storePromptText: Bool

    public init(
        enabled: Set<TelemetrySource> = [.agentHook, .frontmostApp, .processActivity, .manual],
        storePromptText: Bool = false
    ) {
        self.enabled = enabled
        self.storePromptText = storePromptText
    }

    public func allows(_ source: TelemetrySource) -> Bool {
        enabled.contains(source)
    }

    public static let `default` = TelemetryConsent()
}
