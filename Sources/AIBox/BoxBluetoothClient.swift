import AIBoxCore
import CoreBluetooth
import Foundation

struct BoxDeviceChoice {
    let id: UUID
    var title: String { "AIBox · \(id.uuidString.suffix(6))" }
}

struct BoxPairingState {
    let devices: [BoxDeviceChoice]
    let savedDeviceID: UUID?
    let candidateID: UUID?
    let canConfirm: Bool
    let canRetry: Bool
    let isSelecting: Bool
    let isBusy: Bool
    var needsSystemPairingReset: Bool = false
    let status: String
}

@MainActor
final class BoxBluetoothClient: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private let onStatus: (String) -> Void
    private let onConnectionChange: (Bool) -> Void
    private let onPairingChange: (BoxPairingState) -> Void
    private let onShake: () -> Void
    private let onSoundReading: (Int, Bool) -> Void
    private let pairing = BoxPairing()
    private var discovered: [CBPeripheral] = []
    private var statusText = "box：尚未連線"
    private var afterDisconnect: (() -> Void)?
    private var isConnected = false {
        didSet {
            if isConnected != oldValue { onConnectionChange(isConnected) }
        }
    }
    private var central: CBCentralManager!
    private var board: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var session = BoxSession()
    private var decoder = BoxLineDecoder()
    private var timeout: Timer?
    private var stopped = false
    private var needsSystemPairingReset = false
    private let serviceID = CBUUID(string: BoxProtocol.service)
    private let commandID = CBUUID(string: BoxProtocol.commands)
    private let eventID = CBUUID(string: BoxProtocol.events)

    var needsDeviceSelection: Bool { pairing.savedDeviceID == nil }
    var pairingState: BoxPairingState {
        BoxPairingState(devices: discovered.map { BoxDeviceChoice(id: $0.identifier) },
                        savedDeviceID: pairing.savedDeviceID, candidateID: pairing.candidateID,
                        canConfirm: pairing.candidateID != nil && session.isIdentificationVisible
                            && afterDisconnect == nil && board?.state == .connected,
                        canRetry: session.canRetryIdentification && afterDisconnect == nil,
                        isSelecting: pairing.isSelecting,
                        isBusy: afterDisconnect != nil || (board != nil && !session.canRetryIdentification),
                        needsSystemPairingReset: needsSystemPairingReset,
                        status: statusText)
    }

    init(onStatus: @escaping (String) -> Void, onConnectionChange: @escaping (Bool) -> Void,
         onPairingChange: @escaping (BoxPairingState) -> Void, onShake: @escaping () -> Void,
         onSoundReading: @escaping (Int, Bool) -> Void) {
        self.onStatus = onStatus
        self.onConnectionChange = onConnectionChange
        self.onPairingChange = onPairingChange
        self.onShake = onShake
        self.onSoundReading = onSoundReading
        super.init()
    }
    func start() {
        stopped = false
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else { reconnect() }
    }
    func setPattern(_ value: BoxLightPattern) {
        if let command = session.setPattern(value), afterDisconnect == nil { send(command) }
    }
    func setColors(_ value: BoxLightColors) {
        if let command = session.setColors(value), afterDisconnect == nil { send(command) }
    }
    func setBlinkInterval(_ tenths: Int) {
        if let command = session.setBlinkInterval(tenths), afterDisconnect == nil { send(command) }
    }
    func setDetection(shake: Bool, sound: Bool) {
        if let command = session.setDetection(shake: shake, sound: sound), afterDisconnect == nil { send(command) }
    }
    func setSoundSensitivity(_ value: Int) {
        if let command = session.setSoundSensitivity(value), afterDisconnect == nil { send(command) }
    }
    func setSoundMonitoring(_ enabled: Bool) {
        if let command = session.setSoundMonitoring(enabled), afterDisconnect == nil { send(command) }
    }
    func reconnect() {
        if pairing.isSelecting { beginSelection(); return }
        stopped = false
        disconnectThen { [weak self] in self?.scan() }
    }
    func beginSelection() {
        stopped = false
        pairing.beginSelection()
        disconnectThen { [weak self] in
            guard let self else { return }
            self.discovered.removeAll()
            self.scan()
        }
    }
    func selectDevice(_ identifier: UUID) {
        guard pairing.isSelecting, let peripheral = discovered.first(where: { $0.identifier == identifier }) else { return }
        stopped = false
        disconnectThen { [weak self] in
            guard let self, self.pairing.isSelecting else { return }
            guard self.central.state == .poweredOn else {
                self.centralManagerDidUpdateState(self.central)
                return
            }
            self.pairing.select(identifier)
            _ = self.session.beginIdentification()
            self.connect(peripheral)
        }
    }
    func retryIdentification() {
        guard pairing.candidateID != nil, session.canRetryIdentification else { return }
        if let command = session.beginIdentification() { send(command) }
        reportStatus("box：正在重新顯示辨識顏色…")
    }
    func confirmColor(_ color: BoxPairingColor) {
        guard afterDisconnect == nil, board?.state == .connected, pairingState.canConfirm,
              let command = session.answer(color) else { return }
        send(command)
        reportStatus("box：等待 box 確認顏色並儲存配對…")
    }
    var canUnpair: Bool { isConnected && session.phase == .ready }
    func unpair() {
        guard canUnpair, let command = session.unpair() else { return }
        stopped = true
        central.stopScan()
        isConnected = false
        send(command)
        reportStatus("box：正在解除配對…")
    }
    func cancelSelection() {
        guard pairing.isSelecting else { return }
        if needsSystemPairingReset {
            pairing.cancelSelection()
            stop()
            clearSession()
            return
        }
        stopped = false
        pairing.cancelSelection()
        disconnectThen { [weak self] in self?.scan() }
    }
    func stop() {
        stopped = true
        afterDisconnect = nil
        isConnected = false
        timeout?.invalidate()
        central?.stopScan()
        if let board { central?.cancelPeripheralConnection(board) }
    }
    private func reportStatus(_ value: String) {
        statusText = value
        onStatus(value)
        onPairingChange(pairingState)
    }
    private func scan() {
        guard !stopped else { return }
        guard central.state == .poweredOn else { centralManagerDidUpdateState(central); return }
        guard pairing.isSelecting || pairing.savedDeviceID != nil else {
            reportStatus("box：尚未選擇，請到設定按「選擇／更換 box…」")
            return
        }
        reportStatus(pairing.isSelecting ? "box：搜尋附近裝置中…" : "box：搜尋已記住的裝置中…")
        central.scanForPeripherals(withServices: [serviceID])
        armTimeout("找不到已記住的 AIBox；請確認供電，再重新連線。", seconds: 30) { [weak self] in
            guard let self else { return }
            if self.pairing.isSelecting {
                self.central.stopScan()
                self.reportStatus(self.discovered.isEmpty
                    ? "box：找不到裝置，請確認供電後重新搜尋。"
                    : "box：請選擇裝置，再按「辨識這台」。")
            } else {
                self.reportStatus("box：等待已記住的 AIBox 上線，開機後會自動連線…")
            }
        }
    }
    private func connect(_ peripheral: CBPeripheral) {
        needsSystemPairingReset = false
        board = peripheral
        peripheral.delegate = self
        central.stopScan()
        reportStatus("box：連線中…")
        armTimeout("連線逾時。", seconds: 15)
        central.connect(peripheral)
    }
    private func clearSession() {
        timeout?.invalidate()
        board = nil
        commandCharacteristic = nil
        session.disconnected()
        pairing.discardCandidate()
        isConnected = false
        decoder = BoxLineDecoder()
    }
    // Leave identification mode before switching away; wait for the old peripheral's
    // disconnect callback so it cannot clear a newly selected connection.
    private func disconnectThen(_ action: @escaping () -> Void) {
        central?.stopScan()
        isConnected = false
        pairing.discardCandidate()
        if afterDisconnect != nil {
            afterDisconnect = action
            return
        }
        timeout?.invalidate()
        guard let board else { clearSession(); action(); return }
        afterDisconnect = action
        reportStatus("box：正在切換連線…")
        if board.state == .connected, session.isIdentifyingChoice, commandCharacteristic != nil {
            send("X")
            armTimeout("", onTimeout: { [weak self] in self?.requestDisconnect() })
        } else {
            requestDisconnect()
        }
    }
    private func requestDisconnect() {
        timeout?.invalidate()
        guard let board, board.state != .disconnected, central.state == .poweredOn else {
            completeDisconnect()
            return
        }
        central.cancelPeripheralConnection(board)
    }
    private func completeDisconnect() {
        let action = afterDisconnect
        afterDisconnect = nil
        clearSession()
        action?()
    }
    private func armTimeout(_ message: String, seconds: TimeInterval = 5, onTimeout: (() -> Void)? = nil) {
        timeout?.invalidate()
        timeout = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                if let onTimeout { onTimeout() }
                else { self?.fail(message, retry: true) }
            }
        }
    }
    private func fail(_ message: String, retry: Bool = false, error: Error? = nil) {
        if let board, BoxPairing.requiresSystemPairingReset(error) {
            showSystemPairingReset(for: board)
            return
        }
        if retry, !stopped, !pairing.isSelecting, pairing.savedDeviceID != nil,
           !needsSystemPairingReset, central.state == .poweredOn {
            disconnectThen { [weak self] in
                guard let self, !self.stopped else { return }
                self.reportStatus("box：\(message) 3 秒後自動重連…")
                self.armTimeout("", seconds: 3) { [weak self] in self?.scan() }
            }
            return
        }
        stopped = true
        central.stopScan()
        let previous = board
        clearSession()
        if let previous { central.cancelPeripheralConnection(previous) }
        reportStatus("box：\(message)")
    }
    private func showSystemPairingReset(for peripheral: CBPeripheral) {
        needsSystemPairingReset = true
        pairing.beginSelection()
        if !discovered.contains(where: { $0.identifier == peripheral.identifier }) {
            discovered.append(peripheral)
        }
        fail("\(BoxDeviceChoice(id: peripheral.identifier).title) 已清除配對，但 macOS 仍保留舊配對。請在「系統設定 → 藍牙」對 AIBox 選擇「忘記此裝置設定」，再回來按「重新搜尋」並確認燈色。")
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn, afterDisconnect != nil { completeDisconnect() }
        switch central.state {
        case .poweredOn:
            stopped = false
            if board == nil { scan() }
        case .unauthorized: fail("未獲藍牙權限；請在系統設定允許 AIBox 使用藍牙。")
        case .poweredOff: clearSession(); reportStatus("box：Mac 藍牙已關閉")
        case .unsupported: fail("此 Mac 不支援 BLE")
        default: clearSession(); reportStatus("box：等待藍牙就緒…")
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        guard !stopped, central.isScanning, afterDisconnect == nil, board == nil,
              name == BoxProtocol.deviceName else { return }
        if pairing.isSelecting {
            if !discovered.contains(where: { $0.identifier == peripheral.identifier }) {
                discovered.append(peripheral)
                onPairingChange(pairingState)
            }
        } else if pairing.shouldReconnect(to: peripheral.identifier) {
            connect(peripheral)
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard board === peripheral, afterDisconnect == nil else { return }
        armTimeout("裝置未回覆服務資訊。")
        peripheral.discoverServices([serviceID])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard board === peripheral else { return }
        if afterDisconnect != nil { completeDisconnect(); return }
        if BoxPairing.requiresSystemPairingReset(error) {
            showSystemPairingReset(for: peripheral)
            return
        }
        fail("連線失敗。", retry: true)
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard board === peripheral else { return }
        if afterDisconnect != nil { completeDisconnect(); return }
        if BoxPairing.requiresSystemPairingReset(error) {
            showSystemPairingReset(for: peripheral)
            return
        }
        clearSession()
        if !stopped { scan() }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard board === peripheral, afterDisconnect == nil else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == serviceID }) else {
            fail("找不到 AIBox 通訊服務。", retry: error != nil, error: error); return
        }
        peripheral.discoverCharacteristics([commandID, eventID], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard board === peripheral, afterDisconnect == nil else { return }
        guard error == nil,
              let rx = service.characteristics?.first(where: { $0.uuid == commandID }), rx.properties.contains(.write),
              let tx = service.characteristics?.first(where: { $0.uuid == eventID }), tx.properties.contains(.notify) else {
            fail("AIBox 通訊特徵不符。", retry: error != nil, error: error); return
        }
        commandCharacteristic = rx
        reportStatus("box：建立藍牙加密連線；若系統要求配對，請允許。")
        armTimeout("藍牙加密連線尚未完成；若系統要求配對，請允許。", seconds: 60)
        peripheral.setNotifyValue(true, for: tx)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard board === peripheral, afterDisconnect == nil, characteristic.uuid == eventID else { return }
        guard error == nil, characteristic.isNotifying else {
            fail("無法訂閱裝置事件。", retry: error != nil, error: error); return
        }
        reportStatus("box：確認裝置中…")
        send(session.subscribed())
        armTimeout("裝置尚未完成授權確認。", seconds: 15)
    }
    private func send(_ command: String) {
        guard let board, board.state == .connected, let commandCharacteristic else { return }
        armTimeout("裝置指令未獲確認。")
        board.writeValue(Data((command + "\n").utf8), for: commandCharacteristic, type: .withResponse)
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard board === peripheral else { return }
        if error != nil {
            if afterDisconnect != nil { requestDisconnect() }
            else { fail("傳送指令失敗。", retry: true, error: error) }
        }
    }
    private func reportReady() {
        guard let board else { return }
        if session.phase == .ready, session.isAuthorized, pairing.shouldReconnect(to: board.identifier) {
            isConnected = true
            let lightStatus = session.confirmedPattern.map { " · \($0.label)已確認" } ?? ""
            reportStatus("box：已連線" + lightStatus)
        } else if session.phase == .rejectedColor {
            reportStatus("box：顏色不符，尚未記住；請重新辨識或選擇另一台。")
        } else if session.isIdentificationVisible {
            reportStatus("box：請看實體 box 閃爍的顏色，並在視窗中選擇。")
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard board === peripheral, characteristic.uuid == eventID else { return }
        if afterDisconnect != nil {
            if error != nil { requestDisconnect() }
            else if let data = characteristic.value, decoder.append(data).contains("ACK X") { requestDisconnect() }
            return
        }
        guard error == nil, let data = characteristic.value else {
            fail("讀取裝置事件失敗。", retry: error != nil, error: error); return
        }
        for line in decoder.append(data) {
            if line.hasPrefix("MIC ") {
                if let reading = session.soundReading(line) { onSoundReading(reading.peak, reading.meetsThreshold) }
                continue
            }
            if line == "ERR IMU" { fail("裝置的加速度計初始化失敗"); return }
            if line == "ERR MIC" { fail("裝置的麥克風初始化失敗"); return }
            if line == "ERR COMMAND" { fail("裝置不支援目前指令，請更新 box 韌體。"); return }
            if line == "ERR COLOR" { fail("裝置無法套用燈號顏色"); return }
            if line == "ERR INTERVAL" { fail("裝置無法套用閃燈間隔"); return }
            if line.hasPrefix("AIBOX-") && line != BoxProtocol.identity { fail("裝置韌體版本不符"); return }
            if line == "ERR OWNER" { fail("這台 box 已綁定其他主機；請先解除配對，或開機後持續搖晃 2 秒。"); return }
            if line == "ERR SECURITY" { fail("無法建立安全配對，請重新連線。"); return }
            if line == "ERR STORAGE" { fail("box 無法儲存配對，請重新連線後重試。"); return }
            if line == "ERR RANDOM" { fail("box 無法產生辨識顏色，請重新辨識。"); return }
            if line == "RESET PAIRING" {
                showSystemPairingReset(for: peripheral)
                return
            }
            if line == "ACK U", session.phase == .unpairing {
                pairing.forgetDevice()
                stop()
                clearSession()
                reportStatus("box：已解除配對，可由其他主機重新配對。")
                return
            }
            let next = session.receive(line)
            if session.needsPairing {
                pairing.beginSelection()
                pairing.select(peripheral.identifier)
                if !discovered.contains(where: { $0.identifier == peripheral.identifier }) { discovered.append(peripheral) }
                if let command = session.beginIdentification() { send(command) }
                reportStatus("box：需要確認燈色，正在讓 box 顯示顏色…")
                continue
            }
            if pairing.isSelecting, session.didConfirmColor {
                _ = pairing.confirmAuthorizedDevice(peripheral.identifier, session: session)
                reportStatus("box：已確認配對，正在同步燈號…")
            }
            if session.pendingCommand == nil { timeout?.invalidate() }
            reportReady()
            if let next { send(next) }
            if isConnected && session.isShake(line) { onShake() }
        }
    }
}
