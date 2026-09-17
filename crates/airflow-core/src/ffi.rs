use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::sync::Arc;

use crate::arbitration::ArbitrationEngine;
use crate::drivers::shokz::ShokzDriver;
use crate::models::{AppConfig, AudioDevice, EngineState, PairedDeviceInfo};
use crate::whitelist::DeviceWhitelistManager;

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum AirFlowStateCode {
    Idle = 0,
    Bypassed = 1,
    HostActive = 2,
    PeerActive = 3,
    Cooldown = 4,
}

pub type AirFlowStateCallback =
    extern "C" fn(state_code: AirFlowStateCode, reason: *const c_char, remaining_ms: u64, user_data: *mut c_void);

pub type AirFlowPauseCallback =
    extern "C" fn(device_id: *const c_char, device_name: *const c_char, user_data: *mut c_void);

pub struct AirFlowEngineHandle {
    pub engine: Arc<ArbitrationEngine>,
    pub whitelist: Arc<DeviceWhitelistManager>,
}

/// Creates a new AirFlow arbitration engine instance.
#[no_mangle]
pub unsafe extern "C" fn airflow_engine_create() -> *mut AirFlowEngineHandle {
    let config = AppConfig::default();
    let driver = Arc::new(ShokzDriver::default());
    let whitelist = Arc::new(DeviceWhitelistManager::new(config.clone()));
    let engine = Arc::new(ArbitrationEngine::new(driver, whitelist.clone(), config));

    let handle = Box::new(AirFlowEngineHandle { engine, whitelist });
    Box::into_raw(handle)
}

/// Frees an AirFlow arbitration engine instance.
#[no_mangle]
pub unsafe extern "C" fn airflow_engine_destroy(handle: *mut AirFlowEngineHandle) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Notifies the engine that the default audio output device has changed.
#[no_mangle]
pub unsafe extern "C" fn airflow_engine_on_audio_device_changed(
    handle: *mut AirFlowEngineHandle,
    id: u32,
    name: *const c_char,
    is_bluetooth: bool,
) {
    if handle.is_null() || name.is_null() {
        return;
    }
    let handle = &*handle;
    let name_str = match CStr::from_ptr(name).to_str() {
        Ok(s) => s,
        Err(_) => return,
    };

    let device = AudioDevice::new(id, name_str, is_bluetooth);
    handle.engine.handle_audio_device_changed(device);
}

/// Notifies the engine that system media playback state has changed.
#[no_mangle]
pub unsafe extern "C" fn airflow_engine_on_media_playback_changed(
    handle: *mut AirFlowEngineHandle,
    is_playing: bool,
) {
    if handle.is_null() {
        return;
    }
    let handle = &*handle;
    handle.engine.handle_media_playback_changed(is_playing);
}

/// Toggles whether global handoff is enabled.
#[no_mangle]
pub unsafe extern "C" fn airflow_engine_set_handoff_enabled(
    handle: *mut AirFlowEngineHandle,
    enabled: bool,
) {
    if handle.is_null() {
        return;
    }
    let handle = &*handle;
    handle.engine.set_handoff_enabled(enabled);
}

/// Toggles whether Apple AirPods bypass mode is enabled on Apple platforms.
#[no_mangle]
pub unsafe extern "C" fn airflow_engine_set_airpods_bypass_enabled(
    handle: *mut AirFlowEngineHandle,
    enabled: bool,
) {
    if handle.is_null() {
        return;
    }
    let handle = &*handle;
    handle.engine.set_airpods_bypass_enabled(enabled);
}

/// Registers a callback invoked whenever the arbitration state changes.
#[no_mangle]
pub unsafe extern "C" fn airflow_engine_register_state_callback(
    handle: *mut AirFlowEngineHandle,
    callback: AirFlowStateCallback,
    user_data: *mut c_void,
) {
    if handle.is_null() {
        return;
    }
    let handle = &*handle;
    let user_data_ptr = user_data as usize;

    handle.engine.on_state_changed(move |state| {
        let (code, reason_cstr, remaining_ms) = match state {
            EngineState::Idle => (AirFlowStateCode::Idle, None, 0),
            EngineState::Bypassed { reason } => {
                (AirFlowStateCode::Bypassed, CString::new(reason.as_str()).ok(), 0)
            }
            EngineState::HostActive => (AirFlowStateCode::HostActive, None, 0),
            EngineState::PeerActive => (AirFlowStateCode::PeerActive, None, 0),
            EngineState::Cooldown { remaining_ms } => {
                (AirFlowStateCode::Cooldown, None, *remaining_ms)
            }
        };

        let ptr = reason_cstr
            .as_ref()
            .map(|cs| cs.as_ptr())
            .unwrap_or(std::ptr::null());

        callback(code, ptr, remaining_ms, user_data_ptr as *mut c_void);
    });
}

