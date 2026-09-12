import Darwin
import Foundation

public struct CodexHookStatus {
    public let eventName: String
    public let key: String
    public let currentHash: String
    public let command: String
    public let enabled: Bool
    public let trustStatus: String

    public var isActive: Bool { enabled && trustStatus == "trusted" }
}

public struct CodexHookConfiguration {
    public let filePath: String
    public let version: String
    public let hook: CodexHookStatus?
    public let permissionHook: CodexHookStatus?
    public let userInputHook: CodexHookStatus?
    public let hooksEnabled: Bool
    fileprivate let stopGroups: [[String: Any]]
    fileprivate let permissionGroups: [[String: Any]]
    fileprivate let userInputGroups: [[String: Any]]

    public var configuredHooks: [CodexHookStatus] { [hook, permissionHook, userInputHook].compactMap { $0 } }
    public var allConfigured: Bool { hook != nil && permissionHook != nil && userInputHook != nil }
    public var allActive: Bool { allConfigured && configuredHooks.allSatisfy(\.isActive) }
}

public struct CodexUsageWindow: Equatable {
    public let usedPercent: Int
    public let windowDurationMins: Int
    public let resetsAt: Date

    public var remainingPercent: Int {
        max(0, min(100, 100 - usedPercent))
    }
}

public struct CodexUsageSnapshot: Equatable {
    public let weekly: CodexUsageWindow?
    public let codex53Spark: CodexUsageWindow?

    init(rateLimitsResponse: [String: Any]) throws {
        let limits = rateLimitsResponse["rateLimitsByLimitId"] as? [String: Any] ?? [:]
        let weeklySource = (limits["codex"] as? [String: Any])
            ?? (rateLimitsResponse["rateLimits"] as? [String: Any])
        weekly = Self.window(from: weeklySource)

        let sparkSource = limits.first { key, value in
            guard let limit = value as? [String: Any] else { return false }
            let name = (limit["limitName"] as? String)?.lowercased() ?? ""
            return key == "codex_bengalfox" || name.contains("5.3-codex-spark")
        }?.value as? [String: Any]
        codex53Spark = Self.window(from: sparkSource)

        guard weekly != nil || codex53Spark != nil else {
            throw CodexSetupError.invalidResponse
        }
    }

    private static func window(from source: [String: Any]?) -> CodexUsageWindow? {
        guard let primary = source?["primary"] as? [String: Any],
              let usedPercent = integer(primary["usedPercent"]),
              let duration = integer(primary["windowDurationMins"]),
              let timestamp = integer(primary["resetsAt"]) else {
            return nil
        }
        return CodexUsageWindow(usedPercent: usedPercent,
                                windowDurationMins: duration,
                                resetsAt: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}

public enum CodexSetupError: LocalizedError {
    case unavailable(String)
    case hookChanged
    case invalidResponse
    case timeout
    case rpc(String)
    case overridden

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .hookChanged: return "Hook 定義已變更，請重新檢查並確認信任。"
        case .invalidResponse: return "無法讀取 Codex 的設定回應，未確認設定成功。"
        case .timeout: return "Codex 設定操作逾時，請重新開啟設定視窗確認結果。"
        case .rpc(let message): return "Codex 設定失敗：\(message)"
        case .overridden: return "設定被其他層級覆蓋，尚未完成 Hook 啟用。"
        }
    }
}

/// Uses Codex's config RPCs, leaving TOML parsing and targeted edits to Codex.
/// Call from a background queue: the short-lived app-server uses synchronous stdio.
public struct CodexConfigurationService {
    public static let userInputMatcher = "^(request_user_input|request_user_input_async)$"
    public let executableURL: URL
    public let helperURL: URL
    private let environment: [String: String]?

    public var hookCommand: String {
        "'" + helperURL.path.replacingOccurrences(of: "'", with: "'\"'\"'") + "' --hook"
    }

    public init(executableURL: URL, helperURL: URL, environment: [String: String]? = nil) {
        self.executableURL = executableURL
        self.helperURL = helperURL
        self.environment = environment
    }

    public func read() throws -> CodexHookConfiguration {
        let server = try makeServer()
        defer { server.close() }
        return try read(from: server)
    }

    public func readUsage() throws -> CodexUsageSnapshot {
        let server = try makeServer()
        defer { server.close() }
        return try server.readUsage()
    }

