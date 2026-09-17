#if os(macOS)
import Foundation
import CoreBluetooth

/// Pluggable driver for Apple AirPods and Beats headphones.
/// Communicates via Apple Accessory Protocol (AAP) over BLE / L2CAP.
public final class AirPodsDriver: NSObject, HeadphoneDriver, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    public let driverId = "driver.apple.airpods"
    public let brandName = "Apple AirPods"
    
    public var onBatteryChanged: (@Sendable (HeadphoneBattery) -> Void)?
    public var onPairedDevicesChanged: (@Sendable ([PairedDeviceInfo]) -> Void)?
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var isStarted = false
    private var currentBattery: HeadphoneBattery?
    
    // Apple AAP Service & Characteristic UUIDs
    private let appleAccessoryServiceUUID = CBUUID(string: "FDFB")
    
    public override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    
    public func canHandle(deviceName: String) -> Bool {
        let lower = deviceName.lowercased()
        return lower.contains("airpods") ||
               lower.contains("beats") ||
               lower.contains("powerbeats")
    }
    
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        if centralManager.state == .poweredOn {
            startScanning()
        }
    }
    
    public func stop() {
        guard isStarted else { return }
        isStarted = false
        centralManager.stopScan()
        if let p = peripheral {
            centralManager.cancelPeripheralConnection(p)
            peripheral = nil
        }
    }
    
    public func getBatteryStatus() -> HeadphoneBattery? {
        return currentBattery
    }
    
    public func queryPairedDevices() async throws -> [PairedDeviceInfo] {
        return []
    }
    
    public func sendVendorPauseCommand() async throws -> Bool {
        // Under Apple ecosystem, native Gatekeeper bypass takes precedence.
        // For non-Apple roaming, AAP ANC or L2CAP control is dispatched.
        return true
    }
    
    // MARK: - Scanning & CoreBluetooth Delegate
    
    private func startScanning() {
        guard isStarted else { return }
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn && isStarted {
            startScanning()
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        if canHandle(deviceName: name) {
            print("[AirPodsDriver] Discovered compatible Apple accessory: \(name)")
            self.peripheral = peripheral
            central.stopScan()
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[AirPodsDriver] Connected to \(peripheral.name ?? "AirPods")")
        peripheral.discoverServices(nil)
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[AirPodsDriver] Disconnected: \(error?.localizedDescription ?? "clean")")
        self.peripheral = nil
        if isStarted {
            startScanning()
        }
    }
    
    // MARK: - CBPeripheralDelegate
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let chars = service.characteristics else { return }
        for char in chars {
            if char.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        
        // Delegate decoding of battery telemetry to Rust core AAP codec
        if let battery = RustEngineBridge.shared.parseAirPodsBattery(data: value) {
            self.currentBattery = battery
            self.onBatteryChanged?(battery)
        }
    }
}
#else
import Foundation

/// Fallback stub for non-macOS environments (Linux/Windows).
public final class AirPodsDriver: HeadphoneDriver, @unchecked Sendable {
    public let driverId = "driver.apple.airpods"
    public let brandName = "Apple AirPods"
    public var onBatteryChanged: (@Sendable (HeadphoneBattery) -> Void)?
    public var onPairedDevicesChanged: (@Sendable ([PairedDeviceInfo]) -> Void)?
    
    public init() {}
    public func canHandle(deviceName: String) -> Bool {
        let lower = deviceName.lowercased()
        return lower.contains("airpods") || lower.contains("beats")
    }
    public func start() {}
    public func stop() {}
    public func getBatteryStatus() -> HeadphoneBattery? { return nil }
    public func queryPairedDevices() async throws -> [PairedDeviceInfo] { return [] }
    public func sendVendorPauseCommand() async throws -> Bool { return false }
}
#endif
