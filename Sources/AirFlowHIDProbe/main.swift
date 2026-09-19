import AirFlow
import AppKit
import Foundation
import IOBluetooth
import IOBluetoothUI

// This is an opt-in diagnostic, not a production handoff transport.
@MainActor
func log(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    FileHandle.standardOutput.write(Data(line.utf8))
}

func normalized(_ address: String) -> String {
    address.replacingOccurrences(of: "-", with: ":").uppercased()
}

@MainActor
final class Scanner: NSObject, @preconcurrency IOBluetoothDeviceInquiryDelegate {
    var finished = false
    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry, device: IOBluetoothDevice) {
        log("Discovered \(device.name ?? "unnamed") address=\(device.addressString ?? "unknown") paired=\(device.isPaired())")
    }
    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry, error: IOReturn, aborted: Bool) {
        log("Scan completed status=\(error) aborted=\(aborted); no pairing or control attempted")
        finished = true
    }
    func run() {
        guard let inquiry = IOBluetoothDeviceInquiry(delegate: self) else { return }
        inquiry.inquiryLength = 8
        inquiry.updateNewDeviceNames = false
        let status = inquiry.start()
        log("Scan requested status=\(status)")
        guard status == 0 else { return }
        let deadline = Date().addingTimeInterval(30)
        while !finished && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        if !finished { log("Scan timed out; stopping inquiry"); inquiry.stop() }
    }
}

@MainActor
final class Probe: NSObject, @preconcurrency IOBluetoothL2CAPChannelDelegate {
    let codec: URL
    let packets: [String: [UInt8]]
    let defaults = UserDefaults(suiteName: "org.airflow.hid-validation")!
    var record: IOBluetoothSDPServiceRecord?
    var notification: IOBluetoothUserNotification?
    var target: IOBluetoothDevice?
    var channels: [UInt16: IOBluetoothL2CAPChannel] = [:]
    var opening: Set<UInt16> = []
    var ready: Set<UInt16> = []
    var pending: [Int: (NSMutableData, String)] = [:]
    var serial = 0
    var readyAt = Date.distantFuture
    var lastPress = Date.distantPast
    var keyState = "released"
    var suspended = false
    var connectionGeneration = 0
    var source: DispatchSourceRead?
    var signals: [DispatchSourceSignal] = []

    init(codec: URL) throws {
        self.codec = codec
        guard let packets = try Self.invoke(codec, []) as? [String: [UInt8]],
              ["descriptor", "pause", "toggle", "release"].allSatisfy({ !(packets[$0] ?? []).isEmpty }) else {
            throw NSError(domain: "HIDCodec", code: 2)
        }
        self.packets = packets
        super.init()
    }