/// Registers a callback invoked whenever a pause must be dispatched to the mobile peer.
#[no_mangle]
pub unsafe extern "C" fn airflow_engine_register_pause_callback(
    handle: *mut AirFlowEngineHandle,
    callback: AirFlowPauseCallback,
    user_data: *mut c_void,
) {
    if handle.is_null() {
        return;
    }
    let handle = &*handle;
    let user_data_ptr = user_data as usize;

    handle.engine.on_remote_pause_requested(move |peer| {
        let id_cstr = CString::new(peer.id.as_str()).unwrap_or_default();
        let name_cstr = CString::new(peer.name.as_str()).unwrap_or_default();
        callback(id_cstr.as_ptr(), name_cstr.as_ptr(), user_data_ptr as *mut c_void);
    });
}

/// Binds a mobile peer device to the whitelist.
#[no_mangle]
pub unsafe extern "C" fn airflow_whitelist_bind_device(
    handle: *mut AirFlowEngineHandle,
    id: *const c_char,
    name: *const c_char,
    address: *const c_char,
) {
    if handle.is_null() || id.is_null() || name.is_null() {
        return;
    }
    let handle = &*handle;
    let id_str = match CStr::from_ptr(id).to_str() {
        Ok(s) => s,
        Err(_) => return,
    };
    let name_str = match CStr::from_ptr(name).to_str() {
        Ok(s) => s,
        Err(_) => return,
    };
    let addr_str = if address.is_null() {
        None
    } else {
        CStr::from_ptr(address).to_str().ok().map(|s| s.to_string())
    };

    let peer = PairedDeviceInfo::new(id_str, name_str, addr_str, true);
    handle.whitelist.bind_device(peer);
}

/// Unbinds any current mobile peer device from the whitelist.
#[no_mangle]
pub unsafe extern "C" fn airflow_whitelist_unbind_device(handle: *mut AirFlowEngineHandle) {
    if handle.is_null() {
        return;
    }
    let handle = &*handle;
    handle.whitelist.unbind_device();
}

/// Checks if a device is whitelisted.
#[no_mangle]
pub unsafe extern "C" fn airflow_whitelist_is_allowed(
    handle: *mut AirFlowEngineHandle,
    id: *const c_char,
    name: *const c_char,
) -> bool {
    if handle.is_null() || id.is_null() {
        return false;
    }
    let handle = &*handle;
    let id_str = match CStr::from_ptr(id).to_str() {
        Ok(s) => s,
        Err(_) => return false,
    };
    let name_str = if name.is_null() {
        None
    } else {
        CStr::from_ptr(name).to_str().ok()
    };

    handle.whitelist.is_whitelisted(id_str, name_str)
}

/// Returns the pointer to the static BES/Shokz pause command packet.
#[no_mangle]
pub unsafe extern "C" fn airflow_shokz_get_pause_packet(out_len: *mut usize) -> *const u8 {
    let packet = ShokzDriver::pause_packet();
    if !out_len.is_null() {
        *out_len = packet.len();
    }
    packet.as_ptr()
}

/// Parses a Google Fast Pair battery packet (at least 3 bytes).
/// Writes left, right, case_level (0-100 or -1 if missing), and is_charging.
#[no_mangle]
pub unsafe extern "C" fn airflow_shokz_parse_battery(
    data: *const u8,
    len: usize,
    out_left: *mut i32,
    out_right: *mut i32,
    out_case: *mut i32,
    out_charging: *mut bool,
) -> bool {
    if data.is_null() || len < 3 {
        return false;
    }
    let slice = std::slice::from_raw_parts(data, len);
    if let Some(battery) = ShokzDriver::parse_fast_pair_battery(slice) {
        if !out_left.is_null() {
            *out_left = battery.left.map(|v| v as i32).unwrap_or(-1);
        }
        if !out_right.is_null() {
            *out_right = battery.right.map(|v| v as i32).unwrap_or(-1);
        }
        if !out_case.is_null() {
            *out_case = battery.case_level.map(|v| v as i32).unwrap_or(-1);
        }
        if !out_charging.is_null() {
            *out_charging = battery.is_charging;
        }
        true
    } else {
        false
    }
}
