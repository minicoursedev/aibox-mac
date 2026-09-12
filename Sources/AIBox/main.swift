import AIBoxCore
import AppKit

@MainActor
private final class SoundLevelSliderCell: NSSliderCell {
    var soundLevel: Double?

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let bar = NSRect(x: rect.minX, y: rect.midY - 6, width: rect.width, height: 12)
        let track = NSBezierPath(roundedRect: bar, xRadius: 6, yRadius: 6)
        NSColor.quaternaryLabelColor.setFill()
        track.fill()
        guard isEnabled, let soundLevel else { return }
        NSGraphicsContext.saveGraphicsState()
        track.addClip()
        (soundLevel >= doubleValue ? NSColor.systemOrange : NSColor.systemGreen).setFill()
        NSRect(x: bar.minX, y: bar.minY, width: bar.width * CGFloat(soundLevel / 100), height: bar.height).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

@MainActor
private final class UsageSummaryView: NSView {
    private var weeklyWindow: CodexUsageWindow?
    private var sparkWindow: CodexUsageWindow?
    private var isLoading = true
    private let textFont = NSFont.menuFont(ofSize: 14)
    private var textHeight: CGFloat {
        ceil("重置時間".size(withAttributes: [.font: textFont]).height)
    }

    override var intrinsicContentSize: NSSize {
        // Bottom inset, reset label, gap, bar, arc, gap, title, top inset.
        NSSize(width: 320, height: ceil(12 + textHeight + 10 + 7 + 3.5 + 52 + 10 + textHeight + 10))
    }

    func update(weekly: CodexUsageWindow?, spark: CodexUsageWindow?, isLoading: Bool = false) {
        weeklyWindow = weekly
        sparkWindow = spark
        self.isLoading = isLoading
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let gauges: [(String, CodexUsageWindow?)] = [
            ("周 TOKEN 用量", weeklyWindow),
            ("CODEX-5.3-Spark", sparkWindow),
        ]
        let lineWidth: CGFloat = 7
        let centerY: CGFloat = 12 + textHeight + 10 + lineWidth + lineWidth / 2
        let columnWidth = bounds.width / CGFloat(gauges.count)
        let barWidth = min(104, max(0, columnWidth - 20))
        let radius = barWidth / 2
        let barHeight: CGFloat = 7
        let barY = centerY - lineWidth / 2 - barHeight
        let trackColor = NSColor.labelColor.withAlphaComponent(0.25)

        for (index, gauge) in gauges.enumerated() {
            let column = NSRect(x: CGFloat(index) * columnWidth, y: 0,
                                width: columnWidth, height: bounds.height)
            let center = NSPoint(x: column.midX, y: centerY)
            let track = NSBezierPath()
            track.lineWidth = lineWidth
            track.lineCapStyle = .round
            track.appendArc(withCenter: center, radius: radius - lineWidth / 2,
                            startAngle: 0, endAngle: 180, clockwise: false)
            trackColor.setStroke()
            track.stroke()

            if let window = gauge.1 {
                let progress = CGFloat(max(0, min(100, window.remainingPercent))) / 100
                let arc = NSBezierPath()
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                arc.appendArc(withCenter: center, radius: radius - lineWidth / 2,
                              startAngle: 0, endAngle: 180 * progress, clockwise: false)
                NSColor.controlAccentColor.setStroke()
                arc.stroke()
            }

            let value: String
            if isLoading && gauge.1 == nil {
                value = "…"
            } else if let window = gauge.1 {
                value = "\(window.remainingPercent)%"
            } else {
                value = "—"
            }
            let valueAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
            let valueSize = value.size(withAttributes: valueAttributes)
            let valueCenterY = center.y + radius * 0.33
            value.draw(at: NSPoint(x: center.x - valueSize.width / 2,
                                   y: valueCenterY - valueSize.height / 2),
                       withAttributes: valueAttributes)

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: textFont,
                .foregroundColor: NSColor.labelColor,
            ]
            Self.drawCentered(gauge.0, in: column, y: center.y + radius + 10,
                              with: titleAttributes)

            let resetText: String
            let resetProgress: CGFloat
            if let window = gauge.1 {
                resetText = Self.resetText(for: window)
                let totalSeconds = max(1, Double(window.windowDurationMins) * 60)
                let remainingSeconds = max(0, window.resetsAt.timeIntervalSinceNow)
                resetProgress = max(0, min(1, remainingSeconds / totalSeconds))
            } else if isLoading {
                resetText = "讀取中…"
                resetProgress = 0
            } else {
                resetText = "重置時間未知"
                resetProgress = 0
            }

            let resetAttributes: [NSAttributedString.Key: Any] = [
                .font: textFont,
                .foregroundColor: NSColor.labelColor,
            ]

            let barRect = NSRect(x: center.x - barWidth / 2, y: barY,
                                 width: barWidth, height: barHeight)
            let trackBar = NSBezierPath(roundedRect: barRect, xRadius: 3.5, yRadius: 3.5)
            trackColor.setFill()
            trackBar.fill()
            if resetProgress > 0 {
                let remainingWidth = barRect.width * resetProgress
                let filledRect = NSRect(x: barRect.maxX - remainingWidth, y: barRect.minY,
                                        width: remainingWidth,
                                        height: barRect.height)
                let filledBar = NSBezierPath(roundedRect: filledRect,
                                             xRadius: 3.5, yRadius: 3.5)
                NSColor.controlAccentColor.setFill()
                filledBar.fill()
            }

            let resetTextY = barY - 10 - resetText.size(withAttributes: resetAttributes).height
            Self.drawCentered(resetText, in: column, y: resetTextY, with: resetAttributes)
        }
    }

