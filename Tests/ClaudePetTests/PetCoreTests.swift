import XCTest
@testable import PetCore

final class AtlasGeometryTests: XCTestCase {
    func testAtlasMatchesTheV2Contract() {
        XCTAssertEqual(AtlasGeometry.columns * AtlasGeometry.cellWidth, 1536)
        XCTAssertEqual(AtlasGeometry.contractRows * AtlasGeometry.cellHeight, 2288)
        XCTAssertEqual(AtlasGeometry.lookDirectionCount, 16)
    }

    /// The settle has to end on the breathing loop's opening pose, or he jumps
    /// at the handover. Codex draws frame 3 and frame 4 identically for this.
    func testTheSleepRowIsShapedForASeamlessHandover() {
        XCTAssertEqual(SleepRow.settle.count, SleepRow.settleDurations.count)
        XCTAssertEqual(SleepRow.breathe.count, SleepRow.breatheDurations.count)
        XCTAssertEqual(SleepRow.settle.last! + 1, SleepRow.breathe.first!)
        let all = SleepRow.settle + SleepRow.breathe
        XCTAssertEqual(all, Array(0..<AtlasGeometry.columns), "the row must be used in order")
        XCTAssertEqual(SleepRow.row, AtlasGeometry.contractRows, "sleep sits past the contract")
    }

    func testEveryStateFitsItsRow() {
        for state in PetState.allCases {
            XCTAssertLessThanOrEqual(state.frameCount, AtlasGeometry.columns, "\(state) overflows its row")
            XCTAssertGreaterThan(state.frameCount, 0)
            XCTAssertTrue((0...8).contains(state.row))
            XCTAssertNotEqual(state.row, SleepRow.row)
        }
        // Rows 0-8 each belong to exactly one state.
        XCTAssertEqual(Set(PetState.allCases.map(\.row)).count, 9)
    }

    /// A state whose cells are a movement is animated; one whose cells are just
    /// different looks is held. Time on screen is not the whole story: the sad
    /// reaction is brief and still held, because its eight cells are eight ways
    /// of looking glum rather than eight steps of a motion.
    func testPlaybackModeMatchesWhetherTheCellsAreAMotion() {
        for state in [PetState.running, .review, .waiting, .failed] {
            XCTAssertEqual(state.playback, .pose, "\(state) should hold a pose")
        }
        for state in [PetState.runningRight, .runningLeft, .waving, .jumping] {
            XCTAssertEqual(state.playback, .sequence, "\(state) should animate")
        }
        // Idle's cells are one pose drawn six times with a blink in the middle,
        // so it is a loop, not a set of poses to pick from.
        XCTAssertEqual(PetState.idle.playback, .sequence,
                       "idle is an authored loop and must play through")
    }

    /// The idle loop is a blink between two holds, and Pace is applied per
    /// frame, so the split has to survive anyone editing the durations: the
    /// holds must stay above the threshold and the blink below it.
    func testTheIdleBlinkIsNotStretchedByPace() {
        let durations = PetState.idle.durations
        let holds = durations.filter { $0 >= PetState.holdFrameMilliseconds }
        let blink = durations.filter { $0 < PetState.holdFrameMilliseconds }
        XCTAssertEqual(holds.count, 2, "the loop is two open-eyed holds")
        XCTAssertEqual(blink.count, 4, "with the blink between them")
        // A movement must never be caught by the hold rule, or Pace would put
        // it back into slow motion.
        for state in [PetState.jumping, .waving, .runningRight, .runningLeft] {
            XCTAssertTrue(state.durations.allSatisfy { $0 < PetState.holdFrameMilliseconds },
                          "\(state) is a movement and must play at its own speed")
        }
    }

    /// The one that actually matters: every one-shot needs something to end it,
    /// or it pins the pet forever. An animated one ends when its frames run
    /// out; a held one has no frames to run out of, so it needs a clock.
    func testEveryOneShotHasSomethingToEndIt() {
        for state in PetState.allCases where state.isOneShot {
            if state.playback == .pose {
                XCTAssertNotNil(state.poseOneShotDuration,
                                "\(state) is held and plays once, so it needs a duration")
            }
        }
    }

    /// A duration on a state that is not a held one-shot would never be read,
    /// which makes it a lie about how that state behaves.
    func testOnlyHeldOneShotsCarryADuration() {
        for state in PetState.allCases where state.poseOneShotDuration != nil {
            XCTAssertTrue(state.isOneShot, "\(state) is not a one-shot")
            XCTAssertEqual(state.playback, .pose, "\(state) is animated, so its frames end it")
        }
    }

