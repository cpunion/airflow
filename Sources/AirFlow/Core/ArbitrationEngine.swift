import Foundation

/// Central arbitration engine that coordinates audio routing, gatekeeper bypass,
/// playback observation, and anti-ping-pong cooldown logic.
public final class ArbitrationEngine: @unchecked Sendable {
    public private(set) var currentState: EngineState = .idle {
        didSet {
            onStateChanged?(currentState)
        }
    }
    
    public var onStateChanged: (@Sendable (EngineState) -> Void)?
    
    private let audioMonitor: AudioDeviceMonitorProtocol
    private let mediaObserver: MediaPlaybackObserverProtocol
    private let driver: HeadphoneDriver
    private let whitelistManager: DeviceWhitelistManager
    private let config: AppConfig
    
    private var isHandoffEnabled: Bool = true
    private var isAirPodsBypassEnabled: Bool = true
    private var cooldownTimer: Timer?
    private var currentAudioDevice: AudioDevice?
    
    public init(
        audioMonitor: AudioDeviceMonitorProtocol,
        mediaObserver: MediaPlaybackObserverProtocol,
        driver: HeadphoneDriver,
        whitelistManager: DeviceWhitelistManager,
        config: AppConfig = .load()
    ) {
        self.audioMonitor = audioMonitor
        self.mediaObserver = mediaObserver
        self.driver = driver
        self.whitelistManager = whitelistManager
        self.config = config
        self.isAirPodsBypassEnabled = config.enableAirPodsBypass
    }
    
    public func start() {
        print("[ArbitrationEngine] Starting handoff arbitration engine...")
        
        driver.start()
        
        // 1. Observe default audio device changes (Gatekeeper)
        audioMonitor.startMonitoring { [weak self] device in
            self?.handleAudioDeviceChanged(device)
        }
        
        // 2. Observe system media playback changes
        mediaObserver.startMonitoring { [weak self] isPlaying in
            self?.handleMediaPlaybackChanged(isPlaying)
        }
    }
    
    public func stop() {
        audioMonitor.stopMonitoring()
        mediaObserver.stopMonitoring()
        driver.stop()
        cooldownTimer?.invalidate()
        cooldownTimer = nil
        currentState = .idle
    }
    
    public func setHandoffEnabled(_ enabled: Bool) {
        self.isHandoffEnabled = enabled
        if !enabled {
            currentState = .bypassed(reason: "Handoff Disabled by User")
        } else if let device = currentAudioDevice {
            handleAudioDeviceChanged(device)
        }
    }
    
    public func setAirPodsBypassEnabled(_ enabled: Bool) {
        self.isAirPodsBypassEnabled = enabled
        if let device = currentAudioDevice {
            handleAudioDeviceChanged(device)
        }
    }
    
    // MARK: - State Machine & Event Handling
    
    private func handleAudioDeviceChanged(_ device: AudioDevice) {
        self.currentAudioDevice = device
        print("[ArbitrationEngine] Audio device changed to: '\(device.name)'")
        
        guard isHandoffEnabled else {
            currentState = .bypassed(reason: "Handoff Disabled by User")
            return
        }
        
        // Gatekeeper Check: Is it an Apple AirPods device?
        if device.isAirPods {
            let isPeerAndroid = config.targetPhoneName?.lowercased().contains("android") ?? false
            let shouldBypass = isAirPodsBypassEnabled && !isPeerAndroid
            
            if shouldBypass {
                print("[ArbitrationEngine] GATEKEEPER BYPASS: Detected AirPods on Apple ecosystem. Handing over to native Apple engine.")
                currentState = .bypassed(reason: "AirPods Active (Native Apple Handoff)")
                return
            } else {
                print("[ArbitrationEngine] AirPods active with custom management enabled (Android peer or manual override).")
            }
        }
        
        // Check for built-in speaker
        if device.isBuiltin {
            currentState = .bypassed(reason: "Internal Speakers Active")
            return
        }
        
        // Target Headphone Match
        if driver.canHandle(deviceName: device.name) || device.isShokz || device.isAirPods {
            print("[ArbitrationEngine] Target headphone '\(device.name)' connected and active.")
            let isPlaying = mediaObserver.isMediaPlaying()
            if isPlaying {
                transitionToHostActive()
            } else {
                currentState = .idle
            }
        } else {
            currentState = .bypassed(reason: "Non-target audio device: \(device.name)")
        }
    }
    
    private func handleMediaPlaybackChanged(_ isPlaying: Bool) {
        guard isHandoffEnabled else { return }
        
        // Ignore if currently bypassed (e.g. AirPods in use)
        if case .bypassed = currentState {
            return
        }
        
        if isPlaying {
            // Host started playing media!
            if case .cooldown = currentState {
                print("[ArbitrationEngine] In cooldown, ignoring playback trigger.")
                return
            }
            transitionToHostActive()
        } else {
            // Host stopped playing
            if case .hostActive = currentState {
                currentState = .idle
                print("[ArbitrationEngine] Host media stopped. State -> Idle")
            }
        }
    }
    
    private func transitionToHostActive() {
        currentState = .hostActive
        print("[ArbitrationEngine] Host Active! Coordinating mobile peer pause...")
        
        // Dispatch pause to the whitelisted mobile peer
        if let boundPeer = whitelistManager.getBoundDevice() {
            print("[ArbitrationEngine] Sending Pause to whitelisted peer: \(boundPeer.name)")
            // Future extension: dispatch BLE remote command / Apple Media Service
        }
        
        startCooldown()
    }
    
    private func startCooldown() {
        cooldownTimer?.invalidate()
        let ms = config.arbitrationCooldownMs
        currentState = .cooldown(remainingMs: ms)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { [weak self] in
            guard let self = self else { return }
            if case .cooldown = self.currentState {
                let isPlaying = self.mediaObserver.isMediaPlaying()
                self.currentState = isPlaying ? .hostActive : .idle
                print("[ArbitrationEngine] Cooldown expired. Returned to \(self.currentState)")
            }
        }
    }
}
