use super::HeadphoneDriver;

/// State transitions for single-point Bluetooth earbud connection roaming.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum RoamingState {
    /// Inactive or settled connection.
    #[default]
    Idle,
    /// Dispatched disconnect request to mobile peer to free the single ACL link.
    RequestingPeerDisconnect,
    /// Waiting for host Bluetooth controller to page and claim the incoming ACL connection.
    PagingLocalAcl,
    /// Successfully roamed and connected to the target host.
    Completed,
    /// Roaming timed out or was rejected by the controller.
    Failed,
}

/// Coordinates dynamic connection roaming for single-point headphones without hardware multipoint.
#[derive(Debug, Default)]
pub struct RoamingCoordinator {
    state: RoamingState,
}

impl RoamingCoordinator {
    pub fn new() -> Self {
        Self {
            state: RoamingState::Idle,
        }
    }

    pub fn current_state(&self) -> RoamingState {
        self.state
    }

    /// Triggers roaming towards the local host.
    pub fn begin_roaming(&mut self) -> RoamingState {
        self.state = RoamingState::RequestingPeerDisconnect;
        self.state
    }

    /// Called when confirmation is received that the peer dropped its ACL link.
    pub fn on_peer_disconnected(&mut self) -> RoamingState {
        if self.state == RoamingState::RequestingPeerDisconnect {
            self.state = RoamingState::PagingLocalAcl;
        }
        self.state
    }

    /// Called when local host finishes connecting to the headphone.
    pub fn on_local_connected(&mut self) -> RoamingState {
        if self.state == RoamingState::PagingLocalAcl {
            self.state = RoamingState::Completed;
        }
        self.state
    }

    /// Resets the coordinator back to idle.
    pub fn reset(&mut self) {
        self.state = RoamingState::Idle;
    }
}

/// Generic fallback driver for standard Bluetooth multipoint and singlepoint headphones.
#[derive(Debug, Default)]
pub struct GenericDriver {
    pub coordinator: RoamingCoordinator,
}

impl GenericDriver {
    pub const DRIVER_ID: &'static str = "driver.generic.bluetooth";
    pub const BRAND_NAME: &'static str = "Generic Bluetooth";

    pub fn can_roam_to(current: &str, target: &str) -> bool {
        !current.is_empty() && !target.is_empty() && current != target
    }
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_roaming_lifecycle() {
        let mut coordinator = RoamingCoordinator::new();
        assert_eq!(coordinator.current_state(), RoamingState::Idle);

        assert_eq!(coordinator.begin_roaming(), RoamingState::RequestingPeerDisconnect);
        assert_eq!(coordinator.on_peer_disconnected(), RoamingState::PagingLocalAcl);
        assert_eq!(coordinator.on_local_connected(), RoamingState::Completed);

        coordinator.reset();
        assert_eq!(coordinator.current_state(), RoamingState::Idle);
    }
}
