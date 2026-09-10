import Foundation
import AppKit

public struct DownloadItem: Identifiable, Sendable {
    public let id: String
    public let videoId: String
    public let title: String
    public let quality: String
    public var progress: Double
    public var statusText: String
    public var isComplete: Bool
    
    public init(id: String = UUID().uuidString, videoId: String, title: String, quality: String, progress: Double = 0, statusText: String = "Đang bắt đầu...", isComplete: Bool = false) {
        self.id = id
        self.videoId = videoId
        self.title = title
        self.quality = quality
        self.progress = progress
        self.statusText = statusText
        self.isComplete = isComplete
    }
}

@MainActor
public final class DownloadManager: ObservableObject {
    public static let shared = DownloadManager()
    
    @Published public var downloads: [DownloadItem] = []
    
    public var downloadDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Downloads/YouTube_Adfree")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private init() {}
    
    public func startDownload(video: Video, quality: String = "1080", isAudioOnly: Bool = false) {
        let item = DownloadItem(
            videoId: video.id,
            title: video.title,
            quality: isAudioOnly ? "Audio MP3" : "\(quality)p MP4"
        )
        downloads.insert(item, at: 0)
        let itemId = item.id
        
        let outTemplate = downloadDir.appendingPathComponent("%(title)s.%(ext)s").path
        let ytdlp = "/opt/homebrew/bin/yt-dlp"
        
        var args = [
            "-o", outTemplate,
            "--no-playlist",
            "--newline"
        ]
        
        if isAudioOnly {
            args += ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
        } else {
            args += ["-f", "bestvideo[height<=\(quality)][ext=mp4]+bestaudio[ext=m4a]/best[height<=\(quality)]/best", "--merge-output-format", "mp4"]
        }
        args.append("https://www.youtube.com/watch?v=\(video.id)")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ytdlp)
            process.arguments = args
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                if let str = String(data: data, encoding: .utf8) {
                    Task { @MainActor in
                        self?.parseProgress(str, forItemId: itemId)
                    }
                }
            }
            
            do {
                try process.run()
                process.waitUntilExit()
                
                Task { @MainActor in
                    if let idx = self?.downloads.firstIndex(where: { $0.id == itemId }) {
                        self?.downloads[idx].progress = 1.0
                        self?.downloads[idx].statusText = "Hoàn thành ✓"
                        self?.downloads[idx].isComplete = true
                    }
                }
            } catch {
                Task { @MainActor in
                    if let idx = self?.downloads.firstIndex(where: { $0.id == itemId }) {
                        self?.downloads[idx].statusText = "Lỗi tải về"
                    }
                }
            }
        }
    }
    
    private func parseProgress(_ output: String, forItemId id: String) {
        guard let idx = downloads.firstIndex(where: { $0.id == id }) else { return }
        
        // Match [download]  45.6% of 25.00MiB at 3.50MiB/s
        if output.contains("[download]") {
            if let percentRange = output.range(of: #"\b\d+(\.\d+)?%"#, options: .regularExpression) {
                let percentStr = String(output[percentRange]).replacingOccurrences(of: "%", with: "")
                if let val = Double(percentStr) {
                    downloads[idx].progress = val / 100.0
                    downloads[idx].statusText = "Đang tải: \(Int(val))%"
                }
            }
        } else if output.contains("[Merger]") || output.contains("[ExtractAudio]") {
            downloads[idx].statusText = "Đang xử lý xuất file..."
        }
    }
    
    public func openDownloadFolder() {
        NSWorkspace.shared.open(downloadDir)
    }
}
