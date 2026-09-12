import Foundation
import XCTest
@testable import AIBoxCore

final class NotificationTests: XCTestCase {
    func testQuestionHooksPreservePromptsAndConversationAcrossBridgeAndHistory() throws {
        for (tool, field) in [("request_user_input", "question"), ("request_user_input_async", "title")] {
            let payload = Data("""
            {"hook_event_name":"PreToolUse","session_id":"questions-thread","turn_id":"questions-turn",
             "tool_name":"\(tool)","tool_input":{"questions":[
                {"\(field)":"選擇方案？📦","options":[]},{"\(field)":"第二個問題"}]}}
            """.utf8)
            let question = try XCTUnwrap(TurnCompletion.parse(payload))
            XCTAssertEqual(question.type, "UserInputRequest")
            XCTAssertEqual(question.threadID, "questions-thread")
            XCTAssertEqual(question.turnID, "questions-turn")
            XCTAssertEqual(question.eventLabel, "等待回答")
            XCTAssertEqual(question.displayText, "選擇方案？📦\n第二個問題")
            XCTAssertEqual(question, try TurnCompletion.parse(JSONEncoder().encode(question)))
            let history = CompletionHistory()
            history.receive(question)
            XCTAssertEqual(history.latestUnopened?.notification, question)
        }
    }

    func testOnlyQuestionToolsWithQuestionsBecomeAlerts() throws {
        for name in ["Bash", "mcp__other__request_user_input", "request_user_input_extra"] {
            XCTAssertNil(try TurnCompletion.parse(Data("""
            {"hook_event_name":"PreToolUse","tool_name":"\(name)","tool_input":"not a question"}
            """.utf8)))
        }
        for input in ["{}", "{\"questions\":[]}", "{\"questions\":[{\"title\":\" \"}]}"] {
            XCTAssertNil(try TurnCompletion.parse(Data("""
            {"hook_event_name":"PreToolUse","tool_name":"request_user_input_async",
             "session_id":"t","turn_id":"r","tool_input":\(input)}
            """.utf8)))
        }
    }

