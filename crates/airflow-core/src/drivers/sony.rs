use super::HeadphoneDriver;
use crate::models::HeadphoneBattery;

/// Pluggable driver for Sony wireless headphones using the Sony MDR protocol
/// (e.g. WH-1000XM4, WH-1000XM5, WF-1000XM4, WF-1000XM5, LinkBuds).
#[derive(Debug, Default)]
pub struct SonyDriver;

impl SonyDriver {
    pub const DRIVER_ID: &'static str = "driver.sony.mdr";
    pub const BRAND_NAME: &'static str = "Sony";

    /// Sony MDR Serial Port Profile (SPP) Service UUID.
    pub const SONY_MDR_SERVICE_UUID: &'static str = "00001101-0000-1000-8000-00805F9B34FB";

    pub const START_BYTE: u8 = 0x0C;
    pub const CMD_BATTERY_STATUS: u8 = 0x22;
    pub const CMD_GET_PAIRED_DEVICES: u8 = 0x4E;
    pub const CMD_SWITCH_AUDIO_CONNECTION: u8 = 0x4F;

    /// Wraps a raw Sony MDR payload in standard framing:
    /// `[START_BYTE (0x0C), Seq, Len, Payload..., Checksum]`
    pub fn build_frame(payload: &[u8], seq: u8) -> Vec<u8> {
        let mut frame = Vec::with_capacity(payload.len() + 4);
        frame.push(Self::START_BYTE);
        frame.push(seq);
        frame.push(payload.len() as u8);
        frame.extend_from_slice(payload);

        // Checksum is the sum of all bytes after the start byte
        let checksum: u8 = frame[1..].iter().fold(0u8, |acc, &b| acc.wrapping_add(b));
        frame.push(checksum);
        frame
    }

    /// Verifies and extracts the inner payload from a framed Sony MDR packet.
    pub fn verify_and_unpack_frame<'a>(frame: &'a [u8]) -> Result<&'a [u8], &'static str> {
        if frame.len() < 4 {
            return Err("Frame too short");
        }
        if frame[0] != Self::START_BYTE {
            return Err("Invalid start byte");
        }
        let len = frame[2] as usize;
        if frame.len() != len + 4 {
            return Err("Length mismatch");
        }

        let expected_checksum = frame[frame.len() - 1];
        let actual_checksum: u8 = frame[1..frame.len() - 1]
            .iter()
            .fold(0u8, |acc, &b| acc.wrapping_add(b));

        if expected_checksum != actual_checksum {
            return Err("Checksum mismatch");
        }

        Ok(&frame[3..3 + len])
    }

    /// Builds the `GetPairedDevices` multipoint query packet.
    pub fn build_query_paired_devices_packet(seq: u8) -> Vec<u8> {
        Self::build_frame(&[Self::CMD_GET_PAIRED_DEVICES, 0x00], seq)
    }

    /// Builds a `SwitchAudioConnection` command packet addressing the target 6-byte Bluetooth MAC.
    pub fn build_switch_connection_packet(seq: u8, target_mac: [u8; 6]) -> Vec<u8> {
        let mut payload = Vec::with_capacity(8);
        payload.push(Self::CMD_SWITCH_AUDIO_CONNECTION);
        payload.push(0x01); // Connect action
        payload.extend_from_slice(&target_mac);
        Self::build_frame(&payload, seq)
    }

    /// Parses a Sony MDR battery response payload.
    /// Expected format: `[CMD_BATTERY_STATUS (0x22), LeftPct, RightPct, CasePct, ChargingFlags]`
    pub fn parse_battery_response(payload: &[u8]) -> Option<HeadphoneBattery> {
        if payload.len() < 4 || payload[0] != Self::CMD_BATTERY_STATUS {
            return None;
        }

        let decode = |b: u8| -> Option<u8> {
            if b <= 100 {
                Some(b)
            } else {
                None
            }
        };

        let left = decode(payload[1]);
        let right = decode(payload[2]);
        let case_level = decode(payload[3]);
        let is_charging = if payload.len() > 4 {
            payload[4] != 0
        } else {
            false
        };

        Some(HeadphoneBattery {
            left,
            right,
            case_level,
            is_charging,
        })
    }
}

impl HeadphoneDriver for SonyDriver {
    fn driver_id(&self) -> &'static str {
        Self::DRIVER_ID
    }

    fn brand_name(&self) -> &'static str {
        Self::BRAND_NAME
    }

    fn can_handle(&self, device_name: &str) -> bool {
        let lower = device_name.to_lowercase();
        lower.contains("wh-1000x")
            || lower.contains("wf-1000x")
            || lower.contains("linkbuds")
            || lower.contains("sony")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sony_driver_matching() {
        let driver = SonyDriver::default();
        assert!(driver.can_handle("WH-1000XM5"));
        assert!(driver.can_handle("WF-1000XM4"));
        assert!(driver.can_handle("Sony LinkBuds S"));
        assert!(!driver.can_handle("AirPods Pro"));
    }

    #[test]
    fn test_sony_frame_packing_and_unpacking() {
        let payload = [0x4E, 0x00];
        let frame = SonyDriver::build_frame(&payload, 1);

        assert_eq!(frame[0], SonyDriver::START_BYTE);
        assert_eq!(frame[1], 1); // seq
        assert_eq!(frame[2], 2); // len
        assert_eq!(&frame[3..5], &payload);

        let unpacked = SonyDriver::verify_and_unpack_frame(&frame).expect("Valid frame");
        assert_eq!(unpacked, &payload);
    }

    #[test]
    fn test_sony_switch_connection_packet() {
        let mac = [0xAA, 0xBB, 0xCC, 0x11, 0x22, 0x33];
        let packet = SonyDriver::build_switch_connection_packet(5, mac);
        let unpacked = SonyDriver::verify_and_unpack_frame(&packet).expect("Valid frame");
        assert_eq!(unpacked[0], SonyDriver::CMD_SWITCH_AUDIO_CONNECTION);
        assert_eq!(unpacked[1], 0x01);
        assert_eq!(&unpacked[2..8], &mac);
    }

    #[test]
    fn test_sony_battery_parsing() {
        let payload = [0x22, 80, 85, 90, 0x01];
        let battery = SonyDriver::parse_battery_response(&payload).expect("Valid battery");
        assert_eq!(battery.left, Some(80));
        assert_eq!(battery.right, Some(85));
        assert_eq!(battery.case_level, Some(90));
        assert!(battery.is_charging);
        assert_eq!(battery.primary_percentage(), 82);
    }
}
