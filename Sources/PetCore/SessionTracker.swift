// Turns the stream of Claude Code hook events into one pet state.
//
// Several Claude Code sessions can be running at once, so each session keeps
// its own state and the pet shows whichever one most deserves attention.

import Foundation

public struct PetEvent {
    public let event: String
    public let sessionID: String?
    public let cwd: String?
    public let toolName: String?
    public let toolUseID: String?
    public let toolError: Bool
    public let summary: String?
    public let reason: String?
    public let entrypoint: String?
    /// Which `tool_input` field `summary` came from, so it can be phrased.
    public let summaryKind: Phrasebook.Detail
    /// Notification payloads carry their text here rather than in `tool_input`.
    public let message: String?

    /// True for a terminal session a person is watching. Headless `claude -p`
    /// runs report `sdk-cli`.
    public var isInteractive: Bool { entrypoint == nil || entrypoint == "cli" }

    public init?(json: [String: Any]) {
        guard let event = json["event"] as? String else { return nil }
        self.event = event
        sessionID = json["session_id"] as? String
        cwd = json["cwd"] as? String
        toolName = json["tool_name"] as? String
        toolUseID = json["tool_use_id"] as? String
        toolError = json["tool_error"] as? Bool ?? false
        summary = json["summary"] as? String
        reason = json["reason"] as? String
        entrypoint = json["entrypoint"] as? String
        summaryKind = (json["summary_kind"] as? String)
            .flatMap(Phrasebook.Detail.init(rawValue:)) ?? .none
        message = json["message"] as? String
    }
}

/// What a session is doing right now, plus the label for the speech bubble.
public struct SessionSnapshot {
    public var state: PetState = .idle
    public var oneShot: PetState?
    public var label: String = ""
    public var cwd: String = ""
    public var updatedAt = Date()

    public var projectName: String {
        cwd.isEmpty ? "" : (cwd as NSString).lastPathComponent
    }
}

public final class SessionTracker {
    public init() {}

    public private(set) var sessions: [String: SessionSnapshot] = [:]
    /// When false, headless `claude -p` sessions are ignored. Hooks that spawn
    /// their own Claude sessions would otherwise keep the pet permanently busy.
    public var followsBackgroundSessions = false {
        didSet { if oldValue != followsBackgroundSessions { dropIgnoredSessions() } }
    }
    private var ignoredSessions: Set<String> = []

    /// When set, the pet follows only this session and ignores the rest.
    /// Useful when several Claude Code windows are open and only one matters.
    public var pinnedSessionID: String? {
        didSet { if oldValue != pinnedSessionID { publish() } }
    }
    /// Tool calls that have started but not reported back, per session.
    private var outstandingTools: [String: Set<String>] = [:]

    /// Fires when the last session ends, so the pet can settle straight away
    /// instead of waiting out the idle timer. Only a real `SessionEnd` counts:
    /// a session that merely falls silent is handled by the timer, because it
    /// may well come back.
    public var onAllSessionsEnded: (() -> Void)?

    /// Fires whenever the aggregate state or label changes. The last argument
    /// is the name of the session the label came from, so the bubble can say
    /// who is talking when several Claude Code windows are open. It is empty
    /// only when there is nothing to show.
    public var onChange: ((PetState, PetState?, String, String) -> Void)?

    public var activeSessionCount: Int { sessions.count }

    /// Matches the wording the status menu uses for a session with no cwd.
    private static func displayName(_ snapshot: SessionSnapshot) -> String {
        snapshot.projectName.isEmpty ? "session" : snapshot.projectName
    }

    /// Read tools make him inspect; everything else makes him work.
    private static func state(forTool tool: String) -> PetState {
        switch tool {
        case "Read", "Grep", "Glob", "NotebookRead", "WebFetch", "WebSearch", "ToolSearch":
            return .review
        default:
            return .running
        }
    }

