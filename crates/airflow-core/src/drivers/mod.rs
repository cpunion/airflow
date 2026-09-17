pub mod airpods;
pub mod generic;
pub mod shokz;
pub mod sony;

pub use airpods::AirPodsDriver;
pub use generic::GenericDriver;
pub use shokz::ShokzDriver;
pub use sony::SonyDriver;

/// Pluggable driver interface for wireless headphones and earbuds.
pub trait HeadphoneDriver: Send + Sync {
    /// Unique driver identifier (e.g., "driver.shokz.opendots", "driver.apple.airpods").
    fn driver_id(&self) -> &'static str;

    /// User-visible brand name.
    fn brand_name(&self) -> &'static str;

    /// Inspects a discovered Bluetooth device name and determines if this driver can handle it.
    fn can_handle(&self, device_name: &str) -> bool;
}
