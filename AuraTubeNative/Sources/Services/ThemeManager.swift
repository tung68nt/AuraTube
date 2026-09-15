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
    
    public func cycleTheme() {
        switch currentTheme {
        case .system:
            currentTheme = .light
        case .light:
            currentTheme = .dark
        case .dark:
            currentTheme = .system
        }
    }
    
    public func setTheme(_ theme: AppTheme) {
        currentTheme = theme
    }
    
    public func applyTheme() {
        switch currentTheme {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        
        for window in NSApp.windows {
            AppDelegate.configureTitlebar(for: window)
        }
    }
}
