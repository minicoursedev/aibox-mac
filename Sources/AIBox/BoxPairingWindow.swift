import AIBoxCore
import AppKit

@MainActor
final class BoxPairingWindow: NSWindowController, NSWindowDelegate {
    private let onSearch: () -> Void
    private let onSelect: (UUID) -> Void
    private let onAnswer: (BoxPairingColor) -> Void
    private let onRetry: () -> Void
    private let onCancel: () -> Void
    private let devices = NSPopUpButton(frame: .zero, pullsDown: false)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let savedDevice = NSTextField(wrappingLabelWithString: "")
    private let prompt = NSTextField(wrappingLabelWithString: "請先選擇裝置，再按「辨識這台」。")
    private var identifyButton: NSButton!
    private var retryButton: NSButton!
    private var searchButton: NSButton!
    private var bluetoothSettingsButton: NSButton!
    private var answers: [NSButton] = []
    private var currentState: BoxPairingState?

    init(onSearch: @escaping () -> Void, onSelect: @escaping (UUID) -> Void,
         onAnswer: @escaping (BoxPairingColor) -> Void, onRetry: @escaping () -> Void,
         onCancel: @escaping () -> Void) {
        self.onSearch = onSearch
        self.onSelect = onSelect
        self.onAnswer = onAnswer
        self.onRetry = onRetry
        self.onCancel = onCancel
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 470),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "選擇 AIBox"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        let title = NSTextField(labelWithString: "確認你的 AIBox")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        let description = NSTextField(wrappingLabelWithString:
            "選一台 box，觀察它閃爍的顏色，再選出你看到的顏色。確認後，這台 Mac 會記住並只連回這台 box。")
        description.textColor = .secondaryLabelColor
        savedDevice.textColor = .secondaryLabelColor
        savedDevice.font = .systemFont(ofSize: 12)
        devices.setAccessibilityLabel("附近的 AIBox")
        devices.target = self
        devices.action = #selector(deviceChanged)
        devices.widthAnchor.constraint(equalToConstant: 280).isActive = true
        identifyButton = NSButton(title: "辨識這台", target: self, action: #selector(identify))
        identifyButton.bezelStyle = .rounded
        let choiceRow = NSStackView(views: [devices, identifyButton])
        choiceRow.spacing = 12
        prompt.font = .systemFont(ofSize: 14, weight: .medium)
        for color in BoxPairingColor.allCases {
            let button = NSButton(title: color.label, target: self, action: #selector(answer(_:)))
            button.tag = color.rawValue
            button.bezelStyle = .rounded
            let rgb = color.rgb
            let tint = NSColor(srgbRed: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255,
                               blue: CGFloat(rgb.blue) / 255, alpha: 1)
            button.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: color.label)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [tint]))
            button.image?.isTemplate = false
            button.imagePosition = .imageLeading
            button.widthAnchor.constraint(equalToConstant: 100).isActive = true
            button.setAccessibilityLabel("我看到\(color.label)")
            answers.append(button)
        }
        let answerRow = NSStackView(views: answers)
        answerRow.spacing = 12
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        searchButton = NSButton(title: "重新搜尋", target: self, action: #selector(search))
        retryButton = NSButton(title: "重新辨識", target: self, action: #selector(retry))
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        for button in [searchButton!, retryButton!, cancel] { button.bezelStyle = .rounded }
        let actions = NSStackView(views: [searchButton, retryButton, cancel])
        actions.spacing = 10
        bluetoothSettingsButton = NSButton(title: "開啟藍牙設定", target: self, action: #selector(openBluetoothSettings))
        bluetoothSettingsButton.bezelStyle = .rounded
        bluetoothSettingsButton.isHidden = true
        let stack = NSStackView(views: [title, description, savedDevice, choiceRow, prompt, answerRow, status, bluetoothSettingsButton, actions])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -24),
        ])
        for label in [description, savedDevice, status, prompt] { label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ state: BoxPairingState) {
        let completed = currentState?.isSelecting == true && !state.isSelecting
        let previous = devices.selectedItem?.representedObject as? UUID
        let selection = state.candidateID != currentState?.candidateID ? state.candidateID ?? previous : previous
        currentState = state
        devices.removeAllItems()
        for device in state.devices {
            devices.addItem(withTitle: device.title)
            devices.lastItem?.representedObject = device.id
        }
        if let index = state.devices.firstIndex(where: { $0.id == selection }) {
            devices.selectItem(at: index)
        }
        if state.devices.isEmpty { devices.addItem(withTitle: "尚未找到裝置") }
        savedDevice.stringValue = state.savedDeviceID.map {
            "已記住：\(BoxDeviceChoice(id: $0).title)；選對新裝置的顏色後才會更換。"
        } ?? "尚未記住裝置"
        status.stringValue = state.status
        bluetoothSettingsButton.isHidden = !state.needsSystemPairingReset
        updateControls()
        if completed { close() }
    }

    private func updateControls() {
        guard let state = currentState else { return }
        let selected = devices.selectedItem?.representedObject as? UUID
        let isCandidateSelected = state.candidateID != nil && selected == state.candidateID
        let canAnswer = state.canConfirm && isCandidateSelected
        devices.isEnabled = !state.isBusy && !state.devices.isEmpty
        identifyButton.isEnabled = devices.isEnabled
        searchButton.isEnabled = !state.isBusy
        retryButton.isEnabled = state.canRetry && isCandidateSelected
        answers.forEach { $0.isEnabled = canAnswer }
        prompt.stringValue = state.needsSystemPairingReset ? "請先清除 macOS 保留的舊配對。"
            : canAnswer ? "你看到 box 閃爍哪個顏色？"
            : state.canRetry && isCandidateSelected ? "請按「重新辨識」再確認顏色。"
            : isCandidateSelected ? "正在等待 box 確認…" : "請先選擇裝置，再按「辨識這台」。"
    }

    @objc private func deviceChanged() { updateControls() }
    @objc private func search() { onSearch() }
    @objc private func identify() {
        if let id = devices.selectedItem?.representedObject as? UUID { onSelect(id) }
    }
    @objc private func answer(_ sender: NSButton) {
        if let color = BoxPairingColor(rawValue: sender.tag) { onAnswer(color) }
    }
    @objc private func retry() { onRetry() }
    @objc private func openBluetoothSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
    }
    @objc private func cancel() { close() }
    func windowWillClose(_ notification: Notification) { onCancel() }
}
