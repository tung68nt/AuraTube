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
                                        Color.white.opacity(isHovered ? 0.52 : 0.35),
                                        Color.white.opacity(isHovered ? 0.30 : 0.15)
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
                            // Light Mode: Authentic Liquid Glass Capsule
                            Capsule().fill(.ultraThinMaterial)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(isHovered ? 0.52 : 0.35),
                                            Color.white.opacity(isHovered ? 0.30 : 0.15)
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
                                        Color.white.opacity(isHovered ? 0.95 : 0.85),
                                        Color.black.opacity(isHovered ? 0.12 : 0.07)
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
                                                Color.white.opacity(hoverVm.isHovered ? 0.52 : 0.35),
                                                Color.white.opacity(hoverVm.isHovered ? 0.30 : 0.15)
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

// MARK: - 5. Interactive Liquid Glass Capsule Button (Chips, Pills & Tags)
public struct LiquidGlassCapsuleButton<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    public let action: () -> Void
    public var isSelected: Bool = false
    public var isProminent: Bool = false
    @ViewBuilder public let content: () -> Content
    
    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false
    @State private var mouseLocation: CGPoint = .zero
    
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
                    GeometryReader { geo in
                        ZStack {
                            if isSelected {
                                if isDark {
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color(white: 0.98), Color(white: 0.90)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                } else {
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color(white: 0.18), Color(white: 0.08)],
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
                                                Color(red: 0.08, green: 0.48, blue: 0.98).opacity(isHovered ? 0.95 : 0.85),
                                                Color(red: 0.42, green: 0.18, blue: 0.92).opacity(isHovered ? 0.95 : 0.85)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            } else {
                                // Authentic Liquid Glass Material Base
                                Capsule().fill(.ultraThinMaterial)
                                
                                if isDark {
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(isHovered ? 0.18 : 0.10),
                                                    Color.white.opacity(isHovered ? 0.08 : 0.03)
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                } else {
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(isHovered ? 0.52 : 0.35),
                                                    Color.white.opacity(isHovered ? 0.30 : 0.15)
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                }
                                
                                // Dynamic Mouse-Tracking Specular Refraction (Gentle Glass Sheen)
                                if isHovered {
                                    let glowOpacity: Double = isSelected ? 0.12 : (isDark ? 0.16 : 0.22)
                                    RadialGradient(
                                        colors: [
                                            Color.white.opacity(glowOpacity),
                                            Color.white.opacity(glowOpacity * 0.25),
                                            Color.clear
                                        ],
                                        center: UnitPoint(
                                            x: max(0, min(1, mouseLocation.x / max(geo.size.width, 1))),
                                            y: max(0, min(1, mouseLocation.y / max(geo.size.height, 1)))
                                        ),
                                        startRadius: 0,
                                        endRadius: max(geo.size.width, geo.size.height) * 0.65
                                    )
                                    .clipShape(Capsule())
                                }
                            }
                            
                            // Inner Top Crescent Highlight (Specular Bevel)
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(isSelected ? 0.5 : (isDark ? (isHovered ? 0.55 : 0.30) : (isHovered ? 0.95 : 0.80))),
                                            Color.white.opacity(0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .center
                                    ),
                                    lineWidth: 1.0
                                )
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
                                            Color.white.opacity(isHovered ? 0.38 : 0.18),
                                            Color.white.opacity(isHovered ? 0.12 : 0.05)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ) :
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(isHovered ? 0.98 : 0.88),
                                            Color.black.opacity(isHovered ? 0.14 : 0.08)
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
                        (isProminent ? Color.blue.opacity(0.35) : Color.black.opacity(isDark ? (isHovered ? 0.30 : 0.12) : (isHovered ? 0.10 : 0.04))),
                    radius: isHovered ? 5.5 : 2.5,
                    x: 0,
                    y: isHovered ? 2.5 : 1
                )
                .scaleEffect(isPressed ? 0.95 : (isHovered ? 1.035 : 1.0))
                .animation(.spring(response: 0.26, dampingFraction: 0.68), value: isHovered)
                .animation(.spring(response: 0.16, dampingFraction: 0.75), value: isPressed)
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                mouseLocation = location
                isHovered = true
            case .ended:
                isHovered = false
            }
        }
        ._onButtonGesture { pressing in
            isPressed = pressing
        } perform: {}
    }
}

