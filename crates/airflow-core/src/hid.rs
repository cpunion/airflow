//! Consumer-control reports for the opt-in Classic HID validation tool.
//! Transport success does not establish that a phone acted on a report.

pub const REPORT_ID: u8 = 7;

// A distinct report ID prevents confusion with the old Play/Pause-only report.
// It does not guarantee that a host refreshes its cached descriptor.
pub const REPORT_DESCRIPTOR: &[u8] = &[
    0x05, 0x0C, // Usage Page (Consumer)
    0x09, 0x01, // Usage (Consumer Control)
    0xA1, 0x01, // Collection (Application)
    0x85, REPORT_ID, 0x15, 0x00, // Logical Minimum (0)
    0x25, 0x01, // Logical Maximum (1)
    0x09, 0xB1, // Pause, independent of playback state
    0x09, 0xCD, // Play/Pause toggle, manual diagnostic only
    0x75, 0x01, // Report Size (1 bit)
    0x95, 0x02, // Report Count (2)
    0x81, 0x02, // Input (Data, Variable, Absolute)
    0x75, 0x06, // Six padding bits
    0x95, 0x01, 0x81, 0x03, // Input (Constant)
    0xC0,
];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ConsumerKey {
    Pause,
    PlayPause,
    Released,
}

pub fn input_report(key: ConsumerKey) -> [u8; 3] {
    let bits = match key {
        ConsumerKey::Pause => 1,
        ConsumerKey::PlayPause => 2,
        ConsumerKey::Released => 0,
    };
    [0xA1, REPORT_ID, bits]
}

#[derive(Debug, PartialEq, Eq)]
pub enum ControlAction {
    Reply(Vec<u8>),
    Suspend,
    Resume,
    Unplug,
    Ignore,
}

/// Handle the report-only HIDP subset used by this diagnostic device.
pub fn control_request(request: &[u8], current: ConsumerKey) -> ControlAction {
    use ControlAction::*;
    let Some(&header) = request.first() else {
        return Ignore;
    };
    match header {
        // A handshake is a response, not a request. Never answer it with another
        // handshake, which could turn a peer error into a protocol reply loop.
        0x00..=0x0F => Ignore,
        0x13 if request.len() == 1 => Suspend,
        0x14 if request.len() == 1 => Resume,
        0x15 if request.len() == 1 => Unplug,
        0x60 if request.len() == 1 => Reply(vec![0xA0, 1]),
        0x71 if request.len() == 1 => Reply(vec![0]),
        0x41 | 0x49 => {
            let expected = if header == 0x49 { 4 } else { 2 };
            if request.len() != expected {
                return Reply(vec![4]); // Invalid parameter.
            }
            if request[1] != REPORT_ID {
                return Reply(vec![2]); // Invalid report ID.
            }
            if header == 0x49 && u16::from_le_bytes([request[2], request[3]]) < 2 {
                return Reply(vec![4]);
            }
            Reply(input_report(current).to_vec())
        }
        // Boot protocol, output/feature reports, and idle requests are unsupported.
        _ => Reply(vec![3]),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pause_toggle_and_release_have_distinct_bits() {
        assert_eq!(input_report(ConsumerKey::Pause), [0xA1, 7, 1]);
        assert_eq!(input_report(ConsumerKey::PlayPause), [0xA1, 7, 2]);
        assert_eq!(input_report(ConsumerKey::Released), [0xA1, 7, 0]);
        assert!(REPORT_DESCRIPTOR
            .windows(4)
            .any(|b| b == [0x09, 0xB1, 0x09, 0xCD]));
    }

    #[test]
    fn get_report_returns_current_input_and_rejects_bad_requests() {
        use ControlAction::Reply;
        assert_eq!(
            control_request(&[0x41, 7], ConsumerKey::Pause),
            Reply(vec![0xA1, 7, 1])
        );
        assert_eq!(
            control_request(&[0x49, 7, 2, 0], ConsumerKey::Released),
            Reply(vec![0xA1, 7, 0])
        );
        for request in [&[0x41][..], &[0x49, 7], &[0x49, 7, 1, 0]] {
            assert_eq!(
                control_request(request, ConsumerKey::Released),
                Reply(vec![4])
            );
        }
        assert_eq!(
            control_request(&[0x41, 1], ConsumerKey::Released),
            Reply(vec![2])
        );
        assert_eq!(
            control_request(&[0x42, 7], ConsumerKey::Released),
            Reply(vec![3])
        );
    }

    #[test]
    fn only_report_protocol_is_supported() {
        assert_eq!(
            control_request(&[0x60], ConsumerKey::Released),
            ControlAction::Reply(vec![0xA0, 1])
        );
        assert_eq!(
            control_request(&[0x71], ConsumerKey::Released),
            ControlAction::Reply(vec![0])
        );
        assert_eq!(
            control_request(&[0x70], ConsumerKey::Released),
            ControlAction::Reply(vec![3])
        );
    }

    #[test]
    fn lifecycle_requests_are_not_media_commands() {
        assert_eq!(
            control_request(&[], ConsumerKey::Released),
            ControlAction::Ignore
        );
        assert_eq!(
            control_request(&[0x13], ConsumerKey::Released),
            ControlAction::Suspend
        );
        assert_eq!(
            control_request(&[0x14], ConsumerKey::Released),
            ControlAction::Resume
        );
        assert_eq!(
            control_request(&[0x15], ConsumerKey::Released),
            ControlAction::Unplug
        );
        assert_eq!(
            control_request(&[0x15, 0], ConsumerKey::Released),
            ControlAction::Reply(vec![3])
        );
        for status in 0..=15 {
            assert_eq!(
                control_request(&[status], ConsumerKey::Released),
                ControlAction::Ignore
            );
        }
    }
}
