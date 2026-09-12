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

        let heading = NSTextField(labelWithString: "燈號顏色")
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        addArrangedSubview(heading)
        addRow("待機", slots: [.idle])
        addRow("回覆停止", slots: [.completion, .completionAlternate])
        addRow("授權請求", slots: [.permission, .permissionAlternate])
        let intervalLabel = NSTextField(labelWithString: "交替間隔")
        intervalLabel.widthAnchor.constraint(equalToConstant: 92).isActive = true
        let slider = NSSlider(value: Double(min(100, max(1, intervalTenths))) / 10,
                              minValue: 0.1, maxValue: 10,
                              target: self, action: #selector(intervalChanged(_:)))
        slider.isContinuous = true
        slider.setAccessibilityLabel("交替間隔，每個顏色顯示秒數")
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        intervalValue.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        intervalValue.widthAnchor.constraint(equalToConstant: 58).isActive = true
        updateIntervalLabel(Int((slider.doubleValue * 10).rounded()))
        let intervalRow = NSStackView(views: [intervalLabel, slider, intervalValue])
        intervalRow.orientation = .horizontal
        intervalRow.alignment = .centerY
        intervalRow.spacing = 10
        addArrangedSubview(intervalRow)
        let intervalHint = NSTextField(labelWithString: "每個顏色顯示 0.1～10 秒，適用於回覆停止與授權請求。")
        intervalHint.font = .systemFont(ofSize: 11)
        intervalHint.textColor = .secondaryLabelColor
        addArrangedSubview(intervalHint)
        let hint = NSTextField(labelWithString: "點色塊開啟色環；顏色自動儲存，連線後套用至對應燈號。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        addArrangedSubview(hint)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func addRow(_ title: String, slots: [BoxColorSlot]) {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 92).isActive = true
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
            well.setAccessibilityLabel("\(title)顏色\(index + 1)")
            well.toolTip = "點擊以色環選擇\(title)顏色\(index + 1)"
            row.addArrangedSubview(well)
            well.widthAnchor.constraint(equalToConstant: 52).isActive = true
            well.heightAnchor.constraint(equalToConstant: 26).isActive = true
        }
        let behavior = NSTextField(labelWithString: slots.count == 1 ? "恆亮" : "兩色交替")
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
        intervalValue.stringValue = String(format: "%.1f 秒", Double(tenths) / 10)
    }

    @objc private func intervalChanged(_ sender: NSSlider) {
        let tenths = min(100, max(1, Int((sender.doubleValue * 10).rounded())))
        sender.doubleValue = Double(tenths) / 10
        updateIntervalLabel(tenths)
        onIntervalChange(tenths)
    }
}
