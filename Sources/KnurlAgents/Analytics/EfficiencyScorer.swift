import Foundation

/// One signed, named reason the score moved. The UI renders these verbatim, so
/// a score can always be traced back to the metric that produced it.
public struct ScoreContribution: Sendable, Equatable, Identifiable {
    public var id: String { label }
    public var label: String
    public var delta: Int
    /// The observed number behind the delta, e.g. "idle 8% of tracked time".
    public var evidence: String

    public init(label: String, delta: Int, evidence: String) {
        self.label = label
        self.delta = delta
        self.evidence = evidence
    }
}

/// How much of the score is actually grounded. A basic-integration agent can
/// only supply time signals, so its score is explicitly marked partial rather
/// than presented with the same authority as a hooked session.
public enum ScoreConfidence: String, Sendable {
    case grounded
    case partial
    case insufficient

    public var title: String {
        switch self {
        case .grounded: "Based on full session telemetry"
        case .partial: "Based on timing only — this agent has basic integration"
        case .insufficient: "Not enough signal to score this session"
        }
    }
}

public struct EfficiencyScore: Sendable, Equatable {
    public var value: Int
    public var contributions: [ScoreContribution]
    public var confidence: ScoreConfidence

    public var positives: [ScoreContribution] { contributions.filter { $0.delta > 0 } }
    public var negatives: [ScoreContribution] { contributions.filter { $0.delta < 0 } }
}

/// Turns observed metrics into a 0–100 score. Every factor is skipped entirely
/// when the underlying counter has no data, so a session that never ran a tool
/// is not rewarded *or* punished for its tool failure rate.
public enum EfficiencyScorer {
    static let baseline = 70

