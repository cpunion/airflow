use std::sync::Arc;
use parking_lot::RwLock;
use tracing::{debug, info};

use crate::drivers::HeadphoneDriver;
use crate::models::{AppConfig, AudioDevice, EngineState, PairedDeviceInfo};
use crate::whitelist::DeviceWhitelistManager;

pub type StateCallback = Arc<dyn Fn(&EngineState) + Send + Sync>;
pub type PauseCallback = Arc<dyn Fn(&PairedDeviceInfo) + Send + Sync>;

/// Central arbitration engine that coordinates audio routing, gatekeeper bypass,
/// playback observation, and anti-ping-pong cooldown logic.
pub struct ArbitrationEngine {
    current_state: RwLock<EngineState>,
    current_audio_device: RwLock<Option<AudioDevice>>,
    is_media_playing: RwLock<bool>,
    is_handoff_enabled: RwLock<bool>,
    is_airpods_bypass_enabled: RwLock<bool>,
    driver: Arc<dyn HeadphoneDriver>,
    whitelist_manager: Arc<DeviceWhitelistManager>,
    config: AppConfig,
    state_callbacks: RwLock<Vec<StateCallback>>,
    pause_callbacks: RwLock<Vec<PauseCallback>>,
}

impl ArbitrationEngine {
    pub fn new(
        driver: Arc<dyn HeadphoneDriver>,
        whitelist_manager: Arc<DeviceWhitelistManager>,
        config: AppConfig,
    ) -> Self {
        let bypass_enabled = config.enable_airpods_bypass;
        Self {
            current_state: RwLock::new(EngineState::Idle),
            current_audio_device: RwLock::new(None),
            is_media_playing: RwLock::new(false),
            is_handoff_enabled: RwLock::new(true),
            is_airpods_bypass_enabled: RwLock::new(bypass_enabled),
            driver,
            whitelist_manager,
            config,
            state_callbacks: RwLock::new(Vec::new()),
            pause_callbacks: RwLock::new(Vec::new()),
        }
    }

    /// Subscribes to engine state changes.
    pub fn on_state_changed(&self, callback: impl Fn(&EngineState) + Send + Sync + 'static) {
        self.state_callbacks.write().push(Arc::new(callback));
    }

    /// Subscribes to requests to send pause commands to the whitelisted mobile peer.
    pub fn on_remote_pause_requested(
        &self,
        callback: impl Fn(&PairedDeviceInfo) + Send + Sync + 'static,
    ) {
        self.pause_callbacks.write().push(Arc::new(callback));
    }

    /// Returns the current state of the engine.
    pub fn current_state(&self) -> EngineState {
        self.current_state.read().clone()
    }

    /// Returns the currently active audio device, if any.
    pub fn current_audio_device(&self) -> Option<AudioDevice> {
        self.current_audio_device.read().clone()
    }

    /// Sets whether global handoff arbitration is enabled.
    pub fn set_handoff_enabled(&self, enabled: bool) {
        *self.is_handoff_enabled.write() = enabled;
        if !enabled {
            self.transition_to(EngineState::Bypassed {
                reason: "Handoff Disabled by User".to_string(),
            });
        } else if let Some(device) = self.current_audio_device.read().clone() {
            self.handle_audio_device_changed(device);
        }
    }

    /// Configures whether Apple AirPods are automatically bypassed on Apple platforms.
    pub fn set_airpods_bypass_enabled(&self, enabled: bool) {
        *self.is_airpods_bypass_enabled.write() = enabled;
        if let Some(device) = self.current_audio_device.read().clone() {
            self.handle_audio_device_changed(device);
        }
    }

