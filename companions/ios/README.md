# AirFlow iOS Companion Status

There is currently no validated iOS companion implementation that pauses arbitrary
other media apps. The former BLE / Shortcut / webhook instructions described
unverified proposals, not a working installation guide.

The preferred experiment is a desktop-only Classic Bluetooth HID remote, with
explicit phone consent and an independent Pause report. Real playback effects,
first-time pairing, and reconnect behavior still require iPhone validation.

An optional iOS app could improve onboarding, authenticated messaging, diagnostics,
and documented accessory integration. It does not gain general cross-app playback
control: [MPRemoteCommandCenter](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter)
handles remote commands for an app's own player. Background BLE support does not
change that media-permission boundary.

See [Mobile compatibility and validation](../../docs/MOBILE_COMPATIBILITY_AND_VALIDATION.md)
for tiers, the Android companion recommendation, evidence, and diagnostic usage.
Apple-managed AirPods / Beats output remains subject to Gatekeeper bypass.
