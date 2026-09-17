#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

/// Manages the native macOS menu bar item (NSStatusItem) and popover lifecycle.
@MainActor
public final class MenubarManager: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let viewModel: StatusPopoverViewModel
    private let engine: ArbitrationEngine
    private let audioMonitor: AudioDeviceMonitorProtocol
    private let driver: HeadphoneDriver
    private let whitelistManager: DeviceWhitelistManager
    
    public init(
        engine: ArbitrationEngine,
        audioMonitor: AudioDeviceMonitorProtocol,
        driver: HeadphoneDriver,
        whitelistManager: DeviceWhitelistManager
    ) {
        self.engine = engine
        self.audioMonitor = audioMonitor
        self.driver = driver
        self.whitelistManager = whitelistManager
        self.viewModel = StatusPopoverViewModel()
        super.init()
        
        setupStatusItem()
        setupPopover()
        bindViewModel()
    }
    
    private func setupStatusItem() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        
        button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "AirFlow")
        button.target = self
        button.action = #selector(togglePopover)
    }
    
    private func setupPopover() {
        self.popover = NSPopover()
        self.popover.contentSize = NSSize(width: 340, height: 380)
        self.popover.behavior = .transient
        self.popover.contentViewController = NSHostingController(rootView: StatusPopoverView(viewModel: viewModel))
    }
    
    private func bindViewModel() {
        // Initial state
        viewModel.boundPeer = whitelistManager.getBoundDevice()
        viewModel.currentAudioDevice = audioMonitor.getCurrentDefaultDevice()
        viewModel.availableAudioDevices = audioMonitor.listOutputDevices()
        viewModel.battery = driver.getBatteryStatus()
        viewModel.activeStrategy = engine.dispatcher.activeStrategy
        viewModel.cooldownSeconds = Double(engine.cooldownMs) / 1000.0
        viewModel.isLaunchAtLoginEnabled = LaunchAtLoginHelper.shared.isEnabled
        viewModel.bleSubscribersCount = BleRemoteServer.shared.subscribedCentrals.count
        
        // Listen to engine state
        engine.onStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.viewModel.engineState = state
                self?.updateStatusItemAppearance(for: state)
            }
        }
        
        // Listen to driver battery updates
        driver.onBatteryChanged = { [weak self] battery in
            Task { @MainActor in
                self?.viewModel.battery = battery
                self?.updateBatteryTitle(battery: battery)
            }
        }
        
        // Wire UI callbacks
        viewModel.onToggleHandoff = { [weak self] enabled in
            self?.engine.setHandoffEnabled(enabled)
        }
        
        viewModel.onToggleAirPodsBypass = { [weak self] enabled in
            self?.engine.setAirPodsBypassEnabled(enabled)
        }
        
        viewModel.onSelectDevice = { [weak self] device in
            self?.audioMonitor.setDefaultOutputDevice(deviceID: device.id)
        }
        
        viewModel.onStrategyChanged = { [weak self] strategy in
            self?.engine.dispatcher.setStrategy(strategy)
        }
        
        viewModel.onCooldownChanged = { [weak self] seconds in
            self?.engine.setCooldownMs(Int(seconds * 1000.0))
        }
        
        viewModel.onToggleLaunchAtLogin = { enabled in
            LaunchAtLoginHelper.shared.isEnabled = enabled
        }
        
        viewModel.onTestPause = { [weak self] in
            guard let self = self else { return }
            if let peer = self.whitelistManager.getBoundDevice() {
                self.engine.dispatcher.dispatchPause(to: peer)
            } else {
                // Temporary mock peer for testing if whitelist is empty
                let fallbackPeer = PairedDeviceInfo(id: "TEST-LOCAL", name: "Default Test Phone")
                self.whitelistManager.bindDevice(fallbackPeer)
                self.engine.dispatcher.dispatchPause(to: fallbackPeer)
            }
        }
        
        viewModel.onQuit = {
            NSApp.terminate(nil)
        }
    }
    
    private func updateStatusItemAppearance(for state: EngineState) {
        guard let button = statusItem.button else { return }
        
        switch state {
        case .bypassed:
            button.appearsDisabled = true
            button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "AirFlow Bypassed")
        case .hostActive:
            button.appearsDisabled = false
            button.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Mac Streaming")
        case .peerActive:
            button.appearsDisabled = false
            button.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "Phone Streaming")
        case .cooldown:
            button.appearsDisabled = false
            button.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Cooldown")
        case .idle:
            button.appearsDisabled = false
            button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "AirFlow")
        }
    }
    
    private func updateBatteryTitle(battery: HeadphoneBattery) {
        guard let button = statusItem.button else { return }
        let pct = battery.primaryPercentage
        button.title = " \(pct)%"
    }
    
    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Refresh dynamic state on popover open
            viewModel.availableAudioDevices = audioMonitor.listOutputDevices()
            viewModel.currentAudioDevice = audioMonitor.getCurrentDefaultDevice()
            viewModel.boundPeer = whitelistManager.getBoundDevice()
            viewModel.isLaunchAtLoginEnabled = LaunchAtLoginHelper.shared.isEnabled
            viewModel.bleSubscribersCount = BleRemoteServer.shared.subscribedCentrals.count
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
#else
import Foundation

/// Fallback stub for non-macOS platforms without AppKit/SwiftUI.
public final class MenubarManager: @unchecked Sendable {
    public init(
        engine: ArbitrationEngine,
        audioMonitor: AudioDeviceMonitorProtocol,
        driver: HeadphoneDriver,
        whitelistManager: DeviceWhitelistManager
    ) {}
}
#endif
