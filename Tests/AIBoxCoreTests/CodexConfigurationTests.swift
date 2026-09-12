import AppKit
import Foundation
import XCTest
@testable import AIBoxCore

final class CodexConfigurationTests: XCTestCase {
    func testCommandQuotesExecutablePath() {
        let service = CodexConfigurationService(executableURL: URL(fileURLWithPath: "/not-installed"),
            helperURL: URL(fileURLWithPath: "/AIBox 空白's/$test/aibox-notify"))
        XCTAssertEqual(service.hookCommand, "'/AIBox 空白'\"'\"'s/$test/aibox-notify' --hook")
    }

    func testMissingHelperDoesNotStartConfiguration() {
        let service = CodexConfigurationService(executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                                                helperURL: URL(fileURLWithPath: "/not-installed/aibox-notify"))
        XCTAssertThrowsError(try service.read())
    }

    func testUsageSnapshotReportsWeeklyAndSparkRemainingPercent() throws {
        let response: [String: Any] = [
            "rateLimits": [
                "primary": ["usedPercent": 77, "windowDurationMins": 10080,
                             "resetsAt": 1_788_748_448],
            ],
            "rateLimitsByLimitId": [
                "codex": [
                    "primary": ["usedPercent": 77, "windowDurationMins": 10080,
                                 "resetsAt": 1_788_748_448],
                ],
                "codex_bengalfox": [
                    "limitName": "GPT-5.3-Codex-Spark",
                    "primary": ["usedPercent": 42, "windowDurationMins": 300,
                                 "resetsAt": 1_788_532_752],
                ],
            ],
        ]

        let snapshot = try CodexUsageSnapshot(rateLimitsResponse: response)
        XCTAssertEqual(snapshot.weekly?.usedPercent, 77)
        XCTAssertEqual(snapshot.weekly?.remainingPercent, 23)
        XCTAssertEqual(snapshot.weekly?.windowDurationMins, 10080)
        XCTAssertEqual(snapshot.codex53Spark?.usedPercent, 42)
        XCTAssertEqual(snapshot.codex53Spark?.remainingPercent, 58)
    }

    func testInstalledCodexSchemeResolvesBundledExecutable() throws {
        guard let executable = ProcessInfo.processInfo.environment["AIBOX_TEST_CODEX_EXECUTABLE"] else {
            throw XCTSkip("Requires the installed Codex App.")
        }
        let app = try XCTUnwrap(NSWorkspace.shared.urlForApplication(toOpen: URL(string: "codex://threads")!))
        let bundled = try XCTUnwrap(Bundle(url: app)?.url(forResource: "codex", withExtension: nil))
        XCTAssertEqual(bundled.resolvingSymlinksInPath(), URL(fileURLWithPath: executable).resolvingSymlinksInPath())
    }

