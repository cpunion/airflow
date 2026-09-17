import Foundation

#if os(macOS)
import ServiceManagement

/// Helper for configuring launch-at-login on macOS using ServiceManagement.
public final class LaunchAtLoginHelper: @unchecked Sendable {
    public static let shared = LaunchAtLoginHelper()
    
    private init() {}
    
    public var isAvailable: Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }
    
    public var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            }
            return false
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        if SMAppService.mainApp.status != .enabled {
                            try SMAppService.mainApp.register()
                            print("[LaunchAtLogin] Registered AirFlow for launch at login.")
                        }
                    } else {
                        if SMAppService.mainApp.status == .enabled {
                            try SMAppService.mainApp.unregister()
                            print("[LaunchAtLogin] Unregistered AirFlow from launch at login.")
                        }
                    }
                } catch {
                    print("[LaunchAtLogin] Failed to update launch at login status: \(error.localizedDescription)")
                }
            }
        }
    }
}
#else
/// Fallback stub for non-macOS platforms.
public final class LaunchAtLoginHelper: @unchecked Sendable {
    public static let shared = LaunchAtLoginHelper()
    public var isAvailable: Bool { return false }
    public var isEnabled: Bool {
        get { return false }
        set {}
    }
    private init() {}
}
#endif
