use super::HeadphoneDriver;
use crate::models::HeadphoneBattery;

/// Active Noise Cancellation (ANC) listening modes supported by Apple AirPods.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AncMode {
    Off = 0x01,
    NoiseCancellation = 0x02,
    Transparency = 0x03,
    Adaptive = 0x04,
}

/// Real-time ear detection state for left and right AirPods.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EarDetectionStatus {
    pub left_in_ear: bool,
    pub right_in_ear: bool,
}

/// Pluggable driver for Apple AirPods and Beats devices using Apple Accessory Protocol (AAP).
#[derive(Debug, Default)]
pub struct AirPodsDriver;

impl AirPodsDriver {
    pub const DRIVER_ID: &'static str = "driver.apple.airpods";
    pub const BRAND_NAME: &'static str = "Apple";

    /// Standard Apple Accessory Protocol (AAP) L2CAP Protocol/Service Multiplexer.
    pub const AAP_L2CAP_PSM: u16 = 0x1001;

    /// AAP Opcode for In-Ear detection telemetry.
    pub const AAP_OPCODE_IN_EAR_STATUS: u8 = 0x01;
    /// AAP Opcode for Battery status telemetry.
    pub const AAP_OPCODE_BATTERY_STATUS: u8 = 0x04;
    /// AAP Opcode for ANC / Transparency mode toggle.
    pub const AAP_OPCODE_ANC_CONTROL: u8 = 0x0D;

    /// Builds an AAP packet to toggle ANC mode.
    /// Format: [Length (LE u16), Opcode, Mode]
    pub fn build_anc_command(mode: AncMode) -> Vec<u8> {
        vec![0x02, 0x00, Self::AAP_OPCODE_ANC_CONTROL, mode as u8]
    }

    /// Parses an AAP In-Ear detection frame.
    /// Expected format: [Length (u16), Opcode (0x01), LeftStatus (0x01=in, 0x00=out), RightStatus (0x01=in, 0x00=out)]
    pub fn parse_in_ear_status(payload: &[u8]) -> Option<EarDetectionStatus> {
        if payload.len() < 4 || payload[2] != Self::AAP_OPCODE_IN_EAR_STATUS {
            return None;
        }

        let left_in_ear = payload[3] == 0x01;
        let right_in_ear = if payload.len() > 4 {
            payload[4] == 0x01
        } else {
            left_in_ear
        };

        Some(EarDetectionStatus {
            left_in_ear,
            right_in_ear,
        })
    }

    /// Parses an AAP Battery telemetry frame.
    /// Expected format: [Length (u16), Opcode (0x04), LeftPct (0-100), RightPct (0-100), CasePct (0-100), Flags]
    pub fn parse_battery_status(payload: &[u8]) -> Option<HeadphoneBattery> {
        if payload.len() < 6 || payload[2] != Self::AAP_OPCODE_BATTERY_STATUS {
            return None;
        }

        let decode = |b: u8| -> Option<u8> {
            if b <= 100 {
                Some(b)
            } else {
                None
            }
        };

        let left = decode(payload[3]);
        let right = decode(payload[4]);
        let case_level = decode(payload[5]);
        let is_charging = if payload.len() > 6 {
            payload[6] & 0x01 != 0
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

impl HeadphoneDriver for AirPodsDriver {
    fn driver_id(&self) -> &'static str {
        Self::DRIVER_ID
    }

    fn brand_name(&self) -> &'static str {
        Self::BRAND_NAME
    }

    fn can_handle(&self, device_name: &str) -> bool {
        let lower = device_name.to_lowercase();
        lower.contains("airpods")
            || lower.contains("beats fit pro")
            || lower.contains("beats studio")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_airpods_driver_matching() {
        let driver = AirPodsDriver::default();
        assert!(driver.can_handle("AirPods Pro"));
        assert!(driver.can_handle("AirPods Max"));
        assert!(driver.can_handle("Beats Fit Pro"));
        assert!(!driver.can_handle("OpenDots 2"));
    }

    #[test]
    fn test_airpods_anc_command_builder() {
        let cmd = AirPodsDriver::build_anc_command(AncMode::NoiseCancellation);
        assert_eq!(cmd, vec![0x02, 0x00, 0x0D, 0x02]);

        let trans_cmd = AirPodsDriver::build_anc_command(AncMode::Transparency);
        assert_eq!(trans_cmd, vec![0x02, 0x00, 0x0D, 0x03]);
    }

    #[test]
    fn test_airpods_in_ear_parser() {
        // [Len, Len, Opcode 0x01, Left In-Ear (1), Right Out-of-Ear (0)]
        let payload = [0x03, 0x00, 0x01, 0x01, 0x00];
        let status = AirPodsDriver::parse_in_ear_status(&payload).expect("Valid in-ear payload");
        assert!(status.left_in_ear);
        assert!(!status.right_in_ear);
    }

    #[test]
    fn test_airpods_battery_parser() {
        // [Len, Len, Opcode 0x04, Left 90%, Right 95%, Case 100%, Flags: Charging (1)]
        let payload = [0x05, 0x00, 0x04, 90, 95, 100, 0x01];
        let battery = AirPodsDriver::parse_battery_status(&payload).expect("Valid battery payload");
        assert_eq!(battery.left, Some(90));
        assert_eq!(battery.right, Some(95));
        assert_eq!(battery.case_level, Some(100));
        assert!(battery.is_charging);
        assert_eq!(battery.primary_percentage(), 92);
    }
}