    /// Processes an audio device change event from the platform monitor.
    pub fn handle_audio_device_changed(&self, device: AudioDevice) {
        info!("[ArbitrationEngine] Audio device changed to: '{}'", device.name);
        *self.current_audio_device.write() = Some(device.clone());

        if !*self.is_handoff_enabled.read() {
            self.transition_to(EngineState::Bypassed {
                reason: "Handoff Disabled by User".to_string(),
            });
            return;
        }

        // Gatekeeper Check: Is it an Apple AirPods or Beats device?
        if device.is_airpods() {
            let is_peer_android = self
                .config
                .target_phone_name
                .as_ref()
                .map(|name| name.to_lowercase().contains("android"))
                .unwrap_or(false);

            let should_bypass = *self.is_airpods_bypass_enabled.read() && !is_peer_android;

            if should_bypass {
                info!("[ArbitrationEngine] GATEKEEPER BYPASS: Detected AirPods on Apple ecosystem. Handing over to native Apple engine.");
                self.transition_to(EngineState::Bypassed {
                    reason: "AirPods Active (Native Apple Handoff)".to_string(),
                });
                return;
            } else {
                info!("[ArbitrationEngine] AirPods active with custom management enabled (Android peer or manual override).");
            }
        }

        // Built-in speaker check
        if device.is_builtin() {
            self.transition_to(EngineState::Bypassed {
                reason: "Internal Speakers Active".to_string(),
            });
            return;
        }

        // Target Headphone Match
        if self.driver.can_handle(&device.name) || device.is_airpods() {
            info!(
                "[ArbitrationEngine] Target headphone '{}' connected and active.",
                device.name
            );
            if *self.is_media_playing.read() {
                self.transition_to_host_active();
            } else {
                self.transition_to(EngineState::Idle);
            }
        } else {
            self.transition_to(EngineState::Bypassed {
                reason: format!("Non-target audio device: {}", device.name),
            });
        }
    }

    /// Processes a media playback state change event from the platform observer.
    pub fn handle_media_playback_changed(&self, is_playing: bool) {
        *self.is_media_playing.write() = is_playing;

        if !*self.is_handoff_enabled.read() {
            return;
        }

        // Ignore if currently bypassed (e.g. AirPods in native mode)
        if matches!(self.current_state(), EngineState::Bypassed { .. }) {
            return;
        }

        if is_playing {
            if matches!(self.current_state(), EngineState::Cooldown { .. }) {
                debug!("[ArbitrationEngine] In cooldown, ignoring playback trigger.");
                return;
            }
            self.transition_to_host_active();
        } else {
            if matches!(self.current_state(), EngineState::HostActive) {
                self.transition_to(EngineState::Idle);
                info!("[ArbitrationEngine] Host media stopped. State -> Idle");
            }
        }
    }

    /// Dispatches a pause signal to the mobile peer and transitions to Cooldown state.
    fn transition_to_host_active(&self) {
        info!("[ArbitrationEngine] Host Active! Coordinating mobile peer pause...");

        // Dispatch pause to the whitelisted mobile peer
        if let Some(bound_peer) = self.whitelist_manager.get_bound_device() {
            info!(
                "[ArbitrationEngine] Sending Pause to whitelisted peer: {}",
                bound_peer.name
            );
            let callbacks = self.pause_callbacks.read().clone();
            for cb in callbacks {
                cb(&bound_peer);
            }
        }

        self.start_cooldown();
    }

    /// Enforces intentional cooldown to prevent circular pause deadlocks.
    fn start_cooldown(&self) {
        let ms = self.config.arbitration_cooldown_ms;
        self.transition_to(EngineState::Cooldown {
            remaining_ms: ms,
        });

        // Note: For async runtimes or UI timers, cooldown expiration can be triggered by calling
        // handle_cooldown_expired() or passing a callback.
    }

    /// Handles cooldown timer expiration.
    pub fn handle_cooldown_expired(&self) {
        if matches!(self.current_state(), EngineState::Cooldown { .. }) {
            let next_state = if *self.is_media_playing.read() {
                EngineState::HostActive
            } else {
                EngineState::Idle
            };
            self.transition_to(next_state);
        }
    }

