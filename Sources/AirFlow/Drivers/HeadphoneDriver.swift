import Foundation

/// Represents granular battery levels for wireless headphones (e.g. Left/Right earbuds and Case).
public struct HeadphoneBattery: Sendable, Equatable {
    public let left: Int?
    public let right: Int?
    public let caseLevel: Int?
    public let isCharging: Bool
    
    public init(left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil, isCharging: Bool = false) {
        self.left = left
        self.right = right
        self.caseLevel = caseLevel
        self.isCharging = isCharging
    }
    
    /// Returns primary single percentage representation (average or single earbud).
    public var primaryPercentage: Int {
        if let l = left, let r = right {
            return (l + r) / 2
        }
        return left ?? right ?? caseLevel ?? 0
    }
}

/// Abstract protocol representing a pluggable headphone driver (e.g. Shokz, AirPods, Sony, Bose).
public protocol HeadphoneDriver: AnyObject, Sendable {
    /// Unique driver identifier (e.g., "driver.shokz.opendots", "driver.apple.airpods").
    var driverId: String { get }
    
    /// Human-readable brand name.
    var brandName: String { get }
    
    /// Tests if this driver can manage the specified device by name or signature.
    func canHandle(deviceName: String) -> Bool
    
    /// Starts communication with the headphone hardware.
    func start()
    
    /// Stops communication.
    func stop()
    
    /// Returns latest battery status if available.
    func getBatteryStatus() -> HeadphoneBattery?
    
    /// Queries the headphone for its internal list of multipoint paired devices.
    func queryPairedDevices() async throws -> [PairedDeviceInfo]
    
    /// Callback invoked whenever battery status changes.
    var onBatteryChanged: (@Sendable (HeadphoneBattery) -> Void)? { get set }
    
    /// Callback invoked whenever paired devices list changes.
    var onPairedDevicesChanged: (@Sendable ([PairedDeviceInfo]) -> Void)? { get set }
}
