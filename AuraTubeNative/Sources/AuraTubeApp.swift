import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?
    
    override init() {
        super.init()
        AppDelegate.shared = self
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        ThemeManager.shared.applyTheme()
        MenuBarController.shared.setup()
        
        for window in NSApp.windows {
            AppDelegate.configureTitlebar(for: window)
        }
        
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { notif in
            if let window = notif.object as? NSWindow {
                AppDelegate.configureTitlebar(for: window)
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
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
                return true
            }
        }
        return true
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
    
    public static func configureTitlebar(for window: NSWindow) {
        // Only configure primary resizable main windows (prevent injecting into about dialogs, popovers, sheets)
        guard !(window is NSPanel), !window.isSheet, window.styleMask.contains(.resizable) else { return }
        
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = true
        
        let isDark = (window.effectiveAppearance.name == .darkAqua || window.effectiveAppearance.name == .vibrantDark)
        window.backgroundColor = isDark ? NSColor(calibratedWhite: 0.11, alpha: 1.0) : NSColor(calibratedWhite: 0.96, alpha: 1.0)
        
        // Hide opaque titlebar background views so SwiftUI liquid glass renders without cutoff
        if let closeButton = window.standardWindowButton(.closeButton),
           let titlebarView = closeButton.superview {
            for v in titlebarView.subviews {
                if !(v is NSButton) && !v.subviews.contains(where: { $0 is NSButton }) {
                    v.isHidden = true
                }
            }
            if let container = titlebarView.superview {
                for v in container.subviews where v !== titlebarView {
                    v.isHidden = true
                }
            }
        }
        
        // Ensure standard window buttons (traffic lights) are always visible and properly layered
        for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = window.standardWindowButton(buttonType) {
                button.isHidden = false
            }
        }
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
                .keyboardShortcut(.space, modifiers: [])
                
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
                .keyboardShortcut("f", modifiers: [])
                
                Button("Thoát toàn màn hình") {
                    if PlayerManager.shared.isVideoFullscreen {
                        PlayerManager.shared.toggleFullscreen()
                    }
                }
                .keyboardShortcut(.escape, modifiers: [])
                
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
