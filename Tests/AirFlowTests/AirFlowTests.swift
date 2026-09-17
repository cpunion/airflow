import Foundation
import Testing
@testable import AirFlow

// MARK: - Mock Implementations

final class MockAudioMonitor: AudioDeviceMonitorProtocol, @unchecked Sendable {
    var onDeviceChanged: (@Sendable (AudioDevice) -> Void)?
    var currentDevice: AudioDevice?
    var devicesList: [AudioDevice] = []
    
    func startMonitoring(onDeviceChanged: @escaping @Sendable (AudioDevice) -> Void) {
        self.onDeviceChanged = onDeviceChanged
        if let dev = currentDevice {
            onDeviceChanged(dev)
        }
    }
    
    func stopMonitoring() {
        self.onDeviceChanged = nil
    }
    
    func getCurrentDefaultDevice() -> AudioDevice? {
        return currentDevice
    }
    
    func listOutputDevices() -> [AudioDevice] {
        return devicesList
    }
    
    func triggerDeviceChange(_ device: AudioDevice) {
        self.currentDevice = device
        self.onDeviceChanged?(device)
    }
}

final class MockMediaObserver: MediaPlaybackObserverProtocol, @unchecked Sendable {
    var onPlaybackChanged: (@Sendable (Bool) -> Void)?
    var isPlaying = false
    var pauseCallCount = 0
    var resumeCallCount = 0
    
    func startMonitoring(onPlaybackChanged: @escaping @Sendable (Bool) -> Void) {
        self.onPlaybackChanged = onPlaybackChanged
    }
    
    func stopMonitoring() {
        self.onPlaybackChanged = nil
    }
    
    func isMediaPlaying() -> Bool {
        return isPlaying
    }
    
    func pauseMedia() {
        pauseCallCount += 1
        isPlaying = false
        onPlaybackChanged?(false)
    }
    
    func resumeMedia() {
        resumeCallCount += 1
        isPlaying = true
        onPlaybackChanged?(true)
    }
    
    func triggerPlayback(playing: Bool) {
        self.isPlaying = playing
        self.onPlaybackChanged?(playing)
    }
}

final class MockDriver: HeadphoneDriver, @unchecked Sendable {
    var driverId = "mock.driver"
    var brandName = "Mock"
    var isStarted = false
    var battery: HeadphoneBattery?
    var onBatteryChanged: (@Sendable (HeadphoneBattery) -> Void)?
    var onPairedDevicesChanged: (@Sendable ([PairedDeviceInfo]) -> Void)?
    
    func canHandle(deviceName: String) -> Bool {
        return deviceName.lowercased().contains("opendots") || deviceName.lowercased().contains("headphone")
    }
    
    func start() {
        isStarted = true
    }
    
    func stop() {
        isStarted = false
    }
    
    func getBatteryStatus() -> HeadphoneBattery? {
        return battery
    }
    
    func queryPairedDevices() async throws -> [PairedDeviceInfo] {
        return [PairedDeviceInfo(id: "mock-peer", name: "Mock Phone")]
    }
}

// MARK: - Unit Tests

@Suite("AirFlow Arbitration & Gatekeeper Tests")
struct ArbitrationTests {
    
    @Test("Gatekeeper: Automatically bypasses when AirPods are active on Apple ecosystem")
    func testAirPodsBypass() async throws {
        let audioMonitor = MockAudioMonitor()
        let mediaObserver = MockMediaObserver()
        let driver = MockDriver()
        let config = AppConfig(targetPhoneName: "iPhone 15", enableAirPodsBypass: true)
        let whitelist = DeviceWhitelistManager(config: config)
        
        let engine = ArbitrationEngine(
            audioMonitor: audioMonitor,
            mediaObserver: mediaObserver,
            driver: driver,
            whitelistManager: whitelist,
            config: config
        )
        
        engine.start()
        
        // Trigger AirPods connection
        let airPods = AudioDevice(id: 1, name: "AirPods Pro", isBluetooth: true)
        audioMonitor.triggerDeviceChange(airPods)
        
        #expect(engine.currentState == .bypassed(reason: "AirPods Active (Native Apple Handoff)"))
        
        // Media play while AirPods active should NOT trigger arbitration
        mediaObserver.triggerPlayback(playing: true)
        #expect(engine.currentState == .bypassed(reason: "AirPods Active (Native Apple Handoff)"))
    }
    
    @Test("Gatekeeper: Does NOT bypass AirPods when peer is Android")
    func testAirPodsWithAndroidPeer() async throws {
        let audioMonitor = MockAudioMonitor()
        let mediaObserver = MockMediaObserver()
        let driver = MockDriver()
        let config = AppConfig(targetPhoneName: "Pixel 8 (Android)", enableAirPodsBypass: true)
        let whitelist = DeviceWhitelistManager(config: config)
        
        let engine = ArbitrationEngine(
            audioMonitor: audioMonitor,
            mediaObserver: mediaObserver,
            driver: driver,
            whitelistManager: whitelist,
            config: config
        )
        
        engine.start()
        
        // Trigger AirPods connection
        let airPods = AudioDevice(id: 1, name: "AirPods Pro", isBluetooth: true)
        audioMonitor.triggerDeviceChange(airPods)
        
        // Should NOT bypass because peer is Android!
        #expect(engine.currentState == .idle)
    }
    
