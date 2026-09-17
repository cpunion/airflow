# AirFlow (`shokz-handoff`)

> Universal, intelligent audio handoff and device manager for wireless headphones across macOS, Linux, Android, and iOS.
> **AirPods-like seamless switching for Shokz, Sony, Bose, and more — with zero mobile apps required on iOS.**

---

## 🚀 Overview

Standard Bluetooth Multipoint headphones (such as Shokz OpenDots 2, Sony WH/WF series, and Bose QuietComfort) utilize a rigid **"First-Come, First-Served"** audio routing model:
- If your phone is playing music, video on your computer has no audio until you pull out your phone and manually pause.
- If your computer is playing video, your phone cannot preempt it.

**AirFlow** eliminates this frustration by providing an intelligent, bidirectional arbitration layer between your computer and mobile devices:
1. **Play on Computer ➔ Phone Automatically Pauses ➔ Headphone output transitions seamlessly**.
2. **Play on Phone ➔ Computer Automatically Pauses ➔ Headphone output transitions seamlessly**.
3. **Gatekeeper Bypass**: Automatically detects native AirPods and gracefully steps aside, preventing conflicts with Apple's built-in ecosystem handoff.
4. **Driver Plugin Architecture**: Designed to support Shokz, AirPods (including Linux reverse-engineered AAP support), Sony MDR, Bose, and generic single-point Bluetooth headphones.

---

## 📚 Technical Documentation

- **[docs/DESIGN.md](docs/DESIGN.md)**: Complete system specification, state machine diagrams, protocol reverse-engineering analysis (Shokz BES, Apple AAP, Sony MDR), and cross-platform architecture.
- **[AGENTS.md](AGENTS.md)**: Developer & AI Agent guide detailing repository structure, build guidelines, and Bluetooth protocol implementations.

---

## 🛠 Project Structure

```
shokz/
├── docs/
│   └── DESIGN.md                 # Full architectural specification
├── AGENTS.md                     # Agent guide & developer instructions
├── Package.swift                 # Swift Package Manager manifest
├── Sources/
│   └── ShokzHandoff/
│       ├── Core/                 # Arbitration engine, state machine, whitelist
│       ├── Drivers/              # Headphone drivers (Shokz, AirPods, Sony, Generic)
│       ├── Platform/             # macOS CoreAudio & MediaRemote platform adapters
│       └── UI/                   # Menubar status item & notification UI
└── Tests/
    └── ShokzHandoffTests/
```

---

## 💻 Building & Running (macOS)

### Prerequisites
- macOS 14.0+ (Sonoma, Sequoia, or later)
- Swift 6.0+ toolchain (`swift --version`)

### Build
```bash
swift build
```

### Run
```bash
swift run ShokzHandoff
```

---

## 🗺 Roadmap

- [x] Comprehensive requirements, research & architecture specification.
- [x] Hardware protocol verification (CoreAudio, MediaRemote, Shokz BLE GATT services).
- [ ] Implement pluggable `HeadphoneDriver` architecture (`ShokzDriver` first).
- [ ] Implement macOS menubar app with device auto-detection and whitelist binding.
- [ ] Implement Linux daemon (BlueZ + PipeWire + MPRIS) and Apple Accessory Protocol (AAP) driver for AirPods.
- [ ] Implement single-point headphone dynamic reconnect emulation.