    static func invoke(_ path: URL, _ args: [String]) throws -> [String: Any] {
        let process = Process()
        process.executableURL = path
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw NSError(domain: "HIDCodec", code: 1) }
        return result
    }

    func publish() throws {
        func uint(_ value: Int, _ size: Int = 2) -> [String: Any] {
            ["DataElementType": 1, "DataElementSize": size, "DataElementValue": value]
        }
        func bool(_ value: Bool) -> [String: Any] {
            ["DataElementType": 5, "DataElementSize": 1, "DataElementValue": value]
        }
        let descriptor = Data(packets["descriptor"]!)
        let attrs: [String: Any] = [
            "0001 - ServiceClassIDList": [IOBluetoothSDPUUID.uuid16(0x1124)!],
            "0004 - ProtocolDescriptorList": [
                [IOBluetoothSDPUUID.uuid16(0x0100)!, uint(0x11)],
                [IOBluetoothSDPUUID.uuid16(0x0011)!]
            ],
            "0005 - BrowseGroupList": [IOBluetoothSDPUUID.uuid16(0x1002)!],
            "0009 - BluetoothProfileDescriptorList": [[IOBluetoothSDPUUID.uuid16(0x1124)!, uint(0x0101)]],
            "000D - AdditionalProtocolDescriptorLists": [[
                [IOBluetoothSDPUUID.uuid16(0x0100)!, uint(0x13)],
                [IOBluetoothSDPUUID.uuid16(0x0011)!]
            ]],
            "0100 - ServiceName": "AirFlow Consumer Pause Validation",
            "0200 - HIDDeviceReleaseNumber": uint(0x0100),
            "0201 - HIDParserVersion": uint(0x0111),
            "0202 - HIDDeviceSubclass": uint(0, 1),
            "0203 - HIDCountryCode": uint(0, 1),
            "0204 - HIDVirtualCable": bool(true),
            "0205 - HIDReconnectInitiate": bool(true),
            "0206 - HIDDescriptorList": [[uint(0x22, 1), [
                "DataElementType": 4, "DataElementSize": descriptor.count,
                "DataElementValue": descriptor
            ]]],
            "0207 - HIDLANGIDBaseList": [[uint(0x0409), uint(0x0100)]],
            "0208 - HIDSDPDisable": bool(false),
            "0209 - HIDBatteryPower": bool(false),
            "020A - HIDRemoteWake": bool(false),
            "020B - HIDProfileVersion": uint(0x0101),
            "020C - HIDSupervisionTimeout": uint(0x1F40),
            "020D - HIDNormallyConnectable": bool(true),
            "020E - HIDBootDevice": bool(false),
            "LocalAttributes": ["Persistent": false]
        ]
        guard let service = IOBluetoothSDPServiceRecord.publishedServiceRecord(with: attrs) else {
            throw NSError(domain: "HIDPublish", code: 1)
        }
        record = service
        var handle: BluetoothSDPServiceRecordHandle = 0
        let status = service.getHandle(&handle)
        log("SDP published status=\(status) handle=\(handle); no peer commands sent")
        notification = IOBluetoothL2CAPChannel.register(forChannelOpenNotifications: self,
            selector: #selector(incoming(_:channel:)))
    }

    // OS pairing alone never authorizes media control. Require a separate explicit selection.
    func authorize(_ address: String) {
        guard target == nil, channels.isEmpty,
              address.range(of: "^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}$", options: .regularExpression) != nil,
              let device = IOBluetoothDevice(addressString: address), device.isPaired() else {
            log("REFUSED: select an exact paired address while disconnected")
            return
        }
        defaults.set(normalized(address), forKey: "confirmedTarget")
        target = device
        log("Explicit diagnostic whitelist saved for \(device.name ?? "unnamed"); connect is separate")
    }

    func allowed() -> Bool {
        guard let target, target.isPaired(), let address = target.addressString else { return false }
        return defaults.string(forKey: "confirmedTarget") == normalized(address)
    }

    func connect() {
        guard allowed(), channels.isEmpty, let target else {
            log("REFUSED: authorize a paired target first, or disconnect existing probe channels")
            return
        }
        suspended = false
        keyState = "released"
        connectionGeneration += 1
        let generation = connectionGeneration
        // On macOS 26, the asynchronous path for a disconnected ACL internally
        // waits synchronously inside its completion callback and can fail before
        // the successful L2CAP callback arrives. Establish the ACL first.
        if !target.isConnected() {
            let status = target.openConnection()
            log("Baseband open status=\(status)")
            guard status == 0 else { return }
        }
        open(target, psm: 0x11)
        if ready.contains(0x11) { open(target, psm: 0x13) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [self] in
            if connectionGeneration == generation && ready != [0x11, 0x13] {
                log("Connection timed out before both channels opened")
                disconnect()
            }
        }
    }

    func open(_ device: IOBluetoothDevice, psm: UInt16) {
        opening.insert(psm)
        defer { opening.remove(psm) }
        var channel: IOBluetoothL2CAPChannel?
        // A delegate is required during open, or IOBluetooth never opens the
        // underlying streams even when the peer accepts the L2CAP channel.
        let status = device.openL2CAPChannelSync(&channel, withPSM: psm, delegate: self)
        log("Synchronous open PSM=\(String(psm, radix: 16)) status=\(status)")
        guard status == 0, let channel else { disconnect(); return }
        channels[psm] = channel
        channel.setDelegate(self)
        if !ready.contains(psm) { l2capChannelOpenComplete(channel, status: status) }
    }

    @objc func incoming(_ notice: IOBluetoothUserNotification, channel: IOBluetoothL2CAPChannel) {
        guard channel.isIncoming(), [UInt16(0x11), 0x13].contains(channel.psm), allowed(),
              normalized(channel.device.addressString ?? "") == normalized(target?.addressString ?? ""),
              channels[channel.psm] == nil else { return }
        channels[channel.psm] = channel
        channel.setDelegate(self)
        l2capChannelOpenComplete(channel, status: 0)
    }

    func l2capChannelOpenComplete(_ channel: IOBluetoothL2CAPChannel, status: IOReturn) {
        guard allowed(), normalized(channel.device.addressString ?? "") == normalized(target?.addressString ?? ""),
              channels[channel.psm] === channel || opening.contains(channel.psm) else { channel.close(); return }
        log("Open completed PSM=\(String(channel.psm, radix: 16)) status=\(status)")
        guard status == 0 else { disconnect(); return }
        channels[channel.psm] = channel
        ready.insert(channel.psm)
        if ready == [0x11, 0x13] {
            readyAt = Date().addingTimeInterval(5)
            log("Both channels open; wait 5 seconds for peer setup. Media outcome remains UNKNOWN")
        }
    }

    func l2capChannelData(_ channel: IOBluetoothL2CAPChannel, data pointer: UnsafeMutableRawPointer, length: Int) {
        guard allowed(), channels[channel.psm] === channel else { return }
        let hex = Data(bytes: pointer, count: length).map { String(format: "%02X", $0) }.joined(separator: "-")
        log("RX PSM=\(String(channel.psm, radix: 16)) bytes=\(hex)")
        guard channel.psm == 0x11, length > 0 else { return }
        do {
            let reply = try Self.invoke(codec, ["control", hex, keyState])
            switch reply["action"] as? String {
            case "reply":
                guard let bytes = reply["bytes"] as? [UInt8] else {
                    log("Malformed codec reply"); disconnect(); return
                }
                write(bytes, channel: channel, label: "control")
            case "suspend": suspended = true
            case "resume": suspended = false
            case "unplug": disconnect()
            default: break
            }
        } catch { log("Codec error: \(error)"); disconnect() }
    }

    func press(_ key: String) {
        guard allowed(), !suspended, ready == [0x11, 0x13], Date() >= readyAt,
              Date().timeIntervalSince(lastPress) >= 1.5, keyState == "released",
              pending.isEmpty, let channel = channels[0x13] else {
            log("REFUSED: target, channels, setup delay, suspension, pending write, or cooldown guard")
            return
        }
        guard let output = CoreAudioMonitor().getCurrentDefaultDevice() else {
            log("BYPASS: cannot verify current audio output")
            return
        }
        // Conservatively bypass every Beats model in this diagnostic.
        guard !output.isAirPods, !output.name.lowercased().contains("beats") else {
            log("BYPASS: Apple-managed audio output")
            return
        }
        lastPress = Date()
        keyState = key
        write(packets[key]!, channel: channel, label: key)
    }

    func write(_ bytes: [UInt8], channel: IOBluetoothL2CAPChannel, label: String) {
        serial += 1
        let token = serial
        let buffer = NSMutableData(data: Data(bytes))
        pending[token] = (buffer, label)
        let status = channel.writeAsync(buffer.mutableBytes, length: UInt16(buffer.length),
                                        refcon: UnsafeMutableRawPointer(bitPattern: token))
        log("TX queued \(label) bytes=\(bytes.map { String(format: "%02X", $0) }.joined(separator: "-")) status=\(status)")
        if status != 0 { pending.removeValue(forKey: token); disconnect() }
    }

    func l2capChannelWriteComplete(_ channel: IOBluetoothL2CAPChannel,
                                   refcon: UnsafeMutableRawPointer?, status: IOReturn) {
        guard let refcon, let (_, label) = pending.removeValue(forKey: Int(bitPattern: refcon)) else { return }
        log("TX completed \(label) status=\(status); this is NOT proof of phone playback state")
        guard status == 0 else { disconnect(); return }
        if label == "pause" || label == "toggle" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [self] in
                guard channels[0x13] === channel, allowed() else { return }
                keyState = "released"
                write(packets["release"]!, channel: channel, label: "release")
            }
        }
    }

    func l2capChannelClosed(_ channel: IOBluetoothL2CAPChannel) {
        log("Closed PSM=\(String(channel.psm, radix: 16))")
        if channels[channel.psm] === channel {
            channels.removeValue(forKey: channel.psm)
            ready.remove(channel.psm)
            readyAt = .distantFuture
        }
    }

    func disconnect() {
        connectionGeneration += 1
        let owned = Array(channels.values)
        channels.removeAll()
        ready.removeAll()
        readyAt = .distantFuture
        for channel in owned { channel.close() }
        // Do not disconnect the entire Bluetooth device or erase its pairing.
        log("Probe channels closed; existing OS pairing preserved")
    }

    func cleanup() {
        disconnect()
        notification?.unregister()
        notification = nil
        if let record { log("SDP remove status=\(record.remove())") }
        record = nil
    }

    func command(_ line: String) {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        guard let command = parts.first else { return }
        switch command {
        case "authorize" where parts.count == 2: authorize(parts[1])
        case "connect": connect()
        case "disconnect": disconnect()
        case "pause": press("pause")
        case "toggle-confirmed": press("toggle")
        case "observe" where parts.count == 2: log("MANUAL OBSERVATION: \(parts[1])")
        case "quit": cleanup(); exit(0)
        default: log("Commands: authorize AA:BB:CC:DD:EE:FF | connect | pause | toggle-confirmed | observe TEXT | disconnect | quit")
        }
    }

    func run() {
        source = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        source?.setEventHandler { [self] in
            if let line = readLine() {
                // Bluetooth synchronous calls must not nest inside a main GCD
                // callback: their completion delivery also needs the main queue.
                RunLoop.main.perform(inModes: [.default]) { [self] in
                    MainActor.assumeIsolated { command(line) }
                }
            } else { cleanup(); exit(0) }
        }
        source?.resume()
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let handler = DispatchSource.makeSignalSource(signal: number, queue: .main)
            handler.setEventHandler { [self] in cleanup(); exit(0) }
            handler.resume()
            signals.append(handler)
        }
        command("help")
        RunLoop.main.run()
    }
}

