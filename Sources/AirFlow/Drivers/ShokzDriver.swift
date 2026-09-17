#if os(macOS)
import Foundation
import CoreBluetooth

/// Pluggable driver for Shokz headphones (e.g. OpenDots 2, OpenRun Pro, OpenFit).
/// Communicates via Google Fast Pair (0xFE2C) and Bestechnic (BES) vendor GATT services.
public final class ShokzDriver: NSObject, HeadphoneDriver, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    public let driverId = "driver.shokz.opendots"
    public let brandName = "Shokz"
    
    public var onBatteryChanged: (@Sendable (HeadphoneBattery) -> Void)?
    public var onPairedDevicesChanged: (@Sendable ([PairedDeviceInfo]) -> Void)?
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var isStarted = false
    private var currentBattery: HeadphoneBattery?
    
    private let targetConfig: AppConfig
    
    // UUID Constants
    private let fastPairServiceUUID = CBUUID(string: "FE2C")
    private let fastPairBatteryCharUUID = CBUUID(string: "FE2C1239-8366-4814-8EB0-01DE32100BEA")
    private let vendorServiceUUID = CBUUID(string: "FC4A")
    private let vendorWriteCharUUID = CBUUID(string: "FC4C")
    private let vendorNotifyCharUUID = CBUUID(string: "FC4B")
    private let besCoreServiceUUID = CBUUID(string: "01000100-0000-1000-8000-009078563412")
    private let besWriteCharUUID = CBUUID(string: "03000300-0000-1000-8000-009278563412")
    private let besNotifyCharUUID = CBUUID(string: "02000200-0000-1000-8000-009178563412")
    
    public init(config: AppConfig = .load()) {
        self.targetConfig = config
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    
    public func canHandle(deviceName: String) -> Bool {
        let lower = deviceName.lowercased()
        return lower.contains("shokz") || lower.contains("opendots") || lower.contains("openfit") || lower.contains("openrun")
    }
    
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        if centralManager.state == .poweredOn {
            checkConnectedPeripherals()
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
        #if os(macOS)
        if let sysBattery = MacOSBluetoothBatteryProvider.queryBattery(for: "Shokz") ??
                            MacOSBluetoothBatteryProvider.queryBattery(for: "OpenDots") ??
                            MacOSBluetoothBatteryProvider.queryBattery(for: targetConfig.targetHeadphoneName) {
            self.currentBattery = sysBattery
            return sysBattery
        }
        #endif
        return currentBattery
    }
    
    public func queryPairedDevices() async throws -> [PairedDeviceInfo] {
        // Return paired device info if parsed from vendor telemetry or fallback from config
        if let phoneName = targetConfig.targetPhoneName {
            return [
                PairedDeviceInfo(
                    id: targetConfig.targetPhoneUUID ?? UUID().uuidString,
                    name: phoneName,
                    address: targetConfig.targetPhoneBTAddr,
                    isConnected: true
                )
            ]
        }
        return []
    }
    
    public func sendVendorPauseCommand() async throws -> Bool {
        guard let p = peripheral else {
            print("[ShokzDriver] Cannot send pause command: Headphone peripheral not connected.")
            return false
        }
        
        let pauseCommand = RustEngineBridge.shared.buildShokzPausePacket()
        
        if let service = p.services?.first(where: { $0.uuid == vendorServiceUUID }),
           let char = service.characteristics?.first(where: { $0.uuid == vendorWriteCharUUID }) {
            p.writeValue(pauseCommand, for: char, type: .withoutResponse)
            print("[ShokzDriver] Sent vendor pause frame to Shokz headphone over GATT 0xFC4C.")
            return true
        } else if let service = p.services?.first(where: { $0.uuid == besCoreServiceUUID }),
                  let char = service.characteristics?.first(where: { $0.uuid == besWriteCharUUID }) {
            p.writeValue(pauseCommand, for: char, type: .withoutResponse)
            print("[ShokzDriver] Sent vendor pause frame to Shokz headphone over BES GATT 03000300.")
            return true
        }
        
        print("[ShokzDriver] Cannot send pause command: No suitable write characteristic found.")
        return false
    }
    
    // MARK: - Private Scanning & Connection
    
    private func checkConnectedPeripherals() {
        guard isStarted, centralManager.state == .poweredOn else { return }
        if peripheral != nil { return }
        
        let services = [fastPairServiceUUID, vendorServiceUUID, besCoreServiceUUID]
        let connected = centralManager.retrieveConnectedPeripherals(withServices: services)
        for p in connected {
            let name = p.name ?? ""
            let idString = p.identifier.uuidString
            let matchesConfig = (targetConfig.targetHeadphoneUUID != nil && idString == targetConfig.targetHeadphoneUUID)
            let matchesName = canHandle(deviceName: name)
            if matchesConfig || matchesName {
                print("[ShokzDriver] Retrieved already-connected headphone: \(name) (\(idString))")
                self.peripheral = p
                p.delegate = self
                centralManager.connect(p, options: nil)
                return
            }
        }
    }
    
    private func startScanning() {
        guard isStarted else { return }
        checkConnectedPeripherals()
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }
    
    // MARK: - CBCentralManagerDelegate
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn && isStarted {
            checkConnectedPeripherals()
            startScanning()
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let idString = peripheral.identifier.uuidString
        
        let matchesConfig = (targetConfig.targetHeadphoneUUID != nil && idString == targetConfig.targetHeadphoneUUID)
        let matchesName = canHandle(deviceName: name)
        
        if matchesConfig || matchesName {
            print("[ShokzDriver] Found target headphone: \(name) (\(idString))")
            self.peripheral = peripheral
            central.stopScan()
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[ShokzDriver] Connected to \(peripheral.name ?? "Shokz")! Discovering services...")
        peripheral.discoverServices([fastPairServiceUUID, vendorServiceUUID, besCoreServiceUUID])
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[ShokzDriver] Disconnected from headphone: \(error?.localizedDescription ?? "clean")")
        self.peripheral = nil
        if isStarted {
            startScanning()
        }
    }
    
    // MARK: - CBPeripheralDelegate
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for s in services {
            if s.uuid == fastPairServiceUUID {
                peripheral.discoverCharacteristics([fastPairBatteryCharUUID], for: s)
            } else if s.uuid == vendorServiceUUID {
                peripheral.discoverCharacteristics([vendorWriteCharUUID, vendorNotifyCharUUID], for: s)
            } else if s.uuid == besCoreServiceUUID {
                peripheral.discoverCharacteristics([besWriteCharUUID, besNotifyCharUUID], for: s)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let chars = service.characteristics else { return }
        for c in chars {
            if c.uuid == fastPairBatteryCharUUID {
                peripheral.readValue(for: c)
                peripheral.setNotifyValue(true, for: c)
            } else if c.uuid == vendorNotifyCharUUID || c.uuid == besNotifyCharUUID {
                peripheral.setNotifyValue(true, for: c)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        
        if characteristic.uuid == fastPairBatteryCharUUID {
            parseFastPairBattery(data: data)
        }
    }
    
    // MARK: - Battery Parsing
    
    private func parseFastPairBattery(data: Data) {
        if let battery = RustEngineBridge.shared.parseShokzBattery(data: data) {
            self.currentBattery = battery
            self.onBatteryChanged?(battery)
            return
        }
        
        // Fast pair battery format fallback
        guard data.count >= 3 else { return }
        
        func decodeLevel(_ byte: UInt8) -> Int? {
            let val = Int(byte & 0x7F)
            return (val <= 100) ? val : nil
        }
        
        let left = decodeLevel(data[0])
        let right = decodeLevel(data[1])
        let caseLevel = decodeLevel(data[2])
        let isCharging = (data[0] & 0x80 != 0) || (data[1] & 0x80 != 0) || (data[2] & 0x80 != 0)
        
        let battery = HeadphoneBattery(
            left: left,
            right: right,
            caseLevel: caseLevel,
            isCharging: isCharging
        )
        
        self.currentBattery = battery
        self.onBatteryChanged?(battery)
    }
}
#else
import Foundation

/// Fallback stub for non-macOS environments (Linux/Windows).
public final class ShokzDriver: HeadphoneDriver, @unchecked Sendable {
    public let driverId = "driver.shokz.opendots"
    public let brandName = "Shokz"
    public var onBatteryChanged: (@Sendable (HeadphoneBattery) -> Void)?
    public var onPairedDevicesChanged: (@Sendable ([PairedDeviceInfo]) -> Void)?
    
    public init(config: AppConfig = .load()) {}
    public func canHandle(deviceName: String) -> Bool {
        let lower = deviceName.lowercased()
        return lower.contains("shokz") || lower.contains("opendots") || lower.contains("openfit") || lower.contains("openrun")
    }
    public func start() {}
    public func stop() {}
    public func getBatteryStatus() -> HeadphoneBattery? { return nil }
    public func queryPairedDevices() async throws -> [PairedDeviceInfo] { return [] }
    public func sendVendorPauseCommand() async throws -> Bool { return false }
}
#endif

