import SwiftUI
import AppKit

// MARK: - MiniPlayerEngine Stub for Backward Compatibility
@MainActor
public final class MiniPlayerEngine {
    public static let shared = MiniPlayerEngine()
    private init() {}
    public func stop() {
        // No-op: Retired in favor of Native Media Controller & PiP
    }
}

// MARK: - MiniNativePlayerView: Edge-to-Edge Native Media Artwork
public struct MiniNativePlayerView: View {
    @ObservedObject private var playerManager = PlayerManager.shared
    
    public init() {}
    
    private var primaryThumbnailUrl: URL? {
        guard let video = playerManager.currentVideo else { return nil }
        if !video.thumbnail.isEmpty, let url = URL(string: video.thumbnail) {
            return url
        }
        return URL(string: "https://i.ytimg.com/vi/\(video.id)/hqdefault.jpg")
    }
    
    private var highResThumbnailUrl: URL? {
        guard let video = playerManager.currentVideo else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(video.id)/maxresdefault.jpg")
    }
    
    public var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                
                if playerManager.currentVideo != nil {
                    // 1. Full-bleed Artwork with Graceful High-Res Fallback
                    AsyncImage(url: highResThumbnailUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        case .failure, .empty:
                            // Fallback to standard thumbnail (always reliable from YouTube/yt-dlp)
                            AsyncImage(url: primaryThumbnailUrl) { fbPhase in
                                if let fbImage = fbPhase.image {
                                    fbImage
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: geo.size.width, height: geo.size.height)
                                        .clipped()
                                } else {
                                    Color(white: 0.12)
                                }
                            }
                        @unknown default:
                            Color(white: 0.12)
                        }
                    }
                    
                    // 2. Subtle Cinematic Lighting Gradient
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.25),
                            Color.clear,
                            Color.black.opacity(0.4)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    
                    // 3. PiP Status Badge (Top-Right)
                    if playerManager.isPictureInPictureActive {
                        VStack {
                            HStack {
                                Spacer()
                                HStack(spacing: 4) {
                                    Image(systemName: "pip")
                                        .font(.system(size: 9.5, weight: .bold))
                                    Text("Đang phát PiP")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.75))
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
                                        )
                                )
                                .padding(8)
                            }
                            Spacer()
                        }
                    }
                } else {
                    Color(white: 0.08)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
