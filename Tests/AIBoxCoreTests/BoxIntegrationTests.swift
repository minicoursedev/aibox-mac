import AppKit
import XCTest
@testable import AIBoxCore

final class BoxIntegrationTests: XCTestCase {
    func testLiveSoundMonitoringLifecycleAndTelemetryDuringSensitivityEdits() {
        var session = BoxSession()
        XCTAssertNil(session.soundReading("MIC 1200 0"))
        XCTAssertNil(session.setSoundMonitoring(true))
        _ = session.subscribed()
        _ = session.receive(BoxProtocol.identity)
        _ = session.receive("AUTHORIZED")
        _ = session.receive("ACK S 11")
        XCTAssertEqual(session.receive("ACK M 50"), "R 1")
        XCTAssertEqual(session.receive("ACK R 1"), "T 1000")
        _ = session.receive("ACK T 1000")
        _ = session.receive("ACK L I 0000FF 0000FF")
        XCTAssertEqual(session.setSoundSensitivity(20), "M 20")
        XCTAssertEqual(session.soundReading("MIC 1200 0")?.peak, 1200)
        XCTAssertEqual(session.soundReading("MIC 1200 0")?.meetsThreshold, false)
        XCTAssertEqual(session.soundReading("MIC 1200 1")?.meetsThreshold, true)
        XCTAssertNil(session.receive("MIC 1200 0"))
        XCTAssertEqual(session.pendingCommand, "M 20")
        XCTAssertEqual(session.soundReading("MIC 0 0")?.peak, 0)
        XCTAssertEqual(session.soundReading("MIC 32768 0")?.peak, 32768)
        for invalid in ["MIC -1 0", "MIC 32769 1", "MIC x 0", "MIC 1 2", "MIC 1", "MIC 1 0 extra", "SHAKE 1"] {
            XCTAssertNil(session.soundReading(invalid))
        }
        _ = session.receive("ACK M 20")
        session.disconnected()
        XCTAssertNil(session.soundReading("MIC 100 0"))
        _ = session.subscribed()
        _ = session.receive(BoxProtocol.identity)
        _ = session.receive("AUTHORIZED")
        _ = session.receive("ACK S 11")
        XCTAssertEqual(session.receive("ACK M 20"), "R 1")
        _ = session.receive("ACK R 1")
        _ = session.receive("ACK T 1000")
        _ = session.receive("ACK L I 0000FF 0000FF")
        XCTAssertEqual(session.setSoundMonitoring(false), "R 0")
        XCTAssertNil(session.soundReading("MIC 100 0"))
        XCTAssertNil(session.receive("ACK R 0"))
        _ = session.setSoundMonitoring(true)
        _ = session.receive("ACK R 1")
        _ = session.setDetection(shake: true, sound: false)
        XCTAssertNil(session.soundReading("MIC 100 0"))
    }

    func testSoundSensitivityCoalescesEditsAndRestoresOnReconnect() {
        var session = BoxSession()
        XCTAssertNil(session.setSoundSensitivity(-1))
        XCTAssertEqual(session.soundSensitivity, 0)
        _ = session.subscribed()
        _ = session.receive(BoxProtocol.identity)
        _ = session.receive("AUTHORIZED")
        XCTAssertEqual(session.receive("ACK S 11"), "M 0")
        XCTAssertNil(session.setSoundSensitivity(25))
        XCTAssertNil(session.setSoundSensitivity(101))
        XCTAssertEqual(session.soundSensitivity, 100)
        XCTAssertNil(session.receive("ACK M 25"))
        XCTAssertEqual(session.pendingCommand, "M 0")
        XCTAssertEqual(session.receive("ACK M 0"), "M 100")
        XCTAssertNil(session.setPattern(.permission))
        XCTAssertEqual(session.receive("ACK M 100"), "T 1000")
        XCTAssertEqual(session.receive("ACK T 1000"), "L P FF0000 FFFFFF")
        XCTAssertNil(session.receive("ACK L P FF0000 FFFFFF"))
        XCTAssertEqual(session.setSoundSensitivity(20), "M 20")
        XCTAssertNil(session.receive("ACK M 20"))
        XCTAssertEqual(session.confirmedPattern, .permission)
        XCTAssertNil(session.setSoundSensitivity(20))
        session.disconnected()
        _ = session.subscribed()
        _ = session.receive(BoxProtocol.identity)
        _ = session.receive("AUTHORIZED")
        XCTAssertEqual(session.receive("ACK S 11"), "M 20")
        XCTAssertEqual(session.receive("ACK M 20"), "T 1000")
    }