// MARK: - 6. Interactive Liquid Glass Circle Button (with Mouse-Tracking & Liquid Optics)
public struct LiquidGlassCircleButton<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    public let action: () -> Void
    public var size: CGFloat = 28
    public var isActive: Bool = false
    public var activeTint: Color? = nil
    @ViewBuilder public let content: () -> Content
    
    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false
    @State private var mouseLocation: CGPoint = .zero
    
    public init(
        action: @escaping () -> Void,
        size: CGFloat = 28,
        isActive: Bool = false,
        activeTint: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.action = action
        self.size = size
        self.isActive = isActive
        self.activeTint = activeTint
        self.content = content
    }
    
    public var body: some View {
        let isDark = (colorScheme == .dark)
        
        Button(action: action) {
            content()
                .frame(width: size, height: size)
                .background(
                    ZStack {
                        // 1. Frosted Material (Hardware-accelerated macOS blur)
                        Circle().fill(.ultraThinMaterial)
                        
                        // 2. Liquid Glass Ambient Tint
                        if isActive {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            (activeTint ?? Color(red: 0.2, green: 0.65, blue: 1.0)),
                                            (activeTint ?? Color(red: 0.2, green: 0.65, blue: 1.0)).opacity(0.82)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        } else if isDark {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(isHovered ? 0.22 : 0.12),
                                            Color.white.opacity(isHovered ? 0.08 : 0.03)
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
                                            Color.white.opacity(isHovered ? 0.48 : 0.28),
                                            Color.white.opacity(isHovered ? 0.28 : 0.12)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                        
                        // 3. Dynamic Specular Sheen (Subtle, Silk Glass Optics - No Blinding Flare)
                        if isHovered && !isPressed {
                            if isActive {
                                // Active colored buttons (e.g. Red PiP button): gentle ambient lift without any mouse hotspot
                                Circle()
                                    .fill(Color.white.opacity(0.12))
                            } else {
                                // Translucent glass buttons: delicate, silky optical refraction
                                let glowOpacity: Double = isDark ? 0.15 : 0.20
                                RadialGradient(
                                    colors: [
                                        Color.white.opacity(glowOpacity),
                                        Color.white.opacity(glowOpacity * 0.25),
                                        Color.clear
                                    ],
                                    center: UnitPoint(
                                        x: max(0, min(1, mouseLocation.x / max(size, 1))),
                                        y: max(0, min(1, mouseLocation.y / max(size, 1)))
                                    ),
                                    startRadius: 0,
                                    endRadius: size * 0.8
                                )
                                .clipShape(Circle())
                            }
                        }
                        
                        // 4. Inner Top-Edge Specular Reflection (Glass Bevel)
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isActive ? 0.45 : (isDark ? (isHovered ? 0.65 : 0.38) : (isHovered ? 0.95 : 0.82))),
                                        Color.white.opacity(0.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                ),
                                lineWidth: 1.0
                            )
                    }
                )
                .overlay(
                    // 5. Outer Dual Hairline Refraction Rim
                    Circle()
                        .strokeBorder(
                            isActive ?
                                LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.15)], startPoint: .top, endPoint: .bottom) :
                                (isDark ?
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(isHovered ? 0.45 : 0.22),
                                            Color.black.opacity(isHovered ? 0.30 : 0.15)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ) :
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(isHovered ? 0.98 : 0.85),
                                            Color.black.opacity(isHovered ? 0.14 : 0.08)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                ),
                            lineWidth: 0.85
                        )
                )
                .clipShape(Circle())
                .shadow(
                    color: isActive ?
                        (activeTint ?? Color.blue).opacity(isHovered ? 0.25 : 0.15) :
                        Color.black.opacity(isDark ? (isHovered ? 0.25 : 0.12) : (isHovered ? 0.10 : 0.04)),
                    radius: isHovered ? 4.0 : 2.0,
                    x: 0,
                    y: isHovered ? 1.5 : 0.5
                )
                .scaleEffect(isPressed ? 0.92 : (isHovered ? 1.05 : 1.0))
                .animation(.spring(response: 0.26, dampingFraction: 0.65), value: isHovered)
                .animation(.spring(response: 0.16, dampingFraction: 0.75), value: isPressed)
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                mouseLocation = location
                isHovered = true
            case .ended:
                isHovered = false
            }
        }
        ._onButtonGesture { pressing in
            isPressed = pressing
        } perform: {}
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
                        // YouTube Light Liquid Glass Search Bar
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isHovered ? 0.78 : 0.62),
                                        Color.white.opacity(isHovered ? 0.58 : 0.42)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
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
                                    Color.white.opacity(0.95),
                                    Color.black.opacity(isHovered ? 0.16 : 0.10)
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