    fn transition_to(&self, new_state: EngineState) {
        {
            let mut lock = self.current_state.write();
            *lock = new_state.clone();
        }
        let callbacks = self.state_callbacks.read().clone();
        for cb in callbacks {
            cb(&new_state);
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicBool, Ordering};
    use crate::drivers::shokz::ShokzDriver;
    use super::*;

    #[test]
    fn test_gatekeeper_bypasses_airpods_on_apple_ecosystem() {
        let driver = Arc::new(ShokzDriver::default());
        let whitelist = Arc::new(DeviceWhitelistManager::new(AppConfig::default()));
        let engine = ArbitrationEngine::new(driver, whitelist, AppConfig::default());

        let airpods = AudioDevice::new(1, "AirPods Pro", true);
        engine.handle_audio_device_changed(airpods);

        assert!(matches!(
            engine.current_state(),
            EngineState::Bypassed { ref reason } if reason.contains("AirPods Active")
        ));
    }

    #[test]
    fn test_gatekeeper_does_not_bypass_when_peer_is_android() {
        let driver = Arc::new(ShokzDriver::default());
        let mut config = AppConfig::default();
        config.target_phone_name = Some("Pixel 8 Pro (Android)".to_string());

        let whitelist = Arc::new(DeviceWhitelistManager::new(config.clone()));
        let engine = ArbitrationEngine::new(driver, whitelist, config);

        let airpods = AudioDevice::new(1, "AirPods Pro", true);
        engine.handle_audio_device_changed(airpods);

        // Should NOT be bypassed
        assert_eq!(engine.current_state(), EngineState::Idle);
    }

    #[test]
    fn test_gatekeeper_user_manual_bypass_toggle() {
        let driver = Arc::new(ShokzDriver::default());
        let whitelist = Arc::new(DeviceWhitelistManager::new(AppConfig::default()));
        let engine = ArbitrationEngine::new(driver, whitelist, AppConfig::default());

        engine.set_airpods_bypass_enabled(false);

        let airpods = AudioDevice::new(1, "AirPods Pro", true);
        engine.handle_audio_device_changed(airpods);

        // Since user disabled AirPods bypass, engine controls AirPods
        assert_eq!(engine.current_state(), EngineState::Idle);
    }

    #[test]
    fn test_target_multipoint_headphone_activates_engine() {
        let driver = Arc::new(ShokzDriver::default());
        let whitelist = Arc::new(DeviceWhitelistManager::new(AppConfig::default()));
        let engine = ArbitrationEngine::new(driver, whitelist, AppConfig::default());

        let headphone = AudioDevice::new(2, "OpenDots 2", true);
        engine.handle_audio_device_changed(headphone);

        assert_eq!(engine.current_state(), EngineState::Idle);

        // Play media
        engine.handle_media_playback_changed(true);
        assert!(matches!(
            engine.current_state(),
            EngineState::Cooldown { .. }
        ));

        // Cooldown expires
        engine.handle_cooldown_expired();
        assert_eq!(engine.current_state(), EngineState::HostActive);

        // Pause media
        engine.handle_media_playback_changed(false);
        assert_eq!(engine.current_state(), EngineState::Idle);
    }

    #[test]
    fn test_peer_pause_request_dispatch_to_whitelisted_peer() {
        let driver = Arc::new(ShokzDriver::default());
        let whitelist = Arc::new(DeviceWhitelistManager::new(AppConfig::default()));
        let bound_peer = PairedDeviceInfo::new("DEV-1", "My iPhone", None, true);
        whitelist.bind_device(bound_peer);

        let engine = ArbitrationEngine::new(driver, whitelist, AppConfig::default());
        let pause_called = Arc::new(AtomicBool::new(false));
        let pause_called_clone = pause_called.clone();

        engine.on_remote_pause_requested(move |peer| {
            if peer.name == "My iPhone" {
                pause_called_clone.store(true, Ordering::SeqCst);
            }
        });

        let headphone = AudioDevice::new(2, "OpenDots 2", true);
        engine.handle_audio_device_changed(headphone);
        engine.handle_media_playback_changed(true);

        assert!(pause_called.load(Ordering::SeqCst));
    }
}
