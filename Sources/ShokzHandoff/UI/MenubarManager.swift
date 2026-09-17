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
        self.popover.contentSize = NSSize(width: 320, height: 260)
        self.popover.behavior = .transient
        self.popover.contentViewController = NSHostingController(rootView: StatusPopoverView(viewModel: viewModel))
    }
    
    private func bindViewModel() {
        // Initial state
        viewModel.boundPeer = whitelistManager.getBoundDevice()
        viewModel.currentAudioDevice = audioMonitor.getCurrentDefaultDevice()
        viewModel.availableAudioDevices = audioMonitor.listOutputDevices()
        viewModel.battery = driver.getBatteryStatus()
        
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
        
        viewModel.onQuit = {
            NSApp.terminate(nil)
        }
    }
    
    private func updateStatusItemAppearance(for state: EngineState) {
        guard let button = statusItem.button else { return }
        
        switch state {
        case .bypassed:
            button.appearsDisabled = true
        case .hostActive, .peerActive:
            button.appearsDisabled = false
            button.image = NSImage(systemSymbolName: "headphones.circle.fill", accessibilityDescription: "Streaming")
        default:
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
            // Refresh devices on click
            viewModel.availableAudioDevices = audioMonitor.listOutputDevices()
            viewModel.currentAudioDevice = audioMonitor.getCurrentDefaultDevice()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
