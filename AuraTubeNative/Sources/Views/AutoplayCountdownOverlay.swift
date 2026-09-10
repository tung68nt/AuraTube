import SwiftUI
import AppKit

public struct AutoplayCountdownOverlay: View {
    let video: Video
    @ObservedObject private var playerManager = PlayerManager.shared
    
    public init(video: Video) {
        self.video = video
    }
    
    private var countdown: Int {
        playerManager.autoplayCountdown ?? 5
    }
    
    public var body: some View {
        ZStack {
            // Semi-transparent backdrop
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            // Central Countdown Card
            VStack(spacing: 16) {
                // Header: Countdown Title & Autoplay Switch
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 3)
                                .frame(width: 28, height: 28)
                            
                            Circle()
                                .trim(from: 0, to: CGFloat(countdown) / 5.0)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.2, blue: 0.3), Color(red: 0.9, green: 0.08, blue: 0.18)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .frame(width: 28, height: 28)
                                .animation(.linear(duration: 1.0), value: countdown)
                            
                            Text("\(countdown)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        
                        Text("Tự động phát sau \(countdown)s")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    // Autoplay Quick Toggle
                    Button(action: {
                        playerManager.toggleAutoplay()
                    }) {
                        HStack(spacing: 6) {
                            Text("Tự động phát")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(Color(white: 0.75))
                            
                            ZStack(alignment: playerManager.isAutoplayEnabled ? .trailing : .leading) {
                                Capsule()
                                    .fill(playerManager.isAutoplayEnabled ? Color.white : Color(white: 0.28))
                                    .frame(width: 30, height: 15)
                                
                                Circle()
                                    .fill(playerManager.isAutoplayEnabled ? Color.black : Color(white: 0.75))
                                    .frame(width: 11, height: 11)
                                    .padding(.horizontal, 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Bật/Tắt tự động phát video kế tiếp")
                }
                
                // Next Video Information Preview
                HStack(spacing: 14) {
                    ZStack(alignment: .bottomTrailing) {
                        AsyncImage(url: URL(string: video.thumbnail)) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFill()
                            } else {
                                Color(white: 0.15)
                            }
                        }
                        .frame(width: 140, height: 80)
                        .clipped()
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        
                        if !video.durationFormatted.isEmpty {
                            Text(video.durationFormatted)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.85))
                                .cornerRadius(4)
                                .padding(4)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        Text(video.uploader)
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.7))
                            .lineLimit(1)
                        
                        if !video.metadataFormatted.isEmpty {
                            Text(video.metadataFormatted)
                                .font(.system(size: 11))
                                .foregroundColor(Color(white: 0.5))
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Color.white.opacity(0.05))
                .cornerRadius(10)
                
                // Bottom Action Buttons
                HStack(spacing: 12) {
                    Button(action: {
                        playerManager.cancelAutoplay()
                    }) {
                        Text("Hủy")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(white: 0.85))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .cornerRadius(18)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        playerManager.playNextVideo()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Phát ngay")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color.white)
                        .cornerRadius(18)
                        .shadow(color: .white.opacity(0.2), radius: 6, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(width: 420)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.12).opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.7), radius: 24, y: 10)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