// MARK: - 8. Right-Click Interceptor for Custom Liquid Glass Popovers
public struct RightClickDetector: NSViewRepresentable {
    public let action: () -> Void
    
    public init(action: @escaping () -> Void) {
        self.action = action
    }
    
    public func makeNSView(context: Context) -> RightClickNSView {
        let view = RightClickNSView()
        view.action = action
        return view
    }
    
    public func updateNSView(_ nsView: RightClickNSView, context: Context) {
        nsView.action = action
    }
}

public final class RightClickNSView: NSView {
    public var action: (() -> Void)?
    
    public override func hitTest(_ point: NSPoint) -> NSView? {
        if let event = NSApp.currentEvent, event.type == .rightMouseDown || event.type == .rightMouseUp {
            return self
        }
        return nil
    }
    
    public override func rightMouseDown(with event: NSEvent) {
        action?()
    }
}

public struct OnRightClickModifier: ViewModifier {
    public let action: () -> Void
    
    public func body(content: Content) -> some View {
        content.overlay(
            RightClickDetector(action: action)
        )
    }
}

// MARK: - 9. Liquid Glass Menu Container (Replaces stark opaque NSMenu)
public struct LiquidGlassMenuContainer<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder public let content: () -> Content
    
    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    public var body: some View {
        let isDark = colorScheme == .dark
        
        content()
            .padding(8)
            .background(
                ZStack {
                    VisualEffectBackground(material: .popover, blendingMode: .withinWindow)
                    
                    if isDark {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(white: 0.12).opacity(0.85),
                                        Color(white: 0.06).opacity(0.92)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.65),
                                        Color.white.opacity(0.45)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    
                    // Specular Crescent Bevel Highlight
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isDark ? 0.32 : 0.85),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .center
                            ),
                            lineWidth: 1.0
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isDark ?
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.24),
                                    Color.white.opacity(0.06),
                                    Color.black.opacity(0.40)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.92),
                                    Color.black.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                        lineWidth: 0.85
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.black.opacity(isDark ? 0.35 : 0.14), radius: 18, x: 0, y: 8)
            .shadow(color: Color.black.opacity(isDark ? 0.20 : 0.08), radius: 4, x: 0, y: 2)
    }
}

// MARK: - 10. Liquid Glass Menu Row
public struct LiquidGlassMenuRow: View {
    @Environment(\.colorScheme) private var colorScheme
    public let title: String
    public var subtitle: String? = nil
    public var icon: String
    public var iconTint: Color = .primary
    public var shortcut: String? = nil
    public let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    public init(
        title: String,
        subtitle: String? = nil,
        icon: String,
        iconTint: Color = .primary,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconTint = iconTint
        self.shortcut = shortcut
        self.action = action
    }
    
    public var body: some View {
        let isDark = colorScheme == .dark
        
        Button(action: action) {
            HStack(spacing: 10) {
                // Frosted icon lens
                ZStack {
                    Circle()
                        .fill(iconTint.opacity(isDark ? 0.20 : 0.14))
                        .frame(width: 26, height: 26)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(iconTint)
                }
                
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 10.5))
                            .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                    }
                }
                
                Spacer(minLength: 8)
                
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                        )
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6.5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isHovered ?
                            (isDark ? Color.white.opacity(0.12) : Color.white.opacity(0.65)) :
                            Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isHovered ?
                            (isDark ? Color.white.opacity(0.18) : Color.white.opacity(0.85)) :
                            Color.clear,
                        lineWidth: 0.75
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - 11. Liquid Glass Luxury Switch (visionOS / macOS Sequoia Style)
public struct LiquidGlassLuxurySwitch: View {
    @Binding public var isOn: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    public init(isOn: Binding<Bool>) {
        self._isOn = isOn
    }
    
