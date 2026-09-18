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
    @StateObject private var vm = DownloadSheetViewModel()
    @ObservedObject private var downloadManager = DownloadManager.shared
    
    private var currentItem: DownloadItem? {
        if let id = vm.currentDownloadId {
            return downloadManager.downloads.first(where: { $0.id == id })
        }
        return nil
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(red: 0.35, green: 0.75, blue: 1.0))
                    Text(vm.isStarted ? "Tiến trình tải về" : "Tải phương tiện")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(white: 0.6))
                        .padding(6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            
            // Video Card Preview
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: video.thumbnail)) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        Color(white: 0.15)
                    }
                }
                .frame(width: 110, height: 62)
                .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text(video.uploader)
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(white: 0.65))
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.04))
            .cornerRadius(10)
            
            if !vm.isStarted {
                // MARK: - Configuration View (Pre-download)
                // Segment Video / Audio
                HStack(alignment: .center, spacing: 14) {
                    Text("Định dạng")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(white: 0.8))
                        .frame(width: 80, alignment: .leading)
                    
                    HStack(spacing: 8) {
                        // Video MP4 Button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                vm.isAudioOnly = false
                            }
                        }) {
                            HStack(spacing: 7) {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(!vm.isAudioOnly ? Color(red: 1.0, green: 0.28, blue: 0.35) : Color(white: 0.55))
                                Text("Video MP4")
                                    .font(.system(size: 12.5, weight: !vm.isAudioOnly ? .semibold : .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(
                                !vm.isAudioOnly ?
                                    Color.white.opacity(0.16) :
                                    Color.white.opacity(0.04)
                            )
                            .foregroundColor(!vm.isAudioOnly ? .white : Color(white: 0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(!vm.isAudioOnly ? Color.white.opacity(0.28) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .cornerRadius(8)
                            .shadow(color: !vm.isAudioOnly ? Color.black.opacity(0.25) : Color.clear, radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                        
                        // Audio MP3 Button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                vm.isAudioOnly = true
                            }
                        }) {
                            HStack(spacing: 7) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 12))
                                    .foregroundColor(vm.isAudioOnly ? Color(red: 0.35, green: 0.75, blue: 1.0) : Color(white: 0.55))
                                Text("Âm thanh MP3")
                                    .font(.system(size: 12.5, weight: vm.isAudioOnly ? .semibold : .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(
                                vm.isAudioOnly ?
                                    Color.white.opacity(0.16) :
                                    Color.white.opacity(0.04)
                            )
                            .foregroundColor(vm.isAudioOnly ? .white : Color(white: 0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(vm.isAudioOnly ? Color.white.opacity(0.28) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .cornerRadius(8)
                            .shadow(color: vm.isAudioOnly ? Color.black.opacity(0.25) : Color.clear, radius: 3, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                if !vm.isAudioOnly {
                    HStack(alignment: .center, spacing: 14) {
                        Text("Chất lượng")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(white: 0.8))
                            .frame(width: 80, alignment: .leading)
                        
                        HStack(spacing: 6) {
                            ForEach(["1080", "720", "480", "360"], id: \.self) { q in
                                Button(action: { vm.selectedTier = q }) {
                                    Text("\(q)p")
                                        .font(.system(size: 12, weight: vm.selectedTier == q ? .semibold : .medium))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 28)
                                        .background(vm.selectedTier == q ? Color.white : Color.white.opacity(0.06))
                                        .foregroundColor(vm.selectedTier == q ? Color.black : Color(white: 0.85))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(vm.selectedTier == q ? Color.white : Color.white.opacity(0.08), lineWidth: 1)
                                        )
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: 14) {
                        Text("Chất lượng")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(white: 0.8))
                            .frame(width: 80, alignment: .leading)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "music.note")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(Color(red: 0.35, green: 0.75, blue: 1.0))
                            Text("MP3 320 kbps (Chất lượng cao nhất)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(white: 0.9))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .cornerRadius(6)
                    }
                }
                
                // Submit Button
                Button(action: startDownload) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 14))
                        Text(vm.isAudioOnly ? "Bắt đầu tải Âm thanh MP3" : "Bắt đầu tải Video MP4 (\(vm.selectedTier)p)")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
            } else {
                // MARK: - Live Download Progress View
                VStack(alignment: .leading, spacing: 14) {
                    let item = currentItem
                    let isComplete = item?.isComplete == true
                    let isError = item?.isError == true
                    let progress = item?.progress ?? 0.0
                    let pctInt = Int(progress * 100)
                    
                    // Progress Header: Status text & Percentage
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
                                    .foregroundColor(Color(red: 0.35, green: 0.75, blue: 1.0))
                                    .font(.system(size: 14, weight: .bold))
                                Text(item?.statusText.isEmpty == false ? item!.statusText : "Đang kết nối & tải...")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color(white: 0.9))
                                    .lineLimit(1)
                            }
                        }
                        
                        Spacer()
                        
                        Text("\(pctInt)%")
                            .font(.system(size: 16, weight: .heavy, design: .monospaced))
                            .foregroundColor(isComplete ? .green : (isError ? Color(red: 1.0, green: 0.35, blue: 0.35) : Color(red: 0.35, green: 0.75, blue: 1.0)))
                    }
                    
                    // Progress Bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.1))
                            
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    isComplete ?
                                        LinearGradient(colors: [Color.green, Color(red: 0.2, green: 0.85, blue: 0.4)], startPoint: .leading, endPoint: .trailing) :
                                    isError ?
                                        LinearGradient(colors: [Color.red, Color.orange], startPoint: .leading, endPoint: .trailing) :
                                        LinearGradient(colors: [Color(red: 0.1, green: 0.6, blue: 1.0), Color(red: 0.4, green: 0.85, blue: 1.0)], startPoint: .leading, endPoint: .trailing)
                                )
                                .frame(width: max(8, geo.size.width * CGFloat(min(1.0, max(0.0, progress)))))
                                .animation(.linear(duration: 0.25), value: progress)
                        }
                    }
                    .frame(height: 8)
                    
                    // Download Metrics (Speed, Size, ETA)
                    HStack(spacing: 12) {
                        if let speed = item?.speed, !speed.isEmpty {
                            Label(speed, systemImage: "bolt.fill")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(Color(white: 0.7))
                        }
                        
                        if let size = item?.totalSize, !size.isEmpty {
                            Label(size, systemImage: "internaldrive")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(Color(white: 0.7))
                        }
                        
                        if let eta = item?.eta, !eta.isEmpty {
                            Label("Còn \(eta)", systemImage: "clock")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(Color(white: 0.7))
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
                            .background(Color.red.opacity(0.12))
                            .cornerRadius(6)
                    }
                    
                    // Actions Bar
                    HStack(spacing: 10) {
                        if isComplete {
                            Button(action: {
                                if let item = item {
                                    downloadManager.openFileInFinder(for: item)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.fill")
                                    Text("Mở tệp trong Finder")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { dismiss() }) {
                                Text("Đóng")
                                    .font(.system(size: 13, weight: .medium))
                                    .frame(width: 90)
                                    .frame(height: 36)
                                    .background(Color.white.opacity(0.1))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        } else if isError {
                            Button(action: {
                                vm.isStarted = false
                                vm.currentDownloadId = nil
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Thử tải lại")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(Color.white.opacity(0.15))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { dismiss() }) {
                                Text("Đóng")
                                    .font(.system(size: 13, weight: .medium))
                                    .frame(width: 90)
                                    .frame(height: 36)
                                    .background(Color.white.opacity(0.08))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(action: { dismiss() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down.to.line.compact")
                                    Text("Tải trong nền (Ẩn popup)")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(Color.white)
                                .foregroundColor(.black)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            
                            if let id = vm.currentDownloadId {
                                Button(action: {
                                    downloadManager.cancelDownload(id: id)
                                }) {
                                    Text("Hủy")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.45))
                                        .frame(width: 70)
                                        .frame(height: 36)
                                        .background(Color.red.opacity(0.12))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(14)
                .background(Color.white.opacity(0.04))
                .cornerRadius(10)
            }
            
            // Footer: Folder link
            HStack {
                Text("Lưu tại: ~/Downloads/YouTube_Adfree")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.5))
                Spacer()
                Button(action: { DownloadManager.shared.openDownloadFolder() }) {
                    Text("Mở thư mục ↗")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(white: 0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .frame(width: 450)
        .background(Color(white: 0.12))
    }
    
    private func startDownload() {
        let id = DownloadManager.shared.startDownload(video: video, quality: vm.selectedTier, isAudioOnly: vm.isAudioOnly)
        vm.currentDownloadId = id
        withAnimation(.easeInOut(duration: 0.2)) {
            vm.isStarted = true
        }
    }
}
