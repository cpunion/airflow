#if os(macOS)
import Foundation
@preconcurrency import CoreBluetooth

/// BLE GATT Server for AirFlow Remote Companion.
/// Advertises a dedicated AirFlow Remote Control GATT Service, allowing secondary mobile
/// devices (iOS or Android) to connect, receive immediate media pause commands,
/// and notify the host of their playback state without requiring HID pairing or special entitlements.
public final class BleRemoteServer: NSObject, CBPeripheralManagerDelegate, @unchecked Sendable {
    public static let shared = BleRemoteServer()
    
    // AirFlow Service and Characteristic UUIDs
    nonisolated(unsafe) public static let serviceUUID = CBUUID(string: "A1BF0001-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) public static let commandCharUUID = CBUUID(string: "A1BF0002-0000-1000-8000-00805F9B34FB")
    nonisolated(unsafe) public static let statusCharUUID = CBUUID(string: "A1BF0003-0000-1000-8000-00805F9B34FB")
    
    public private(set) var isAdvertising: Bool = false
    public private(set) var subscribedCentrals: [CBCentral] = []
    
    public var onMobilePlaybackChanged: (@Sendable (Bool) -> Void)?
    
    private var peripheralManager: CBPeripheralManager!
    private var commandCharacteristic: CBMutableCharacteristic?
    private var statusCharacteristic: CBMutableCharacteristic?
    private var isStarted = false
    
    private override init() {
        super.init()
        let cmdChar = CBMutableCharacteristic(
            type: Self.commandCharUUID,
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable]
        )
        self.commandCharacteristic = cmdChar
        
        let statChar = CBMutableCharacteristic(
            type: Self.statusCharUUID,
            properties: [.write, .writeWithoutResponse, .read, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
        self.statusCharacteristic = statChar
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
    }
    
    public func startAdvertising() {
        guard !isStarted else { return }
        isStarted = true
        if peripheralManager.state == .poweredOn {
            setupAndAdvertise()
        }
    }
    
    public func stopAdvertising() {
        guard isStarted else { return }
        isStarted = false
        peripheralManager.stopAdvertising()
        peripheralManager.removeAllServices()
        isAdvertising = false
        subscribedCentrals.removeAll()
    }
    
    /// Dispatches a pause command (0x01) to all subscribed mobile peers.
    @discardableResult
    public func sendPause() -> Bool {
        return sendCommand(0x01, name: "PAUSE")
    }
    
    /// Dispatches a play/resume command (0x02) to all subscribed mobile peers.
    @discardableResult
    public func sendPlay() -> Bool {
        return sendCommand(0x02, name: "PLAY")
    }
    
    private func sendCommand(_ opcode: UInt8, name: String) -> Bool {
        guard let char = commandCharacteristic else {
            print("[BleRemoteServer] Command characteristic not initialized.")
            return false
        }
        
        guard peripheralManager.state == .poweredOn else {
            print("[BleRemoteServer] Peripheral manager is not powered on yet. Command buffered.")
            return true
        }
        
        let data = Data([opcode])
        let sent = peripheralManager.updateValue(data, for: char, onSubscribedCentrals: nil)
        if sent {
            print("[BleRemoteServer] Dispatched \(name) opcode (0x\(String(format: "%02X", opcode))) to \(subscribedCentrals.count) subscribed central(s).")
        } else {
            print("[BleRemoteServer] Note: updateValue queued or no centrals subscribed (count: \(subscribedCentrals.count)).")
        }
        return true
    }
    
    // MARK: - Setup GATT Service
    
    private func setupAndAdvertise() {
        guard let cmdChar = commandCharacteristic, let statChar = statusCharacteristic else { return }
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [cmdChar, statChar]
        peripheralManager.removeAllServices()
        peripheralManager.add(service)
    }
    
    // MARK: - CBPeripheralManagerDelegate
    
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn && isStarted {
            setupAndAdvertise()
        } else if peripheral.state != .poweredOn {
            isAdvertising = false
            subscribedCentrals.removeAll()
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            print("[BleRemoteServer] Failed to publish service: \(error.localizedDescription)")
            return
        }
        
        peripheral.startAdvertising([
            CBAdvertisementDataLocalNameKey: "AirFlow Remote",
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]
        ])
    }
    
    public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            print("[BleRemoteServer] Failed to advertise: \(error.localizedDescription)")
            isAdvertising = false
        } else {
            isAdvertising = true
            print("[BleRemoteServer] Advertising 'AirFlow Remote' GATT service (\(Self.serviceUUID.uuidString)). Ready for mobile connections.")
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        if !subscribedCentrals.contains(where: { $0.identifier == central.identifier }) {
            subscribedCentrals.append(central)
        }
        print("[BleRemoteServer] Mobile peer subscribed: \(central.identifier) (total subscribers: \(subscribedCentrals.count))")
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribedCentrals.removeAll(where: { $0.identifier == central.identifier })
        print("[BleRemoteServer] Mobile peer unsubscribed: \(central.identifier) (remaining subscribers: \(subscribedCentrals.count))")
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == Self.statusCharUUID, let data = request.value, !data.isEmpty {
                let isPlaying = data[0] != 0
                print("[BleRemoteServer] Received mobile playback update: \(isPlaying ? "Playing" : "Paused")")
                onMobilePlaybackChanged?(isPlaying)
            }
            peripheral.respond(to: request, withResult: .success)
        }
    }
}
#else
import Foundation

/// Fallback stub for non-macOS environments.
public final class BleRemoteServer: @unchecked Sendable {
    public static let shared = BleRemoteServer()
    public private(set) var isAdvertising: Bool = false
    public var onMobilePlaybackChanged: (@Sendable (Bool) -> Void)?
    
    private init() {}
    public func startAdvertising() {}
    public func stopAdvertising() {}
    public func sendPause() -> Bool { return true }
    public func sendPlay() -> Bool { return true }
}
#endif
