#if os(macOS)
import Foundation

/// Implementation of MediaPlaybackObserverProtocol for macOS using the private MediaRemote.framework.
/// Provides system-wide playback observation and global pause/resume controls.
public final class MediaRemoteObserver: MediaPlaybackObserverProtocol, @unchecked Sendable {
    private typealias MRGetPlaying = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    private typealias MRSendCommand = @convention(c) (UInt32, AnyObject?) -> Bool
    private typealias MRRegisterNotification = @convention(c) (DispatchQueue) -> Void
    private typealias MRUnregisterNotification = @convention(c) () -> Void
    
    private var handle: UnsafeMutableRawPointer?
    private var getPlayingFn: MRGetPlaying?
    private var sendCommandFn: MRSendCommand?
    private var registerNotificationFn: MRRegisterNotification?
    private var unregisterNotificationFn: MRUnregisterNotification?
    
    private var isRunning = false
    private var callback: (@Sendable (Bool) -> Void)?
    private var observerToken: NSObjectProtocol?
    
    private let kMRPlay: UInt32 = 0
    private let kMRPause: UInt32 = 1
    private let kMRTogglePlayPause: UInt32 = 2
    
    public init() {
        loadMediaRemote()
    }
    
    deinit {
        stopMonitoring()
        if let handle = handle {
            dlclose(handle)
        }
    }
    
    private func loadMediaRemote() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let h = dlopen(path, RTLD_NOW) else {
            print("[MediaRemoteObserver] Warning: Failed to load MediaRemote: \(String(cString: dlerror()))")
            return
        }
        self.handle = h
        
        if let sym = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            self.getPlayingFn = unsafeBitCast(sym, to: MRGetPlaying.self)
        }
        if let sym = dlsym(h, "MRMediaRemoteSendCommand") {
            self.sendCommandFn = unsafeBitCast(sym, to: MRSendCommand.self)
        }
        if let sym = dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            self.registerNotificationFn = unsafeBitCast(sym, to: MRRegisterNotification.self)
        }
        if let sym = dlsym(h, "MRMediaRemoteUnregisterForNowPlayingNotifications") {
            self.unregisterNotificationFn = unsafeBitCast(sym, to: MRUnregisterNotification.self)
        }
    }
    
    public func startMonitoring(onPlaybackChanged: @escaping @Sendable (Bool) -> Void) {
        guard !isRunning else { return }
        self.callback = onPlaybackChanged
        self.isRunning = true
        
        registerNotificationFn?(DispatchQueue.main)
        
        let notifName = NSNotification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")
        self.observerToken = NotificationCenter.default.addObserver(
            forName: notifName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            self.queryCurrentPlaybackState { isPlaying in
                self.callback?(isPlaying)
            }
        }
        
        // Initial state query
        queryCurrentPlaybackState { [weak self] isPlaying in
            self?.callback?(isPlaying)
        }
    }
    
    public func stopMonitoring() {
        guard isRunning else { return }
        isRunning = false
        
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
            observerToken = nil
        }
        unregisterNotificationFn?()
    }
    
    public func isMediaPlaying() -> Bool {
        final class ResultBox: @unchecked Sendable {
            var value = false
        }
        let box = ResultBox()
        let sema = DispatchSemaphore(value: 0)
        queryCurrentPlaybackState { isPlaying in
            box.value = isPlaying
            sema.signal()
        }
        _ = sema.wait(timeout: .now() + 0.3)
        return box.value
    }
    
    public func pauseMedia() {
        guard let sendCommand = sendCommandFn else { return }
        _ = sendCommand(kMRPause, nil)
    }
    
    public func resumeMedia() {
        guard let sendCommand = sendCommandFn else { return }
        _ = sendCommand(kMRPlay, nil)
    }
    
    // MARK: - Private Helpers
    
    private func queryCurrentPlaybackState(completion: @escaping @Sendable (Bool) -> Void) {
        guard let getPlaying = getPlayingFn else {
            completion(false)
            return
        }
        getPlaying(DispatchQueue.global()) { isPlaying in
            completion(isPlaying)
        }
    }
}
#else
import Foundation

/// Fallback stub for non-macOS environments (Linux/Windows).
public final class MediaRemoteObserver: MediaPlaybackObserverProtocol, @unchecked Sendable {
    public init() {}
    public func startMonitoring(onPlaybackChanged: @escaping @Sendable (Bool) -> Void) {}
    public func stopMonitoring() {}
    public func isMediaPlaying() -> Bool { return false }
    public func pauseMedia() {}
    public func resumeMedia() {}
}
#endif