    func testOfficialRPCAddsThreeEventsWithoutNotifyAndRequiresTrust() throws {
        try withFixture { service, file in
            let before = try service.read()
            XCTAssertNil(before.hook)
            XCTAssertNil(before.permissionHook)
            XCTAssertNil(before.userInputHook)
            let after = try service.configure(expected: before)
            XCTAssertEqual(after.hook?.command, service.hookCommand)
            XCTAssertEqual(after.hook?.trustStatus, "untrusted")
            XCTAssertFalse(after.hook?.isActive ?? true)
            XCTAssertEqual(after.permissionHook?.command, service.hookCommand)
            XCTAssertEqual(after.permissionHook?.eventName, "PermissionRequest")
            XCTAssertEqual(after.permissionHook?.trustStatus, "untrusted")
            XCTAssertEqual(after.userInputHook?.command, service.hookCommand)
            XCTAssertEqual(after.userInputHook?.eventName, "PreToolUse")
            XCTAssertEqual(after.userInputHook?.trustStatus, "untrusted")
            XCTAssertTrue(after.allConfigured)
            XCTAssertFalse(after.allActive)
            XCTAssertFalse(try String(contentsOf: file).contains("notify ="))
            let bytes = try Data(contentsOf: file)
            _ = try service.configure(expected: after)
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }

    func testOfficialRPCPreservesNotifyOtherHooksAndTOMLComments() throws {
        let original = #"""
        # Keep this heading.
        notify = [
          'python3', # Original notification command.
          '''/old notifier.py''',
        ]
        model = "example-model" # Keep this comment.
        developer_instructions = """
        notify = ["this is text, not a setting"]
        Keep this multiline instruction.
        """

        [[hooks.Stop]]
        [[hooks.Stop.hooks]]
        type = "command"
        command = "/usr/bin/true"

        [[hooks.PermissionRequest]]
        [[hooks.PermissionRequest.hooks]]
        type = "command"
        command = "/usr/bin/false"
        """# + "\n"
        try withFixture(contents: original) { service, file in
            let before = try service.read()
            XCTAssertNil(before.hook)
            let after = try service.configure(expected: before)
            XCTAssertEqual(after.hook?.trustStatus, "untrusted")
            let updated = try String(contentsOf: file)
            let boundary = try XCTUnwrap(original.range(of: "[[hooks.Stop]]")).lowerBound
            XCTAssertTrue(updated.hasPrefix(String(original[..<boundary])), "notify and unrelated TOML remain byte-identical")
            XCTAssertTrue(updated.contains("command = \"/usr/bin/true\""))
            XCTAssertTrue(updated.contains("command = \"/usr/bin/false\""))
            let trusted = try service.trust(expected: after)
            XCTAssertTrue(trusted.hook?.isActive == true)
            XCTAssertTrue(trusted.permissionHook?.isActive == true)
            XCTAssertTrue(trusted.allActive)
            XCTAssertTrue(try String(contentsOf: file).hasPrefix(String(original[..<boundary])))
            let bytes = try Data(contentsOf: file)
            _ = try service.trust(expected: trusted)
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }

    func testTrustPreservesOtherHooksState() throws {
        try withFixture(contents: "[hooks.state.unrelated]\nenabled = false\ntrusted_hash = \"keep\"\n") { service, file in
            let installed = try service.configure(expected: service.read())
            _ = try service.trust(expected: installed)
            let updated = try String(contentsOf: file)
            XCTAssertTrue(updated.contains("[hooks.state.unrelated]"))
            XCTAssertTrue(updated.contains("enabled = false"))
            XCTAssertTrue(updated.contains("trusted_hash = \"keep\""))
        }
    }

    func testQuestionHookPreservesExistingMatcherAndUpgradesTrustedInstallation() throws {
        try withFixture { service, file in
            let installed = try service.configure(expected: service.read())
            _ = try service.trust(expected: installed)
            // Simulate the previous version plus an unrelated, narrowly matched tool hook.
            let contents = try String(contentsOf: file).replacingOccurrences(
                of: CodexConfigurationService.userInputMatcher, with: "^Bash$")
            try contents.write(to: file, atomically: true, encoding: .utf8)
            let before = try service.read()
            XCTAssertNil(before.userInputHook)
            XCTAssertTrue(before.hook?.isActive == true)
            XCTAssertTrue(before.permissionHook?.isActive == true)
            let after = try service.configure(expected: before)
            XCTAssertTrue(after.hook?.isActive == true)
            XCTAssertTrue(after.permissionHook?.isActive == true)
            XCTAssertEqual(after.userInputHook?.trustStatus, "untrusted")
            let updated = try String(contentsOf: file)
            XCTAssertTrue(updated.contains("^Bash$"))
            XCTAssertTrue(updated.contains(CodexConfigurationService.userInputMatcher))
            _ = try service.configure(expected: after)
            XCTAssertEqual(try String(contentsOf: file), updated)
        }
    }

    func testExistingHooksJSONIsPreserved() throws {
        try withFixture { service, file in
            let hooksFile = file.deletingLastPathComponent().appendingPathComponent("hooks.json")
            let contents = Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/usr/bin/true"}]}]}}"#.utf8)
            try contents.write(to: hooksFile)
            let after = try service.configure(expected: service.read())
            XCTAssertNotNil(after.hook)
            XCTAssertEqual(try Data(contentsOf: hooksFile), contents)
        }
    }

    func testDisabledGlobalHooksIsReportedWithoutEnablingIt() throws {
        try withFixture(contents: "[features]\nhooks = false\n") { service, _ in
            XCTAssertFalse(try service.read().hooksEnabled)
        }
    }

    func testStaleVersionDoesNotOverwriteExternalChanges() throws {
        try withFixture(contents: "model = \"example-model\"\n") { service, file in
            let before = try service.read()
            let external = "model = \"changed-elsewhere\"\nnotify = [\"/new-notifier\"]\n"
            try external.write(to: file, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try service.configure(expected: before))
            XCTAssertEqual(try String(contentsOf: file), external)
        }
    }

    func testTrustRejectsChangedDefinition() throws {
        try withFixture { service, file in
            let before = try service.configure(expected: service.read())
            let modified = try String(contentsOf: file).replacingOccurrences(of: " --hook", with: " --changed")
            try modified.write(to: file, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try service.trust(expected: before))
            XCTAssertEqual(try String(contentsOf: file), modified)
        }
    }

    func testStopOnlyInstallationAddsPermissionWithoutDuplicatingOrRetrustingStop() throws {
        try withFixture { service, file in
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            let command = String(decoding: try encoder.encode(service.hookCommand), as: UTF8.self)
            let original = "[[hooks.Stop]]\n[[hooks.Stop.hooks]]\ntype = \"command\"\ncommand = \(command)\n"
            try original.write(to: file, atomically: true, encoding: .utf8)
            let stop = try XCTUnwrap(service.read().hook)
            let key = String(decoding: try encoder.encode(stop.key), as: UTF8.self)
            let withTrust = original + "\n[hooks.state.\(key)]\nenabled = true\ntrusted_hash = \"\(stop.currentHash)\"\n"
            try withTrust.write(to: file, atomically: true, encoding: .utf8)
            let before = try service.read()
            XCTAssertTrue(before.hook?.isActive == true)
            XCTAssertNil(before.permissionHook)
            XCTAssertFalse(before.allActive)
            let after = try service.configure(expected: before)
            XCTAssertTrue(after.hook?.isActive == true)
            XCTAssertEqual(after.hook?.key, before.hook?.key)
            XCTAssertEqual(after.hook?.currentHash, before.hook?.currentHash)
            XCTAssertEqual(after.permissionHook?.trustStatus, "untrusted")
            XCTAssertFalse(after.allActive)
            let configured = try String(contentsOf: file)
            XCTAssertEqual(configured.components(separatedBy: "[[hooks.Stop.hooks]]").count - 1, 1)
            XCTAssertEqual(configured.components(separatedBy: " --hook").count - 1, 3)
            let trusted = try service.trust(expected: after)
            XCTAssertTrue(trusted.allActive)
            let bytes = try Data(contentsOf: file)
            _ = try service.configure(expected: trusted)
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }

    func testTrustRejectsChangedPermissionDefinitionOnly() throws {
        try withFixture { service, file in
            let before = try service.configure(expected: service.read())
            let contents = try String(contentsOf: file)
            let boundary = try XCTUnwrap(contents.range(of: "PermissionRequest")).lowerBound
            let modified = String(contents[..<boundary])
                + contents[boundary...].replacingOccurrences(of: " --hook", with: " --changed")
            try modified.write(to: file, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try service.trust(expected: before))
            XCTAssertEqual(try String(contentsOf: file), modified)
        }
    }

    func testMalformedConfigurationIsNotModified() throws {
        let malformed = "notify = [\"unterminated\"\n"
        try withFixture(contents: malformed) { service, file in
            XCTAssertThrowsError(try service.read())
            XCTAssertEqual(try String(contentsOf: file), malformed)
        }
    }

    private func withFixture(contents: String? = nil,
                             _ test: (CodexConfigurationService, URL) throws -> Void) throws {
        guard let executable = ProcessInfo.processInfo.environment["AIBOX_TEST_CODEX_EXECUTABLE"] else {
            throw XCTSkip("Set AIBOX_TEST_CODEX_EXECUTABLE for isolated official Codex RPC tests.")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aibox-config-test-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("config.toml")
        if let contents { try contents.write(to: file, atomically: true, encoding: .utf8) }
        let helper = directory.appendingPathComponent("AIBox 空白 '測試' \"引號\"-notify")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let service = CodexConfigurationService(executableURL: URL(fileURLWithPath: executable), helperURL: helper,
            environment: ["CODEX_HOME": directory.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"])
        try test(service, file)
    }
}
