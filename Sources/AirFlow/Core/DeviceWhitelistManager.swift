import Foundation

/// Manages persistent binding and whitelist verification for the target mobile peer.
/// Enforces strict whitelisting to guarantee the engine never commands or affects untargeted devices.
public final class DeviceWhitelistManager: @unchecked Sendable {
    private let userDefaultsKeyId = "airflow.whitelist.target_device_id"
    private let userDefaultsKeyName = "airflow.whitelist.target_device_name"
    
    private let config: AppConfig
    private var boundDevice: PairedDeviceInfo?
    
    public init(config: AppConfig = .load()) {
        self.config = config
        loadBoundDevice()
    }
    
    /// Returns the currently whitelisted target mobile peer, if any.
    public func getBoundDevice() -> PairedDeviceInfo? {
        return boundDevice
    }
    
    /// Binds and whitelists a specific mobile device.
    public func bindDevice(_ device: PairedDeviceInfo) {
        self.boundDevice = device
        UserDefaults.standard.set(device.id, forKey: userDefaultsKeyId)
        UserDefaults.standard.set(device.name, forKey: userDefaultsKeyName)
        print("[DeviceWhitelistManager] Bound target device: \(device.name) (\(device.id))")
    }
    
    /// Unbinds the current whitelisted device.
    public func unbindDevice() {
        self.boundDevice = nil
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyId)
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyName)
        print("[DeviceWhitelistManager] Unbound target device")
    }
    
    /// Checks whether the given peripheral identifier or name matches the whitelist.
    public func isWhitelisted(id: String, name: String? = nil) -> Bool {
        if let bound = boundDevice {
            if bound.id == id { return true }
            if let n = name, n == bound.name { return true }
        }
        
        // Fallback to .env configuration if not yet explicitly saved in UserDefaults
        if let configUUID = config.targetPhoneUUID, configUUID == id {
            return true
        }
        if let configName = config.targetPhoneName, let n = name, configName == n {
            return true
        }
        
        return false
    }
    
    private func loadBoundDevice() {
        if let savedId = UserDefaults.standard.string(forKey: userDefaultsKeyId),
           let savedName = UserDefaults.standard.string(forKey: userDefaultsKeyName) {
            self.boundDevice = PairedDeviceInfo(id: savedId, name: savedName, isConnected: true)
            return
        }
        
        // Populate from config (.env) if present
        if let phoneName = config.targetPhoneName {
            self.boundDevice = PairedDeviceInfo(
                id: config.targetPhoneUUID ?? UUID().uuidString,
                name: phoneName,
                address: config.targetPhoneBTAddr,
                isConnected: true
            )
        }
    }
}
