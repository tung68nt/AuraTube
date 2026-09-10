import SwiftUI
import AppKit

@MainActor
final class DownloadSheetViewModel: ObservableObject {
    @Published var selectedTier = "1080"
    @Published var isAudioOnly = false
    @Published var isStarted = false
}

public struct DownloadSheetView: View {
    let video: Video
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = DownloadSheetViewModel()
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                Text("Tải phương tiện")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
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
                .frame(width: 120, height: 68)
                .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text(video.uploader)
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.65))
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.04))
            .cornerRadius(10)
            
            // Segment Video / Audio (Discrete modern macOS pill buttons)
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
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
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
                    Image(systemName: vm.isStarted ? "checkmark" : "arrow.down.circle.fill")
                        .font(.system(size: 14))
                    Text(vm.isStarted ? "Đã thêm vào hàng đợi tải về!" : (vm.isAudioOnly ? "Tải xuống Âm thanh MP3" : "Tải xuống Video MP4 (\(vm.selectedTier)p)"))
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(vm.isStarted ? Color.green : Color.white)
                .foregroundColor(vm.isStarted ? .white : .black)
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(vm.isStarted)
            
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
        .frame(width: 440)
        .background(Color(white: 0.12))
    }
    
    private func startDownload() {
        DownloadManager.shared.startDownload(video: video, quality: vm.selectedTier, isAudioOnly: vm.isAudioOnly)
        vm.isStarted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            dismiss()
        }
    }
}
