import Foundation

/// A pattern found across sessions. `evidence` is the actual arithmetic behind
/// the headline and is always shown with it — an insight with no evidence is a
/// bug, not a nicety.
public struct SessionInsight: Sendable, Equatable, Identifiable {
    public var id: String
    public var headline: String
    public var evidence: [String]
    public var sampleSize: Int

    public init(id: String, headline: String, evidence: [String], sampleSize: Int) {
        self.id = id
        self.headline = headline
        self.evidence = evidence
        self.sampleSize = sampleSize
    }
}

/// Derives insights only where the sample supports them. Every rule returns nil
/// rather than softening its language when data is thin, so the UI can render
/// "not enough data yet" honestly instead of showing a weak claim.
public enum SessionInsightEngine {
    /// Sessions required in each side of a comparison before it is reported.
    public static let minimumPerGroup = 5

    public static func insights(for sessions: [AgentSession], now: Date = Date()) -> [SessionInsight] {
        let ended = sessions.filter { $0.status == .ended }
        return [
            durationSweetSpot(ended, now: now),
            longSessionCorrections(ended, now: now),
            testsEarly(ended),
            filesTouchedRollback(ended),
            agentByProject(ended),
        ].compactMap { $0 }
    }

    // MARK: - Rules

    /// Which duration band has the highest success rate.
    static func durationSweetSpot(_ sessions: [AgentSession], now: Date) -> SessionInsight? {
        let bands: [(String, ClosedRange<Double>)] = [
            ("under 20 minutes", 0...1200),
            ("20–40 minute", 1200...2400),
            ("40–90 minute", 2400...5400),
            ("over 90 minute", 5400...Double.greatestFiniteMagnitude),
        ]
        var rows: [(String, Int, Double)] = []
        for (label, range) in bands {
            let group = sessions.filter { range.contains($0.duration(at: now)) }
            guard group.count >= minimumPerGroup else { continue }
            let rate = Double(group.filter { $0.outcome == .successful }.count) / Double(group.count)
            rows.append((label, group.count, rate))
        }
        guard rows.count >= 2, let best = rows.max(by: { $0.2 < $1.2 }) else { return nil }
        return SessionInsight(
            id: "duration-sweet-spot",
            headline: "Your \(best.0) sessions have the highest success rate.",
            evidence: rows.map { "\($0.0): \(pct($0.2)) successful of \($0.1) sessions" },
            sampleSize: rows.reduce(0) { $0 + $1.1 }
        )
    }

    /// Whether long sessions actually produce more correction loops here.
    static func longSessionCorrections(_ sessions: [AgentSession], now: Date) -> SessionInsight? {
        let long = sessions.filter { $0.duration(at: now) > 5400 }
        let short = sessions.filter { $0.duration(at: now) <= 5400 }
        guard long.count >= minimumPerGroup, short.count >= minimumPerGroup else { return nil }
        let longRate = mean(long.map { Double($0.metrics.correctionLoops) })
        let shortRate = mean(short.map { Double($0.metrics.correctionLoops) })
        guard shortRate > 0, longRate > shortRate * 1.2 else { return nil }
        let factor = (longRate / shortRate * 10).rounded() / 10
        return SessionInsight(
            id: "long-session-corrections",
            headline: "Sessions longer than 90 minutes produce \(factor)x more corrections.",
            evidence: [
                "Over 90 min: \(round1(longRate)) corrections per session across \(long.count) sessions",
                "Under 90 min: \(round1(shortRate)) corrections per session across \(short.count) sessions",
            ],
            sampleSize: long.count + short.count
        )
    }

    /// Whether running tests before the second agent iteration correlates with success.
    static func testsEarly(_ sessions: [AgentSession]) -> SessionInsight? {
        let early = sessions.filter { testedBeforeSecondIteration($0) }
        let late = sessions.filter { !testedBeforeSecondIteration($0) }
        guard early.count >= minimumPerGroup, late.count >= minimumPerGroup else { return nil }
        let earlyRate = successRate(early)
        let lateRate = successRate(late)
        guard earlyRate > lateRate + 0.15 else { return nil }
        return SessionInsight(
            id: "tests-early",
            headline: "You do better when tests run before the second agent iteration.",
            evidence: [
                "Tests first: \(pct(earlyRate)) successful of \(early.count) sessions",
                "Tests later: \(pct(lateRate)) successful of \(late.count) sessions",
            ],
            sampleSize: early.count + late.count
        )
    }

    /// Whether wide changes correlate with rollback.
    static func filesTouchedRollback(_ sessions: [AgentSession]) -> SessionInsight? {
        let wide = sessions.filter { $0.metrics.filesChanged.count > 12 }
        let narrow = sessions.filter { $0.metrics.filesChanged.count <= 12 && !$0.metrics.filesChanged.isEmpty }
        guard wide.count >= minimumPerGroup, narrow.count >= minimumPerGroup else { return nil }
        let wideRate = rollbackRate(wide)
        let narrowRate = rollbackRate(narrow)
        guard wideRate > narrowRate + 0.10 else { return nil }
        return SessionInsight(
            id: "files-rollback",
            headline: "Sessions touching more than 12 files have a higher rollback rate.",
            evidence: [
                "Over 12 files: \(pct(wideRate)) rolled back of \(wide.count) sessions",
                "12 or fewer: \(pct(narrowRate)) rolled back of \(narrow.count) sessions",
            ],
            sampleSize: wide.count + narrow.count
        )
    }

    /// Which agent performs better on a specific project, where both have data.
    static func agentByProject(_ sessions: [AgentSession]) -> SessionInsight? {
        let byProject = Dictionary(grouping: sessions.filter { $0.project != nil }, by: { $0.project! })
        for (project, group) in byProject.sorted(by: { $0.value.count > $1.value.count }) {
            let byAgent = Dictionary(grouping: group, by: \.agent)
                .filter { $0.value.count >= minimumPerGroup }
            guard byAgent.count >= 2 else { continue }
            let ranked = byAgent
                .map { (agent: $0.key, count: $0.value.count, rate: successRate($0.value)) }
                .sorted { $0.rate > $1.rate }
            guard let best = ranked.first, let next = ranked.dropFirst().first,
                  best.rate > next.rate + 0.15 else { continue }
            return SessionInsight(
                id: "agent-by-project-\(project)",
                headline: "\(best.agent.title) currently performs better on \(project).",
                evidence: ranked.map { "\($0.agent.title): \(pct($0.rate)) successful of \($0.count) sessions" },
                sampleSize: ranked.reduce(0) { $0 + $1.count }
            )
        }
        return nil
    }

    // MARK: - Helpers

    static func testedBeforeSecondIteration(_ session: AgentSession) -> Bool {
        var responses = 0
        for event in session.events {
            if event.kind == .agentResponse { responses += 1 }
            if event.kind == .testStarted { return responses < 2 }
        }
        return false
    }

    private static func successRate(_ sessions: [AgentSession]) -> Double {
        sessions.isEmpty ? 0 : Double(sessions.filter { $0.outcome == .successful }.count) / Double(sessions.count)
    }

    private static func rollbackRate(_ sessions: [AgentSession]) -> Double {
        sessions.isEmpty ? 0 : Double(sessions.filter { $0.outcome == .rolledBack }.count) / Double(sessions.count)
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func pct(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    private static func round1(_ value: Double) -> String { String(format: "%.1f", value) }
}
