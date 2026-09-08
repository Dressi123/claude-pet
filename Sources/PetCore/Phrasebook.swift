// Turns Claude Code's tool traffic into something Mikkel would actually say.
//
// Two rules. Never show a tool name, because "Bash:" is machinery and reads
// like a log line. And never show the private description verbatim, because it
// is written in the imperative for Claude's own benefit, not for a reader.
//
// His brief asks for curious, precise and calm, so the lines stay short and
// never gush.

import Foundation

public enum Phrasebook {
    /// Which field of `tool_input` the hook pulled the value from. Knowing this
    /// is what lets a file name read differently from a search pattern.
    public enum Detail: String {
        case description, command, file, pattern, url, query, none
    }

    // MARK: - Working

    public static func working(tool: String?, detail: Detail, value: String?) -> String {
        let subject = (value?.isEmpty == false) ? value! : nil

        switch tool {
        case "Read", "NotebookRead":
            guard let subject else { return "Having a read" }
            return pick(["Let me look at \(subject)",
                         "Reading \(subject)",
                         "Having a look at \(subject)"], seed: subject)

        case "Edit", "Write", "NotebookEdit", "MultiEdit":
            guard let subject else { return "Making a change" }
            return pick(["Tidying up \(subject)",
                         "Working on \(subject)",
                         "Editing \(subject)"], seed: subject)

        case "Grep":
            guard let subject else { return "Searching around" }
            return pick(["Hunting for \(subject)",
                         "Searching for \(subject)",
                         "Digging around for \(subject)"], seed: subject)

        case "Glob":
            guard let subject else { return "Looking around" }
            return "Looking for \(subject)"

        case "WebFetch", "WebSearch":
            guard let subject else { return "Off to read the docs" }
            return pick(["Off to read \(subject)",
                         "Looking up \(subject)"], seed: subject)

        case "Agent", "Task":
            return "Sending a helper off"

        case "TodoWrite":
            return "Keeping track of the plan"

        case "Bash":
            switch detail {
            case .description:
                guard let subject else { return "Running something" }
                return "Let me \(uncapitalised(subject))"
            case .command:
                guard let subject else { return "Running something" }
                return "Running \(subject)"
            default:
                return "Running something"
            }

        default:
            // An unknown or MCP tool. Say something honest rather than guess.
            guard let subject else { return "Working on it" }
            return "Working on \(subject)"
        }
    }

    // MARK: - Everything else

    public static func greeting() -> String { "Hi there" }

    public static func finished() -> String {
        pick(["All done", "That's done", "Finished"], seed: "\(Int(Date().timeIntervalSince1970) / 60)")
    }

    public static func prompt(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "On it" }
        return "On it: \(text)"
    }

    public static func needsYou(_ message: String?) -> String {
        // Claude's own wording says what it needs, which beats anything of ours.
        guard let message, !message.isEmpty else { return "I need you for this one" }
        return message
    }

    public static func toolFailed() -> String {
        pick(["Hm, that didn't work", "That didn't go through", "That one failed"],
             seed: "\(Int(Date().timeIntervalSince1970) / 60)")
    }

    public static func toolsFailed(count: Int) -> String {
        count == 1 ? toolFailed() : "\(count) of those failed"
    }

    public static func subagentDone() -> String { "My helper's finished" }

    // MARK: - Helpers

    /// Lowers the first letter so a description can follow "Let me". Left alone
    /// for an acronym or a proper noun, where "let me GitHub" would be wrong.
    static func uncapitalised(_ s: String) -> String {
        guard let first = s.first, first.isUppercase else { return s }
        // "API", "GitHub": another capital anywhere in the first word means a
        // real name, and lowering it would be wrong.
        let firstWord = s.prefix { !$0.isWhitespace }
        if firstWord.dropFirst().contains(where: \.isUppercase) { return s }
        return first.lowercased() + s.dropFirst()
    }

    /// Stable across launches and across repeats of the same subject, so the
    /// bubble never rewords itself while one tool call is still running.
    /// Swift's own hashing is seeded per process and cannot be used here.
    static func pick(_ options: [String], seed: String) -> String {
        guard let first = options.first else { return "" }
        guard options.count > 1 else { return first }
        var hash: UInt64 = 5381
        for byte in seed.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return options[Int(hash % UInt64(options.count))]
    }
}
