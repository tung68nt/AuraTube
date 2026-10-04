import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static private(set) var shared: AppDelegate?
    public static var isTerminating: Bool = false
    
    override init() {
        super.init()
        AppDelegate.shared = self
        
        // 150 MB RAM Cache, 1 GB Disk Cache for buttery smooth thumbnail loading
        let memoryCapacity = 150 * 1024 * 1024
        let diskCapacity = 1024 * 1024 * 1024
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("com.auratube.cache")
        URLCache.shared = URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, directory: cacheDir)
        
        AppFont.registerCustomFonts()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppFont.registerCustomFonts()
        ScrollBoost.install()
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
        // Warm the web player once the window is up, so the first video starts quickly
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            MainWebPlayerPool.shared.prewarm()
        }
        
        if UpdateService.shared.autoCheckEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                Task { @MainActor in
                    UpdateService.shared.checkForUpdates(isUserInitiated: false)
                }
            }
        }
        
        // Return PiP to the main player when the user comes back to AuraTube from another app.
        // Keyed on app activation, not on the main window becoming key: opening PiP from inside
        // the app shuffles key status between the panel and the main window, and treating that
        // as "user returned" pulled the panel back to the main player's frame right after it opened.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                let pm = PlayerManager.shared
                guard pm.isPictureInPictureActive, pm.autoReturnPiPOnAppFocus else { return }
                
                // Debounce to prevent immediate exit right after entering PiP
                let elapsed = Date().timeIntervalSinceReferenceDate - pm.lastPiPEnterTimestamp
                guard elapsed > 0.4 else { return }
                
                // Dragging / clicking the PiP (or hiding it to audio-only) is not "back to the app"
                guard !PiPWindowController.shared.isUserInteractingWithPiP else { return }
                
                pm.exitPictureInPicture()
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
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    @MainActor
    @objc func handleMainWindowClose(_ sender: Any?) {
        terminateAppCompletely()
    }
    
    @MainActor
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !(sender is NSPanel), !sender.isSheet, sender.styleMask.contains(.resizable) else {
            return true
        }
        terminateAppCompletely()
        return true
    }
    
    @MainActor
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        guard !(window is NSPanel), !window.isSheet, window.styleMask.contains(.resizable) else { return }
        terminateAppCompletely()
    }
    
    @MainActor
    public func terminateAppCompletely() {
        guard !AppDelegate.isTerminating else { return }
        AppDelegate.isTerminating = true
        
        // Save playback progress to persistent storage immediately
        PlayerManager.shared.flushSavedPlaybackPositions()
        
        // Immediately pause and stop audio & video playback
        PlayerManager.shared.pause()
        PlayerManager.shared.isPictureInPictureActive = false
        PiPWindowController.shared.close()
        
        // Terminate process immediately so no audio or background tasks continue running
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
    
    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        AppDelegate.isTerminating = true
        PlayerManager.shared.flushSavedPlaybackPositions()
        PlayerManager.shared.pause()
        PiPWindowController.shared.close()
    }
    
    func applicationDidResignActive(_ notification: Notification) {
        Task { @MainActor in
            guard !AppDelegate.isTerminating else { return }
            
            // Check if there is still a visible, non-minimized main window
            let hasVisibleMainWindow = NSApp.windows.contains { win in
                !(win is NSPanel) && !win.isSheet && win.styleMask.contains(.resizable) && win.isVisible && !win.isMiniaturized
            }
            guard hasVisibleMainWindow else { return }
            
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
            if pm.isPlaying || pm.isPictureInPictureActive {
                PlaybackActivityManager.shared.ensurePlaybackActivity()
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
        if let closeBtn = window.standardWindowButton(.closeButton) {
            closeBtn.target = AppDelegate.shared
            closeBtn.action = #selector(AppDelegate.handleMainWindowClose(_:))
            closeBtn.isHidden = false
        }
        for buttonType in [NSWindow.ButtonType.miniaturizeButton, .zoomButton] {
            if let button = window.standardWindowButton(buttonType) {
                button.isHidden = false
            }
        }
        
        window.delegate = AppDelegate.shared
        
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
            
            CommandGroup(replacing: .appSettings) {
                Button("Cài đặt...") {
                    NotificationCenter.default.post(name: .showSettingsNotification, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
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
    static let showSettingsNotification = Notification.Name("AuraTubeShowSettingsNotification")
}
