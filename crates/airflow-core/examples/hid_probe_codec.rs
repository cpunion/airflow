//! JSON boundary for the Swift hardware probe; all HID bytes originate in Rust.
use airflow_core::hid::{
    control_request, input_report, ConsumerKey, ControlAction, REPORT_DESCRIPTOR,
};
use serde_json::json;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let output = match args.as_slice() {
        [] => json!({
            "descriptor": REPORT_DESCRIPTOR,
            "pause": input_report(ConsumerKey::Pause),
            "toggle": input_report(ConsumerKey::PlayPause),
            "release": input_report(ConsumerKey::Released),
        }),
        [mode, hex, state] if mode == "control" => {
            let bytes: Result<Vec<u8>, _> =
                hex.split('-').map(|b| u8::from_str_radix(b, 16)).collect();
            let bytes = bytes.unwrap_or_else(|_| {
                eprintln!("Invalid HIDP hexadecimal request");
                std::process::exit(2);
            });
            let key = match state.as_str() {
                "pause" => ConsumerKey::Pause,
                "toggle" => ConsumerKey::PlayPause,
                "released" => ConsumerKey::Released,
                _ => {
                    eprintln!("Unknown input report state");
                    std::process::exit(2);
                }
            };
            match control_request(&bytes, key) {
                ControlAction::Reply(bytes) => json!({"action":"reply", "bytes":bytes}),
                ControlAction::Suspend => json!({"action":"suspend"}),
                ControlAction::Resume => json!({"action":"resume"}),
                ControlAction::Unplug => json!({"action":"unplug"}),
                ControlAction::Ignore => json!({"action":"ignore"}),
            }
        }
        _ => {
            eprintln!("Usage: hid_probe_codec [control HEX-BYTES released|pause|toggle]");
            std::process::exit(2);
        }
    };
    println!("{output}");
}
