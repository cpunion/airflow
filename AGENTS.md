# AGENTS.md - Developer & Agent Guide

> Guidelines, technical invariants, and architecture context for AI agents and human contributors working on the **AirFlow** codebase.

---

## 1. Project Mission & Invariants

**AirFlow** is a universal, cross-platform audio roaming and device manager for wireless headphones. It bridges the gap between Apple's proprietary seamless handoff and open/third-party platforms (macOS, Linux, Android, iOS, Windows).

### ⚠️ Non-Negotiable Invariants:
1. **Language Convention**: All documentation, commit messages, and **in-code comments must be written in English**.
2. **Gatekeeper Bypass (AirPods Safety)**:
   - If the active system audio output device is an Apple AirPods device (or Beats with Apple H1/H2/W1 chip), the engine **MUST enter Bypass mode** and refrain from dispatching any handoff commands. Apple's native handoff engine already manages AirPods on macOS/iOS.
3. **Strict Whitelisting**:
   - The engine must NEVER send control packets or pause commands to unverified or arbitrary BLE/Bluetooth devices. Target mobile devices must be explicitly confirmed and saved in the user's whitelist.
4. **Anti-Ping-Pong Protection**:
   - An intentional arbitration cooldown (default `1.5s`) must be enforced whenever a pause is dispatched to a peer. Incoming pause notifications from that peer during the cooldown must be ignored to prevent circular playback deadlocks.
5. **Pull Request (PR) Contribution Workflow**:
   - All subsequent updates, features, bugfixes, and documentation changes MUST be developed on dedicated feature/bugfix branches and submitted via Pull Requests (`gh pr create`). Direct pushes to `main` are strictly forbidden.

---

## 2. Directory Structure & Layering

```
AirFlow/
├── docs/
│   └── DESIGN.md                 # Primary architecture & protocol specification
├── AGENTS.md                     # Agent guide (this document)
├── README.md                     # Public project overview & quickstart
├── Package.swift                 # SPM manifest (Swift 6.0+)
├── Sources/
│   └── AirFlow/
│       ├── AirFlowApp.swift      # Entry point & CLI/Menubar bootstrap
│       ├── Core/
│       │   ├── ArbitrationEngine.swift     # State machine & mutual exclusion logic
│       │   ├── Config.swift                # Dynamic .env configuration loader
│       │   ├── DeviceWhitelistManager.swift # Device ID persistence & binding
│       │   └── Models.swift                # Shared models (AudioDevice, PeerDevice, etc.)
│       ├── Drivers/
│       │   ├── HeadphoneDriver.swift       # Protocol definition for headphone drivers
│       │   ├── ShokzDriver.swift           # Bestechnic BES & FC4A GATT implementation
│       │   ├── AirPodsDriver.swift         # AAP L2CAP implementation (for Linux/macOS)
│       │   ├── SonyDriver.swift            # Sony MDR protocol adapter
│       │   └── GenericDriver.swift         # Fallback single/multi-point driver
│       ├── Platform/
│       │   ├── PlatformInterfaces.swift    # AudioDeviceMonitor & MediaObserver protocols
│       │   ├── MacOS/
│       │   │   ├── CoreAudioMonitor.swift  # CoreAudio default output listener
│       │   │   └── MediaRemoteObserver.swift # Private MediaRemote.framework bridge
│       │   ├── Linux/                      # BlueZ D-Bus, PipeWire, and MPRIS adapters
│       │   └── Windows/                    # WASAPI & WinRT GSMTC adapters
│       └── UI/
│           ├── MenubarManager.swift        # macOS NSStatusItem manager
│           └── StatusPopoverView.swift     # SwiftUI battery & device popover
└── Tests/
    └── AirFlowTests/
```

---

## 3. Protocol & Hardware Implementation Reference

### 3.1 Shokz OpenDots 2 (Bestechnic BES Chipset)
- **Fast Pair Service**: `0xFE2C`
  - Model ID Characteristic: `FE2C1233-8366-4814-8EB0-01DE32100BEA` (Read `0x474E85`)
  - Battery Characteristic: `FE2C1239-8366-4814-8EB0-01DE32100BEA` (Left, Right, Case battery)
- **Vendor Control GATT Service**: `0xFC4A`
  - Command TX: `0xFC4C` (Write, WriteWithoutResponse)
  - Telemetry RX: `0xFC4B` (Notify)
- **BES Core Vendor Service**: `01000100-0000-1000-8000-009078563412`
  - Command TX: `03000300-0000-1000-8000-009278563412` (Write)
  - Telemetry RX: `02000200-0000-1000-8000-009178563412` (Notify)

### 3.2 Apple Accessory Protocol (AAP - AirPods on Linux)
- **L2CAP PSM**: `0x1001` (bypasses standard A2DP/AVRCP).
- **Core Features**:
  - Unsolicited packet streaming for in-ear detection (`EarIn` / `EarOut`), lid open/close, and raw battery status.
  - Active Noise Cancellation (ANC) control commands (Off, ANC, Transparency, Adaptive).
- **Reference Projects**:
  - `kavishdevar/librepods` (Linux GUI & daemon)
  - `superninjv/airpods-helper` (Rust D-Bus daemon)
  - `tyalie/AAP-Protocol-Defintion` (Kaitai binary protocol schema)

### 3.3 macOS MediaRemote.framework (Private API)
Dynamic loading via `dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)`:
- `MRMediaRemoteGetNowPlayingApplicationIsPlaying(DispatchQueue, (Bool) -> Void)`: Tests if active media is playing.
- `MRMediaRemoteSendCommand(1 /* kMRPause */, nil)`: Globally pauses media on all running apps (Chrome, Safari, Spotify, Music, etc.).
- `MRMediaRemoteRegisterForNowPlayingNotifications(DispatchQueue)`: Registers for system-wide now-playing change events.

### 3.4 Windows WinRT GSMTC & WASAPI
- **Media Control**: `Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager` (GSMTC)
  - `TryPauseAsync()` / `TryPlayAsync()`: System-wide media pause across Chrome, Edge, Spotify, VLC, YouTube.
  - `PlaybackInfoChanged`: Real-time notification of active media state.
- **Audio Endpoint Monitoring**: `IMMNotificationClient::OnDefaultDeviceChanged` via Windows Core Audio (WASAPI).
- **Bluetooth GATT**: `Windows.Devices.Bluetooth.GenericAttributeProfile` for Fast Pair and vendor services.
- **Reference**: `MagicPods` (established commercial AirPods implementation on Windows).

---

## 4. Build, Run, and Testing Guidelines

```bash
# Build the project
swift build

# Run executable in development mode
swift run AirFlow

# Run unit tests
swift test
```

### Mocking & Hardware Independence:
- When writing tests for `ArbitrationEngine` or `DeviceWhitelistManager`, **never require physical Bluetooth hardware**.
- Inject mock implementations of `AudioDeviceMonitor`, `MediaPlaybackObserver`, and `HeadphoneDriver`.
