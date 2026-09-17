import Foundation

/// Composite driver that manages multiple brand-specific drivers (Shokz, AirPods, Sony, Generic)
/// and dynamically delegates calls to the best-matching driver based on the active device.
public final class CompositeHeadphoneDriver: HeadphoneDriver, @unchecked Sendable {
    public let driverId = "driver.composite.universal"
    public var brandName: String {
        return activeDriver.brandName
    }
    
    public var onBatteryChanged: (@Sendable (HeadphoneBattery) -> Void)? {
        didSet {
            for driver in drivers {
                let d = driver
                d.onBatteryChanged = { [weak self] battery in
                    self?.onBatteryChanged?(battery)
                }
            }
        }
    }
    
    public var onPairedDevicesChanged: (@Sendable ([PairedDeviceInfo]) -> Void)? {
        didSet {
            for driver in drivers {
                let d = driver
                d.onPairedDevicesChanged = { [weak self] devices in
                    self?.onPairedDevicesChanged?(devices)
                }
            }
        }
    }
    
    private let drivers: [HeadphoneDriver]
    private var activeDriver: HeadphoneDriver
    
    public init(drivers: [HeadphoneDriver]) {
        self.drivers = drivers
        self.activeDriver = drivers.first ?? GenericDriver()
        
        // Wire up initial callbacks
        for driver in drivers {
            let d = driver
            d.onBatteryChanged = { [weak self] battery in
                self?.onBatteryChanged?(battery)
            }
            d.onPairedDevicesChanged = { [weak self] devices in
                self?.onPairedDevicesChanged?(devices)
            }
        }
    }
    
    /// Selects and switches the active driver based on the headphone name.
    public func selectDriver(for deviceName: String) {
        for driver in drivers {
            if driver.canHandle(deviceName: deviceName) {
                if driver.driverId != activeDriver.driverId {
                    print("[CompositeDriver] Switching active driver to '\(driver.brandName)' for device: \(deviceName)")
                    activeDriver.stop()
                    activeDriver = driver
                    activeDriver.start()
                }
                return
            }
        }
    }
    
    public func canHandle(deviceName: String) -> Bool {
        return drivers.contains { $0.canHandle(deviceName: deviceName) }
    }
    
    public func start() {
        activeDriver.start()
    }
    
    public func stop() {
        for driver in drivers {
            driver.stop()
        }
    }
    
    public func getBatteryStatus() -> HeadphoneBattery? {
        return activeDriver.getBatteryStatus()
    }
    
    public func queryPairedDevices() async throws -> [PairedDeviceInfo] {
        return try await activeDriver.queryPairedDevices()
    }
    
    public func sendVendorPauseCommand() async throws -> Bool {
        return try await activeDriver.sendVendorPauseCommand()
    }
}
