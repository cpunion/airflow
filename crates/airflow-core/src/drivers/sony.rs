use super::HeadphoneDriver;

/// Pluggable driver for Sony wireless headphones using the Sony MDR protocol
/// (e.g. WH-1000XM4, WH-1000XM5, WF-1000XM4, WF-1000XM5, LinkBuds).
#[derive(Debug, Default)]
pub struct SonyDriver;

impl SonyDriver {
    pub const DRIVER_ID: &'static str = "driver.sony.mdr";
    pub const BRAND_NAME: &'static str = "Sony";

    /// Sony MDR Service UUID
    pub const SONY_MDR_SERVICE_UUID: &'static str = "00001101-0000-1000-8000-00805F9B34FB";
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
}
