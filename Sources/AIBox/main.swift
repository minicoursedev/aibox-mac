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
        ceil(String(localized: "Reset time", bundle: AppLanguage.bundle).size(withAttributes: [.font: textFont]).height)
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
            (String(localized: "Weekly TOKEN usage", bundle: AppLanguage.bundle), weeklyWindow),
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
                resetText = String(localized: "Loading…", bundle: AppLanguage.bundle)
                resetProgress = 0
            } else {
                resetText = String(localized: "Reset time unknown", bundle: AppLanguage.bundle)
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

        if days > 0 { return String(localized: "In \(String(days))d \(String(hours))h", bundle: AppLanguage.bundle) }
        if hours > 0 { return String(localized: "In \(String(hours))h \(String(minutes))m", bundle: AppLanguage.bundle) }
        if minutes > 0 { return String(localized: "In \(String(minutes))m", bundle: AppLanguage.bundle) }
        return String(localized: "Resetting soon", bundle: AppLanguage.bundle)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, NSTabViewDelegate {
    private let history = CompletionHistory(defaults: .standard)
    private let payloadLog = NotificationPayloadLog()
    private let server = NotificationServer()
    private let boxStatus = NSTextField(wrappingLabelWithString: String(localized: "box: Not connected", bundle: AppLanguage.bundle))
    private lazy var box: BoxBluetoothClient = BoxBluetoothClient(
        onStatus: { [weak self] status in
            self?.boxStatus.stringValue = status
            self?.statusItem?.button?.toolTip = String(localized: "AIBox: Running\n\(String(status))", bundle: AppLanguage.bundle)
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
    private var rebuildSettingsContent = false
    private var settingsTabs: NSTabView?
    private var detectShake = UserDefaults.standard.object(forKey: "aibox.detectShake") as? Bool ?? true
    private var detectSound = UserDefaults.standard.object(forKey: "aibox.detectSound") as? Bool ?? true
    private var soundSensitivity = min(100, max(0,
        UserDefaults.standard.object(forKey: "aibox.soundSensitivity") as? Int ?? 50))
    private var soundSensitivitySlider: NSSlider?
    private let soundSensitivityValue = NSTextField(labelWithString: "")
    private var latestSoundPeak: Int?
    private let soundMeterValue = NSTextField(labelWithString: String(localized: "Waiting for sound…", bundle: AppLanguage.bundle))
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
    private let codexStatus = NSTextField(wrappingLabelWithString: String(localized: "Codex settings have not been checked.", bundle: AppLanguage.bundle))
    private var codexStatusText: (() -> String)?
    private let codexConfigPath = NSTextField(wrappingLabelWithString: "")
    private let notificationStatus = NSTextField(wrappingLabelWithString: String(localized: "No notifications received yet.", bundle: AppLanguage.bundle))
    private let remoteConnection = RemoteNotificationConnection()
    private let remoteHost = NSTextField(string: UserDefaults.standard.string(forKey: "aibox.remoteHost") ?? "")
    private let remoteStatus = NSTextField(wrappingLabelWithString: String(localized: "Not connected", bundle: AppLanguage.bundle))
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
                    return BridgeReply(accepted: false, visibleCount: 0, error: String(localized: "AIBox has stopped.", bundle: AppLanguage.bundle))
                }
                return self.receive(payload)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "AIBox could not start", bundle: AppLanguage.bundle)
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon(isConnected: false)
        if let button = statusItem.button {
            button.toolTip = String(localized: "AIBox: Running", bundle: AppLanguage.bundle)
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
            self.remoteButton?.title = self.remoteConnection.isEnabled ? String(localized: "Disconnect", bundle: AppLanguage.bundle) : String(localized: "Save and Connect", bundle: AppLanguage.bundle)
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
                               error: String(localized: "Could not save notification payload: \(String(error.localizedDescription))", bundle: AppLanguage.bundle))
        }
        do {
            guard let notification = try TurnCompletion.parse(payload) else {
                return BridgeReply(accepted: false, visibleCount: history.recent.count,
                                   error: String(localized: "This event is not a conversation notification supported by AIBox.", bundle: AppLanguage.bundle))
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
                               error: String(localized: "Invalid notification format; type, thread-id and turn-id are required.", bundle: AppLanguage.bundle))
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuild(menu)
        refreshUsage()
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.font = .menuFont(ofSize: 14)
        menu.addItem(menuLabel(String(localized: "AIBox: Running", bundle: AppLanguage.bundle)))
        menu.addItem(menuLabel(boxStatus.stringValue))
        let usageItem = NSMenuItem()
        usageView.frame = NSRect(origin: .zero, size: usageView.intrinsicContentSize)
        usageItem.view = usageView
        menu.addItem(usageItem)
        menu.addItem(.separator())
        menu.addItem(menuLabel(String(localized: "Recent notifications (up to 20)", bundle: AppLanguage.bundle)))
        if history.recent.isEmpty {
            menu.addItem(menuLabel(String(localized: "No notifications", bundle: AppLanguage.bundle)))
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
        let settings = NSMenuItem(title: String(localized: "Settings…", bundle: AppLanguage.bundle), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: String(localized: "Quit", bundle: AppLanguage.bundle), action: #selector(quitAIBox), keyEquivalent: "q")
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
        if settingsWindow == nil || rebuildSettingsContent {
            rebuildSettingsContent = false
            let window = settingsWindow ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 580),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = String(localized: "AIBox Settings", bundle: AppLanguage.bundle)
            window.isReleasedWhenClosed = false
            window.delegate = self
            setupButton = NSButton(title: String(localized: "Set Up Codex", bundle: AppLanguage.bundle), target: self, action: #selector(setupCodex))
            setupButton.bezelStyle = .rounded
            permissionRequestButton = NSButton(
                checkboxWithTitle: String(localized: "Receive PermissionRequest notifications", bundle: AppLanguage.bundle),
                target: self,
                action: #selector(togglePermissionRequests))
            permissionRequestButton.state = acceptsPermissionRequests ? .on : .off
            userInputRequestButton = NSButton(
                checkboxWithTitle: String(localized: "Receive question and option prompts", bundle: AppLanguage.bundle),
                target: self, action: #selector(toggleUserInputRequests))
            userInputRequestButton.state = acceptsUserInputRequests ? .on : .off
            userInputRequestButton.toolTip = String(localized: "When disabled, new question prompts will not be added or change the light. Existing notifications and raw logs are retained.", bundle: AppLanguage.bundle)
            codexConfigPath.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            codexConfigPath.textColor = .secondaryLabelColor
            notificationStatus.textColor = .secondaryLabelColor
            let connectButton = NSButton(title: String(localized: "Reconnect", bundle: AppLanguage.bundle), target: self, action: #selector(connectBox))
            connectButton.bezelStyle = .rounded
            let selectBoxButton = NSButton(title: String(localized: "Choose / Change Device…", bundle: AppLanguage.bundle), target: self, action: #selector(openBoxPairing))
            selectBoxButton.bezelStyle = .rounded
            let unpairButton = NSButton(title: String(localized: "Unpair", bundle: AppLanguage.bundle), target: self, action: #selector(unpairBox))
            unpairButton.bezelStyle = .rounded
            unpairBoxButton = unpairButton
            let connectionButtons = NSStackView(views: [connectButton, selectBoxButton, unpairButton])
            connectionButtons.spacing = 10
            let shakeButton = NSButton(checkboxWithTitle: String(localized: "Detect Motion", bundle: AppLanguage.bundle), target: self, action: #selector(toggleDetection(_:)))
            shakeButton.tag = 0
            shakeButton.state = detectShake ? .on : .off
            shakeButton.toolTip = String(localized: "Open notifications by shaking. This does not affect shaking for 2 seconds at startup to reset pairing.", bundle: AppLanguage.bundle)
            let soundButton = NSButton(checkboxWithTitle: String(localized: "Detect Sound", bundle: AppLanguage.bundle), target: self, action: #selector(toggleDetection(_:)))
            soundButton.tag = 1
            soundButton.state = detectSound ? .on : .off
            soundButton.toolTip = String(localized: "Open notifications with sudden sounds such as clapping.", bundle: AppLanguage.bundle)
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
            sensitivitySlider.setAccessibilityLabel(String(localized: "Sound sensitivity", bundle: AppLanguage.bundle))
            sensitivitySlider.toolTip = String(localized: "Drag the white thumb to compare with the current level. The bar turns orange when the level exceeds the thumb.", bundle: AppLanguage.bundle)
            soundSensitivitySlider = sensitivitySlider
            soundSensitivityValue.stringValue = String(localized: "Threshold \(String(soundSensitivity))", bundle: AppLanguage.bundle)
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
            let soundTitle = NSTextField(labelWithString: String(localized: "Sound Adjustment", bundle: AppLanguage.bundle))
            soundTitle.font = .systemFont(ofSize: 14, weight: .semibold)
            soundThresholdStatus.font = .systemFont(ofSize: 12, weight: .semibold)
            let soundTitleRow = NSStackView(views: [soundTitle, soundThresholdStatus])
            soundTitleRow.spacing = 12
            let soundHelp = NSTextField(wrappingLabelWithString:
                String(localized: "The white thumb sets the threshold; the fill shows the current level. The color changes as you cross the level, so you can adjust while listening.", bundle: AppLanguage.bundle))
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
                String(localized: "Hooks run only after you confirm trust. Reopen your Codex conversation after setup; restart Codex if the hooks have not loaded. Keep AIBox running and click a notification to open its conversation. Stop marks stop processing; other hooks may still request continuation.", bundle: AppLanguage.bundle))
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
            let languagePicker = NSPopUpButton()
            languagePicker.addItems(withTitles: [
                "繁體中文", "English"
            ])
            languagePicker.selectItem(at: AppLanguage.allCases.firstIndex(of: AppLanguage.selected) ?? 0)
            languagePicker.target = self
            languagePicker.action = #selector(changeLanguage(_:))
            languagePicker.setAccessibilityLabel(String(localized: "Language", bundle: AppLanguage.bundle))
            let languageRow = NSStackView(views: [
                NSTextField(labelWithString: String(localized: "Language", bundle: AppLanguage.bundle)), languagePicker
            ])
            languageRow.spacing = 12
            let languageHelp = NSTextField(wrappingLabelWithString:
                String(localized: "Language changes take effect immediately and are saved automatically.", bundle: AppLanguage.bundle))
            languageHelp.font = .systemFont(ofSize: 12)
            languageHelp.textColor = .secondaryLabelColor
            let tabs = NSTabView()
            remoteHost.placeholderString = String(localized: "SSH host alias, e.g. srv", bundle: AppLanguage.bundle)
            remoteHost.setAccessibilityLabel(String(localized: "Remote SSH host", bundle: AppLanguage.bundle))
            remoteHost.widthAnchor.constraint(equalToConstant: 280).isActive = true
            remoteButton = NSButton(title: remoteConnection.isEnabled ? String(localized: "Disconnect", bundle: AppLanguage.bundle) : String(localized: "Save and Connect", bundle: AppLanguage.bundle),
                                    target: self, action: #selector(toggleRemoteConnection))
            remoteButton.bezelStyle = .rounded
            let remoteRow = NSStackView(views: [remoteHost, remoteButton])
            remoteRow.spacing = 10
            remoteStatus.font = .systemFont(ofSize: 12)
            remoteStatus.textColor = .secondaryLabelColor
            let remoteHelp = NSTextField(wrappingLabelWithString:
                String(localized: "Uses your SSH keys and trusted hosts. Installs the remote notification script on connection, retries after disconnection, and reconnects when AIBox starts. Requires Python 3.\n\nFor first use, configure and trust the hook in remote Codex using the command below. Reopen the remote conversation after setup.", bundle: AppLanguage.bundle))
            remoteHelp.font = .systemFont(ofSize: 12)
            let remoteCommand = NSTextField(wrappingLabelWithString: "python3 ~/.codex/aibox/notify.py")
            remoteCommand.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            remoteCommand.isSelectable = true
            tabs.font = .systemFont(ofSize: 14)
            tabs.translatesAutoresizingMaskIntoConstraints = false
            let pages: [(id: String, title: String, summary: String, views: [NSView])] = [
                ("general", String(localized: "General", bundle: AppLanguage.bundle), String(localized: "Choose the display language for AIBox.", bundle: AppLanguage.bundle),
                 [languageRow, languageHelp]),
                ("sensors", String(localized: "Sensors", bundle: AppLanguage.bundle), String(localized: "Choose motion or sound to open notifications, and adjust the sound threshold live.", bundle: AppLanguage.bundle),
                 [detectionRow, soundSettings]),
                ("lights", String(localized: "Lights", bundle: AppLanguage.bundle), String(localized: "Set idle and alert colors. Lights reflect the latest unopened notification; questions use the permission request colors.", bundle: AppLanguage.bundle),
                 [colorSettings]),
                ("notifications", String(localized: "Notifications", bundle: AppLanguage.bundle), String(localized: "Response stop notifications are received automatically. Toggle other alerts individually and view the latest 20 notifications in the menu bar.", bundle: AppLanguage.bundle),
                 [permissionRequestButton, userInputRequestButton, notificationStatus]),
                ("device", String(localized: "Device", bundle: AppLanguage.bundle), String(localized: "Manage the paired AIBox or choose another device.", bundle: AppLanguage.bundle),
                 [boxStatus, connectionButtons]),
                ("remote", String(localized: "Remote", bundle: AppLanguage.bundle), String(localized: "Receive response stop, permission and question alerts from one SSH host. Your Mac must remain online.", bundle: AppLanguage.bundle),
                 [remoteRow, remoteStatus, remoteHelp, remoteCommand]),
                ("codex", "Codex", String(localized: "Send Codex response and question alerts to AIBox.", bundle: AppLanguage.bundle),
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
            if settingsWindow == nil { window.center() }
            settingsWindow = window
        }
        setupButton.isEnabled = !setupBusy
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
            notificationStatus.stringValue = String(localized: "Last notification: \(String(timeFormatter.string(from: latest.receivedAt)))", bundle: AppLanguage.bundle)
        } else {
            notificationStatus.stringValue = String(localized: "No notifications received yet.", bundle: AppLanguage.bundle)
        }
    }

    @objc private func changeLanguage(_ sender: NSPopUpButton) {
        guard AppLanguage.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        let language = AppLanguage.allCases[sender.indexOfSelectedItem]
        guard language != AppLanguage.selected else { return }
        AppLanguage.selected = language
        let selectedTab = settingsTabs?.selectedTabViewItem?.identifier
        // Rebuild only the settings content, keeping the window and live services.
        // Shared controls are reused; release their old layout constraints first.
        func removeConstraints(_ view: NSView) {
            NSLayoutConstraint.deactivate(view.constraints)
            view.subviews.forEach(removeConstraints)
        }
        if let content = settingsWindow?.contentView {
            removeConstraints(content)
            settingsWindow?.contentView = NSView(frame: content.frame)
        }
        rebuildSettingsContent = true
        openSettings()
        if let selectedTab { settingsTabs?.selectTabViewItem(withIdentifier: selectedTab) }
        if let codexStatusText { codexStatus.stringValue = codexStatusText() }
        box.refreshLanguage()
        remoteConnection.refreshLanguage()
        boxPairingWindow.refreshLanguage()
        if let menu = statusItem?.menu { rebuild(menu) }
        usageView.needsDisplay = true
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
        soundSensitivityValue.stringValue = String(localized: "Threshold \(String(value))", bundle: AppLanguage.bundle)
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
            soundMeterValue.stringValue = detectSound ? String(localized: "Waiting for sound…", bundle: AppLanguage.bundle) : String(localized: "Sound detection is off", bundle: AppLanguage.bundle)
            soundThresholdStatus.stringValue = ""
            slider.setAccessibilityValueDescription(soundMeterValue.stringValue)
            return
        }
        let decibels = peak > 0 ? 20 * log10(Double(peak) / 32768) : -90
        let level = min(100, max(0, (decibels + 90) / 90 * 100))
        cell.soundLevel = level
        let above = level >= Double(soundSensitivity)
        soundThresholdStatus.stringValue = above ? String(localized: "Above threshold", bundle: AppLanguage.bundle) : String(localized: "Below threshold", bundle: AppLanguage.bundle)
        soundThresholdStatus.textColor = above ? .systemOrange : .secondaryLabelColor
        soundMeterValue.stringValue = String(localized: "Current level \(String(Int(level.rounded())))", bundle: AppLanguage.bundle)
        slider.setAccessibilityValueDescription(String(localized: "Threshold \(String(soundSensitivity)), \(String(soundMeterValue.stringValue))", bundle: AppLanguage.bundle))
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        box.setSoundMonitoring(false)
        updateSoundMeter(nil)
    }
    @objc private func quitAIBox() { NSApp.terminate(nil) }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Could Not Open Conversation", bundle: AppLanguage.bundle)
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
            throw CodexSetupError.unavailable(String(localized: "Codex App or aibox-notify was not found. Check the installation and build.", bundle: AppLanguage.bundle))
        }
        return CodexConfigurationService(executableURL: executable, helperURL: helper)
    }

    private func updateCodexStatus(_ text: @autoclosure @escaping () -> String) {
        codexStatusText = text
        codexStatus.stringValue = text()
    }

    private func runCodexSetup(configure: Bool) {
        guard !setupBusy else { return }
        setupBusy = true
        setupButton.isEnabled = false
        updateCodexStatus(String(localized: "Reading Codex settings…", bundle: AppLanguage.bundle))
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
                    updateCodexStatus(String(localized: "Setting up response stop, permission and question alerts…", bundle: AppLanguage.bundle))
                    let expected = configuration
                    configuration = try await Task.detached {
                        try service.configure(expected: expected)
                    }.value
                }
                if configure && !configuration.allActive {
                    let pending = configuration.configuredHooks.filter { !$0.isActive }
                    let alert = NSAlert()
                    alert.messageText = String(localized: "Trust and enable AIBox conversation notification hooks?", bundle: AppLanguage.bundle)
                    let commands = pending.map { String(localized: "Event: \(String($0.eventName))\nCommand: \(String($0.command))", bundle: AppLanguage.bundle) }.joined(separator: "\n\n")
                    alert.informativeText = commands + String(localized: "\n\nCodex will send the conversation ID, turn ID, and final response, permission request, or questions and options to local AIBox. This program only receives notifications. It does not answer questions, approve or deny permissions, or request continuation.", bundle: AppLanguage.bundle)
                    alert.addButton(withTitle: String(localized: "Cancel", bundle: AppLanguage.bundle))
                    alert.addButton(withTitle: String(localized: "Trust and Enable", bundle: AppLanguage.bundle))
                    guard alert.runModal() == .alertSecondButtonReturn else {
                        updateCodexStatus(String(localized: "Untrusted notification hooks were not enabled. Previously enabled hooks are unchanged.", bundle: AppLanguage.bundle))
                        return
                    }
                    updateCodexStatus(String(localized: "Saving hook trust confirmation…", bundle: AppLanguage.bundle))
                    let expected = configuration
                    configuration = try await Task.detached { try service.trust(expected: expected) }.value
                }
                if !configuration.hooksEnabled {
                    updateCodexStatus(String(localized: "Codex hooks are disabled. AIBox did not change this setting.", bundle: AppLanguage.bundle))
                } else {
                    func status(_ hook: CodexHookStatus?) -> String {
                        guard let hook else { return String(localized: "Not configured", bundle: AppLanguage.bundle) }
                        return hook.isActive ? String(localized: "Configured and trusted", bundle: AppLanguage.bundle) : String(localized: "Awaiting trust / activation", bundle: AppLanguage.bundle)
                    }
                    updateCodexStatus(String(localized: "Response stop: \(String(status(configuration.hook)))\nPermission requests: \(String(status(configuration.permissionHook)))\nQuestions: \(String(status(configuration.userInputHook)))\nSetup status does not confirm notification delivery.", bundle: AppLanguage.bundle))
                }
            } catch {
                updateCodexStatus(error.localizedDescription)
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
