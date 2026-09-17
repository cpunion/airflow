#ifndef AIRFLOW_CORE_H
#define AIRFLOW_CORE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum AirFlowStateCode {
    AIRFLOW_STATE_IDLE = 0,
    AIRFLOW_STATE_BYPASSED = 1,
    AIRFLOW_STATE_HOST_ACTIVE = 2,
    AIRFLOW_STATE_PEER_ACTIVE = 3,
    AIRFLOW_STATE_COOLDOWN = 4
} AirFlowStateCode;

typedef struct AirFlowEngineHandle AirFlowEngineHandle;

typedef void (*AirFlowStateCallback)(
    AirFlowStateCode state_code,
    const char *reason,
    uint64_t remaining_ms,
    void *user_data
);

typedef void (*AirFlowPauseCallback)(
    const char *device_id,
    const char *device_name,
    void *user_data
);

// Engine Lifecycle
AirFlowEngineHandle* airflow_engine_create(void);
void airflow_engine_destroy(AirFlowEngineHandle *handle);

// Event Handlers
void airflow_engine_on_audio_device_changed(
    AirFlowEngineHandle *handle,
    uint32_t id,
    const char *name,
    bool is_bluetooth
);

void airflow_engine_on_media_playback_changed(
    AirFlowEngineHandle *handle,
    bool is_playing
);

// Configuration & Toggles
void airflow_engine_set_handoff_enabled(AirFlowEngineHandle *handle, bool enabled);
void airflow_engine_set_airpods_bypass_enabled(AirFlowEngineHandle *handle, bool enabled);

// Callbacks
void airflow_engine_register_state_callback(
    AirFlowEngineHandle *handle,
    AirFlowStateCallback callback,
    void *user_data
);

void airflow_engine_register_pause_callback(
    AirFlowEngineHandle *handle,
    AirFlowPauseCallback callback,
    void *user_data
);

// Whitelist Management
void airflow_whitelist_bind_device(
    AirFlowEngineHandle *handle,
    const char *id,
    const char *name,
    const char *address
);

void airflow_whitelist_unbind_device(AirFlowEngineHandle *handle);

bool airflow_whitelist_is_allowed(
    AirFlowEngineHandle *handle,
    const char *id,
    const char *name
);

// Shokz / BES Protocol Decoders & Encoders
const uint8_t* airflow_shokz_get_pause_packet(size_t *out_len);

bool airflow_shokz_parse_battery(
    const uint8_t *data,
    size_t len,
    int32_t *out_left,
    int32_t *out_right,
    int32_t *out_case,
    bool *out_charging
);

// Apple Accessory Protocol (AAP) Decoders & Encoders
size_t airflow_airpods_build_anc_command(
    uint8_t mode_code,
    uint8_t *out_buf,
    size_t max_len
);

bool airflow_airpods_parse_in_ear(
    const uint8_t *data,
    size_t len,
    bool *out_left,
    bool *out_right
);

bool airflow_airpods_parse_battery(
    const uint8_t *data,
    size_t len,
    int32_t *out_left,
    int32_t *out_right,
    int32_t *out_case,
    bool *out_charging
);

// Sony MDR Protocol Decoders & Encoders
size_t airflow_sony_build_switch_connection(
    uint8_t seq,
    const uint8_t *target_mac,
    uint8_t *out_buf,
    size_t max_len
);

bool airflow_sony_parse_battery(
    const uint8_t *data,
    size_t len,
    int32_t *out_left,
    int32_t *out_right,
    int32_t *out_case,
    bool *out_charging
);

#ifdef __cplusplus
}
#endif

#endif // AIRFLOW_CORE_H