    private static func drawCentered(_ text: String, in column: NSRect, y: CGFloat,
                                     with attributes: [NSAttributedString.Key: Any]) {
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: column.midX - size.width / 2, y: y),
                  withAttributes: attributes)
    }

    private static func resetText(for window: CodexUsageWindow) -> String {
        let seconds = max(0, Int(ceil(window.resetsAt.timeIntervalSinceNow)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 { return "\(days)天\(hours)小時後" }
        if hours > 0 { return "\(hours)小時\(minutes)分後" }
        if minutes > 0 { return "\(minutes)分後" }
        return "即將重置"
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, NSTabViewDelegate {
    private let history = CompletionHistory(defaults: .standard)
    private let payloadLog = NotificationPayloadLog()
    private let server = NotificationServer()
    private let boxStatus = NSTextField(wrappingLabelWithString: "box：尚未連線")
    private lazy var box: BoxBluetoothClient = BoxBluetoothClient(
        onStatus: { [weak self] status in
            self?.boxStatus.stringValue = status
            self?.statusItem?.button?.toolTip = "AIBox：執行中\n\(status)"
            if let menu = self?.statusItem?.menu { self?.rebuild(menu) }
        },
        onConnectionChange: { [weak self] connected in
            self?.updateStatusIcon(isConnected: connected)
            if !connected { self?.updateSoundMeter(nil) }
        },
        onPairingChange: { [weak self] state in
            guard let self else { return }
            self.unpairBoxButton?.isEnabled = self.box.canUnpair
            self.boxPairingWindow.update(state)
            if state.isSelecting && self.boxPairingWindow.window?.isVisible != true {
                self.boxPairingWindow.showWindow(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        },
        onShake: { [weak self] in self?.alertFlow.shake() },
        onSoundReading: { [weak self] peak, _ in
            self?.updateSoundMeter(peak)
        }
    )
    private lazy var boxPairingWindow = BoxPairingWindow(
        onSearch: { [weak self] in self?.box.beginSelection() },
        onSelect: { [weak self] in self?.box.selectDevice($0) },
        onAnswer: { [weak self] in self?.box.confirmColor($0) },
        onRetry: { [weak self] in self?.box.retryIdentification() },
        onCancel: { [weak self] in self?.box.cancelSelection() }
    )
    private lazy var alertFlow: ConversationAlertFlow = ConversationAlertFlow(
        history: history,
        setPattern: { [weak self] in self?.box.setPattern($0) },
        openURL: { NSWorkspace.shared.open($0) },
        onFailure: { [weak self] in self?.showError($0) }
    )
    private lazy var notificationMenu = ConversationNotificationMenu(
        openURL: { NSWorkspace.shared.open($0) },
        onFailure: { [weak self] message in self?.showError(message) }
    )
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var settingsTabs: NSTabView?
    private var detectShake = UserDefaults.standard.object(forKey: "aibox.detectShake") as? Bool ?? true
    private var detectSound = UserDefaults.standard.object(forKey: "aibox.detectSound") as? Bool ?? true
    private var soundSensitivity = min(100, max(0,
        UserDefaults.standard.object(forKey: "aibox.soundSensitivity") as? Int ?? 50))
    private var soundSensitivitySlider: NSSlider?
    private let soundSensitivityValue = NSTextField(labelWithString: "")
    private var latestSoundPeak: Int?
    private let soundMeterValue = NSTextField(labelWithString: "等待收音…")
    private let soundThresholdStatus = NSTextField(labelWithString: "")
    private var soundMeterTimeout: Timer?
    private var unpairBoxButton: NSButton?
    private var blinkIntervalTenths = min(100, max(1,
        UserDefaults.standard.object(forKey: "aibox.blinkIntervalTenths") as? Int ?? 10))
    private var lightColors: BoxLightColors = {
        guard let data = UserDefaults.standard.data(forKey: "aibox.lightColors"),
              let colors = try? JSONDecoder().decode(BoxLightColors.self, from: data) else {
            return BoxLightColors()
        }
        return colors
    }()
    private let usageView = UsageSummaryView()
    private let codexStatus = NSTextField(wrappingLabelWithString: "尚未檢查 Codex 設定。")
    private let codexConfigPath = NSTextField(wrappingLabelWithString: "")
    private let notificationStatus = NSTextField(wrappingLabelWithString: "尚未收到通知。")
    private let remoteConnection = RemoteNotificationConnection()
    private let remoteHost = NSTextField(string: UserDefaults.standard.string(forKey: "aibox.remoteHost") ?? "")
    private let remoteStatus = NSTextField(wrappingLabelWithString: "尚未連線")
    private var remoteButton: NSButton!
    private var setupButton: NSButton!
    private var permissionRequestButton: NSButton!
    private var userInputRequestButton: NSButton!
    private var setupBusy = false
    private var acceptsPermissionRequests =
        UserDefaults.standard.object(forKey: "aibox.acceptPermissionRequests") as? Bool ?? true
    private var acceptsUserInputRequests =
        UserDefaults.standard.object(forKey: "aibox.acceptUserInputRequests") as? Bool ?? true
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm:ss"
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try server.start { [weak self] payload in
                guard let self else {
                    return BridgeReply(accepted: false, visibleCount: 0, error: "AIBox 已停止。")
                }
                return self.receive(payload)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "AIBox 無法啟動"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon(isConnected: false)
        if let button = statusItem.button {
            button.toolTip = "AIBox：執行中"
            button.setAccessibilityLabel("AIBox")
        }
        let menu = NSMenu(title: "AIBox")
        menu.delegate = self
        statusItem.menu = menu
        rebuild(menu)
        box.setColors(lightColors)
        box.setBlinkInterval(blinkIntervalTenths)
        box.setDetection(shake: detectShake, sound: detectSound)
        box.setSoundSensitivity(soundSensitivity)
        if let latest = history.latestUnopened {
            box.setPattern(latest.notification.type == "PermissionRequest" || latest.notification.type == "UserInputRequest" ? .permission : .completion)
        }
        box.start()
        remoteConnection.onStatus = { [weak self] status in
            guard let self else { return }
            self.remoteStatus.stringValue = status
            self.remoteHost.isEnabled = !self.remoteConnection.isEnabled
            self.remoteButton?.title = self.remoteConnection.isEnabled ? "斷線" : "儲存並連線"
        }
        if UserDefaults.standard.bool(forKey: "aibox.remoteEnabled") {
            remoteConnection.connect(host: remoteHost.stringValue)
        }
        if box.needsDeviceSelection { openBoxPairing() }
        refreshUsage()
    }

    private func updateStatusIcon(isConnected: Bool) {
        var image = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: "AIBox")
        if !isConnected {
            image = image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
        }
        image?.isTemplate = isConnected
        statusItem?.button?.image = image
    }

    private func receive(_ payload: Data) -> BridgeReply {
        do {
            try payloadLog.append(payload)
        } catch {
            return BridgeReply(accepted: false, visibleCount: history.recent.count,
                               error: "無法保存通知 payload：\(error.localizedDescription)")
        }
        do {
            guard let notification = try TurnCompletion.parse(payload) else {
                return BridgeReply(accepted: false, visibleCount: history.recent.count,
                                   error: "此事件不是 AIBox 支援的對話通知。")
            }
            if notification.type == "PermissionRequest", !acceptsPermissionRequests {
                return BridgeReply(accepted: true, visibleCount: history.recent.count)
            }
            if notification.type == "UserInputRequest", !acceptsUserInputRequests {
                return BridgeReply(accepted: true, visibleCount: history.recent.count)
            }
            if notification.type == "Stop" {
                struct StopPayload: Decodable { let transcript_path: String? }
                let stop = try JSONDecoder().decode(StopPayload.self, from: payload)
                guard let path = stop.transcript_path, !path.isEmpty else {
                    return BridgeReply(accepted: true, visibleCount: history.recent.count)
                }
            }
            alertFlow.receive(notification)
            updateNotificationStatus()
            if let menu = statusItem?.menu { rebuild(menu) }
            return BridgeReply(accepted: true, visibleCount: history.recent.count)
        } catch {
            return BridgeReply(accepted: false, visibleCount: history.recent.count,
                               error: "通知格式不符，需包含 type、thread-id 與 turn-id。")
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuild(menu)
        refreshUsage()
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.font = .menuFont(ofSize: 14)
        menu.addItem(menuLabel("AIBox：執行中"))
        menu.addItem(menuLabel(boxStatus.stringValue))
        let usageItem = NSMenuItem()
        usageView.frame = NSRect(origin: .zero, size: usageView.intrinsicContentSize)
        usageItem.view = usageView
        menu.addItem(usageItem)
        menu.addItem(.separator())
        menu.addItem(menuLabel("最近通知（最多 20 筆）"))
        if history.recent.isEmpty {
            menu.addItem(menuLabel("尚無通知"))
        } else {
            for record in history.recent {
                let text = record.notification.displayText
                let singleLine = text.components(separatedBy: .newlines).joined(separator: " ")
                let summary = String(singleLine.prefix(64)) + (singleLine.count > 64 ? "…" : "")
                let item = notificationMenu.item(notification: record.notification,
                    title: "\(timeFormatter.string(from: record.receivedAt))  \(summary)",
                    onOpened: { [weak self] in self?.alertFlow.didOpen(record.id) })
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "設定…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "結束", action: #selector(quitAIBox), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func menuLabel(_ title: String) -> NSMenuItem {
        // Read-only information is not a disabled command; draw it at normal
        // text contrast while keeping the row noninteractive.
        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 14)
        label.textColor = .labelColor
        let size = label.fittingSize
        let row = NSView(frame: NSRect(x: 0, y: 0,
            width: max(usageView.intrinsicContentSize.width, size.width + 28),
            height: ceil(size.height) + 8))
        label.frame = NSRect(x: 14, y: 4, width: row.bounds.width - 28, height: size.height)
        label.autoresizingMask = [.width]
        row.addSubview(label)
        let item = NSMenuItem()
        item.title = title
        item.view = row
        return item
    }

    private var usageRefreshInFlight = false

    private func refreshUsage() {
        guard !usageRefreshInFlight else { return }
        usageRefreshInFlight = true
        usageView.update(weekly: nil, spark: nil, isLoading: true)

        Task { @MainActor in
            defer { usageRefreshInFlight = false }
            do {
                let service = try codexService()
                let usage = try await Task.detached { try service.readUsage() }.value
                usageView.update(weekly: usage.weekly, spark: usage.codex53Spark)
            } catch {
                usageView.update(weekly: nil, spark: nil)
            }
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 540),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "AIBox 設定"
            window.isReleasedWhenClosed = false
            window.delegate = self
            setupButton = NSButton(title: "設定 Codex", target: self, action: #selector(setupCodex))
            setupButton.bezelStyle = .rounded
            permissionRequestButton = NSButton(
                checkboxWithTitle: "接收 PermissionRequest（授權請求通知）",
                target: self,
                action: #selector(togglePermissionRequests))
            permissionRequestButton.state = acceptsPermissionRequests ? .on : .off
            userInputRequestButton = NSButton(
                checkboxWithTitle: "接收問答提醒（等待回答／選擇方案）",
                target: self, action: #selector(toggleUserInputRequests))
            userInputRequestButton.state = acceptsUserInputRequests ? .on : .off
            userInputRequestButton.toolTip = "關閉後不新增問答提醒或切換燈號；既有清單及原始通知紀錄保留。"
            codexConfigPath.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            codexConfigPath.textColor = .secondaryLabelColor
            notificationStatus.textColor = .secondaryLabelColor
            let connectButton = NSButton(title: "重新連線", target: self, action: #selector(connectBox))
            connectButton.bezelStyle = .rounded
            let selectBoxButton = NSButton(title: "選擇／更換裝置…", target: self, action: #selector(openBoxPairing))
            selectBoxButton.bezelStyle = .rounded
            let unpairButton = NSButton(title: "解除配對", target: self, action: #selector(unpairBox))
            unpairButton.bezelStyle = .rounded
            unpairBoxButton = unpairButton
            let connectionButtons = NSStackView(views: [connectButton, selectBoxButton, unpairButton])
            connectionButtons.spacing = 10
            let shakeButton = NSButton(checkboxWithTitle: "偵測晃動", target: self, action: #selector(toggleDetection(_:)))
            shakeButton.tag = 0
            shakeButton.state = detectShake ? .on : .off
            shakeButton.toolTip = "控制晃動開啟通知；不影響開機搖晃 2 秒重新配對。"
            let soundButton = NSButton(checkboxWithTitle: "偵測聲音", target: self, action: #selector(toggleDetection(_:)))
            soundButton.tag = 1
            soundButton.state = detectSound ? .on : .off
            soundButton.toolTip = "控制拍手等突發聲音開啟通知。"
            for button in [shakeButton, soundButton] { button.font = .systemFont(ofSize: 14) }
            let detectionRow = NSStackView(views: [shakeButton, soundButton])
            detectionRow.spacing = 24
            let sensitivitySlider = NSSlider()
            sensitivitySlider.cell = SoundLevelSliderCell()
            sensitivitySlider.minValue = 0
            sensitivitySlider.maxValue = 100
            sensitivitySlider.doubleValue = Double(soundSensitivity)
            sensitivitySlider.target = self
            sensitivitySlider.action = #selector(changeSoundSensitivity(_:))
            sensitivitySlider.isContinuous = true
            sensitivitySlider.isEnabled = detectSound
            sensitivitySlider.setAccessibilityLabel("收音敏感度")
            sensitivitySlider.toolTip = "拖曳白色拉桿比對目前音量；音量超過拉桿位置時立即轉橘色。"
            soundSensitivitySlider = sensitivitySlider
            soundSensitivityValue.stringValue = "設定 \(soundSensitivity)"
            soundSensitivityValue.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            soundMeterValue.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            let soundValues = NSStackView(views: [soundSensitivityValue, soundMeterValue])
            soundValues.distribution = .equalSpacing
            let soundScale = NSStackView(views: [NSTextField(labelWithString: "0"), NSTextField(labelWithString: "100")])
            soundScale.distribution = .equalSpacing
            for label in soundScale.arrangedSubviews.compactMap({ $0 as? NSTextField }) {
                label.font = .systemFont(ofSize: 11)
                label.textColor = .secondaryLabelColor
            }
            let soundTitle = NSTextField(labelWithString: "收音調整")
            soundTitle.font = .systemFont(ofSize: 14, weight: .semibold)
            soundThresholdStatus.font = .systemFont(ofSize: 12, weight: .semibold)
            let soundTitleRow = NSStackView(views: [soundTitle, soundThresholdStatus])
            soundTitleRow.spacing = 12
            let soundHelp = NSTextField(wrappingLabelWithString:
                "白色拉桿是設定位置，填色是目前音量。拖過音量交界時立即變色，方便邊聽邊調整。")
            soundHelp.font = .systemFont(ofSize: 12)
            soundHelp.textColor = .secondaryLabelColor
            let soundSettings = NSStackView(views: [soundTitleRow, soundValues, sensitivitySlider, soundScale, soundHelp])
            soundSettings.orientation = .vertical
            soundSettings.alignment = .leading
            soundSettings.spacing = 6
            sensitivitySlider.widthAnchor.constraint(equalToConstant: 478).isActive = true
            for view in [soundValues, soundScale, soundHelp] {
                view.widthAnchor.constraint(equalTo: sensitivitySlider.widthAnchor).isActive = true
            }
            updateSoundMeter(nil)
            let note = NSTextField(wrappingLabelWithString:
                "Hook 需確認信任後才會執行。設定後請重新開啟 Codex 對話；若尚未載入，請自行重啟 Codex。保持 AIBox 執行，收到通知後點擊該筆即可開啟對應對話。Stop 表示進入停止處理；其他 Hook 仍可能要求續跑。")
            note.font = .systemFont(ofSize: 12)
            note.textColor = .secondaryLabelColor
            let colorSettings = LightColorSettingsView(
                colors: lightColors, intervalTenths: blinkIntervalTenths,
                onIntervalChange: { [weak self] tenths in
                    self?.blinkIntervalTenths = tenths
                    UserDefaults.standard.set(tenths, forKey: "aibox.blinkIntervalTenths")
                    self?.box.setBlinkInterval(tenths)
                }
            ) { [weak self] colors in
                self?.lightColors = colors
                if let data = try? JSONEncoder().encode(colors) {
                    UserDefaults.standard.set(data, forKey: "aibox.lightColors")
                }
                self?.box.setColors(colors)
            }
            let tabs = NSTabView()
            remoteHost.placeholderString = "SSH 主機別名，例如 srv"
            remoteHost.setAccessibilityLabel("遠端 SSH 主機")
            remoteHost.widthAnchor.constraint(equalToConstant: 280).isActive = true
            remoteButton = NSButton(title: remoteConnection.isEnabled ? "斷線" : "儲存並連線",
                                    target: self, action: #selector(toggleRemoteConnection))
            remoteButton.bezelStyle = .rounded
            let remoteRow = NSStackView(views: [remoteHost, remoteButton])
            remoteRow.spacing = 10
            remoteStatus.font = .systemFont(ofSize: 12)
            remoteStatus.textColor = .secondaryLabelColor
            let remoteHelp = NSTextField(wrappingLabelWithString:
                "沿用 SSH 金鑰及已信任的主機。連線時安裝遠端通知腳本，斷線後自動重試；下次開啟 AIBox 會恢復連線。需 Python 3。\n\n首次使用還需在遠端 Codex 設定並信任 Hook，指令如下。完成設定後請重新開啟遠端對話。")
            remoteHelp.font = .systemFont(ofSize: 12)
            let remoteCommand = NSTextField(wrappingLabelWithString: "python3 ~/.codex/aibox/notify.py")
            remoteCommand.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            remoteCommand.isSelectable = true
            tabs.font = .systemFont(ofSize: 14)
            tabs.translatesAutoresizingMaskIntoConstraints = false
            let pages: [(id: String, title: String, summary: String, views: [NSView])] = [
                ("sensors", "感應", "選擇用晃動或聲音開啟通知，並即時調整收音。",
                 [detectionRow, soundSettings]),
                ("lights", "燈號", "設定待機與提醒的顏色。燈號對應最新尚未開啟的通知；等待回答沿用授權請求燈色。",
                 [colorSettings]),
                ("notifications", "通知", "回覆停止通知會自動接收。其他提醒可個別開關，最近 20 筆通知可從選單列查看。",
                 [permissionRequestButton, userInputRequestButton, notificationStatus]),
                ("device", "裝置", "管理目前配對的 AIBox，或選擇另一台裝置。",
                 [boxStatus, connectionButtons]),
                ("remote", "遠端", "接收一台 SSH 主機的回覆停止、授權請求及問答提醒。Mac 必須保持在線。",
                 [remoteRow, remoteStatus, remoteHelp, remoteCommand]),
                ("codex", "Codex", "將 Codex 的回覆與詢問提醒傳到 AIBox。",
                 [setupButton, codexStatus, codexConfigPath, note])
            ]
            for page in pages {
                let heading = NSTextField(labelWithString: page.title)
                heading.font = .systemFont(ofSize: 22, weight: .semibold)
                let summary = NSTextField(wrappingLabelWithString: page.summary)
                summary.font = .systemFont(ofSize: 13)
                summary.textColor = .secondaryLabelColor
                let stack = NSStackView(views: [heading, summary] + page.views)
                stack.orientation = .vertical
                stack.alignment = .leading
                stack.spacing = 20
                stack.setCustomSpacing(8, after: heading)
                stack.setCustomSpacing(28, after: summary)
                stack.translatesAutoresizingMaskIntoConstraints = false
                let content = NSView()
                content.addSubview(stack)
                NSLayoutConstraint.activate([
                    stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
                    stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
                    stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
                    stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -28),
                    summary.widthAnchor.constraint(equalTo: stack.widthAnchor)
                ])
                for label in page.views.compactMap({ $0 as? NSTextField }) {
                    label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                }
                let item = NSTabViewItem(identifier: page.id)
                item.label = page.title
                item.view = content
                tabs.addTabViewItem(item)
            }
            tabs.delegate = self
            settingsTabs = tabs
            window.contentView!.addSubview(tabs)
            NSLayoutConstraint.activate([
                tabs.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
                tabs.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
                tabs.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
                tabs.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20)
            ])
            window.center()
            settingsWindow = window
        }
        unpairBoxButton?.isEnabled = box.canUnpair
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        updateSoundMonitoring()
        updateNotificationStatus()
        if !setupBusy { runCodexSetup(configure: false) }
    }

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        updateSoundMonitoring()
    }
    private func updateSoundMonitoring() {
        let visible = settingsWindow?.isVisible == true
            && settingsTabs?.selectedTabViewItem?.identifier as? String == "sensors"
        box.setSoundMonitoring(visible)
        if !visible { updateSoundMeter(nil) }
    }

    private func updateNotificationStatus() {
        if let latest = history.recent.first {
            notificationStatus.stringValue = "最後收到通知：\(timeFormatter.string(from: latest.receivedAt))"
        } else {
            notificationStatus.stringValue = "尚未收到通知。"
        }
    }

    @objc private func setupCodex() { runCodexSetup(configure: true) }
    @objc private func unpairBox() { box.unpair() }

    @objc private func openBoxPairing() {
        if boxPairingWindow.window?.isVisible != true { box.beginSelection() }
        boxPairingWindow.update(box.pairingState)
        NSApp.activate(ignoringOtherApps: true)
        boxPairingWindow.showWindow(nil)
        boxPairingWindow.window?.makeKeyAndOrderFront(nil)
    }
    @objc private func connectBox() {
        if box.needsDeviceSelection { openBoxPairing() }
        else { box.reconnect() }
    }
    @objc private func togglePermissionRequests() {
        acceptsPermissionRequests = permissionRequestButton.state == .on
        UserDefaults.standard.set(acceptsPermissionRequests, forKey: "aibox.acceptPermissionRequests")
    }
    @objc private func toggleUserInputRequests() {
        acceptsUserInputRequests = userInputRequestButton.state == .on
        UserDefaults.standard.set(acceptsUserInputRequests, forKey: "aibox.acceptUserInputRequests")
    }
    @objc private func toggleDetection(_ sender: NSButton) {
        if sender.tag == 0 {
            detectShake = sender.state == .on
            UserDefaults.standard.set(detectShake, forKey: "aibox.detectShake")
        } else {
            detectSound = sender.state == .on
            UserDefaults.standard.set(detectSound, forKey: "aibox.detectSound")
            soundSensitivitySlider?.isEnabled = detectSound
            updateSoundMeter(nil)
        }
        box.setDetection(shake: detectShake, sound: detectSound)
    }
    @objc private func changeSoundSensitivity(_ sender: NSSlider) {
        let value = Int(sender.doubleValue.rounded())
        sender.doubleValue = Double(value)
        guard value != soundSensitivity else { return }
        soundSensitivity = value
        soundSensitivityValue.stringValue = "設定 \(value)"
        refreshSoundMeter()
        UserDefaults.standard.set(value, forKey: "aibox.soundSensitivity")
        box.setSoundSensitivity(value)
    }
    private func updateSoundMeter(_ peak: Int?) {
        soundMeterTimeout?.invalidate()
        latestSoundPeak = peak
        refreshSoundMeter()
        guard detectSound, peak != nil else { return }
        let timer = Timer(timeInterval: 2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateSoundMeter(nil) }
        }
        soundMeterTimeout = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func refreshSoundMeter() {
        guard let slider = soundSensitivitySlider, let cell = slider.cell as? SoundLevelSliderCell else { return }
        defer { slider.needsDisplay = true }
        guard detectSound, let peak = latestSoundPeak else {
            cell.soundLevel = nil
            soundMeterValue.stringValue = detectSound ? "等待收音…" : "聲音偵測已關閉"
            soundThresholdStatus.stringValue = ""
            slider.setAccessibilityValueDescription(soundMeterValue.stringValue)
            return
        }
        let decibels = peak > 0 ? 20 * log10(Double(peak) / 32768) : -90
        let level = min(100, max(0, (decibels + 90) / 90 * 100))
        cell.soundLevel = level
        let above = level >= Double(soundSensitivity)
        soundThresholdStatus.stringValue = above ? "音量高於拉桿" : "音量低於拉桿"
        soundThresholdStatus.textColor = above ? .systemOrange : .secondaryLabelColor
        soundMeterValue.stringValue = "目前音量 \(Int(level.rounded()))"
        slider.setAccessibilityValueDescription("設定 \(soundSensitivity)，\(soundMeterValue.stringValue)")
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        box.setSoundMonitoring(false)
        updateSoundMeter(nil)
    }
    @objc private func quitAIBox() { NSApp.terminate(nil) }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "無法開啟對話"
        alert.informativeText = message
        alert.runModal()
    }

    private func codexService() throws -> CodexConfigurationService {
        let scheme = URL(string: "codex://threads")!
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: scheme),
              let bundle = Bundle(url: appURL),
              let executable = bundle.url(forResource: "codex", withExtension: nil),
              let helper = Bundle.main.executableURL?.deletingLastPathComponent()
                  .appendingPathComponent("aibox-notify") else {
            throw CodexSetupError.unavailable("找不到 Codex App 或 aibox-notify，請確認安裝與建置結果。")
        }
        return CodexConfigurationService(executableURL: executable, helperURL: helper)
    }

    private func runCodexSetup(configure: Bool) {
        guard !setupBusy else { return }
        setupBusy = true
        setupButton.isEnabled = false
        codexStatus.stringValue = "正在讀取 Codex 設定…"
        Task { @MainActor in
            defer {
                setupBusy = false
                setupButton.isEnabled = true
            }
            do {
                let service = try codexService()
                var configuration = try await Task.detached { try service.read() }.value
                codexConfigPath.stringValue = configuration.filePath
                if configure && !configuration.allConfigured {
                    codexStatus.stringValue = "正在設定回覆停止、授權請求與問答提醒…"
                    let expected = configuration
                    configuration = try await Task.detached {
                        try service.configure(expected: expected)
                    }.value
                }
                if configure && !configuration.allActive {
                    let pending = configuration.configuredHooks.filter { !$0.isActive }
                    let alert = NSAlert()
                    alert.messageText = "信任並啟用 AIBox 對話通知 Hook？"
                    let commands = pending.map { "事件：\($0.eventName)\n程式：\($0.command)" }.joined(separator: "\n\n")
                    alert.informativeText = commands + "\n\nCodex 將把對話 ID、輪次 ID，以及最後回覆、授權請求或問題與選項傳給本機 AIBox。此程式只接收通知，不代答問題、不同意或拒絕授權，不要求續跑。"
                    alert.addButton(withTitle: "取消")
                    alert.addButton(withTitle: "信任並啟用")
                    guard alert.runModal() == .alertSecondButtonReturn else {
                        codexStatus.stringValue = "尚未信任的通知 Hook 未啟用；原本已啟用的 Hook 不受影響。"
                        return
                    }
                    codexStatus.stringValue = "正在記錄此 Hook 的信任確認…"
                    let expected = configuration
                    configuration = try await Task.detached { try service.trust(expected: expected) }.value
                }
                if !configuration.hooksEnabled {
                    codexStatus.stringValue = "Codex 的 hooks 功能已停用；AIBox 未更改此設定。"
                } else {
                    func status(_ hook: CodexHookStatus?) -> String {
                        guard let hook else { return "未設定" }
                        return hook.isActive ? "已設定並信任" : "待信任／啟用"
                    }
                    codexStatus.stringValue = "回覆停止：\(status(configuration.hook))\n授權請求：\(status(configuration.permissionHook))\n問答提醒：\(status(configuration.userInputHook))\n設定狀態不代表已收到通知。"
                }
            } catch {
                codexStatus.stringValue = error.localizedDescription
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func toggleRemoteConnection() {
        if remoteConnection.isEnabled {
            UserDefaults.standard.set(false, forKey: "aibox.remoteEnabled")
            remoteConnection.disconnect()
        } else {
            let host = remoteHost.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            remoteHost.stringValue = host
            remoteConnection.connect(host: host)
            if remoteConnection.isEnabled {
                UserDefaults.standard.set(host, forKey: "aibox.remoteHost")
                UserDefaults.standard.set(true, forKey: "aibox.remoteEnabled")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        remoteConnection.disconnect()
        box.stop()
        server.stop()
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { application.run() }
}