    /// The blink twins must line up index-for-index with the look cells, or he
    /// blinks facing a different way than he was looking.
    func testLookBlinkCellsMirrorTheLookDirections() {
        for index in 0..<AtlasGeometry.lookDirectionCount {
            let look = AtlasGeometry.lookCell(index: index)
            let blink = AtlasGeometry.lookBlinkCell(index: index)
            XCTAssertEqual(blink.column, look.column, "direction \(index) changed column")
            XCTAssertEqual(blink.row - look.row, AtlasGeometry.firstLookBlinkRow - 9,
                           "direction \(index) is not the same offset from its look row")
        }
        // The halves are meant to be shippable separately, so the first eight
        // must all live in the first blink row.
        for index in 0..<8 {
            XCTAssertEqual(AtlasGeometry.lookBlinkCell(index: index).row,
                           AtlasGeometry.firstLookBlinkRow)
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

final class PhrasebookTests: XCTestCase {
    /// The whole point: a tool name must never reach the bubble.
    func testNoToolNameEverLeaks() {
        let tools = ["Bash", "Read", "Edit", "Write", "Grep", "Glob",
                     "WebFetch", "WebSearch", "Agent", "Task", "TodoWrite",
                     "mcp__something__weird", "NotebookEdit"]
        for tool in tools {
            for detail in [Phrasebook.Detail.description, .command, .file, .pattern, .none] {
                let line = Phrasebook.working(tool: tool, detail: detail, value: "thing.swift")
                XCTAssertFalse(line.contains(tool), "\(tool) leaked into: \(line)")
                XCTAssertFalse(line.isEmpty)
            }
        }
    }

    func testAMissingSubjectStillReadsAsASentence() {
        for tool in ["Bash", "Read", "Grep", "Edit", "Unknown"] {
            let line = Phrasebook.working(tool: tool, detail: .none, value: nil)
            XCTAssertFalse(line.isEmpty)
            XCTAssertFalse(line.hasSuffix(" "), "dangling subject in: \(line)")
        }
    }

    /// A Bash description is written in the imperative for Claude, so it has to
    /// be folded into the pet's own sentence rather than shown raw.
    func testBashDescriptionBecomesFirstPerson() {
        let line = Phrasebook.working(tool: "Bash", detail: .description,
                                      value: "Stack the two bubble captures")
        XCTAssertEqual(line, "Let me stack the two bubble captures")
    }

    func testAcronymsAndProperNounsKeepTheirCapital() {
        XCTAssertEqual(Phrasebook.uncapitalised("GitHub the thing"), "GitHub the thing")
        XCTAssertEqual(Phrasebook.uncapitalised("API check"), "API check")
        XCTAssertEqual(Phrasebook.uncapitalised("Check the thing"), "check the thing")
    }

    /// Phrasing must not reword itself while one tool call is still running.
    func testPhrasingIsStableForTheSameSubject() {
        let first = Phrasebook.working(tool: "Read", detail: .file, value: "Atlas.swift")
        for _ in 0..<20 {
            XCTAssertEqual(Phrasebook.working(tool: "Read", detail: .file, value: "Atlas.swift"), first)
        }
    }

    func testDifferentSubjectsCanGetDifferentPhrasings() {
        let subjects = ["Atlas.swift", "PetView.swift", "main.swift", "README.md",
                        "EventServer.swift", "Package.swift", "bundle.sh"]
        let lines = Set(subjects.map {
            Phrasebook.working(tool: "Read", detail: .file, value: $0)
                .replacingOccurrences(of: $0, with: "X")
        })
        XCTAssertGreaterThan(lines.count, 1, "every subject got identical phrasing")
    }

    /// Claude Code notifies both when it needs a decision and when it has
    /// simply finished. Only the first is a request.
    func testAnIdleNoticeIsNotTreatedAsARequest() {
        XCTAssertTrue(Phrasebook.isIdlePrompt("Claude is waiting for your input"))
        XCTAssertTrue(Phrasebook.isIdlePrompt("Claude is idle"))
        XCTAssertFalse(Phrasebook.isIdlePrompt("Claude needs your permission to use Bash"))
        XCTAssertFalse(Phrasebook.isIdlePrompt(nil))
    }

    func testClaudesOwnWordingWinsForApprovals() {
        XCTAssertEqual(Phrasebook.needsYou("Claude needs your permission to use Bash"),
                       "Claude needs your permission to use Bash")
        XCTAssertEqual(Phrasebook.needsYou(nil), "I need you for this one")
        XCTAssertEqual(Phrasebook.needsYou(""), "I need you for this one")
    }
}

final class SessionTrackerTests: XCTestCase {
    private func event(_ name: String, session: String = "s", tool: String? = nil,
                       id: String? = nil, error: Bool = false,
                       entrypoint: String? = nil, message: String? = nil,
                       cwd: String? = nil) -> PetEvent {
        var json: [String: Any] = ["event": name, "session_id": session]
        if let cwd { json["cwd"] = cwd }
        if let tool { json["tool_name"] = tool }
        if let id { json["tool_use_id"] = id }
        if error { json["tool_error"] = true }
        if let entrypoint { json["entrypoint"] = entrypoint }
        if let message { json["message"] = message }
        return PetEvent(json: json)!
    }

    /// The fourth element is the session name the bubble puts in its header.
    private func capture(_ tracker: SessionTracker) -> () -> (PetState, PetState?, String, String) {
        var last: (PetState, PetState?, String, String) = (.idle, nil, "", "")
        tracker.onChange = { last = ($0, $1, $2, $3) }
        return { last }
    }

    func testTheBubbleIsToldWhichSessionIsSpeaking() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("SessionStart", session: "a", cwd: "/Users/x/code/claude-pet"))
        XCTAssertEqual(latest().3, "claude-pet", "the header names the session's project")

        // A session with no cwd still needs a header, and it has to match the
        // word the status menu uses for the same session.
        tracker.handle(event("SessionStart", session: "b"))
        XCTAssertEqual(latest().3, "session")
    }

    func testNothingToShowMeansNoHeader() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("SessionStart", session: "a", cwd: "/Users/x/code/claude-pet"))
        tracker.handle(event("SessionEnd", session: "a"))
        XCTAssertEqual(latest().3, "", "an empty bubble must not keep a stale name")
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
        tracker.onChange = { _, _, _, _ in }

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

