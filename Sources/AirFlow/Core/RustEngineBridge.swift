import Foundation

/// C-compatible state codes matching `AirFlowStateCode` in `airflow_core.h`.
public enum RustStateCode: UInt32 {
    case idle = 0
    case bypassed = 1
    case hostActive = 2
    case peerActive = 3
    case cooldown = 4
}

/// Dynamically bridges the Swift frontend to `airflow-core` (Rust C-ABI library).
/// If `libairflow_core` is available, all arbitration decisions are delegated to the Rust engine.
public final class RustEngineBridge: @unchecked Sendable {
    private var dylibHandle: UnsafeMutableRawPointer?
    private var engineHandle: OpaquePointer?
    
    // Function pointers resolved via dlsym
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
        if let dylib = dylibHandle {
            dlclose(dylib)
        }
    }
    
    private func loadDylib(customPath: String?) {
        let candidatePaths: [String] = [
            customPath,
            Bundle.main.sharedFrameworksPath.map { "\($0)/libairflow_core.dylib" },
            "target/release/libairflow_core.dylib",
            "target/debug/libairflow_core.dylib",
            "/usr/local/lib/libairflow_core.dylib",
            "libairflow_core.dylib"
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
            // Attempt standard dlopen search
            if let handle = dlopen("libairflow_core.dylib", RTLD_NOW) {
                self.dylibHandle = handle
                print("[RustEngineBridge] Successfully loaded Rust core via dlopen search path.")
                bindSymbols()
            }
        }
    }
    
    private func bindSymbols() {
        guard let dylib = dylibHandle else { return }
        
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
    
    private func resolve<T>(_ handle: UnsafeMutableRawPointer, _ symbol: String) -> T? {
        guard let sym = dlsym(handle, symbol) else {
            print("[RustEngineBridge] Warning: symbol '\(symbol)' not found in library.")
            return nil
        }
        return unsafeBitCast(sym, to: T.self)
    }
    
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
}
