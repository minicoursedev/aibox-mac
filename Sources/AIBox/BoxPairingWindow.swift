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
    private let prompt = NSTextField(wrappingLabelWithString: String(localized: "Select a device, then click Identify.", bundle: AppLanguage.bundle))
    private var identifyButton: NSButton!
    private var retryButton: NSButton!
    private var searchButton: NSButton!
    private var bluetoothSettingsButton: NSButton!
    private var answers: [NSButton] = []
    private var currentState: BoxPairingState?
    private var refreshStaticText: (() -> Void)?

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
        window.title = String(localized: "Choose AIBox", bundle: AppLanguage.bundle)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        let title = NSTextField(labelWithString: String(localized: "Identify Your AIBox", bundle: AppLanguage.bundle))
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        let description = NSTextField(wrappingLabelWithString:
            String(localized: "Choose a box, observe its flashing color, then select the color you see. After confirmation, this Mac will remember and reconnect only to that box.", bundle: AppLanguage.bundle))
        description.textColor = .secondaryLabelColor
        savedDevice.textColor = .secondaryLabelColor
        savedDevice.font = .systemFont(ofSize: 12)
        devices.setAccessibilityLabel(String(localized: "Nearby AIBox devices", bundle: AppLanguage.bundle))
        devices.target = self
        devices.action = #selector(deviceChanged)
        devices.widthAnchor.constraint(equalToConstant: 280).isActive = true
        identifyButton = NSButton(title: String(localized: "Identify", bundle: AppLanguage.bundle), target: self, action: #selector(identify))
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
            button.setAccessibilityLabel(String(localized: "I see \(String(color.label))", bundle: AppLanguage.bundle))
            answers.append(button)
        }
        let answerRow = NSStackView(views: answers)
        answerRow.spacing = 12
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        searchButton = NSButton(title: String(localized: "Search Again", bundle: AppLanguage.bundle), target: self, action: #selector(search))
        retryButton = NSButton(title: String(localized: "Identify Again", bundle: AppLanguage.bundle), target: self, action: #selector(retry))
        let cancel = NSButton(title: String(localized: "Cancel", bundle: AppLanguage.bundle), target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        for button in [searchButton!, retryButton!, cancel] { button.bezelStyle = .rounded }
        let actions = NSStackView(views: [searchButton, retryButton, cancel])
        actions.spacing = 10
        bluetoothSettingsButton = NSButton(title: String(localized: "Open Bluetooth Settings", bundle: AppLanguage.bundle), target: self, action: #selector(openBluetoothSettings))
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
        refreshStaticText = { [weak self, weak window] in
            guard let self else { return }
            window?.title = String(localized: "Choose AIBox", bundle: AppLanguage.bundle)
            title.stringValue = String(localized: "Identify Your AIBox", bundle: AppLanguage.bundle)
            description.stringValue = String(localized: "Choose a box, observe its flashing color, then select the color you see. After confirmation, this Mac will remember and reconnect only to that box.", bundle: AppLanguage.bundle)
            self.identifyButton?.title = String(localized: "Identify", bundle: AppLanguage.bundle)
            self.searchButton?.title = String(localized: "Search Again", bundle: AppLanguage.bundle)
            self.retryButton?.title = String(localized: "Identify Again", bundle: AppLanguage.bundle)
            self.bluetoothSettingsButton?.title = String(localized: "Open Bluetooth Settings", bundle: AppLanguage.bundle)
            cancel.title = String(localized: "Cancel", bundle: AppLanguage.bundle)
            self.devices.setAccessibilityLabel(String(localized: "Nearby AIBox devices", bundle: AppLanguage.bundle))
            for button in self.answers {
                guard let color = BoxPairingColor(rawValue: button.tag) else { continue }
                button.title = color.label
                button.setAccessibilityLabel(String(localized: "I see \(String(color.label))", bundle: AppLanguage.bundle))
                button.image?.accessibilityDescription = color.label
            }
        }
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshLanguage() {
        refreshStaticText?()
        if let currentState { update(currentState) }
    }

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
        if state.devices.isEmpty { devices.addItem(withTitle: String(localized: "No devices found", bundle: AppLanguage.bundle)) }
        savedDevice.stringValue = state.savedDeviceID.map {
            String(localized: "Remembered: \(String(BoxDeviceChoice(id: $0).title)). Replaced only after confirming the new device's color.", bundle: AppLanguage.bundle)
        } ?? String(localized: "No remembered device", bundle: AppLanguage.bundle)
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
        prompt.stringValue = state.needsSystemPairingReset ? String(localized: "First remove the old pairing saved by macOS.", bundle: AppLanguage.bundle)
            : canAnswer ? String(localized: "Which color is the box flashing?", bundle: AppLanguage.bundle)
            : state.canRetry && isCandidateSelected ? String(localized: "Click Identify Again and confirm the color.", bundle: AppLanguage.bundle)
            : isCandidateSelected ? String(localized: "Waiting for box confirmation…", bundle: AppLanguage.bundle) : String(localized: "Select a device, then click Identify.", bundle: AppLanguage.bundle)
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
