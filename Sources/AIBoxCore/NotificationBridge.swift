import Darwin
import Foundation

public struct BridgeReply: Codable {
    public let accepted: Bool
    public let visibleCount: Int
    public let error: String?

    public init(accepted: Bool, visibleCount: Int, error: String? = nil) {
        self.accepted = accepted
        self.visibleCount = visibleCount
        self.error = error
    }
}

public enum BridgeError: Error, LocalizedError {
    case system(String, Int32)
    case alreadyRunning
    case unexpectedSocketPath
    case noReply

    public var errorDescription: String? {
        switch self {
        case .system(let operation, let code):
            return "\(operation)：\(String(cString: strerror(code)))"
        case .alreadyRunning: return String(localized: "AIBox is already running.", bundle: AppLanguage.bundle)
        case .unexpectedSocketPath: return String(localized: "The notification socket path is occupied by another file.", bundle: AppLanguage.bundle)
        case .noReply: return String(localized: "No acknowledgment from AIBox. Make sure the app is running.", bundle: AppLanguage.bundle)
        }
    }
}

private enum LocalSocket {
    static var directory: String { "/tmp/aibox-mac-\(getuid())" }
    static var path: String { directory + "/notify.sock" }

    static func address() -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8) + [0]
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            target.copyBytes(from: bytes)
        }
        return address
    }

    static func descriptor(timed: Bool = true) throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BridgeError.system("socket", errno) }
        if timed { configureClient(fd) }
        return fd
    }

    static func configureClient(_ fd: Int32) {
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout.size(ofValue: noSigPipe)))
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    }

    static func connect(_ fd: Int32) -> Int32 {
        var address = address()
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    static func write(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw BridgeError.system("write", errno) }
                offset += count
            }
        }
    }

    static func read(from fd: Int32) throws -> Data {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count == 0 { return result }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw BridgeError.system("read", errno) }
            result.append(contentsOf: buffer.prefix(count))
        }
    }
}

public enum NotificationClient {
    public static func send(_ payload: Data) throws -> BridgeReply {
        let fd = try LocalSocket.descriptor()
        defer { Darwin.close(fd) }
        guard LocalSocket.connect(fd) == 0 else {
            throw BridgeError.system(String(localized: "Start AIBox first (connect)", bundle: AppLanguage.bundle), errno)
        }
        try LocalSocket.write(payload, to: fd)
        Darwin.shutdown(fd, SHUT_WR)
        let reply = try LocalSocket.read(from: fd)
        guard !reply.isEmpty else { throw BridgeError.noReply }
        return try JSONDecoder().decode(BridgeReply.self, from: reply)
    }
}

public final class NotificationServer {
    private var descriptor: Int32 = -1

    public init() {}

    public func start(handler: @escaping @MainActor (Data) -> BridgeReply) throws {
        let manager = FileManager.default
        try manager.createDirectory(atPath: LocalSocket.directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        var directoryInfo = stat()
        guard lstat(LocalSocket.directory, &directoryInfo) == 0,
              directoryInfo.st_uid == getuid(),
              directoryInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              directoryInfo.st_mode & 0o077 == 0 else {
            throw BridgeError.unexpectedSocketPath
        }

        var fileInfo = stat()
        if lstat(LocalSocket.path, &fileInfo) == 0 {
            guard fileInfo.st_uid == getuid(),
                  fileInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK) else {
                throw BridgeError.unexpectedSocketPath
            }
            let probe = try LocalSocket.descriptor()
            let connected = LocalSocket.connect(probe) == 0
            let connectionError = errno
            Darwin.close(probe)
            if connected { throw BridgeError.alreadyRunning }
            guard connectionError == ECONNREFUSED || connectionError == ENOENT else {
                throw BridgeError.system("connect", connectionError)
            }
            try manager.removeItem(atPath: LocalSocket.path)
        }

        let fd = try LocalSocket.descriptor(timed: false)
        var address = LocalSocket.address()
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            Darwin.close(fd)
            throw BridgeError.system("bind", code)
        }
        guard Darwin.listen(fd, 16) == 0 else {
            let code = errno
            Darwin.close(fd)
            try? manager.removeItem(atPath: LocalSocket.path)
            throw BridgeError.system("listen", code)
        }
        descriptor = fd
        DispatchQueue(label: "local.aibox.accept", qos: .utility).async {
            while true {
                let client = Darwin.accept(fd, nil, nil)
                if client < 0 && errno == EINTR { continue }
                guard client >= 0 else { break }
                LocalSocket.configureClient(client)
                DispatchQueue.global(qos: .utility).async {
                    defer { Darwin.close(client) }
                    do {
                        let payload = try LocalSocket.read(from: client)
                        guard !payload.isEmpty else { return }
                        let reply = DispatchQueue.main.sync {
                            MainActor.assumeIsolated { handler(payload) }
                        }
                        try LocalSocket.write(JSONEncoder().encode(reply), to: client)
                    } catch {
                        // Failure is returned through the socket; notification text is not logged.
                        let reply = BridgeReply(accepted: false, visibleCount: 0, error: String(localized: "Notification transfer failed.", bundle: AppLanguage.bundle))
                        if let encoded = try? JSONEncoder().encode(reply) {
                            try? LocalSocket.write(encoded, to: client)
                        }
                    }
                }
            }
        }
    }

    public func stop() {
        guard descriptor >= 0 else { return }
        Darwin.shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
        descriptor = -1
        try? FileManager.default.removeItem(atPath: LocalSocket.path)
    }
}
