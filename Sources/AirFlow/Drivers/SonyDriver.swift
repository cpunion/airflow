#if os(macOS)
import Foundation
import CoreBluetooth

/// Pluggable driver for Sony headphones (WH-1000XM4/XM5, WF-1000XM4/XM5, LinkBuds).
/// Communicates via Sony MDR BLE GATT service.
public final class SonyDriver: NSObject, HeadphoneDriver, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    public let driverId = "driver.sony.mdr"
    public let brandName = "Sony MDR"
    
    public var onBatteryChanged: (@Sendable (HeadphoneBattery) -> Void)?
    public var onPairedDevicesChanged: (@Sendable ([PairedDeviceInfo]) -> Void)?
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var isStarted = false
    private var currentBattery: HeadphoneBattery?
    
    // Sony MDR GATT Service UUIDs
    private let sonyServiceUUID = CBUUID(string: "0000FF00-0000-1000-8000-00805F9B34FB")
    private let sonyTxCharUUID = CBUUID(string: "0000FF01-0000-1000-8000-00805F9B34FB")
    private let sonyRxCharUUID = CBUUID(string: "0000FF02-0000-1000-8000-00805F9B34FB")
    
    public override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    
    public func canHandle(deviceName: String) -> Bool {
        let lower = deviceName.lowercased()
        return lower.contains("sony") ||
               lower.contains("wh-1000") ||
               lower.contains("wf-1000") ||
               lower.contains("linkbuds") ||
               lower.contains("wi-1000")
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
        guard let p = peripheral else {
            print("[SonyDriver] Peripheral not connected.")
            return false
        }
        
        guard let service = p.services?.first(where: { $0.uuid == sonyServiceUUID }),
              let char = service.characteristics?.first(where: { $0.uuid == sonyTxCharUUID }) else {
            print("[SonyDriver] Sony MDR Tx characteristic not found.")
            return false
        }
        
        // Build Sony MDR switch audio / pause packet using Rust core
        let packet = RustEngineBridge.shared.buildSonySwitchAudioPacket(targetSlot: 0x01)
        p.writeValue(packet, for: char, type: .withoutResponse)
        print("[SonyDriver] Dispatched Sony MDR switch/pause frame to headphone.")
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
            print("[SonyDriver] Discovered Sony headphone: \(name)")
            self.peripheral = peripheral
            central.stopScan()
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[SonyDriver] Connected to \(peripheral.name ?? "Sony")")
        peripheral.discoverServices([sonyServiceUUID])
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[SonyDriver] Disconnected: \(error?.localizedDescription ?? "clean")")
        self.peripheral = nil
        if isStarted {
            startScanning()
        }
    }
    
    // MARK: - CBPeripheralDelegate
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for service in services {
            if service.uuid == sonyServiceUUID {
                peripheral.discoverCharacteristics([sonyTxCharUUID, sonyRxCharUUID], for: service)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let chars = service.characteristics else { return }
        for char in chars {
            if char.uuid == sonyRxCharUUID {
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        
        // Delegate decoding of MDR telemetry to Rust core
        if let battery = RustEngineBridge.shared.parseSonyBattery(data: value) {
            self.currentBattery = battery
            self.onBatteryChanged?(battery)
        }
    }
}
#else
import Foundation

/// Fallback stub for non-macOS environments (Linux/Windows).
public final class SonyDriver: HeadphoneDriver, @unchecked Sendable {
    public let driverId = "driver.sony.mdr"
    public let brandName = "Sony MDR"
    public var onBatteryChanged: (@Sendable (HeadphoneBattery) -> Void)?
    public var onPairedDevicesChanged: (@Sendable ([PairedDeviceInfo]) -> Void)?
    
    public init() {}
    public func canHandle(deviceName: String) -> Bool {
        let lower = deviceName.lowercased()
        return lower.contains("sony") || lower.contains("wh-1000") || lower.contains("wf-1000")
    }
    public func start() {}
    public func stop() {}
    public func getBatteryStatus() -> HeadphoneBattery? { return nil }
    public func queryPairedDevices() async throws -> [PairedDeviceInfo] { return [] }
    public func sendVendorPauseCommand() async throws -> Bool { return false }
}
#endif
