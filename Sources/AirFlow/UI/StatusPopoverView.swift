#if canImport(AppKit) && canImport(SwiftUI)
import SwiftUI

/// Observable view model binding the core engine state to the SwiftUI popover interface.
@MainActor
public final class StatusPopoverViewModel: ObservableObject {
    @Published public var engineState: EngineState = .idle
    @Published public var battery: HeadphoneBattery? = HeadphoneBattery(left: 80, right: 80, caseLevel: 90)
    @Published public var boundPeer: PairedDeviceInfo?
    @Published public var availableAudioDevices: [AudioDevice] = []
    @Published public var currentAudioDevice: AudioDevice?
    @Published public var isHandoffEnabled: Bool = true
    @Published public var isAirPodsBypassEnabled: Bool = true
    
    public var onToggleHandoff: ((Bool) -> Void)?
    public var onToggleAirPodsBypass: ((Bool) -> Void)?
    public var onSelectDevice: ((AudioDevice) -> Void)?
    public var onQuit: (() -> Void)?
    
    public init() {}
}

/// Native macOS SwiftUI Popover UI presenting battery gauges, active devices, and handoff controls.
public struct StatusPopoverView: View {
    @ObservedObject public var viewModel: StatusPopoverViewModel
    
    public init(viewModel: StatusPopoverViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: App Title & Engine State Badge
            HStack {
                Text("AirFlow")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                statusBadge
            }
            
            Divider()
            
            // Section 1: Active Headphone & Battery Gauges
            headphoneSection
            
            Divider()
            
            // Section 2: Mobile Peer Device
            peerSection
            
            Divider()
            
            // Section 3: Audio Output Selection
            outputDeviceSection
            
            Divider()
            
            // Footer: Controls & Quit
            VStack(spacing: 8) {
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
                    Spacer()
                    Button("Quit") {
                        viewModel.onQuit?()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.footnote)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "headphones")
                    .foregroundColor(.accentColor)
                Text(viewModel.currentAudioDevice?.name ?? "Wireless Headphone")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            
            if let battery = viewModel.battery {
                HStack(spacing: 12) {
                    if let l = battery.left {
                        batteryItem(label: "L", level: l)
                    }
                    if let r = battery.right {
                        batteryItem(label: "R", level: r)
                    }
                    if let c = battery.caseLevel {
                        batteryItem(label: "Case", level: c, isCase: true)
                    }
                }
                .padding(.top, 2)
            }
        }
    }
    
    private func batteryItem(label: String, level: Int, isCase: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: isCase ? "case.fill" : "earbuds")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("\(label):")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("\(level)%")
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }
    
    private var peerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "iphone.gen3")
                    .foregroundColor(.accentColor)
                Text("Linked Peer")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(viewModel.boundPeer != nil ? "Connected" : "Not Linked")
                    .font(.caption2)
                    .foregroundColor(viewModel.boundPeer != nil ? .green : .secondary)
            }
            
            if let peer = viewModel.boundPeer {
                Text(peer.name)
                    .font(.footnote)
                    .foregroundColor(.primary)
            } else {
                Text("No target phone selected in whitelist.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var outputDeviceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Audio Output Device")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Picker("", selection: Binding(
                get: { viewModel.currentAudioDevice?.id ?? 0 },
                set: { newId in
                    if let match = viewModel.availableAudioDevices.first(where: { $0.id == newId }) {
                        viewModel.onSelectDevice?(match)
                    }
                }
            )) {
                ForEach(viewModel.availableAudioDevices, id: \.id) { device in
                    Text(device.name).tag(device.id)
                }
            }
            .labelsHidden()
        }
    }
}
#endif

