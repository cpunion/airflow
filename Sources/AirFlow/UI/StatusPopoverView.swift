#if canImport(AppKit) && canImport(SwiftUI)
import SwiftUI

/// Observable view model binding the core engine state to the SwiftUI popover interface.
@MainActor
public final class StatusPopoverViewModel: ObservableObject {
    @Published public var engineState: EngineState = .idle
    @Published public var battery: HeadphoneBattery? = nil
    @Published public var boundPeer: PairedDeviceInfo?
    @Published public var availablePeers: [PairedDeviceInfo] = []
    @Published public var availableAudioDevices: [AudioDevice] = []
    @Published public var currentAudioDevice: AudioDevice?
    @Published public var isHandoffEnabled: Bool = true
    @Published public var isAirPodsBypassEnabled: Bool = true
    @Published public var activeStrategy: DispatchStrategy = .headphoneGatt
    @Published public var cooldownSeconds: Double = 1.5
    @Published public var isLaunchAtLoginEnabled: Bool = false
    @Published public var testFeedbackMessage: String?
    @Published public var bleSubscribersCount: Int = 0
    
    public var isTwsDevice: Bool {
        return currentAudioDevice?.isTws ?? true
    }
    
    public var onSelectPeer: ((PairedDeviceInfo) -> Void)?
    public var onToggleHandoff: ((Bool) -> Void)?
    public var onToggleAirPodsBypass: ((Bool) -> Void)?
    public var onSelectDevice: ((AudioDevice) -> Void)?
    public var onStrategyChanged: ((DispatchStrategy) -> Void)?
    public var onCooldownChanged: ((Double) -> Void)?
    public var onToggleLaunchAtLogin: ((Bool) -> Void)?
    public var onTestPause: (() -> Void)?
    public var onQuit: (() -> Void)?
    
    public init() {}
    
    public func triggerTestPauseFeedback() {
        self.testFeedbackMessage = "Pause sent!"
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self.testFeedbackMessage == "Pause sent!" {
                self.testFeedbackMessage = nil
            }
        }
    }
}

/// Native macOS SwiftUI Popover UI presenting battery gauges, active devices, and handoff controls.
public struct StatusPopoverView: View {
    @ObservedObject public var viewModel: StatusPopoverViewModel
    
