import SwiftUI
import AppKit

// MARK: - Dedicated Borderless Floating PiP Panel
public final class PiPPanel: NSPanel {
    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }
    
    // Completely suppress default macOS window buttons (no traffic lights at all!)
    override public func standardWindowButton(_ b: NSWindow.ButtonType) -> NSButton? {
        return nil
    }
    
    override public func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            if !isKeyWindow {
                makeKeyAndOrderFront(nil)
            }
        }
        
        // Intercept keyboard shortcuts before WebKit / child views can consume them
        if event.type == .keyDown {
            if PiPWindowController.shared.handleKeyDown(event) {
                return
            }
        }
        
        super.sendEvent(event)
    }
}

// MARK: - Native PiP Window Drag View (Hardware-Accelerated Window Moving)
public struct PiPWindowDragView: NSViewRepresentable {
    public init() {}
    
    public func makeNSView(context: Context) -> DragView {
        DragView()
    }
    
    public func updateNSView(_ nsView: DragView, context: Context) {}
    
    public final class DragView: NSView {
        override public func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                PiPWindowController.shared.toggleSnapSize()
                return
            }
            self.window?.performDrag(with: event)
        }
    }
}

// MARK: - PiP Visual HUD State Manager
@MainActor
public final class PiPOverlayState: ObservableObject {
    public static let shared = PiPOverlayState()
    
    @Published public var hudIcon: String = ""
    @Published public var hudText: String = ""
    @Published public var isHudVisible: Bool = false
    @Published public var isHovering: Bool = false
    @Published public var isProgressHovered: Bool = false
    
    private var hideTimer: Timer?
    
    public func triggerHUD(icon: String, text: String) {
        hideTimer?.invalidate()
        hudIcon = icon
        hudText = text
        withAnimation(.easeOut(duration: 0.15)) {
            isHudVisible = true
        }
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                withAnimation(.easeIn(duration: 0.25)) {
                    self?.isHudVisible = false
                }
            }
        }
    }
}

// MARK: - Native macOS Floating Picture-in-Picture Window Controller
@MainActor
public final class PiPWindowController: NSObject, ObservableObject, NSWindowDelegate {
    public static let shared = PiPWindowController()
    
    private static let pipWidthKey = "auratube_default_pip_width"
    
