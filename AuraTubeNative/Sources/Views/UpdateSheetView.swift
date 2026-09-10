import SwiftUI
import AppKit

public struct UpdateSheetView: View {
    @ObservedObject private var updateService = UpdateService.shared
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 10) {
                YouTubeBrandBadge(width: 26)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cập Nhật Ứng Dụng")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text("AuraTube cho macOS")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.6))
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color(white: 0.4))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)
            .background(Color.white.opacity(0.03))
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            // Content Body based on status
            VStack(spacing: 18) {
                switch updateService.status {
                case .checking:
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
                case .idle:
                    checkingView
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            // Footer: Auto-check toggle & App info
            HStack {
                Toggle("Tự động kiểm tra bản mới khi mở app", isOn: $updateService.autoCheckEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(white: 0.7))
                
                Spacer()
                
                Text("v\(updateService.currentVersion)")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Color(white: 0.45))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.02))
        }
        .frame(width: 480, height: 380)
        .background(Color(white: 0.11))
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Status Subviews
    
    private var checkingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Đang kiểm tra bản cập nhật mới...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(white: 0.9))
            Text("Phiên bản hiện tại: v\(updateService.currentVersion)")
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.5))
            Spacer()
        }
    }
    
    private func upToDateView(version: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 58, height: 58)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.green)
            }
            
            Text("AuraTube đã là phiên bản mới nhất")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            Text("Bạn đang trải nghiệm phiên bản v\(version) mượt mà nhất.")
                .font(.system(size: 12.5))
                .foregroundColor(Color(white: 0.65))
                .multilineTextAlignment(.center)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Text("Đóng")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 100, height: 32)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func availableView(update: AppUpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles")
                        .font(.system(size: 20))
                        .foregroundColor(.cyan)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Có phiên bản mới:")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(white: 0.85))
                        Text("v\(update.version)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.3))
                            .cornerRadius(4)
                    }
                    
                    if let size = update.fileSize {
                        Text("Dung lượng: \(size)")
                            .font(.system(size: 11.5))
                            .foregroundColor(Color(white: 0.5))
                    }
                }
            }
            
            // Release Notes Box
            VStack(alignment: .leading, spacing: 6) {
                Text("Nhật ký cập nhật:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(white: 0.75))
                
                ScrollView {
                    Text(update.releaseNotes.isEmpty ? "• Cải thiện hiệu năng và độ ổn định phát video.\n• Sửa một số lỗi giao diện và đồng bộ." : update.releaseNotes)
                        .font(.system(size: 12))
                        .lineSpacing(4)
                        .foregroundColor(Color(white: 0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 110)
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            
            Spacer(minLength: 0)
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Text("Để sau")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                        .foregroundColor(Color(white: 0.8))
                }
                .buttonStyle(.plain)
                
                Button(action: { updateService.startDownload(update: update) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Cập nhật ngay")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Color(red: 0.1, green: 0.5, blue: 1.0))
                    .cornerRadius(8)
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func downloadingView(progress: Double, written: Int64, total: Int64) -> some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 38))
                .foregroundColor(.cyan)
            
            Text("Đang tải bản cập nhật mới...")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            
            VStack(spacing: 6) {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                
                HStack {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.cyan)
                    Spacer()
                    if total > 0 {
                        Text("\(ByteCountFormatter.string(fromByteCount: written, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                            .font(.system(size: 11.5))
                            .foregroundColor(Color(white: 0.5))
                    }
                }
            }
            
            Spacer()
            
            Button(action: { updateService.cancelDownload() }) {
                Text("Hủy tải")
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: 90, height: 28)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                    .foregroundColor(Color(white: 0.75))
            }
            .buttonStyle(.plain)
        }
    }
    
    private func readyToInstallView(zipUrl: URL, update: AppUpdateInfo) -> some View {
        VStack(spacing: 16) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 58, height: 58)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.blue)
            }
            
            Text("Bản cập nhật đã sẵn sàng!")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            Text("AuraTube v\(update.version) đã được tải xuống hoàn tất. Bấm nút bên dưới để cài đặt và khởi động lại ứng dụng.")
                .font(.system(size: 12.5))
                .foregroundColor(Color(white: 0.65))
                .multilineTextAlignment(.center)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Text("Để sau")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                        .foregroundColor(Color(white: 0.8))
                }
                .buttonStyle(.plain)
                
                Button(action: { updateService.installAndRelaunch(zipUrl: zipUrl) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Cài đặt & Khởi động lại")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Color.green)
                    .cornerRadius(8)
                    .foregroundColor(.black)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var installingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Đang cài đặt và khởi động lại AuraTube...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
            Text("Ứng dụng sẽ tự động mở lại trong giây lát.")
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.5))
            Spacer()
        }
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundColor(.yellow)
            
            Text("Không thể kiểm tra cập nhật")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            
            Text(message)
                .font(.system(size: 12.5))
                .foregroundColor(Color(white: 0.65))
                .multilineTextAlignment(.center)
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Text("Đóng")
                        .font(.system(size: 13))
                        .frame(width: 90, height: 32)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                        .foregroundColor(Color(white: 0.8))
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    if let url = URL(string: "https://github.com/tung68nt/AuraTube/releases") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("Tải từ GitHub")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 100, height: 32)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                Button(action: { updateService.checkForUpdates(isUserInitiated: true) }) {
                    Text("Thử lại")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 80, height: 32)
                        .background(Color.blue)
                        .cornerRadius(8)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
