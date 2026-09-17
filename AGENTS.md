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
├── Cargo.toml                    # Rust workspace manifest
├── Package.swift                 # SPM manifest (Swift 6.0+)
├── crates/
│   ├── airflow-core/             # Rust arbitration engine & C-ABI library
│   │   ├── include/airflow_core.h # Public C-ABI header
│   │   └── src/
│   │       ├── arbitration.rs    # Core state machine & mutual exclusion
│   │       ├── whitelist.rs      # Device whitelist & persistence
│   │       ├── models.rs         # Shared domain models
│   │       ├── drivers/          # Driver implementations (Shokz, AirPods, Sony, Generic)
│   │       └── ffi.rs            # C-ABI export layer for Swift / WinUI / GTK
│   └── airflow-cli/              # Zero-dependency Rust CLI & background daemon
│       └── src/main.rs
├── Sources/
│   └── AirFlow/
│       ├── AirFlowApp.swift      # Entry point & CLI/Menubar bootstrap
│       ├── Core/
│       │   ├── ArbitrationEngine.swift     # State machine & mutual exclusion logic
│       │   ├── RustEngineBridge.swift      # Dynamic C-ABI bridge to airflow-core
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

## 3. Division of Responsibilities: Rust Core vs. Platform Layers

To maintain absolute cross-platform parity and avoid logic divergence, code responsibilities are strictly separated between **Rust Core** and **Platform Layers**:

### 🦀 What Lives in Rust (`crates/airflow-core`):
1. **Arbitration State Machine & Engine**:
   - `ArbitrationEngine`: Central finite state machine (`Idle`, `Bypassed`, `HostActive`, `PeerActive`, `Cooldown`).
   - Anti-ping-pong cooldown timers and mutual exclusion.
   - Gatekeeper bypass logic (Apple AirPods on macOS/iOS bypass, Android peer detection, speaker bypass).
2. **Whitelist Management & Security Rules**:
   - `DeviceWhitelistManager`: Target device verification, paired device table matching, and whitelist persistence.
   - Enforces the strict whitelisting invariant before dispatching any pause command.
3. **Wire Protocol Encoders & Decoders (Hardware Driver Logic)**:
   - All byte-level packet framing, serialization, and parsing:
     - Bestechnic (BES) / Shokz command packets (`pause_packet`, query device table).
     - Google Fast Pair battery packet decoding (`parse_fast_pair_battery`).
     - Apple Accessory Protocol (AAP) L2CAP frame codecs.
     - Sony MDR packet framing.
   - *Why*: Wire protocols are 100% platform-agnostic. Implementing them once in Rust guarantees bug-free parity across macOS, Linux, and Windows.
4. **Dispatch Policy**:
   - Deciding between Headphone GATT, BLE Remote, and Local Network based on device type and availability.
5. **C-ABI Export Layer (`ffi.rs`, `include/airflow_core.h`)**:
   - Clean C functions allowing Swift, C, Python, or C# to drive the core engine.

---

### 🍏 / 🐧 / 🪟 What Lives in Platform Layers (macOS, Linux, Windows):
1. **OS Audio Subsystem Integration (I/O)**:
   - macOS: CoreAudio HAL (`AudioObjectGetPropertyData` / `AudioObjectSetPropertyData` for default audio output switching and device enumeration).
   - Linux: PipeWire / PulseAudio via `libpipewire` / `pactl` / D-Bus.
   - Windows: WASAPI (`IMMDeviceEnumerator` / `IMMNotificationClient`).
2. **OS Media Playback Observers**:
   - macOS: `MediaRemote.framework` (`MRMediaRemoteGetNowPlayingApplicationIsPlaying` / `MRMediaRemoteSendCommand`).
   - Linux: MPRIS D-Bus (`org.mpris.MediaPlayer2.Player`).
   - Windows: WinRT GSMTC (`GlobalSystemMediaTransportControlsSessionManager`).
3. **OS Bluetooth Transport (I/O Only)**:
   - macOS: `CoreBluetooth` (`CBCentralManager`, `CBPeripheral`, `CBPeripheralManager`).
   - Linux: BlueZ D-Bus + L2CAP sockets.
   - Windows: `Windows.Devices.Bluetooth.GenericAttributeProfile`.
   - *Rule*: Platform Bluetooth layers perform only connection management and raw byte I/O. They pass received bytes into Rust for decoding and write bytes generated by Rust onto the GATT characteristic.
