# Mobile compatibility and macOS / iPhone validation

Updated: 2026-09-19. Status: experimental; no end-to-end iPhone pause result has been confirmed.

## Product scope and recommendation

Keep installation simple: a desktop app with an Add Phone wizard, an optional Android companion for enhanced coordination, and no mandatory iOS companion. External USB / ESP32 / nRF52 hardware is out of scope. Test Classic HID first; virtual A2DP / AVRCP is the second, lower-priority software experiment.

Compatibility is a property of a tested combination of desktop OS, phone OS, player, headphone model, and firmware, not a brand-wide promise:

| Tier | Required evidence | User-visible behavior |
| --- | --- | --- |
| Enhanced | Peer state observation, explicit pause, actual audio transfer, and reconnect verified in both directions | Automatic bidirectional coordination for the tested combination |
| Basic | Explicit non-toggle pause works in playing, paused, and idle states; reconnect and headphone transfer verified | One-way coordination; peer state may be unknown |
| Manual | Automated control unavailable or unverified | Available device/battery information and manual switching |
| Native bypass | Apple-managed AirPods / Beats output | Do not compete with Apple's handoff |

These are acceptance criteria, not current support claims. A transport ACK, successful write, or unit test alone cannot award Basic or Enhanced compatibility. Never automatically substitute Play/Pause for Pause when the phone's playback state is unknown.

## What a phone app improves

### Android: valuable, with explicit user authorization

An enabled notification-listener app can obtain active media controllers and observe media sessions. It can request an explicit pause via transport controls. This avoids depending on each headphone vendor's private control protocol and can provide peer playback state for bidirectional arbitration. An ordinary app must guide the user through notification-access approval; declaring the privileged `MEDIA_CONTENT_CONTROL` permission is not a substitute. Only players exposing suitable sessions and honoring requests are covered. See [MediaSessionManager](https://developer.android.com/reference/android/media/session/MediaSessionManager) and [TransportControls.pause](https://developer.android.com/reference/android/media/session/MediaController.TransportControls#pause()).

