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
    private var statusText = { String(localized: "box: Not connected", bundle: AppLanguage.bundle) }
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
                        status: statusText())
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
        reportStatus(String(localized: "box: Showing identification color again…", bundle: AppLanguage.bundle))
    }
    func confirmColor(_ color: BoxPairingColor) {
        guard afterDisconnect == nil, board?.state == .connected, pairingState.canConfirm,
              let command = session.answer(color) else { return }
        send(command)
        reportStatus(String(localized: "box: Waiting for color confirmation and pairing to be saved…", bundle: AppLanguage.bundle))
    }
    var canUnpair: Bool { isConnected && session.phase == .ready }
    func unpair() {
        guard canUnpair, let command = session.unpair() else { return }
        stopped = true
        central.stopScan()
        isConnected = false
        send(command)
        reportStatus(String(localized: "box: Unpairing…", bundle: AppLanguage.bundle))
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
    func refreshLanguage() {
        onStatus(statusText())
        onPairingChange(pairingState)
    }
    private func reportStatus(_ value: @autoclosure @escaping () -> String) {
        statusText = value
        onStatus(value())
        onPairingChange(pairingState)
    }
    private func scan() {
        guard !stopped else { return }
        guard central.state == .poweredOn else { centralManagerDidUpdateState(central); return }
        guard pairing.isSelecting || pairing.savedDeviceID != nil else {
            reportStatus(String(localized: "box: No device selected. Use Choose / Change Device in Settings.", bundle: AppLanguage.bundle))
            return
        }
        let selecting = pairing.isSelecting
        reportStatus(selecting ? String(localized: "box: Searching for nearby devices…", bundle: AppLanguage.bundle) : String(localized: "box: Searching for remembered device…", bundle: AppLanguage.bundle))
        central.scanForPeripherals(withServices: [serviceID])
        armTimeout(String(localized: "Remembered AIBox not found. Check its power and reconnect.", bundle: AppLanguage.bundle), seconds: 30) { [weak self] in
            guard let self else { return }
            if self.pairing.isSelecting {
                self.central.stopScan()
                let isEmpty = self.discovered.isEmpty
                self.reportStatus(isEmpty
                    ? String(localized: "box: No device found. Check its power and search again.", bundle: AppLanguage.bundle)
                    : String(localized: "box: Select a device, then click Identify.", bundle: AppLanguage.bundle))
            } else {
                self.reportStatus(String(localized: "box: Waiting for remembered AIBox; it will connect automatically when powered on…", bundle: AppLanguage.bundle))
            }
        }
    }
    private func connect(_ peripheral: CBPeripheral) {
        needsSystemPairingReset = false
        board = peripheral
        peripheral.delegate = self
        central.stopScan()
        reportStatus(String(localized: "box: Connecting…", bundle: AppLanguage.bundle))
        armTimeout(String(localized: "Connection timed out.", bundle: AppLanguage.bundle), seconds: 15)
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
        reportStatus(String(localized: "box: Switching connections…", bundle: AppLanguage.bundle))
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
    private func armTimeout(_ message: @autoclosure @escaping () -> String, seconds: TimeInterval = 5, onTimeout: (() -> Void)? = nil) {
        timeout?.invalidate()
        timeout = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                if let onTimeout { onTimeout() }
                else { self?.fail(message(), retry: true) }
            }
        }
    }
    private func fail(_ message: @autoclosure @escaping () -> String, retry: Bool = false, error: Error? = nil) {
        if let board, BoxPairing.requiresSystemPairingReset(error) {
            showSystemPairingReset(for: board)
            return
        }
        if retry, !stopped, !pairing.isSelecting, pairing.savedDeviceID != nil,
           !needsSystemPairingReset, central.state == .poweredOn {
            disconnectThen { [weak self] in
                guard let self, !self.stopped else { return }
                self.reportStatus(String(localized: "box: \(String(message())) Reconnecting in 3 seconds…", bundle: AppLanguage.bundle))
                self.armTimeout("", seconds: 3) { [weak self] in self?.scan() }
            }
            return
        }
        stopped = true
        central.stopScan()
        let previous = board
        clearSession()
        if let previous { central.cancelPeripheralConnection(previous) }
        reportStatus("box: \(message())")
    }
    private func showSystemPairingReset(for peripheral: CBPeripheral) {
        needsSystemPairingReset = true
        pairing.beginSelection()
        if !discovered.contains(where: { $0.identifier == peripheral.identifier }) {
            discovered.append(peripheral)
        }
        fail(String(localized: "\(String(BoxDeviceChoice(id: peripheral.identifier).title)) cleared its pairing, but macOS still has the old pairing. In System Settings → Bluetooth, choose Forget This Device for AIBox, then return, click Search Again and confirm the light color.", bundle: AppLanguage.bundle))
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn, afterDisconnect != nil { completeDisconnect() }
        switch central.state {
        case .poweredOn:
            stopped = false
            if board == nil { scan() }
        case .unauthorized: fail(String(localized: "Bluetooth access denied. Allow AIBox to use Bluetooth in System Settings.", bundle: AppLanguage.bundle))
        case .poweredOff: clearSession(); reportStatus(String(localized: "box: Mac Bluetooth is off", bundle: AppLanguage.bundle))
        case .unsupported: fail(String(localized: "This Mac does not support BLE", bundle: AppLanguage.bundle))
        default: clearSession(); reportStatus(String(localized: "box: Waiting for Bluetooth…", bundle: AppLanguage.bundle))
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
        armTimeout(String(localized: "The device did not return service information.", bundle: AppLanguage.bundle))
        peripheral.discoverServices([serviceID])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard board === peripheral else { return }
        if afterDisconnect != nil { completeDisconnect(); return }
        if BoxPairing.requiresSystemPairingReset(error) {
            showSystemPairingReset(for: peripheral)
            return
        }
        fail(String(localized: "Connection failed.", bundle: AppLanguage.bundle), retry: true)
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
            fail(String(localized: "AIBox communication service not found.", bundle: AppLanguage.bundle), retry: error != nil, error: error); return
        }
        peripheral.discoverCharacteristics([commandID, eventID], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard board === peripheral, afterDisconnect == nil else { return }
        guard error == nil,
              let rx = service.characteristics?.first(where: { $0.uuid == commandID }), rx.properties.contains(.write),
              let tx = service.characteristics?.first(where: { $0.uuid == eventID }), tx.properties.contains(.notify) else {
            fail(String(localized: "AIBox communication characteristics do not match.", bundle: AppLanguage.bundle), retry: error != nil, error: error); return
        }
        commandCharacteristic = rx
        reportStatus(String(localized: "box: Establishing encrypted Bluetooth connection. Allow pairing if prompted.", bundle: AppLanguage.bundle))
        armTimeout(String(localized: "Encrypted Bluetooth connection is incomplete. Allow pairing if prompted.", bundle: AppLanguage.bundle), seconds: 60)
        peripheral.setNotifyValue(true, for: tx)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard board === peripheral, afterDisconnect == nil, characteristic.uuid == eventID else { return }
        guard error == nil, characteristic.isNotifying else {
            fail(String(localized: "Could not subscribe to device events.", bundle: AppLanguage.bundle), retry: error != nil, error: error); return
        }
        reportStatus(String(localized: "box: Verifying device…", bundle: AppLanguage.bundle))
        send(session.subscribed())
        armTimeout(String(localized: "Device authorization has not completed.", bundle: AppLanguage.bundle), seconds: 15)
    }
    private func send(_ command: String) {
        guard let board, board.state == .connected, let commandCharacteristic else { return }
        armTimeout(String(localized: "Device command was not acknowledged.", bundle: AppLanguage.bundle))
        board.writeValue(Data((command + "\n").utf8), for: commandCharacteristic, type: .withResponse)
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard board === peripheral else { return }
        if error != nil {
            if afterDisconnect != nil { requestDisconnect() }
            else { fail(String(localized: "Failed to send command.", bundle: AppLanguage.bundle), retry: true, error: error) }
        }
    }
    private func reportReady() {
        guard let board else { return }
        if session.phase == .ready, session.isAuthorized, pairing.shouldReconnect(to: board.identifier) {
            isConnected = true
            let confirmedPattern = session.confirmedPattern
            let lightStatus = { confirmedPattern.map { String(localized: " · \(String($0.label)) confirmed", bundle: AppLanguage.bundle) } ?? "" }
            reportStatus(String(localized: "box: Connected", bundle: AppLanguage.bundle) + lightStatus())
        } else if session.phase == .rejectedColor {
            reportStatus(String(localized: "box: Color mismatch; device not saved. Identify again or choose another device.", bundle: AppLanguage.bundle))
        } else if session.isIdentificationVisible {
            reportStatus(String(localized: "box: Observe the flashing color on the physical box and select it in the window.", bundle: AppLanguage.bundle))
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
            fail(String(localized: "Failed to read device events.", bundle: AppLanguage.bundle), retry: error != nil, error: error); return
        }
        for line in decoder.append(data) {
            if line.hasPrefix("MIC ") {
                if let reading = session.soundReading(line) { onSoundReading(reading.peak, reading.meetsThreshold) }
                continue
            }
            if line == "ERR IMU" { fail(String(localized: "Device accelerometer initialization failed", bundle: AppLanguage.bundle)); return }
            if line == "ERR MIC" { fail(String(localized: "Device microphone initialization failed", bundle: AppLanguage.bundle)); return }
            if line == "ERR COMMAND" { fail(String(localized: "Device does not support this command. Update the box firmware.", bundle: AppLanguage.bundle)); return }
            if line == "ERR COLOR" { fail(String(localized: "Device could not apply light colors", bundle: AppLanguage.bundle)); return }
            if line == "ERR INTERVAL" { fail(String(localized: "Device could not apply blink interval", bundle: AppLanguage.bundle)); return }
            if line.hasPrefix("AIBOX-") && line != BoxProtocol.identity { fail(String(localized: "Device firmware version mismatch", bundle: AppLanguage.bundle)); return }
            if line == "ERR OWNER" { fail(String(localized: "This box is paired with another host. Unpair it first or shake continuously for 2 seconds after powering on.", bundle: AppLanguage.bundle)); return }
            if line == "ERR SECURITY" { fail(String(localized: "Could not establish secure pairing. Reconnect and try again.", bundle: AppLanguage.bundle)); return }
            if line == "ERR STORAGE" { fail(String(localized: "box could not save pairing. Reconnect and try again.", bundle: AppLanguage.bundle)); return }
            if line == "ERR RANDOM" { fail(String(localized: "box could not generate an identification color. Identify again.", bundle: AppLanguage.bundle)); return }
            if line == "RESET PAIRING" {
                showSystemPairingReset(for: peripheral)
                return
            }
            if line == "ACK U", session.phase == .unpairing {
                pairing.forgetDevice()
                stop()
                clearSession()
                reportStatus(String(localized: "box: Unpaired; ready to pair with another host.", bundle: AppLanguage.bundle))
                return
            }
            let next = session.receive(line)
            if session.needsPairing {
                pairing.beginSelection()
                pairing.select(peripheral.identifier)
                if !discovered.contains(where: { $0.identifier == peripheral.identifier }) { discovered.append(peripheral) }
                if let command = session.beginIdentification() { send(command) }
                reportStatus(String(localized: "box: Color confirmation required; displaying identification color…", bundle: AppLanguage.bundle))
                continue
            }
            if pairing.isSelecting, session.didConfirmColor {
                _ = pairing.confirmAuthorizedDevice(peripheral.identifier, session: session)
                reportStatus(String(localized: "box: Pairing confirmed; syncing lights…", bundle: AppLanguage.bundle))
            }
            if session.pendingCommand == nil { timeout?.invalidate() }
            reportReady()
            if let next { send(next) }
            if isConnected && session.isShake(line) { onShake() }
        }
    }
}
