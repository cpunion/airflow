use super::HeadphoneDriver;

/// Pluggable driver for Shokz and Bestechnic (BES) chipset headphones
/// (e.g. OpenDots 2, OpenRun Pro, OpenFit).
#[derive(Debug, Default)]
pub struct ShokzDriver;

impl ShokzDriver {
    pub const DRIVER_ID: &'static str = "driver.shokz.opendots";
    pub const BRAND_NAME: &'static str = "Shokz";

    // Google Fast Pair Service
    pub const FAST_PAIR_SERVICE_UUID: u16 = 0xFE2C;
    pub const MODEL_ID_CHAR_UUID: &'static str = "FE2C1233-8366-4814-8EB0-01DE32100BEA";
    pub const BATTERY_CHAR_UUID: &'static str = "FE2C1239-8366-4814-8EB0-01DE32100BEA";

    // Vendor Control GATT Service
    pub const VENDOR_SERVICE_UUID: u16 = 0xFC4A;
    pub const VENDOR_CMD_TX_CHAR_UUID: u16 = 0xFC4C;
    pub const VENDOR_NOTIFY_RX_CHAR_UUID: u16 = 0xFC4B;

    // BES Core Vendor Service
    pub const BES_CORE_SERVICE_UUID: &'static str = "01000100-0000-1000-8000-009078563412";
    pub const BES_CMD_TX_CHAR_UUID: &'static str = "03000300-0000-1000-8000-009278563412";
    pub const BES_NOTIFY_RX_CHAR_UUID: &'static str = "02000200-0000-1000-8000-009178563412";

    /// Builds a vendor GATT command packet to query paired multipoint devices.
    pub fn build_query_paired_devices_packet() -> Vec<u8> {
        // Opcode 0x05, Sub-command 0x01 (Query Multipoint Device Table)
        vec![0xAA, 0x55, 0x05, 0x01, 0x00, 0x06]
    }
}

impl HeadphoneDriver for ShokzDriver {
    fn driver_id(&self) -> &'static str {
        Self::DRIVER_ID
    }

    fn brand_name(&self) -> &'static str {
        Self::BRAND_NAME
    }

    fn can_handle(&self, device_name: &str) -> bool {
        let lower = device_name.to_lowercase();
        lower.contains("shokz")
            || lower.contains("opendots")
            || lower.contains("openfit")
            || lower.contains("openrun")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_shokz_driver_matching() {
        let driver = ShokzDriver::default();
        assert!(driver.can_handle("OpenDots 2 by Shokz"));
        assert!(driver.can_handle("OpenFit Air"));
        assert!(driver.can_handle("Shokz OpenRun Pro"));
        assert!(!driver.can_handle("Sony WH-1000XM5"));
        assert!(!driver.can_handle("AirPods Pro"));
    }
}
