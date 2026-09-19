import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?
    
    override init() {
        super.init()
        AppDelegate.shared = self
        AppFont.registerCustomFonts()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppFont.registerCustomFonts()
        ThemeManager.shared.applyTheme()
        MenuBarController.shared.setup()
        
        for window in NSApp.windows {
            AppDelegate.configureTitlebar(for: window)
        }
        
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { notif in
            if let window = notif.object as? NSWindow {
                Task { @MainActor in
                    AppDelegate.configureTitlebar(for: window)
                }
            }
        }
        
        // Auto-check for updates after app launch if enabled
        if UpdateService.shared.autoCheckEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                Task { @MainActor in
                    UpdateService.shared.checkForUpdates(isUserInitiated: false)
                }
            }
        }
        
        // Automatically return PiP to main player when user clicks/focuses the main application window
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            Task { @MainActor in
                guard let window = notification.object as? NSWindow else { return }
                let pm = PlayerManager.shared
                
                // Only act if PiP is currently active and autoReturnPiPOnAppFocus is enabled
                guard pm.isPictureInPictureActive, pm.autoReturnPiPOnAppFocus else { return }
                
                // Debounce to prevent immediate exit right after entering PiP
                let elapsed = Date().timeIntervalSinceReferenceDate - pm.lastPiPEnterTimestamp
                guard elapsed > 0.4 else { return }
                
                // Verify that this is the main application window (not the PiP floating panel, not an auxiliary panel)
                if !PiPWindowController.shared.isPipWindow(window),
                   !(window is NSPanel),
                   window.canBecomeMain {
                    pm.exitPictureInPicture()
                }
            }
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            let pm = PlayerManager.shared
            if pm.isPictureInPictureActive, pm.autoReturnPiPOnAppFocus {
                let elapsed = Date().timeIntervalSinceReferenceDate - pm.lastPiPEnterTimestamp
                if elapsed > 0.4 {
                    pm.exitPictureInPicture()
                }
            }
        }
        if !flag {
            for window in sender.windows {
                if !PiPWindowController.shared.isPipWindow(window) {
                    window.makeKeyAndOrderFront(self)
                    return true
                }
            }
        }
        return true
    }
    
    func applicationDidResignActive(_ notification: Notification) {
        Task { @MainActor in
            let pm = PlayerManager.shared
            // When leaving AuraTube to another app:
            // If user has enabled auto PiP, video is playing, PiP is not already active, and not in fullscreen
            if pm.autoPiPOnAppSwitch,
               pm.currentVideo != nil,
               pm.isPlaying,
               !pm.isPictureInPictureActive,
               !pm.isVideoFullscreen {
                pm.enterPictureInPicture(isAutoTriggered: true)
            }
        }
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            let pm = PlayerManager.shared
            guard pm.isPictureInPictureActive else { return }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                let elapsed = Date().timeIntervalSinceReferenceDate - pm.lastPiPEnterTimestamp
                guard elapsed > 0.4 else { return }
                
                // If the user focused the floating PiP window itself, keep it in PiP!
                if let keyWindow = NSApp.keyWindow, PiPWindowController.shared.isPipWindow(keyWindow) {
                    return
                }
                
                // If returning to the main window and auto return is enabled
                if pm.autoReturnPiPOnAppFocus || pm.wasAutoPiPTriggered {
                    pm.exitPictureInPicture()
                }
            }
        }
    }
    
    @MainActor
    public static func showStandardAboutPanel() {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.9"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "10"
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "AuraTube",
            .applicationVersion: appVersion,
            .version: buildNumber
        ]
        let copyright = "Copyright © 2026 Tung Nguyen. All rights reserved."
        let attr = NSAttributedString(
            string: copyright,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        options[.credits] = attr
        NSApp.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(options)
    }
    
    @MainActor
    public static func configureTitlebar(for window: NSWindow) {
        // Only configure primary resizable main windows (prevent injecting into about dialogs, popovers, sheets)
        guard !(window is NSPanel), !window.isSheet, window.styleMask.contains(.resizable) else { return }
        
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isOpaque = true
        window.hasShadow = true
        
        if PlayerManager.shared.isVideoFullscreen || window.styleMask.contains(.fullScreen) {
            window.backgroundColor = .black
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.cornerRadius = 0
            window.contentView?.layer?.masksToBounds = false
            return
        }
        
        let isDark: Bool
        switch ThemeManager.shared.currentTheme {
        case .dark:
            isDark = true
        case .light:
            isDark = false
        case .system:
            if let appearance = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
                isDark = (appearance == .darkAqua)
            } else {
                isDark = (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            }
        }
        
        let bgColor = isDark ?
            NSColor(red: 16/255, green: 16/255, blue: 20/255, alpha: 1.0) :
            NSColor(red: 250/255, green: 250/255, blue: 252/255, alpha: 1.0)
            
        window.backgroundColor = bgColor
        
        // Ensure standard window buttons (traffic lights) are always visible and properly layered
        for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = window.standardWindowButton(buttonType) {
                button.isHidden = false
            }
        }
        
        // Ensure the window's content view clips cleanly to smooth macOS rounded corners (16px)
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = 16
        window.contentView?.layer?.masksToBounds = true
    }
}

