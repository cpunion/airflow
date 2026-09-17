# AirFlow Android Companion Guide & Daemon Specification

The Android companion service enables instant, bidirectional audio roaming between your Android device and macOS, Linux, or Windows PCs running AirFlow.

---

## 1. BLE Protocol Specification

AirFlow acts as a BLE Peripheral advertising the `AirFlow Remote` service:
- **Service UUID**: `A1BF0001-0000-1000-8000-00805F9B34FB`
- **Command TX / Notification Characteristic**: `A1BF0002-0000-1000-8000-00805F9B34FB`
  - Properties: `Notify`, `Read`
  - CCCD: `0x2902` (Client Characteristic Configuration Descriptor)
- **Status / Ack Characteristic**: `A1BF0003-0000-1000-8000-00805F9B34FB`
  - Properties: `Write`, `WriteWithoutResponse`

### Command Opcode Table:
| Opcode | Meaning | Action on Android |
| :--- | :--- | :--- |
| `0x01` | **Pause Media** | Dispatch `KeyEvent.KEYCODE_MEDIA_PAUSE` or invoke `MediaController.getTransportControls().pause()` |
| `0x02` | **Resume Media** | Dispatch `KeyEvent.KEYCODE_MEDIA_PLAY` |
| `0x03` | **Query Status** | Reply on Characteristic `0xA1BF0003` with current playback state |

---

## 2. Quick Setup via Automate / Tasker

You can automate Android media pause with zero coding using **Tasker** or **Automate**:
1. Add a **Bluetooth Low Energy** event listener for Service `0xA1BF0001` and Characteristic `0xA1BF0002`.
2. When byte `0x01` is received:
   - Run Action: `Media Control` -> `Cmd: Pause` -> `Simulate Media Button: Checked`.
3. AirFlow on your PC will automatically detect your phone as a connected peer and reflect its status in the menu bar popover.

---

## 3. Background Daemon Implementation (Kotlin)

For standalone companion apps, instantiate a background `BluetoothGattCallback`:
```kotlin
class AirFlowCompanionService : Service() {
    private val SERVICE_UUID = UUID.fromString("A1BF0001-0000-1000-8000-00805F9B34FB")
    private val CHAR_CMD_UUID = UUID.fromString("A1BF0002-0000-1000-8000-00805F9B34FB")

    override fun onCharacteristicChanged(gatt: BluetoothGatt, char: BluetoothGattCharacteristic) {
        val payload = char.value ?: return
        if (payload.isNotEmpty() && payload[0] == 0x01.toByte()) {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PAUSE))
            audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PAUSE))
        }
    }
}
```
