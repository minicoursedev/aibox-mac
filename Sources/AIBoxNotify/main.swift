import AIBoxCore
import Darwin
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--help" {
    print("使用方式：aibox-notify --hook < Hook.json\n或：aibox-notify '<Codex notify JSON>'\n需先啟動 AIBox App。")
    exit(0)
}
guard CommandLine.arguments.count == 2 else {
    fail("使用方式：aibox-notify --hook（由 stdin 接收 JSON）或 aibox-notify '<Codex notify JSON>'")
}

let isHook = CommandLine.arguments[1] == "--hook"
do {
    let payload = isHook ? FileHandle.standardInput.readDataToEndOfFile()
                         : Data(CommandLine.arguments[1].utf8)
    guard try TurnCompletion.parse(payload) != nil else {
        if isHook { print("{}") }
        exit(0)
    }
    let reply = try NotificationClient.send(payload)
    guard reply.accepted else { fail(reply.error ?? "AIBox 未接受通知。") }
    if isHook {
        // Observe only: never return a continuation, approval, or stop decision.
        print("{}")
    } else {
        let output = try JSONEncoder().encode(reply)
        FileHandle.standardOutput.write(output + Data("\n".utf8))
    }
} catch {
    fail(error.localizedDescription)
}
