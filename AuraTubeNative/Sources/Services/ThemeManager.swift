import SwiftUI
import AppKit

public enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .system: return "Tự động (Hệ thống)"
        case .light: return "Giao diện sáng (Light)"
        case .dark: return "Giao diện tối (Dark)"
        }
    }
    
    public var shortTitle: String {
        switch self {
        case .system: return "Tự động"
        case .light: return "Sáng"
        case .dark: return "Tối"
        }
    }
    
    public var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }
}

public struct ThemeToastInfo: Equatable {
    public let icon: String
    public let message: String
    
    public init(icon: String, message: String) {
        self.icon = icon
        self.message = message
    }
}

@MainActor
public final class ThemeManager: ObservableObject {
    public static let shared = ThemeManager()
    
    private let themeKey = "aura_app_theme_preference"
    
    @Published public var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: themeKey)
            applyTheme()
        }
    }
    
    @Published public var themeToast: ThemeToastInfo? = nil
    private var toastDismissWorkItem: DispatchWorkItem?
    
    public init() {
        if let saved = UserDefaults.standard.string(forKey: themeKey),
           let theme = AppTheme(rawValue: saved) {
            self.currentTheme = theme
        } else {
            self.currentTheme = .system
        }
    }
    
    public var colorScheme: ColorScheme? {
        switch currentTheme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    
    public var appearance: NSAppearance? {
        switch currentTheme {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
    
    public func cycleTheme() {
        withAnimation(.easeInOut(duration: 0.28)) {
            switch currentTheme {
            case .system:
                currentTheme = .light
            case .light:
                currentTheme = .dark
            case .dark:
                currentTheme = .system
            }
        }
        showFeedbackToast()
    }
    
    public func setTheme(_ theme: AppTheme) {
        withAnimation(.easeInOut(duration: 0.28)) {
            currentTheme = theme
        }
        showFeedbackToast()
    }
    
    public func showFeedbackToast() {
        let isSysDark: Bool
        if let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            isSysDark = (match == .darkAqua)
        } else {
            isSysDark = false
        }
        
        let icon: String
        let message: String
        switch currentTheme {
        case .light:
            icon = "sun.max.fill"
            message = "Giao diện: Sáng (Light)"
        case .dark:
            icon = "moon.stars.fill"
            message = "Giao diện: Tối (Dark)"
        case .system:
            icon = "circle.lefthalf.filled"
            message = isSysDark ? "Giao diện: Tự động (Hệ thống: Tối)" : "Giao diện: Tự động (Hệ thống: Sáng)"
        }
        
        toastDismissWorkItem?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            self.themeToast = ThemeToastInfo(icon: icon, message: message)
        }
        
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) {
                self?.themeToast = nil
            }
        }
        toastDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }
    
    public func applyTheme() {
        let appAppearance = appearance
        NSApp.appearance = appAppearance
        
        for window in NSApp.windows {
            window.appearance = appAppearance
            AppDelegate.configureTitlebar(for: window)
            window.contentView?.needsLayout = true
            window.contentView?.needsDisplay = true
        }
        
        NotificationCenter.default.post(name: NSNotification.Name("AuraTubeThemeDidChange"), object: nil)
    }
}