    public static func score(_ session: AgentSession, at now: Date = Date()) -> EfficiencyScore {
        let metrics = session.metrics
        var contributions: [ScoreContribution] = []

        // Needs at least a minute of tracked time before any judgement is fair.
        guard metrics.trackedSeconds >= 60 else {
            return EfficiencyScore(value: 0, contributions: [], confidence: .insufficient)
        }

        // --- Idle ---------------------------------------------------------
        let idle = metrics.idleRatio
        if idle <= 0.15 {
            contributions.append(.init(
                label: "Low idle time",
                delta: 8,
                evidence: "Waiting was \(percent(idle)) of tracked time"
            ))
        } else if idle >= 0.40 {
            let delta = -min(18, Int(((idle - 0.40) * 60).rounded()) + 6)
            contributions.append(.init(
                label: "High idle time",
                delta: delta,
                evidence: "Waiting was \(percent(idle)) of tracked time"
            ))
        }

        // --- Tool reliability ---------------------------------------------
        if metrics.toolCalls >= 5 {
            let rate = metrics.toolFailureRate
            if rate <= 0.05 {
                contributions.append(.init(
                    label: "Tools ran clean",
                    delta: 6,
                    evidence: "\(metrics.failedToolCalls) of \(metrics.toolCalls) tool calls failed"
                ))
            } else if rate >= 0.20 {
                let delta = -min(16, Int((rate * 40).rounded()))
                contributions.append(.init(
                    label: "High tool failure rate",
                    delta: delta,
                    evidence: "\(metrics.failedToolCalls) of \(metrics.toolCalls) tool calls failed"
                ))
            }
        }

        // --- Correction loops ---------------------------------------------
        if metrics.correctionLoops >= 2 {
            let delta = -min(15, metrics.correctionLoops * 4)
            contributions.append(.init(
                label: "Repeated corrections",
                delta: delta,
                evidence: "\(metrics.correctionLoops) correction loops"
            ))
        } else if metrics.correctionLoops == 0, metrics.agentResponses >= 3 {
            contributions.append(.init(
                label: "No correction loops",
                delta: 5,
                evidence: "\(metrics.agentResponses) agent responses, none re-run after a failure"
            ))
        }

        // --- Retries -------------------------------------------------------
        if metrics.retries >= 3 {
            contributions.append(.init(
                label: "Excessive retries",
                delta: -min(10, metrics.retries * 2),
                evidence: "\(metrics.retries) retries"
            ))
        }

        // --- Tests ---------------------------------------------------------
        if metrics.testRuns > 0 {
            if metrics.testFailures == 0 {
                contributions.append(.init(
                    label: "Tests passed",
                    delta: 10,
                    evidence: "\(metrics.testRuns) test runs, no failures"
                ))
            } else if endedOnPassingTests(session) {
                contributions.append(.init(
                    label: "Tests recovered",
                    delta: 4,
                    evidence: "\(metrics.testFailures) failures, last run passed"
                ))
            } else {
                contributions.append(.init(
                    label: "Tests left failing",
                    delta: -12,
                    evidence: "\(metrics.testFailures) of \(metrics.testRuns) test runs failed"
                ))
            }
        }

        // --- Outcome -------------------------------------------------------
        switch session.outcome {
        case .successful:
            contributions.append(.init(
                label: "Successful completion",
                delta: 10,
                evidence: outcomeEvidence(session)
            ))
        case .partiallySuccessful:
            contributions.append(.init(label: "Partial completion", delta: 0, evidence: outcomeEvidence(session)))
        case .abandoned:
            contributions.append(.init(label: "Session abandoned", delta: -12, evidence: outcomeEvidence(session)))
        case .rolledBack:
            contributions.append(.init(label: "Work rolled back", delta: -16, evidence: outcomeEvidence(session)))
        case .unknown:
            break
        }

        // --- Context switching ----------------------------------------------
        let hours = max(metrics.trackedSeconds / 3600, 0.01)
        let switchesPerHour = Double(metrics.contextSwitches) / hours
        if switchesPerHour >= 20 {
            contributions.append(.init(
                label: "High context switching",
                delta: -min(12, Int((switchesPerHour / 4).rounded())),
                evidence: "\(metrics.contextSwitches) app switches, \(Int(switchesPerHour.rounded()))/hour"
            ))
        } else if metrics.contextSwitches > 0, switchesPerHour <= 6 {
            contributions.append(.init(
                label: "Stayed in the work",
                delta: 4,
                evidence: "\(Int(switchesPerHour.rounded())) app switches per hour"
            ))
        }

        // --- Time to useful result -------------------------------------------
        if let first = timeToFirstResult(session) {
            if first <= 300 {
                contributions.append(.init(
                    label: "Fast first result",
                    delta: 6,
                    evidence: "First file edit after \(minutes(first))"
                ))
            } else if first >= 1200 {
                contributions.append(.init(
                    label: "Slow first result",
                    delta: -8,
                    evidence: "First file edit after \(minutes(first))"
                ))
            }
        }

        let total = contributions.reduce(baseline) { $0 + $1.delta }
        let clamped = max(0, min(100, total))
        return EfficiencyScore(
            value: clamped,
            contributions: contributions.sorted { abs($0.delta) > abs($1.delta) },
            confidence: session.agent.integration == .deep ? .grounded : .partial
        )
    }

    private static func endedOnPassingTests(_ session: AgentSession) -> Bool {
        for event in session.events.reversed() {
            if event.kind == .testPassed { return true }
            if event.kind == .testFailed { return false }
        }
        return false
    }

    private static func timeToFirstResult(_ session: AgentSession) -> TimeInterval? {
        guard let first = session.events.first(where: { $0.kind == .fileEdited }) else { return nil }
        return first.timestamp.timeIntervalSince(session.startedAt)
    }

    private static func outcomeEvidence(_ session: AgentSession) -> String {
        let source = session.outcomeProvenance == .userSet ? "set by you" : "inferred"
        return "\(session.outcome.title), \(source)"
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func minutes(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "\(Int(seconds))s" : "\(Int(seconds / 60))m"
    }
}
