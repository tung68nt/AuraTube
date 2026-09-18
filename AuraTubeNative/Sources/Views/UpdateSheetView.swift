import SwiftUI
import AppKit

public struct UpdateSheetView: View {
    @ObservedObject private var updateService = UpdateService.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
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
            switch updateService.status {
            case .checking, .idle:
                checkingView
            case .upToDate(let version):
                upToDateView(version: version)
            case .available(let update):
                availableView(update: update)
            case .downloading(let progress, let written, let total):
                downloadingView(progress: progress, written: written, total: total)
            case .readyToInstall(let zipUrl, let update):
                readyToInstallView(zipUrl: zipUrl, update: update)
            case .installing:
                installingView
            case .error(let message):
                errorView(message: message)
            }
        }
        .padding(24)
        .frame(width: 540)
        .background(
            ZStack {
                // 1. Native macOS Window Vibrancy Base
                VisualEffectBackground(material: .popover, blendingMode: .behindWindow, state: .active)
                
                // 2. Liquid Glass Translucent Tint
                if isDark {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 32/255, green: 34/255, blue: 40/255).opacity(0.65),
                                    Color(red: 22/255, green: 23/255, blue: 28/255).opacity(0.72)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.75),
                                    Color(red: 248/255, green: 249/255, blue: 252/255).opacity(0.78)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                
                // 3. Specular Light Sheen (Top reflection)
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
            // Specular Rim Hairline
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
    
    // MARK: - App Icon View
    @ViewBuilder
    private var iconView: some View {
        VStack {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(isDark ? 0.25 : 0.45), lineWidth: 0.75)
                    )
                    .shadow(color: Color.black.opacity(isDark ? 0.45 : 0.18), radius: 8, y: 4)
            }
            Spacer()
        }
        .frame(width: 64)
        .padding(.top, 4)
    }
    
    // MARK: - 1. Available View (Apple HIG Native Software Update)
    private func availableView(update: AppUpdateInfo) -> some View {
        HStack(alignment: .top, spacing: 20) {
            iconView
            
            VStack(alignment: .leading, spacing: 14) {
                // Header Titles
                VStack(alignment: .leading, spacing: 4) {
                    Text("Có bản cập nhật mới cho AuraTube")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    
                    Text("AuraTube v\(update.version) hiện đã sẵn sàng tải về. Bạn đang sử dụng phiên bản v\(updateService.currentVersion).")
                        .font(.system(size: 12.5))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        .lineSpacing(2)
                }
                
                // Release Notes Label
                Text("Nội dung cập nhật:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.85))
                
                // Recessed Frosted Glass Plate for Release Notes
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        let lines = update.releaseNotes.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        ForEach(lines.indices, id: \.self) { idx in
                            let line = lines[idx]
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(isDark ? Color.white.opacity(0.40) : Color.black.opacity(0.35))
                                
                                let cleaned = line.replacingOccurrences(of: "^[•\\-\\s]+", with: "", options: .regularExpression)
                                Text(cleaned)
                                    .font(.system(size: 12))
                                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.92))
                                    .lineSpacing(2.5)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.08), lineWidth: 0.75)
                )
                
                // Bottom Row: Auto-check toggle & macOS Standard Action Buttons
                HStack(alignment: .center) {
                    Toggle("Tự động kiểm tra bản cập nhật", isOn: $updateService.autoCheckEnabled)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    
                    Spacer()
                    
                    // Secondary Button: "Để sau"
                    Button(action: { dismiss() }) {
                        Text("Để sau")
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            .fixedSize()
                            .padding(.horizontal, 14)
                            .frame(height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.12), lineWidth: 0.75)
                            )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    
                    // Primary Button: "Cập nhật ngay"
                    Button(action: { updateService.startDownload(update: update) }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Cập nhật ngay")
                                .font(.system(size: 12.5, weight: .semibold))
                                .fixedSize()
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 26)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(red: 0.05, green: 0.48, blue: 0.98))
                                
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.35), Color.clear],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 0.75
                                    )
                            }
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
        }
    }
    
    // MARK: - 2. Checking View
    private var checkingView: some View {
        HStack(alignment: .top, spacing: 20) {
            iconView
            
            VStack(alignment: .leading, spacing: 14) {
                Text("Đang kiểm tra bản cập nhật mới...")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                
                Text("AuraTube đang kết nối tới máy chủ cập nhật để kiểm tra các cải tiến mới nhất.")
                    .font(.system(size: 12.5))
                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    .lineSpacing(2)
                
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Phiên bản hiện tại: v\(updateService.currentVersion)")
                        .font(.system(size: 12))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                }
                .padding(.vertical, 8)
                
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Text("Hủy")
                            .font(.system(size: 12.5))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            .fixedSize()
                            .padding(.horizontal, 14)
                            .frame(height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.12), lineWidth: 0.75)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - 3. Up To Date View
    private func upToDateView(version: String) -> some View {
        HStack(alignment: .top, spacing: 20) {
            iconView
            
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(red: 0.12, green: 0.65, blue: 0.25))
                        .font(.system(size: 15))
                    Text("AuraTube đã là phiên bản mới nhất")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                }
                
                Text("Bạn đang trải nghiệm phiên bản v\(version) mượt mà nhất với đầy đủ tính năng tối ưu theo chuẩn Apple HIG.")
                    .font(.system(size: 12.5))
                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    .lineSpacing(2)
                
                HStack {
                    Toggle("Tự động kiểm tra bản cập nhật", isOn: $updateService.autoCheckEnabled)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Text("Đóng")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            .fixedSize()
                            .padding(.horizontal, 16)
                            .frame(height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.14), lineWidth: 0.75)
                            )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 6)
            }
        }
    }
    
    // MARK: - 4. Downloading View
    private func downloadingView(progress: Double, written: Int64, total: Int64) -> some View {
        HStack(alignment: .top, spacing: 20) {
            iconView
            
            VStack(alignment: .leading, spacing: 14) {
                Text("Đang tải bản cập nhật AuraTube...")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(.linear)
                    
                    HStack {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(isDark ? .cyan : Color(red: 0.05, green: 0.45, blue: 0.90))
                        
                        Spacer()
                        
                        if total > 0 {
                            Text("\(ByteCountFormatter.string(fromByteCount: written, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                                .font(.system(size: 11))
                                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        }
                    }
                }
                .padding(.vertical, 4)
                
                HStack {
                    Spacer()
                    Button(action: { updateService.cancelDownload() }) {
                        Text("Hủy tải")
                            .font(.system(size: 12.5))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            .fixedSize()
                            .padding(.horizontal, 14)
                            .frame(height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.12), lineWidth: 0.75)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - 5. Ready To Install View
    private func readyToInstallView(zipUrl: URL, update: AppUpdateInfo) -> some View {
        HStack(alignment: .top, spacing: 20) {
            iconView
            
            VStack(alignment: .leading, spacing: 14) {
                Text("Bản cập nhật đã sẵn sàng cài đặt!")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                
                Text("AuraTube v\(update.version) đã được tải xuống và kiểm tra tính toàn vẹn. Hãy cài đặt và khởi động lại ứng dụng.")
                    .font(.system(size: 12.5))
                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    .lineSpacing(2)
                
                HStack(alignment: .center) {
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Text("Để sau")
                            .font(.system(size: 12.5))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            .fixedSize()
                            .padding(.horizontal, 14)
                            .frame(height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.12), lineWidth: 0.75)
                            )
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { updateService.installAndRelaunch(zipUrl: zipUrl) }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .bold))
                            Text("Cài đặt & Khởi động lại")
                                .font(.system(size: 12.5, weight: .semibold))
                                .fixedSize()
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 26)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(red: 0.10, green: 0.65, blue: 0.30))
                                
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75)
                            }
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 6)
            }
        }
    }
    
    // MARK: - 6. Installing View
    private var installingView: some View {
        HStack(alignment: .top, spacing: 20) {
            iconView
            
            VStack(alignment: .leading, spacing: 14) {
                Text("Đang cài đặt và khởi động lại...")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                
                Text("AuraTube đang được cập nhật và sẽ tự khởi động lại trong giây lát.")
                    .font(.system(size: 12.5))
                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    .lineSpacing(2)
                
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Đang giải nén và thay thế phiên bản...")
                        .font(.system(size: 12))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                }
                .padding(.vertical, 8)
            }
        }
    }
    
    // MARK: - 7. Error View
    private func errorView(message: String) -> some View {
        HStack(alignment: .top, spacing: 20) {
            iconView
            
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 15))
                    Text("Không thể kiểm tra cập nhật")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                }
                
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    .lineSpacing(2)
                
                HStack {
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Text("Đóng")
                            .font(.system(size: 12.5))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            .fixedSize()
                            .padding(.horizontal, 14)
                            .frame(height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.12), lineWidth: 0.75)
                            )
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { updateService.checkForUpdates(isUserInitiated: true) }) {
                        Text("Thử lại")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.white)
                            .fixedSize()
                            .padding(.horizontal, 14)
                            .frame(height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.blue)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
            }
        }
    }
}