    public var body: some View {
        let isDark = colorScheme == .dark
        
        Button(action: {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.70)) {
                isOn.toggle()
            }
        }) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                // 1. Track Base
                Capsule()
                    .fill(
                        isOn ?
                            LinearGradient(
                                colors: [
                                    Color(red: 0.08, green: 0.50, blue: 1.0),
                                    Color(red: 0.16, green: 0.36, blue: 0.96)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: isDark ? [
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.06)
                                ] : [
                                    Color.black.opacity(0.12),
                                    Color.black.opacity(0.06)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
                    .frame(width: 38, height: 22)
                
                // 2. Specular Bevel Highlight on Track
                Capsule()
                    .strokeBorder(
                        isOn ?
                            LinearGradient(
                                colors: [Color.white.opacity(0.55), Color.white.opacity(0.15)],
                                startPoint: .top,
                                endPoint: .bottom
                            ) :
                            LinearGradient(
                                colors: isDark ? [
                                    Color.white.opacity(0.20),
                                    Color.white.opacity(0.04)
                                ] : [
                                    Color.white.opacity(0.85),
                                    Color.black.opacity(0.08)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                        lineWidth: 0.85
                    )
                    .frame(width: 38, height: 22)
                
                // 3. Porcelain Glass Knob
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color(white: 0.94)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.9), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 2.5, x: 0, y: 1.5)
                    .padding(2)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 12. Liquid Glass Segmented Size Picker
public struct LiquidGlassSegmentedSizePicker: View {
    @ObservedObject var pipController = PiPWindowController.shared
    @Environment(\.colorScheme) private var colorScheme
    
    public init() {}
    
    private let sizes: [(width: CGFloat, label: String, sub: String)] = [
        (380, "380p", "Nhỏ"),
        (540, "540p", "Vừa"),
        (720, "720p", "Lớn")
    ]
    
    public var body: some View {
        let isDark = colorScheme == .dark
        let currentWidth = pipController.currentWidth
        
        HStack(spacing: 4) {
            ForEach(sizes, id: \.width) { item in
                let isSelected = abs(currentWidth - item.width) < 30
                
                Button(action: {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.75)) {
                        pipController.setPipSize(width: item.width)
                    }
                }) {
                    HStack(spacing: 3) {
                        Text(item.label)
                            .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                        Text("•")
                            .font(.system(size: 8))
                            .opacity(0.6)
                        Text(item.sub)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                            .opacity(isSelected ? 0.95 : 0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundColor(
                        isSelected ?
                            (isDark ? Color.black : Color.white) :
                            ThemeColor.textPrimary(for: colorScheme).opacity(0.85)
                    )
                    .background(
                        ZStack {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        isDark ?
                                            LinearGradient(colors: [Color.white, Color(white: 0.90)], startPoint: .top, endPoint: .bottom) :
                                            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
                                    )
                                    .shadow(color: Color.black.opacity(isDark ? 0.20 : 0.15), radius: 3, x: 0, y: 1.5)
                            }
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isSelected ?
                                    Color.white.opacity(isDark ? 0.4 : 0.2) :
                                    Color.clear,
                                lineWidth: 0.75
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isDark ?
                        Color.white.opacity(0.06) :
                        Color.black.opacity(0.04)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
                    lineWidth: 0.75
                )
        )
    }
}

// MARK: - 13. Liquid Glass Floating PiP Settings Card
@MainActor
public struct PiPLiquidGlassSettingsCard: View {
    @ObservedObject var playerManager: PlayerManager = PlayerManager.shared
    @Environment(\.colorScheme) private var colorScheme
    public var onClose: (() -> Void)? = nil
    
    public init(playerManager: PlayerManager? = nil, onClose: (() -> Void)? = nil) {
        self.playerManager = playerManager ?? PlayerManager.shared
        self.onClose = onClose
    }
    
    public var body: some View {
        let isDark = colorScheme == .dark
        let isActive = playerManager.isPictureInPictureActive
        
        VStack(alignment: .leading, spacing: 13) {
            // 1. Header Bar: Engine Title + Status Indicator + Close Button
            HStack(alignment: .center) {
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        (isActive ? Color.red : Color(red: 0.08, green: 0.48, blue: 0.98)).opacity(isDark ? 0.25 : 0.18),
                                        (isActive ? Color.red : Color(red: 0.08, green: 0.48, blue: 0.98)).opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 26, height: 26)
                        
                        Image(systemName: "pip")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(isActive ? .red : Color(red: 0.08, green: 0.48, blue: 0.98))
                    }
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Cửa sổ nổi PiP")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                        Text(isActive ? "Đang ghim trên màn hình" : "Chế độ phát nền & mini")
                            .font(.system(size: 10))
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme).opacity(0.8))
                    }
                }
                
                Spacer()
                
                // Status indicator pill
                HStack(spacing: 4) {
                    Circle()
                        .fill(isActive ? Color.red : Color.green)
                        .frame(width: 5.5, height: 5.5)
                    Text(isActive ? "Đang bật" : "Sẵn sàng")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isActive ? .red : Color.green)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(isActive ? Color.red.opacity(0.12) : Color.green.opacity(0.12))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isActive ? Color.red.opacity(0.25) : Color.green.opacity(0.25), lineWidth: 0.75)
                )
                
                // Close button
                Button(action: {
                    if let onClose = onClose {
                        onClose()
                    } else {
                        playerManager.togglePiPSettingsCard()
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
            
            // 2. Hero PiP Action Button (Vibrant Liquid Glass Gradient)
            Button(action: {
                playerManager.togglePictureInPicture()
            }) {
                HStack(spacing: 10) {
                    Image(systemName: isActive ? "pip.exit" : "pip.enter")
                        .font(.system(size: 14, weight: .bold))
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(isActive ? "Đưa video về cửa sổ chính" : "Chuyển sang cửa sổ nổi")
                            .font(.system(size: 12.5, weight: .bold))
                        Text(isActive ? "Tắt cửa sổ nổi và phát ở app AuraTube" : "Ghim video luôn nổi trên các ứng dụng")
                            .font(.system(size: 10))
                            .opacity(0.85)
                    }
                    
                    Spacer()
                    
                    Text("P")
                        .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.25))
                        )
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        if isActive {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.92, green: 0.22, blue: 0.32),
                                            Color(red: 0.80, green: 0.12, blue: 0.22)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.08, green: 0.48, blue: 0.98),
                                            Color(red: 0.18, green: 0.32, blue: 0.92)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        // Top crescent reflection
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.45), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                ),
                                lineWidth: 1.0
                            )
                    }
                )
                .shadow(color: (isActive ? Color.red : Color.blue).opacity(0.32), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            
            // 3. Size Control Section (Always accessible)
            VStack(alignment: .leading, spacing: 6) {
                Text("KÍCH THƯỚC CỬA SỔ NỔI")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                    .tracking(0.5)
                
                LiquidGlassSegmentedSizePicker()
            }
            
            // Specular Divider
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, ThemeColor.divider(for: colorScheme), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.75)
            
            // 4. Smart Automation Toggles
            VStack(alignment: .leading, spacing: 10) {
                Text("TỰ ĐỘNG HÓA THÔNG MINH")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                    .tracking(0.5)
                
                // Toggle 1: Auto PiP on app switch
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(ThemeColor.textPrimary(for: colorScheme).opacity(0.06))
                            .frame(width: 26, height: 26)
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Tự động chuyển PiP khi chuyển app")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                        Text("Tự bật PiP khi bạn chuyển sang app khác")
                            .font(.system(size: 10))
                            .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                    }
                    
                    Spacer()
                    
                    LiquidGlassLuxurySwitch(isOn: $playerManager.autoPiPOnAppSwitch)
                }
                
                // Toggle 2: Return PiP on main app focus
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(ThemeColor.textPrimary(for: colorScheme).opacity(0.06))
                            .frame(width: 26, height: 26)
                        Image(systemName: "arrow.uturn.backward.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Tắt PiP khi bấm lại app chính")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                        Text("Khôi phục phát ở màn hình chính")
                            .font(.system(size: 10))
                            .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                    }
                    
                    Spacer()
                    
                    LiquidGlassLuxurySwitch(isOn: $playerManager.autoReturnPiPOnAppFocus)
                }
            }
        }
        .padding(14)
        .frame(width: 304)
        .background(
            ZStack {
                // 1. Ultra-thin hardware vibrancy
                VisualEffectBackground(material: .popover, blendingMode: .withinWindow)
                
                // 2. Translucent Ambient Glass Tint
                if isDark {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 24/255, green: 26/255, blue: 34/255).opacity(0.86),
                                    Color(red: 14/255, green: 16/255, blue: 22/255).opacity(0.92)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color.white.opacity(0.30)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                // 3. Specular Prismatic Bevel (Inner Crescent)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.35 : 0.90),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1.0
                    )
            }
        )
        .overlay(
            // 4. Outer Dual Specular Hairline
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isDark ?
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.28),
                                Color.white.opacity(0.08),
                                Color.black.opacity(0.40)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color.white.opacity(0.60),
                                Color.black.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                    lineWidth: 0.85
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(isDark ? 0.35 : 0.08), radius: 8, x: 0, y: 4)
        .shadow(color: isDark ? Color.blue.opacity(0.10) : Color.black.opacity(0.12), radius: 24, x: 0, y: 12)
    }
}