    public func handle(_ event: PetEvent) {
        let id = event.sessionID ?? "default"

        // A session's interactive-ness is known from its first event and does
        // not change, so remember the verdict for events that omit the field.
        if !event.isInteractive { ignoredSessions.insert(id) }
        if !followsBackgroundSessions, ignoredSessions.contains(id) { return }

        var snapshot = sessions[id] ?? SessionSnapshot()
        snapshot.updatedAt = Date()
        if let cwd = event.cwd { snapshot.cwd = cwd }

        switch event.event {
        case "SessionStart":
            snapshot.state = .idle
            snapshot.oneShot = .waving
            snapshot.label = Phrasebook.greeting()
            outstandingTools[id] = []

        case "UserPromptSubmit":
            settleUnfinishedTools(sessionID: id, into: &snapshot)
            snapshot.state = .running
            snapshot.label = Phrasebook.prompt(event.summary)

        case "PreToolUse":
            let tool = event.toolName ?? ""
            snapshot.state = Self.state(forTool: tool)
            snapshot.label = Phrasebook.working(
                tool: tool, detail: event.summaryKind, value: event.summary)
            if let toolID = event.toolUseID {
                outstandingTools[id, default: []].insert(toolID)
            }

        case "PostToolUse":
            if let toolID = event.toolUseID {
                outstandingTools[id]?.remove(toolID)
            }
            if event.toolError {
                snapshot.oneShot = .failed
                snapshot.label = Phrasebook.toolFailed()
            }
            // The pose set by PreToolUse stands until the next tool or the end
            // of the turn. Claude is still busy either way, and flipping back
            // here made a run of reads restart the animation twice per tool.

        case "Notification":
            let text = event.message ?? event.summary
            if Phrasebook.isIdlePrompt(text) {
                // Claude has finished and is waiting on you. That is the end of
                // the turn, not a request, so settle rather than ask.
                settleUnfinishedTools(sessionID: id, into: &snapshot)
                snapshot.state = .idle
                snapshot.label = ""
            } else {
                snapshot.state = .waiting
                snapshot.label = Phrasebook.needsYou(text)
            }

        case "SubagentStop":
            snapshot.oneShot = .jumping
            snapshot.label = Phrasebook.subagentDone()

        case "Stop":
            settleUnfinishedTools(sessionID: id, into: &snapshot)
            snapshot.state = .idle
            if snapshot.oneShot == nil { snapshot.label = Phrasebook.finished() }

        case "SessionEnd":
            sessions.removeValue(forKey: id)
            outstandingTools.removeValue(forKey: id)
            // Releasing the pin here stops a finished session from leaving the
            // pet permanently blank.
            if pinnedSessionID == id { pinnedSessionID = nil }
            publish()
            if sessions.isEmpty { onAllSessionsEnded?() }
            return

        default:
            break
        }

        sessions[id] = snapshot
        publish()
    }

    /// A tool call that never produced a `PostToolUse` failed. Claude Code does
    /// not emit `PostToolUse` for a failing tool, so the unmatched
    /// `tool_use_id` is the signal. Only checked at turn boundaries, where
    /// parallel tool calls cannot be mistaken for failures.
    private func settleUnfinishedTools(sessionID: String, into snapshot: inout SessionSnapshot) {
        guard let outstanding = outstandingTools[sessionID], !outstanding.isEmpty else { return }
        outstandingTools[sessionID] = []
        snapshot.oneShot = .failed
        snapshot.label = Phrasebook.toolsFailed(count: outstanding.count)
    }

    /// A session that has gone quiet for this long stops competing on state.
    /// Claude Code does not always send `SessionEnd`, so a session killed while
    /// asking for approval would otherwise sit at the top priority forever and
    /// freeze the pet on "needs you".
    public static let livelinessWindow: TimeInterval = 90

    /// Ages a session artificially. Tests only: the liveliness rules are
    /// time-based and cannot otherwise be exercised without sleeping.
    public func backdateForTesting(sessionID: String, to date: Date) {
        sessions[sessionID]?.updatedAt = date
    }

    /// Re-evaluates which session the pet should show. Called on a timer so a
    /// session that falls silent stops dominating even when nothing else is
    /// generating events.
    public func refresh() {
        pruneStaleSessions()
        publish()
    }

    /// Drops sessions whose Claude Code process died without a `SessionEnd`.
    public func pruneStaleSessions(olderThan interval: TimeInterval = 30 * 60) {
        let cutoff = Date().addingTimeInterval(-interval)
        let stale = sessions.filter { $0.value.updatedAt < cutoff }.map(\.key)
        guard !stale.isEmpty else { return }
        for id in stale {
            sessions.removeValue(forKey: id)
            outstandingTools.removeValue(forKey: id)
        }
        publish()
    }

    private func dropIgnoredSessions() {
        guard !followsBackgroundSessions else { return }
        for id in ignoredSessions where sessions[id] != nil {
            sessions.removeValue(forKey: id)
            outstandingTools.removeValue(forKey: id)
        }
        publish()
    }

    private func publish() {
        // Pinning overrides every other rule: show that session or nothing.
        if let pinned = pinnedSessionID {
            guard let snapshot = sessions[pinned] else {
                onChange?(.idle, nil, "", "")
                return
            }
            onChange?(snapshot.state, snapshot.oneShot, snapshot.label,
                      Self.displayName(snapshot))
            if snapshot.oneShot != nil { sessions[pinned]?.oneShot = nil }
            return
        }

        // A session that is still active always outranks one that has gone
        // quiet, whatever the two states are. Only then does state priority
        // decide, and recency breaks the remaining ties.
        let now = Date()
        func rank(_ s: SessionSnapshot) -> (Int, Int) {
            let live = now.timeIntervalSince(s.updatedAt) <= Self.livelinessWindow ? 1 : 0
            return (live, max(s.state.priority, s.oneShot?.priority ?? -1))
        }
        // Keep the key so the winner's one-shot can be consumed below.
        let winner = sessions.max { lhs, rhs in
            let l = rank(lhs.value), r = rank(rhs.value)
            if l != r { return l < r }
            return lhs.value.updatedAt < rhs.value.updatedAt
        }
        guard let winner else {
            onChange?(.idle, nil, "", "")
            return
        }
        onChange?(winner.value.state, winner.value.oneShot, winner.value.label,
                  Self.displayName(winner.value))

        // One-shots are edge-triggered: waving and jumping happen once, at the
        // moment they are announced. Consuming here stops a later, unrelated
        // publish from replaying a reaction the pet has already given.
        if winner.value.oneShot != nil {
            sessions[winner.key]?.oneShot = nil
        }
    }
}
