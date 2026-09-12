// Wires the pet into Claude Code by adding hooks to ~/.claude/settings.json.
//
// Other hooks almost certainly live there already, so entries are appended to
// the existing arrays and never replace the `hooks` block. Every write is
// preceded by a timestamped backup.

import Foundation

enum HookInstaller {
    static let events = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "Notification",
        "SubagentStop",
        "Stop",
        "SessionEnd",
    ]

    /// `CLAUDE_PET_SETTINGS` points this at another file, which is the only way
    /// to exercise installing and removing hooks without editing the settings
    /// the machine is actually using. Same reason `CLAUDE_PET_SOCKET` exists.
    static var settingsURL: URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_PET_SETTINGS"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    /// The helper binary sits beside the app binary in the build output.
    static var helperPath: String {
        let appPath = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        return appPath.deletingLastPathComponent().appendingPathComponent("claude-pet-hook").path
    }

    /// Matches this app's hook wherever it was installed from, including a
    /// build that has since been moved or renamed. The helper's filename is the
    /// only stable part of the command: the path in front of it changes every
    /// time the app moves.
    private static func isOurs(_ command: String) -> Bool {
        Self.helperNames.contains { command.contains($0) }
    }

    /// The current helper, and the name it shipped under before the pet stopped
    /// having a name. An old entry has to be recognised to be replaced.
    private static let helperNames = ["claude-pet-hook", "mikkel-hook"]

    /// Claude Code runs a hook's command through a shell, and the app installs
    /// to "Claude Pet.app", so the path has a space in it. Written raw it would
    /// be read as a command plus arguments and every hook would fail. Single
    /// quotes are the one form no shell reinterprets, and the awkward closing
    /// dance escapes a quote inside the path itself.
    static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func install() throws -> String {
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            throw InstallError.helperMissing(helperPath)
        }
        var settings = try loadSettings()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let command = shellQuoted(helperPath)
        var added: [String] = []
        var replaced = 0

        for event in events {
            var matchers = hooks[event] as? [[String: Any]] ?? []
            // Drop any entry of ours first rather than skipping the event when
            // one is present. Skipping was why moving the app left a hook
            // pointing at where it used to be: the stale command still looked
            // like ours, so nothing was written and nothing said so.
            var stale = 0
            matchers = matchers.compactMap { matcher in
                var entries = matcher["hooks"] as? [[String: Any]] ?? []
                let before = entries.count
                entries.removeAll {
                    let existing = $0["command"] as? String ?? ""
                    return isOurs(existing) && existing != command
                }
                stale += before - entries.count
                if entries.isEmpty { return nil }
                var updated = matcher
                updated["hooks"] = entries
                return updated
            }
            replaced += stale

            let current = matchers.contains { matcher in
                let entries = matcher["hooks"] as? [[String: Any]] ?? []
                return entries.contains { ($0["command"] as? String) == command }
            }
            if !current {
                matchers.append([
                    "hooks": [["type": "command", "command": command, "timeout": 5]],
                ])
                added.append(event)
            }
            hooks[event] = matchers
        }

        guard !added.isEmpty || replaced > 0 else {
            return "Hooks were already installed. Nothing changed."
        }
        settings["hooks"] = hooks
        try writeSettings(settings)
        var message = added.isEmpty
            ? "Pet hooks were already there."
            : "Installed pet hooks for \(added.joined(separator: ", "))."
        if replaced > 0 {
            message += " Removed \(replaced) stale entr\(replaced == 1 ? "y" : "ies") from an earlier install."
        }
        return message + " Existing hooks were left in place."
    }

    static func uninstall() throws -> String {
        var settings = try loadSettings()
        guard var hooks = settings["hooks"] as? [String: Any] else {
            return "No hooks are configured. Nothing to remove."
        }
        var removed = 0

        for event in events {
            guard var matchers = hooks[event] as? [[String: Any]] else { continue }
            let before = matchers.count
            matchers = matchers.compactMap { matcher in
                var entries = matcher["hooks"] as? [[String: Any]] ?? []
                entries.removeAll { isOurs($0["command"] as? String ?? "") }
                if entries.isEmpty { return nil }
                var updated = matcher
                updated["hooks"] = entries
                return updated
            }
            removed += before - matchers.count
            if matchers.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = matchers }
        }

        guard removed > 0 else { return "No pet hooks found. Nothing changed." }
        settings["hooks"] = hooks
        try writeSettings(settings)
        return "Removed \(removed) pet hook entries."
    }

    static var isInstalled: Bool {
        guard
            let settings = try? loadSettings(),
            let hooks = settings["hooks"] as? [String: Any]
        else { return false }
        return hooks.values.contains { value in
            guard let matchers = value as? [[String: Any]] else { return false }
            return matchers.contains { matcher in
                let entries = matcher["hooks"] as? [[String: Any]] ?? []
                return entries.contains { isOurs($0["command"] as? String ?? "") }
            }
        }
    }

    private static func loadSettings() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL) else { return [:] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.unreadableSettings
        }
        return json
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        let url = settingsURL
        if FileManager.default.fileExists(atPath: url.path) {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("settings.json.claude-pet-backup-\(stamp)")
            try? FileManager.default.copyItem(at: url, to: backup)
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    enum InstallError: LocalizedError {
        case helperMissing(String)
        case unreadableSettings

        var errorDescription: String? {
            switch self {
            case .helperMissing(let path):
                return "The claude-pet-hook helper is not at \(path). Run `swift build -c release` first."
            case .unreadableSettings:
                return "~/.claude/settings.json is not valid JSON, so it was left untouched."
            }
        }
    }
}
