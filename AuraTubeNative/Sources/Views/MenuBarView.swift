import SwiftUI
import AppKit

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var isScrubbing: Bool = false
    @Published var scrubTime: Double = 0
    @Published var isHoveringBar: Bool = false
    @Published var showCenterFlash: Bool = false
    @Published var flashIsPlaying: Bool = false
    @Published var isHoveringVideo: Bool = false
}

public struct MenuBarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var playerManager = PlayerManager.shared
    @ObservedObject private var clock = PlaybackClock.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    
    @StateObject private var vm = MenuBarViewModel()
    
    var onOpenMainWindow: () -> Void
    
    public init(onOpenMainWindow: @escaping () -> Void) {
        self.onOpenMainWindow = onOpenMainWindow
    }
    
    private var isDark: Bool {
        colorScheme == .dark
    }
    
    private var textPrimary: Color {
        isDark ? Color(red: 0.96, green: 0.96, blue: 0.97) : Color(red: 0.10, green: 0.10, blue: 0.12)
    }
    
    private var textSecondary: Color {
        isDark ? Color(red: 0.72, green: 0.74, blue: 0.79) : Color(red: 0.40, green: 0.42, blue: 0.47)
    }
    
    private var textTertiary: Color {
        isDark ? Color(red: 0.55, green: 0.57, blue: 0.62) : Color(red: 0.50, green: 0.52, blue: 0.58)
    }
    
    private var effectiveDuration: Double {
        clock.duration > 0 ? clock.duration : playerManager.duration
    }
    
    private var effectiveCurrentTime: Double {
        if vm.isScrubbing {
            return vm.scrubTime
        }
        return clock.currentTime > 0 ? clock.currentTime : playerManager.currentTime
    }
    
    private func triggerTogglePlayPause() {
        playerManager.togglePlayPause()
        vm.flashIsPlaying = playerManager.isPlaying
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            vm.showCenterFlash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeOut(duration: 0.2)) {
                vm.showCenterFlash = false
            }
        }
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // 1. Header: Branding, Quick Theme Switcher & Actions
            HStack(spacing: 8) {
                Button(action: {
                    AppDelegate.showStandardAboutPanel()
                }) {
                    HStack(spacing: 7) {
                        YouTubeBrandBadge(width: 24)
                        Text("AuraTube")
                            .font(.system(size: 15.5, weight: .bold))
                            .foregroundColor(textPrimary)
                    }
                }
                .buttonStyle(.plain)
                .help("Xem thông tin AuraTube")
                
                Spacer()
                
                // Quick Theme Toggle Button (Cycles System -> Light -> Dark)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        themeManager.cycleTheme()
                    }
                }) {
                    Image(systemName: themeManager.currentTheme.iconName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(textPrimary.opacity(0.88))
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08), lineWidth: 0.75)
                        )
                }
                .buttonStyle(.plain)
                .help("Giao diện: \(themeManager.currentTheme.title) (Bấm để đổi)")
                
                // Picture-in-Picture Button
                Button(action: {
                    playerManager.togglePictureInPicture()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: playerManager.isPictureInPictureActive ? "pip.exit" : "pip.enter")
                            .font(.system(size: 10.5, weight: .bold))
                        Text("PiP")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .foregroundColor(playerManager.isPictureInPictureActive ? .white : textPrimary)
                    .background(
                        Capsule()
                            .fill(
                                playerManager.isPictureInPictureActive ?
                                Color(red: 0.95, green: 0.15, blue: 0.15) :
                                (isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
                            )
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                playerManager.isPictureInPictureActive ?
                                Color.red.opacity(0.4) :
                                (isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)),
                                lineWidth: 0.75
                            )
                    )
                }
                .buttonStyle(.plain)
                .help("Bật / Tắt Picture-in-Picture (P / ⌥⌘P)")
                
                // Expand to Main Window Button
                Button(action: onOpenMainWindow) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("⌘O")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .foregroundColor(textPrimary)
                    .background(
                        Capsule()
                            .fill(isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08), lineWidth: 0.75)
                    )
                }
                .buttonStyle(.plain)
                .help("Mở cửa sổ chính (⌘O)")
            }
            
            // 2. Main Media Content or Empty State
            if let video = playerManager.currentVideo {
                VStack(spacing: 10) {
                    // Video Thumbnail Preview with Play/Pause on click
                    Button(action: {
                        triggerTogglePlayPause()
                    }) {
                        ZStack(alignment: .center) {
                            MiniNativePlayerView()
                                .allowsHitTesting(false)
                                .frame(height: playerManager.isCurrentVideoVertical ? 310 : 162)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.12),
                                            lineWidth: 1
                                        )
                                )
                            
                            // Center Play Button when Paused
                            if !playerManager.isPlaying && !vm.showCenterFlash {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.60))
                                        .frame(width: 50, height: 50)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.white.opacity(0.4), lineWidth: 1.2)
                                        )
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.white)
                                        .offset(x: 2)
                                }
                                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 3)
                                .transition(.scale(scale: 0.85).combined(with: .opacity))
                            }
                            
                            // Center Flash Animation on Play/Pause Toggle
                            if vm.showCenterFlash {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.65))
                                        .frame(width: 54, height: 54)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.white.opacity(0.4), lineWidth: 1.2)
                                        )
                                    Image(systemName: vm.flashIsPlaying ? "play.fill" : "pause.fill")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundColor(.white)
                                        .offset(x: vm.flashIsPlaying ? 2 : 0)
                                }
                                .transition(.scale(scale: 1.15).combined(with: .opacity))
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        vm.isHoveringVideo = hovering
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    
                    // Video Metadata (Title & Channel)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(video.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        Text(video.uploader)
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundColor(textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // 3. High-Contrast Interactive Timeline Scrubber
                    timelineScrubber
                    
                    // 4. Playback Controls Row: Rewind 10, Play/Pause, Forward 10, Volume/Mute
                    HStack(spacing: 14) {
                        // Rewind 10s
                        Button(action: { playerManager.seekRelative(-10) }) {
                            Image(systemName: "gobackward.10")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(textPrimary)
                                .frame(width: 30, height: 30)
                                .background(
                                    Circle()
                                        .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.06), lineWidth: 0.75)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Tua lùi 10 giây (←)")
                        
                        // Center Prominent Play / Pause Button (High Contrast)
                        Button(action: { triggerTogglePlayPause() }) {
                            ZStack {
                                Circle()
                                    .fill(
                                        isDark ?
                                        Color(red: 0.95, green: 0.95, blue: 0.96) :
                                        Color(red: 0.12, green: 0.12, blue: 0.14)
                                    )
                                Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(isDark ? Color.black : Color.white)
                                    .offset(x: playerManager.isPlaying ? 0 : 1)
                            }
                            .frame(width: 36, height: 36)
                            .shadow(color: Color.black.opacity(isDark ? 0.35 : 0.18), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                        .help("Phát / Tạm dừng (Space)")
                        
                        // Forward 10s
                        Button(action: { playerManager.seekRelative(10) }) {
                            Image(systemName: "goforward.10")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(textPrimary)
                                .frame(width: 30, height: 30)
                                .background(
                                    Circle()
                                        .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.06), lineWidth: 0.75)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Tua tới 10 giây (→)")
                        
                        Spacer()
                        
                        // Volume / Mute Button
                        Button(action: { playerManager.toggleMute() }) {
                            Image(systemName: playerManager.isMuted ? "speaker.slash.fill" : (playerManager.volume > 0.5 ? "speaker.wave.2.fill" : "speaker.wave.1.fill"))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(playerManager.isMuted ? Color.red : textPrimary)
                                .frame(width: 30, height: 30)
                                .background(
                                    Circle()
                                        .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.06), lineWidth: 0.75)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Bật / Tắt tiếng (M)")
                    }
                    .padding(.horizontal, 2)
                }
            } else {
                // Empty state when no video is loaded
                VStack(spacing: 10) {
                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.system(size: 28))
                        .foregroundColor(textSecondary.opacity(0.6))
                    Text("Chưa phát video nào")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(textSecondary)
                    Text("Tìm kiếm hoặc bấm mở video trong AuraTube")
                        .font(.system(size: 11))
                        .foregroundColor(textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: playerManager.isCurrentVideoVertical ? 300 : 320)
        .background(
            ZStack {
                // Native ultra-thin glass material base
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                
                // Adaptive rich surface tint
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isDark ?
                        LinearGradient(
                            colors: [
                                Color(red: 24/255, green: 24/255, blue: 28/255).opacity(0.92),
                                Color(red: 16/255, green: 16/255, blue: 20/255).opacity(0.94)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ) :
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.96),
                                Color(red: 248/255, green: 248/255, blue: 250/255).opacity(0.96)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isDark ?
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ) :
                    LinearGradient(
                        colors: [Color.black.opacity(0.10), Color.black.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(
            color: Color.black.opacity(isDark ? 0.40 : 0.12),
            radius: 12,
            x: 0,
            y: 4
        )
        .preferredColorScheme(themeManager.colorScheme)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: playerManager.isCurrentVideoVertical)
    }
    
    // MARK: - Interactive Custom Timeline Scrubber
    private var timelineScrubber: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let total = max(1.0, effectiveDuration)
                let progress = max(0.0, min(1.0, effectiveCurrentTime / total))
                
                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.10))
                        .frame(height: vm.isHoveringBar || vm.isScrubbing ? 5 : 3.5)
                    
                    // Active played fill (YouTube Red)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.red, Color(red: 1.0, green: 0.25, blue: 0.25)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: max(4, geo.size.width * CGFloat(progress)),
                            height: vm.isHoveringBar || vm.isScrubbing ? 5 : 3.5
                        )
                    
                    // Scrub thumb
                    if vm.isHoveringBar || vm.isScrubbing {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                            .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                            .offset(x: max(0, min(geo.size.width - 10, geo.size.width * CGFloat(progress) - 5)))
                    }
                }
                .frame(height: 12)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            let pct = max(0.0, min(1.0, val.location.x / geo.size.width))
                            vm.isScrubbing = true
                            vm.scrubTime = pct * total
                        }
                        .onEnded { val in
                            let pct = max(0.0, min(1.0, val.location.x / geo.size.width))
                            let target = pct * total
                            playerManager.seek(to: target)
                            vm.isScrubbing = false
                        }
                )
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        vm.isHoveringBar = hovering
                    }
                }
            }
            .frame(height: 12)
            
            // Time Labels (Elapsed / Total)
            HStack {
                Text(formatTime(effectiveCurrentTime))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(textTertiary)
                Spacer()
                Text(formatTime(effectiveDuration))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(textTertiary)
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds >= 0 else { return "0:00" }
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
