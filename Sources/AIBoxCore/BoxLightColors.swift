import Foundation

public struct BoxRGB: Codable, Equatable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var hex: String { String(format: "%02X%02X%02X", red, green, blue) }
}

public enum BoxColorSlot: Int {
    case idle, completion, completionAlternate, permission, permissionAlternate
}

public struct BoxLightColors: Codable, Equatable {
    public var idle = BoxRGB(red: 0, green: 0, blue: 255)
    public var completion = BoxRGB(red: 255, green: 255, blue: 0)
    public var completionAlternate = BoxRGB(red: 255, green: 255, blue: 255)
    public var permission = BoxRGB(red: 255, green: 0, blue: 0)
    public var permissionAlternate = BoxRGB(red: 255, green: 255, blue: 255)

    public init() {}

    public subscript(slot: BoxColorSlot) -> BoxRGB {
        get {
            switch slot {
            case .idle: return idle
            case .completion: return completion
            case .completionAlternate: return completionAlternate
            case .permission: return permission
            case .permissionAlternate: return permissionAlternate
            }
        }
        set {
            switch slot {
            case .idle: idle = newValue
            case .completion: completion = newValue
            case .completionAlternate: completionAlternate = newValue
            case .permission: permission = newValue
            case .permissionAlternate: permissionAlternate = newValue
            }
        }
    }

    public func command(for pattern: BoxLightPattern) -> String {
        let first: BoxRGB
        let second: BoxRGB
        switch pattern {
        case .idle: (first, second) = (idle, idle)
        case .completion: (first, second) = (completion, completionAlternate)
        case .permission: (first, second) = (permission, permissionAlternate)
        }
        return "L \(pattern.rawValue) \(first.hex) \(second.hex)"
    }
}
