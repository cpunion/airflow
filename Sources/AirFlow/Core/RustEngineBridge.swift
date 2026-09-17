import Foundation

#if canImport(Darwin)
import Darwin
#elseif os(Linux)
import Glibc
#elseif os(Windows)
import WinSDK
#endif

/// C-compatible state codes matching `AirFlowStateCode` in `airflow_core.h`.
public enum RustStateCode: UInt32 {
    case idle = 0
    case bypassed = 1
    case hostActive = 2
    case peerActive = 3
    case cooldown = 4
}

/// Dynamically bridges the Swift frontend to `airflow-core` (Rust C-ABI library).
/// If `libairflow_core` (or `airflow_core.dll` on Windows) is available, all arbitration decisions are delegated to the Rust engine.
public final class RustEngineBridge: @unchecked Sendable {
    #if os(Windows)
    private var dylibHandle: HMODULE?
    #else
    private var dylibHandle: UnsafeMutableRawPointer?
    #endif
    
    private var engineHandle: OpaquePointer?
    
    public static let shared = RustEngineBridge()

    private typealias CreateFn = @convention(c) () -> OpaquePointer?
    private typealias DestroyFn = @convention(c) (OpaquePointer?) -> Void
    private typealias AudioChangedFn = @convention(c) (OpaquePointer?, UInt32, UnsafePointer<CChar>?, Bool) -> Void
    private typealias MediaChangedFn = @convention(c) (OpaquePointer?, Bool) -> Void
    private typealias SetHandoffFn = @convention(c) (OpaquePointer?, Bool) -> Void
    private typealias SetAirPodsBypassFn = @convention(c) (OpaquePointer?, Bool) -> Void
    private typealias StateCallbackC = @convention(c) (UInt32, UnsafePointer<CChar>?, UInt64, UnsafeMutableRawPointer?) -> Void
    private typealias PauseCallbackC = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void
    private typealias RegisterStateCbFn = @convention(c) (OpaquePointer?, StateCallbackC, UnsafeMutableRawPointer?) -> Void
    private typealias RegisterPauseCbFn = @convention(c) (OpaquePointer?, PauseCallbackC, UnsafeMutableRawPointer?) -> Void
    private typealias WhitelistBindFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void
    private typealias WhitelistUnbindFn = @convention(c) (OpaquePointer?) -> Void
    private typealias WhitelistAllowedFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Bool
    
    // Wire Codec Function Pointers
    private typealias ShokzGetPauseFn = @convention(c) (UnsafeMutablePointer<Int>?) -> UnsafePointer<UInt8>?
    private typealias ShokzParseBatteryFn = @convention(c) (UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<CBool>?) -> CBool
    private typealias AirPodsBuildAncFn = @convention(c) (UInt8, UnsafeMutablePointer<UInt8>?, Int) -> Int
    private typealias AirPodsParseInEarFn = @convention(c) (UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<CBool>?, UnsafeMutablePointer<CBool>?) -> CBool
    private typealias AirPodsParseBatteryFn = @convention(c) (UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<CBool>?) -> CBool
    private typealias SonyBuildSwitchAudioFn = @convention(c) (UInt8, UnsafePointer<UInt8>?, UnsafeMutablePointer<UInt8>?, Int) -> Int
    private typealias SonyParseBatteryFn = @convention(c) (UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<CBool>?) -> CBool
    private typealias GenericCanRoamFn = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> CBool
    
    private var fnCreate: CreateFn?
    private var fnDestroy: DestroyFn?
    private var fnAudioChanged: AudioChangedFn?
    private var fnMediaChanged: MediaChangedFn?
    private var fnSetHandoff: SetHandoffFn?
    private var fnSetAirPodsBypass: SetAirPodsBypassFn?
    private var fnRegisterStateCb: RegisterStateCbFn?
    private var fnRegisterPauseCb: RegisterPauseCbFn?
    private var fnWhitelistBind: WhitelistBindFn?
    private var fnWhitelistUnbind: WhitelistUnbindFn?
    private var fnWhitelistAllowed: WhitelistAllowedFn?
    