4. **OS Lifecycle & System Services**:
   - macOS: `ServiceManagement` (`SMAppService`) for Launch-at-Login.
   - Linux: `systemd --user` unit.
   - Windows: Task Scheduler or Run registry key.
5. **Native UI & Menubar**:
   - macOS: `NSStatusItem` + SwiftUI Popover (`MenubarManager`, `StatusPopoverView`).
   - Linux: AppIndicator / GNOME shell extension / Waybar module.
   - Windows: WinUI 3 / Modern Flyout taskbar tray app.

---

## 4. Protocol & Hardware Implementation Reference

### 4.1 Shokz OpenDots 2 (Bestechnic BES Chipset)
- **Fast Pair Service**: `0xFE2C`
  - Model ID Characteristic: `FE2C1233-8366-4814-8EB0-01DE32100BEA` (Read `0x474E85`)
  - Battery Characteristic: `FE2C1239-8366-4814-8EB0-01DE32100BEA` (Left, Right, Case battery)
- **Vendor Control GATT Service**: `0xFC4A`
  - Command TX: `0xFC4C` (Write, WriteWithoutResponse)
  - Telemetry RX: `0xFC4B` (Notify)
- **BES Core Vendor Service**: `01000100-0000-1000-8000-009078563412`
  - Command TX: `03000300-0000-1000-8000-009278563412` (Write)
  - Telemetry RX: `02000200-0000-1000-8000-009178563412` (Notify)

### 4.2 Apple Accessory Protocol (AAP - AirPods on Linux)
- **L2CAP PSM**: `0x1001` (bypasses standard A2DP/AVRCP).
- **Core Features**:
  - Unsolicited packet streaming for in-ear detection (`EarIn` / `EarOut`), lid open/close, and raw battery status.
  - Active Noise Cancellation (ANC) control commands (Off, ANC, Transparency, Adaptive).
- **Reference Projects**:
  - `kavishdevar/librepods` (Linux GUI & daemon)
  - `superninjv/airpods-helper` (Rust D-Bus daemon)
  - `tyalie/AAP-Protocol-Defintion` (Kaitai binary protocol schema)

### 4.3 macOS MediaRemote.framework (Private API)
Dynamic loading via `dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW)`:
- `MRMediaRemoteGetNowPlayingApplicationIsPlaying(DispatchQueue, (Bool) -> Void)`: Tests if active media is playing.
- `MRMediaRemoteSendCommand(1 /* kMRPause */, nil)`: Globally pauses media on all running apps (Chrome, Safari, Spotify, Music, etc.).
- `MRMediaRemoteRegisterForNowPlayingNotifications(DispatchQueue)`: Registers for system-wide now-playing change events.

### 4.4 Windows WinRT GSMTC & WASAPI
- **Media Control**: `Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager` (GSMTC)
  - `TryPauseAsync()` / `TryPlayAsync()`: System-wide media pause across Chrome, Edge, Spotify, VLC, YouTube.
  - `PlaybackInfoChanged`: Real-time notification of active media state.
- **Audio Endpoint Monitoring**: `IMMNotificationClient::OnDefaultDeviceChanged` via Windows Core Audio (WASAPI).
- **Bluetooth GATT**: `Windows.Devices.Bluetooth.GenericAttributeProfile` for Fast Pair and vendor services.
- **Reference**: `MagicPods` (established commercial AirPods implementation on Windows).

---

## 5. Build, Run, and Testing Guidelines

### Rust Core & CLI:
```bash
# Build Rust workspace (Core + CLI)
cargo build --release

# Run Rust unit tests
cargo test --workspace

# Run Rust CLI daemon
cargo run -p airflow-cli -- daemon
```

### macOS Swift App & SPM:
```bash
# Build Swift project
swift build

# Run executable in development mode
swift run AirFlow

# Run unit tests (including Rust FFI bridge tests)
swift test
```

### Mocking & Hardware Independence:
- When writing tests for `ArbitrationEngine` or `DeviceWhitelistManager`, **never require physical Bluetooth hardware**.
- Inject mock implementations of `AudioDeviceMonitor`, `MediaPlaybackObserver`, and `HeadphoneDriver`.
