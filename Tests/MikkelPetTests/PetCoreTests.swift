import XCTest
@testable import PetCore

final class AtlasGeometryTests: XCTestCase {
    func testAtlasMatchesTheV2Contract() {
        XCTAssertEqual(AtlasGeometry.columns * AtlasGeometry.cellWidth, 1536)
        XCTAssertEqual(AtlasGeometry.rows * AtlasGeometry.cellHeight, 2288)
        XCTAssertEqual(AtlasGeometry.lookDirectionCount, 16)
    }

    func testEveryStateFitsItsRow() {
        for state in PetState.allCases {
            XCTAssertLessThanOrEqual(state.frameCount, AtlasGeometry.columns, "\(state) overflows its row")
            XCTAssertGreaterThan(state.frameCount, 0)
            XCTAssertTrue((0...8).contains(state.row))
        }
        // Rows 0-8 each belong to exactly one state.
        XCTAssertEqual(Set(PetState.allCases.map(\.row)).count, 9)
    }

    /// Long-lived status poses are held; brief, deliberate motion is animated.
    func testPlaybackModeMatchesHowLongAStateIsOnScreen() {
        for state in [PetState.idle, .running, .review, .waiting] {
            XCTAssertEqual(state.playback, .pose, "\(state) should hold a pose")
        }
        for state in [PetState.runningRight, .runningLeft, .waving, .jumping, .failed] {
            XCTAssertEqual(state.playback, .sequence, "\(state) should animate")
        }
    }

    /// Every one-shot is a real animation, never a held pose.
    func testOneShotsAreAlwaysAnimated() {
        for state in PetState.allCases where state.isOneShot {
            XCTAssertEqual(state.playback, .sequence, "\(state) plays once, so it must animate")
        }
    }

    func testLookDirectionsSplitAcrossRowsNineAndTen() {
        XCTAssertEqual(AtlasGeometry.lookCell(index: 0).row, 9)
        XCTAssertEqual(AtlasGeometry.lookCell(index: 0).column, 0)
        XCTAssertEqual(AtlasGeometry.lookCell(index: 7).row, 9)
        XCTAssertEqual(AtlasGeometry.lookCell(index: 8).row, 10)
        XCTAssertEqual(AtlasGeometry.lookCell(index: 8).column, 0)
        XCTAssertEqual(AtlasGeometry.lookCell(index: 15).row, 10)
        XCTAssertEqual(AtlasGeometry.lookCell(index: 15).column, 7)
    }

    func testLookIndexWrapsInBothDirections() {
        XCTAssertEqual(AtlasGeometry.lookCell(index: 16).column, AtlasGeometry.lookCell(index: 0).column)
        XCTAssertEqual(AtlasGeometry.lookCell(index: -1).column, AtlasGeometry.lookCell(index: 15).column)
    }
}

final class SessionTrackerTests: XCTestCase {
    private func event(_ name: String, session: String = "s", tool: String? = nil,
                       id: String? = nil, error: Bool = false,
                       entrypoint: String? = nil, message: String? = nil) -> PetEvent {
        var json: [String: Any] = ["event": name, "session_id": session]
        if let tool { json["tool_name"] = tool }
        if let id { json["tool_use_id"] = id }
        if error { json["tool_error"] = true }
        if let entrypoint { json["entrypoint"] = entrypoint }
        if let message { json["message"] = message }
        return PetEvent(json: json)!
    }

    private func capture(_ tracker: SessionTracker) -> () -> (PetState, PetState?, String) {
        var last: (PetState, PetState?, String) = (.idle, nil, "")
        tracker.onChange = { last = ($0, $1, $2) }
        return { last }
    }

