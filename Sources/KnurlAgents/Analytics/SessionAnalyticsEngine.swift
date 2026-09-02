import Foundation

public enum AnalyticsRange: Sendable, Equatable {
    case today
    case days(Int)
    case custom(start: Date, end: Date)

    public var title: String {
        switch self {
        case .today: "Today"
        case .days(let count): "\(count) days"
        case .custom: "Custom"
        }
    }

    public func interval(now: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            return DateInterval(start: start, end: now)
        case .days(let count):
            let start = calendar.date(byAdding: .day, value: -count, to: calendar.startOfDay(for: now)) ?? now
            return DateInterval(start: start, end: now)
        case .custom(let start, let end):
            return DateInterval(start: min(start, end), end: max(start, end))
        }
    }
}

/// Aggregated numbers for one period. Every field is a sum or mean of observed
/// session metrics — nothing here is modelled or extrapolated.
public struct AnalyticsSummary: Sendable, Equatable {
    public var sessionCount = 0
    public var totalSeconds: TimeInterval = 0
    public var agentActiveSeconds: TimeInterval = 0
    public var humanActiveSeconds: TimeInterval = 0
    public var idleSeconds: TimeInterval = 0
    public var longestSessionSeconds: TimeInterval = 0
    public var contextSwitches = 0
    public var prompts = 0
    public var toolCalls = 0
    public var failedToolCalls = 0
    public var filesChanged = 0
    public var testRuns = 0
    public var testFailures = 0
    public var correctionLoops = 0
    public var successfulSessions = 0

    public var averageSessionSeconds: TimeInterval {
        sessionCount > 0 ? totalSeconds / Double(sessionCount) : 0
    }

    /// Correction loops per session, not per prompt — the denominator that
    /// matches how the number is described in the UI.
    public var correctionRate: Double {
        sessionCount > 0 ? Double(correctionLoops) / Double(sessionCount) : 0
    }

    public var successRate: Double {
        sessionCount > 0 ? Double(successfulSessions) / Double(sessionCount) : 0
    }

    public var isEmpty: Bool { sessionCount == 0 }
}

/// One agent's row in the comparison view.
public struct AgentComparison: Sendable, Equatable, Identifiable {
    public var agent: AgentKind
    public var summary: AnalyticsSummary
    public var averageEfficiency: Int?
    public var averageTimeToResultSeconds: TimeInterval?

    public var id: String { agent.rawValue }

    public var promptsPerSession: Double {
        summary.sessionCount > 0 ? Double(summary.prompts) / Double(summary.sessionCount) : 0
    }
}

public enum SessionAnalyticsEngine {
    public static func sessions(
        _ sessions: [AgentSession],
        in range: AnalyticsRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [AgentSession] {
        let interval = range.interval(now: now, calendar: calendar)
        return sessions.filter { interval.contains($0.startedAt) }
    }

    public static func summarise(_ sessions: [AgentSession], now: Date = Date()) -> AnalyticsSummary {
        var summary = AnalyticsSummary()
        var paths = Set<String>()
        for session in sessions {
            summary.sessionCount += 1
            let duration = session.duration(at: now)
            summary.totalSeconds += duration
            summary.longestSessionSeconds = max(summary.longestSessionSeconds, duration)
            summary.agentActiveSeconds += session.metrics.agentActiveSeconds
            summary.humanActiveSeconds += session.metrics.humanActiveSeconds
            summary.idleSeconds += session.metrics.idleSeconds
            summary.contextSwitches += session.metrics.contextSwitches
            summary.prompts += session.metrics.prompts
            summary.toolCalls += session.metrics.toolCalls
            summary.failedToolCalls += session.metrics.failedToolCalls
            summary.testRuns += session.metrics.testRuns
            summary.testFailures += session.metrics.testFailures
            summary.correctionLoops += session.metrics.correctionLoops
            if session.outcome == .successful { summary.successfulSessions += 1 }
            paths.formUnion(session.metrics.filesChanged)
        }
        summary.filesChanged = paths.count
        return summary
    }

    public static func compare(_ sessions: [AgentSession], now: Date = Date()) -> [AgentComparison] {
        let grouped = Dictionary(grouping: sessions, by: \.agent)
        return grouped.map { agent, group in
            let scores = group
                .filter { $0.status == .ended }
                .map { EfficiencyScorer.score($0, at: now) }
                .filter { $0.confidence != .insufficient }
                .map(\.value)
            let times = group.compactMap { timeToFirstResult($0) }
            return AgentComparison(
                agent: agent,
                summary: summarise(group, now: now),
                averageEfficiency: scores.isEmpty ? nil : scores.reduce(0, +) / scores.count,
                averageTimeToResultSeconds: times.isEmpty ? nil : times.reduce(0, +) / Double(times.count)
            )
        }
        .sorted { $0.summary.totalSeconds > $1.summary.totalSeconds }
    }

    /// Daily buckets for trend lines. Days with no sessions are present with an
    /// empty summary so a chart shows the gap instead of closing over it.
    public static func daily(
        _ sessions: [AgentSession],
        in range: AnalyticsRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [(day: Date, summary: AnalyticsSummary)] {
        let interval = range.interval(now: now, calendar: calendar)
        var buckets: [(Date, AnalyticsSummary)] = []
        var cursor = calendar.startOfDay(for: interval.start)
        let last = calendar.startOfDay(for: interval.end)
        while cursor <= last {
            let next = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            let day = sessions.filter { $0.startedAt >= cursor && $0.startedAt < next }
            buckets.append((cursor, summarise(day, now: now)))
            cursor = next
        }
        return buckets
    }

    static func timeToFirstResult(_ session: AgentSession) -> TimeInterval? {
        guard let first = session.events.first(where: { $0.kind == .fileEdited }) else { return nil }
        return first.timestamp.timeIntervalSince(session.startedAt)
    }
}