// MARK: - 14. Seamless Liquid Glass PiP Button
@MainActor
public struct LiquidGlassPiPButton: View {
    @ObservedObject private var playerManager = PlayerManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered: Bool = false
    
    public init() {}
    
    public var body: some View {
        let isDark = colorScheme == .dark
        let isActive = playerManager.isPictureInPictureActive
        
        HStack(spacing: 0) {
            // Main Action Button (Toggle PiP immediately)
            Button(action: {
                playerManager.togglePictureInPicture()
            }) {
                Image(systemName: isActive ? "pip.exit" : "pip.enter")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(isActive ? .white : ThemeColor.textPrimary(for: colorScheme).opacity(0.85))
                    .frame(width: 26, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Dropdown Chevron Trigger (Seamlessly integrated - NO dividing line!)
            Button(action: {
                playerManager.togglePiPSettingsCard()
            }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isActive ? Color.white.opacity(0.9) : ThemeColor.textSecondary(for: colorScheme))
                    .frame(width: 16, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                
                if isActive {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.red.opacity(0.90), Color.red.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                } else if isDark {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.20 : 0.10),
                                    Color.white.opacity(isHovered ? 0.08 : 0.03)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                } else {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.52 : 0.32),
                                    Color.white.opacity(isHovered ? 0.28 : 0.14)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                
                // Specular Bevel
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isActive ? 0.45 : (isDark ? 0.40 : 0.85)),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 1.0
                    )
            }
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    isActive ?
                        LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.15)], startPoint: .top, endPoint: .bottom) :
                        (isDark ?
                            LinearGradient(
                                colors: [Color.white.opacity(isHovered ? 0.40 : 0.20), Color.black.opacity(0.30)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [Color.white.opacity(0.92), Color.black.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        ),
                    lineWidth: 0.85
                )
        )
        .clipShape(Capsule())
        .shadow(
            color: isActive ?
                Color.red.opacity(0.3) :
                Color.black.opacity(isDark ? 0.20 : 0.06),
            radius: isHovered ? 4 : 2,
            x: 0,
            y: 1
        )
        .onHover { hovering in
            withAnimation(.spring(response: 0.24, dampingFraction: 0.75)) {
                isHovered = hovering
            }
        }
        .onRightClick {
            playerManager.togglePiPSettingsCard()
        }
        .help(isActive ? "Đưa video về cửa sổ chính (P) • Bấm ▾ để cài đặt kính lỏng" : "Chuyển sang cửa sổ nổi PiP (P) • Bấm ▾ để cài đặt kính lỏng")
    }
}

// MARK: - 15. View Extension Helpers
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
    
    func onRightClick(perform action: @escaping () -> Void) -> some View {
        self.modifier(OnRightClickModifier(action: action))
    }
}

