#if os(macOS)
import Foundation
import CoreAudio

/// Implementation of AudioDeviceMonitorProtocol for macOS using CoreAudio.
/// Responsible for listening to default audio output changes and enforcing Gatekeeper bypass for AirPods.
public final class CoreAudioMonitor: AudioDeviceMonitorProtocol, @unchecked Sendable {
    private var isRunning = false
    private var callback: (@Sendable (AudioDevice) -> Void)?
    private var propertyListenerBlock: AudioObjectPropertyListenerBlock?
    
    public init() {}
    
    deinit {
        stopMonitoring()
    }
    
    public func startMonitoring(onDeviceChanged: @escaping @Sendable (AudioDevice) -> Void) {
        self.callback = onDeviceChanged
        self.isRunning = true
        
        // Notify immediately with the initial device
        if let current = getCurrentDefaultDevice() {
            onDeviceChanged(current)
        }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self, self.isRunning else { return }
            if let device = self.getCurrentDefaultDevice() {
                self.callback?(device)
            }
        }
        
        self.propertyListenerBlock = block
        
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        
        if status != noErr {
            print("[CoreAudioMonitor] Warning: Failed to add property listener (status: \(status))")
        }
    }
    
    public func stopMonitoring() {
        guard isRunning else { return }
        isRunning = false
        
        if let block = propertyListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
            propertyListenerBlock = nil
        }
    }
    
    public func getCurrentDefaultDevice() -> AudioDevice? {
        var deviceID = AudioDeviceID(0)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceID
        )
        
        guard status == noErr, deviceID != 0 else { return nil }
        return getDevice(by: deviceID)
    }
    
    public func listOutputDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize: UInt32 = 0
        
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        
        guard status == noErr, propertySize > 0 else { return [] }
        
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        let fetchStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )
        
        guard fetchStatus == noErr else { return [] }
        
        var outputDevices: [AudioDevice] = []
        for id in deviceIDs {
            if hasOutputChannels(deviceID: id), let device = getDevice(by: id) {
                outputDevices.append(device)
            }
        }
        return outputDevices
    }
    
    @discardableResult
    public func setDefaultOutputDevice(deviceID: UInt32) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var targetID = AudioDeviceID(deviceID)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &targetID
        )
        if status == noErr {
            print("[CoreAudioMonitor] Successfully switched default output device to ID: \(deviceID)")
            if let dev = getDevice(by: targetID) {
                callback?(dev)
            }
            return true
        } else {
            print("[CoreAudioMonitor] Failed to set default output device ID \(deviceID), status: \(status)")
            return false
        }
    }
    
    // MARK: - Private Helpers
    
    private func getDevice(by id: AudioDeviceID) -> AudioDevice? {
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfName: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        
        let nameStatus = AudioObjectGetPropertyData(
            id,
            &nameAddress,
            0,
            nil,
            &nameSize,
            &cfName
        )
        
        guard nameStatus == noErr, let name = cfName?.takeRetainedValue() as String? else { return nil }
        
        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType: UInt32 = 0
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        
        _ = AudioObjectGetPropertyData(
            id,
            &transportAddress,
            0,
            nil,
            &transportSize,
            &transportType
        )
        
        let isBluetooth = (transportType == kAudioDeviceTransportTypeBluetooth || transportType == kAudioDeviceTransportTypeBluetoothLE)
        return AudioDevice(id: id, name: name, isBluetooth: isBluetooth)
    }
    
    private func hasOutputChannels(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propertySize)
        guard status == noErr, propertySize > 0 else { return false }
        
        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(propertySize))
        defer { bufferListPointer.deallocate() }
        
        let readStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, bufferListPointer)
        guard readStatus == noErr else { return false }
        
        let bufferList = bufferListPointer.pointee
        return bufferList.mNumberBuffers > 0
    }
}
#else
import Foundation

/// Fallback stub for non-macOS environments (Linux/Windows).
public final class CoreAudioMonitor: AudioDeviceMonitorProtocol, @unchecked Sendable {
    public init() {}
    public func startMonitoring(onDeviceChanged: @escaping @Sendable (AudioDevice) -> Void) {}
    public func stopMonitoring() {}
    public func getCurrentDefaultDevice() -> AudioDevice? { return nil }
    public func listOutputDevices() -> [AudioDevice] { return [] }
    @discardableResult
    public func setDefaultOutputDevice(deviceID: UInt32) -> Bool { return false }
}
#endif

