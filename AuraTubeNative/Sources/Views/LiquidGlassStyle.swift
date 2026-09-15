import SwiftUI
import AppKit

// MARK: - Apple macOS Human Interface Guidelines (HIG) Liquid Glass System
// Supports both macOS Dark Mode (Obsidian Glass) and Light Mode (Frosted Milk Glass):
// Native vibrancy, continuous squircles, delicate specular hairline reflections,
// and authentic optical depth adhering to Apple HIG.

@MainActor
public final class LiquidHoverViewModel: ObservableObject {
    @Published public var isHovered: Bool = false
    public init() {}
}

// MARK: - Semantic Theme Color System (Calibrated to Authentic YouTube Palette + Apple Liquid Glass)
public struct ThemeColor {
    // YouTube Authentic Text Hierarchy
    public static func textPrimary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 241/255, green: 241/255, blue: 241/255) : Color(red: 15/255, green: 15/255, blue: 15/255)
    }
    
    public static func textSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 170/255, green: 170/255, blue: 170/255) : Color(red: 96/255, green: 96/255, blue: 96/255)
    }
    
    public static func textTertiary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 113/255, green: 113/255, blue: 113/255) : Color(red: 144/255, green: 144/255, blue: 144/255)
    }
    
    // Specular Hairline Dividers
    public static func divider(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }
    
    // Header Surfaces (YouTube Base + Glass Translucency)
    public static func headerBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 15/255, green: 15/255, blue: 15/255).opacity(0.88) : Color.white.opacity(0.88)
    }
    
    public static func windowBackground(for scheme: ColorScheme) -> NSColor {
        scheme == .dark ? NSColor(red: 15/255, green: 15/255, blue: 15/255, alpha: 1.0) : NSColor(red: 249/255, green: 249/255, blue: 249/255, alpha: 1.0)
    }
    
    public static func sidebarHover(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }
    
    public static func sidebarSelected(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.09)
    }
    
    public static func cardBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.85)
    }
    
    public static func cardBorder(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }
    
    public static func buttonBackground(for scheme: ColorScheme, isHovered: Bool) -> Color {
        if scheme == .dark {
            return Color.white.opacity(isHovered ? 0.18 : 0.10)
        } else {
            return isHovered ? Color(white: 0.90) : Color(white: 0.95)
        }
    }
    
    public static func buttonBorder(for scheme: ColorScheme, isHovered: Bool) -> Color {
        if scheme == .dark {
            return Color.white.opacity(isHovered ? 0.28 : 0.14)
        } else {
            return isHovered ? Color.black.opacity(0.18) : Color.black.opacity(0.08)
        }
    }
}

// MARK: - 1. Native macOS Window Vibrancy (NSVisualEffectView)
public struct VisualEffectBackground: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State
    
    public init(
        material: NSVisualEffectView.Material = .underWindowBackground,
        blendingMode: NSVisualEffectView.BlendingMode = .withinWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - 2. Continuous Glass Container Modifier
public struct LiquidGlassModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    public var cornerRadius: CGFloat = 12
    public var isHovered: Bool = false
    public var elevation: CGFloat = 3
    
    public init(cornerRadius: CGFloat = 12, isHovered: Bool = false, elevation: CGFloat = 3) {
        self.cornerRadius = cornerRadius
        self.isHovered = isHovered
        self.elevation = elevation
    }
    
    public func body(content: Content) -> some View {
        let isDark = (colorScheme == .dark)
        
        content
            .background(
                ZStack {
                    // 1. Frosted Material Base (Native macOS blur)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    
                    // 2. Liquid Glass Ambient Tint
                    if isDark {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isHovered ? 0.09 : 0.04),
                                        Color.white.opacity(isHovered ? 0.02 : 0.005)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isHovered ? 0.85 : 0.70),
                                        Color.white.opacity(isHovered ? 0.65 : 0.50)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                }
            )
            .overlay(
                // 3. Hairline Specular Refraction (0.75pt delicate highlight)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isDark ?
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.22 : 0.12),
                                    Color.white.opacity(isHovered ? 0.07 : 0.03),
                                    Color.black.opacity(0.12)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ) :
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.95 : 0.85),
                                    Color.white.opacity(isHovered ? 0.50 : 0.35),
                                    Color.black.opacity(0.08)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                        lineWidth: 0.75
                    )
            )
            .shadow(
                color: Color.black.opacity(isDark ? (isHovered ? 0.30 : 0.16) : (isHovered ? 0.10 : 0.05)),
                radius: isHovered ? elevation * 1.5 : elevation,
                x: 0,
                y: isHovered ? elevation * 0.75 : elevation * 0.5
            )
    }
}

