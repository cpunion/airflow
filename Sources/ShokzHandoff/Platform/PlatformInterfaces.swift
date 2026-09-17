import Foundation

/// Protocol for monitoring system-wide audio output devices across operating systems.
public protocol AudioDeviceMonitorProtocol: AnyObject, Sendable {
    /// Starts observing system default output device changes.
    func startMonitoring(onDeviceChanged: @escaping @Sendable (AudioDevice) -> Void)
    
    /// Stops observing.
    func stopMonitoring()
    
    /// Fetches the currently active default audio output device.
    func getCurrentDefaultDevice() -> AudioDevice?
    
    /// Enumerates all available audio output devices on the host.
    func listOutputDevices() -> [AudioDevice]
}

/// Protocol for monitoring and controlling media playback across operating systems.
public protocol MediaPlaybackObserverProtocol: AnyObject, Sendable {
    /// Starts observing system-wide media playback changes (e.g. video/music starting or stopping).
    func startMonitoring(onPlaybackChanged: @escaping @Sendable (Bool) -> Void)
    
    /// Stops observing.
    func stopMonitoring()
    
    /// Returns true if any application on the host is currently playing audio/video media.
    func isMediaPlaying() -> Bool
    
    /// Dispatches a global pause command to currently playing media applications.
    func pauseMedia()
    
    /// Dispatches a global resume/play command to media applications.
    func resumeMedia()
}
