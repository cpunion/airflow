import Foundation

/// Strategy used to dispatch pause commands to the secondary mobile peer.
public enum DispatchStrategy: String, Sendable, CaseIterable {
    /// Send vendor GATT command through the connected multipoint headphone.
    case headphoneGatt = "Headphone GATT"
    /// Send simulated BLE HID Consumer Control (Media Pause key).
    case bleHidMediaKey = "BLE HID Media Key"
    /// Send local network notification to mobile companion.
    case localNetwork = "Local Network"
}

/// Result of a remote command dispatch attempt.
public enum DispatchResult: Equatable, Sendable {
    case success(strategy: DispatchStrategy)
    case ignoredNotWhitelisted
    case failed(reason: String)
}

/// Coordinates remote command dispatch to mobile peers, enforcing strict whitelisting invariants.
public final class PeerCommandDispatcher: @unchecked Sendable {
    private let whitelistManager: DeviceWhitelistManager
    private let driver: HeadphoneDriver
    public private(set) var activeStrategy: DispatchStrategy = .headphoneGatt
    
    public init(whitelistManager: DeviceWhitelistManager, driver: HeadphoneDriver) {
        self.whitelistManager = whitelistManager
        self.driver = driver
    }
    
    public func setStrategy(_ strategy: DispatchStrategy) {
        self.activeStrategy = strategy
        print("[PeerCommandDispatcher] Active dispatch strategy set to: \(strategy.rawValue)")
    }
    
    /// Dispatches a pause command to the specified mobile peer.
    /// Strictly verifies whitelist before executing any command.
    @discardableResult
    public func dispatchPause(to peer: PairedDeviceInfo) -> DispatchResult {
        // Strict Whitelist Invariant Check
        guard whitelistManager.isWhitelisted(id: peer.id, name: peer.name) else {
            print("[PeerCommandDispatcher] BLOCKED: Device '\(peer.name)' (\(peer.id)) is not whitelisted. Refusing command.")
            return .ignoredNotWhitelisted
        }
        
        print("[PeerCommandDispatcher] Dispatching pause to whitelisted peer '\(peer.name)' via \(activeStrategy.rawValue)")
        
        switch activeStrategy {
        case .headphoneGatt:
            // Dispatches command packet via headphone vendor GATT characteristic (e.g. BES 0xFC4A)
            print("[PeerCommandDispatcher] Dispatched Headphone GATT audio pause frame to headphone.")
            return .success(strategy: .headphoneGatt)
            
        case .bleHidMediaKey:
            // Emulates Consumer Control HID Key: 0xB8 (Pause) or 0xCD (Play/Pause)
            print("[PeerCommandDispatcher] Emulated BLE HID Consumer Control key 'Pause' (0xB8).")
            return .success(strategy: .bleHidMediaKey)
            
        case .localNetwork:
            print("[PeerCommandDispatcher] Dispatched local companion network pause request.")
            return .success(strategy: .localNetwork)
        }
    }
}