    @Published public var defaultWidth: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(defaultWidth), forKey: Self.pipWidthKey)
        }
    }
    
    public private(set) var pipWindow: PiPPanel?
    public func isPipWindow(_ window: NSWindow?) -> Bool {
        guard let w = window else { return false }
        return w === pipWindow
    }
    private var eventMonitor: Any?
    
    public override init() {
        let saved = UserDefaults.standard.double(forKey: Self.pipWidthKey)
        self.defaultWidth = saved > 0 ? CGFloat(saved) : 540
        super.init()
    }
    
    public func show(video: Video?) {
        if let existing = pipWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        
        let initialWidth: CGFloat = defaultWidth
        let initialHeight: CGFloat = defaultWidth * (9.0 / 16.0)
        
        // Position at bottom-right corner of main screen
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screenFrame.maxX - initialWidth - 28
        let y = screenFrame.minY + 28
        
        let panel = PiPPanel(
            contentRect: NSRect(x: x, y: y, width: initialWidth, height: initialHeight),
            styleMask: [.titled, .fullSizeContentView, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.showsToolbarButton = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.minSize = NSSize(width: 300, height: 300 * (9.0 / 16.0))
        panel.maxSize = NSSize(width: 960, height: 960 * (9.0 / 16.0))
        panel.aspectRatio = NSSize(width: 16, height: 9)
        panel.delegate = self
        
        // Extra safety: aggressively strip out any default window chrome buttons
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.closeButton)?.removeFromSuperview()
        panel.standardWindowButton(.miniaturizeButton)?.removeFromSuperview()
        panel.standardWindowButton(.zoomButton)?.removeFromSuperview()
        
        let hostingView = NSHostingView(rootView: PiPFloatingContentView().ignoresSafeArea())
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 16
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView
        
        self.pipWindow = panel
        
        // Register local key event monitor
        self.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let pip = self.pipWindow, pip.isKeyWindow else { return event }
            if self.handleKeyDown(event) {
                return nil
            }
            return event
        }
        
        // Smooth fade-in
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        panel.animator().alphaValue = 1.0
    }
    
    public func close() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        guard let panel = pipWindow else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                panel.close()
                self?.pipWindow = nil
            }
        })
    }
    
    public func returnToMainWindow() {
        PlayerManager.shared.togglePictureInPicture()
        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow = NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeKey }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }
    
    public var currentWidth: CGFloat {
        pipWindow?.frame.width ?? defaultWidth
    }
    
    public func toggleSnapSize() {
        let currentW = currentWidth
        let targetWidth: CGFloat
        if currentW < 420 {
            targetWidth = 540
        } else if currentW < 600 {
            targetWidth = 720
        } else {
            targetWidth = 380
        }
        setPipSize(width: targetWidth)
    }
    
    public func setPipSize(width targetWidth: CGFloat) {
        defaultWidth = targetWidth
        objectWillChange.send()
        
        guard let panel = pipWindow else { return }
        let targetHeight = targetWidth * (9.0 / 16.0)
        let currentFrame = panel.frame
        let newX = currentFrame.maxX - targetWidth
        let newY = currentFrame.minY
        let newFrame = NSRect(x: newX, y: newY, width: targetWidth, height: targetHeight)
        panel.setFrame(newFrame, display: true, animate: true)
        
        let label = targetWidth >= 700 ? "Lớn (720p)" : (targetWidth >= 500 ? "Trung bình (540p)" : "Nhỏ (380p)")
        PiPOverlayState.shared.triggerHUD(icon: "aspectratio", text: label)
    }
    
    public func windowDidResize(_ notification: Notification) {
        if let panel = pipWindow {
            defaultWidth = panel.frame.width
            objectWillChange.send()
        }
    }
    
    @discardableResult
    public func handleKeyDown(_ event: NSEvent) -> Bool {
        let pm = PlayerManager.shared
        switch event.keyCode {
        case 49, 40: // Space or K: Toggle Play/Pause
            let willPlay = !pm.isPlaying
            pm.togglePlayPause()
            PiPOverlayState.shared.triggerHUD(
                icon: willPlay ? "play.fill" : "pause.fill",
                text: willPlay ? "Phát" : "Tạm dừng"
            )
            return true
            
        case 46: // M: Toggle Mute
            let willMute = !pm.isMuted
            pm.toggleMute()
            let volPct = Int(pm.volume * 100)
            PiPOverlayState.shared.triggerHUD(
                icon: willMute ? "speaker.slash.fill" : "speaker.wave.2.fill",
                text: willMute ? "Đã tắt tiếng" : "Âm lượng \(volPct)%"
            )
            return true
            
        case 35: // P: Toggle PiP / Return to main
            returnToMainWindow()
            return true
            
        case 53: // Esc: Close PiP
            pm.togglePictureInPicture()
            return true
            
        case 3: // F: Return to main window
            returnToMainWindow()
            return true
            
        case 123, 38: // Left Arrow or J: Seek -10s
            pm.seekRelative(-10)
            PiPOverlayState.shared.triggerHUD(icon: "gobackward.10", text: "-10 giây")
            return true
            
        case 124, 37: // Right Arrow or L: Seek +10s
            pm.seekRelative(10)
            PiPOverlayState.shared.triggerHUD(icon: "goforward.10", text: "+10 giây")
            return true
            
        case 126: // Up Arrow: Volume Up
            let newVol = min(1.0, pm.volume + 0.05)
            pm.volume = newVol
            pm.isMuted = false
            PiPOverlayState.shared.triggerHUD(icon: "speaker.wave.3.fill", text: "\(Int(newVol * 100))%")
            return true
            
        case 125: // Down Arrow: Volume Down
            let newVol = max(0.0, pm.volume - 0.05)
            pm.volume = newVol
            let iconName = newVol <= 0.01 ? "speaker.slash.fill" : (newVol < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")
            PiPOverlayState.shared.triggerHUD(icon: iconName, text: "\(Int(newVol * 100))%")
            return true
            
        case 29: seekPercent(0.0); return true // 0
        case 18: seekPercent(0.1); return true // 1
        case 19: seekPercent(0.2); return true // 2
        case 20: seekPercent(0.3); return true // 3
        case 21: seekPercent(0.4); return true // 4
        case 23: seekPercent(0.5); return true // 5
        case 22: seekPercent(0.6); return true // 6
        case 26: seekPercent(0.7); return true // 7
        case 28: seekPercent(0.8); return true // 8
        case 25: seekPercent(0.9); return true // 9
            
        default:
            return false
        }
    }
    
    private func seekPercent(_ pct: Double) {
        let target = PlayerManager.shared.duration * pct
        PlayerManager.shared.seek(to: target)
        PiPOverlayState.shared.triggerHUD(icon: "clock.arrow.circlepath", text: "\(Int(pct * 100))%")
    }
    
    public func windowWillClose(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        pipWindow = nil
        if PlayerManager.shared.isPictureInPictureActive {
            PlayerManager.shared.isPictureInPictureActive = false
        }
    }
}