// MARK: - 3. Liquid Glass Capsule Modifier (Chips & Pills)
public struct LiquidGlassCapsuleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    public var isHovered: Bool = false
    public var isSelected: Bool = false
    public var elevation: CGFloat = 2.5
    
    public init(isHovered: Bool = false, isSelected: Bool = false, elevation: CGFloat = 2.5) {
        self.isHovered = isHovered
        self.isSelected = isSelected
        self.elevation = elevation
    }
    
    public func body(content: Content) -> some View {
        let isDark = (colorScheme == .dark)
        
        content
            .background(
                ZStack {
                    if isSelected {
                        if isDark {
                            // YouTube Active: Crisp Silk White (#f1f1f1) with Apple specular glow
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 248/255, green: 248/255, blue: 248/255),
                                            Color(red: 236/255, green: 236/255, blue: 236/255)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        } else {
                            // YouTube Active: Deep Obsidian Black (#0f0f0f) with subtle specular sheen
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 25/255, green: 25/255, blue: 25/255),
                                            Color(red: 12/255, green: 12/255, blue: 12/255)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                    } else {
                        // YouTube Inactive + Apple Frosted Vibrancy
                        if isDark {
                            Capsule().fill(.ultraThinMaterial)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(isHovered ? 0.18 : 0.10),
                                            Color.white.opacity(isHovered ? 0.12 : 0.06)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        } else {
                            // Light Mode: Clean YouTube pill
                            Capsule()
                                .fill(isHovered ? Color(white: 0.90) : Color(white: 0.94))
                        }
                    }
                }
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ?
                            (isDark ?
                                LinearGradient(colors: [Color.white, Color(white: 0.85)], startPoint: .top, endPoint: .bottom) :
                                LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom)
                            ) :
                            (isDark ?
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isHovered ? 0.28 : 0.16),
                                        Color.white.opacity(isHovered ? 0.08 : 0.03)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ) :
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(isHovered ? 0.15 : 0.08),
                                        Color.black.opacity(isHovered ? 0.10 : 0.04)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            ),
                        lineWidth: 0.75
                    )
            )
            .shadow(
                color: isSelected ?
                    (isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.20)) :
                    Color.black.opacity(isDark ? (isHovered ? 0.25 : 0.14) : (isHovered ? 0.08 : 0.03)),
                radius: isSelected ? 4 : (isHovered ? elevation * 1.3 : elevation),
                x: 0,
                y: isSelected ? 1.5 : elevation * 0.4
            )
    }
}

