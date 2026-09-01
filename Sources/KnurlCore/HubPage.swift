public enum HubPage: String, CaseIterable, Sendable, Identifiable, Hashable {
    case home
    case agents
    case workspace
    case flow
    case system
    case sessions

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: "Home"
        case .agents: "Agents"
        case .workspace: "Workspace"
        case .flow: "Flow"
        case .system: "System"
        case .sessions: "Sessions"
        }
    }

    public var symbol: String {
        switch self {
        case .home: "house.fill"
        case .agents: "circle.hexagongrid.fill"
        case .workspace: "rectangle.split.2x2.fill"
        case .flow: "waveform"
        case .system: "slider.horizontal.3"
        case .sessions: "clock.arrow.circlepath"
        }
    }
}
