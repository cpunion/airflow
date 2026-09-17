use serde::{Deserialize, Serialize};

/// Represents an audio output device discovered on the host system.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AudioDevice {
    pub id: u32,
    pub name: String,
    pub is_bluetooth: bool,
}

impl AudioDevice {
    pub fn new(id: u32, name: impl Into<String>, is_bluetooth: bool) -> Self {
        Self {
            id,
            name: name.into(),
            is_bluetooth,
        }
    }

    /// Returns true if the device is an Apple AirPods or Beats device with native Apple handoff.
    pub fn is_airpods(&self) -> bool {
        let lower = self.name.to_lowercase();
        lower.contains("airpods")
            || lower.contains("beats fit pro")
            || lower.contains("beats studio")
    }

    /// Returns true if this device is considered an internal built-in speaker.
    pub fn is_builtin(&self) -> bool {
        let lower = self.name.to_lowercase();
        lower.contains("speaker") || lower.contains("扬声器") || lower.contains("internal")
    }
}

/// Represents information about a device paired with a headphone.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PairedDeviceInfo {
    pub id: String,
    pub name: String,
    pub address: Option<String>,
    pub is_connected: bool,
}

impl PairedDeviceInfo {
    pub fn new(
        id: impl Into<String>,
        name: impl Into<String>,
        address: Option<String>,
        is_connected: bool,
    ) -> Self {
        Self {
            id: id.into(),
            name: name.into(),
            address,
            is_connected,
        }
    }
}

/// Current state of the handoff arbitration engine.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", content = "details")]
pub enum EngineState {
    /// Idle state, waiting for audio playback events.
    Idle,
    /// Bypassed state: active device does not require arbitration (e.g., AirPods or internal speaker).
    Bypassed { reason: String },
    /// Active state: host (Mac/Linux/Windows) is actively playing media.
    HostActive,
    /// Active state: mobile peer (iPhone/Android) is actively playing media.
    PeerActive,
    /// Cooldown window to prevent circular pause ping-pong loops.
    Cooldown { remaining_ms: u64 },
}

/// Application configuration for arbitration and target device pairing.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppConfig {
    pub target_phone_name: Option<String>,
    pub target_phone_uuid: Option<String>,
    pub target_phone_bt_addr: Option<String>,
    pub target_headphone_name: String,
    pub target_headphone_uuid: Option<String>,
    pub target_headphone_bt_addr: Option<String>,
    pub arbitration_cooldown_ms: u64,
    pub enable_airpods_bypass: bool,
    pub enable_auto_pause: bool,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            target_phone_name: None,
            target_phone_uuid: None,
            target_phone_bt_addr: None,
            target_headphone_name: "Wireless Headphone".to_string(),
            target_headphone_uuid: None,
            target_headphone_bt_addr: None,
            arbitration_cooldown_ms: 1500,
            enable_airpods_bypass: true,
            enable_auto_pause: true,
        }
    }
}
