import Foundation

/// One user-selected SSH host. The remote socket is private to the SSH account.
@MainActor
public final class RemoteNotificationConnection {
    public private(set) var isEnabled = false
    public var onStatus: ((String) -> Void)?
    public private(set) var status = "尚未連線"
    private var host = ""
    private var process: Process?
    private var input: Pipe?
    private var retry: DispatchWorkItem?
    private var deadline: DispatchWorkItem?
    private var generation = UUID()
    private var retryDelay: Double = 2
    private let executable: URL

    public init(executable: URL = URL(fileURLWithPath: "/usr/bin/ssh")) {
        self.executable = executable
    }

    public static func validHost(_ host: String) -> Bool {
        host.range(of: #"^[A-Za-z0-9][A-Za-z0-9._@-]{0,252}$"#,
                   options: .regularExpression) != nil
    }

    public func connect(host: String) {
        disconnect()
        guard Self.validHost(host) else {
            update("請輸入 SSH 主機別名，例如 srv；不含空白或連線參數。")
            return
        }
        self.host = host
        isEnabled = true
        retryDelay = 2
        prepare()
    }

    public func disconnect() {
        isEnabled = false
        generation = UUID()
        retry?.cancel()
        deadline?.cancel()
        retry = nil
        deadline = nil
        try? input?.fileHandleForWriting.close()
        input = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        update("已斷線")
    }

    private func update(_ message: String) {
        status = message
        onStatus?(message)
    }

    private var options: [String] {
        ["-T", "-S", "none", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
         "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15",
         "-o", "ServerAliveCountMax=2", "-o", "ExitOnForwardFailure=yes",
         "-o", "ForwardAgent=no", "-o", "ForwardX11=no"]
    }

    private func prepare() {
        update("正在連線至 \(host)…")
        do {
            let packaged = Bundle.main.resourceURL?.appendingPathComponent("AIBoxMac_AIBoxCore.bundle")
            let resources = packaged.flatMap { Bundle(url: $0) } ?? Bundle.module
            let directory = resources.resourceURL!
            let script = try String(contentsOf: directory.appendingPathComponent("prepare.py"), encoding: .utf8)
            let sender = directory.appendingPathComponent("notify.py")
            let quoted = "'" + script.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
            var response = ""
            launch(arguments: options + [host, "python3 -c " + quoted], source: sender,
                   output: { response += $0 }, finished: { [weak self] code in
                guard let self else { return }
                guard code == 0,
                      let line = response.components(separatedBy: "\n").first(where: { $0.hasPrefix("AIBOX_SOCKET=") }) else {
                    self.failed(response)
                    return
                }
                let socket = String(line.dropFirst("AIBOX_SOCKET=".count))
                guard socket.hasPrefix("/"), socket.utf8.count < 100,
                      !socket.contains(":"), !socket.contains("\r") else {
                    self.failed("遠端傳回的通知路徑無效。")
                    return
                }
                self.startTunnel(socket: socket)
            })
        } catch { failed(error.localizedDescription) }
    }

    private func startTunnel(socket: String) {
        var response = ""
        let local = "/tmp/aibox-mac-\(getuid())/notify.sock"
        launch(arguments: options + ["-R", socket + ":" + local, host,
                                     "printf 'AIBOX_READY\\n'; cat >/dev/null"],
               source: nil, output: { [weak self] text in
            guard let self else { return }
            response += text
            if response.components(separatedBy: "\n").contains("AIBOX_READY") {
                self.deadline?.cancel()
                self.retryDelay = 2
                self.update("已連線至 \(self.host)；等待遠端 Hook 通知。")
            }
        }, finished: { [weak self] _ in
            self?.failed(response.replacingOccurrences(of: "AIBOX_READY", with: ""))
        })
    }

    private func failed(_ detail: String) {
        guard isEnabled else { return }
        deadline?.cancel()
        let message = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        update("連線中斷，\(Int(retryDelay)) 秒後重試。" + (message.isEmpty ? "" : "\n" + String(message.suffix(600))))
        let token = generation
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isEnabled, self.generation == token else { return }
                self.prepare()
            }
        }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: work)
        retryDelay = min(retryDelay * 2, 30)
    }

    private func launch(arguments: [String], source: URL?,
                        output: @escaping (String) -> Void, finished: @escaping (Int32) -> Void) {
        let child = Process()
        child.executableURL = executable
        child.arguments = arguments
        let stdin = Pipe()
        let stream = Pipe()
        child.standardOutput = stream
        child.standardError = stream
        let token = generation
        do {
            if let source {
                let file = try FileHandle(forReadingFrom: source)
                defer { try? file.close() }
                child.standardInput = file
                try child.run()
            } else {
                child.standardInput = stdin
                try child.run()
            }
        } catch { failed(error.localizedDescription); return }
        process = child
        input = stdin
        deadline?.cancel()
        let timeout = DispatchWorkItem { [weak child] in
            if let child, child.isRunning { child.terminate() }
        }
        deadline = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
        DispatchQueue.global(qos: .utility).async {
            while true {
                let bytes = stream.fileHandleForReading.availableData
                if bytes.isEmpty { break }
                let text = String(decoding: bytes, as: UTF8.self)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token, self.isEnabled else { return }
                    output(text)
                }
            }
            child.waitUntilExit()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token, self.isEnabled else { return }
                self.deadline?.cancel()
                self.process = nil
                self.input = nil
                finished(child.terminationStatus)
            }
        }
    }
}
