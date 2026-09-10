import AppKit
import SwiftUI

@MainActor
public final class AboutWindowController: NSObject, NSWindowDelegate {
    public static let shared = AboutWindowController()
    
    private var window: NSWindow?
    
    public func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let aboutView = AboutView { [weak self] in
            self?.close()
        }
        
        let hostingController = NSHostingController(rootView: aboutView)
        
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 310),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = true
        win.level = .floating
        win.contentViewController = hostingController
        win.center()
        win.delegate = self
        
        // Hide standard window buttons so they don't collide or look ugly
        win.standardWindowButton(.miniaturizeButton)?.isHidden = true
        win.standardWindowButton(.zoomButton)?.isHidden = true
        win.standardWindowButton(.closeButton)?.isHidden = true
        
        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func close() {
        window?.close()
        window = nil
    }
    
    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
