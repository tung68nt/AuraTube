import AppKit
import SwiftUI
import Combine

@MainActor
public final class MenuBarController: NSObject, NSPopoverDelegate {
    public static let shared = MenuBarController()
    
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var outsideClickGlobalMonitor: Any?
    private var outsideClickLocalMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    
    public override init() {
        super.init()
    }
    
    public func setup() {
        // 1. Create NSStatusItem in system status bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 3.4 24 17.2" width="21.5" height="15.5">
              <path fill="#ffffff" fill-rule="evenodd" d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z"/>
            </svg>
            """
            if let data = svg.data(using: .utf8), let img = NSImage(data: data) {
                img.size = NSSize(width: 21.5, height: 15.5)
                img.isTemplate = true
                button.image = img
            } else if let img = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "AuraTube") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "▶"
            }
            button.target = self
            button.action = #selector(togglePopover)
        }
        
        // 2. Setup NSPopover with MenuBarView
        let popover = NSPopover()
        let initialSize = PlayerManager.shared.isCurrentVideoVertical ? NSSize(width: 300, height: 510) : NSSize(width: 320, height: 360)
        popover.contentSize = initialSize
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self
        popover.setValue(true, forKeyPath: "shouldHideAnchor")
        
        let contentView = MenuBarView { [weak self] in
            self?.openMainWindow()
        }
        .preferredColorScheme(.dark)
        
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.view.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = hostingController
        self.popover = popover
        
        // 3. Observe vertical video state changes to dynamically adapt popover dimensions
        PlayerManager.shared.$isCurrentVideoVertical
            .receive(on: RunLoop.main)
            .sink { [weak self] isVertical in
                self?.updatePopoverSize(isVertical: isVertical)
            }
            .store(in: &cancellables)
        
        // Pre-initialize persistent background MiniPlayerEngine so both players run simultaneously from launch
        _ = MiniPlayerEngine.shared
    }
    
    public func updatePopoverSize(isVertical: Bool) {
        let targetSize = isVertical ? NSSize(width: 300, height: 510) : NSSize(width: 320, height: 360)
        if popover?.contentSize != targetSize {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                popover?.contentSize = targetSize
            }
        }
    }
    
    @objc public func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        if popover.isShown {
            closePopover()
        } else {
            updatePopoverSize(isVertical: PlayerManager.shared.isCurrentVideoVertical)
            NSApp.activate(ignoringOtherApps: true)
            popover.appearance = NSAppearance(named: .darkAqua)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            
            if let window = popover.contentViewController?.view.window {
                window.appearance = NSAppearance(named: .darkAqua)
                window.makeKeyAndOrderFront(nil)
                DispatchQueue.main.async {
                    window.makeKey()
                }
            }
            
            startOutsideClickMonitors()
            NotificationCenter.default.post(name: NSNotification.Name("AuraTubeMenuBarPopoverShown"), object: nil)
        }
    }
    
    public func closePopover() {
        stopOutsideClickMonitors()
        if let popover = popover, popover.isShown {
            popover.performClose(nil)
        }
    }
    
    private func startOutsideClickMonitors() {
        stopOutsideClickMonitors()
        
        // 1. Global monitor: Catches clicks in other apps, desktop, other menubar items
        outsideClickGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closePopover()
            }
        }
        
        // 2. Local monitor: Catches clicks outside popover AND keyboard events (Space, arrows, Mute)
        outsideClickLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self = self else { return event }
            
            if event.type == .keyDown {
                guard let popover = self.popover, popover.isShown else { return event }
                
                // Don't intercept if user is typing in a text field
                if let responder = event.window?.firstResponder,
                   responder is NSTextView || responder is NSTextField {
                    return event
                }
                
                if event.keyCode == 49 { // Spacebar: Play / Pause
                    PlayerManager.shared.togglePlayPause()
                    return nil
                } else if event.keyCode == 123 { // Left arrow: seek -10s
                    PlayerManager.shared.seekRelative(-10)
                    return nil
                } else if event.keyCode == 124 { // Right arrow: seek +10s
                    PlayerManager.shared.seekRelative(10)
                    return nil
                } else if event.keyCode == 46 { // M key: toggle mute
                    PlayerManager.shared.toggleMute()
                    return nil
                }
                return event
            }
            
            if let popWindow = self.popover?.contentViewController?.view.window {
                if event.window != popWindow {
                    // If clicking the status bar button itself, allow togglePopover to handle it
                    if let btnWindow = self.statusItem?.button?.window, event.window == btnWindow {
                        return event
                    }
                    DispatchQueue.main.async {
                        self.closePopover()
                    }
                }
            }
            return event
        }
    }
    
    private func stopOutsideClickMonitors() {
        if let g = outsideClickGlobalMonitor {
            NSEvent.removeMonitor(g)
            outsideClickGlobalMonitor = nil
        }
        if let l = outsideClickLocalMonitor {
            NSEvent.removeMonitor(l)
            outsideClickLocalMonitor = nil
        }
    }
    
    // MARK: - NSPopoverDelegate
    public func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitors()
        NotificationCenter.default.post(name: NSNotification.Name("AuraTubeMenuBarPopoverClosed"), object: nil)
    }
    
    public func openMainWindow() {
        closePopover()
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