    private var fnShokzGetPause: ShokzGetPauseFn?
    private var fnShokzParseBattery: ShokzParseBatteryFn?
    private var fnAirPodsBuildAnc: AirPodsBuildAncFn?
    private var fnAirPodsParseInEar: AirPodsParseInEarFn?
    private var fnAirPodsParseBattery: AirPodsParseBatteryFn?
    private var fnSonyBuildSwitchAudio: SonyBuildSwitchAudioFn?
    private var fnSonyParseBattery: SonyParseBatteryFn?
    private var fnGenericCanRoam: GenericCanRoamFn?
    
    public var onStateChanged: (@Sendable (EngineState) -> Void)?
    public var onPausePeerRequested: (@Sendable (_ id: String, _ name: String) -> Void)?
    
    public var isAvailable: Bool {
        return engineHandle != nil
    }
    
    public init(customDylibPath: String? = nil) {
        loadDylib(customPath: customDylibPath)
    }
    
    deinit {
        if let engine = engineHandle, let destroy = fnDestroy {
            destroy(engine)
        }
        #if os(Windows)
        if let dylib = dylibHandle {
            FreeLibrary(dylib)
        }
        #else
        if let dylib = dylibHandle {
            dlclose(dylib)
        }
        #endif
    }
    
    private func loadDylib(customPath: String?) {
        #if os(Windows)
        let candidatePaths: [String] = [
            customPath,
            "target/release/airflow_core.dll",
            "target/debug/airflow_core.dll",
            "airflow_core.dll"
        ].compactMap { $0 }
        
        for path in candidatePaths {
            if FileManager.default.fileExists(atPath: path) {
                let handle = path.withCString { LoadLibraryA($0) }
                if let handle = handle {
                    self.dylibHandle = handle
                    print("[RustEngineBridge] Successfully loaded Rust core from: \(path)")
                    bindSymbols()
                    break
                }
            }
        }
        
        if dylibHandle == nil {
            let handle = "airflow_core.dll".withCString { LoadLibraryA($0) }
            if let handle = handle {
                self.dylibHandle = handle
                print("[RustEngineBridge] Successfully loaded Rust core via LoadLibrary search path.")
                bindSymbols()
            }
        }
        #else
        let candidatePaths: [String] = [
            customPath,
            Bundle.main.sharedFrameworksPath.map { "\($0)/libairflow_core.dylib" },
            "target/release/libairflow_core.dylib",
            "target/debug/libairflow_core.dylib",
            "target/release/libairflow_core.so",
            "target/debug/libairflow_core.so",
            "/usr/local/lib/libairflow_core.dylib",
            "/usr/local/lib/libairflow_core.so",
            "libairflow_core.dylib",
            "libairflow_core.so"
        ].compactMap { $0 }
        
        for path in candidatePaths {
            if FileManager.default.fileExists(atPath: path) {
                if let handle = dlopen(path, RTLD_NOW) {
                    self.dylibHandle = handle
                    print("[RustEngineBridge] Successfully loaded Rust core from: \(path)")
                    bindSymbols()
                    break
                }
            }
        }
        
        if dylibHandle == nil {
            let fallbackName = "libairflow_core.dylib"
            if let handle = dlopen(fallbackName, RTLD_NOW) {
                self.dylibHandle = handle
                print("[RustEngineBridge] Successfully loaded Rust core via dlopen search path.")
                bindSymbols()
            }
        }
        #endif
    }
    
