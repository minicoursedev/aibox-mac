import Foundation
import XCTest
@testable import AIBoxCore

final class RemoteNotificationTests: XCTestCase {
    @MainActor
    func testInvalidHostCannotStartSSH() {
        let connection = RemoteNotificationConnection(executable: URL(fileURLWithPath: "/missing"))
        for host in ["-oProxyCommand=bad", "srv;echo", "srv\nother", "srv -p 22", ""] {
            connection.connect(host: host)
            XCTAssertFalse(connection.isEnabled)
            XCTAssertTrue(connection.status.contains("主機別名"))
        }
    }

    @MainActor
    func testRetryConnectAndManualDisconnectStopsRetries() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("ssh")
        let script = """
        #!/bin/sh
        case " $* " in
          *" -R "*) printf 'AIBOX_READY\\n'; cat >/dev/null ;;
          *) cat >/dev/null
             if [ ! -e '\(root.path)/attempt' ]; then
               touch '\(root.path)/attempt'
               echo 'connection refused' >&2
               exit 1
             fi
             printf 'AIBOX_SOCKET=/tmp/aibox-test/notify.sock\\n' ;;
        esac
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let connection = RemoteNotificationConnection(executable: executable)
        defer { connection.disconnect() }
        let connected = expectation(description: "retry establishes tunnel")
        var sawRetry = false
        connection.onStatus = { status in
            if status.contains("秒後重試") { sawRetry = true }
            if status.hasPrefix("已連線至") { connected.fulfill() }
        }
        connection.connect(host: "test-host")
        await fulfillment(of: [connected], timeout: 6)
        XCTAssertTrue(sawRetry)
        XCTAssertTrue(connection.isEnabled)
        connection.disconnect()
        let noReconnect = expectation(description: "manual disconnect prevents reconnect")
        noReconnect.isInverted = true
        connection.onStatus = { _ in noReconnect.fulfill() }
        await fulfillment(of: [noReconnect], timeout: 2.2)
        XCTAssertEqual(connection.status, "已斷線")
        XCTAssertFalse(connection.isEnabled)
        connection.onStatus = nil
    }
}