        XCTAssertEqual(latest().2, "On it: fix the flaky test")
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
        tracker.onChange = { _, oneShot, _, _ in oneShots.append(oneShot) }

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
        tracker.onChange = { state, _, _, _ in states.append(state) }

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

    /// The reported bug: finishing a task left him asking for input, because
    /// the "waiting for your input" notice took the asking pose.
    func testFinishingDoesNotLeaveHimAsking() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("PreToolUse", tool: "Bash", id: "a", entrypoint: "cli"))
        tracker.handle(event("PostToolUse", tool: "Bash", id: "a", entrypoint: "cli"))
        tracker.handle(event("Stop", entrypoint: "cli"))
        tracker.handle(event("Notification", entrypoint: "cli",
                             message: "Claude is waiting for your input"))

        XCTAssertEqual(latest().0, .idle, "a finished turn is rest, not a request")
        XCTAssertEqual(latest().2, "")
    }

    func testARealApprovalStillAsks() {
        let tracker = SessionTracker()
        let latest = capture(tracker)

        tracker.handle(event("Notification", entrypoint: "cli",
                             message: "Claude needs your permission to use Bash"))

        XCTAssertEqual(latest().0, .waiting)
        XCTAssertEqual(latest().2, "Claude needs your permission to use Bash")
    }

    /// Closing the last session means there is nothing left to watch, so the
    /// pet should settle at once rather than wait out the idle timer.
    func testTheLastSessionEndingIsAnnounced() {
        let tracker = SessionTracker()
        tracker.onChange = { _, _, _, _ in }
        var announced = 0
        tracker.onAllSessionsEnded = { announced += 1 }

        tracker.handle(event("SessionStart", session: "a", entrypoint: "cli"))
        tracker.handle(event("SessionStart", session: "b", entrypoint: "cli"))

        tracker.handle(event("SessionEnd", session: "a", entrypoint: "cli"))
        XCTAssertEqual(announced, 0, "another session is still open")

        tracker.handle(event("SessionEnd", session: "b", entrypoint: "cli"))
        XCTAssertEqual(announced, 1)
    }

    /// A session that merely falls silent may still come back, so only a real
    /// SessionEnd should settle him early.
    func testGoingQuietDoesNotAnnounceTheEnd() {
        let tracker = SessionTracker()
        tracker.onChange = { _, _, _, _ in }
        var announced = 0
        tracker.onAllSessionsEnded = { announced += 1 }

        tracker.handle(event("PreToolUse", session: "a", tool: "Bash", id: "1", entrypoint: "cli"))
        tracker.backdateForTesting(
            sessionID: "a", to: Date().addingTimeInterval(-SessionTracker.livelinessWindow - 10))
        tracker.refresh()

        XCTAssertEqual(announced, 0)
    }

    func testAPayloadWithoutAnEventNameIsRejected() {
        XCTAssertNil(PetEvent(json: ["session_id": "s"]))
    }
}
