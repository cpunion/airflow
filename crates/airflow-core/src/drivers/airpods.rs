use super::HeadphoneDriver;

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
}