    public init(viewModel: StatusPopoverViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: App Title & Engine State Badge
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "airpodsmax")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                    Text("AirFlow")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                Spacer()
                statusBadge
            }
            
            Divider()
            
            // Section 1: Active Headphone & Battery Gauges
            headphoneSection
            
            Divider()
            
            // Section 2: Mobile Peer Device & Remote Dispatch
            peerSection
            
            Divider()
            
            // Section 3: Audio Output Selection
            outputDeviceSection
            
            Divider()
            
            // Section 4: Engine Settings & Configuration
            settingsSection
            
            Divider()
            
            // Footer: Controls & Quit
            HStack {
                Text("v1.0.0 • macOS Native")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Quit AirFlow") {
                    viewModel.onQuit?()
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var statusBadge: some View {
        switch viewModel.engineState {
        case .idle:
            Label("Idle", systemImage: "circle.fill")
                .foregroundColor(.gray)
                .font(.caption)
        case .hostActive:
            Label("Mac Streaming", systemImage: "speaker.wave.2.fill")
                .foregroundColor(.green)
                .font(.caption)
        case .peerActive:
            Label("Phone Streaming", systemImage: "iphone")
                .foregroundColor(.blue)
                .font(.caption)
        case .cooldown:
            Label("Cooldown", systemImage: "lock.fill")
                .foregroundColor(.orange)
                .font(.caption)
        case .bypassed(let reason):
            Label("Bypassed", systemImage: "arrow.uturn.forward")
                .foregroundColor(.secondary)
                .font(.caption)
                .help(reason)
        }
    }
    
    private var headphoneSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "headphones")
                    .foregroundColor(.accentColor)
                Text(viewModel.currentAudioDevice?.name ?? "Wireless Headphone")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer()
                if let dev = viewModel.currentAudioDevice, dev.isAirPods {
                    Text("AirPods")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(4)
                }
            }
            
            if let battery = viewModel.battery {
                HStack(spacing: 8) {
                    if let leftLevel = battery.left, let rightLevel = battery.right {
                        batteryItem(
                            label: "Left",
                            text: "\(leftLevel)%",
                            icon: "earbuds",
                            level: leftLevel,
                            isCharging: battery.isCharging
                        )
                        batteryItem(
                            label: "Right",
                            text: "\(rightLevel)%",
                            icon: "earbuds",
                            level: rightLevel,
                            isCharging: battery.isCharging
                        )
                        if let caseLevel = battery.caseLevel {
                            batteryItem(
                                label: "Case",
                                text: "\(caseLevel)%",
                                icon: "case.fill",
                                level: caseLevel
                            )
                        }
                    } else {
                        let pct = battery.primaryPercentage
                        batteryItem(
                            label: "Battery",
                            text: "\(pct)%",
                            icon: "headphones",
                            level: pct,
                            isCharging: battery.isCharging
                        )
                        if let caseLevel = battery.caseLevel {
                            batteryItem(
                                label: "Case",
                                text: "\(caseLevel)%",
                                icon: "case.fill",
                                level: caseLevel
                            )
                        }
                    }
                }
                .padding(.top, 2)
                
                if viewModel.isTwsDevice && (battery.left == nil || battery.caseLevel == nil) {
                    Text("Note: Case & earbud sync telemetry updates when docked or opened.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func batteryItem(
        label: String,
        text: String,
        icon: String,
        level: Int? = nil,
        isCharging: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: isCharging ? "bolt.fill" : icon)
                .font(.caption2)
                .foregroundColor(level != nil ? batteryColor(level!) : .secondary)
            Text("\(label):")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }
    
    private func batteryColor(_ level: Int) -> Color {
        if level > 50 { return .green }
        if level > 20 { return .orange }
        return .red
    }
    
    private var peerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "iphone.gen3")
                    .foregroundColor(.accentColor)
                Text("Mobile Peer")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                
                if let feedback = viewModel.testFeedbackMessage {
                    Text(feedback)
                        .font(.caption2)
                        .foregroundColor(.green)
                        .fontWeight(.bold)
                } else {
                    Button(action: {
                        viewModel.onTestPause?()
                        viewModel.triggerTestPauseFeedback()
                    }) {
                        Label("Test Pause", systemImage: "pause.fill")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            }
            
            // Target Phone Selection Dropdown
            HStack {
                Text("Target:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Picker("", selection: Binding(
                    get: { viewModel.boundPeer?.id ?? "" },
                    set: { newId in
                        if let match = viewModel.availablePeers.first(where: { $0.id == newId }) {
                            viewModel.boundPeer = match
                            viewModel.onSelectPeer?(match)
                        }
                    }
                )) {
                    if viewModel.availablePeers.isEmpty {
                        Text(viewModel.boundPeer?.name ?? "No paired phones found").tag(viewModel.boundPeer?.id ?? "")
                    } else {
                        ForEach(viewModel.availablePeers) { peer in
                            Text(peer.name).tag(peer.id)
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                
                Spacer()
                
                Text("BLE: \(viewModel.bleSubscribersCount) linked")
                    .font(.caption2)
                    .foregroundColor(viewModel.bleSubscribersCount > 0 ? .green : .secondary)
            }
            
            // Dispatch strategy picker
            HStack {
                Text("Dispatch Via:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Picker("", selection: Binding(
                    get: { viewModel.activeStrategy },
                    set: { newStrat in
                        viewModel.activeStrategy = newStrat
                        viewModel.onStrategyChanged?(newStrat)
                    }
                )) {
                    ForEach(DispatchStrategy.allCases, id: \.self) { strat in
                        Text(strat.rawValue).tag(strat)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
            }
            
            Text(strategyHint(for: viewModel.activeStrategy))
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private func strategyHint(for strategy: DispatchStrategy) -> String {
        switch strategy {
        case .headphoneGatt:
            return "Relays pause command through headphone multipoint audio firmware."
        case .bleRemote:
            return "Phone connects to 'AirFlow Remote' BLE service to receive instant pause."
        case .bleHidMediaKey:
            return "Emulates Bluetooth media remote key (Pause) to paired phone."
        case .localNetwork:
            return "Sends local network webhook to phone / iOS Shortcut automation."
        }
    }
    
    private var outputDeviceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Audio Output Routing")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Picker("", selection: Binding(
                get: { viewModel.currentAudioDevice?.id ?? 0 },
                set: { newId in
                    if let match = viewModel.availableAudioDevices.first(where: { $0.id == newId }) {
                        viewModel.currentAudioDevice = match
                        viewModel.onSelectDevice?(match)
                    }
                }
            )) {
                ForEach(viewModel.availableAudioDevices, id: \.id) { device in
                    HStack {
                        Image(systemName: device.isBluetooth ? "headphones" : "speaker.wave.2")
                        Text(device.name)
                    }
                    .tag(device.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
        }
    }
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("Smart Handoff", isOn: $viewModel.isHandoffEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: viewModel.isHandoffEnabled) { _, newValue in
                        viewModel.onToggleHandoff?(newValue)
                    }
                
                Spacer()
                
                Toggle("AirPods Bypass", isOn: $viewModel.isAirPodsBypassEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: viewModel.isAirPodsBypassEnabled) { _, newValue in
                        viewModel.onToggleAirPodsBypass?(newValue)
                    }
            }
            
            HStack {
                Toggle("Launch at Login", isOn: $viewModel.isLaunchAtLoginEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: viewModel.isLaunchAtLoginEnabled) { _, newValue in
                        viewModel.onToggleLaunchAtLogin?(newValue)
                    }
                
                Spacer()
                
                // Cooldown setting
                HStack(spacing: 4) {
                    Text("Cooldown:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Picker("", selection: Binding(
                        get: { viewModel.cooldownSeconds },
                        set: { newSec in
                            viewModel.cooldownSeconds = newSec
                            viewModel.onCooldownChanged?(newSec)
                        }
                    )) {
                        Text("0.5s").tag(0.5)
                        Text("1.0s").tag(1.0)
                        Text("1.5s").tag(1.5)
                        Text("2.0s").tag(2.0)
                        Text("3.0s").tag(3.0)
                    }
                    .pickerStyle(.menu)
                    .controlSize(.mini)
                    .frame(width: 70)
                }
            }
        }
    }
}
#endif
