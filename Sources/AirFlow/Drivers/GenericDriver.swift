import Foundation
#if os(macOS)
import CoreBluetooth
#endif

/// Fallback driver for generic standard Bluetooth headphones and earbuds.
/// Supports standard Bluetooth Battery Service (0x180F) and roaming coordination.
public final class GenericDriver: NSObject, HeadphoneDriver, @unchecked Sendable {
    public let driverId = "driver.generic.bluetooth"
    public let brandName = "Generic Bluetooth"
    
    public var onBatteryChanged: (@Sendable (HeadphoneBattery) -> Void)?
    public var onPairedDevicesChanged: (@Sendable ([PairedDeviceInfo]) -> Void)?
    
    private var isStarted = false
    private var currentBattery: HeadphoneBattery?
    
    #if os(macOS)
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryLevelCharUUID = CBUUID(string: "2A19")
    #endif
    
    public override init() {
        super.init()
        #if os(macOS)
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
        #endif
    }
    
    public func canHandle(deviceName: String) -> Bool {
        // Fallback handles all Bluetooth audio devices if no specialized driver matches
        return true
    }
    
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        #if os(macOS)
        if centralManager.state == .poweredOn {
            startScanning()
        }
        #endif
    }
    
    public func stop() {
        guard isStarted else { return }
        isStarted = false
        #if os(macOS)
        centralManager.stopScan()
        if let p = peripheral {
            centralManager.cancelPeripheralConnection(p)
            peripheral = nil
        }
        #endif
    }
    
    public func getBatteryStatus() -> HeadphoneBattery? {
        #if os(macOS)
        if let sysBattery = MacOSBluetoothBatteryProvider.queryBattery() {
            self.currentBattery = sysBattery
            return sysBattery
        }
        #endif
        return currentBattery
    }
    
    public func queryPairedDevices() async throws -> [PairedDeviceInfo] {
        return []
    }
    
    public func sendVendorPauseCommand() async throws -> Bool {
        // Generic headphones do not support proprietary multipoint switching commands.
        // Roaming is performed via OS-level disconnect / connect or peer media pause.
        return false
    }
    
    #if os(macOS)
    private func checkConnectedPeripherals() {
        guard isStarted, centralManager.state == .poweredOn else { return }
        if peripheral != nil { return }
        let connected = centralManager.retrieveConnectedPeripherals(withServices: [batteryServiceUUID, CBUUID(string: "180A")])
        if let p = connected.first {
            print("[GenericDriver] Retrieved already-connected audio device: \(p.name ?? "")")
            self.peripheral = p
            p.delegate = self
            centralManager.connect(p, options: nil)
        }
    }
    
    fileprivate func startScanning() {
        guard isStarted else { return }
        checkConnectedPeripherals()
        centralManager.scanForPeripherals(withServices: [batteryServiceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }
    #endif
}

#if os(macOS)
extension GenericDriver: CBCentralManagerDelegate, CBPeripheralDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn && isStarted {
            checkConnectedPeripherals()
            startScanning()
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        self.peripheral = peripheral
        central.stopScan()
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([batteryServiceUUID])
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.peripheral = nil
        if isStarted {
            startScanning()
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for service in services where service.uuid == batteryServiceUUID {
            peripheral.discoverCharacteristics([batteryLevelCharUUID], for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let chars = service.characteristics else { return }
        for char in chars where char.uuid == batteryLevelCharUUID {
            peripheral.readValue(for: char)
            peripheral.setNotifyValue(true, for: char)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, !data.isEmpty else { return }
        let level = Int(data[0])
        let battery = HeadphoneBattery(left: level, right: level, caseLevel: nil, isCharging: false)
        self.currentBattery = battery
        self.onBatteryChanged?(battery)
    }
}
#endif