    @MainActor
    func testQuestionUsesPermissionLightAndOpensItsConversation() {
        let history = CompletionHistory()
        var patterns: [BoxLightPattern] = []
        var opened: [String] = []
        let flow = ConversationAlertFlow(history: history, setPattern: { patterns.append($0) },
            openURL: { opened.append($0.absoluteString); return true }, onFailure: { XCTFail($0) })
        flow.receive(notification("question", type: "UserInputRequest"))
        flow.shake()
        XCTAssertEqual(patterns, [.permission, .idle])
        XCTAssertEqual(opened, ["codex://threads/question"])
        XCTAssertNil(history.latestUnopened)
    }

    func testDetectionSettingsHandshakeUpdatesAndReconnect() {
        for shake in [false, true] {
            for sound in [false, true] {
                var session = BoxSession()
                let command = "S \(shake ? 1 : 0)\(sound ? 1 : 0)"
                XCTAssertNil(session.setDetection(shake: shake, sound: sound))
                _ = session.subscribed()
                _ = session.receive(BoxProtocol.identity)
                XCTAssertEqual(session.receive("AUTHORIZED"), command)
                XCTAssertNil(session.receive("ACK S"))
                XCTAssertEqual(session.phase, .arming)
                XCTAssertEqual(session.receive("ACK \(command)"), "M 50")
                XCTAssertEqual(session.receive("ACK M 50"), "T 1000")
                _ = session.receive("ACK T 1000")
                _ = session.receive("ACK L I 0000FF 0000FF")
                XCTAssertEqual(session.isShake("SHAKE 1"), shake || sound)
                session.disconnected()
                _ = session.subscribed()
                _ = session.receive(BoxProtocol.identity)
                XCTAssertEqual(session.receive("AUTHORIZED"), command)
            }
        }
        var session = BoxSession()
        _ = session.subscribed()
        _ = session.receive(BoxProtocol.identity)
        _ = session.receive("AUTHORIZED")
        _ = session.setDetection(shake: false, sound: true)
        XCTAssertEqual(session.receive("ACK S 11"), "S 01")
        XCTAssertNil(session.setDetection(shake: true, sound: false))
        XCTAssertEqual(session.receive("ACK S 01"), "S 10")
        XCTAssertEqual(session.receive("ACK S 10"), "M 50")
        XCTAssertEqual(session.receive("ACK M 50"), "T 1000")
        _ = session.receive("ACK T 1000")
        _ = session.receive("ACK L I 0000FF 0000FF")
        XCTAssertEqual(session.setPattern(.permission), "L P FF0000 FFFFFF")
        XCTAssertNil(session.setDetection(shake: false, sound: false))
        XCTAssertEqual(session.receive("ACK L P FF0000 FFFFFF"), "S 00")
        XCTAssertNil(session.receive("ACK S 00"))
        XCTAssertEqual(session.confirmedPattern, .permission)
        XCTAssertFalse(session.isShake("SHAKE 2"))
    }

    private func notification(_ id: String, type: String = "Stop") -> TurnCompletion {
        .init(type: type, threadID: id, turnID: id, lastAssistantMessage: id)
    }

