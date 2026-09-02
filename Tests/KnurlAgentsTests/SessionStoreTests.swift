import Foundation
import Testing
@testable import KnurlAgents

@MainActor
private func makeStore() -> SessionStore { SessionStore() }

private func event(
    _ kind: AgentEventKind,
    _ session: UUID,
    at offset: TimeInterval,
    from origin: Date,
    metadata: [String: String] = [:]
) -> AgentEvent {
    AgentEvent(
        sessionID: session,
        timestamp: origin.addingTimeInterval(offset),
        kind: kind,
        source: .simulated,
        summary: kind.rawValue,
        metadata: metadata
    )
}

@Suite("Session phase accounting")
struct PhaseTests {
    @Test @MainActor
    func threeClocksSumToTrackedTime() {
        let origin = Date(timeIntervalSince1970: 1_000_000)
        let store = makeStore()
        let session = store.startSession(agent: .cursor, project: "knurl", at: origin)

        store.apply(event(.promptSubmitted, session.id, at: 0, from: origin))
        store.apply(event(.toolStarted, session.id, at: 60, from: origin))
        store.apply(event(.userActivity, session.id, at: 300, from: origin))
        store.apply(event(.idleStarted, session.id, at: 420, from: origin))
        store.endSession(session.id, at: origin.addingTimeInterval(600))

        let ended = try! #require(store.history.first)
        #expect(ended.metrics.trackedSeconds == 600)
        #expect(ended.metrics.agentActiveSeconds == 300)
        #expect(ended.metrics.humanActiveSeconds == 120)
        #expect(ended.metrics.idleSeconds == 180)
    }

    @Test @MainActor
    func longestAgentRunTracksTheBiggestUninterruptedStretch() {
        let origin = Date(timeIntervalSince1970: 2_000_000)
        let store = makeStore()
        let session = store.startSession(agent: .cursor, at: origin)

        store.apply(event(.toolStarted, session.id, at: 0, from: origin))
        store.apply(event(.userActivity, session.id, at: 100, from: origin))
        store.apply(event(.toolStarted, session.id, at: 200, from: origin))
        store.apply(event(.userActivity, session.id, at: 500, from: origin))
        store.endSession(session.id, at: origin.addingTimeInterval(520))

        let ended = try! #require(store.history.first)
        #expect(ended.metrics.longestAgentRunSeconds == 300)
    }

    @Test @MainActor
    func pausedSessionStopsAccumulating() {
        let origin = Date(timeIntervalSince1970: 3_000_000)
        let store = makeStore()
        let session = store.startSession(agent: .cursor, at: origin)
        store.apply(event(.toolStarted, session.id, at: 0, from: origin))
        store.pause(session.id, at: origin.addingTimeInterval(100))
        store.apply(event(.toolStarted, session.id, at: 400, from: origin))

        let live = try! #require(store.live.first)
        #expect(live.metrics.agentActiveSeconds == 100)
        #expect(live.status == .paused)
    }
}

@Suite("Metric derivation")
struct MetricTests {
    @Test @MainActor
    func correctionLoopCountedOnlyAfterAFailure() {
        let origin = Date(timeIntervalSince1970: 4_000_000)
        let store = makeStore()
        let session = store.startSession(agent: .cursor, at: origin)

        store.apply(event(.toolStarted, session.id, at: 0, from: origin))
        store.apply(event(.toolCompleted, session.id, at: 10, from: origin))
        store.apply(event(.toolStarted, session.id, at: 20, from: origin))
        #expect(store.live[0].metrics.correctionLoops == 0)

        store.apply(event(.toolFailed, session.id, at: 30, from: origin))
        store.apply(event(.toolStarted, session.id, at: 40, from: origin))
        #expect(store.live[0].metrics.correctionLoops == 1)
    }

    @Test @MainActor
    func retryRequiresTheSameToolToFailFirst() {
        let origin = Date(timeIntervalSince1970: 5_000_000)
        let store = makeStore()
        let session = store.startSession(agent: .cursor, at: origin)

        store.apply(event(.toolFailed, session.id, at: 0, from: origin, metadata: ["tool": "swift build"]))
        store.apply(event(.toolStarted, session.id, at: 10, from: origin, metadata: ["tool": "swift build"]))
        #expect(store.live[0].metrics.retries == 1)

        store.apply(event(.toolFailed, session.id, at: 20, from: origin, metadata: ["tool": "swift build"]))
        store.apply(event(.toolStarted, session.id, at: 30, from: origin, metadata: ["tool": "swift test"]))
        #expect(store.live[0].metrics.retries == 1)
    }

    @Test @MainActor
    func filesChangedCountsDistinctPaths() {
        let origin = Date(timeIntervalSince1970: 6_000_000)
        let store = makeStore()
        let session = store.startSession(agent: .cursor, at: origin)

        for offset in 0..<3 {
            store.apply(event(.fileEdited, session.id, at: Double(offset), from: origin, metadata: ["path": "A.swift"]))
        }
        store.apply(event(.fileEdited, session.id, at: 5, from: origin, metadata: ["path": "B.swift"]))

        #expect(store.live[0].metrics.fileEdits == 4)
        #expect(store.live[0].metrics.filesChanged.count == 2)
    }
}

@Suite("Outcome inference")
struct OutcomeTests {
    @Test @MainActor
    func commitWithoutFailingTestsIsSuccessful() {
        let origin = Date(timeIntervalSince1970: 7_000_000)
        let store = makeStore()
        let session = store.startSession(agent: .cursor, at: origin)
        store.apply(event(.fileEdited, session.id, at: 10, from: origin, metadata: ["path": "A.swift"]))
        store.apply(event(.testPassed, session.id, at: 20, from: origin))
        store.apply(event(.gitCommit, session.id, at: 30, from: origin))
        store.endSession(session.id, at: origin.addingTimeInterval(60))

        #expect(store.history[0].outcome == .successful)
        #expect(store.history[0].outcomeProvenance == .inferred)
    }

    @Test @MainActor
    func revertingCommitIsRolledBack() {
        let origin = Date(timeIntervalSince1970: 8_000_000)
        let store = makeStore()
        let session = store.startSession(agent: .cursor, at: origin)
        store.apply(event(.fileEdited, session.id, at: 10, from: origin, metadata: ["path": "A.swift"]))
        store.apply(event(.gitCommit, session.id, at: 20, from: origin, metadata: ["revert": "true"]))
        store.endSession(session.id, at: origin.addingTimeInterval(40))

        #expect(store.history[0].outcome == .rolledBack)
    }

    @Test @MainActor
    func noWorkAndOnePromptIsAbandoned() {
        let origin = Date(timeIntervalSince1970: 9_000_000)
        let store = makeStore()
        let session = store.startSession(agent: .cursor, at: origin)
        store.apply(event(.promptSubmitted, session.id, at: 5, from: origin))
        store.endSession(session.id, at: origin.addingTimeInterval(30))

        #expect(store.history[0].outcome == .abandoned)
    }

    @Test @MainActor
    func userOverrideSticksAndIsMarked() {
        let origin = Date(timeIntervalSince1970: 10_000_000)
        let store = makeStore()
        let session = store.startSession(agent: .cursor, at: origin)
        store.apply(event(.promptSubmitted, session.id, at: 5, from: origin))
        store.endSession(session.id, at: origin.addingTimeInterval(30))
        store.setOutcome(.successful, for: session.id)

        #expect(store.history[0].outcome == .successful)
        #expect(store.history[0].outcomeProvenance == .userSet)
    }
}
