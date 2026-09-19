# AirFlow

> Universal, intelligent audio handoff and device manager for wireless headphones across macOS, Linux, Windows, Android, and iOS.
> **Goal: seamless switching for third-party headphones, with compatibility tiers based on tested device combinations.**

Current status: experimental. App-free iPhone pause and bidirectional handoff are
not yet verified end to end. See the [compatibility and validation record](docs/MOBILE_COMPATIBILITY_AND_VALIDATION.md)
for measured results, mobile companion limits, and outstanding phone tests.

---

## 🚀 Overview

Standard Bluetooth Multipoint headphones (such as Shokz OpenDots 2, Sony WH/WF series, and Bose QuietComfort) utilize a rigid **"First-Come, First-Served"** audio routing model:
- If your phone is playing music, video on your computer has no audio until you pull out your phone and manually pause.
- If your computer is playing video, your phone cannot preempt it.

**AirFlow** aims to address this with a bidirectional arbitration layer between your computer and mobile devices. The following describes target behavior, not uniformly available capabilities:
1. **Play on Computer ➔ Phone Automatically Pauses ➔ Headphone output transitions seamlessly**.
2. **Play on Phone ➔ Computer Automatically Pauses ➔ Headphone output transitions seamlessly**.
3. **Gatekeeper Bypass**: Automatically detects native AirPods and gracefully steps aside, preventing conflicts with Apple's built-in ecosystem handoff.
4. **Driver Plugin Architecture**: Designed to support Shokz, AirPods (including Linux reverse-engineered AAP support), Sony MDR, Bose, and generic single-point Bluetooth headphones.
5. **Cross-Platform Parity**: Architectural support for macOS (CoreAudio + MediaRemote), Linux (PipeWire + MPRIS), and Windows (WASAPI + GSMTC WinRT).

---

## 📚 Technical Documentation

- **[docs/MOBILE_COMPATIBILITY_AND_VALIDATION.md](docs/MOBILE_COMPATIBILITY_AND_VALIDATION.md)**: Compatibility tiers, mobile app capabilities, and reproducible macOS / iPhone verification.
- **[docs/DESIGN.md](docs/DESIGN.md)**: Complete system specification, state machine diagrams, protocol reverse-engineering analysis (Shokz BES, Apple AAP, Sony MDR, MagicPods), and cross-platform architecture.
- **[docs/TROUBLESHOOTING_AND_RECOMMENDATIONS.md](docs/TROUBLESHOOTING_AND_RECOMMENDATIONS.md)**: Hardware diagnostic findings, Shokz battery & mobile app reverse-engineering report, and architectural recommendations.
- **[AGENTS.md](AGENTS.md)**: Developer & AI Agent guide detailing repository structure, build guidelines, and Bluetooth protocol implementations.

---

## 🛠 Project Structure

```
AirFlow/
├── docs/
│   └── DESIGN.md                 # Full architectural specification
├── AGENTS.md                     # Agent guide & developer instructions
├── Cargo.toml                    # Rust workspace manifest
├── Package.swift                 # Swift Package Manager manifest
├── crates/
│   ├── airflow-core/             # Rust arbitration engine & C-ABI library
│   │   ├── include/airflow_core.h # Public C-ABI header
│   │   └── src/                  # Arbitration, whitelist, drivers (BES, AAP, MDR)
│   └── airflow-cli/              # Zero-dependency Rust CLI & background daemon
├── Sources/
│   └── AirFlow/
│       ├── Core/                 # State machine, RustEngineBridge, whitelist, config
│       ├── Drivers/              # Headphone drivers (Shokz, AirPods, Sony, Generic)
│       ├── Platform/             # macOS, Linux, and Windows platform adapters
│       └── UI/                   # Menubar status item & SwiftUI popover
└── Tests/
    └── AirFlowTests/
```

---

## 💻 Building & Running

### Rust Core & Standalone CLI (All Platforms: macOS, Linux, Windows)
```bash
# Build Rust release binaries
cargo build --release

# Run Rust unit tests
cargo test --workspace

# Run standalone CLI daemon (zero external runtime dependencies, ~1.6MB)
cargo run -p airflow-cli -- daemon
```

### macOS Native Menubar App (SwiftUI)
```bash
# Build Swift menubar app
swift build

# Run macOS app
swift run AirFlow

# Run Swift test suite (with dynamic Rust C-ABI bridge test)
swift test
```

---

## 🗺 Roadmap

- [x] Comprehensive requirements, research & architecture specification.
- [x] Hardware protocol verification (CoreAudio, MediaRemote, BLE GATT services).
- [x] Pluggable `HeadphoneDriver` architecture (supporting Fast Pair & BES chipsets).
- [x] Native macOS menubar app with battery gauges, device switcher, and whitelist binding.
- [x] Hardware-independent unit test suite for Gatekeeper bypass and arbitration engine.
- [ ] Mobile peer remote control command dispatch.
- [ ] Linux daemon implementation (BlueZ + PipeWire + MPRIS) and Apple Accessory Protocol (AAP) driver for AirPods.
- [ ] Windows daemon implementation (WASAPI + GSMTC WinRT) and modern flyout tray UI.
- [ ] Single-point headphone dynamic reconnect emulation.

---

## 🤝 Contributing

We welcome contributions! Please adhere to the following guidelines:
1. All contributions, bug fixes, and feature additions must be submitted via **Pull Requests (PRs)** targeting `main`. Direct pushes to `main` are disabled.
2. Ensure all commit messages, code comments, and documentation are written in **English**.
3. All new logic and state machine changes must include unit tests verifying behavior across platforms. Run `swift test` before submitting your PR.
