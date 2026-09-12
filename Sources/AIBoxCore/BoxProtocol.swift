import Foundation

public enum BoxProtocol {
    public static let deviceName = "AIBox"
    public static let identity = "AIBOX-5"
    public static let service = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let commands = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let events = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
}

public enum BoxLightPattern: String {
    case idle = "I"
    case completion = "C"
    case permission = "P"

    public var label: String {
        switch self {
        case .idle: return String(localized: "Idle light", bundle: AppLanguage.bundle)
        case .completion: return String(localized: "Response stop light", bundle: AppLanguage.bundle)
        case .permission: return String(localized: "Permission request light", bundle: AppLanguage.bundle)
        }
    }
}

/// GATT may split a newline-delimited message across multiple packets.
public struct BoxLineDecoder {
    private var buffer = Data()
    public init() {}
    public mutating func append(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 10) {
            if let line = String(data: buffer[..<newline], encoding: .utf8) {
                lines.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            buffer.removeSubrange(...newline)
        }
        return lines
    }
}

/// Authorization precedes normal commands; every color answer belongs to a box-issued challenge.
public struct BoxSession {
    public enum Phase { case disconnected, identifying, authorizing, startingIdentification, choosingColor, answering, rejectedColor, arming, ready, unpairing }
    public private(set) var phase: Phase = .disconnected
    public private(set) var pendingCommand: String?
    public private(set) var desiredPattern: BoxLightPattern = .idle
    public private(set) var confirmedPattern: BoxLightPattern?
    public private(set) var colors = BoxLightColors()
    public private(set) var blinkIntervalTenths = 10
    public private(set) var soundSensitivity = 50
    public private(set) var isAuthorized = false
    public private(set) var didConfirmColor = false
    public private(set) var needsPairing = false
    private var identifyingChoice = false
    private var challenge: String?
    private var confirmedIntervalTenths: Int?
    private var confirmedSoundSensitivity: Int?
    private var soundMonitoring = false
    private var confirmedSoundMonitoring = false
    private var detectShake = true
    private var detectSound = true
    private var confirmedDetectionCommand: String?
    private var detectionCommand: String { "S \(detectShake ? 1 : 0)\(detectSound ? 1 : 0)" }
    private var confirmedLightCommand: String?

    public var isIdentificationVisible: Bool { phase == .choosingColor && challenge != nil }
    public var canRetryIdentification: Bool { phase == .choosingColor || phase == .rejectedColor }
    public var isIdentifyingChoice: Bool { identifyingChoice && !didConfirmColor }

