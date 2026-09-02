import Foundation
import Testing
@testable import KnurlAgents

private let origin = Date(timeIntervalSince1970: 1_700_000_000)

private func session(
    agent: AgentKind = .cursor,
    project: String? = nil,
    minutes: Double,
    outcome: SessionOutcome = .unknown,
    corrections: Int = 0,
    files: Int = 0,
    tune: (inout SessionMetrics) -> Void = { _ in }
) -> AgentSession {
    var metrics = SessionMetrics()
    metrics.agentActiveSeconds = minutes * 60 * 0.7
    metrics.humanActiveSeconds = minutes * 60 * 0.2
    metrics.idleSeconds = minutes * 60 * 0.1
    metrics.correctionLoops = corrections
    metrics.filesChanged = Set((0..<files).map { "File\($0).swift" })
    tune(&metrics)
    return AgentSession(
        agent: agent,
        project: project,
        startedAt: origin,
        endedAt: origin.addingTimeInterval(minutes * 60),
        status: .ended,
        metrics: metrics,
        outcome: outcome
    )
}

@Suite("Efficiency scoring")
struct ScoringTests {
    @Test
    func shortSessionsAreNotScored() {
        let brief = session(minutes: 0.5)
        let score = EfficiencyScorer.score(brief, at: origin)
        #expect(score.confidence == .insufficient)
        #expect(score.contributions.isEmpty)
    }

    @Test
    func factorsWithNoDataContributeNothing() {
        // No tools, no tests, no outcome — only the idle factor may apply.
        let bare = session(minutes: 30)
        let score = EfficiencyScorer.score(bare, at: origin)
        #expect(!score.contributions.contains { $0.label.contains("tool") })
        #expect(!score.contributions.contains { $0.label.contains("Tests") })
    }

    @Test
    func everyContributionCarriesItsEvidence() {
        let worked = session(minutes: 40, outcome: .successful, corrections: 4) { metrics in
            metrics.toolCalls = 40
            metrics.failedToolCalls = 12
            metrics.testRuns = 3
            metrics.testFailures = 0
        }
        let score = EfficiencyScorer.score(worked, at: origin)
        #expect(!score.contributions.isEmpty)
        for contribution in score.contributions {
            #expect(!contribution.evidence.isEmpty)
            #expect(contribution.delta != 0 || contribution.label == "Partial completion")
        }
    }

    @Test
    func scoreStaysInRangeUnderCompoundedPenalties() {
        let bad = session(minutes: 200, outcome: .rolledBack, corrections: 20) { metrics in
            metrics.toolCalls = 50
            metrics.failedToolCalls = 45
            metrics.testRuns = 5
            metrics.testFailures = 5
            metrics.retries = 15
            metrics.contextSwitches = 400
            metrics.idleSeconds = metrics.trackedSeconds
        }
        let score = EfficiencyScorer.score(bad, at: origin)
        #expect(score.value >= 0)
        #expect(score.value <= 100)
    }

    @Test
    func basicIntegrationIsMarkedPartial() {
        let terminal = session(agent: .terminalAgent, minutes: 30)
        #expect(EfficiencyScorer.score(terminal, at: origin).confidence == .partial)
    }
}

@Suite("Insights refuse to fabricate")
struct InsightTests {
    @Test
    func noInsightsFromAThinSample() {
        let few = (0..<3).map { _ in session(minutes: 30, outcome: .successful) }
        #expect(SessionInsightEngine.insights(for: few, now: origin).isEmpty)
    }

    @Test
    func durationInsightNeedsTwoPopulatedBands() {
        // Ten sessions, all in one band — no comparison is possible.
        let oneBand = (0..<10).map { _ in session(minutes: 30, outcome: .successful) }
        let result = SessionInsightEngine.durationSweetSpot(oneBand, now: origin)
        #expect(result == nil)
    }

    @Test
    func durationInsightAppearsWithTwoBandsAndCitesBoth() {
        let good = (0..<6).map { _ in session(minutes: 30, outcome: .successful) }
        let bad = (0..<6).map { _ in session(minutes: 120, outcome: .abandoned) }
        let result = SessionInsightEngine.durationSweetSpot(good + bad, now: origin)
        let insight = try! #require(result)
        #expect(insight.headline.contains("20–40 minute"))
        #expect(insight.evidence.count == 2)
        #expect(insight.sampleSize == 12)
    }

    @Test
    func correctionInsightStaysSilentWhenTheEffectIsSmall() {
        let long = (0..<6).map { _ in session(minutes: 120, corrections: 2) }
        let short = (0..<6).map { _ in session(minutes: 30, corrections: 2) }
        #expect(SessionInsightEngine.longSessionCorrections(long + short, now: origin) == nil)
    }

    @Test
    func correctionInsightReportsTheRealMultiple() {
        let long = (0..<6).map { _ in session(minutes: 120, corrections: 6) }
        let short = (0..<6).map { _ in session(minutes: 30, corrections: 2) }
        let insight = try! #require(SessionInsightEngine.longSessionCorrections(long + short, now: origin))
        #expect(insight.headline.contains("3.0x"))
    }
}

@Suite("Aggregation")
struct AggregationTests {
    @Test
    func filesChangedAcrossSessionsIsDistinct() {
        let a = session(minutes: 10, files: 5)
        let b = session(minutes: 10, files: 5)
        // Same synthetic paths in both, so the union is 5, not 10.
        let summary = SessionAnalyticsEngine.summarise([a, b], now: origin)
        #expect(summary.filesChanged == 5)
        #expect(summary.sessionCount == 2)
    }

    @Test
    func comparisonRanksByTimeAndOmitsUnscorableAgents() {
        let cursor = (0..<3).map { _ in session(agent: .cursor, minutes: 60, outcome: .successful) }
        let codex = (0..<2).map { _ in session(agent: .codex, minutes: 10, outcome: .abandoned) }
        let rows = SessionAnalyticsEngine.compare(cursor + codex, now: origin)
        #expect(rows.first?.agent == .cursor)
        #expect(rows.count == 2)
    }

    @Test
    func dailyBucketsKeepEmptyDays() {
        let buckets = SessionAnalyticsEngine.daily([], in: .days(7), now: origin)
        #expect(buckets.count == 8)
        #expect(buckets.allSatisfy { $0.summary.isEmpty })
    }
}
