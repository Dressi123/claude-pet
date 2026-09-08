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

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    /// The helper binary sits beside the app binary in the build output.
    static var helperPath: String {
        let appPath = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        return appPath.deletingLastPathComponent().appendingPathComponent("mikkel-hook").path
    }

    private static func isOurs(_ command: String) -> Bool {
        command.contains("mikkel-hook")
    }

    static func install() throws -> String {
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            throw InstallError.helperMissing(helperPath)
        }
        var settings = try loadSettings()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var added: [String] = []

        for event in events {
            var matchers = hooks[event] as? [[String: Any]] ?? []
            let alreadyPresent = matchers.contains { matcher in
                let entries = matcher["hooks"] as? [[String: Any]] ?? []
                return entries.contains { isOurs($0["command"] as? String ?? "") }
            }
            if alreadyPresent { continue }
            matchers.append([
                "hooks": [["type": "command", "command": helperPath, "timeout": 5]],
            ])
            hooks[event] = matchers
            added.append(event)
        }

        guard !added.isEmpty else { return "Hooks were already installed. Nothing changed." }
        settings["hooks"] = hooks
        try writeSettings(settings)
        return "Installed pet hooks for \(added.joined(separator: ", ")). Existing hooks were left in place."
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
                .appendingPathComponent("settings.json.mikkel-backup-\(stamp)")
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
                return "The mikkel-hook helper is not at \(path). Run `swift build -c release` first."
            case .unreadableSettings:
                return "~/.claude/settings.json is not valid JSON, so it was left untouched."
            }
        }
    }
}
