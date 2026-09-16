import SwiftUI
import AppKit

// MARK: - MiniPlayerEngine Stub for Backward Compatibility
@MainActor
public final class MiniPlayerEngine {
    public static let shared = MiniPlayerEngine()
    private init() {}
    public func stop() {
        // No-op: The second WebKit player has been retired in favor of native macOS Now Playing Architecture
    }
}

// MARK: - Live Equalizer Bars View (Visual indication when playing)
struct MiniEqualizerIndicator: View {
    let isPlaying: Bool
    @State private var bar1Height: CGFloat = 4
    @State private var bar2Height: CGFloat = 10
    @State private var bar3Height: CGFloat = 6
    @State private var bar4Height: CGFloat = 12
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            bar(height: bar1Height)
            bar(height: bar2Height)
            bar(height: bar3Height)
            bar(height: bar4Height)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.65))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8))
        )
        .onAppear {
            if isPlaying { startAnimating() }
        }
        .onChange(of: isPlaying) { playing in
            if playing { startAnimating() } else { stopAnimating() }
        }
    }
    
    private func bar(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.red)
            .frame(width: 2.5, height: isPlaying ? height : 3)
    }
    
    private func startAnimating() {
        withAnimation(Animation.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) {
            bar1Height = 12
            bar2Height = 5
            bar3Height = 14
            bar4Height = 7
        }
    }
    
    private func stopAnimating() {
        withAnimation(.easeOut(duration: 0.2)) {
            bar1Height = 3
            bar2Height = 3
            bar3Height = 3
            bar4Height = 3
        }
    }
}

// MARK: - MiniNativePlayerView: High-Performance Native Media Artwork
public struct MiniNativePlayerView: View {
    @ObservedObject private var playerManager = PlayerManager.shared
    
    public init() {}
    
    private var maxResThumbnailUrl: URL? {
        guard let video = playerManager.currentVideo else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(video.id)/maxresdefault.jpg") ?? URL(string: video.thumbnail)
    }
    
    public var body: some View {
        ZStack {
            Color.black
            
            if let video = playerManager.currentVideo {
                // High-resolution artwork with graceful fallback
                AsyncImage(url: maxResThumbnailUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        AsyncImage(url: URL(string: video.thumbnail)) { fbPhase in
                            if let fbImage = fbPhase.image {
                                fbImage
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Color(white: 0.08)
                            }
                        }
                    case .empty:
                        Color(white: 0.08)
                    @unknown default:
                        Color(white: 0.08)
                    }
                }
                
                // Subtle dark gradient overlays for cinematic depth
                LinearGradient(
                    colors: [Color.black.opacity(0.35), Color.clear, Color.black.opacity(0.35)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Overlay badges
                VStack {
                    HStack {
                        // Live Audio/Video Equalizer Indicator
                        if playerManager.isPlaying {
                            MiniEqualizerIndicator(isPlaying: playerManager.isPlaying)
                                .transition(.opacity)
                        }
                        
                        Spacer()
                        
                        // Picture-in-Picture indicator if active
                        if playerManager.isPictureInPictureActive {
                            HStack(spacing: 3) {
                                Image(systemName: "pip")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Đang phát PiP")
                                    .font(.system(size: 9.5, weight: .medium))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.75))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8))
                            )
                            .foregroundColor(.white)
                        }
                    }
                    .padding(8)
                    
                    Spacer()
                }
            } else {
                Color.black
            }
        }
    }
}
