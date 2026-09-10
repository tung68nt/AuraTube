import SwiftUI
import AppKit

// MARK: - Apple macOS Human Interface Guidelines (HIG) Liquid Glass System
// Built specifically for macOS Dark Mode: Native vibrancy, continuous squircles,
// delicate specular hairline reflections, and authentic optical depth.

@MainActor
public final class LiquidHoverViewModel: ObservableObject {
    @Published public var isHovered: Bool = false
    public init() {}
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
    public var cornerRadius: CGFloat = 12
    public var isHovered: Bool = false
    public var elevation: CGFloat = 3
    
    public init(cornerRadius: CGFloat = 12, isHovered: Bool = false, elevation: CGFloat = 3) {
        self.cornerRadius = cornerRadius
        self.isHovered = isHovered
        self.elevation = elevation
    }
    
    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // 1. Frosted Material Base (Native macOS blur)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    
                    // 2. Liquid Glass Ambient Tint (Soft top-lit reflection)
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
                }
            )
            .overlay(
                // 3. Hairline Specular Refraction (0.75pt delicate top-edge highlight)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isHovered ? 0.22 : 0.12),
                                Color.white.opacity(isHovered ? 0.07 : 0.03),
                                Color.black.opacity(0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            )
            .shadow(
                color: Color.black.opacity(isHovered ? 0.30 : 0.16),
                radius: isHovered ? elevation * 1.5 : elevation,
                x: 0,
                y: isHovered ? elevation * 0.75 : elevation * 0.5
            )
    }
}

// MARK: - 3. Liquid Glass Capsule Modifier (Chips & Pills)
public struct LiquidGlassCapsuleModifier: ViewModifier {
    public var isHovered: Bool = false
    public var isSelected: Bool = false
    public var elevation: CGFloat = 2.5
    
    public init(isHovered: Bool = false, isSelected: Bool = false, elevation: CGFloat = 2.5) {
        self.isHovered = isHovered
        self.isSelected = isSelected
        self.elevation = elevation
    }
    
    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    if isSelected {
                        // Luminous active pill: Apple-style translucent silk white
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(white: 0.94),
                                        Color(white: 0.86)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    } else {
                        // Inactive glass pill: Frosted material with ambient top glint
                        Capsule()
                            .fill(.ultraThinMaterial)
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isHovered ? 0.11 : 0.05),
                                        Color.white.opacity(isHovered ? 0.03 : 0.01)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                }
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ?
                            LinearGradient(
                                colors: [Color.white, Color(white: 0.82)],
                                startPoint: .top,
                                endPoint: .bottom
                            ) :
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.22 : 0.11),
                                    Color.white.opacity(isHovered ? 0.06 : 0.02)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                        lineWidth: 0.75
                    )
            )
            .shadow(
                color: isSelected ?
                    Color.white.opacity(0.18) :
                    Color.black.opacity(isHovered ? 0.25 : 0.14),
                radius: isSelected ? 5 : (isHovered ? elevation * 1.5 : elevation),
                x: 0,
                y: isSelected ? 1.5 : elevation * 0.5
            )
    }
}

// MARK: - 4. Interactive Liquid Glass Button (Continuous Squircle)
public struct LiquidGlassButton<Content: View>: View {
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
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isProminent ? 0.35 : (hoverVm.isHovered ? 0.22 : 0.12)),
                                    Color.white.opacity(isProminent ? 0.12 : (hoverVm.isHovered ? 0.06 : 0.02))
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(
                    color: isProminent ?
                        Color.blue.opacity(hoverVm.isHovered ? 0.4 : 0.2) :
                        Color.black.opacity(hoverVm.isHovered ? 0.24 : 0.12),
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
        Button(action: action) {
            content()
                .background(
                    ZStack {
                        if isSelected {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(white: 0.96), Color(white: 0.88)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
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
                            Capsule().fill(.ultraThinMaterial)
                            
                            // Translucent liquid glass body wash
                            Capsule()
                                .fill(Color.white.opacity(hoverVm.isHovered ? 0.12 : 0.065))
                            
                            // Top specular glint
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(hoverVm.isHovered ? 0.10 : 0.05),
                                            Color.clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        }
                    }
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ?
                                LinearGradient(colors: [Color.white, Color(white: 0.84)], startPoint: .top, endPoint: .bottom) :
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(hoverVm.isHovered ? 0.28 : 0.15),
                                        Color.white.opacity(hoverVm.isHovered ? 0.08 : 0.03)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                            lineWidth: 0.75
                        )
                )
                .clipShape(Capsule())
                .shadow(
                    color: isSelected ?
                        Color.white.opacity(0.18) :
                        (isProminent ? Color.blue.opacity(0.35) : Color.black.opacity(hoverVm.isHovered ? 0.24 : 0.12)),
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
        Button(action: action) {
            content()
                .frame(width: size, height: size)
                .background(
                    ZStack {
                        Circle().fill(.ultraThinMaterial)
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
                    }
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(hoverVm.isHovered ? 0.22 : 0.11),
                                    Color.white.opacity(hoverVm.isHovered ? 0.06 : 0.02)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                )
                .clipShape(Circle())
                .shadow(
                    color: Color.black.opacity(hoverVm.isHovered ? 0.25 : 0.12),
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

// MARK: - 7. View Extension Helpers
public extension View {
    func liquidGlass(cornerRadius: CGFloat = 12, isHovered: Bool = false, elevation: CGFloat = 3) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, isHovered: isHovered, elevation: elevation))
    }
    
    func liquidGlassCapsule(isHovered: Bool = false, isSelected: Bool = false, elevation: CGFloat = 2.5) -> some View {
        self.modifier(LiquidGlassCapsuleModifier(isHovered: isHovered, isSelected: isSelected, elevation: elevation))
    }
    
    // Apple-Style Unified Search Bar
    func liquidGlassSearchBar(isHovered: Bool = false) -> some View {
        self
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(isHovered ? 0.11 : 0.075))
                    
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.08 : 0.04),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isHovered ? 0.28 : 0.18),
                                Color.white.opacity(isHovered ? 0.10 : 0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: Color.black.opacity(0.20), radius: isHovered ? 3 : 1.5, x: 0, y: 1)
    }
}
