import SwiftUI
import AppKit

@MainActor
final class FullscreenViewModel: ObservableObject {
    @Published var isControlsVisible: Bool = true
    var hideTimer: Timer? = nil
    var mouseMonitor: Any? = nil
    var keyMonitor: Any? = nil
}

public struct FullscreenVideoOverlay: View {
    let video: Video
    
    @ObservedObject private var playerManager = PlayerManager.shared
    @StateObject private var vm = FullscreenViewModel()
    
    public init(video: Video) {
        self.video = video
    }
    
    private var isVertical: Bool {
        // 1. Kiểm tra video prop
        if video.isShort || video.isExplicitShort == true || video.durationFormatted == "Shorts" { return true }
        let vt = video.title.lowercased()
        if vt.contains("short") || vt.contains("tiktok") || vt.contains("reels") { return true }
        if let d = video.duration, d > 0 && d <= 240 { return true }
        
        // 2. Kiểm tra PlayerManager.currentVideo
        if let cur = playerManager.currentVideo {
            if cur.isShort || cur.isExplicitShort == true || cur.durationFormatted == "Shorts" { return true }
            let ct = cur.title.lowercased()
            if ct.contains("short") || ct.contains("tiktok") || ct.contains("reels") { return true }
            if let d = cur.duration, d > 0 && d <= 240 { return true }
        }
        
        // 3. Kiểm tra cờ PlayerManager
        if playerManager.isCurrentVideoVertical { return true }
        if playerManager.duration > 0 && playerManager.duration <= 240 { return true }
        
        // 4. Nếu tỷ lệ player hiện tại < 1.45 (bao gồm cả 4:3 SD của shorts embed, 1:1, 9:16)
        if playerManager.currentVideoAspectRatio < 1.45 { return true }
        
        return false
    }
    
    private var currentRatio: Double {
        if isVertical {
            return 9.0 / 16.0
        }
        // Chỉ chấp nhận tỷ lệ ngang chuẩn 16:9
        if playerManager.currentVideoAspectRatio >= 1.5 && playerManager.currentVideoAspectRatio <= 2.6 {
            return playerManager.currentVideoAspectRatio
        }
        return 16.0 / 9.0
    }
    
    public var body: some View {
        ZStack(alignment: .center) {
            // Pure black background covering whole display
            Color.black
                .ignoresSafeArea()
            
            
            // Video Player centered with exact aspect ratio (Clean containment, no zoom crop)
            GeometryReader { geo in
                let screenW = geo.size.width
                let screenH = geo.size.height
                
                // Khi là video dọc/shorts, ép chuẩn 9:16 vừa vặn chiều cao màn hình, tuyệt đối không zoom crop
                let targetH: CGFloat = isVertical ? screenH : min(screenH, screenW / CGFloat(currentRatio))
                let targetW: CGFloat = isVertical ? (screenH * 9.0 / 16.0) : (targetH * CGFloat(currentRatio))
                
                ZStack {
                    NativePlayerView(cornerRadius: 0)
                        .frame(width: targetW, height: targetH)
                    
                    // Click to play/pause, double click to exit fullscreen
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .frame(width: targetW, height: targetH)
                        .onTapGesture(count: 2) {
                            playerManager.toggleFullscreen()
                        }
                        .simultaneousGesture(
                            TapGesture(count: 1).onEnded {
                                playerManager.togglePlayPause()
                                showControlsAndResetTimer()
                            }
                        )
                }
                .frame(width: targetW, height: targetH)
                .position(x: screenW / 2, y: screenH / 2)
            }
            
            // Autoplay Countdown Overlay in Fullscreen
            if playerManager.autoplayCountdown != nil, let next = playerManager.nextVideo {
                AutoplayCountdownOverlay(video: next)
                    .zIndex(50)
            }
            
            // Top and Bottom Controls Overlay
            VStack(spacing: 0) {
                // Top Bar: Back/Exit button, Title, Uploader
                if vm.isControlsVisible {
                    HStack(spacing: 16) {
                        Button(action: {
                            playerManager.toggleFullscreen()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .bold))
                                Text("Thoát toàn màn hình")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Thoát toàn màn hình (Esc hoặc F)")
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(video.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(video.uploader)
                                .font(.system(size: 12.5))
                                .foregroundColor(Color.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .background(
                        LinearGradient(
                            stops: [
                                .init(color: Color.black.opacity(0.85), location: 0.0),
                                .init(color: Color.black.opacity(0.4), location: 0.6),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 100)
                        .allowsHitTesting(false),
                        alignment: .top
                    )
                    .transition(.opacity)
                }
                
                Spacer()
                
                // Bottom Controls: PlayerControlOverlay (Full-width edge-to-edge)
                if vm.isControlsVisible {
                    PlayerControlOverlay()
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            setupMonitors()
            showControlsAndResetTimer()
        }
        .onDisappear {
            cleanupMonitors()
        }
    }
    
    private func setupMonitors() {
        // Keyboard shortcuts in fullscreen
        vm.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc key (53)
            if event.keyCode == 53 {
                playerManager.toggleFullscreen()
                return nil
            }
            // F or f key (3)
            if event.keyCode == 3 || event.charactersIgnoringModifiers == "f" || event.charactersIgnoringModifiers == "F" {
                playerManager.toggleFullscreen()
                return nil
            }
            // Space (49)
            if event.keyCode == 49 {
                playerManager.togglePlayPause()
                showControlsAndResetTimer()
                return nil
            }
            // Left arrow (123)
            if event.keyCode == 123 {
                playerManager.seekRelative(-10)
                showControlsAndResetTimer()
                return nil
            }
            // Right arrow (124)
            if event.keyCode == 124 {
                playerManager.seekRelative(10)
                showControlsAndResetTimer()
                return nil
            }
            // Up arrow (126) - volume up
            if event.keyCode == 126 {
                playerManager.volume = min(1.0, playerManager.volume + 0.05)
                showControlsAndResetTimer()
                return nil
            }
            // Down arrow (125) - volume down
            if event.keyCode == 125 {
                playerManager.volume = max(0.0, playerManager.volume - 0.05)
                showControlsAndResetTimer()
                return nil
            }
            // M or m (46) - mute
            if event.keyCode == 46 || event.charactersIgnoringModifiers == "m" || event.charactersIgnoringModifiers == "M" {
                playerManager.toggleMute()
                showControlsAndResetTimer()
                return nil
            }
            return event
        }
        
        // Mouse movement monitor: wake up controls when mouse moves or clicks
        vm.mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown]) { event in
            showControlsAndResetTimer()
            return event
        }
    }
    
    private func cleanupMonitors() {
        if let km = vm.keyMonitor {
            NSEvent.removeMonitor(km)
            vm.keyMonitor = nil
        }
        if let mm = vm.mouseMonitor {
            NSEvent.removeMonitor(mm)
            vm.mouseMonitor = nil
        }
        vm.hideTimer?.invalidate()
        vm.hideTimer = nil
        NSCursor.unhide()
    }
    
    private func showControlsAndResetTimer() {
        NSCursor.unhide()
        if !vm.isControlsVisible {
            withAnimation(.easeInOut(duration: 0.2)) {
                vm.isControlsVisible = true
            }
        }
        vm.hideTimer?.invalidate()
        vm.hideTimer = Timer.scheduledTimer(withTimeInterval: 2.8, repeats: false) { _ in
            Task { @MainActor in
                if playerManager.isPlaying && playerManager.isVideoFullscreen {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        vm.isControlsVisible = false
                    }
                    NSCursor.setHiddenUntilMouseMoves(true)
                }
            }
        }
    }
}