// MARK: - Floating PiP Content View (100% Tràn Viền Edge-to-Edge)
public struct PiPFloatingContentView: View {
    @ObservedObject private var playerManager = PlayerManager.shared
    @ObservedObject private var clock = PlaybackClock.shared
    @ObservedObject private var hud = PiPOverlayState.shared
    
    private var effectiveDuration: Double {
        clock.duration > 0 ? clock.duration : playerManager.duration
    }
    
    private var effectiveTime: Double {
        clock.currentTime > 0 ? clock.currentTime : playerManager.currentTime
    }
    
    public var body: some View {
        ZStack {
            Color.black
            
            // 1. Full-bleed edge-to-edge Native Video Player
            NativePlayerView(cornerRadius: 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // 2. Interactive Control Overlay (On Hover)
            if hud.isHovering {
                ZStack {
                    // Window drag surface in background (drag anywhere to move window, double click to snap size)
                    PiPWindowDragView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Cinematic gradient vignetting
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.82),
                            Color.black.opacity(0.15),
                            Color.black.opacity(0.85)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                    
                    VStack(spacing: 0) {
                        // Top Navigation / Header Bar
                        topHeaderBar
                            .padding(.top, 10)
                            .padding(.horizontal, 12)
                        
                        Spacer()
                        
                        // Bottom Timeline & Playback Controls
                        bottomControlsBar
                            .padding(.bottom, 10)
                            .padding(.horizontal, 12)
                    }
                }
                .transition(.opacity)
            }
            
            // 3. Animated Center HUD Badge (Space / Mute / Seek feedback)
            if hud.isHudVisible {
                VStack(spacing: 6) {
                    Image(systemName: hud.hudIcon)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                    if !hud.hudText.isEmpty {
                        Text(hud.hudText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.75))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(hud.isHovering ? 0.30 : 0.16),
                            Color.white.opacity(hud.isHovering ? 0.12 : 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.18)) {
                hud.isHovering = hovering
            }
        }
        .contextMenu {
            Button {
                PiPWindowController.shared.returnToMainWindow()
            } label: {
                Label("Đưa video về cửa sổ chính (P)", systemImage: "arrow.up.forward.app")
            }
            
            Divider()
            
            Button("Kích thước: Nhỏ (380p)") {
                PiPWindowController.shared.setPipSize(width: 380)
            }
            Button("Kích thước: Trung bình (540p)") {
                PiPWindowController.shared.setPipSize(width: 540)
            }
            Button("Kích thước: Lớn (720p)") {
                PiPWindowController.shared.setPipSize(width: 720)
            }
            
            Divider()
            
            Toggle("Tự động chuyển PiP khi chuyển app", isOn: $playerManager.autoPiPOnAppSwitch)
            Toggle("Tắt PiP khi bấm lại app chính", isOn: $playerManager.autoReturnPiPOnAppFocus)
        }
    }
    
    // MARK: - Top Header Bar
    private var topHeaderBar: some View {
        HStack(spacing: 10) {
            // Close PiP Button
            Button(action: {
                PlayerManager.shared.togglePictureInPicture()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.black.opacity(0.65)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .help("Đóng PiP (Esc)")
            
            // Video Title & Channel Info
            if let video = playerManager.currentVideo {
                VStack(alignment: .leading, spacing: 1) {
                    Text(video.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    if !video.uploader.isEmpty {
                        Text(video.uploader)
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundColor(Color(white: 0.72))
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Snap Size Button (Cycle between 380p, 540p, 720p)
            Button(action: {
                PiPWindowController.shared.toggleSnapSize()
            }) {
                Image(systemName: "aspectratio")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.black.opacity(0.65)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Kích thước: Nhỏ (380p)") {
                    PiPWindowController.shared.setPipSize(width: 380)
                }
                Button("Kích thước: Trung bình (540p)") {
                    PiPWindowController.shared.setPipSize(width: 540)
                }
                Button("Kích thước: Lớn (720p)") {
                    PiPWindowController.shared.setPipSize(width: 720)
                }
            }
            .help("Bấm để đổi kích thước PiP (380p / 540p / 720p) hoặc chuột phải để chọn")
            
            // Return to Main Window / App Button
            Button(action: {
                PiPWindowController.shared.returnToMainWindow()
            }) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.black.opacity(0.65)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .help("Đưa video về cửa sổ chính (P / F)")
        }
    }
    
    // MARK: - Bottom Controls Bar
    private var bottomControlsBar: some View {
        VStack(spacing: 8) {
            // Timeline Progress Scrubber
            PiPInteractiveProgressBar()
            
            HStack(spacing: 12) {
                // Seek backward 10s
                Button(action: {
                    playerManager.seekRelative(-10)
                    hud.triggerHUD(icon: "gobackward.10", text: "-10s")
                }) {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .help("Lùi 10 giây (← / J)")
                
                // Play / Pause Button
                Button(action: {
                    playerManager.togglePlayPause()
                    hud.triggerHUD(
                        icon: playerManager.isPlaying ? "pause.fill" : "play.fill",
                        text: playerManager.isPlaying ? "Tạm dừng" : "Phát"
                    )
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.22))
                        Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help("Phát / Tạm dừng (Space / K)")
                
                // Seek forward 10s
                Button(action: {
                    playerManager.seekRelative(10)
                    hud.triggerHUD(icon: "goforward.10", text: "+10s")
                }) {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .help("Tiến 10 giây (→ / L)")
                
                // Time label (Current / Total)
                HStack(spacing: 3) {
                    Text(formatSeconds(effectiveTime))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                    Text("/")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                    Text(formatSeconds(effectiveDuration))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                }
                .padding(.leading, 2)
                
                Spacer()
                
                // Mute / Unmute Button
                Button(action: {
                    playerManager.toggleMute()
                    hud.triggerHUD(
                        icon: playerManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        text: playerManager.isMuted ? "Đã tắt tiếng" : "Âm lượng \(Int(playerManager.volume * 100))%"
                    )
                }) {
                    Image(systemName: playerManager.isMuted ? "speaker.slash.fill" : (playerManager.volume > 0.5 ? "speaker.wave.2.fill" : "speaker.wave.1.fill"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Tắt/Bật tiếng (M)")
                
                // Mini Volume Scrub Slider
                GeometryReader { volGeo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.25))
                            .frame(height: 4)
                        Capsule()
                            .fill(Color.white)
                            .frame(width: volGeo.size.width * CGFloat(playerManager.isMuted ? 0 : playerManager.volume), height: 4)
                    }
                    .frame(height: 18)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                let pct = max(0.0, min(1.0, val.location.x / volGeo.size.width))
                                playerManager.volume = pct
                                playerManager.isMuted = false
                            }
                    )
                }
                .frame(width: 48, height: 18)
                .help("Kéo chỉnh âm lượng (hoặc phím ↑ / ↓)")
                
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
                )
        )
    }
    
    
    private func formatSeconds(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        let hrs = s / 3600
        let mins = (s % 3600) / 60
        let secs = s % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        } else {
            return String(format: "%d:%02d", mins, secs)
        }
    }
}

// MARK: - High-Precision PiP Interactive Progress Bar
public struct PiPInteractiveProgressBar: View {
    @ObservedObject private var playerManager = PlayerManager.shared
    @ObservedObject private var clock = PlaybackClock.shared
    @ObservedObject private var hud = PiPOverlayState.shared
    
    private var effectiveDuration: Double {
        clock.duration > 0 ? clock.duration : playerManager.duration
    }
    
    private var effectiveTime: Double {
        clock.currentTime > 0 ? clock.currentTime : playerManager.currentTime
    }
    
    public var body: some View {
        GeometryReader { geo in
            let total = max(1.0, effectiveDuration)
            let progress = max(0.0, min(1.0, effectiveTime / total))
            
            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.white.opacity(0.24))
                    .frame(height: hud.isProgressHovered ? 5 : 3)
                
                // Played Progress (YouTube Red gradient)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color(red: 1.0, green: 0.25, blue: 0.25)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, geo.size.width * CGFloat(progress)), height: hud.isProgressHovered ? 5 : 3)
                
                // Scrub thumb
                if hud.isProgressHovered {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .shadow(radius: 2)
                        .offset(x: max(0, min(geo.size.width - 10, geo.size.width * CGFloat(progress) - 5)))
                }
            }
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        let pct = max(0.0, min(1.0, val.location.x / geo.size.width))
                        let targetSec = pct * total
                        playerManager.seek(to: targetSec)
                    }
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    hud.isProgressHovered = hovering
                }
            }
        }
        .frame(height: 10)
    }
}
