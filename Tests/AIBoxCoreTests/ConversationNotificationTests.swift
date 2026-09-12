import AppKit
import XCTest
@testable import AIBoxCore

final class ConversationNotificationTests: XCTestCase {
    func testConversationURLPreservesExactIdentifier() {
        XCTAssertEqual(CodexConversationLink.url(threadID: "01a06b12-a910-7230-91af-5ba4ae9b4033")?.absoluteString,
                       "codex://threads/01a06b12-a910-7230-91af-5ba4ae9b4033")
        XCTAssertNil(CodexConversationLink.url(threadID: ""))
        XCTAssertEqual(CodexConversationLink.url(threadID: "a/b?c#d%")?.absoluteString,
                       "codex://threads/a%2Fb%3Fc%23d%25")
    }

    @MainActor
    func testClickingOlderNotificationOpensItsOwnThread() throws {
        var opened: [URL] = []
        let handler = ConversationNotificationMenu(openURL: { opened.append($0); return true },
                                                   onFailure: { XCTFail($0) })
        let old = handler.item(notification: .init(type: "Stop", threadID: "older-thread", turnID: "one",
                                                   lastAssistantMessage: "older"), title: "older")
        let new = handler.item(notification: .init(type: "Stop", threadID: "newer-thread", turnID: "two",
                                                   lastAssistantMessage: "newer"), title: "newer")
        XCTAssertTrue(NSApplication.shared.sendAction(try XCTUnwrap(old.action), to: old.target, from: old))
        XCTAssertTrue(NSApplication.shared.sendAction(try XCTUnwrap(new.action), to: new.target, from: new))
        XCTAssertEqual(opened.map(\.absoluteString), ["codex://threads/older-thread", "codex://threads/newer-thread"])
    }

    @MainActor
    func testPermissionNotificationClickOpensItsOwnConversationWithoutApproving() throws {
        var opened: [URL] = []
        let handler = ConversationNotificationMenu(openURL: { opened.append($0); return true },
                                                   onFailure: { XCTFail($0) })
        let notification = TurnCompletion(type: "PermissionRequest", threadID: "approval-thread", turnID: "r",
                                          lastAssistantMessage: nil, toolName: "Bash", permissionDescription: "讀取資料")
        let item = handler.item(notification: notification, title: notification.displayText)
        XCTAssertEqual(item.title, "授權請求 · Bash · 讀取資料")
        XCTAssertTrue(try XCTUnwrap(item.toolTip).contains("approval-thread"))
        XCTAssertTrue(NSApplication.shared.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        XCTAssertEqual(opened.map(\.absoluteString), ["codex://threads/approval-thread"])
    }

    @MainActor
    func testOpenFailureIsReported() throws {
        var failures: [String] = []
        let handler = ConversationNotificationMenu(openURL: { _ in false }, onFailure: { failures.append($0) })
        let item = handler.item(notification: .init(type: "Stop", threadID: "t", turnID: "r",
                                                    lastAssistantMessage: nil), title: "test")
        XCTAssertTrue(NSApplication.shared.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        XCTAssertEqual(failures.count, 1)
    }
}