@main
struct AuraTubeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var playerManager = PlayerManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(themeManager.colorScheme)
                .animation(.easeInOut(duration: 0.28), value: themeManager.currentTheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Giới thiệu về AuraTube") {
                    AppDelegate.showStandardAboutPanel()
                }
                
                Button("Kiểm tra bản cập nhật...") {
                    UpdateService.shared.checkForUpdates(isUserInitiated: true)
                }
                .keyboardShortcut("u", modifiers: .command)
                Divider()
            }
            
            CommandMenu("Giao diện") {
                Button("Tự động (Theo hệ thống)") {
                    themeManager.setTheme(.system)
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])
                
                Button("Giao diện sáng (Light)") {
                    themeManager.setTheme(.light)
                }
                .keyboardShortcut("1", modifiers: [.command, .shift])
                
                Button("Giao diện tối (Dark)") {
                    themeManager.setTheme(.dark)
                }
                .keyboardShortcut("2", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Chuyển đổi giao diện (Light/Dark)") {
                    themeManager.cycleTheme()
                }
                .keyboardShortcut("t", modifiers: .command)
            }
            
            CommandMenu("Hiển thị") {
                Button("Hiện / Ẩn Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebarNotification, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
            }
            
            CommandMenu("Điều khiển Media") {
                Button("Bật Mini Player (Menu Bar)") {
                    MenuBarController.shared.togglePopover()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Phát / Tạm dừng") {
                    playerManager.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: .command)
                
                Button("Tua tới 10s") {
                    playerManager.seekRelative(10)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                
                Button("Tua lùi 10s") {
                    playerManager.seekRelative(-10)
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                
                Button("Bật / Tắt tiếng") {
                    playerManager.toggleMute()
                }
                .keyboardShortcut("m", modifiers: .command)
                
                Button("Toàn màn hình") {
                    PlayerManager.shared.toggleFullscreen()
                }
                .keyboardShortcut("f", modifiers: [.control, .command])
                
                Button("Thoát toàn màn hình") {
                    if PlayerManager.shared.isVideoFullscreen {
                        PlayerManager.shared.toggleFullscreen()
                    }
                }
                
                Button(playerManager.isPictureInPictureActive ? "Tắt Picture-in-Picture" : "Bật Picture-in-Picture") {
                    playerManager.togglePictureInPicture()
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
                
                Toggle("Tự động chuyển PiP khi chuyển app", isOn: $playerManager.autoPiPOnAppSwitch)
                Toggle("Tắt PiP khi bấm lại app chính", isOn: $playerManager.autoReturnPiPOnAppFocus)
                
                Divider()
                
                Button("Lưu / Bỏ lưu video") {
                    if let v = playerManager.currentVideo {
                        playerManager.toggleBookmark(v)
                    }
                }
                .keyboardShortcut("b", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let toggleSidebarNotification = Notification.Name("AuraTubeToggleSidebarNotification")
}