// MARK: - 4. Interactive Liquid Glass Button (Continuous Squircle)
public struct LiquidGlassButton<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    public let action: () -> Void
    public var cornerRadius: CGFloat = 8
    public var isProminent: Bool = false
    public var prominentGradient: [Color]? = nil
    @ViewBuilder public let content: () -> Content
    
    @StateObject private var hoverVm = LiquidHoverViewModel()
    
    public init(
        action: @escaping () -> Void,
        cornerRadius: CGFloat = 8,
        isProminent: Bool = false,
        prominentGradient: [Color]? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.action = action
        self.cornerRadius = cornerRadius
        self.isProminent = isProminent
        self.prominentGradient = prominentGradient
        self.content = content
    }
    
    public var body: some View {
        let isDark = (colorScheme == .dark)
        
        Button(action: action) {
            content()
                .background(
                    ZStack {
                        if isProminent {
                            let colors = prominentGradient ?? [
                                Color(red: 0.08, green: 0.48, blue: 0.98),
                                Color(red: 0.42, green: 0.18, blue: 0.92)
                            ]
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: colors.map { $0.opacity(hoverVm.isHovered ? 0.95 : 0.85) },
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        } else {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(.ultraThinMaterial)
                            
                            if isDark {
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(hoverVm.isHovered ? 0.12 : 0.06),
                                                Color.white.opacity(hoverVm.isHovered ? 0.03 : 0.01)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            } else {
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(hoverVm.isHovered ? 0.85 : 0.70),
                                                Color.white.opacity(hoverVm.isHovered ? 0.65 : 0.50)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            isProminent ?
                                LinearGradient(
                                    colors: [Color.white.opacity(0.35), Color.white.opacity(0.12)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ) :
                                (isDark ?
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(hoverVm.isHovered ? 0.22 : 0.12),
                                            Color.white.opacity(hoverVm.isHovered ? 0.06 : 0.02)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ) :
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(hoverVm.isHovered ? 0.95 : 0.85),
                                            Color.black.opacity(hoverVm.isHovered ? 0.12 : 0.06)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                ),
                            lineWidth: 0.75
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(
                    color: isProminent ?
                        Color.blue.opacity(hoverVm.isHovered ? 0.4 : 0.2) :
                        Color.black.opacity(isDark ? (hoverVm.isHovered ? 0.24 : 0.12) : (hoverVm.isHovered ? 0.08 : 0.04)),
                    radius: hoverVm.isHovered ? 5 : 2.5,
                    x: 0,
                    y: hoverVm.isHovered ? 2 : 1
                )
                .scaleEffect(hoverVm.isHovered ? 1.012 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.82), value: hoverVm.isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoverVm.isHovered = hovering
        }
    }
}

// MARK: - 5. Interactive Liquid Glass Capsule Button
public struct LiquidGlassCapsuleButton<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    public let action: () -> Void
    public var isSelected: Bool = false
    public var isProminent: Bool = false
    @ViewBuilder public let content: () -> Content
    
    @StateObject private var hoverVm = LiquidHoverViewModel()
    
    public init(
        action: @escaping () -> Void,
        isSelected: Bool = false,
        isProminent: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.action = action
        self.isSelected = isSelected
        self.isProminent = isProminent
        self.content = content
    }
    
    public var body: some View {
        let isDark = (colorScheme == .dark)
        
        Button(action: action) {
            content()
                .background(
                    ZStack {
                        if isSelected {
                            if isDark {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(white: hoverVm.isHovered ? 0.98 : 0.94), Color(white: hoverVm.isHovered ? 0.90 : 0.86)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            } else {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(white: hoverVm.isHovered ? 0.22 : 0.12), Color(white: hoverVm.isHovered ? 0.15 : 0.08)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                        } else if isProminent {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.08, green: 0.48, blue: 0.98).opacity(hoverVm.isHovered ? 0.95 : 0.85),
                                            Color(red: 0.42, green: 0.18, blue: 0.92).opacity(hoverVm.isHovered ? 0.95 : 0.85)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        } else {
                            if isDark {
                                Capsule()
                                    .fill(Color(white: hoverVm.isHovered ? 0.26 : 0.18))
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(hoverVm.isHovered ? 0.12 : 0.06),
                                                Color.clear
                                            ],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            } else {
                                Capsule()
                                    .fill(Color(white: hoverVm.isHovered ? 0.87 : 0.93))
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(hoverVm.isHovered ? 0.65 : 0.45),
                                                Color.clear
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                        }
                    }
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ?
                                (isDark ?
                                    LinearGradient(colors: [Color.white, Color(white: 0.84)], startPoint: .top, endPoint: .bottom) :
                                    LinearGradient(colors: [Color(white: 0.35), Color(white: 0.18)], startPoint: .top, endPoint: .bottom)
                                ) :
                                (isDark ?
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(hoverVm.isHovered ? 0.28 : 0.15),
                                            Color.white.opacity(hoverVm.isHovered ? 0.10 : 0.05)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ) :
                                    LinearGradient(
                                        colors: [
                                            Color.black.opacity(hoverVm.isHovered ? 0.16 : 0.10),
                                            Color.black.opacity(hoverVm.isHovered ? 0.12 : 0.07)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                ),
                            lineWidth: 0.85
                        )
                )
                .clipShape(Capsule())
                .shadow(
                    color: isSelected ?
                        (isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.16)) :
                        (isProminent ? Color.blue.opacity(0.35) : Color.black.opacity(isDark ? (hoverVm.isHovered ? 0.24 : 0.12) : (hoverVm.isHovered ? 0.08 : 0.04))),
                    radius: hoverVm.isHovered ? 5 : 2.5,
                    x: 0,
                    y: hoverVm.isHovered ? 2 : 1
                )
                .scaleEffect(hoverVm.isHovered ? 1.012 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.82), value: hoverVm.isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoverVm.isHovered = hovering
        }
    }
}

// MARK: - 6. Interactive Liquid Glass Circle Button
public struct LiquidGlassCircleButton<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    public let action: () -> Void
    public var size: CGFloat = 28
    @ViewBuilder public let content: () -> Content
    
    @StateObject private var hoverVm = LiquidHoverViewModel()
    
    public init(
        action: @escaping () -> Void,
        size: CGFloat = 28,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.action = action
        self.size = size
        self.content = content
    }
    
    public var body: some View {
        let isDark = (colorScheme == .dark)
        
        Button(action: action) {
            content()
                .frame(width: size, height: size)
                .background(
                    ZStack {
                        Circle().fill(.ultraThinMaterial)
                        if isDark {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(hoverVm.isHovered ? 0.12 : 0.05),
                                            Color.white.opacity(hoverVm.isHovered ? 0.03 : 0.01)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        } else {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(hoverVm.isHovered ? 0.85 : 0.70),
                                            Color.white.opacity(hoverVm.isHovered ? 0.65 : 0.50)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                    }
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            isDark ?
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(hoverVm.isHovered ? 0.22 : 0.11),
                                        Color.white.opacity(hoverVm.isHovered ? 0.06 : 0.02)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ) :
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(hoverVm.isHovered ? 0.95 : 0.85),
                                        Color.black.opacity(hoverVm.isHovered ? 0.12 : 0.06)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                            lineWidth: 0.75
                        )
                )
                .clipShape(Circle())
                .shadow(
                    color: Color.black.opacity(isDark ? (hoverVm.isHovered ? 0.25 : 0.12) : (hoverVm.isHovered ? 0.08 : 0.04)),
                    radius: hoverVm.isHovered ? 4 : 2,
                    x: 0,
                    y: hoverVm.isHovered ? 1.5 : 1
                )
                .scaleEffect(hoverVm.isHovered ? 1.04 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.82), value: hoverVm.isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoverVm.isHovered = hovering
        }
    }
}

