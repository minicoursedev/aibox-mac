import XCTest
import CoreBluetooth
@testable import AIBoxCore

final class BoxPairingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private let first = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let second = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    override func setUp() {
        suite = "AIBoxPairingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    private func challenge(_ id: String = "1234ABCD") -> BoxSession {
        var session = BoxSession()
        XCTAssertNil(session.beginIdentification())
        XCTAssertEqual(session.subscribed(), "?")
        XCTAssertEqual(session.receive("AIBOX-5"), "B")
        XCTAssertFalse(session.isIdentificationVisible)
        XCTAssertNil(session.receive("PAIR \(id)"))
        XCTAssertTrue(session.isIdentificationVisible)
        return session
    }
    private func confirmed(_ color: BoxPairingColor = .green) -> BoxSession {
        var session = challenge()
        _ = session.answer(color)
        XCTAssertEqual(session.receive("PAIRED 1234ABCD"), "S 11")
        return session
    }
    func testFirstUseNeverChoosesEitherNearbyDeviceAutomatically() {
        let pairing = BoxPairing(defaults: defaults)
        XCTAssertFalse(pairing.shouldReconnect(to: first))
        XCTAssertFalse(pairing.shouldReconnect(to: second))
        XCTAssertFalse(pairing.confirmAuthorizedDevice(first, session: confirmed()))
        XCTAssertNil(pairing.savedDeviceID)
    }
    func testRemovedSystemBondRequiresForgetInsteadOfGenericReconnect() {
        XCTAssertTrue(BoxPairing.requiresSystemPairingReset(
            NSError(domain: CBErrorDomain, code: CBError.peerRemovedPairingInformation.rawValue)))
        // ATT code 14 means a different error; never tell the user to forget
        // a valid bond just because another domain uses the same number.
        XCTAssertFalse(BoxPairing.requiresSystemPairingReset(
            NSError(domain: CBATTErrorDomain, code: 14)))
        XCTAssertFalse(BoxPairing.requiresSystemPairingReset(
            NSError(domain: CBErrorDomain, code: CBError.connectionTimeout.rawValue)))
        XCTAssertFalse(BoxPairing.requiresSystemPairingReset(nil))
    }
    func testSaveRequiresBoxAcknowledgementAndMatchingCandidate() {
        let pairing = BoxPairing(defaults: defaults)
        pairing.beginSelection()
        pairing.select(second)
        var session = challenge()
        XCTAssertFalse(pairing.confirmAuthorizedDevice(second, session: session))
        XCTAssertEqual(session.answer(.red), "V 1234ABCD R")
        XCTAssertFalse(pairing.confirmAuthorizedDevice(second, session: session))
        XCTAssertNil(session.receive("PAIRED 87654321"))
        XCTAssertFalse(session.isAuthorized)
        _ = session.receive("PAIRED 1234ABCD")
        XCTAssertFalse(pairing.confirmAuthorizedDevice(first, session: session))
        XCTAssertTrue(pairing.confirmAuthorizedDevice(second, session: session))
        XCTAssertEqual(BoxPairing(defaults: defaults).savedDeviceID, second)
        XCTAssertTrue(BoxPairing(defaults: defaults).shouldReconnect(to: second))
    }
    func testWrongAnswerInvalidatesChallengeAndRequiresRetry() {
        var session = challenge()
        XCTAssertNil(session.receive("PAIRED 1234ABCD")) // no submitted answer
        _ = session.answer(.blue)
        XCTAssertNil(session.receive("ERR ANSWER 1234ABCD"))
        XCTAssertEqual(session.phase, .rejectedColor)
        XCTAssertFalse(session.isAuthorized)
        XCTAssertNil(session.answer(.green))
        XCTAssertNil(session.receive("PAIRED 1234ABCD"))
        XCTAssertEqual(session.beginIdentification(), "B")
        _ = session.receive("PAIR 9876ABCD")
        _ = session.answer(.red)
        XCTAssertNil(session.receive("PAIRED 1234ABCD"))
        XCTAssertFalse(session.isAuthorized)
        XCTAssertEqual(session.receive("PAIRED 9876ABCD"), "S 11")
    }
    func testCancelledOrDisconnectedReplacementPreservesExistingChoice() {
        let pairing = BoxPairing(defaults: defaults)
        pairing.beginSelection()
        pairing.select(first)
        XCTAssertTrue(pairing.confirmAuthorizedDevice(first, session: confirmed()))
        pairing.beginSelection()
        pairing.select(second)
        var session = challenge()
        _ = session.answer(.green)
        session.disconnected()
        XCTAssertNil(session.receive("PAIRED 1234ABCD"))
        XCTAssertFalse(pairing.confirmAuthorizedDevice(second, session: session))
        pairing.cancelSelection()
        XCTAssertTrue(pairing.shouldReconnect(to: first))
        XCTAssertEqual(BoxPairing(defaults: defaults).savedDeviceID, first)
    }
    func testReconnectAuthorizationCannotStandInForColorConfirmation() {
        let pairing = BoxPairing(defaults: defaults)
        pairing.beginSelection()
        pairing.select(second)
        var session = BoxSession()
        _ = session.subscribed()
        _ = session.receive("AIBOX-5")
        XCTAssertEqual(session.receive("AUTHORIZED"), "S 11")
        XCTAssertTrue(session.isAuthorized)
        XCTAssertFalse(pairing.confirmAuthorizedDevice(second, session: session))
    }
    func testResetBoxRequiresNewColorConfirmationEvenWithSavedIdentifier() {
        var session = BoxSession()
        _ = session.subscribed()
        _ = session.receive("AIBOX-5")
        XCTAssertNil(session.receive("PAIR REQUIRED"))
        XCTAssertTrue(session.needsPairing)
        XCTAssertFalse(session.isAuthorized)
        XCTAssertNil(session.receive("ACK S 11"))
        XCTAssertEqual(session.beginIdentification(), "B")
        _ = session.receive("PAIR ABCD1234")
        _ = session.answer(.blue)
        XCTAssertEqual(session.receive("PAIRED ABCD1234"), "S 11")
    }
    func testChallengeParserAndEveryColorFitDefaultBLEPacket() {
        for color in BoxPairingColor.allCases {
            var session = BoxSession()
            _ = session.beginIdentification()
            _ = session.subscribed()
            _ = session.receive("AIBOX-5")
            for invalid in ["PAIR R", "PAIR 1234ABCD R", "PAIR 0000000", "PAIR 0000000Z"] {
                XCTAssertNil(session.receive(invalid))
                XCTAssertFalse(session.isIdentificationVisible)
            }
            _ = session.receive("PAIR 1234ABCD")
            let answer = session.answer(color)!
            XCTAssertLessThanOrEqual((answer + "\n").utf8.count, 20)
            XCTAssertNil(session.answer(color))
            XCTAssertFalse(session.isShake("SHAKE 1"))
        }
    }
    func testNotificationAndSettingsDuringConfirmationRestoreLatestIntent() {
        var session = challenge()
        var colors = BoxLightColors()
        colors.permission = BoxRGB(red: 0, green: 255, blue: 255)
        XCTAssertNil(session.setPattern(.completion))
        XCTAssertNil(session.setPattern(.permission))
        XCTAssertNil(session.setColors(colors))
        XCTAssertNil(session.setBlinkInterval(7))
        XCTAssertTrue(session.isIdentificationVisible)
        _ = session.answer(.red)
        _ = session.receive("PAIRED 1234ABCD")
        XCTAssertEqual(session.receive("ACK S 11"), "M 50")
        XCTAssertEqual(session.receive("ACK M 50"), "T 700")
        XCTAssertEqual(session.receive("ACK T 700"), "L P 00FFFF FFFFFF")
        _ = session.receive("ACK L P 00FFFF FFFFFF")
        XCTAssertEqual(session.confirmedPattern, .permission)
        XCTAssertTrue(session.isShake("SHAKE 1"))
    }
    func testUnpairStopsCommandsAndForgetPersists() {
        let pairing = BoxPairing(defaults: defaults)
        pairing.beginSelection()
        pairing.select(first)
        var session = confirmed()
        XCTAssertTrue(pairing.confirmAuthorizedDevice(first, session: session))
        _ = session.receive("ACK S 11")
        _ = session.receive("ACK M 50")
        XCTAssertEqual(session.unpair(), "U")
        XCTAssertNil(session.setPattern(.completion))
        XCTAssertNil(session.receive("ACK T 1000"))
        XCTAssertFalse(session.isShake("SHAKE 1"))
        pairing.forgetDevice()
        XCTAssertNil(BoxPairing(defaults: defaults).savedDeviceID)
        XCTAssertFalse(pairing.shouldReconnect(to: first))
    }
    @MainActor
    func testColorConfirmationDoesNotConsumeWaitingNotification() {
        let history = CompletionHistory()
        var session = challenge()
        var opened: [URL] = []
        let flow = ConversationAlertFlow(history: history, setPattern: { _ = session.setPattern($0) },
            openURL: { opened.append($0); return true }, onFailure: { XCTFail($0) })
        flow.receive(.init(type: "Stop", threadID: "waiting", turnID: "turn", lastAssistantMessage: "done"))
        XCTAssertFalse(session.isShake("SHAKE 1"))
        _ = session.answer(.green)
        _ = session.receive("PAIRED 1234ABCD")
        XCTAssertEqual(session.receive("ACK S 11"), "M 50")
        XCTAssertEqual(session.receive("ACK M 50"), "T 1000")
        XCTAssertEqual(session.receive("ACK T 1000"), "L C FFFF00 FFFFFF")
        _ = session.receive("ACK L C FFFF00 FFFFFF")
        XCTAssertEqual(history.latestUnopened?.notification.threadID, "waiting")
        XCTAssertTrue(session.isShake("SHAKE 2"))
        flow.shake()
        XCTAssertEqual(opened.map(\.absoluteString), ["codex://threads/waiting"])
        XCTAssertNil(history.latestUnopened)
    }
}