@main
struct HIDProbeMain {
    @MainActor static func main() throws {
        let args = CommandLine.arguments.dropFirst()
        if args.first == "--scan" { Scanner().run(); return }
        if args.first == "--list" {
            for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] {
                log("\(device.name ?? "unnamed") address=\(device.addressString ?? "unknown") paired=\(device.isPaired()) connected=\(device.isConnected())")
            }
            if let output = CoreAudioMonitor().getCurrentDefaultDevice() { log("Audio output: \(output.name)") }
            return
        }
        guard args.count == 2, ["--local", "--interactive", "--pair-ui"].contains(args.first!) else {
            log("Usage: AirFlowHIDProbe --list | --scan | (--local | --interactive | --pair-ui) PATH_TO_RUST_CODEC")
            return
        }
        let probe = try Probe(codec: URL(fileURLWithPath: args.last!))
        try probe.publish()
        if args.first == "--local" { probe.cleanup(); return }
        if args.first == "--pair-ui" {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            let panel = IOBluetoothPairingController()
            panel.setTitle("AirFlow: Pair a test phone")
            log("Pairing UI opened. Confirm matching codes on both devices; no media whitelist is granted.")
            log("Pairing UI result=\(panel.runModal())")
            probe.cleanup()
            return
        }
        probe.run()
    }
}
