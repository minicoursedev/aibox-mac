import AIBoxCore
import AppKit

@MainActor
private final class WheelColorWell: NSColorWell {
    override func activate(_ exclusive: Bool) {
        super.activate(exclusive)
        NSColorPanel.shared.showsAlpha = false
        NSColorPanel.shared.mode = .wheel
        NSColorPanel.shared.makeKeyAndOrderFront(nil)
    }

    override func mouseDown(with event: NSEvent) {
        activate(true)
    }
}

@MainActor
final class LightColorSettingsView: NSStackView {
    private var colors: BoxLightColors
    private let onChange: (BoxLightColors) -> Void
    private let onIntervalChange: (Int) -> Void
    private let intervalValue = NSTextField(labelWithString: "")

    init(colors: BoxLightColors, intervalTenths: Int,
         onIntervalChange: @escaping (Int) -> Void,
         onChange: @escaping (BoxLightColors) -> Void) {
        self.colors = colors
        self.onChange = onChange
        self.onIntervalChange = onIntervalChange
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 8

        let heading = NSTextField(labelWithString: String(localized: "Light Colors", bundle: AppLanguage.bundle))
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        addArrangedSubview(heading)
        addRow(String(localized: "Idle", bundle: AppLanguage.bundle), slots: [.idle])
        addRow(String(localized: "Response stopped", bundle: AppLanguage.bundle), slots: [.completion, .completionAlternate])
        addRow(String(localized: "Permission request", bundle: AppLanguage.bundle), slots: [.permission, .permissionAlternate])
        let intervalLabel = NSTextField(labelWithString: String(localized: "Color interval", bundle: AppLanguage.bundle))
        intervalLabel.widthAnchor.constraint(equalToConstant: 130).isActive = true
        let slider = NSSlider(value: Double(min(100, max(1, intervalTenths))) / 10,
                              minValue: 0.1, maxValue: 10,
                              target: self, action: #selector(intervalChanged(_:)))
        slider.isContinuous = true
        slider.setAccessibilityLabel(String(localized: "Color interval, seconds per color", bundle: AppLanguage.bundle))
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        intervalValue.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        intervalValue.widthAnchor.constraint(equalToConstant: 58).isActive = true
        updateIntervalLabel(Int((slider.doubleValue * 10).rounded()))
        let intervalRow = NSStackView(views: [intervalLabel, slider, intervalValue])
        intervalRow.orientation = .horizontal
        intervalRow.alignment = .centerY
        intervalRow.spacing = 10
        addArrangedSubview(intervalRow)
        let intervalHint = NSTextField(labelWithString: String(localized: "Show each color for 0.1–10 seconds for response stop and permission alerts.", bundle: AppLanguage.bundle))
        intervalHint.font = .systemFont(ofSize: 11)
        intervalHint.textColor = .secondaryLabelColor
        addArrangedSubview(intervalHint)
        let hint = NSTextField(labelWithString: String(localized: "Click a swatch to open the color wheel. Colors are saved automatically and applied when connected.", bundle: AppLanguage.bundle))
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        addArrangedSubview(hint)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func addRow(_ title: String, slots: [BoxColorSlot]) {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 130).isActive = true
        let row = NSStackView(views: [label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        for (index, slot) in slots.enumerated() {
            if index > 0 { row.addArrangedSubview(NSTextField(labelWithString: "↔")) }
            let well = WheelColorWell(frame: .zero)
            if #available(macOS 14, *) { well.supportsAlpha = false }
            let rgb = colors[slot]
            well.color = NSColor(srgbRed: CGFloat(rgb.red) / 255,
                                 green: CGFloat(rgb.green) / 255,
                                 blue: CGFloat(rgb.blue) / 255, alpha: 1)
            well.tag = slot.rawValue
            well.target = self
            well.action = #selector(colorChanged(_:))
            well.isContinuous = true
            well.setAccessibilityLabel(String(localized: "\(String(title)) color \(String(index + 1))", bundle: AppLanguage.bundle))
            well.toolTip = String(localized: "Click to choose \(String(title)) color \(String(index + 1)) using the color wheel", bundle: AppLanguage.bundle)
            row.addArrangedSubview(well)
            well.widthAnchor.constraint(equalToConstant: 52).isActive = true
            well.heightAnchor.constraint(equalToConstant: 26).isActive = true
        }
        let behavior = NSTextField(labelWithString: slots.count == 1 ? String(localized: "Steady", bundle: AppLanguage.bundle) : String(localized: "Alternating", bundle: AppLanguage.bundle))
        behavior.textColor = .secondaryLabelColor
        behavior.font = .systemFont(ofSize: 11)
        row.addArrangedSubview(behavior)
        addArrangedSubview(row)
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        guard let slot = BoxColorSlot(rawValue: sender.tag),
              let color = sender.color.usingColorSpace(.sRGB) else { return }
        func byte(_ value: CGFloat) -> UInt8 { UInt8((min(1, max(0, value)) * 255).rounded()) }
        colors[slot] = BoxRGB(red: byte(color.redComponent), green: byte(color.greenComponent),
                             blue: byte(color.blueComponent))
        onChange(colors)
    }

    private func updateIntervalLabel(_ tenths: Int) {
        intervalValue.stringValue = String(format: String(localized: "%.1f s", bundle: AppLanguage.bundle), Double(tenths) / 10)
    }

    @objc private func intervalChanged(_ sender: NSSlider) {
        let tenths = min(100, max(1, Int((sender.doubleValue * 10).rounded())))
        sender.doubleValue = Double(tenths) / 10
        updateIntervalLabel(tenths)
        onIntervalChange(tenths)
    }
}
