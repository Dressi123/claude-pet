// The v2 Codex pet contract, transcribed. Cells are 192x208 in an 8-column by
// 11-row atlas: rows 0-8 are animation states, rows 9-10 are the 16 clockwise
// look directions. Frame durations are per-frame and deliberately uneven.

import Foundation

public enum PetState: String, CaseIterable {
    case idle
    case runningRight = "running-right"
    case runningLeft = "running-left"
    case waving
    case jumping
    case failed
    case waiting
    case running
    case review

    public var row: Int {
        switch self {
        case .idle: return 0
        case .runningRight: return 1
        case .runningLeft: return 2
        case .waving: return 3
        case .jumping: return 4
        case .failed: return 5
        case .waiting: return 6
        case .running: return 7
        case .review: return 8
        }
    }

    /// Milliseconds per frame. Length also defines how many columns are used.
    public var durations: [Int] {
        switch self {
        // Frames 1-4 are the blink and keep the atlas's own timing: a blink
        // slowed down stops being a blink and starts being drowsiness. The two
        // long frames either side of it are open-eyed holds, and they are much
        // longer than the contract's 280 and 320 because at those he blinked
        // about once a second, which reads as nervous.
        case .idle: return [800, 110, 110, 140, 140, 1000]
        case .runningRight, .runningLeft: return [120, 120, 120, 120, 120, 120, 120, 220]
        case .waving: return [140, 140, 140, 280]
        // A fuller eight-frame arc than the contract's five: settle, crouch,
        // launch, rise, peak, fall, land, recover. Quick through the air and
        // slower at either end, so the leap has some snap to it.
        case .jumping: return [150, 110, 90, 90, 130, 90, 110, 220]
        case .failed: return [140, 140, 140, 140, 140, 140, 140, 240]
        case .waiting: return [150, 150, 150, 150, 150, 260]
        case .running: return [120, 120, 120, 120, 120, 220]
        case .review: return [150, 150, 150, 150, 150, 280]
        }
    }

    public var frameCount: Int { durations.count }

    /// The row of closed-eye twins for this state's poses, when the sheet has
    /// one. Held poses are one still cell for seconds at a time, so without a
    /// twin he simply stares. Idle is absent on purpose: its blink is drawn
    /// into the loop itself.
    ///
    /// Rows are numbered by when the art arrived rather than by state order,
    /// because a row is only added once it is filled. An empty reserved row
    /// would draw nothing at all.
    public var blinkRow: Int? {
        switch self {
        case .running: return 14
        case .review: return 15
        case .waiting: return 16
        default: return nil
        }
    }

    /// How long this state's open-eyed holds last in total, which for the idle
    /// row is the gap between one blink and the next. Anything else that needs
    /// to blink at his natural rate takes it from here rather than inventing a
    /// number that then drifts away from this one.
    public var blinkIntervalMilliseconds: Int {
        durations.filter { $0 >= Self.holdFrameMilliseconds }.reduce(0, +)
    }

    /// A frame at least this long is him holding still rather than a step of a
    /// movement. Pace stretches the holds and leaves the movement alone, so a
    /// calmer pace means he blinks less often rather than blinking in slow
    /// motion, and a jump stays a jump at every setting.
    public static let holdFrameMilliseconds = 400

    /// How a row is played back.
    public enum Playback: Equatable {
        /// Flipbook: run the atlas's frame durations in order.
        case sequence
        /// Hold one pose for a few seconds, then cut to another at random.
        case pose
    }

    /// Working, inspecting and asking are on screen for minutes at a time and
    /// their cells really are six different poses, so flipping through them
    /// reads as frantic rather than busy. They hold a pose instead. So does a
    /// failure: its eight cells are eight ways of looking glum, and running
    /// them in order cycled the lot in about a second, which read as panic.
    ///
    /// Idle is the exception among the status rows, and it is worth saying why
    /// out loud, because it looks like an inconsistency. Its six cells are not
    /// six poses. They are one seated pose drawn six times, and cell 2 has the
    /// eyes closed: the row is an idle loop with a blink built into it, and the
    /// durations say so, a long hold either side of three short frames. Holding
    /// one cell of it threw the blink away and, worse, could park him with his
    /// eyes shut for three seconds. Played in order it does exactly what the
    /// art was drawn to do.
    ///
    /// Locomotion is a flipbook, and so are the one-shots that are movements in
    /// their own right: a wave and a jump are over in half a second and the
    /// movement *is* the content.
    public var playback: Playback {
        switch self {
        case .running, .review, .waiting, .failed: return .pose
        case .idle, .runningRight, .runningLeft, .waving, .jumping: return .sequence
        }
    }

