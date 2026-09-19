import SwiftUI
import AppKit

@MainActor
final class DownloadSheetViewModel: ObservableObject {
    @Published var selectedTier = "1080"
    @Published var isAudioOnly = false
    @Published var isStarted = false
    @Published var currentDownloadId: String? = nil
}

public struct DownloadSheetView: View {
    let video: Video
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var vm = DownloadSheetViewModel()
    @ObservedObject private var downloadManager = DownloadManager.shared
    
    private var isDark: Bool {
        colorScheme == .dark
    }
    
    private var currentItem: DownloadItem? {
        if let id = vm.currentDownloadId {
            return downloadManager.downloads.first(where: { $0.id == id })
        }
        return nil
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            videoCardPreview
            if !vm.isStarted {
                configView
            } else {
                progressView
            }
            footerView
        }
        .padding(22)
        .frame(width: 460)
        .background(liquidGlassBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(liquidGlassBorder)
        .shadow(color: Color.black.opacity(isDark ? 0.42 : 0.16), radius: 26, y: 12)
    }
    
    // MARK: - Header
    @ViewBuilder
    private var headerView: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 0.08, green: 0.50, blue: 0.98))
                Text(vm.isStarted ? "Tiến trình tải về" : "Tải phương tiện")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    )
                    .overlay(
                        Circle()
                            .stroke(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 0.75)
                    )
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Video Card Preview (Recessed Frosted Plate)
    @ViewBuilder
    private var videoCardPreview: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: video.thumbnail)) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 110, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 0.75)
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    .lineLimit(2)
                Text(video.uploader)
                    .font(.system(size: 11.5))
                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.75)
        )
    }
    
    // MARK: - Configuration View (Pre-download)
    @ViewBuilder
    private var configView: some View {
        VStack(spacing: 14) {
            // Segment Video / Audio
            HStack(alignment: .center, spacing: 14) {
                Text("Định dạng")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    .frame(width: 76, alignment: .leading)
                
                HStack(spacing: 8) {
                    formatButton(
                        title: "Video MP4",
                        icon: "video.fill",
                        iconColor: Color(red: 1.0, green: 0.28, blue: 0.35),
                        isSelected: !vm.isAudioOnly
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            vm.isAudioOnly = false
                        }
                    }
                    
                    formatButton(
                        title: "Âm thanh MP3",
                        icon: "waveform",
                        iconColor: Color(red: 0.08, green: 0.50, blue: 0.98),
                        isSelected: vm.isAudioOnly
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            vm.isAudioOnly = true
                        }
                    }
                }
            }
            
            // Quality Selector
            HStack(alignment: .center, spacing: 14) {
                Text("Chất lượng")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    .frame(width: 76, alignment: .leading)
                
                if !vm.isAudioOnly {
                    videoQualityButtons
                } else {
                    audioQualityBadge
                }
            }
            
            // Primary Download Button
            primaryDownloadButton
        }
    }
    
    @ViewBuilder
    private var videoQualityButtons: some View {
        HStack(spacing: 6) {
            ForEach(["1080", "720", "480", "360"], id: \.self) { q in
                qualityButton(tier: q)
            }
        }
    }
    
    @ViewBuilder
    private func qualityButton(tier: String) -> some View {
        let isSelected = vm.selectedTier == tier
        Button(action: {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                vm.selectedTier = tier
            }
        }) {
            Text("\(tier)p")
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            isSelected ?
                                (isDark ?
                                    LinearGradient(colors: [Color.white, Color(white: 0.90)], startPoint: .top, endPoint: .bottom) :
                                    LinearGradient(colors: [Color(white: 0.16), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)) :
                                (isDark ?
                                    LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom) :
                                    LinearGradient(colors: [Color.black.opacity(0.05), Color.black.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                        )
                )
                .foregroundColor(
                    isSelected ?
                        (isDark ? Color.black : Color.white) :
                        ThemeColor.textPrimary(for: colorScheme).opacity(0.85)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isSelected ?
                                (isDark ? Color.white.opacity(0.3) : Color.black.opacity(0.2)) :
                                (isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)),
                            lineWidth: 0.75
                        )
                )
                .shadow(color: isSelected ? Color.black.opacity(isDark ? 0.20 : 0.12) : Color.clear, radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var audioQualityBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(Color(red: 0.08, green: 0.50, blue: 0.98))
            Text("MP3 320 kbps (Chất lượng cao nhất)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.75)
        )
    }
    
    @ViewBuilder
    private var primaryDownloadButton: some View {
        Button(action: startDownload) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(vm.isAudioOnly ? "Bắt đầu tải Âm thanh MP3" : "Bắt đầu tải Video MP4 (\(vm.selectedTier)p)")
                    .font(.system(size: 13.5, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.40), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: Color(red: 0.08, green: 0.50, blue: 0.98).opacity(0.35), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Live Download Progress View
    @ViewBuilder
    private var progressView: some View {
        let item = currentItem
        let isComplete = item?.isComplete == true
        let isError = item?.isError == true
        let progress = item?.progress ?? 0.0
        let pctInt = Int(progress * 100)
        
        VStack(alignment: .leading, spacing: 14) {
            // Header: Status & Percentage
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    if isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 14, weight: .bold))
                        Text("Tải về hoàn tất")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundColor(.green)
                    } else if isError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.35))
                            .font(.system(size: 14, weight: .bold))
                        Text("Tải thất bại")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.35))
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(Color(red: 0.08, green: 0.50, blue: 0.98))
                            .font(.system(size: 14, weight: .bold))
                        Text(item?.statusText.isEmpty == false ? item!.statusText : "Đang kết nối & tải...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Text("\(pctInt)%")
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                    .foregroundColor(isComplete ? .green : (isError ? Color(red: 1.0, green: 0.35, blue: 0.35) : Color(red: 0.08, green: 0.50, blue: 0.98)))
            }
            
            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            isComplete ?
                                LinearGradient(colors: [Color.green, Color(red: 0.2, green: 0.85, blue: 0.4)], startPoint: .leading, endPoint: .trailing) :
                            isError ?
                                LinearGradient(colors: [Color.red, Color.orange], startPoint: .leading, endPoint: .trailing) :
                                LinearGradient(colors: [Color(red: 0.08, green: 0.50, blue: 0.98), Color(red: 0.35, green: 0.75, blue: 1.0)], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: max(8, geo.size.width * CGFloat(min(1.0, max(0.0, progress)))))
                        .animation(.linear(duration: 0.25), value: progress)
                }
            }
            .frame(height: 8)
            
            // Metrics
            HStack(spacing: 12) {
                if let speed = item?.speed, !speed.isEmpty {
                    Label(speed, systemImage: "bolt.fill")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                }
                if let size = item?.totalSize, !size.isEmpty {
                    Label(size, systemImage: "internaldrive")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                }
                if let eta = item?.eta, !eta.isEmpty {
                    Label("Còn \(eta)", systemImage: "clock")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                }
                Spacer()
            }
            .padding(.top, 2)
            
            if isError, let err = item?.errorMessage, !err.isEmpty {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(isDark ? 0.15 : 0.08))
                    .cornerRadius(6)
            }
            
            // Action Buttons
            HStack(spacing: 10) {
                if isComplete {
                    completeActions(item: item)
                } else if isError {
                    errorActions
                } else {
                    inProgressActions
                }
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.75)
        )
    }
    
    @ViewBuilder
    private func completeActions(item: DownloadItem?) -> some View {
        Button(action: {
            if let item = item {
                downloadManager.openFileInFinder(for: item)
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                Text("Mở tệp trong Finder")
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [Color.green, Color(red: 0.16, green: 0.70, blue: 0.32)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75)
            )
            .shadow(color: Color.green.opacity(0.3), radius: 4, y: 1.5)
        }
        .buttonStyle(.plain)
        
        glassDismissButton(title: "Đóng", width: 80)
    }
    
    @ViewBuilder
    private var errorActions: some View {
        Button(action: {
            vm.isStarted = false
            vm.currentDownloadId = nil
        }) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                Text("Thử tải lại")
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.12), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        
        glassDismissButton(title: "Đóng", width: 80)
    }
    
    @ViewBuilder
    private var inProgressActions: some View {
        Button(action: { dismiss() }) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.to.line.compact")
                Text("Tải trong nền (Ẩn popup)")
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.10), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        
        if let id = vm.currentDownloadId {
            Button(action: {
                downloadManager.cancelDownload(id: id)
            }) {
                Text("Hủy")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.35))
                    .frame(width: 65)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.red.opacity(isDark ? 0.15 : 0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.red.opacity(isDark ? 0.25 : 0.15), lineWidth: 0.75)
                    )
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    private func glassDismissButton(title: String, width: CGFloat) -> some View {
        Button(action: { dismiss() }) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.85))
                .frame(width: width)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.10), lineWidth: 0.75)
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Footer: Folder Link
    @ViewBuilder
    private var footerView: some View {
        HStack {
            Text("Lưu tại: ~/Downloads/YouTube_Adfree")
                .font(.system(size: 11))
                .foregroundColor(ThemeColor.textSecondary(for: colorScheme).opacity(0.75))
            Spacer()
            Button(action: { DownloadManager.shared.openDownloadFolder() }) {
                HStack(spacing: 3) {
                    Text("Mở thư mục")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.85))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Liquid Glass Background & Border
    @ViewBuilder
    private var liquidGlassBackground: some View {
        ZStack {
            // 1. Hardware Optical Blur
            VisualEffectBackground(material: .popover, blendingMode: .behindWindow, state: .active)
            
            // 2. Translucent Optical Glass Tint
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
    }
    
    @ViewBuilder
    private var liquidGlassBorder: some View {
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
    }
    
    // MARK: - Format Button Helper
    @ViewBuilder
    private func formatButton(
        title: String,
        icon: String,
        iconColor: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? iconColor : ThemeColor.textSecondary(for: colorScheme).opacity(0.7))
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected ?
                            (isDark ?
                                LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.10)], startPoint: .top, endPoint: .bottom) :
                                LinearGradient(colors: [Color.white.opacity(0.95), Color(white: 0.90)], startPoint: .top, endPoint: .bottom)) :
                            (isDark ?
                                LinearGradient(colors: [Color.white.opacity(0.04), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom) :
                                LinearGradient(colors: [Color.black.opacity(0.04), Color.black.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    )
            )
            .foregroundColor(
                isSelected ?
                    (isDark ? Color.white : Color.black) :
                    ThemeColor.textSecondary(for: colorScheme)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected ?
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isDark ? 0.35 : 0.85),
                                    Color.white.opacity(isDark ? 0.10 : 0.30)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ) :
                            LinearGradient(
                                colors: [
                                    isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: isSelected ? Color.black.opacity(isDark ? 0.22 : 0.10) : Color.clear, radius: 4, y: 1.5)
        }
        .buttonStyle(.plain)
    }
    
    private func startDownload() {
        let id = DownloadManager.shared.startDownload(video: video, quality: vm.selectedTier, isAudioOnly: vm.isAudioOnly)
        vm.currentDownloadId = id
        withAnimation(.easeInOut(duration: 0.2)) {
            vm.isStarted = true
        }
    }
}
