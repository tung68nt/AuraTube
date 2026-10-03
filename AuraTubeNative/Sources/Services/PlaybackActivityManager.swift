import Foundation

/// Manages macOS system power and scheduling activity assertions to prevent App Nap,
/// background CPU throttling, and frame rate drops during video playback and PiP multitasking.
@MainActor
public final class PlaybackActivityManager {
    public static let shared = PlaybackActivityManager()
    
    private var activityToken: NSObjectProtocol?
    
    private init() {}
    
    /// Requests high-priority scheduling and disables App Nap for seamless 60/120fps playback across all app switches.
    public func ensurePlaybackActivity(reason: String = "AuraTube Media Playback") {
        guard activityToken == nil else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
            reason: reason
        )
    }
    
    /// Releases the activity assertion when playback is paused and PiP is closed.
    public func endPlaybackActivity() {
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }
}