    @MainActor
    func testShakeOpensNewestUnopenedAndRetainsHistory() {
        let history = CompletionHistory()
        var urls: [String] = []
        var patterns: [BoxLightPattern] = []
        let flow = ConversationAlertFlow(history: history, setPattern: { patterns.append($0) },
                                        openURL: { urls.append($0.absoluteString); return true }, onFailure: { XCTFail($0) })
        flow.receive(notification("older"))
        flow.receive(notification("newer", type: "PermissionRequest"))
        flow.shake()
        XCTAssertEqual(history.latestUnopened?.notification.threadID, "older")
        flow.shake()
        flow.shake()
        XCTAssertEqual(urls, ["codex://threads/newer", "codex://threads/older"])
        XCTAssertEqual(patterns, [.completion, .permission, .completion, .idle])
        XCTAssertEqual(history.recent.count, 2)
        XCTAssertNil(history.latestUnopened)
    }

    @MainActor
    func testFailedOpenDoesNotConsumeNotificationOrStopAlert() {
        let history = CompletionHistory()
        var patterns: [BoxLightPattern] = []
        var failures = 0
        let flow = ConversationAlertFlow(history: history, setPattern: { patterns.append($0) },
                                        openURL: { _ in false }, onFailure: { _ in failures += 1 })
        flow.receive(notification("pending"))
        flow.shake()
        XCTAssertEqual(history.latestUnopened?.notification.threadID, "pending")
        XCTAssertEqual(patterns, [.completion])
        XCTAssertEqual(failures, 1)
    }

