import Foundation
import CoreBluetooth

public enum BoxPairingColor: Int, CaseIterable {
    case red, green, blue

    public var label: String {
        switch self {
        case .red: return "紅色"
        case .green: return "綠色"
        case .blue: return "藍色"
        }
    }

    public var rgb: BoxRGB {
        switch self {
        case .red: return BoxRGB(red: 255, green: 0, blue: 0)
        case .green: return BoxRGB(red: 0, green: 255, blue: 0)
        case .blue: return BoxRGB(red: 0, green: 0, blue: 255)
        }
    }

    var code: String { ["R", "G", "B"][rawValue] }
}

/// A saved choice changes only after the displayed color is correctly confirmed.
public final class BoxPairing {
    private let defaults: UserDefaults
    private static let key = "aibox.selectedBoxIdentifier"
    public private(set) var savedDeviceID: UUID?
    public private(set) var isSelecting = false
    public private(set) var candidateID: UUID?

    /// A missing peer bond requires macOS to forget its cached key. Reconnecting
    /// or clearing our saved peripheral UUID does not remove that system bond.
    public static func requiresSystemPairingReset(_ error: Error?) -> Bool {
        guard let error = error as NSError? else { return false }
        return error.domain == CBErrorDomain
            && error.code == CBError.peerRemovedPairingInformation.rawValue
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        savedDeviceID = defaults.string(forKey: Self.key).flatMap(UUID.init(uuidString:))
    }

    public func shouldReconnect(to identifier: UUID) -> Bool {
        !isSelecting && identifier == savedDeviceID
    }

    public func beginSelection() {
        isSelecting = true
        discardCandidate()
    }

    public func select(_ identifier: UUID) {
        guard isSelecting else { return }
        candidateID = identifier
    }

    @discardableResult
    public func confirmAuthorizedDevice(_ identifier: UUID, session: BoxSession) -> Bool {
        guard isSelecting, candidateID == identifier, session.isAuthorized, session.didConfirmColor else { return false }
        savedDeviceID = identifier
        defaults.set(identifier.uuidString, forKey: Self.key)
        isSelecting = false
        discardCandidate()
        return true
    }

    public func discardCandidate() {
        candidateID = nil
    }

    public func forgetDevice() {
        savedDeviceID = nil
        defaults.removeObject(forKey: Self.key)
        cancelSelection()
    }

    public func cancelSelection() {
        isSelecting = false
        discardCandidate()
    }
}
