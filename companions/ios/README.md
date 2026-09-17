# AirFlow iOS Companion Guide

AirFlow connects seamlessly with your iPhone or iPad using the **AirFlow Remote** BLE companion protocol or local network automations.

---

## 1. Zero-App Setup: iOS Shortcuts Automation

You do not need a custom App Store app installed on your iPhone to pause media when your computer starts playback. You can set this up in seconds using Apple's built-in **Shortcuts** app.

### Method A: BLE Remote via LightBlue or BLE Shortcut
1. AirFlow on your Mac advertises a dedicated companion GATT service:
   - **Service UUID**: `A1BF0001-0000-1000-8000-00805F9B34FB`
   - **Command Characteristic**: `A1BF0002-0000-1000-8000-00805F9B34FB` (Notify)
2. When your Mac begins media playback, AirFlow dispatches notification payload `0x01` (Pause).
3. Using any BLE background receiver (or Shortcuts Bluetooth trigger), execute the native action:
   - **Action**: *Play/Pause iPhone* (Set to **Pause**).

### Method B: Local Network Webhook
If your phone and Mac are connected to the same Wi-Fi network:
1. Enable `LocalNetwork` strategy in AirFlow menu bar popover (`Cmd+Shift+P`).
2. Point AirFlow to your iPhone's local automation listener (e.g. Scriptable, Shortcuts URL trigger).
3. Receiving the HTTP `POST /pause` invokes immediate system media pause.

---

## 2. Supported Headphone Actions
- **Apple AirPods**: Handled natively by Apple's ecosystem handoff engine. AirFlow automatically enters **Gatekeeper Bypass** mode when AirPods are detected on macOS/iOS.
- **Multipoint Headphones (Shokz, Sony, Bose)**: When AirFlow switches audio to your Mac, it sends a vendor pause packet directly to the headphone or notifies your iPhone to yield the audio stream without disconnects.
