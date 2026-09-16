import SwiftUI
import AppKit

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var isScrubbing: Bool = false
    @Published var scrubTime: Double = 0
}

public struct MenuBarView: View {
    @ObservedObject private var playerManager = PlayerManager.shared
    @ObservedObject private var clock = PlaybackClock.shared
    @StateObject private var vm = MenuBarViewModel()
    @State private var showCenterFlash: Bool = false
    @State private var flashIsPlaying: Bool = false
    @State private var isHoveringVideo: Bool = false
    
    var onOpenMainWindow: () -> Void
    
    public init(onOpenMainWindow: @escaping () -> Void) {
        self.onOpenMainWindow = onOpenMainWindow
    }
    
    private func triggerTogglePlayPause() {
        playerManager.togglePlayPause()
        flashIsPlaying = playerManager.isPlaying
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            showCenterFlash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeOut(duration: 0.2)) {
                showCenterFlash = false
            }
        }
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
                            .font(AppFont.youTubeSans(size: 16.5, weight: .bold))
                            .foregroundColor(.white)
                            .tracking(-0.45)
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
                    Button(action: {
                        triggerTogglePlayPause()
                    }) {
                        ZStack(alignment: .center) {
                            MiniNativePlayerView()
                                .allowsHitTesting(false)
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
                            
                            // Center Play Button when Paused
                            if !playerManager.isPlaying && !showCenterFlash {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.55))
                                        .frame(width: 52, height: 52)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(
                                                    LinearGradient(
                                                        colors: [Color.white.opacity(0.5), Color.white.opacity(0.15)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1.2
                                                )
                                        )
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundColor(.white)
                                        .offset(x: 2)
                                }
                                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 3)
                                .transition(.scale(scale: 0.85).combined(with: .opacity))
                            }
                            
                            // Center Flash Animation on Play/Pause Toggle
                            if showCenterFlash {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.6))
                                        .frame(width: 56, height: 56)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                                        )
                                    Image(systemName: flashIsPlaying ? "play.fill" : "pause.fill")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.white)
                                        .offset(x: flashIsPlaying ? 2 : 0)
                                }
                                .transition(.scale(scale: 1.15).combined(with: .opacity))
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isHoveringVideo = hovering
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
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
                                get: { vm.isScrubbing ? vm.scrubTime : clock.currentTime },
                                set: { vm.scrubTime = $0 }
                            ),
                            in: 0...max(1, playerManager.duration),
                            onEditingChanged: { editing in
                                if editing {
                                    vm.scrubTime = clock.currentTime
                                    vm.isScrubbing = true
                                } else {
                                    playerManager.seek(to: vm.scrubTime)
                                    vm.isScrubbing = false
                                }
                            }
                        )
                        .controlSize(.mini)
                        
                        HStack {
                            Text(formatTime(vm.isScrubbing ? vm.scrubTime : clock.currentTime))
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
                        
                        LiquidGlassCircleButton(action: { triggerTogglePlayPause() }, size: 34) {
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
                    
                    // Space key shortcut for quick toggle in Menu Bar
                    Button("") {
                        triggerTogglePlayPause()
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    .opacity(0)
                    .frame(width: 0, height: 0)
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