    /// Adds missing notification handlers, preserving existing handlers.
    /// Trust is a separate, explicitly reviewed action.
    public func configure(expected: CodexHookConfiguration) throws -> CodexHookConfiguration {
        let server = try makeServer()
        defer { server.close() }
        var edits: [[String: Any]] = []
        for (event, existing, original) in [("Stop", expected.hook, expected.stopGroups),
                                           ("PermissionRequest", expected.permissionHook, expected.permissionGroups),
                                           ("PreToolUse", expected.userInputHook, expected.userInputGroups)] {
            guard existing == nil else { continue }
            var groups = original
            var group: [String: Any] = ["hooks": [["type": "command", "command": hookCommand]]]
            if event == "PreToolUse" { group["matcher"] = Self.userInputMatcher }
            groups.append(group)
            edits.append(["keyPath": "hooks.\(event)", "value": groups, "mergeStrategy": "replace"])
        }
        if !edits.isEmpty { try write(server: server, expected: expected, edits: edits) }
        let result = try read(from: server)
        guard result.allConfigured else { throw CodexSetupError.invalidResponse }
        return result
    }

    /// Uses the same hooks.state fields as Codex's own hook-review UI.
    /// The caller must show the exact command and obtain approval first.
    public func trust(expected: CodexHookConfiguration) throws -> CodexHookConfiguration {
        guard expected.allConfigured, expected.configuredHooks.allSatisfy({ $0.command == hookCommand }) else {
            throw CodexSetupError.hookChanged
        }
        let server = try makeServer()
        defer { server.close() }
        let current = try read(from: server)
        guard current.allConfigured, current.version == expected.version,
              zip(current.configuredHooks, expected.configuredHooks).allSatisfy({ hook, reviewed in
                  hook.eventName == reviewed.eventName && hook.key == reviewed.key
                      && hook.currentHash == reviewed.currentHash
              }) else {
            throw CodexSetupError.hookChanged
        }
        if current.allActive { return current }
        let state = Dictionary(uniqueKeysWithValues: current.configuredHooks.filter { !$0.isActive }.map {
            ($0.key, ["enabled": true, "trusted_hash": $0.currentHash] as [String: Any])
        })
        try write(server: server, expected: current, edits: [
            ["keyPath": "hooks.state", "value": state, "mergeStrategy": "upsert"],
        ])
        let result = try read(from: server)
        guard result.allActive else { throw CodexSetupError.invalidResponse }
        return result
    }

    private func write(server: CodexConfigRPC, expected: CodexHookConfiguration,
                       edits: [[String: Any]]) throws {
        let response = try server.request("config/batchWrite", params: [
            "edits": edits,
            "filePath": expected.filePath, "expectedVersion": expected.version,
        ])
        if response["status"] as? String == "okOverridden" { throw CodexSetupError.overridden }
        guard response["status"] as? String == "ok" else { throw CodexSetupError.invalidResponse }
    }