    private func bindSymbols() {
        #if os(Windows)
        guard let dylib = dylibHandle else { return }
        #else
        guard let dylib = dylibHandle else { return }
        #endif
        
        fnCreate = resolve(dylib, "airflow_engine_create")
        fnDestroy = resolve(dylib, "airflow_engine_destroy")
        fnAudioChanged = resolve(dylib, "airflow_engine_on_audio_device_changed")
        fnMediaChanged = resolve(dylib, "airflow_engine_on_media_playback_changed")
        fnSetHandoff = resolve(dylib, "airflow_engine_set_handoff_enabled")
        fnSetAirPodsBypass = resolve(dylib, "airflow_engine_set_airpods_bypass_enabled")
        fnRegisterStateCb = resolve(dylib, "airflow_engine_register_state_callback")
        fnRegisterPauseCb = resolve(dylib, "airflow_engine_register_pause_callback")
        fnWhitelistBind = resolve(dylib, "airflow_whitelist_bind_device")
        fnWhitelistUnbind = resolve(dylib, "airflow_whitelist_unbind_device")
        fnWhitelistAllowed = resolve(dylib, "airflow_whitelist_is_allowed")
        
        fnShokzGetPause = resolve(dylib, "airflow_shokz_get_pause_packet")
        fnShokzParseBattery = resolve(dylib, "airflow_shokz_parse_battery")
        fnAirPodsBuildAnc = resolve(dylib, "airflow_airpods_build_anc_command")
        fnAirPodsParseInEar = resolve(dylib, "airflow_airpods_parse_in_ear")
        fnAirPodsParseBattery = resolve(dylib, "airflow_airpods_parse_battery")
        fnSonyBuildSwitchAudio = resolve(dylib, "airflow_sony_build_switch_connection")
        fnSonyParseBattery = resolve(dylib, "airflow_sony_parse_battery")
        fnGenericCanRoam = resolve(dylib, "airflow_generic_can_roam")
        
        if let create = fnCreate {
            self.engineHandle = create()
            setupCallbacks()
        }
    }
    
    private func setupCallbacks() {
        guard let engine = engineHandle,
              let registerState = fnRegisterStateCb,
              let registerPause = fnRegisterPauseCb else { return }
        
        let bridgePtr = Unmanaged.passUnretained(self).toOpaque()
        
        let stateCallback: StateCallbackC = { code, reasonPtr, remainingMs, userData in
            guard let userData = userData else { return }
            let bridge = Unmanaged<RustEngineBridge>.fromOpaque(userData).takeUnretainedValue()
            let reason = reasonPtr.map { String(cString: $0) } ?? ""
            
            let engineState: EngineState
            switch RustStateCode(rawValue: code) {
            case .idle:
                engineState = .idle
            case .bypassed:
                engineState = .bypassed(reason: reason)
            case .hostActive:
                engineState = .hostActive
            case .peerActive:
                engineState = .peerActive
            case .cooldown:
                engineState = .cooldown(remainingMs: Int(remainingMs))
            default:
                engineState = .idle
            }
            
            bridge.onStateChanged?(engineState)
        }
        
        registerState(engine, stateCallback, bridgePtr)
        
        let pauseCallback: PauseCallbackC = { idPtr, namePtr, userData in
            guard let userData = userData else { return }
            let bridge = Unmanaged<RustEngineBridge>.fromOpaque(userData).takeUnretainedValue()
            let id = idPtr.map { String(cString: $0) } ?? ""
            let name = namePtr.map { String(cString: $0) } ?? ""
            bridge.onPausePeerRequested?(id, name)
        }
        
        registerPause(engine, pauseCallback, bridgePtr)
    }
    
    #if os(Windows)
    private func resolve<T>(_ handle: HMODULE, _ symbol: String) -> T? {
        guard let sym = symbol.withCString({ GetProcAddress(handle, $0) }) else {
            print("[RustEngineBridge] Warning: symbol '\(symbol)' not found in library.")
            return nil
        }
        return unsafeBitCast(sym, to: T.self)
    }
    #else
    private func resolve<T>(_ handle: UnsafeMutableRawPointer, _ symbol: String) -> T? {
        guard let sym = dlsym(handle, symbol) else {
            print("[RustEngineBridge] Warning: symbol '\(symbol)' not found in library.")
            return nil
        }
        return unsafeBitCast(sym, to: T.self)
    }
    #endif
    
    // MARK: - Public Engine API
    
    public func onAudioDeviceChanged(id: UInt32, name: String, isBluetooth: Bool) {
        guard let engine = engineHandle, let fn = fnAudioChanged else { return }
        name.withCString { cName in
            fn(engine, id, cName, isBluetooth)
        }
    }
    
    public func onMediaPlaybackChanged(isPlaying: Bool) {
        guard let engine = engineHandle, let fn = fnMediaChanged else { return }
        fn(engine, isPlaying)
    }
    
