import Foundation
import Combine

@MainActor
public final class PlaybackClock: ObservableObject {
    public static let shared = PlaybackClock()
    
    @Published public var currentTime: Double = 0
    @Published public var duration: Double = 0
    @Published public var isPlaying: Bool = false
    @Published public var isScrubbing: Bool = false
    
    private init() {}
    
    public func update(time: Double, duration: Double, isPlaying: Bool) {
        if !isScrubbing {
            if abs(self.currentTime - time) > 0.05 {
                self.currentTime = time
            }
        }
        if duration > 0 && abs(self.duration - duration) > 0.5 {
            self.duration = duration
        }
        if self.isPlaying != isPlaying {
            self.isPlaying = isPlaying
        }
    }
    
    public func setSeekTime(_ time: Double) {
        self.currentTime = time
    }
}