    private func makeServer() throws -> CodexConfigRPC {
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw CodexSetupError.unavailable("找不到 App 內的 aibox-notify，請重新建置 AIBox。")
        }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw CodexSetupError.unavailable("找不到 Codex 設定程式，請確認 Codex App 已安裝。")
        }
        return try CodexConfigRPC(executableURL: executableURL, environment: environment)
    }

    private func read(from server: CodexConfigRPC) throws -> CodexHookConfiguration {
        let result = try server.request("config/read", params: ["includeLayers": true])
        guard let layers = result["layers"] as? [[String: Any]],
              let user = layers.first(where: { layer in
                  guard let name = layer["name"] as? [String: Any] else { return false }
                  return name["type"] as? String == "user" && !(name["profile"] is String)
              }),
              let name = user["name"] as? [String: Any],
              let file = name["file"] as? String,
              let version = user["version"] as? String,
              let config = user["config"] as? [String: Any] else {
            throw CodexSetupError.invalidResponse
        }
        let hooks = config["hooks"] as? [String: Any] ?? [:]
        let groups = hooks["Stop"] as? [[String: Any]] ?? []
        let permissionGroups = hooks["PermissionRequest"] as? [[String: Any]] ?? []
        let userInputGroups = hooks["PreToolUse"] as? [[String: Any]] ?? []
        if (hooks["Stop"] != nil && hooks["Stop"] as? [[String: Any]] == nil)
            || (hooks["PermissionRequest"] != nil && hooks["PermissionRequest"] as? [[String: Any]] == nil)
            || (hooks["PreToolUse"] != nil && hooks["PreToolUse"] as? [[String: Any]] == nil) {
            throw CodexSetupError.invalidResponse
        }
        let listed = try server.request("hooks/list", params: ["cwds": [URL(fileURLWithPath: file).deletingLastPathComponent().path]])
        guard let entries = listed["data"] as? [[String: Any]],
              let entry = entries.first, let metadata = entry["hooks"] as? [[String: Any]],
              let errors = entry["errors"] as? [[String: Any]] else { throw CodexSetupError.invalidResponse }
        if !errors.isEmpty { throw CodexSetupError.rpc("Codex 無法載入 Hooks，請先檢查既有 Hooks 設定。") }
        func status(event: String, metadataName: String) throws -> CodexHookStatus? {
            guard let matching = metadata.first(where: {
                $0["eventName"] as? String == metadataName && $0["command"] as? String == hookCommand
                    && $0["source"] as? String == "user"
                    && (event != "PreToolUse" || $0["matcher"] as? String == Self.userInputMatcher)
            }) else { return nil }
            guard let key = matching["key"] as? String,
                  let hash = matching["currentHash"] as? String,
                  let enabled = matching["enabled"] as? Bool,
                  let trustStatus = matching["trustStatus"] as? String else { throw CodexSetupError.invalidResponse }
            return CodexHookStatus(eventName: event, key: key, currentHash: hash, command: hookCommand,
                                   enabled: enabled, trustStatus: trustStatus)
        }
        let effective = result["config"] as? [String: Any] ?? [:]
        let features = effective["features"] as? [String: Any] ?? [:]
        return try CodexHookConfiguration(filePath: file, version: version,
                                      hook: status(event: "Stop", metadataName: "stop"),
                                      permissionHook: status(event: "PermissionRequest", metadataName: "permissionRequest"),
                                      userInputHook: status(event: "PreToolUse", metadataName: "preToolUse"),
                                      hooksEnabled: features["hooks"] as? Bool ?? true, stopGroups: groups,
                                      permissionGroups: permissionGroups, userInputGroups: userInputGroups)
    }
}

private final class CodexConfigRPC {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffered = Data()
    private var nextID = 0
    private var closed = false

    init(executableURL: URL, environment: [String: String]?) throws {
        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        // Do not log unrelated config, account details, or server startup diagnostics.
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForReading.closeFile()
        output.fileHandleForWriting.closeFile()
        // A child exiting early must be reported as an error, not terminate AIBox.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do {
            _ = try request("initialize", params: [
                "clientInfo": ["name": "aibox-mac", "title": "AIBox", "version": "0.1.0"],
                "capabilities": ["experimentalApi": true],
            ])
            try send(["method": "initialized"])
        } catch {
            close()
            throw error
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        try? output.fileHandleForReading.close()
    }

    deinit { close() }

    func request(_ method: String, params: [String: Any]) throws -> [String: Any] {
        nextID += 1
        let id = nextID
        try send(["id": id, "method": method, "params": params])
        let deadline = ProcessInfo.processInfo.systemUptime + 15
        while true {
            let line = try readLine(deadline: deadline)
            guard let response = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                throw CodexSetupError.invalidResponse
            }
            guard response["id"] as? Int == id else { continue }
            if let error = response["error"] as? [String: Any] {
                throw CodexSetupError.rpc(error["message"] as? String ?? "未知錯誤")
            }
            guard let result = response["result"] as? [String: Any] else {
                throw CodexSetupError.invalidResponse
            }
            return result
        }
    }

    func readUsage() throws -> CodexUsageSnapshot {
        try CodexUsageSnapshot(rateLimitsResponse: request("account/rateLimits/read", params: [:]))
    }

    private func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func readLine(deadline: TimeInterval) throws -> Data {
        while true {
            if let end = buffered.firstIndex(of: 0x0A) {
                let line = Data(buffered[..<end])
                buffered.removeSubrange(...end)
                return line
            }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw CodexSetupError.timeout }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor,
                                    events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(remaining * 1_000))
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else { throw CodexSetupError.timeout }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw CodexSetupError.invalidResponse }
            buffered.append(contentsOf: bytes.prefix(count))
        }
    }
}
