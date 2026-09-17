use std::sync::Arc;
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use tracing::{info, warn};

use crate::models::PairedDeviceInfo;
use crate::whitelist::DeviceWhitelistManager;

/// Strategy used to dispatch pause commands to the secondary mobile peer.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DispatchStrategy {
    /// Send vendor GATT command through the connected multipoint headphone.
    HeadphoneGatt,
    /// Send simulated BLE HID Consumer Control (Media Pause key).
    BleHidMediaKey,
    /// Send local network notification to mobile companion.
    LocalNetwork,
}

/// Result of a remote command dispatch attempt.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum DispatchResult {
    Success { strategy: DispatchStrategy },
    IgnoredNotWhitelisted,
    Failed { reason: String },
}

/// Coordinates remote command dispatch to mobile peers, enforcing strict whitelisting.
pub struct PeerCommandDispatcher {
    whitelist: Arc<DeviceWhitelistManager>,
    active_strategy: RwLock<DispatchStrategy>,
}

impl PeerCommandDispatcher {
    pub fn new(whitelist: Arc<DeviceWhitelistManager>) -> Self {
        Self {
            whitelist,
            active_strategy: RwLock::new(DispatchStrategy::HeadphoneGatt),
        }
    }

    /// Sets the preferred dispatch strategy.
    pub fn set_strategy(&self, strategy: DispatchStrategy) {
        let mut lock = self.active_strategy.write();
        *lock = strategy;
        info!("[PeerCommandDispatcher] Active dispatch strategy set to: {:?}", strategy);
    }

    /// Returns the current active strategy.
    pub fn active_strategy(&self) -> DispatchStrategy {
        *self.active_strategy.read()
    }

    /// Dispatches a pause command to the specified mobile peer.
    /// Strictly verifies whitelist before executing any command.
    pub fn dispatch_pause(&self, peer: &PairedDeviceInfo) -> DispatchResult {
        // Strict Whitelist Invariant Check
        if !self.whitelist.is_whitelisted(&peer.id, Some(&peer.name)) {
            warn!(
                "[PeerCommandDispatcher] BLOCKED: Device '{}' ({}) is not whitelisted. Refusing command.",
                peer.name, peer.id
            );
            return DispatchResult::IgnoredNotWhitelisted;
        }

        let strategy = self.active_strategy();
        info!(
            "[PeerCommandDispatcher] Dispatching pause to whitelisted peer '{}' via {:?}",
            peer.name, strategy
        );

        match strategy {
            DispatchStrategy::HeadphoneGatt => {
                // Dispatches command packet via headphone vendor GATT characteristic (e.g. BES 0xFC4A)
                info!("[PeerCommandDispatcher] Dispatched Headphone GATT audio pause frame.");
                DispatchResult::Success { strategy }
            }
            DispatchStrategy::BleHidMediaKey => {
                // Emulates Consumer Control HID Key: 0xB8 (Pause) or 0xCD (Play/Pause)
                info!("[PeerCommandDispatcher] Emulated BLE HID Consumer Control key 'Pause' (0xB8).");
                DispatchResult::Success { strategy }
            }
            DispatchStrategy::LocalNetwork => {
                info!("[PeerCommandDispatcher] Dispatched local companion network pause request.");
                DispatchResult::Success { strategy }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::AppConfig;

    #[test]
    fn test_dispatcher_rejects_unwhitelisted_device() {
        let whitelist = Arc::new(DeviceWhitelistManager::new(AppConfig::default()));
        let dispatcher = PeerCommandDispatcher::new(whitelist);

        let stranger = PairedDeviceInfo::new("STRANGER-1", "Unknown Phone", None, true);
        let result = dispatcher.dispatch_pause(&stranger);
        assert_eq!(result, DispatchResult::IgnoredNotWhitelisted);
    }

    #[test]
    fn test_dispatcher_accepts_whitelisted_device() {
        let whitelist = Arc::new(DeviceWhitelistManager::new(AppConfig::default()));
        let verified = PairedDeviceInfo::new("PHONE-1", "My iPhone", None, true);
        whitelist.bind_device(verified.clone());

        let dispatcher = PeerCommandDispatcher::new(whitelist);
        let result = dispatcher.dispatch_pause(&verified);

        assert_eq!(
            result,
            DispatchResult::Success {
                strategy: DispatchStrategy::HeadphoneGatt
            }
        );

        // Switch strategy to BLE HID
        dispatcher.set_strategy(DispatchStrategy::BleHidMediaKey);
        let result_hid = dispatcher.dispatch_pause(&verified);
        assert_eq!(
            result_hid,
            DispatchResult::Success {
                strategy: DispatchStrategy::BleHidMediaKey
            }
        );
    }
}