    func testHistoryRestoresLatestTwentyAndOpenedState() throws {
        let suite = "AIBoxHistoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = CompletionHistory(defaults: defaults)
        for number in 1...22 {
            history.receive(try XCTUnwrap(TurnCompletion.parse(payload(thread: "thread-\(number)", turn: number))),
                            at: Date(timeIntervalSince1970: Double(number)))
        }
        let newest = try XCTUnwrap(history.latestUnopened)
        history.markOpened(newest.id)

        let restored = CompletionHistory(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertEqual(restored.recent.map(\.id), history.recent.map(\.id))
        XCTAssertEqual(restored.recent.map(\.notification), history.recent.map(\.notification))
        XCTAssertEqual(restored.recent.map(\.receivedAt), history.recent.map(\.receivedAt))
        XCTAssertEqual(restored.totalCount, 20)
        XCTAssertEqual(restored.recent.last?.notification.threadID, "thread-3")
        XCTAssertEqual(restored.latestUnopened?.notification.threadID, "thread-21")

        restored.receive(try XCTUnwrap(TurnCompletion.parse(payload(thread: "thread-22", turn: 23))))
        let updated = CompletionHistory(defaults: defaults)
        XCTAssertEqual(updated.totalCount, 20)
        XCTAssertEqual(updated.latestUnopened?.notification.turnID, "turn-23")
        XCTAssertNotEqual(updated.latestUnopened?.id, newest.id)
        for record in updated.recent { updated.markOpened(record.id) }
        XCTAssertNil(CompletionHistory(defaults: defaults).latestUnopened)

        let data = try XCTUnwrap(defaults.data(forKey: "aibox.completionHistory"))
        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((stored["records"] as? [Any])?.count, 20)
        XCTAssertEqual((stored["opened"] as? [Any])?.count, 20)
    }

    func testPayloadLogPreservesFullInputAcrossRestartAndKeepsTwentyArrivals() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("payloads.json")
        let raw = #"{ "hook_event_name":"PermissionRequest", "session_id":"same", "turn_id":"r", "tool_name":"Bash", "tool_input":{"command":"echo test","extra":[1,true,null]}, "unknown":"📦" }"# + "\n"
        let log = NotificationPayloadLog(url: url)
        for index in 0..<21 {
            try log.append(Data(raw.utf8), at: Date(timeIntervalSince1970: Double(index)))
        }
        // A new instance must retain entries written by the previous process.
        try NotificationPayloadLog(url: url).append(Data(raw.utf8), at: Date(timeIntervalSince1970: 21))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([NotificationPayloadLog.Entry].self, from: Data(contentsOf: url))
        XCTAssertEqual(entries.count, 20)
        XCTAssertEqual(entries.first?.receivedAt, Date(timeIntervalSince1970: 2))
        XCTAssertEqual(entries.last?.receivedAt, Date(timeIntervalSince1970: 21))
        XCTAssertTrue(entries.allSatisfy { $0.payload == raw })
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int, 0o600)
    }

    func testStopHookUsesSessionAndTurnIdentifiers() throws {
        let data = Data(#"{"hook_event_name":"Stop","session_id":"thread-hook","turn_id":"turn-hook","last_assistant_message":"完成了 📦","stop_hook_active":false}"#.utf8)
        let result = try XCTUnwrap(TurnCompletion.parse(data))
        XCTAssertEqual(result.threadID, "thread-hook")
        XCTAssertEqual(result.turnID, "turn-hook")
        XCTAssertEqual(result.type, "Stop")
        XCTAssertEqual(result.displayText, "完成了 📦")
        XCTAssertEqual(result, try TurnCompletion.parse(JSONEncoder().encode(result)))
    }

    func testStopHookMissingMessageHasAccurateFallback() throws {
        let data = Data(#"{"hook_event_name":"Stop","session_id":"t","turn_id":"r"}"#.utf8)
        XCTAssertEqual(try TurnCompletion.parse(data)?.displayText, "回覆停止")
    }

    func testOtherHooksAreIgnoredAndMissingIDsFail() throws {
        XCTAssertNil(try TurnCompletion.parse(Data(#"{"hook_event_name":"PostToolUse"}"#.utf8)))
        XCTAssertThrowsError(try TurnCompletion.parse(Data(#"{"hook_event_name":"Stop","session_id":"t"}"#.utf8)))
    }

    func testPermissionRequestPreservesIdentityToolAndReasonAcrossBridge() throws {
        let data = Data(#"{"hook_event_name":"PermissionRequest","session_id":"permission-thread","turn_id":"permission-turn","tool_name":"Bash","tool_input":{"command":"do not copy raw command","description":"允許讀取？📦\n第二行"}}"#.utf8)
        let result = try XCTUnwrap(TurnCompletion.parse(data))
        XCTAssertEqual(result.type, "PermissionRequest")
        XCTAssertEqual(result.threadID, "permission-thread")
        XCTAssertEqual(result.turnID, "permission-turn")
        XCTAssertEqual(result.toolName, "Bash")
        XCTAssertEqual(result.permissionDescription, "允許讀取？📦\n第二行")
        XCTAssertNil(result.lastAssistantMessage)
        XCTAssertEqual(result.displayText, "授權請求 · Bash · 允許讀取？📦\n第二行")
        let encoded = try JSONEncoder().encode(result)
        XCTAssertEqual(result, try TurnCompletion.parse(encoded))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("do not copy raw command"))
    }

    func testPermissionRequestReasonIsOptionalForAnyToolInputShape() throws {
        for input in ["null", "{}", "[]", "42", "\"text\"", "{\"description\":null}",
                      "{\"description\":42}", "{\"description\":\"  \"}"] {
            let data = Data("{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"t\",\"turn_id\":\"r\",\"tool_name\":\"mcp__example__read\",\"tool_input\":\(input)}".utf8)
            XCTAssertEqual(try TurnCompletion.parse(data)?.displayText, "授權請求 · mcp__example__read")
        }
        let data = Data(#"{"hook_event_name":"PermissionRequest","session_id":"t","turn_id":"r","tool_name":"Bash"}"#.utf8)
        XCTAssertEqual(try TurnCompletion.parse(data)?.displayText, "授權請求 · Bash")
    }

    func testPermissionRequestRequiresIdentityAndTool() {
        for json in [#"{"hook_event_name":"PermissionRequest"}"#,
                     #"{"hook_event_name":"PermissionRequest","session_id":"t","tool_name":"Bash"}"#,
                     #"{"hook_event_name":"PermissionRequest","turn_id":"r","tool_name":"Bash"}"#,
                     #"{"hook_event_name":"PermissionRequest","session_id":"t","turn_id":"r"}"#] {
            XCTAssertThrowsError(try TurnCompletion.parse(Data(json.utf8)))
        }
    }

    func testSameThreadKeepsOnlyTheLatestNotification() {
        let history = CompletionHistory()
        for number in 1...21 {
            history.receive(.init(type: "PermissionRequest", threadID: "t", turnID: "r",
                                  lastAssistantMessage: nil, toolName: "tool-\(number)"))
        }
        history.receive(.init(type: "Stop", threadID: "t", turnID: "r", lastAssistantMessage: "done"))
        XCTAssertEqual(history.totalCount, 1)
        XCTAssertEqual(history.recent.count, 1)
        XCTAssertEqual(history.recent.first?.notification.type, "Stop")
        XCTAssertEqual(history.recent.first?.notification.lastAssistantMessage, "done")
    }

    func payload(thread: String = "same-thread", turn: Int, message: String = "回覆完成") throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "type": "agent-turn-complete",
            "thread-id": thread,
            "turn-id": "turn-\(turn)",
            "last-assistant-message": message,
        ])
    }

    func testDecodesOfficialHyphenatedFieldsAndMultilineUnicode() throws {
        let message = "第一行\n引號：\"測試\"，路徑 \\ 與 📦"
        let result = try XCTUnwrap(TurnCompletion.parse(payload(turn: 3, message: message)))
        XCTAssertEqual(result.threadID, "same-thread")
        XCTAssertEqual(result.turnID, "turn-3")
        XCTAssertEqual(result.displayText, message)
    }

    func testOtherEventsAreIgnoredWithoutRequiringTurnFields() throws {
        XCTAssertNil(try TurnCompletion.parse(Data(#"{"type":"approval-requested"}"#.utf8)))
    }

    func testMalformedCompletionDoesNotBecomeAHistoryEntry() {
        XCTAssertThrowsError(try TurnCompletion.parse(Data(#"{"type":"agent-turn-complete"}"#.utf8)))
    }

    func testMissingMessageHasReadableFallback() throws {
        let data = Data(#"{"type":"agent-turn-complete","thread-id":"t","turn-id":"r"}"#.utf8)
        XCTAssertEqual(try TurnCompletion.parse(data)?.displayText, "回覆已結束")
    }

    func testRecentTwentyUseArrivalOrderAndDiscardOlderRecords() throws {
        let history = CompletionHistory()
        XCTAssertTrue(history.recent.isEmpty)
        for number in 1...22 {
            // Deliberately decreasing dates: display order must follow arrival order.
            history.receive(try XCTUnwrap(TurnCompletion.parse(payload(thread: "thread-\(number)", turn: number))),
                            at: Date(timeIntervalSince1970: Double(100 - number)))
            XCTAssertEqual(history.totalCount, min(number, 20))
        }
        XCTAssertEqual(history.totalCount, 20)
        XCTAssertEqual(history.recent.count, 20)
        XCTAssertEqual(history.recent.first?.notification.turnID, "turn-22")
        XCTAssertEqual(history.recent.last?.notification.turnID, "turn-3")
        XCTAssertEqual(Set(history.recent.map(\.notification.turnID)).count, 20)
        XCTAssertEqual(Set(history.recent.map(\.notification.threadID)).count, 20)
        for number in stride(from: 22, through: 3, by: -1) {
            let pending = try XCTUnwrap(history.latestUnopened)
            XCTAssertEqual(pending.notification.threadID, "thread-\(number)")
            history.markOpened(pending.id)
        }
        XCTAssertNil(history.latestUnopened)
        XCTAssertEqual(history.totalCount, 20)
    }

    func testNewNotificationAfterOpeningSameThreadBecomesPendingAgain() throws {
        let history = CompletionHistory()
        history.receive(.init(type: "Stop", threadID: "t", turnID: "one", lastAssistantMessage: "one"))
        let first = try XCTUnwrap(history.latestUnopened)
        history.markOpened(first.id)
        XCTAssertNil(history.latestUnopened)

        history.receive(.init(type: "Stop", threadID: "t", turnID: "two", lastAssistantMessage: "two"))
        XCTAssertEqual(history.totalCount, 1)
        XCTAssertEqual(history.latestUnopened?.notification.turnID, "two")
    }
}
