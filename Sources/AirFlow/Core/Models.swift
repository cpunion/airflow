import Foundation

/// Represents an audio output device discovered on the system.
public struct AudioDevice: Sendable, Equatable {
    public let id: UInt32
    public let name: String
    public let isBluetooth: Bool
    
    public init(id: UInt32, name: String, isBluetooth: Bool = true) {
        self.id = id
        self.name = name
        self.isBluetooth = isBluetooth
    }
    
    /// Returns true if the device is an Apple AirPods or Beats device with native Apple handoff.
    public var isAirPods: Bool {
        let lower = name.lowercased()
        return lower.contains("airpods") || lower.contains("beats fit pro") || lower.contains("beats studio")
    }
    
    /// Returns true if this device is considered an internal built-in speaker.
    public var isBuiltin: Bool {
        let lower = name.lowercased()
        return lower.contains("speaker") || lower.contains("扬声器") || lower.contains("internal")
    }
}

/// Represents information about a device paired with a headphone.
public struct PairedDeviceInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let address: String?
    public let isConnected: Bool
    
    public init(id: String, name: String, address: String? = nil, isConnected: Bool = false) {
        self.id = id
        self.name = name
        self.address = address
        self.isConnected = isConnected
    }
}

/// Current state of the handoff arbitration engine.
public enum EngineState: Sendable, Equatable {
    /// Idle state, waiting for audio playback events.
    case idle
    /// Bypassed state: active device does not require arbitration (e.g., AirPods or internal speaker).
    case bypassed(reason: String)
    /// Active state: host (Mac/Linux) is actively playing media.
    case hostActive
    /// Active state: mobile peer (iPhone/Android) is actively playing media.
    case peerActive
    /// Cooldown window to prevent circular pause ping-pong loops.
    case cooldown(remainingMs: Int)
}
