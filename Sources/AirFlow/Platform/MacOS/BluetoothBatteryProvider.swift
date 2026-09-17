import Foundation

#if os(macOS)
import IOBluetooth

/// Native macOS Bluetooth battery provider that queries real-time battery status
/// reported by connected Bluetooth audio devices (OpenDots, AirPods, Sony, etc.)
/// to the macOS Bluetooth subsystem (via IOBluetooth).
public enum MacOSBluetoothBatteryProvider {
    /// Queries the real-time battery level of a connected Bluetooth device by name or returns the first connected audio device.
    public static func queryBattery(for deviceName: String? = nil) -> HeadphoneBattery? {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return nil }
        
        for dev in devices where dev.isConnected() {
            let name = dev.nameOrAddress ?? ""
            
            // If deviceName is specified, verify it matches
            if let target = deviceName, !target.isEmpty {
                let targetLower = target.lowercased()
                let nameLower = name.lowercased()
                if !nameLower.contains(targetLower) && !targetLower.contains(nameLower) {
                    continue
                }
            }
            
            let single = (dev.value(forKey: "batteryPercentSingle") as? Int).flatMap { $0 > 0 && $0 <= 100 ? $0 : nil }
            let left = (dev.value(forKey: "batteryPercentLeft") as? Int).flatMap { $0 > 0 && $0 <= 100 ? $0 : nil }
            let right = (dev.value(forKey: "batteryPercentRight") as? Int).flatMap { $0 > 0 && $0 <= 100 ? $0 : nil }
            let caseLvl = (dev.value(forKey: "batteryPercentCase") as? Int).flatMap { $0 > 0 && $0 <= 100 ? $0 : nil }
            
            if left != nil || right != nil || single != nil || caseLvl != nil {
                let finalLeft = left ?? single
                let finalRight = right ?? single
                return HeadphoneBattery(
                    left: finalLeft,
                    right: finalRight,
                    caseLevel: caseLvl,
                    isCharging: false
                )
            }
        }
        return nil
    }
}
#else
public enum MacOSBluetoothBatteryProvider {
    public static func queryBattery(for deviceName: String? = nil) -> HeadphoneBattery? {
        return nil
    }
}
#endif