    @MainActor
    func testMenuClickMarksOnlyThatRecordAndShakeSkipsIt() throws {
        let history = CompletionHistory()
        var opened: [String] = []
        let opener: (URL) -> Bool = { opened.append($0.absoluteString); return true }
        var patterns: [BoxLightPattern] = []
        let flow = ConversationAlertFlow(history: history, setPattern: { patterns.append($0) }, openURL: opener, onFailure: { XCTFail($0) })
        flow.receive(notification("a"))
        flow.receive(notification("b", type: "PermissionRequest"))
        let record = try XCTUnwrap(history.latestUnopened)
        let menu = ConversationNotificationMenu(openURL: opener, onFailure: { XCTFail($0) })
        let item = menu.item(notification: record.notification, title: "b", onOpened: { flow.didOpen(record.id) })
        XCTAssertTrue(NSApplication.shared.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        flow.shake()
        XCTAssertEqual(opened, ["codex://threads/b", "codex://threads/a"])
        XCTAssertEqual(patterns, [.completion, .permission, .completion, .idle])
        XCTAssertEqual(history.recent.count, 2)
    }

    @MainActor
    func testMenuFailureDoesNotInvokeOpenedCallback() throws {
        var callbacks = 0
        let menu = ConversationNotificationMenu(openURL: { _ in false }, onFailure: { _ in })
        let item = menu.item(notification: notification("a"), title: "a", onOpened: { callbacks += 1 })
        XCTAssertTrue(NSApplication.shared.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        XCTAssertEqual(callbacks, 0)
    }

    func testRepeatedThreadIDsKeepOnlyTheLatestRecord() throws {
        let history = CompletionHistory()
        for number in 1...22 {
            history.receive(notification("same-thread"), at: Date(timeIntervalSince1970: Double(100 - number)))
        }
        let newest = try XCTUnwrap(history.latestUnopened)
        XCTAssertEqual(newest.receivedAt, Date(timeIntervalSince1970: 78))
        XCTAssertEqual(history.recent.count, 1)
        XCTAssertEqual(history.totalCount, 1)
        history.markOpened(newest.id)
        XCTAssertNil(history.latestUnopened)
    }

    func testPacketsCanContainPartialOrMultipleMessages() {
        var decoder = BoxLineDecoder()
        XCTAssertEqual(decoder.append(Data("AIBOX-".utf8)), [])
        XCTAssertEqual(decoder.append(Data("2\nACK S\r\nSHA".utf8)), ["AIBOX-2", "ACK S"])
        XCTAssertEqual(decoder.append(Data("KE 12\n".utf8)), ["SHAKE 12"])
    }

    func testHandshakeDoesNotAcceptTestFirmwareOrEarlyShake() {
        var session = BoxSession()
        XCTAssertNil(session.setPattern(.completion))
        XCTAssertEqual(session.subscribed(), "?")
        XCTAssertNil(session.receive("AIBOX-BLE-CHECK-2"))
        XCTAssertNil(session.receive("AIBOX-1"))
        XCTAssertFalse(session.isShake("SHAKE 1"))
        XCTAssertNil(session.receive("AIBOX-2"))
        XCTAssertNil(session.receive("AIBOX-3"))
        XCTAssertNil(session.receive("AIBOX-4"))
        XCTAssertEqual(session.receive("AIBOX-5"), "A")
        XCTAssertNil(session.receive("ACK S 11"))
        XCTAssertEqual(session.receive("AUTHORIZED"), "S 11")
        XCTAssertFalse(session.isShake("SHAKE 1"))
        XCTAssertEqual(session.receive("ACK S 11"), "M 50")
        XCTAssertEqual(session.receive("ACK M 50"), "T 1000")
        XCTAssertEqual(session.receive("ACK T 1000"), "L C FFFF00 FFFFFF")
        XCTAssertTrue(session.isShake("SHAKE 1"))
        XCTAssertFalse(session.isShake("SHAKE 0"))
        XCTAssertFalse(session.isShake("SHAKE text"))
        XCTAssertFalse(session.isShake("ACK C"))
    }

    func testLateAcknowledgementsFollowLatestAlertIntent() {
        var session = BoxSession()
        _ = session.subscribed()
        _ = session.receive("AIBOX-5")
        _ = session.receive("AUTHORIZED")
        XCTAssertEqual(session.receive("ACK S 11"), "M 50")
        XCTAssertEqual(session.receive("ACK M 50"), "T 1000")
        XCTAssertEqual(session.receive("ACK T 1000"), "L I 0000FF 0000FF")
        XCTAssertNil(session.setPattern(.completion))
        XCTAssertEqual(session.receive("ACK L I 0000FF 0000FF"), "L C FFFF00 FFFFFF")
        XCTAssertNil(session.setPattern(.permission))
        XCTAssertEqual(session.receive("ACK L C FFFF00 FFFFFF"), "L P FF0000 FFFFFF")
        XCTAssertNil(session.setPattern(.idle))
        XCTAssertEqual(session.receive("ACK L P FF0000 FFFFFF"), "L I 0000FF 0000FF")
        XCTAssertNil(session.receive("ACK L I 0000FF 0000FF"))
        XCTAssertEqual(session.confirmedPattern, .idle)
        XCTAssertNil(session.pendingCommand)
    }

    func testReconnectionPreservesPendingAlertAndRequiresHandshakeAgain() {
        var session = BoxSession()
        _ = session.setPattern(.permission)
        _ = session.subscribed()
        _ = session.receive("AIBOX-5")
        _ = session.receive("AUTHORIZED")
        _ = session.receive("ACK S 11")
        _ = session.receive("ACK M 50")
        _ = session.receive("ACK T 1000")
        _ = session.receive("ACK L P FF0000 FFFFFF")
        session.disconnected()
        XCTAssertEqual(session.desiredPattern, .permission)
        XCTAssertNil(session.confirmedPattern)
        XCTAssertFalse(session.isShake("SHAKE 1"))
        _ = session.subscribed()
        _ = session.receive("AIBOX-5")
        _ = session.receive("AUTHORIZED")
        XCTAssertEqual(session.receive("ACK S 11"), "M 50")
        XCTAssertEqual(session.receive("ACK M 50"), "T 1000")
        XCTAssertEqual(session.receive("ACK T 1000"), "L P FF0000 FFFFFF")
    }

    @MainActor
    func testLatestUnopenedDeterminesColorNotPermissionPriority() {
        let history = CompletionHistory()
        var patterns: [BoxLightPattern] = []
        let flow = ConversationAlertFlow(history: history, setPattern: { patterns.append($0) },
                                        openURL: { _ in true }, onFailure: { XCTFail($0) })
        flow.receive(notification("permission", type: "PermissionRequest"))
        flow.receive(notification("completion"))
        flow.shake()
        flow.shake()
        XCTAssertEqual(patterns, [.permission, .completion, .permission, .idle])
    }

    @MainActor
    func testClickingOlderNotificationKeepsNewestColor() throws {
        let history = CompletionHistory()
        var patterns: [BoxLightPattern] = []
        let flow = ConversationAlertFlow(history: history, setPattern: { patterns.append($0) },
                                        openURL: { _ in true }, onFailure: { XCTFail($0) })
        flow.receive(notification("older"))
        let older = try XCTUnwrap(history.latestUnopened)
        flow.receive(notification("latest", type: "PermissionRequest"))
        flow.didOpen(older.id)
        XCTAssertEqual(patterns, [.completion, .permission, .permission])
        XCTAssertEqual(history.latestUnopened?.notification.threadID, "latest")
    }

    @MainActor
    func testLegacyCompletionUsesYellowWhite() {
        var patterns: [BoxLightPattern] = []
        let flow = ConversationAlertFlow(history: CompletionHistory(), setPattern: { patterns.append($0) },
                                        openURL: { _ in true }, onFailure: { XCTFail($0) })
        flow.receive(notification("legacy", type: "agent-turn-complete"))
        XCTAssertEqual(patterns, [.completion])
    }

    func testIdleHandshakeAndUnexpectedAcknowledgement() {
        var session = BoxSession()
        XCTAssertEqual(session.desiredPattern, .idle)
        _ = session.subscribed()
        _ = session.receive("AIBOX-5")
        _ = session.receive("AUTHORIZED")
        XCTAssertEqual(session.receive("ACK S 11"), "M 50")
        XCTAssertEqual(session.receive("ACK M 50"), "T 1000")
        XCTAssertEqual(session.receive("ACK T 1000"), "L I 0000FF 0000FF")
        XCTAssertNil(session.receive("ACK F"))
        XCTAssertNil(session.receive("ACK P"))
        XCTAssertEqual(session.pendingCommand, "L I 0000FF 0000FF")
        XCTAssertNil(session.confirmedPattern)
        XCTAssertNil(session.receive("ACK L I 0000FF 0000FF"))
        XCTAssertEqual(session.confirmedPattern, .idle)
        XCTAssertNil(session.setPattern(.idle))
    }

    func testRapidColorEditsCoalesceUntilAcknowledgement() {
        var session = BoxSession()
        _ = session.subscribed()
        _ = session.receive("AIBOX-5")
        _ = session.receive("AUTHORIZED")
        _ = session.receive("ACK S 11")
        _ = session.receive("ACK M 50")
        _ = session.receive("ACK T 1000")
        _ = session.receive("ACK L I 0000FF 0000FF")
        var colors = BoxLightColors()
        colors.idle = BoxRGB(red: 18, green: 52, blue: 86)
        XCTAssertEqual(session.setColors(colors), "L I 123456 123456")
        colors.idle = BoxRGB(red: 171, green: 205, blue: 239)
        XCTAssertNil(session.setColors(colors))
        XCTAssertNil(session.receive("ACK L I 0000FF 0000FF"))
        XCTAssertEqual(session.receive("ACK L I 123456 123456"), "L I ABCDEF ABCDEF")
        XCTAssertNil(session.receive("ACK L I ABCDEF ABCDEF"))
        XCTAssertNil(session.setColors(colors))
    }

    func testInactiveColorEditAppliesWhenPatternChangesAndAfterReconnect() {
        var session = BoxSession()
        _ = session.subscribed()
        _ = session.receive("AIBOX-5")
        _ = session.receive("AUTHORIZED")
        _ = session.receive("ACK S 11")
        _ = session.receive("ACK M 50")
        _ = session.receive("ACK T 1000")
        _ = session.receive("ACK L I 0000FF 0000FF")
        var colors = BoxLightColors()
        colors.completion = BoxRGB(red: 0, green: 255, blue: 128)
        colors.completionAlternate = BoxRGB(red: 128, green: 0, blue: 255)
        XCTAssertNil(session.setColors(colors))
        XCTAssertEqual(session.setPattern(.completion), "L C 00FF80 8000FF")
        _ = session.receive("ACK L C 00FF80 8000FF")
        session.disconnected()
        _ = session.subscribed()
        _ = session.receive("AIBOX-5")
        _ = session.receive("AUTHORIZED")
        XCTAssertEqual(session.receive("ACK S 11"), "M 50")
        XCTAssertEqual(session.receive("ACK M 50"), "T 1000")
        XCTAssertEqual(session.receive("ACK T 1000"), "L C 00FF80 8000FF")
    }

    func testIntervalEndpointsAndRapidEditsFollowLatestIntent() {
        var session = BoxSession()
        _ = session.setBlinkInterval(1)
        _ = session.subscribed()
        _ = session.receive("AIBOX-5")
        _ = session.receive("AUTHORIZED")
        XCTAssertEqual(session.receive("ACK S 11"), "M 50")
        XCTAssertEqual(session.receive("ACK M 50"), "T 100")
        XCTAssertNil(session.setBlinkInterval(25))
        XCTAssertNil(session.setBlinkInterval(100))
        XCTAssertNil(session.receive("ACK T 2500"))
        XCTAssertEqual(session.receive("ACK T 100"), "T 10000")
        XCTAssertEqual(session.receive("ACK T 10000"), "L I 0000FF 0000FF")
        _ = session.receive("ACK L I 0000FF 0000FF")
        XCTAssertNil(session.setBlinkInterval(100))
        session.disconnected()
        _ = session.subscribed()
        _ = session.receive("AIBOX-5")
        _ = session.receive("AUTHORIZED")
        XCTAssertEqual(session.receive("ACK S 11"), "M 50")
        XCTAssertEqual(session.receive("ACK M 50"), "T 10000")
    }

    func testIntervalAndColorChangesSerializeTogether() {
        var session = BoxSession()
        _ = session.subscribed()
        _ = session.receive("AIBOX-5")
        _ = session.receive("AUTHORIZED")
        _ = session.receive("ACK S 11")
        _ = session.receive("ACK M 50")
        _ = session.receive("ACK T 1000")
        XCTAssertNil(session.setBlinkInterval(7))
        XCTAssertNil(session.setPattern(.permission))
        XCTAssertEqual(session.receive("ACK L I 0000FF 0000FF"), "T 700")
        XCTAssertEqual(session.receive("ACK T 700"), "L P FF0000 FFFFFF")
        XCTAssertNil(session.receive("ACK L P FF0000 FFFFFF"))
        XCTAssertEqual(session.confirmedPattern, .permission)
        XCTAssertEqual(session.setBlinkInterval(0), "T 100")
        _ = session.receive("ACK T 100")
        XCTAssertEqual(session.setBlinkInterval(101), "T 10000")
    }

    func testSavedColorsRoundTripAndFitDefaultBLEWriteSize() throws {
        var colors = BoxLightColors()
        colors[.permission] = BoxRGB(red: 12, green: 34, blue: 56)
        colors[.permissionAlternate] = BoxRGB(red: 255, green: 128, blue: 0)
        let data = try JSONEncoder().encode(colors)
        let restored = try JSONDecoder().decode(BoxLightColors.self, from: data)
        XCTAssertEqual(restored, colors)
        XCTAssertEqual(restored.command(for: .permission), "L P 0C2238 FF8000")
        for pattern: BoxLightPattern in [.idle, .completion, .permission] {
            XCTAssertLessThanOrEqual((restored.command(for: pattern) + "\n").utf8.count, 20)
        }
    }
}