    /// How long a one-shot that holds poses stays up before handing back. A
    /// flipbook one-shot ends when its frames run out, but a posed one has no
    /// frames to run out of, so it ends on a clock instead. Long enough to
    /// settle on a few different poses, and short enough that he is himself
    /// again before the bubble fades.
    public var poseOneShotDuration: TimeInterval? {
        switch self {
        case .failed: return 7.0
        default: return nil
        }
    }

    /// One-shot states play once and hand back to the resting state. Looping
    /// states repeat until something else replaces them.
    public var isOneShot: Bool {
        switch self {
        case .waving, .jumping, .failed: return true
        default: return false
        }
    }

    /// Higher wins when several Claude Code sessions are active at once.
    /// "Needs you" outranks "busy", which outranks "resting".
    public var priority: Int {
        switch self {
        case .waiting: return 100
        case .failed: return 90
        case .jumping: return 80
        case .running: return 60
        case .review: return 55
        case .runningRight, .runningLeft: return 50
        case .waving: return 30
        case .idle: return 0
        }
    }
}

public enum AtlasGeometry {
    public static let columns = 8
    /// The v2 contract's height. An atlas may carry one extra row beyond it.
    public static let contractRows = 11
    public static let cellWidth = 192
    public static let cellHeight = 208
    public static let lookDirectionCount = 16
    /// The atlas's dedicated front-facing frame, used when the pointer sits in
    /// the deadzone and for the menu bar icon.
    public static let neutralCell = (row: 0, column: 6)

    /// Fallback for an atlas without a sleep row: the idle blink, which at
    /// least reads calm. The lying-down frame in the failed row has the right
    /// posture but sad brows, so it reads dejected rather than asleep.
    public static let sleepingCell = (row: 0, column: 2)

    /// Look direction `index` (0 = up / 12 o'clock, clockwise in 22.5-degree
    /// steps) to its atlas cell. Row 9 holds 000-157.5, row 10 holds 180-337.5.
    public static func lookCell(index: Int) -> (row: Int, column: Int) {
        let i = ((index % lookDirectionCount) + lookDirectionCount) % lookDirectionCount
        return i < columns ? (9, i) : (10, i - columns)
    }

    /// Closed-eye twins of the look directions, so he can blink while watching
    /// the pointer. Split the same way `lookCell` is, which lets the two halves
    /// arrive separately: a sheet carrying only the first can still blink
    /// through 0-157.5 degrees rather than holding the feature back entirely.
    public static let firstLookBlinkRow = 12

    public static func lookBlinkCell(index: Int) -> (row: Int, column: Int) {
        let i = ((index % lookDirectionCount) + lookDirectionCount) % lookDirectionCount
        return i < columns
            ? (firstLookBlinkRow, i)
            : (firstLookBlinkRow + 1, i - columns)
    }
}

/// The sleep row, one past the v2 contract's eleven.
///
/// Sleeping is not one of the contract's states, so this lives outside
/// `PetState`: it is driven by inactivity rather than by anything Claude does,
/// and an atlas that stops at eleven rows simply falls back to a still pose.
public enum SleepRow {
    public static let row = 11

    /// He lowers himself from sitting into a curl, eyes closing. Plays once.
    public static let settle = [0, 1, 2, 3]
    public static let settleDurations = [420, 420, 460, 520]

    /// Breathing. Frame 7 repeats frame 4's pose, which lands as a natural
    /// pause at the bottom of the breath rather than a stutter.
    public static let breathe = [4, 5, 6, 7]
    public static let breatheDurations = [820, 700, 700, 820]
}
