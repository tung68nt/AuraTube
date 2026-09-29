import SwiftUI
import AppKit

// MARK: - Dedicated Borderless Floating PiP Panel
public final class PiPPanel: NSPanel {
    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }
    
    // Remove all standard window traffic light buttons for a clean, borderless custom UI
    override public func standardWindowButton(_ b: NSWindow.ButtonType) -> NSButton? {
        let btn = super.standardWindowButton(b)
        btn?.isHidden = true
        btn?.removeFromSuperview()
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
    @Published public var isMenuOpen: Bool = false
    @Published public var isHovering: Bool = false {
        didSet {
            PiPWindowController.shared.updateWindowControlsHover(isHovering || isMenuOpen)
        }
    }
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
    public var mainPlayerScreenFrame: NSRect?
    @Published public var isPiPHiddenKeepAudio: Bool = false
    
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
    
    public func captureMainPlayerScreenFrame() {
        if let wv = MainWebPlayerPool.shared.webView, let win = wv.window, !(win is NSPanel), wv.bounds.width > 200 && wv.bounds.height > 100 {
            let screenRect = win.convertToScreen(wv.convert(wv.bounds, to: nil))
            if screenRect.width > 200 && screenRect.height > 100 {
                mainPlayerScreenFrame = screenRect
            }
        }
    }
    
    public func show(video: Video?) {
        if let existing = pipWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        
        let isVertical = video?.isShort == true || PlayerManager.shared.isCurrentVideoVertical
        // For vertical (Shorts), standard ideal PiP dimensions: width 270, height 480 (9:16)
        let initialWidth: CGFloat = round(isVertical ? 270 : defaultWidth)
        let initialHeight: CGFloat = round(isVertical ? (initialWidth * 16.0 / 9.0) : (initialWidth * 9.0 / 16.0))
        
        // Target screen: Prefer the screen of the active window playing the video
        let activeScreen: NSScreen = {
            if let wv = MainWebPlayerPool.shared.webView, let win = wv.window, let s = win.screen {
                return s
            }
            if let mainWin = NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeKey }), let s = mainWin.screen {
                return s
            }
            return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        }()
        
        let screenFrame = activeScreen.visibleFrame
        let targetX = round(screenFrame.maxX - initialWidth - 28)
        let targetY = round(screenFrame.minY + 28)
        let targetFrame = NSRect(x: targetX, y: targetY, width: initialWidth, height: initialHeight)
        
        // Grab live screen geometry of webView if valid
        if let wv = MainWebPlayerPool.shared.webView, let win = wv.window, !(win is NSPanel), wv.bounds.width > 200 && wv.bounds.height > 100 {
            let screenRect = win.convertToScreen(wv.convert(wv.bounds, to: nil))
            if screenRect.width > 200 && screenRect.height > 100 {
                mainPlayerScreenFrame = screenRect
            }
        }
        
        // Start from main window video player's exact screen geometry if available for a 100% seamless transition
        let startFrame: NSRect = {
            if let frame = mainPlayerScreenFrame, frame.width > 200 && frame.height > 100 {
                return frame
            }
            return targetFrame
        }()
        
        let panel = PiPPanel(
            contentRect: startFrame,
            styleMask: [.titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.setFrame(startFrame, display: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.showsToolbarButton = false
        panel.animationBehavior = .none
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // Cap vertical PiP cleanly: min height 320, max height 576 (never covers screen height!)
        panel.minSize = isVertical ? NSSize(width: 180, height: 320) : NSSize(width: 320, height: 180)
        panel.maxSize = isVertical ? NSSize(width: 324, height: 576) : NSSize(width: 960, height: 540)
        panel.aspectRatio = isVertical ? NSSize(width: 9, height: 16) : NSSize(width: 16, height: 9)
        panel.delegate = self
        
        // Strip out all standard window buttons (red close, yellow miniaturize, green zoom)
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.closeButton)?.removeFromSuperview()
        panel.standardWindowButton(.miniaturizeButton)?.removeFromSuperview()
        panel.standardWindowButton(.zoomButton)?.removeFromSuperview()
        
        let hostingView = NSHostingView(rootView: PiPFloatingContentView().ignoresSafeArea())
        hostingView.frame = NSRect(x: 0, y: 0, width: startFrame.width, height: startFrame.height)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 16
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView
        
        self.pipWindow = panel
        self.isPiPHiddenKeepAudio = false
        
        // Register local key event monitor
        self.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let pip = self.pipWindow, pip.isKeyWindow else { return event }
            if self.handleKeyDown(event) {
                return nil
            }
            return event
        }
        
        ScrollForwardingWKWebView.isTransitioning = true
        panel.alphaValue = 1.0
        panel.makeKeyAndOrderFront(nil)
        
        if startFrame != targetFrame {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.36
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(targetFrame, display: true)
            }, completionHandler: {
                panel.invalidateShadow()
                DispatchQueue.main.async {
                    ScrollForwardingWKWebView.isTransitioning = false
                    if let swv = MainWebPlayerPool.shared.webView as? ScrollForwardingWKWebView {
                        swv.triggerRelayout()
                    }
                }
            })
        } else {
            ScrollForwardingWKWebView.isTransitioning = false
            if let swv = MainWebPlayerPool.shared.webView as? ScrollForwardingWKWebView {
                swv.triggerRelayout()
            }
        }
    }
    
    public func close() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isPiPHiddenKeepAudio = false
        guard let panel = pipWindow else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                panel.close()
                self?.pipWindow = nil
                self?.isPiPHiddenKeepAudio = false
            }
        })
    }
    
    // MARK: - Hide PiP & Keep Audio Playing in Background
    public func hidePiPKeepAudio() {
        guard let panel = pipWindow, !isPiPHiddenKeepAudio else { return }
        isPiPHiddenKeepAudio = true
        PiPOverlayState.shared.triggerHUD(icon: "headphones", text: "Đang phát âm thanh trong nền 🎧")
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        }, completionHandler: { [weak self, weak panel] in
            Task { @MainActor [weak self, weak panel] in
                guard let self = self, self.isPiPHiddenKeepAudio else { return }
                panel?.orderOut(nil)
            }
        })
    }
    
    public func unhidePiP() {
        guard let panel = pipWindow, isPiPHiddenKeepAudio else { return }
        isPiPHiddenKeepAudio = false
        panel.alphaValue = 0.0
        panel.makeKeyAndOrderFront(nil)
        PiPOverlayState.shared.triggerHUD(icon: "pip.enter", text: "Đã hiện lại PiP")
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            panel.animator().alphaValue = 1.0
        }, completionHandler: {
            panel.invalidateShadow()
        })
    }
    
    public func toggleHidePiPKeepAudio() {
        if isPiPHiddenKeepAudio {
            unhidePiP()
        } else {
            hidePiPKeepAudio()
        }
    }
    
    public func returnToMainWindow() {
        guard let panel = pipWindow else {
            isPiPHiddenKeepAudio = false
            PlayerManager.shared.isPictureInPictureActive = false
            PlayerManager.shared.refreshPlayerLayout()
            return
        }
        
        isPiPHiddenKeepAudio = false
        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow = NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeKey }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
        
        ScrollForwardingWKWebView.isTransitioning = true
        panel.makeKeyAndOrderFront(nil)
        panel.alphaValue = 1.0
        
        if let targetFrame = mainPlayerScreenFrame, targetFrame.width > 200 && targetFrame.height > 100 {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.32
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(targetFrame, display: true)
            }, completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if let monitor = self.eventMonitor {
                        NSEvent.removeMonitor(monitor)
                        self.eventMonitor = nil
                    }
                    self.isPiPHiddenKeepAudio = false
                    // 1. Tell PlayerManager to return to main player
                    PlayerManager.shared.isPictureInPictureActive = false
                    
                    // 2. Keep panel overlaying seamlessly for 40ms while WatchView attaches the webView
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                        ScrollForwardingWKWebView.isTransitioning = false
                        panel.orderOut(nil)
                        panel.close()
                        self.pipWindow = nil
                        PlayerManager.shared.refreshPlayerLayout()
                    }
                }
            })
        } else {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
            PlayerManager.shared.isPictureInPictureActive = false
            panel.close()
            self.pipWindow = nil
            ScrollForwardingWKWebView.isTransitioning = false
            PlayerManager.shared.refreshPlayerLayout()
        }
    }
    
    public var currentWidth: CGFloat {
        pipWindow?.frame.width ?? defaultWidth
    }
    
    public var isPanelVertical: Bool {
        guard let panel = pipWindow else {
            return PlayerManager.shared.isCurrentVideoVertical || PlayerManager.shared.currentVideo?.isShort == true
        }
        return panel.frame.height > panel.frame.width
    }
    
    public func toggleSnapSize() {
        if isPanelVertical {
            let currentH = pipWindow?.frame.height ?? 480
            let targetH: CGFloat
            if currentH < 440 {
                targetH = 480
            } else if currentH < 520 {
                targetH = 560
            } else {
                targetH = 384
            }
            setPipVerticalSize(height: targetH)
        } else {
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
    }
    
    public func setPipVerticalSize(height targetHeight: CGFloat) {
        guard let panel = pipWindow else { return }
        let targetWidth = targetHeight * (9.0 / 16.0)
        let currentFrame = panel.frame
        let newX = currentFrame.maxX - targetWidth
        let newY = currentFrame.minY
        let newFrame = NSRect(x: newX, y: newY, width: targetWidth, height: targetHeight)
        panel.setFrame(newFrame, display: true, animate: true)
        
        let label = targetHeight >= 540 ? "Lớn (560p dọc)" : (targetHeight >= 450 ? "Tiêu chuẩn (480p dọc)" : "Nhỏ (384p dọc)")
        PiPOverlayState.shared.triggerHUD(icon: "aspectratio", text: label)
    }
    
    public func setPipSize(width targetWidth: CGFloat) {
        if isPanelVertical {
            setPipVerticalSize(height: targetWidth * (16.0 / 9.0))
            return
        }
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
        // Giữ resize mượt mà 120Hz; không spam UserDefaults hay re-render view trong lúc kéo chuột
    }
    
    public func windowDidEndLiveResize(_ notification: Notification) {
        if let panel = pipWindow, !isPanelVertical {
            defaultWidth = panel.frame.width
            UserDefaults.standard.set(Double(panel.frame.width), forKey: Self.pipWidthKey)
        }
    }
    
    public func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        guard let panel = pipWindow else { return newFrame }
        let isVertical = isPanelVertical
        let screen = panel.screen ?? NSScreen.main ?? NSScreen()
        let screenFrame = screen.visibleFrame
        if isVertical {
            let targetH: CGFloat = panel.frame.height >= 500 ? 384 : 560
            let targetW = targetH * (9.0 / 16.0)
            let newX = min(panel.frame.maxX - targetW, screenFrame.maxX - targetW)
            return NSRect(x: newX, y: panel.frame.minY, width: targetW, height: targetH)
        } else {
            let targetW: CGFloat = panel.frame.width >= 540 ? 380 : 720
            let targetH = targetW * (9.0 / 16.0)
            let newX = min(panel.frame.maxX - targetW, screenFrame.maxX - targetW)
            return NSRect(x: newX, y: panel.frame.minY, width: targetW, height: targetH)
        }
    }
    
    public func updateWindowControlsHover(_ isHovering: Bool) {}
    
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
            
        case 45: // N: Next Video (or Shift+N)
            pm.playNextVideo()
            PiPOverlayState.shared.triggerHUD(icon: "forward.end.fill", text: "Video tiếp theo")
            return true
            
        case 35: // P: Toggle PiP / Return to main (or Shift+P for previous video)
            if event.modifierFlags.contains(.shift) {
                pm.playPreviousVideo()
                PiPOverlayState.shared.triggerHUD(icon: "backward.end.fill", text: "Video trước")
            } else {
                returnToMainWindow()
            }
            return true
            
        case 4: // H: Hide PiP (Keep Audio Playing in Background)
            toggleHidePiPKeepAudio()
            return true
            
        case 53: // Esc: Close PiP
            pm.togglePictureInPicture()
            return true
            
        case 3: // F: Return to main window
            returnToMainWindow()
            return true
            
        case 123: // Left Arrow: Cmd+Left for previous video, or Seek -10s
            if event.modifierFlags.contains(.command) {
                pm.playPreviousVideo()
                PiPOverlayState.shared.triggerHUD(icon: "backward.end.fill", text: "Video trước")
            } else {
                pm.seekRelative(-10)
                PiPOverlayState.shared.triggerHUD(icon: "gobackward.10", text: "-10 giây")
            }
            return true
            
        case 38: // J: Seek -10s
            pm.seekRelative(-10)
            PiPOverlayState.shared.triggerHUD(icon: "gobackward.10", text: "-10 giây")
            return true
            
        case 124: // Right Arrow: Cmd+Right for next video, or Seek +10s
            if event.modifierFlags.contains(.command) {
                pm.playNextVideo()
                PiPOverlayState.shared.triggerHUD(icon: "forward.end.fill", text: "Video tiếp theo")
            } else {
                pm.seekRelative(10)
                PiPOverlayState.shared.triggerHUD(icon: "goforward.10", text: "+10 giây")
            }
            return true
            
        case 37: // L: Seek +10s
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
            
        case 47: // Period (.): If Shift is held ('>'), increase playback speed
            if event.modifierFlags.contains(.shift) {
                pm.increasePlaybackRate()
                PiPOverlayState.shared.triggerHUD(icon: "speedometer", text: "Tốc độ: \(pm.displayPlaybackRate)")
                return true
            }
            return false
            
        case 43: // Comma (,): If Shift is held ('<'), decrease playback speed
            if event.modifierFlags.contains(.shift) {
                pm.decreasePlaybackRate()
                PiPOverlayState.shared.triggerHUD(icon: "speedometer", text: "Tốc độ: \(pm.displayPlaybackRate)")
                return true
            }
            return false
            
        case 30: // Right Bracket (]): Increase playback speed
            pm.increasePlaybackRate()
            PiPOverlayState.shared.triggerHUD(icon: "speedometer", text: "Tốc độ: \(pm.displayPlaybackRate)")
            return true
            
        case 33: // Left Bracket ([): Decrease playback speed
            pm.decreasePlaybackRate()
            PiPOverlayState.shared.triggerHUD(icon: "speedometer", text: "Tốc độ: \(pm.displayPlaybackRate)")
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
    @ObservedObject private var hud = PiPOverlayState.shared
    
    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            ZStack {
                Color.black
                
                // 1. Full-bleed edge-to-edge Native Video Player
                if playerManager.isPictureInPictureActive {
                    NativePlayerView(cornerRadius: 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // 2. Interactive Control Overlay (Always resident to eliminate layer allocation and black frame flicker)
                ZStack {
                    // Window drag surface in background (drag anywhere to move window, double click to snap size)
                    PiPWindowDragView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Cinematic seamless gradient vignetting: clear in the center, dark at top & bottom
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.80),
                            Color.black.opacity(0.40),
                            Color.clear,
                            Color.clear,
                            Color.black.opacity(0.45),
                            Color.black.opacity(0.88)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                    
                    VStack(spacing: 0) {
                        // Top Navigation / Header Bar
                        topHeaderBar(width: w)
                            .padding(.top, 10)
                            .padding(.horizontal, 10)
                        
                        Spacer()
                        
                        // Bottom Timeline & Playback Controls
                        bottomControlsBar(width: w)
                            .padding(.bottom, 8)
                            .padding(.horizontal, 10)
                    }
                }
                .opacity((hud.isHovering || hud.isMenuOpen) ? 1.0 : 0.0)
                .allowsHitTesting(hud.isHovering || hud.isMenuOpen)
                .animation(.easeInOut(duration: 0.18), value: hud.isHovering || hud.isMenuOpen)
                
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
            .frame(width: w, height: h)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .onHover { hovering in
            if !hud.isMenuOpen {
                withAnimation(.easeInOut(duration: 0.18)) {
                    hud.isHovering = hovering
                }
            }
        }
        .contextMenu {
            Button {
                PiPWindowController.shared.returnToMainWindow()
            } label: {
                Label("Đưa video về cửa sổ chính (P)", systemImage: "arrow.up.forward.app")
            }
            
            Button {
                PiPWindowController.shared.hidePiPKeepAudio()
            } label: {
                Label("Ẩn cửa sổ PiP (tiếp tục nghe nhạc) (H)", systemImage: "headphones")
            }
            
            Divider()
            
            if PiPWindowController.shared.isPanelVertical {
                Button("Kích thước: Nhỏ (384p dọc)") {
                    PiPWindowController.shared.setPipVerticalSize(height: 384)
                }
                Button("Kích thước: Tiêu chuẩn (480p dọc)") {
                    PiPWindowController.shared.setPipVerticalSize(height: 480)
                }
                Button("Kích thước: Lớn (560p dọc)") {
                    PiPWindowController.shared.setPipVerticalSize(height: 560)
                }
            } else {
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
            
            Divider()
            
            Toggle("Tự động chuyển PiP khi chuyển app", isOn: $playerManager.autoPiPOnAppSwitch)
            Toggle("Tắt PiP khi bấm lại app chính", isOn: $playerManager.autoReturnPiPOnAppFocus)
        }
    }
    
    // MARK: - Top Header Bar
    private func topHeaderBar(width: CGFloat) -> some View {
        HStack(spacing: width < 320 ? 6 : 8) {
            // Close PiP Button
            Button(action: {
                PlayerManager.shared.togglePictureInPicture()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.black.opacity(0.65)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .help("Đóng PiP (Esc)")
            
            // Video Title & Channel Info
            if let video = playerManager.currentVideo {
                VStack(alignment: .leading, spacing: 1) {
                    Text(video.title)
                        .font(.system(size: width < 320 ? 11 : 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    if !video.uploader.isEmpty && width >= 280 {
                        Text(video.uploader)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(Color(white: 0.72))
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer(minLength: 4)
            
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
            
            // Hide PiP & Keep Audio Playing in Background Button
            Button(action: {
                PiPWindowController.shared.hidePiPKeepAudio()
            }) {
                Image(systemName: "headphones")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.95))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.black.opacity(0.65)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .help("Ẩn PiP và tiếp tục nghe âm thanh trong nền (H)")
            
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
    private func bottomControlsBar(width: CGFloat) -> some View {
        let isUltraCompact = width < 290
        let isCompact = width < 370
        let showPrevNext = width >= 370
        let showSeek10s = width >= 300
        let showSpeed = width >= 260
        let showVolumeSlider = width >= 430
        let spacing: CGFloat = isUltraCompact ? 6 : (isCompact ? 8 : (width < 480 ? 8 : 11))
        
        return VStack(spacing: 7) {
            // Timeline Progress Scrubber
            PiPInteractiveProgressBar()
            
            HStack(alignment: .center, spacing: spacing) {
                // Previous Video Button
                if showPrevNext {
                    Button(action: {
                        playerManager.playPreviousVideo()
                        hud.triggerHUD(icon: "backward.end.fill", text: "Video trước")
                    }) {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(playerManager.canPlayPrevious ? 1.0 : 0.45))
                            .frame(width: 18, height: 30, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    .disabled(!playerManager.canPlayPrevious)
                    .help("Video trước đó (Shift + P / ⌘←)")
                }
                
                // Seek backward 10s
                if showSeek10s {
                    Button(action: {
                        playerManager.seekRelative(-10)
                        hud.triggerHUD(icon: "gobackward.10", text: "-10s")
                    }) {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 20, height: 30, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    .help("Lùi 10 giây (← / J)")
                }
                
                // Play / Pause Button (Always present)
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
                            .font(.system(size: isUltraCompact ? 11 : 12.5, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: isUltraCompact ? 28 : 30, height: isUltraCompact ? 28 : 30, alignment: .center)
                }
                .buttonStyle(.plain)
                .help("Phát / Tạm dừng (Space / K)")
                
                // Seek forward 10s
                if showSeek10s {
                    Button(action: {
                        playerManager.seekRelative(10)
                        hud.triggerHUD(icon: "goforward.10", text: "+10s")
                    }) {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 20, height: 30, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    .help("Tiến 10 giây (→ / L)")
                }
                
                // Next Video Button
                if showPrevNext {
                    Button(action: {
                        playerManager.playNextVideo()
                        hud.triggerHUD(icon: "forward.end.fill", text: "Video tiếp theo")
                    }) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 18, height: 30, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    .help("Video tiếp theo (N / Shift + N / ⌘→)")
                }
                
                // Time label (Current / Total) - Guarantees NO line breaks or vertical squishing
                PiPTimeLabelView(
                    fontSize: isUltraCompact ? 9.5 : (isCompact ? 10.5 : 11),
                    showTotalDuration: width >= 230
                )
                .frame(height: 30, alignment: .center)
                
                // Spacer pushes Speed button & Volume controls to the right, giving time label breathing room
                Spacer(minLength: 8)
                
                // Speed Menu Button (Positioned close to speaker icon, optically centered)
                if showSpeed {
                    NativePiPSpeedButtonRepresentable()
                        .frame(width: 44, height: 30, alignment: .center)
                        .offset(y: 1.0)
                }
                
                // Mute / Unmute Button (Always present)
                Button(action: {
                    playerManager.toggleMute()
                    hud.triggerHUD(
                        icon: playerManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        text: playerManager.isMuted ? "Đã tắt tiếng" : "Âm lượng \(Int(playerManager.volume * 100))%"
                    )
                }) {
                    Image(systemName: playerManager.isMuted ? "speaker.slash.fill" : (playerManager.volume > 0.5 ? "speaker.wave.2.fill" : "speaker.wave.1.fill"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 30, alignment: .center)
                }
                .buttonStyle(.plain)
                .help("Tắt/Bật tiếng (M) • Cuộn chuột hoặc phím ↑/↓ để chỉnh âm lượng")
                
                // Mini Volume Scrub Slider (Visible on medium / wide PiP)
                if showVolumeSlider {
                    GeometryReader { volGeo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.25))
                                .frame(height: 3.5)
                            Capsule()
                                .fill(Color.white)
                                .frame(width: volGeo.size.width * CGFloat(playerManager.isMuted ? 0 : playerManager.volume), height: 3.5)
                        }
                        .frame(height: 30, alignment: .center)
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
                    .frame(width: 44, height: 30, alignment: .center)
                    .help("Kéo chỉnh âm lượng (hoặc phím ↑ / ↓)")
                }
            }
        }
    }
}

// MARK: - Native PiP Speed Menu Helper & Native Button
@MainActor
public final class PiPSpeedMenuHelper: NSObject, NSMenuDelegate {
    public static let shared = PiPSpeedMenuHelper()
    
    public func presentSpeedMenu(from view: NSView, currentRate: Double) {
        PiPOverlayState.shared.isMenuOpen = true
        let menu = NSMenu(title: "Tốc độ phát")
        menu.delegate = self
        menu.autoenablesItems = false
        
        let header = NSMenuItem(title: "Tốc độ phát", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())
        
        for rate in PlayerManager.availablePlaybackRates {
            let title = rate == 1.0 ? "1.0x (Chuẩn)" : String(format: "%gx", rate)
            let item = NSMenuItem(title: title, action: #selector(handleSpeedSelect(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = rate
            if abs(currentRate - rate) < 0.01 {
                item.state = .on
            }
            menu.addItem(item)
        }
        
        let location = NSPoint(x: 0, y: view.bounds.height + 4)
        menu.popUp(positioning: nil, at: location, in: view)
    }
    
    @objc private func handleSpeedSelect(_ sender: NSMenuItem) {
        if let rate = sender.representedObject as? Double {
            PlayerManager.shared.setPlaybackRate(rate)
            PiPOverlayState.shared.triggerHUD(icon: "speedometer", text: "Tốc độ: \(PlayerManager.shared.displayPlaybackRate)")
        }
        PiPOverlayState.shared.isMenuOpen = false
    }
    
    public func menuDidClose(_ menu: NSMenu) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            PiPOverlayState.shared.isMenuOpen = false
        }
    }
}

public struct NativePiPSpeedButtonRepresentable: NSViewRepresentable {
    @ObservedObject private var playerManager = PlayerManager.shared
    
    public init() {}
    
    public func makeNSView(context: Context) -> SpeedButtonNSView {
        let view = SpeedButtonNSView()
        view.updateTitle(playerManager.displayPlaybackRate)
        return view
    }
    
    public func updateNSView(_ nsView: SpeedButtonNSView, context: Context) {
        nsView.updateTitle(playerManager.displayPlaybackRate)
    }
    
    public final class SpeedButtonNSView: NSView {
        private let button = NSButton()
        
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }
        
        private func setup() {
            wantsLayer = true
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.setButtonType(.momentaryPushIn)
            button.target = self
            button.action = #selector(handleClick)
            button.wantsLayer = true
            button.layer?.cornerRadius = 5
            button.layer?.cornerCurve = .continuous
            button.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.18).cgColor
            button.layer?.borderColor = NSColor(white: 1.0, alpha: 0.18).cgColor
            button.layer?.borderWidth = 0.5
            
            addSubview(button)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: leadingAnchor),
                button.trailingAnchor.constraint(equalTo: trailingAnchor),
                button.centerYAnchor.constraint(equalTo: centerYAnchor),
                button.heightAnchor.constraint(equalToConstant: 20)
            ])
            toolTip = "Tốc độ phát (Shift + < / > hoặc phím [ / ])"
        }
        
        func updateTitle(_ title: String) {
            let pStyle = NSMutableParagraphStyle()
            pStyle.alignment = .center
            let attr = NSAttributedString(
                string: "\(title) ▾",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 9.5, weight: .bold),
                    .foregroundColor: NSColor.white,
                    .paragraphStyle: pStyle
                ]
            )
            button.attributedTitle = attr
        }
        
        @objc private func handleClick() {
            PiPSpeedMenuHelper.shared.presentSpeedMenu(from: button, currentRate: PlayerManager.shared.playbackRate)
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

// MARK: - Isolated PiP Time Label View: Updates only the time numbers on clock tick
struct PiPTimeLabelView: View {
    @ObservedObject private var clock = PlaybackClock.shared
    @ObservedObject private var playerManager = PlayerManager.shared
    
    var fontSize: CGFloat = 11
    var showTotalDuration: Bool = true
    
    private var effectiveDuration: Double {
        clock.duration > 0 ? clock.duration : playerManager.duration
    }
    
    private var effectiveTime: Double {
        clock.currentTime > 0 ? clock.currentTime : playerManager.currentTime
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            Text(formatSeconds(effectiveTime))
                .font(.system(size: fontSize, weight: .medium).monospacedDigit())
                .foregroundColor(.white)
                .lineLimit(1)
            
            if showTotalDuration {
                Text("/")
                    .font(.system(size: max(8.5, fontSize - 1), weight: .regular))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
                
                Text(formatSeconds(effectiveDuration))
                    .font(.system(size: fontSize, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
        .padding(.leading, 1)
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