For sustained BLE operation, assess CompanionDeviceService / device presence or a connected-device foreground service. Process lifetime, Android background restrictions, and vendor power policies still need testing. Notification access and background execution are separate concerns. See [Android BLE background guidance](https://developer.android.com/develop/connectivity/bluetooth/ble/background).

Recommended onboarding: install once, explicitly approve the desktop identity, grant notification access with a privacy explanation, then run a guided pause test. Do not require root, ADB, or developer mode. Request extra battery-policy changes only when diagnostics establish the need.

### iOS: useful assistance, not universal media authority

An iOS app can assist with onboarding, authenticated messaging, diagnostics, and documented accessory operations. It can control its own media. Apple's MPRemoteCommandCenter receives commands for the app's own handlers; it is not a public interface for pausing arbitrary other apps. A companion alone therefore does not establish universal Spotify / video / browser control or global playback observation. See [MPRemoteCommandCenter](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter).

Core Bluetooth background modes allow selected Bluetooth events to wake an app, but do not guarantee permanent execution or grant cross-app media control. See [Core Bluetooth background processing](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html).

Keep the iOS companion optional unless a specific, tested accessory capability justifies it. It does not remove the need to validate Classic HID. Do not use silent-audio or forced audio-session interruption tricks as pause implementations. A PWA, BLE notification, HTTP message, or Shortcut URL does not by itself establish unattended, background, cross-app pause support.

## Cross-platform obstacles

- A shared Rust engine does not make Bluetooth peripheral/profile availability identical across macOS, Linux, and Windows. Each transport requires its own OS, adapter, driver, permission, packaging, and reconnect validation.
- Phone media pause and headphone audio transfer are separate outcomes. A successful pause does not prove the headphone selects the desktop stream.
- Multipoint arbitration, connection limits, call priority, vendor commands, and firmware differ. Test specific models. Single-point reconnect is a separate, more disruptive path.
- Desktop media observers have coverage limits. The current macOS path uses private MediaRemote APIs; OS updates and distribution policy remain risks.
- Production dispatch paths still include placeholders. This diagnostic is not connected to automatic handoff. Existing mock tests do not establish system-wide media control or three-OS product readiness.

## Evidence on this Mac

Environment: macOS 26.2 (25C56), Apple Silicon, Swift 6.3.3. No phone pairing was erased; no mobile media command was sent during the new diagnostic runs below.

| Check | Result | Evidence / limitation |
| --- | --- | --- |
| Rust regression suite | Passed | 24 tests, including 4 new HID codec tests |
| Swift regression suite | Passed | 22 tests; code-level / mock checks, not phone media validation |
| Probe compilation | Passed | `swift build --product AirFlowHIDProbe` |
| Classic HID local publication | Passed | Service handle obtained, status 0; removal status 0 |
| Inquiry / discovery | Partial | Start status 0; one unrelated device found in the first run; both 15-second and 30-second runs reached their deadline and were stopped; no discoverable iPhone observed |
| Exact-target safety | Passed locally | `pause`, `toggle-confirmed`, and `connect` refused before authorization; malformed address refused; no packets queued |
| Known iPhone in paired-device table | Present | Not application whitelist consent or a fresh-pair test |
| Native scan / pairing UI | Compiles, not exercised | `--pair-ui` uses IOBluetoothUI; never-paired iPhone test pending |
| Independent Pause `0xB1` on iPhone | Pending | Requires selected target and actual player-state observations |
| Paused / idle must not start playing | Pending | Separate acceptance cases |
| Reconnect and pause again | Pending | Must verify media effect, not just channels |
| Locked-screen / background / sleep recovery | Pending | Not inferred from foreground behavior |
| Actual multipoint headphone transfer | Pending | Pause or channel success does not prove audible transfer |

Earlier ad-hoc investigation opened HID control (PSM 0x11) and interrupt (PSM 0x13) channels to the already-paired iPhone and returned success for a Play/Pause write. Actual playback was not confirmed. Those results are transport-only, not a pass for this probe's new Pause descriptor.

The earlier A2DP Sink publication failed; bluetoothd reported a PSM 0x19 registration conflict. An AVRCP publication object was inconclusive because an existing system service was involved. Do not advertise option two as working, replace system services, or infer Linux / Windows failure from this macOS result. It remains lower priority.

The earlier Class-of-Device write returned success without the expected readback. That is not proof that Mac-initiated pairing is impossible. Apple's [IOBluetoothDevicePair](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevicepair) supports application-driven pairing and custom UI; the SDK also exposes IOBluetoothPairingController, used by this diagnostic.

## Run the diagnostic

This developer tool is not the final installation flow. Production should bundle its core and expose a native wizard; end users should not need terminals, Rust, or Swift.

```sh
# Build and check local SDP publication only; no target selected.
sh scripts/test_ios_hid.sh --local

# Read-only device enumeration / discovery.
sh scripts/test_ios_hid.sh --list
sh scripts/test_ios_hid.sh --scan

# Optional first-time pairing: select the phone and compare / accept codes.
# Existing pairings are not removed; control consent is separate.
sh scripts/test_ios_hid.sh --pair-ui

# Interactive validation; initially no target authorized.
sh scripts/test_ios_hid.sh
```

Keep iPhone Settings > Bluetooth open during discovery / pairing. In the interactive prompt:

```text
authorize AA:BB:CC:DD:EE:FF
connect
observe Music, playing, unlocked, headphones connected
pause
observe Music, paused, confirmed on phone
disconnect
connect
quit
```

Replace the address with the explicitly confirmed phone's paired address. The diagnostic saves it in the separate `org.airflow.hid-validation` preferences domain, checks exact identity, and never uses name matching. Each process requires `authorize`; it does not silently reuse saved consent. Pairing UI success does not grant media-control consent automatically.

Wait at least five seconds after both channels open. This grace period is not proof of descriptor acceptance. Received control requests and asynchronous write completions are logged separately. All HID report/descriptor bytes and HIDP replies originate in Rust. Swift handles OS transport. The subprocess codec boundary is for diagnostics; production should use the C ABI.

Pause uses Consumer Usage 0xB1; toggle uses 0xCD. Report ID 7 differs from the earlier probe but does not guarantee iOS cache invalidation. If caching is suspected, record it; do not erase pairing without approval. `toggle-confirmed` is a manual comparison command that can start playback, never an automatic fallback.

Key-down is followed by release. A 1.5-second minimum interval and pending-write guard prevent overlapping presses. Apple AirPods / Beats output, unknown output, missing consent, missing channels, and suspension block key-down. `quit`, SIGINT, and SIGTERM close only probe channels and remove its temporary record; they do not erase pairing or disconnect the entire device. Manual observations are operator reports, not independently measured telemetry.

## Remaining phone acceptance sequence

1. Confirm phone identity and player. Start known media manually; send one Pause and record both transport status and visible / audible phone state.
2. Leave the same player paused; send Pause again and verify it stays paused.
3. Stop / close media; send Pause and verify no player or stale session starts.
4. Repeat with another commonly used player and with the phone locked.
5. Disconnect only probe channels, reconnect without re-pairing, manually start media, and verify Pause again. Also test app restart and desktop sleep/wake.
6. With a specific multipoint headphone connected to both devices, verify desktop audio becomes audible after phone pause. Record model and firmware.
7. On a never-paired phone, use the wizard, compare codes, save explicit consent, and repeat. An already-paired phone cannot establish this result; resetting its pairing requires approval.

Record OS builds, player version, headphone/firmware, report type, initial state, write status, observed final state, and repetitions. Do not commit full Bluetooth addresses or unrelated discovered-device identities.
