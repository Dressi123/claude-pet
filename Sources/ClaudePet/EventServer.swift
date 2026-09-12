// Receives hook events over a Unix datagram socket.
//
// Datagrams mean the hook helper never blocks and never needs a listener to be
// present, which keeps a stopped pet from ever slowing down Claude Code.

import PetCore
import Foundation

final class EventServer {
    static func defaultSocketPath() -> String {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_PET_SOCKET"], !override.isEmpty {
            return override
        }
        return FileManager.default.homeDirectoryForCurrentUser.path + "/.claude-pet/pet.sock"
    }

    private let path: String
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?

    /// Called on the main queue for each decoded event.
    var onEvent: ((PetEvent) -> Void)?

    init(path: String = EventServer.defaultSocketPath()) {
        self.path = path
    }

    func start() throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        // A socket file left behind by a previous run blocks bind() and has to
        // go. But deleting one that a live pet is still listening on would
        // silently steal its address and leave that copy deaf, so probe first
        // and refuse to start when someone answers.
        if FileManager.default.fileExists(atPath: path) {
            if Self.isSocketLive(at: path) { throw ServerError.alreadyRunning }
            unlink(path)
        }

        fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw ServerError.socketFailed(errno) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let sunPathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < sunPathCapacity else {
            throw ServerError.pathTooLong(path)
        }
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: sunPathCapacity) { dst in
                strncpy(dst, path, sunPathCapacity - 1)
            }
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, size)
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            fd = -1
            throw ServerError.bindFailed(code)
        }

        // A burst of hook events must not be dropped while the UI is busy.
        var bufferSize: Int32 = 256 * 1024
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &bufferSize, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in self?.drain() }
        source.resume()
        self.source = source
    }

    /// Connects to the existing socket to see whether anything is bound to it.
    /// A stale file from a crashed run refuses the connection.
    private static func isSocketLive(at path: String) -> Bool {
        let probe = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard probe >= 0 else { return false }
        defer { close(probe) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < capacity else { return false }
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                strncpy(dst, path, capacity - 1)
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(probe, sa, size)
            }
        }
        // ECONNREFUSED means the file is stale; success means a pet is live.
        return result == 0
    }

    private func drain() {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
            guard count > 0 else { return }
            let data = Data(buffer[0..<count])
            guard
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                let event = PetEvent(json: json)
            else { continue }
            DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
        }
    }

    func stop() {
        source?.cancel()
        source = nil
        if fd >= 0 { close(fd) }
        fd = -1
        unlink(path)
    }

    enum ServerError: LocalizedError {
        case socketFailed(Int32)
        case bindFailed(Int32)
        case pathTooLong(String)
        case alreadyRunning

        var errorDescription: String? {
            switch self {
            case .socketFailed(let code):
                return "Could not create the event socket (errno \(code))."
            case .bindFailed(let code):
                return "Could not bind the event socket (errno \(code)). Another pet may already be running."
            case .pathTooLong(let path):
                return "Socket path is too long for a Unix socket: \(path)"
            case .alreadyRunning:
                return "Claude Pet is already running. This copy will now quit so the first one keeps working."
            }
        }
    }
}