// MARK: - 7. Apple-Style Unified Search Bar Modifier
public struct LiquidGlassSearchBarModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    public var isHovered: Bool = false
    
    public func body(content: Content) -> some View {
        let isDark = (colorScheme == .dark)
        
        content
            .background(
                ZStack {
                    if isDark {
                        // YouTube Dark Translucent Search Bar
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(isHovered ? 0.12 : 0.075))
                    } else {
                        // YouTube Light Clean Search Bar
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isDark ?
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.32 : 0.20),
                                    Color.white.opacity(isHovered ? 0.10 : 0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ) :
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(isHovered ? 0.28 : 0.16),
                                    Color.black.opacity(isHovered ? 0.22 : 0.12)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                        lineWidth: 1.0
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(
                color: Color.black.opacity(isDark ? 0.20 : (isHovered ? 0.06 : 0.03)),
                radius: isHovered ? 3 : 1.5,
                x: 0,
                y: 1
            )
    }
}

// MARK: - 8. View Extension Helpers
public extension View {
    func liquidGlass(cornerRadius: CGFloat = 12, isHovered: Bool = false, elevation: CGFloat = 3) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, isHovered: isHovered, elevation: elevation))
    }
    
    func liquidGlassCapsule(isHovered: Bool = false, isSelected: Bool = false, elevation: CGFloat = 2.5) -> some View {
        self.modifier(LiquidGlassCapsuleModifier(isHovered: isHovered, isSelected: isSelected, elevation: elevation))
    }
    
    func liquidGlassSearchBar(isHovered: Bool = false) -> some View {
        self.modifier(LiquidGlassSearchBarModifier(isHovered: isHovered))
    }
}
