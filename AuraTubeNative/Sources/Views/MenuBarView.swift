import SwiftUI
import AppKit

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var isScrubbing: Bool = false
    @Published var scrubTime: Double = 0
}

public struct MenuBarView: View {
    @ObservedObject private var playerManager = PlayerManager.shared
    @StateObject private var vm = MenuBarViewModel()
    var onOpenMainWindow: () -> Void
    
    public init(onOpenMainWindow: @escaping () -> Void) {
        self.onOpenMainWindow = onOpenMainWindow
    }
    
    public var body: some View {
        VStack(spacing: 14) {
            // Header: Branding + Expand Button
            HStack {
                Button(action: {
                    AppDelegate.showStandardAboutPanel()
                }) {
                    HStack(spacing: 8) {
                        YouTubeBrandBadge(width: 25)
                        Text("AuraTube")
                            .font(.custom("Roboto-Bold", size: 14.5))
                            .foregroundColor(.white)
                            .tracking(-0.3)
                    }
                }
                .buttonStyle(.plain)
                .help("Xem thông tin AuraTube")
                
                Spacer()
                
                LiquidGlassButton(action: onOpenMainWindow, cornerRadius: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 11))
                        Text("⌘O")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundColor(Color(white: 0.88))
                }
            }
            
            // Video Info & Mini Player Preview
            if let video = playerManager.currentVideo {
                VStack(spacing: 10) {
                    ZStack(alignment: .bottomTrailing) {
                        MiniNativePlayerView()
                            .aspectRatio(playerManager.isCurrentVideoVertical ? (9/16) : (16/9), contentMode: .fit)
                            .frame(height: playerManager.isCurrentVideoVertical ? 310 : nil)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playerManager.togglePlayPause()
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(video.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(video.uploader)
                            .font(.system(size: 11.5))
                            .foregroundColor(Color(white: 0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Scrubber Progress Bar
                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(
                                get: { vm.isScrubbing ? vm.scrubTime : playerManager.currentTime },
                                set: { vm.scrubTime = $0 }
                            ),
                            in: 0...max(1, playerManager.duration),
                            onEditingChanged: { editing in
                                if editing {
                                    vm.scrubTime = playerManager.currentTime
                                    vm.isScrubbing = true
                                } else {
                                    playerManager.seek(to: vm.scrubTime)
                                    vm.isScrubbing = false
                                }
                            }
                        )
                        .controlSize(.mini)
                        
                        HStack {
                            Text(formatTime(vm.isScrubbing ? vm.scrubTime : playerManager.currentTime))
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(Color(white: 0.55))
                            Spacer()
                            Text(formatTime(playerManager.duration))
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(Color(white: 0.55))
                        }
                    }
                    
                    // Controls with Liquid Glass: Seek Back, Play/Pause, Seek Forward, Volume
                    HStack(spacing: 16) {
                        LiquidGlassCircleButton(action: { playerManager.seekRelative(-10) }, size: 28) {
                            Image(systemName: "gobackward.10")
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                        }
                        
                        LiquidGlassCircleButton(action: { playerManager.togglePlayPause() }, size: 34) {
                            Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        LiquidGlassCircleButton(action: { playerManager.seekRelative(10) }, size: 28) {
                            Image(systemName: "goforward.10")
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        LiquidGlassCircleButton(action: { playerManager.toggleMute() }, size: 28) {
                            Image(systemName: playerManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Color(white: 0.82))
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "play.slash")
                        .font(.system(size: 24))
                        .foregroundColor(Color(white: 0.4))
                    Text("Chưa phát video nào")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(Color(white: 0.6))
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: playerManager.isCurrentVideoVertical ? 300 : 320)
        .liquidGlass(cornerRadius: 14, elevation: 8)
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: playerManager.isCurrentVideoVertical)
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}
