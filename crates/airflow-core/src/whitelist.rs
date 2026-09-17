use std::path::Path;
use parking_lot::RwLock;

use crate::models::{AppConfig, PairedDeviceInfo};

/// Manages persistent binding and whitelist verification for the target mobile peer.
/// Enforces strict whitelisting to guarantee the engine never commands or affects untargeted devices.
#[derive(Debug)]
pub struct DeviceWhitelistManager {
    bound_device: RwLock<Option<PairedDeviceInfo>>,
    config: AppConfig,
}

impl DeviceWhitelistManager {
    pub fn new(config: AppConfig) -> Self {
        let initial_device = if let Some(ref phone_name) = config.target_phone_name {
            Some(PairedDeviceInfo::new(
                config.target_phone_uuid.clone().unwrap_or_default(),
                phone_name.clone(),
                config.target_phone_bt_addr.clone(),
                true,
            ))
        } else {
            None
        };

        Self {
            bound_device: RwLock::new(initial_device),
            config,
        }
    }

    /// Returns the currently whitelisted target mobile peer, if any.
    pub fn get_bound_device(&self) -> Option<PairedDeviceInfo> {
        self.bound_device.read().clone()
    }

    /// Binds and whitelists a specific mobile device.
    pub fn bind_device(&self, device: PairedDeviceInfo) {
        let mut lock = self.bound_device.write();
        *lock = Some(device);
    }

    /// Unbinds the current whitelisted device.
    pub fn unbind_device(&self) {
        let mut lock = self.bound_device.write();
        *lock = None;
    }

    /// Checks whether the given peripheral identifier or name matches the whitelist.
    pub fn is_whitelisted(&self, id: &str, name: Option<&str>) -> bool {
        if let Some(ref bound) = *self.bound_device.read() {
            if bound.id == id {
                return true;
            }
            if let Some(n) = name {
                if bound.name == n {
                    return true;
                }
            }
        }

        // Fallback to configuration if provided
        if let Some(ref config_uuid) = self.config.target_phone_uuid {
            if config_uuid == id {
                return true;
            }
        }
        if let Some(ref config_name) = self.config.target_phone_name {
            if let Some(n) = name {
                if config_name == n {
                    return true;
                }
            }
        }

        false
    }

    /// Saves the current bound device to a JSON file.
    pub fn save_to_file(&self, path: &Path) -> Result<(), std::io::Error> {
        let lock = self.bound_device.read();
        let json = serde_json::to_string_pretty(&*lock)?;
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(path, json)?;
        Ok(())
    }

    /// Loads the bound device from a JSON file.
    pub fn load_from_file(&self, path: &Path) -> Result<(), std::io::Error> {
        if !path.exists() {
            return Ok(());
        }
        let data = std::fs::read_to_string(path)?;
        let device: Option<PairedDeviceInfo> = serde_json::from_str(&data)?;
        let mut lock = self.bound_device.write();
        *lock = device;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_strict_whitelisting() {
        let manager = DeviceWhitelistManager::new(AppConfig::default());
        assert!(!manager.is_whitelisted("UNKNOWN-ID", Some("Unknown Phone")));

        let device = PairedDeviceInfo::new("PHONE-123", "Pixel 8", None, true);
        manager.bind_device(device);

        assert!(manager.is_whitelisted("PHONE-123", None));
        assert!(manager.is_whitelisted("ANY-ID", Some("Pixel 8")));
        assert!(!manager.is_whitelisted("PHONE-999", Some("Stranger Phone")));

        manager.unbind_device();
        assert!(!manager.is_whitelisted("PHONE-123", Some("Pixel 8")));
    }
}