    func testReadToolsMakeHimInspectAndOtherToolsMakeHimWork() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("PreToolUse", tool: "Read", id: "a"))
        XCTAssertEqual(latest().0, .review)

        tracker.handle(event("PreToolUse", tool: "Bash", id: "b"))
        XCTAssertEqual(latest().0, .running)
    }

    /// Claude Code emits no PostToolUse for a tool that fails, so an unmatched
    /// tool_use_id at a turn boundary is the only reliable failure signal.
    /// Verified against real hook payloads.
    func testUnmatchedToolIDAtStopIsTreatedAsAFailure() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("PreToolUse", tool: "Bash", id: "ok"))
        tracker.handle(event("PostToolUse", tool: "Bash", id: "ok"))
        tracker.handle(event("PreToolUse", tool: "Bash", id: "doomed"))
        tracker.handle(event("Stop"))

        XCTAssertEqual(latest().1, .failed)
    }

    func testCompletedToolsDoNotLookLikeFailures() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("PreToolUse", tool: "Bash", id: "a"))
        tracker.handle(event("PostToolUse", tool: "Bash", id: "a"))
        tracker.handle(event("Stop"))

        XCTAssertNil(latest().1)
        XCTAssertEqual(latest().0, .idle)
    }

    func testParallelToolCallsAllResolveWithoutAFalseFailure() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("PreToolUse", tool: "Read", id: "a"))
        tracker.handle(event("PreToolUse", tool: "Read", id: "b"))
        tracker.handle(event("PostToolUse", tool: "Read", id: "b"))
        tracker.handle(event("PostToolUse", tool: "Read", id: "a"))
        tracker.handle(event("Stop"))

        XCTAssertNil(latest().1)
    }

    func testAnExplicitToolErrorReactsImmediately() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("PreToolUse", tool: "Edit", id: "a"))
        tracker.handle(event("PostToolUse", tool: "Edit", id: "a", error: true))

        XCTAssertEqual(latest().1, .failed)
    }

    func testTheSessionNeedingAttentionWinsOverTheBusyOne() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("PreToolUse", session: "busy", tool: "Bash", id: "a"))
        tracker.handle(event("Notification", session: "blocked"))

        XCTAssertEqual(latest().0, .waiting)
    }

    func testEndingASessionFallsBackToTheRemainingOne() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("PreToolUse", session: "one", tool: "Bash", id: "a"))
        tracker.handle(event("Notification", session: "two"))
        XCTAssertEqual(latest().0, .waiting)

        tracker.handle(event("SessionEnd", session: "two"))
        XCTAssertEqual(latest().0, .running)
        XCTAssertEqual(tracker.activeSessionCount, 1)
    }

    func testLastSessionLeavingReturnsHimToIdle() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("PreToolUse", session: "one", tool: "Bash", id: "a"))
        tracker.handle(event("SessionEnd", session: "one"))

        XCTAssertEqual(latest().0, .idle)
        XCTAssertEqual(tracker.activeSessionCount, 0)
    }

    func testStalePrunerDropsSessionsThatDiedWithoutSayingGoodbye() {
        let tracker = SessionTracker()
        tracker.onChange = { _, _, _ in }

        tracker.handle(event("PreToolUse", session: "ghost", tool: "Bash", id: "a"))
        XCTAssertEqual(tracker.activeSessionCount, 1)

        tracker.pruneStaleSessions(olderThan: -1)
        XCTAssertEqual(tracker.activeSessionCount, 0)
    }

    func testPromptTextBecomesTheSpeechBubble() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        var json: [String: Any] = ["event": "UserPromptSubmit", "session_id": "s"]
        json["summary"] = "fix the flaky test"
        tracker.handle(PetEvent(json: json)!)

        XCTAssertEqual(latest().2, "fix the flaky test")
        XCTAssertEqual(latest().0, .running)
    }

    /// Notification text arrives in `message`, not in `tool_input`, so it needs
    /// its own path to the speech bubble.
    func testNotificationTextReachesTheBubble() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("Notification", message: "Claude needs your permission to use Bash"))

        XCTAssertEqual(latest().0, .waiting)
        XCTAssertEqual(latest().2, "Claude needs your permission to use Bash")
    }

    /// Headless `claude -p` runs report entrypoint `sdk-cli`. The user's own
    /// Stop hooks spawn those, which would otherwise pin the pet to busy.
    func testHeadlessSessionsAreIgnoredByDefault() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("PreToolUse", session: "bg", tool: "Bash", id: "a", entrypoint: "sdk-cli"))

        XCTAssertEqual(latest().0, .idle)
        XCTAssertEqual(tracker.activeSessionCount, 0)
    }

    func testInteractiveSessionsAreAlwaysFollowed() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("PreToolUse", session: "fg", tool: "Bash", id: "a", entrypoint: "cli"))

        XCTAssertEqual(latest().0, .running)
    }

    /// Only the first event of a session carries the entrypoint reliably, so
    /// the verdict has to stick for every later event from that session.
    func testAnIgnoredSessionStaysIgnoredOnLaterEvents() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("SessionStart", session: "bg", entrypoint: "sdk-cli"))
        tracker.handle(event("Notification", session: "bg"))

        XCTAssertEqual(latest().0, .idle)
    }

    func testEnablingBackgroundSessionsLetsThemThrough() {
        let tracker = SessionTracker()
        let latest = capture(tracker)
        tracker.followsBackgroundSessions = true

        tracker.handle(event("PreToolUse", session: "bg", tool: "Bash", id: "a", entrypoint: "sdk-cli"))

        XCTAssertEqual(latest().0, .running)
    }

    func testDisablingBackgroundSessionsDropsTheOnesAlreadyTracked() {
        let tracker = SessionTracker()
        let latest = capture(tracker)
        tracker.followsBackgroundSessions = true
        tracker.handle(event("PreToolUse", session: "bg", tool: "Bash", id: "a", entrypoint: "sdk-cli"))
        XCTAssertEqual(latest().0, .running)

        tracker.followsBackgroundSessions = false

        XCTAssertEqual(latest().0, .idle)
        XCTAssertEqual(tracker.activeSessionCount, 0)
    }

    /// A wave or a jump should play once. An unrelated later event must not
    /// make the pet repeat a reaction it has already given.
    func testAOneShotIsNotReplayedByALaterUnrelatedEvent() {
        let tracker = SessionTracker()
        var oneShots: [PetState?] = []
        tracker.onChange = { _, oneShot, _ in oneShots.append(oneShot) }

        tracker.handle(event("SessionStart", session: "a", entrypoint: "cli"))
        XCTAssertEqual(oneShots.last, .waving)

        tracker.handle(event("PreToolUse", session: "a", tool: "Bash", id: "t", entrypoint: "cli"))
        tracker.handle(event("PostToolUse", session: "a", tool: "Bash", id: "t", entrypoint: "cli"))

        XCTAssertEqual(oneShots.filter { $0 == .waving }.count, 1)
    }

    /// A finished tool must not knock the pose back to "working". A run of
    /// reads should stay in one pose instead of alternating twice per tool.
    func testARunOfReadsStaysInOnePose() {
        let tracker = SessionTracker()
        var states: [PetState] = []
        tracker.onChange = { state, _, _ in states.append(state) }

        for i in 0..<4 {
            tracker.handle(event("PreToolUse", tool: "Read", id: "r\(i)", entrypoint: "cli"))
            tracker.handle(event("PostToolUse", tool: "Read", id: "r\(i)", entrypoint: "cli"))
        }

        XCTAssertEqual(Set(states), [.review])
    }

    /// The bug this pins: a session killed while asking for approval kept
    /// priority 100 forever and froze the pet, ignoring the session actually
    /// being used. A live session must outrank a silent one whatever the states.
    func testALiveSessionOutranksAStrandedWaitingOne() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("Notification", session: "stranded", entrypoint: "cli"))
        XCTAssertEqual(latest().0, .waiting)

        // Backdate the stranded session past the liveliness window, as though
        // its Claude Code process died without sending SessionEnd.
        tracker.backdateForTesting(
            sessionID: "stranded",
            to: Date().addingTimeInterval(-SessionTracker.livelinessWindow - 10))

        tracker.handle(event("PreToolUse", session: "active", tool: "Bash", id: "a", entrypoint: "cli"))

        XCTAssertEqual(latest().0, .running, "the session being used must win")
    }

    /// A genuine approval prompt should still win while its session is alive.
    func testARecentWaitingSessionStillWins() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("PreToolUse", session: "busy", tool: "Bash", id: "a", entrypoint: "cli"))
        tracker.handle(event("Notification", session: "asking", entrypoint: "cli"))

        XCTAssertEqual(latest().0, .waiting)
    }

    func testRefreshDemotesASessionThatHasGoneSilent() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("Notification", session: "stranded", entrypoint: "cli"))
        tracker.handle(event("PreToolUse", session: "active", tool: "Bash", id: "a", entrypoint: "cli"))
        tracker.backdateForTesting(
            sessionID: "stranded",
            to: Date().addingTimeInterval(-SessionTracker.livelinessWindow - 10))

        tracker.refresh()

        XCTAssertEqual(latest().0, .running)
    }

    func testPinningFollowsOnlyThatSession() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("PreToolUse", session: "a", tool: "Read", id: "1", entrypoint: "cli"))
        tracker.pinnedSessionID = "a"

        // A higher-priority event elsewhere must not steal the pet.
        tracker.handle(event("Notification", session: "b", entrypoint: "cli"))

        XCTAssertEqual(latest().0, .review, "pinned session a should still be shown")
    }

    func testPinnedSessionEndingReleasesThePin() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("PreToolUse", session: "a", tool: "Bash", id: "1", entrypoint: "cli"))
        tracker.pinnedSessionID = "a"
        tracker.handle(event("Notification", session: "b", entrypoint: "cli"))
        XCTAssertEqual(latest().0, .running)

        tracker.handle(event("SessionEnd", session: "a", entrypoint: "cli"))

        XCTAssertNil(tracker.pinnedSessionID)
        XCTAssertEqual(latest().0, .waiting, "should fall back to the other session")
    }

    func testUnpinningRestoresNormalPriority() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("PreToolUse", session: "a", tool: "Bash", id: "1", entrypoint: "cli"))
        tracker.handle(event("Notification", session: "b", entrypoint: "cli"))
        tracker.pinnedSessionID = "a"
        XCTAssertEqual(latest().0, .running)

        tracker.pinnedSessionID = nil

        XCTAssertEqual(latest().0, .waiting)
    }

    func testAPayloadWithoutAnEventNameIsRejected() {
        XCTAssertNil(PetEvent(json: ["session_id": "s"]))
    }
}
