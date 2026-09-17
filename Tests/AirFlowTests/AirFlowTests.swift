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
    
    @discardableResult
    func setDefaultOutputDevice(deviceID: UInt32) -> Bool {
        if let dev = devicesList.first(where: { $0.id == deviceID }) {
            self.currentDevice = dev
            self.onDeviceChanged?(dev)
            return true
        }
        return false
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
    
    var vendorPauseCallCount = 0
    func sendVendorPauseCommand() async throws -> Bool {
        vendorPauseCallCount += 1
        return true
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
        
        // Switch to BLE HID / Remote
        dispatcher.setStrategy(.bleHidMediaKey)
        let resultHid = dispatcher.dispatchPause(to: peer)
        #expect(resultHid == DispatchResult.success(strategy: DispatchStrategy.bleHidMediaKey))
        
        // Switch to BLE Companion Remote
        dispatcher.setStrategy(.bleRemote)
        let resultBle = dispatcher.dispatchPause(to: peer)
        #expect(resultBle == DispatchResult.success(strategy: DispatchStrategy.bleRemote))
    }
    
    @Test("Dispatcher: Headphone GATT strategy triggers driver pause command")
    func testDispatchVendorGattInvokesDriver() async throws {
        let driver = MockDriver()
        let whitelist = DeviceWhitelistManager(config: AppConfig())
        let peer = PairedDeviceInfo(id: "PEER-GATT", name: "Target Phone")
        whitelist.bindDevice(peer)
        
        let dispatcher = PeerCommandDispatcher(whitelistManager: whitelist, driver: driver)
        dispatcher.setStrategy(.headphoneGatt)
        
        let result = dispatcher.dispatchPause(to: peer)
        #expect(result == DispatchResult.success(strategy: .headphoneGatt))
        
        // Wait for async task to invoke driver
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(driver.vendorPauseCallCount == 1)
    }
}

@Suite("macOS Audio Routing Tests")
struct AudioRoutingTests {
    @Test("Audio Routing: Switches default output device and triggers notification")
    func testAudioOutputDeviceSwitching() {
        let audioMonitor = MockAudioMonitor()
        let internalSpeaker = AudioDevice(id: 10, name: "MacBook Pro Speakers", isBluetooth: false)
        let headphone = AudioDevice(id: 20, name: "Shokz OpenDots", isBluetooth: true)
        
        audioMonitor.devicesList = [internalSpeaker, headphone]
        audioMonitor.currentDevice = internalSpeaker
        
        final class DeviceBox: @unchecked Sendable {
            var device: AudioDevice?
        }
        let box = DeviceBox()
        audioMonitor.startMonitoring { dev in
            box.device = dev
        }
        
        #expect(audioMonitor.getCurrentDefaultDevice()?.id == 10)
        
        // Switch to headphone
        let success = audioMonitor.setDefaultOutputDevice(deviceID: 20)
        #expect(success)
        #expect(audioMonitor.getCurrentDefaultDevice()?.id == 20)
        #expect(box.device?.id == 20)
    }
}

@Suite("Platform Features & Companion Tests")
struct PlatformFeatureTests {
    @Test("Companion: BleRemoteServer starts, exposes status, and provides pause API")
    func testBleRemoteServer() {
        let server = BleRemoteServer.shared
        server.startAdvertising()
        let pauseSent = server.sendPause()
        #expect(pauseSent)
        let playSent = server.sendPlay()
        #expect(playSent)
        server.stopAdvertising()
    }
    
    @Test("macOS Helper: LaunchAtLogin helper accessibility check")
    func testLaunchAtLoginHelper() {
        let helper = LaunchAtLoginHelper.shared
        _ = helper.isAvailable
        _ = helper.isEnabled
    }
}

@Suite("Universal Driver & Registry Tests")
struct UniversalDriverTests {
    @Test("Driver Registry: Dynamically selects matching brand driver")
    func testCompositeDriverSelection() {
        let shokz = ShokzDriver(config: AppConfig())
        let airpods = AirPodsDriver()
        let sony = SonyDriver()
        let generic = GenericDriver()
        let composite = CompositeHeadphoneDriver(drivers: [shokz, airpods, sony, generic])
        
        #expect(composite.canHandle(deviceName: "Shokz OpenDots 2"))
        #expect(composite.canHandle(deviceName: "AirPods Pro"))
        #expect(composite.canHandle(deviceName: "Sony WH-1000XM5"))
        #expect(composite.canHandle(deviceName: "Bose QuietComfort"))
        
        composite.selectDriver(for: "AirPods Max")
        #expect(composite.brandName == "Apple AirPods")
        
        composite.selectDriver(for: "Sony WH-1000XM4")
        #expect(composite.brandName == "Sony MDR")
        
        composite.selectDriver(for: "OpenDots 2")
        #expect(composite.brandName == "Shokz")
    }
}

@Suite("Hardware Parity & Wire Codecs Tests")
struct HardwareWireCodecTests {
    @Test("Wire Codecs: Shokz pause packet framing")
    func testShokzPauseFraming() {
        let packet = RustEngineBridge.shared.buildShokzPausePacket()
        #expect(packet.count == 5)
        #expect(packet[0] == 0x05)
        #expect(packet[1] == 0x5A)
        #expect(packet[2] == 0x02)
        #expect(packet[3] == 0x01)
        #expect(packet[4] == 0x00)
    }
    
    @Test("Wire Codecs: Shokz battery packet decoding")
    func testShokzBatteryDecoding() {
        let data = Data([85 | 0x80, 90, 100])
        let battery = RustEngineBridge.shared.parseShokzBattery(data: data)
        #expect(battery != nil)
        #expect(battery?.left == 85)
        #expect(battery?.right == 90)
        #expect(battery?.caseLevel == 100)
    }
    
    @Test("Wire Codecs: AirPods AAP ANC packet builder")
    func testAirPodsAncBuilder() {
        let packet = RustEngineBridge.shared.buildAirPodsAncPacket(mode: 0x02)
        #expect(packet.count == 4)
        #expect(packet[0] == 0x02) // Length LE
        #expect(packet[2] == 0x0D) // Opcode ANC Control
        #expect(packet[3] == 0x02) // Noise Cancellation Mode
    }
    
    @Test("Wire Codecs: AirPods AAP in-ear detection decoding")
    func testAirPodsInEarDecoding() {
        // [Length LE (2 bytes), Opcode (0x01), Left (0x01), Right (0x01)]
        let data = Data([0x02, 0x00, 0x01, 0x01, 0x01])
        let inEar = RustEngineBridge.shared.parseAirPodsInEar(data: data)
        #expect(inEar != nil)
        #expect(inEar?.primary == 1)
        #expect(inEar?.secondary == 1)
    }
    
    @Test("Wire Codecs: Sony MDR switch audio packet builder")
    func testSonySwitchAudioBuilder() {
        let packet = RustEngineBridge.shared.buildSonySwitchAudioPacket(targetSlot: 0x01)
        #expect(packet.count >= 10)
        #expect(packet[0] == 0x0C) // Sony MDR Frame Start (0x0C)
    }
    
    @Test("Wire Codecs: Generic singlepoint roaming coordination")
    func testGenericRoamingCoordination() {
        let canRoam = RustEngineBridge.shared.genericCanRoam(current: "MacBook", target: "iPhone")
        #expect(canRoam == true)
        
        let sameRoam = RustEngineBridge.shared.genericCanRoam(current: "MacBook", target: "MacBook")
        #expect(sameRoam == false)
    }
}

