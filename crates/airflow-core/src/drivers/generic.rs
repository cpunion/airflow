use super::HeadphoneDriver;

/// Generic fallback driver for standard Bluetooth multipoint and singlepoint headphones.
#[derive(Debug, Default)]
pub struct GenericDriver;

impl GenericDriver {
    pub const DRIVER_ID: &'static str = "driver.generic.bluetooth";
    pub const BRAND_NAME: &'static str = "Generic Bluetooth";
}

impl HeadphoneDriver for GenericDriver {
    fn driver_id(&self) -> &'static str {
        Self::DRIVER_ID
    }

    fn brand_name(&self) -> &'static str {
        Self::BRAND_NAME
    }

    fn can_handle(&self, _device_name: &str) -> bool {
        // Fallback handles any device if explicitly assigned or configured
        true
    }
}
