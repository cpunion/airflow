import AppKit
import Foundation

// MARK: - Application Delegate

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
        
        print("[AirFlow] Ready and running in macOS menu bar.")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("[AirFlow] Terminating application...")
        engine?.stop()
    }
}

// MARK: - Modern Swift 6 Entry Point

@main
struct AirFlowApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Run as an accessory menubar app (no dock icon)
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
