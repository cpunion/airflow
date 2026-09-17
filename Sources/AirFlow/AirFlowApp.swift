import Foundation

#if os(macOS)
import AppKit

// MARK: - Application Delegate (macOS)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var audioMonitor: CoreAudioMonitor!
    private var mediaObserver: MediaRemoteObserver!
    private var driver: ShokzDriver!
    private var whitelistManager: DeviceWhitelistManager!
    private var engine: ArbitrationEngine!
    private var menubarManager: MenubarManager!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[AirFlow] Bootstrapping native macOS menubar application...")
        
        let config = AppConfig.load()
        
        self.audioMonitor = CoreAudioMonitor()
        self.mediaObserver = MediaRemoteObserver()
        self.driver = ShokzDriver(config: config)
        self.whitelistManager = DeviceWhitelistManager(config: config)
        
        self.engine = ArbitrationEngine(
            audioMonitor: audioMonitor,
            mediaObserver: mediaObserver,
            driver: driver,
            whitelistManager: whitelistManager,
            config: config
        )
        
        // Initialize native menu bar & SwiftUI popover UI
        self.menubarManager = MenubarManager(
            engine: engine,
            audioMonitor: audioMonitor,
            driver: driver,
            whitelistManager: whitelistManager
        )
        
        // Start engine services
        engine.start()
        
        // Start AirFlow Remote BLE Companion advertising
        BleRemoteServer.shared.startAdvertising()
        
        print("[AirFlow] Ready and running in macOS menu bar.")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("[AirFlow] Terminating application...")
        BleRemoteServer.shared.stopAdvertising()
        engine?.stop()
    }
}

// MARK: - Modern Swift 6 Entry Point (macOS)

public struct AirFlowApp {
    @MainActor
    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Run as an accessory menubar app (no dock icon)
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

#else

// MARK: - Headless CLI Entry Point (Linux & Windows)

public struct AirFlowApp {
    public static func run() {
        print("[AirFlow] Starting universal headphone handoff daemon (Linux/Windows)...")
        let config = AppConfig.load()
        let audioMonitor = CoreAudioMonitor()
        let mediaObserver = MediaRemoteObserver()
        let driver = ShokzDriver(config: config)
        let whitelist = DeviceWhitelistManager(config: config)
        
        let engine = ArbitrationEngine(
            audioMonitor: audioMonitor,
            mediaObserver: mediaObserver,
            driver: driver,
            whitelistManager: whitelist,
            config: config
        )
        
        engine.start()
        print("[AirFlow] Daemon running. Press Ctrl+C to terminate.")
        RunLoop.main.run()
    }
}

#endif
