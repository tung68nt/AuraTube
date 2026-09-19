import SwiftUI
import AppKit

public enum SettingsTab: String, CaseIterable, Identifiable {
    case appearance = "Giao diện"
    case pip = "Cửa sổ nổi PiP"
    case updates = "Cập nhật & Hệ thống"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .appearance: return "paintbrush.fill"
        case .pip: return "pip.fill"
        case .updates: return "gearshape.2.fill"
        }
    }
}

public struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var playerManager = PlayerManager.shared
    @ObservedObject private var updateService = UpdateService.shared
    
    @State private var selectedTab: SettingsTab
    
    public init(initialTab: SettingsTab = .appearance) {
        _selectedTab = State(initialValue: initialTab)
    }
    
    private var isDark: Bool {
        colorScheme == .dark
    }
    
    private var appIcon: NSImage? {
        if let img = NSImage(contentsOfFile: "/Users/tungnguyen/Code/Youtube/assets/icon.png") {
            return img
        }
        return NSApp.applicationIconImage
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 1. Classic Asymmetric Header (Apple HIG / ALG-DS Section 1 & 3.1)
            HStack(alignment: .center, spacing: 16) {
                // App Icon 52x52 with specular rim & soft shadow
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(isDark ? 0.35 : 0.65),
                                            Color.white.opacity(isDark ? 0.10 : 0.20)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.75
                                )
                        )
                        .shadow(color: Color.black.opacity(isDark ? 0.40 : 0.16), radius: 8, y: 3)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Cài đặt AuraTube")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                        
                        // Version Tag Chip
                        Text("v\(updateService.currentVersion)")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 0.5)
                            )
                    }
                    
                    Text("Tùy biến giao diện, điều khiển cửa sổ nổi PiP và quản lý cập nhật")
                        .font(.system(size: 12))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)
            
            // MARK: - 2. Fluid Liquid Glass Tab Bar (Segmented Selector)
            HStack(spacing: 6) {
                ForEach(SettingsTab.allCases) { tab in
                    tabButton(tab: tab)
                }
                Spacer()
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            
            // MARK: - 3. Tab Content Area with Recessed Frosted Plates (ALG-DS Section 3.3)
            VStack(spacing: 14) {
                switch selectedTab {
                case .appearance:
                    appearanceTabContent
                case .pip:
                    pipTabContent
                case .updates:
                    updatesTabContent
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 290, alignment: .top)
            
            // MARK: - 4. Bottom Action Footer (Apple HIG: Right-aligned dismiss)
            HStack {
                Text("Phím tắt: ⌘, mở Cài đặt • Esc để đóng")
                    .font(.system(size: 11))
                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme).opacity(0.7))
                
                Spacer()
                
                // Done Action Button (Primary Accent)
                Button(action: {
                    dismiss()
                }) {
                    Text("Xong")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.08, green: 0.50, blue: 0.98),
                                            Color(red: 0.04, green: 0.42, blue: 0.92)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.40), Color.clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.75
                                )
                        )
                        .shadow(color: Color.black.opacity(0.18), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                
                // Cancel / Close Button (Secondary Plain)
                Button(action: {
                    dismiss()
                }) {
                    Text("Đóng")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.85))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(
                                    isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.10),
                                    lineWidth: 0.75
                                )
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .frame(width: 560)
        .background(
            ZStack {
                // 1. Hardware Optical Blur
                VisualEffectBackground(material: .popover, blendingMode: .behindWindow, state: .active)
                
                // 2. Translucent Optical Glass Tint (Dark: 32,34,40 @ 0.65; Light: white @ 0.75)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        isDark ?
                            LinearGradient(
                                colors: [
                                    Color(red: 32/255, green: 34/255, blue: 40/255).opacity(0.65),
                                    Color(red: 22/255, green: 23/255, blue: 28/255).opacity(0.72)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ) :
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.75),
                                    Color(red: 248/255, green: 249/255, blue: 252/255).opacity(0.78)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
                
                // 3. Specular Ambient Top Sheen
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDark ? 0.08 : 0.25),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            // 4. Specular Rim Hairline (0.75pt)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isDark ? 0.30 : 0.80),
                            Color.white.opacity(isDark ? 0.08 : 0.25)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        )
        .shadow(color: Color.black.opacity(isDark ? 0.42 : 0.16), radius: 26, y: 12)
    }
    
    // MARK: - Tab Bar Button Component
    @ViewBuilder
    private func tabButton(tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        let fontWeight: Font.Weight = isSelected ? .bold : .medium
        let textColor = isSelected ? (isDark ? Color.white : Color.black) : ThemeColor.textSecondary(for: colorScheme)
        
        Button(action: {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                selectedTab = tab
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 11.5, weight: fontWeight))
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: fontWeight))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundColor(textColor)
            .background(tabButtonBackground(isSelected: isSelected))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(tabButtonBorder(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func tabButtonBackground(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isDark ?
                        LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.10)], startPoint: .top, endPoint: .bottom) :
                        LinearGradient(colors: [Color.white.opacity(0.95), Color(white: 0.90)], startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: Color.black.opacity(isDark ? 0.22 : 0.10), radius: 4, y: 1.5)
        }
    }
    
    @ViewBuilder
    private func tabButtonBorder(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isDark ? 0.35 : 0.85),
                            Color.white.opacity(isDark ? 0.10 : 0.30)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        }
    }
    
    // MARK: - Tab 1: Appearance Content
    @ViewBuilder
    private var appearanceTabContent: some View {
        recessedPlate(title: "Chế độ hiển thị (Theme)") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Chọn giao diện màu sắc phù hợp với sở thích hoặc tự động đồng bộ theo hệ thống macOS.")
                    .font(.system(size: 12))
                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    .lineSpacing(2)
                
                HStack(spacing: 12) {
                    themeOptionCard(
                        theme: .system,
                        title: "Tự động",
                        subtitle: "Đồng bộ macOS",
                        icon: "circle.lefthalf.filled"
                    )
                    
                    themeOptionCard(
                        theme: .light,
                        title: "Sáng",
                        subtitle: "Kính sữa trong suốt",
                        icon: "sun.max.fill"
                    )
                    
                    themeOptionCard(
                        theme: .dark,
                        title: "Tối",
                        subtitle: "Obsidian sâu thẳm",
                        icon: "moon.fill"
                    )
                }
            }
        }
    }
    
    @ViewBuilder
    private func themeOptionCard(theme: AppTheme, title: String, subtitle: String, icon: String) -> some View {
        let isSelected = themeManager.currentTheme == theme
        
        Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                themeManager.setTheme(theme)
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    // Distinct thematic icon badge
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                theme == .light ?
                                    LinearGradient(colors: [Color(red: 1.0, green: 0.65, blue: 0.15), Color(red: 1.0, green: 0.45, blue: 0.10)], startPoint: .top, endPoint: .bottom) :
                                (theme == .dark ?
                                    LinearGradient(colors: [Color(red: 0.38, green: 0.35, blue: 0.85), Color(red: 0.22, green: 0.18, blue: 0.65)], startPoint: .top, endPoint: .bottom) :
                                    LinearGradient(colors: [Color(red: 0.15, green: 0.58, blue: 1.0), Color(red: 0.05, green: 0.38, blue: 0.85)], startPoint: .top, endPoint: .bottom))
                            )
                            .frame(width: 26, height: 26)
                            .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)
                        
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    // State Indicator (Active checkmark vs unselected radio rim)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color(red: 0.08, green: 0.50, blue: 0.98))
                    } else {
                        Circle()
                            .strokeBorder(isDark ? Color.white.opacity(0.22) : Color.black.opacity(0.18), lineWidth: 1.0)
                            .frame(width: 14, height: 14)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(
                                isDark ?
                                    LinearGradient(colors: [Color(red: 0.12, green: 0.45, blue: 0.95).opacity(0.24), Color(red: 0.06, green: 0.30, blue: 0.80).opacity(0.16)], startPoint: .top, endPoint: .bottom) :
                                    LinearGradient(colors: [Color.white, Color(red: 246/255, green: 249/255, blue: 255/255)], startPoint: .top, endPoint: .bottom)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(
                                isDark ?
                                    Color.white.opacity(0.04) :
                                    Color.black.opacity(0.02)
                            )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        isSelected ?
                            LinearGradient(
                                colors: [
                                    Color(red: 0.18, green: 0.60, blue: 1.0),
                                    Color(red: 0.04, green: 0.42, blue: 0.92)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isDark ? 0.16 : 0.65),
                                    Color.black.opacity(isDark ? 0.28 : 0.08)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                        lineWidth: isSelected ? 1.5 : 0.75
                    )
            )
            .shadow(
                color: isSelected ?
                    Color(red: 0.08, green: 0.48, blue: 0.98).opacity(isDark ? 0.30 : 0.14) :
                    Color.black.opacity(isDark ? 0.10 : 0.03),
                radius: isSelected ? 5 : 2,
                x: 0,
                y: isSelected ? 2 : 1
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Tab 2: PiP Content
    @ViewBuilder
    private var pipTabContent: some View {
        VStack(spacing: 12) {
            // Recessed Plate 1: Size Picker
            recessedPlate(title: "Kích thước cửa sổ nổi mặc định") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chọn độ phân giải và tỷ lệ hiển thị ưa thích cho cửa sổ nổi khi tách khỏi giao diện chính.")
                        .font(.system(size: 11.5))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    
                    LiquidGlassSegmentedSizePicker()
                }
            }
            
            // Recessed Plate 2: Automations
            recessedPlate(title: "Tự động hóa thông minh") {
                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tự động chuyển PiP khi chuyển app")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            Text("Tự động bật cửa sổ nổi khi bạn bấm sang ứng dụng khác làm việc")
                                .font(.system(size: 11))
                                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        }
                        Spacer()
                        LiquidGlassLuxurySwitch(isOn: $playerManager.autoPiPOnAppSwitch)
                    }
                    
                    Divider()
                        .opacity(isDark ? 0.2 : 0.4)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tắt PiP khi bấm lại app chính")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            Text("Tự động thu hồi cửa sổ nổi về màn hình phát video khi quay lại AuraTube")
                                .font(.system(size: 11))
                                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        }
                        Spacer()
                        LiquidGlassLuxurySwitch(isOn: $playerManager.autoReturnPiPOnAppFocus)
                    }
                }
            }
        }
    }
    
    // MARK: - Tab 3: Updates & About Content
    @ViewBuilder
    private var updatesTabContent: some View {
        VStack(spacing: 12) {
            recessedPlate(title: "Cập nhật ứng dụng") {
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("AuraTube v\(updateService.currentVersion)")
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                
                                Text("Build \(updateService.currentBuild)")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                            }
                            
                            switch updateService.status {
                            case .checking:
                                Text("Đang kiểm tra bản cập nhật mới trên GitHub...")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(red: 0.08, green: 0.50, blue: 0.98))
                            case .available(let update):
                                Text("Có bản mới v\(update.version)! Sẵn sàng nâng cấp.")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.green)
                            case .upToDate:
                                Text("Bạn đang sử dụng phiên bản mới nhất.")
                                    .font(.system(size: 11))
                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                            case .error(let msg):
                                Text("Không thể kết nối: \(msg)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            default:
                                Text("Tự động kiểm tra bản cập nhật khi khởi chạy ứng dụng.")
                                    .font(.system(size: 11))
                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                            }
                        }
                        
                        Spacer()
                        
                        if updateService.isUpdateAvailable {
                            Button(action: {
                                updateService.showUpdateSheet = true
                            }) {
                                Text("Cập nhật ngay")
                                    .font(.system(size: 11.5, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(Color.green)
                                    )
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(action: {
                                updateService.scanForUpdates(isUserInitiated: true)
                            }) {
                                HStack(spacing: 4) {
                                    SpinningRefreshIcon(isSpinning: updateService.isScanning, size: 10)
                                    Text(updateService.isScanning ? "Đang quét..." : "Kiểm tra ngay")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.85))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 0.75)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(updateService.isScanning)
                        }
                    }
                }
            }
            
            recessedPlate(title: "Phím tắt thao tác nhanh") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 18) {
                        // Cột 1: Điều khiển phát & Âm lượng
                        VStack(alignment: .leading, spacing: 6) {
                            shortcutRow(keys: ["Space", "K"], separator: "/", label: "Phát / Tạm dừng")
                            shortcutRow(keys: ["←", "→"], label: "Tua lùi / tới 10s")
                            shortcutRow(keys: ["↑", "↓"], label: "Tăng / Giảm âm")
                            shortcutRow(keys: ["M"], label: "Tắt / Bật tiếng (Mute)")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Cột 2: Cửa sổ & Điều hướng
                        VStack(alignment: .leading, spacing: 6) {
                            shortcutRow(keys: ["P"], label: "Bật / Tắt cửa sổ PiP")
                            shortcutRow(keys: ["F"], label: "Xem toàn màn hình")
                            shortcutRow(keys: ["⌘", "K"], label: "Mở thanh tìm kiếm")
                            shortcutRow(keys: ["⌘", ","], label: "Cài đặt ứng dụng")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Divider()
                        .opacity(isDark ? 0.16 : 0.3)
                        .padding(.vertical, 1)
                    
                    HStack {
                        Text("Phím số 0 – 9: Nhảy nhanh 0% – 90% video")
                            .font(.system(size: 10.5))
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme).opacity(0.75))
                        
                        Spacer()
                        
                        Text("Bản quyền © 2026 Tung Nguyen")
                            .font(.system(size: 10.5))
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme).opacity(0.65))
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func keyCap(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.9))
            .padding(.horizontal, 5.5)
            .padding(.vertical, 2)
            .frame(minWidth: 19)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        isDark ?
                            LinearGradient(
                                colors: [Color.white.opacity(0.16), Color.white.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ) :
                            LinearGradient(
                                colors: [Color.white, Color(white: 0.93)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(
                        isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.12),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: Color.black.opacity(isDark ? 0.25 : 0.08), radius: 1, x: 0, y: 1)
    }
    
    @ViewBuilder
    private func shortcutRow(keys: [String], separator: String? = nil, label: String) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                    if index > 0, let sep = separator {
                        Text(sep)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme).opacity(0.55))
                    }
                    keyCap(key)
                }
            }
            .frame(width: 74, alignment: .leading)
            
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                .lineLimit(1)
            
            Spacer(minLength: 0)
        }
    }
    
    // MARK: - Recessed Frosted Plate Component (ALG-DS Section 3.3)
    @ViewBuilder
    private func recessedPlate<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.85))
            
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.025))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
                    lineWidth: 0.75
                )
        )
    }
}
