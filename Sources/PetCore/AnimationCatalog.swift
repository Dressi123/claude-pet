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
        case .idle: return [280, 110, 110, 140, 140, 320]
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

    /// How a row is played back.
    public enum Playback: Equatable {
        /// Flipbook: run the atlas's frame durations in order.
        case sequence
        /// Hold one pose for a few seconds, then cut to another at random.
        case pose
    }

    /// The status states are on screen for minutes at a time, so flipping their
    /// frames reads as frantic rather than busy. They hold a pose instead.
    /// Locomotion and the one-shots stay as flipbooks, because those are brief
    /// and the motion itself is the content.
    public var playback: Playback {
        switch self {
        case .idle, .running, .review, .waiting: return .pose
        case .runningRight, .runningLeft, .waving, .jumping, .failed: return .sequence
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