    public func setHandoffEnabled(_ enabled: Bool) {
        guard let engine = engineHandle, let fn = fnSetHandoff else { return }
        fn(engine, enabled)
    }
    
    public func setAirPodsBypassEnabled(_ enabled: Bool) {
        guard let engine = engineHandle, let fn = fnSetAirPodsBypass else { return }
        fn(engine, enabled)
    }
    
    public func bindDevice(id: String, name: String, address: String? = nil) {
        guard let engine = engineHandle, let fn = fnWhitelistBind else { return }
        id.withCString { cId in
            name.withCString { cName in
                if let addr = address {
                    addr.withCString { cAddr in
                        fn(engine, cId, cName, cAddr)
                    }
                } else {
                    fn(engine, cId, cName, nil)
                }
            }
        }
    }
    
    public func unbindDevice() {
        guard let engine = engineHandle, let fn = fnWhitelistUnbind else { return }
        fn(engine)
    }
    
    public func isWhitelisted(id: String, name: String? = nil) -> Bool {
        guard let engine = engineHandle, let fn = fnWhitelistAllowed else { return false }
        return id.withCString { cId in
            if let n = name {
                return n.withCString { cName in
                    fn(engine, cId, cName)
                }
            } else {
                return fn(engine, cId, nil)
            }
        }
    }
    
    // MARK: - Pluggable Hardware Wire Codecs (Hardware Parity)
    
    /// Builds vendor-specific pause command packet using Rust core or native fallback.
    public func buildShokzPausePacket() -> Data {
        if let fn = fnShokzGetPause {
            var len: Int = 0
            if let ptr = fn(&len), len > 0 {
                return Data(bytes: ptr, count: len)
            }
        }
        // Fallback: [0x05, 0x5A, 0x02, 0x01, 0x00]
        return Data([0x05, 0x5A, 0x02, 0x01, 0x00])
    }
    
    /// Parses Fast Pair battery packet using Rust core.
    public func parseShokzBattery(data: Data) -> HeadphoneBattery? {
        guard let fn = fnShokzParseBattery else {
            // Native fallback
            guard data.count >= 3 else { return nil }
            let l = Int(data[0]) & 0x7F
            let r = Int(data[1]) & 0x7F
            let c = Int(data[2]) & 0x7F
            return HeadphoneBattery(
                left: l <= 100 ? l : nil,
                right: r <= 100 ? r : nil,
                caseLevel: c <= 100 ? c : nil,
                isCharging: (data[0] & 0x80) != 0 || (data[1] & 0x80) != 0
            )
        }
        
        var left: Int32 = -1
        var right: Int32 = -1
        var caseLvl: Int32 = -1
        var charging: CBool = false
        
        let ok = data.withUnsafeBytes { rawPtr in
            guard let basePtr = rawPtr.bindMemory(to: UInt8.self).baseAddress else { return false }
            return fn(basePtr, data.count, &left, &right, &caseLvl, &charging)
        }
        
        guard ok else { return nil }
        return HeadphoneBattery(
            left: left >= 0 ? Int(left) : nil,
            right: right >= 0 ? Int(right) : nil,
            caseLevel: caseLvl >= 0 ? Int(caseLvl) : nil,
            isCharging: charging
        )
    }
    
    /// Builds Apple Accessory Protocol (AAP) ANC control packet.
    public func buildAirPodsAncPacket(mode: UInt8) -> Data {
        var buffer = [UInt8](repeating: 0, count: 16)
        if let fn = fnAirPodsBuildAnc {
            let written = fn(mode, &buffer, buffer.count)
            if written > 0 {
                return Data(buffer[0..<written])
            }
        }
        return Data([0x04, 0x00, 0x01, 0x00, mode])
    }
    
    /// Parses Apple Accessory Protocol (AAP) in-ear detection packet.
    public func parseAirPodsInEar(data: Data) -> (primary: UInt8, secondary: UInt8)? {
        guard let fn = fnAirPodsParseInEar else {
            if data.count >= 5 && data[0] == 0x01 {
                return (data[3], data[4])
            }
            return nil
        }
        var leftIn: CBool = false
        var rightIn: CBool = false
        let ok = data.withUnsafeBytes { rawPtr in
            guard let basePtr = rawPtr.bindMemory(to: UInt8.self).baseAddress else { return false }
            return fn(basePtr, data.count, &leftIn, &rightIn)
        }
        guard ok else { return nil }
        return (leftIn ? 1 : 0, rightIn ? 1 : 0)
    }
    
