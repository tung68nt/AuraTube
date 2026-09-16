import SwiftUI
import AppKit

// MARK: - Native macOS Floating Picture-in-Picture Window Controller
@MainActor
public final class PiPWindowController: NSObject, NSWindowDelegate {
    public static let shared = PiPWindowController()
    
    private var pipWindow: NSPanel?
    
    public override init() {
        super.init()
    }
    
    public func show(video: Video?) {
        if let existing = pipWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        
        let initialWidth: CGFloat = 440
        let initialHeight: CGFloat = 440 * (9.0 / 16.0)
        
        // Position at bottom-right corner of main screen
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screenFrame.maxX - initialWidth - 28
        let y = screenFrame.minY + 28
        
        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: initialWidth, height: initialHeight),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hasShadow = true
        panel.minSize = NSSize(width: 280, height: 280 * (9.0 / 16.0))
        panel.maxSize = NSSize(width: 800, height: 800 * (9.0 / 16.0))
        panel.aspectRatio = NSSize(width: 16, height: 9)
        panel.backgroundColor = .black
        panel.isOpaque = false
        panel.delegate = self
        
        let hostingView = NSHostingView(rootView: PiPFloatingContentView())
        panel.contentView = hostingView
        
        self.pipWindow = panel
        panel.makeKeyAndOrderFront(nil)
    }
    
    public func close() {
        pipWindow?.close()
        pipWindow = nil
    }
    
    public func windowWillClose(_ notification: Notification) {
        pipWindow = nil
        if PlayerManager.shared.isPictureInPictureActive {
            PlayerManager.shared.isPictureInPictureActive = false
        }
    }
}

// MARK: - Floating PiP Content View
public struct PiPFloatingContentView: View {
    @ObservedObject private var playerManager = PlayerManager.shared
    @State private var isHovering: Bool = false
    
    public var body: some View {
        ZStack {
            Color.black
            
            NativePlayerView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Smooth Hover Control Overlay
            if isHovering {
                ZStack {
                    LinearGradient(
                        colors: [Color.black.opacity(0.65), Color.clear, Color.black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    
                    // Top Bar with Close and Return-to-Main buttons
                    VStack {
                        HStack {
                            Button(action: {
                                PlayerManager.shared.togglePictureInPicture()
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(Circle().fill(Color.black.opacity(0.6)))
                            }
                            .buttonStyle(.plain)
                            .help("Đóng PiP (trở về cửa sổ chính)")
                            
                            Spacer()
                            
                            if let video = playerManager.currentVideo {
                                Text(video.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                PlayerManager.shared.togglePictureInPicture()
                                NSApp.activate(ignoringOtherApps: true)
                                if let mainWindow = NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeKey }) {
                                    mainWindow.makeKeyAndOrderFront(nil)
                                }
                            }) {
                                Image(systemName: "arrow.up.forward.app")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(Circle().fill(Color.black.opacity(0.6)))
                            }
                            .buttonStyle(.plain)
                            .help("Mở trong cửa sổ chính")
                        }
                        .padding(8)
                        
                        Spacer()
                        
                        // Bottom Quick Playback Controls
                        HStack(spacing: 16) {
                            Button(action: { playerManager.seekRelative(-10) }) {
                                Image(systemName: "gobackward.10")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { playerManager.togglePlayPause() }) {
                                Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { playerManager.seekRelative(10) }) {
                                Image(systemName: "goforward.10")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 14)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                        .padding(.bottom, 8)
                    }
                }
                .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}
