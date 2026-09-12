// claude-pet-hook: reads a Claude Code hook payload on stdin, forwards a compact
// event to the running pet over a Unix datagram socket, and always exits 0.
//
// Claude Code blocks a tool call when a PreToolUse hook exits non-zero, so this
// binary must never fail for any reason: no socket, no listener, bad JSON, and
// unreadable stdin all end the same way.

import Foundation

func socketPath() -> String {
    if let override = ProcessInfo.processInfo.environment["CLAUDE_PET_SOCKET"], !override.isEmpty {
        return override
    }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return home + "/.claude-pet/pet.sock"
}

/// Shortens a value for the speech bubble. Never carries file contents or
/// command output, only the small identifying strings from `tool_input`.
///
/// The kind travels with the value, because the pet phrases a file name quite
/// differently from a search pattern and cannot tell them apart afterwards.
func summary(event: String, payload: [String: Any]) -> (text: String, kind: String)? {
    func clip(_ s: String, _ n: Int = 90) -> String {
        let flat = s.split(whereSeparator: \.isNewline).joined(separator: " ")
        return flat.count <= n ? flat : String(flat.prefix(n - 1)) + "\u{2026}"
    }
    if event == "UserPromptSubmit" {
        return (payload["prompt"] as? String).map { (clip($0), "description") }
    }
    guard let input = payload["tool_input"] as? [String: Any] else { return nil }
    let fields = [
        ("description", "description"), ("command", "command"),
        ("file_path", "file"), ("notebook_path", "file"), ("path", "file"),
        ("pattern", "pattern"), ("url", "url"), ("query", "query"),
    ]
    for (key, kind) in fields {
        if let value = input[key] as? String, !value.isEmpty {
            // A full path is noise in a bubble; the file name is the useful part.
            let shown = kind == "file" ? (value as NSString).lastPathComponent : value
            return (clip(shown), kind)
        }
    }
    return nil
}

let stdinData = FileHandle.standardInput.readDataToEndOfFile()
guard
    let payload = (try? JSONSerialization.jsonObject(with: stdinData)) as? [String: Any],
    let event = payload["hook_event_name"] as? String
else {
    exit(0)
}

var message: [String: Any] = ["event": event, "at": Date().timeIntervalSince1970]
// `cli` is a terminal session a person is watching; `sdk-cli` is a headless
// `claude -p` run, which is how hooks and scripts spawn their own sessions.
if let entrypoint = ProcessInfo.processInfo.environment["CLAUDE_CODE_ENTRYPOINT"] {
    message["entrypoint"] = entrypoint
}
for key in ["session_id", "cwd", "tool_name", "tool_use_id", "permission_mode", "source", "reason", "message"] {
    if let value = payload[key] as? String { message[key] = value }
}
if let (text, kind) = summary(event: event, payload: payload) {
    message["summary"] = text
    message["summary_kind"] = kind
}

// Some tools report a failure inside `tool_response` instead of throwing, so
// the pet gets an immediate signal in addition to the unmatched-id rule.
if let response = payload["tool_response"] {
    if let dict = response as? [String: Any], dict["is_error"] as? Bool == true {
        message["tool_error"] = true
    } else if let text = response as? String, text.hasPrefix("Error") {
        message["tool_error"] = true
    }
}

guard let encoded = try? JSONSerialization.data(withJSONObject: message) else { exit(0) }

let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
guard fd >= 0 else { exit(0) }
defer { close(fd) }

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let path = socketPath()
// sun_path is 104 bytes on Darwin; a longer path can never be bound or reached.
let sunPathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
guard path.utf8.count < sunPathCapacity else { exit(0) }
_ = withUnsafeMutablePointer(to: &addr.sun_path) { raw in
    raw.withMemoryRebound(to: CChar.self, capacity: sunPathCapacity) { dst in
        strncpy(dst, path, sunPathCapacity - 1)
    }
}

let size = socklen_t(MemoryLayout<sockaddr_un>.size)
_ = encoded.withUnsafeBytes { bytes in
    withUnsafePointer(to: &addr) { addrPtr in
        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            sendto(fd, bytes.baseAddress, bytes.count, 0, sa, size)
        }
    }
}

exit(0)