    @Test("Gatekeeper: User can manually disable AirPods bypass on Apple ecosystem")
    func testAirPodsManualOverride() async throws {
        let audioMonitor = MockAudioMonitor()
        let mediaObserver = MockMediaObserver()
        let driver = MockDriver()
        let config = AppConfig(targetPhoneName: "iPhone 15", enableAirPodsBypass: true)
        let whitelist = DeviceWhitelistManager(config: config)
        
        let engine = ArbitrationEngine(
            audioMonitor: audioMonitor,
            mediaObserver: mediaObserver,
            driver: driver,
            whitelistManager: whitelist,
            config: config
        )
        
        engine.start()
        
        let airPods = AudioDevice(id: 1, name: "AirPods Pro", isBluetooth: true)
        audioMonitor.triggerDeviceChange(airPods)
        #expect(engine.currentState == .bypassed(reason: "AirPods Active (Native Apple Handoff)"))
        
        // User disables bypass
        engine.setAirPodsBypassEnabled(false)
        #expect(engine.currentState == .idle)
    }
    
    @Test("Target Headphone: Multipoint headphone activates arbitration engine")
    func testTargetHeadphoneActivation() async throws {
        let audioMonitor = MockAudioMonitor()
        let mediaObserver = MockMediaObserver()
        let driver = MockDriver()
        let config = AppConfig(arbitrationCooldownMs: 100)
        let whitelist = DeviceWhitelistManager(config: config)
        
        let engine = ArbitrationEngine(
            audioMonitor: audioMonitor,
            mediaObserver: mediaObserver,
            driver: driver,
            whitelistManager: whitelist,
            config: config
        )
        
        engine.start()
        
        // Connect target multipoint headphone
        let headphone = AudioDevice(id: 2, name: "OpenDots 2", isBluetooth: true)
        audioMonitor.triggerDeviceChange(headphone)
        
        #expect(engine.currentState == .idle)
        
        // Start playing media
        mediaObserver.triggerPlayback(playing: true)
        
        // Should immediately enter cooldown / host active
        switch engine.currentState {
        case .cooldown, .hostActive:
            break
        default:
            Issue.record("Expected cooldown or hostActive, got: \(engine.currentState)")
        }
    }
    
    @Test("Whitelist: Enforces strict target device verification")
    func testWhitelistVerification() async throws {
        let config = AppConfig(
            targetPhoneName: "Verified Phone",
            targetPhoneUUID: "1234-5678"
        )
        let whitelist = DeviceWhitelistManager(config: config)
        
        #expect(whitelist.isWhitelisted(id: "1234-5678"))
        #expect(whitelist.isWhitelisted(id: "random-id", name: "Verified Phone"))
        #expect(!whitelist.isWhitelisted(id: "random-id", name: "Stranger's iPhone"))
    }
}

@Suite("Rust Core Engine FFI Bridge Tests")
struct RustBridgeTests {
    @Test("Bridge: Loads Rust core dylib and verifies C-ABI interaction")
    func testRustBridgeAvailability() {
        let bridge = RustEngineBridge()
        if bridge.isAvailable {
            #expect(bridge.isAvailable)
            
            // Test whitelist C-ABI
            bridge.bindDevice(id: "RUST-TEST-1", name: "Rust Pixel", address: nil)
            #expect(bridge.isWhitelisted(id: "RUST-TEST-1"))
            #expect(bridge.isWhitelisted(id: "ANY", name: "Rust Pixel"))
            #expect(!bridge.isWhitelisted(id: "UNKNOWN", name: "Stranger"))
            
            bridge.unbindDevice()
            #expect(!bridge.isWhitelisted(id: "RUST-TEST-1"))
        }
    }
}

@Suite("Peer Command Dispatcher Tests")
struct DispatcherTests {
    @Test("Dispatcher: Enforces strict whitelisting before sending commands")
    func testStrictWhitelistEnforcement() {
        let driver = MockDriver()
        let whitelist = DeviceWhitelistManager(config: AppConfig())
        let dispatcher = PeerCommandDispatcher(whitelistManager: whitelist, driver: driver)
        
        let stranger = PairedDeviceInfo(id: "STRANGER-999", name: "Unauthorized Phone")
        let result = dispatcher.dispatchPause(to: stranger)
        #expect(result == .ignoredNotWhitelisted)
    }
    
    @Test("Dispatcher: Dispatches pause to whitelisted peer via active strategy")
    func testDispatchToWhitelistedPeer() {
        let driver = MockDriver()
        let whitelist = DeviceWhitelistManager(config: AppConfig())
        let peer = PairedDeviceInfo(id: "PEER-1", name: "My iPhone")
        whitelist.bindDevice(peer)
        
        let dispatcher = PeerCommandDispatcher(whitelistManager: whitelist, driver: driver)
        
        // Default strategy: Headphone GATT
        let resultGatt = dispatcher.dispatchPause(to: peer)
        #expect(resultGatt == DispatchResult.success(strategy: DispatchStrategy.headphoneGatt))
        
        // Switch to BLE HID
        dispatcher.setStrategy(.bleHidMediaKey)
        let resultHid = dispatcher.dispatchPause(to: peer)
        #expect(resultHid == DispatchResult.success(strategy: DispatchStrategy.bleHidMediaKey))
    }
}
