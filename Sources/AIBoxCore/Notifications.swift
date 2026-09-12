import Foundation

public struct TurnCompletion: Codable, Equatable {
    public let type: String
    public let threadID: String
    public let turnID: String
    public let lastAssistantMessage: String?
    public let toolName: String?
    public let permissionDescription: String?

    public init(type: String, threadID: String, turnID: String, lastAssistantMessage: String?,
                toolName: String? = nil, permissionDescription: String? = nil) {
        self.type = type
        self.threadID = threadID
        self.turnID = turnID
        self.lastAssistantMessage = lastAssistantMessage
        self.toolName = toolName
        self.permissionDescription = permissionDescription
    }

    enum CodingKeys: String, CodingKey {
        case type
        case threadID = "thread-id"
        case turnID = "turn-id"
        case lastAssistantMessage = "last-assistant-message"
        case toolName = "tool-name"
        case permissionDescription = "permission-description"
    }

    public var displayText: String {
        if type == "PermissionRequest" {
            let details = [toolName, permissionDescription].compactMap { value -> String? in
                guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return value
            }
            return ([eventLabel] + details).joined(separator: " · ")
        }
        guard let message = lastAssistantMessage,
              !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return eventLabel
        }
        return message
    }

    public var eventLabel: String {
        switch type {
        case "PermissionRequest": return "授權請求"
        case "UserInputRequest": return "等待回答"
        case "Stop": return "回覆停止"
        default: return "回覆已結束"
        }
    }

    public static func parse(_ data: Data) throws -> TurnCompletion? {
        struct Event: Decodable {
            let type: String?
            let hook_event_name: String?
        }
        let decoder = JSONDecoder()
        let event = try decoder.decode(Event.self, from: data)
        if let name = event.hook_event_name {
            if name == "PreToolUse" {
                struct InputHook: Decodable {
                    let tool_name: String
                    let session_id: String?
                    let turn_id: String?
                    let tool_input: Input?
                    struct Input: Decodable {
                        let questions: [Question]?
                        struct Question: Decodable {
                            let question: String?
                            let title: String?
                        }
                    }
                }
                // Only question tools are notifications; other PreToolUse calls are ignored.
                struct Tool: Decodable { let tool_name: String }
                let tool = try decoder.decode(Tool.self, from: data)
                guard tool.tool_name == "request_user_input" || tool.tool_name == "request_user_input_async" else { return nil }
                let hook = try decoder.decode(InputHook.self, from: data)
                guard let thread = hook.session_id, !thread.isEmpty,
                      let turn = hook.turn_id, !turn.isEmpty,
                      let questions = hook.tool_input?.questions, !questions.isEmpty else { return nil }
                let prompts = questions.compactMap { question -> String? in
                    let text = (question.question ?? question.title)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return text?.isEmpty == false ? text : nil
                }
                guard prompts.count == questions.count else { return nil }
                return TurnCompletion(type: "UserInputRequest", threadID: thread, turnID: turn,
                                      lastAssistantMessage: prompts.joined(separator: "\n"), toolName: hook.tool_name)
            }
            if name == "PermissionRequest" {
                struct PermissionHook: Decodable {
                    let session_id: String
                    let turn_id: String
                    let tool_name: String
                    let description: String?

                    enum CodingKeys: String, CodingKey { case session_id, turn_id, tool_name, tool_input }
                    enum InputKeys: String, CodingKey { case description }

                    init(from decoder: Decoder) throws {
                        let fields = try decoder.container(keyedBy: CodingKeys.self)
                        session_id = try fields.decode(String.self, forKey: .session_id)
                        turn_id = try fields.decode(String.self, forKey: .turn_id)
                        tool_name = try fields.decode(String.self, forKey: .tool_name)
                        // tool_input is any JSON value; only an optional string description is needed.
                        let input = try? fields.nestedContainer(keyedBy: InputKeys.self, forKey: .tool_input)
                        description = try? input?.decodeIfPresent(String.self, forKey: .description)
                    }
                }
                let hook = try decoder.decode(PermissionHook.self, from: data)
                return TurnCompletion(type: name, threadID: hook.session_id, turnID: hook.turn_id,
                                      lastAssistantMessage: nil, toolName: hook.tool_name,
                                      permissionDescription: hook.description)
            }
            guard name == "Stop" else { return nil }
            struct StopHook: Decodable {
                let session_id: String
                let turn_id: String
                let last_assistant_message: String?
            }
            let hook = try decoder.decode(StopHook.self, from: data)
            return TurnCompletion(type: "Stop", threadID: hook.session_id,
                                  turnID: hook.turn_id, lastAssistantMessage: hook.last_assistant_message)
        }
        guard event.type == "agent-turn-complete" || event.type == "Stop"
                || event.type == "PermissionRequest" || event.type == "UserInputRequest" else { return nil }
        return try decoder.decode(TurnCompletion.self, from: data)
    }
}

/// Stores the last 20 arrivals independently of the conversation menu's deduplication.
public final class NotificationPayloadLog {
    public struct Entry: Codable {
        public let receivedAt: Date
        public let payload: String
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AIBox/notification-payloads.json")
    }

    private let url: URL

    public init(url: URL = NotificationPayloadLog.defaultURL) {
        self.url = url
    }

    public func append(_ payload: Data, at date: Date = Date()) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var entries: [Entry] = []
        if FileManager.default.fileExists(atPath: url.path) {
            entries = try decoder.decode([Entry].self, from: Data(contentsOf: url))
        }
        entries.append(Entry(receivedAt: date, payload: String(decoding: payload, as: UTF8.self)))
        entries = Array(entries.suffix(20))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                               withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try encoder.encode(entries).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public struct ReceivedCompletion: Codable {
    public let id: UUID
    public let notification: TurnCompletion
    public let receivedAt: Date
}

/// Keeps the latest notification for each of the 20 most recently updated conversations.
/// Supply defaults to preserve records and opened state across app launches.
public final class CompletionHistory {
    private var records: [ReceivedCompletion] = []
    private var opened: Set<UUID> = []
    private let defaults: UserDefaults?
    private static let storageKey = "aibox.completionHistory"
    private struct Snapshot: Codable {
        let records: [ReceivedCompletion]
        let opened: Set<UUID>
    }

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.storageKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            records = Array(snapshot.records.suffix(20))
            opened = snapshot.opened.intersection(Set(records.map(\.id)))
        }
    }

    private func save() {
        guard let defaults,
              let data = try? JSONEncoder().encode(Snapshot(records: records, opened: opened)) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    public var recent: [ReceivedCompletion] {
        Array(records.reversed())
    }

    public var totalCount: Int { records.count }
    public var latestUnopened: ReceivedCompletion? { records.last { !opened.contains($0.id) } }

    public func markOpened(_ id: UUID) {
        if records.contains(where: { $0.id == id }) {
            opened.insert(id)
            save()
        }
    }

    public func receive(_ notification: TurnCompletion, at date: Date = Date()) {
        if let index = records.lastIndex(where: { $0.notification.threadID == notification.threadID }) {
            opened.remove(records[index].id)
            records.remove(at: index)
        }
        records.append(ReceivedCompletion(id: UUID(), notification: notification, receivedAt: date))
        if records.count > 20 {
            let removed = records.removeFirst()
            opened.remove(removed.id)
        }
        save()
    }
}