    /// Parses Apple Accessory Protocol (AAP) battery packet.
    public func parseAirPodsBattery(data: Data) -> HeadphoneBattery? {
        guard let fn = fnAirPodsParseBattery else {
            if data.count >= 6 && data[0] == 0x04 {
                let l = Int(data[3])
                let r = Int(data[4])
                let c = Int(data[5])
                return HeadphoneBattery(
                    left: l <= 100 ? l : nil,
                    right: r <= 100 ? r : nil,
                    caseLevel: c <= 100 ? c : nil,
                    isCharging: false
                )
            }
            return nil
        }
        var left: Int32 = -1
        var right: Int32 = -1
        var caseLvl: Int32 = -1
        var charging: CBool = false
        let ok = data.withUnsafeBytes { rawPtr in
            guard let basePtr = rawPtr.bindMemory(to: UInt8.self).baseAddress else { return false }
            return fn(basePtr, data.count, &left, &right, &caseLvl, &charging)
        }
        guard ok else { return nil }
        return HeadphoneBattery(
            left: left >= 0 ? Int(left) : nil,
            right: right >= 0 ? Int(right) : nil,
            caseLevel: caseLvl >= 0 ? Int(caseLvl) : nil,
            isCharging: charging
        )
    }
    
    /// Builds Sony MDR multipoint audio switch packet.
    public func buildSonySwitchAudioPacket(targetSlot: UInt8) -> Data {
        var buffer = [UInt8](repeating: 0, count: 32)
        if let fn = fnSonyBuildSwitchAudio {
            let dummyMac: [UInt8] = [0x00, 0x1A, 0x7D, 0xDA, 0x71, targetSlot]
            let written = fn(0x01, dummyMac, &buffer, buffer.count)
            if written > 0 {
                return Data(buffer[0..<written])
            }
        }
        // Fallback: 0x0E start, 0x00 seq, 0x0002 len, 0x4F cmd, slot, chk, 0x3C end
        let chk = (0x00 &+ 0x02 &+ 0x4F &+ targetSlot) & 0xFF
        return Data([0x0E, 0x00, 0x00, 0x02, 0x4F, targetSlot, chk, 0x3C])
    }
    
    /// Parses Sony MDR battery telemetry packet.
    public func parseSonyBattery(data: Data) -> HeadphoneBattery? {
        guard let fn = fnSonyParseBattery else {
            if data.count >= 7 && data[0] == 0x0E && data[4] == 0x22 {
                let l = Int(data[5])
                let r = data.count >= 8 ? Int(data[6]) : l
                return HeadphoneBattery(
                    left: l <= 100 ? l : nil,
                    right: r <= 100 ? r : nil,
                    caseLevel: nil,
                    isCharging: false
                )
            }
            return nil
        }
        var left: Int32 = -1
        var right: Int32 = -1
        var caseLvl: Int32 = -1
        var charging: CBool = false
        let ok = data.withUnsafeBytes { rawPtr in
            guard let basePtr = rawPtr.bindMemory(to: UInt8.self).baseAddress else { return false }
            return fn(basePtr, data.count, &left, &right, &caseLvl, &charging)
        }
        guard ok else { return nil }
        return HeadphoneBattery(
            left: left >= 0 ? Int(left) : nil,
            right: right >= 0 ? Int(right) : nil,
            caseLevel: caseLvl >= 0 ? Int(caseLvl) : nil,
            isCharging: charging
        )
    }
    
    /// Verifies single-point roaming feasibility using Rust core generic driver coordinator.
    public func genericCanRoam(current: String, target: String) -> Bool {
        guard let fn = fnGenericCanRoam else {
            return !current.isEmpty && !target.isEmpty && current != target
        }
        return current.withCString { cCur in
            target.withCString { cTgt in
                fn(cCur, cTgt)
            }
        }
    }
}