    public init() {}
    public mutating func disconnected() {
        phase = .disconnected
        pendingCommand = nil
        confirmedPattern = nil
        confirmedLightCommand = nil
        confirmedIntervalTenths = nil
        confirmedSoundSensitivity = nil
        confirmedSoundMonitoring = false
        confirmedDetectionCommand = nil
        challenge = nil
        identifyingChoice = false
        isAuthorized = false
        didConfirmColor = false
        needsPairing = false
    }
    public mutating func subscribed() -> String {
        phase = .identifying
        pendingCommand = "?"
        return "?"
    }
    public mutating func setPattern(_ value: BoxLightPattern) -> String? {
        desiredPattern = value
        return nextLightCommand()
    }
    public mutating func setColors(_ value: BoxLightColors) -> String? {
        colors = value
        return nextLightCommand()
    }
    public mutating func setBlinkInterval(_ tenths: Int) -> String? {
        blinkIntervalTenths = min(100, max(1, tenths))
        return nextLightCommand()
    }
    public mutating func setDetection(shake: Bool, sound: Bool) -> String? {
        detectShake = shake
        detectSound = sound
        return nextLightCommand()
    }
    public mutating func setSoundSensitivity(_ value: Int) -> String? {
        soundSensitivity = min(100, max(0, value))
        return nextLightCommand()
    }
    public mutating func setSoundMonitoring(_ enabled: Bool) -> String? {
        soundMonitoring = enabled
        return nextLightCommand()
    }
    public func soundReading(_ line: String) -> (peak: Int, meetsThreshold: Bool)? {
        let fields = line.split(separator: " ", omittingEmptySubsequences: false)
        guard phase == .ready, isAuthorized, soundMonitoring, detectSound,
              fields.count == 3, fields[0] == "MIC", let peak = Int(fields[1]),
              (0...32768).contains(peak), fields[2] == "0" || fields[2] == "1" else { return nil }
        return (peak, fields[2] == "1")
    }
    public mutating func beginIdentification() -> String? {
        identifyingChoice = true
        needsPairing = false
        challenge = nil
        didConfirmColor = false
        isAuthorized = false
        if phase == .disconnected || phase == .identifying { return nil }
        phase = .startingIdentification
        pendingCommand = "B"
        return "B"
    }
    public mutating func answer(_ color: BoxPairingColor) -> String? {
        guard isIdentificationVisible, let challenge else { return nil }
        phase = .answering
        let command = "V \(challenge) \(color.code)"
        pendingCommand = command
        return command
    }
    public mutating func unpair() -> String? {
        guard isAuthorized, phase == .ready else { return nil }
        phase = .unpairing
        pendingCommand = "U"
        return "U"
    }
    private mutating func arm() -> String {
        isAuthorized = true
        needsPairing = false
        phase = .arming
        pendingCommand = detectionCommand
        return detectionCommand
    }
    public mutating func receive(_ line: String) -> String? {
        if phase == .identifying && line == BoxProtocol.identity {
            phase = identifyingChoice ? .startingIdentification : .authorizing
            pendingCommand = identifyingChoice ? "B" : "A"
            return pendingCommand
        }
        if phase == .authorizing {
            if line == "AUTHORIZED" { return arm() }
            if line == "PAIR REQUIRED" { needsPairing = true; pendingCommand = nil }
        }
        if phase == .startingIdentification, line.hasPrefix("PAIR ") {
            let value = String(line.dropFirst(5))
            guard value.count == 8, value.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }) else { return nil }
            challenge = value
            phase = .choosingColor
            pendingCommand = nil
            return nil
        }
        if phase == .answering, let challenge {
            if line == "PAIRED \(challenge)" {
                self.challenge = nil
                didConfirmColor = true
                return arm()
            }
            if line == "ERR ANSWER \(challenge)" {
                self.challenge = nil
                phase = .rejectedColor
                pendingCommand = nil
            }
        }
        if phase == .arming, let pendingCommand, line == "ACK \(pendingCommand)" {
            confirmedDetectionCommand = pendingCommand
            phase = .ready
            self.pendingCommand = nil
            return nextLightCommand()
        }
        if phase == .ready, let pendingCommand, line == "ACK \(pendingCommand)" {
            if pendingCommand.hasPrefix("S ") {
                confirmedDetectionCommand = pendingCommand
            } else if pendingCommand.hasPrefix("M ") {
                confirmedSoundSensitivity = Int(pendingCommand.dropFirst(2))
            } else if pendingCommand.hasPrefix("R ") {
                confirmedSoundMonitoring = pendingCommand == "R 1"
            } else if pendingCommand.hasPrefix("T ") {
                confirmedIntervalTenths = Int(pendingCommand.dropFirst(2)).map { $0 / 100 }
            } else {
                confirmedLightCommand = pendingCommand
                confirmedPattern = BoxLightPattern(rawValue: String(pendingCommand.split(separator: " ")[1]))
            }
            self.pendingCommand = nil
            return nextLightCommand()
        }
        return nil
    }
    public func isShake(_ line: String) -> Bool {
        guard phase == .ready, isAuthorized, detectShake || detectSound, line.hasPrefix("SHAKE "),
              let number = UInt32(line.dropFirst(6)) else { return false }
        return number > 0
    }
    private mutating func nextLightCommand() -> String? {
        guard phase == .ready, isAuthorized, pendingCommand == nil else { return nil }
        if confirmedDetectionCommand != detectionCommand {
            pendingCommand = detectionCommand
            return detectionCommand
        }
        if confirmedSoundSensitivity != soundSensitivity {
            let command = "M \(soundSensitivity)"
            pendingCommand = command
            return command
        }
        if confirmedSoundMonitoring != soundMonitoring {
            let command = "R \(soundMonitoring ? 1 : 0)"
            pendingCommand = command
            return command
        }
        if confirmedIntervalTenths != blinkIntervalTenths {
            let command = "T \(blinkIntervalTenths * 100)"
            pendingCommand = command
            return command
        }
        let command = colors.command(for: desiredPattern)
        guard confirmedLightCommand != command else { return nil }
        pendingCommand = command
        return command
    }
}
