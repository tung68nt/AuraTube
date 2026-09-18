import Foundation
import AppKit

public struct DownloadItem: Identifiable, Sendable {
    public let id: String
    public let videoId: String
    public let title: String
    public let thumbnail: String
    public let quality: String
    public let isAudioOnly: Bool
    public var progress: Double
    public var speed: String
    public var eta: String
    public var totalSize: String
    public var statusText: String
    public var isComplete: Bool
    public var isError: Bool
    public var errorMessage: String?
    public var destinationPath: String?
    public let createdAt: Date
    
    public init(
        id: String = UUID().uuidString,
        videoId: String,
        title: String,
        thumbnail: String = "",
        quality: String,
        isAudioOnly: Bool = false,
        progress: Double = 0,
        speed: String = "",
        eta: String = "",
        totalSize: String = "",
        statusText: String = "Đang khởi tạo...",
        isComplete: Bool = false,
        isError: Bool = false,
        errorMessage: String? = nil,
        destinationPath: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.videoId = videoId
        self.title = title
        self.thumbnail = thumbnail
        self.quality = quality
        self.isAudioOnly = isAudioOnly
        self.progress = progress
        self.speed = speed
        self.eta = eta
        self.totalSize = totalSize
        self.statusText = statusText
        self.isComplete = isComplete
        self.isError = isError
        self.errorMessage = errorMessage
        self.destinationPath = destinationPath
        self.createdAt = createdAt
    }
}

@MainActor
public final class DownloadManager: ObservableObject {
    public static let shared = DownloadManager()
    
    @Published public var downloads: [DownloadItem] = []
    @Published public var activeDownloadId: String? = nil
    @Published public var showToastHUD: Bool = false
    
    private var runningProcesses: [String: Process] = [:]
    
    public var downloadDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Downloads/YouTube_Adfree")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    public var hasActiveDownloads: Bool {
        downloads.contains(where: { !$0.isComplete && !$0.isError })
    }
    
    public var activeDownloadCount: Int {
        downloads.filter({ !$0.isComplete && !$0.isError }).count
    }
    
    public var latestDownload: DownloadItem? {
        if let activeId = activeDownloadId, let item = downloads.first(where: { $0.id == activeId }) {
            return item
        }
        return downloads.first
    }
    
    private var binaryPath: String {
        let candidates = [
            Bundle.main.resourcePath.map { "\($0)/bin/yt-dlp" } ?? "",
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ]
        for path in candidates where !path.isEmpty && FileManager.default.fileExists(atPath: path) {
            return path
        }
        return "/opt/homebrew/bin/yt-dlp"
    }
    
    private init() {}
    
    @discardableResult
    public func startDownload(video: Video, quality: String = "1080", isAudioOnly: Bool = false) -> String {
        let item = DownloadItem(
            videoId: video.id,
            title: video.title,
            thumbnail: video.thumbnail,
            quality: isAudioOnly ? "MP3 320k" : "\(quality)p MP4",
            isAudioOnly: isAudioOnly
        )
        downloads.insert(item, at: 0)
        let itemId = item.id
        
        self.activeDownloadId = itemId
        self.showToastHUD = true
        
        let ytdlp = self.binaryPath
        guard FileManager.default.fileExists(atPath: ytdlp) else {
            if let idx = downloads.firstIndex(where: { $0.id == itemId }) {
                downloads[idx].statusText = "Không tìm thấy yt-dlp"
                downloads[idx].isError = true
                downloads[idx].errorMessage = "Chưa cài đặt yt-dlp tại \(ytdlp)"
            }
            return itemId
        }
        
        let outTemplate = downloadDir.appendingPathComponent("%(title)s.%(ext)s").path
        
        var args = [
            "-o", outTemplate,
            "--no-playlist",
            "--newline",
            "--progress"
        ]
        
        if isAudioOnly {
            args += ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
        } else {
            args += [
                "-f", "bestvideo[height<=\(quality)][ext=mp4]+bestaudio[ext=m4a]/best[height<=\(quality)]/best",
                "--merge-output-format", "mp4"
            ]
        }
        args.append("https://www.youtube.com/watch?v=\(video.id)")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ytdlp)
            process.arguments = args
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            Task { @MainActor [weak self] in
                self?.runningProcesses[itemId] = process
            }
            
            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                    Task { @MainActor in
                        self?.parseProgress(str, forItemId: itemId)
                    }
                }
            }
            
            do {
                try process.run()
                process.waitUntilExit()
                
                Task { @MainActor in
                    self?.runningProcesses.removeValue(forKey: itemId)
                    if let idx = self?.downloads.firstIndex(where: { $0.id == itemId }) {
                        if process.terminationStatus == 0 {
                            self?.downloads[idx].progress = 1.0
                            self?.downloads[idx].statusText = "Hoàn tất ✓"
                            self?.downloads[idx].isComplete = true
                            self?.downloads[idx].isError = false
                            
                            // Fallback detect destination file if not already captured
                            if self?.downloads[idx].destinationPath == nil {
                                self?.downloads[idx].destinationPath = self?.findRecentFile(matching: self!.downloads[idx])
                            }
                            
                            self?.notifyCompletion(item: self!.downloads[idx])
                        } else {
                            if self?.downloads[idx].isError != true {
                                self?.downloads[idx].statusText = "Tải thất bại"
                                self?.downloads[idx].isError = true
                                self?.downloads[idx].errorMessage = "Mã lỗi exit code \(process.terminationStatus)"
                            }
                        }
                    }
                }
            } catch {
                Task { @MainActor in
                    self?.runningProcesses.removeValue(forKey: itemId)
                    if let idx = self?.downloads.firstIndex(where: { $0.id == itemId }) {
                        self?.downloads[idx].statusText = "Lỗi khởi chạy tiến trình"
                        self?.downloads[idx].isError = true
                        self?.downloads[idx].errorMessage = error.localizedDescription
                    }
                }
            }
        }
        
        return itemId
    }
    
    public func cancelDownload(id: String) {
        if let proc = runningProcesses[id] {
            proc.terminate()
            runningProcesses.removeValue(forKey: id)
        }
        if let idx = downloads.firstIndex(where: { $0.id == id }) {
            downloads[idx].statusText = "Đã hủy"
            downloads[idx].isError = true
            downloads[idx].errorMessage = "Người dùng đã hủy tác vụ"
        }
    }
    
    public func removeDownload(id: String) {
        cancelDownload(id: id)
        downloads.removeAll(where: { $0.id == id })
        if activeDownloadId == id {
            activeDownloadId = downloads.first(where: { !$0.isComplete && !$0.isError })?.id
            if activeDownloadId == nil {
                showToastHUD = false
            }
        }
    }
    
    public func clearCompleted() {
        downloads.removeAll(where: { $0.isComplete || $0.isError })
        if let activeId = activeDownloadId, !downloads.contains(where: { $0.id == activeId }) {
            activeDownloadId = nil
            showToastHUD = false
        }
    }
    
    private func parseProgress(_ output: String, forItemId id: String) {
        guard let idx = downloads.firstIndex(where: { $0.id == id }) else { return }
        
        // Destination detection
        if output.contains("Destination: ") {
            if let destRange = output.range(of: #"Destination:\s*(.+)$"#, options: .regularExpression) {
                let rawDest = String(output[destRange]).replacingOccurrences(of: "Destination:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !rawDest.isEmpty {
                    downloads[idx].destinationPath = rawDest
                }
            }
        } else if output.contains("Merging formats into ") {
            if let mergeRange = output.range(of: #"Merging formats into "([^"]+)""#, options: .regularExpression) {
                let raw = String(output[mergeRange])
                let clean = raw.replacingOccurrences(of: "Merging formats into \"", with: "").replacingOccurrences(of: "\"", with: "")
                downloads[idx].destinationPath = clean
            }
        } else if output.contains("has already been downloaded") {
            if let range = output.range(of: #"\[download\]\s*(.+?)\s*has already been downloaded"#, options: .regularExpression) {
                let raw = String(output[range])
                    .replacingOccurrences(of: "[download]", with: "")
                    .replacingOccurrences(of: "has already been downloaded", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !raw.isEmpty {
                    downloads[idx].destinationPath = raw
                }
            }
            downloads[idx].progress = 1.0
            downloads[idx].statusText = "Tệp đã có sẵn trên máy ✓"
            downloads[idx].isComplete = true
        }
        
        // Progress percentage detection: [download]  45.6% of 25.00MiB at 3.50MiB/s ETA 00:07
        if output.contains("[download]") {
            // Percent
            if let percentRange = output.range(of: #"\b\d+(\.\d+)?%"#, options: .regularExpression) {
                let percentStr = String(output[percentRange]).replacingOccurrences(of: "%", with: "")
                if let val = Double(percentStr) {
                    downloads[idx].progress = min(1.0, max(0.0, val / 100.0))
                }
            }
            
            // Total Size
            if let sizeRange = output.range(of: #"of\s+~?\s*([0-9.]+[kKMGT]?i?B)"#, options: .regularExpression) {
                let raw = String(output[sizeRange])
                downloads[idx].totalSize = raw.replacingOccurrences(of: "of", with: "").replacingOccurrences(of: "~", with: "").trimmingCharacters(in: .whitespaces)
            }
            
            // Speed
            if let speedRange = output.range(of: #"at\s+([0-9.]+[kKMGT]?i?B/s)"#, options: .regularExpression) {
                let raw = String(output[speedRange])
                downloads[idx].speed = raw.replacingOccurrences(of: "at", with: "").trimmingCharacters(in: .whitespaces)
            }
            
            // ETA
            if let etaRange = output.range(of: #"ETA\s+([0-9:]+)"#, options: .regularExpression) {
                let raw = String(output[etaRange])
                downloads[idx].eta = raw.replacingOccurrences(of: "ETA", with: "").trimmingCharacters(in: .whitespaces)
            }
            
            // Formulate human-readable status text
            var parts: [String] = []
            let pctInt = Int(downloads[idx].progress * 100)
            parts.append("Đang tải: \(pctInt)%")
            if !downloads[idx].speed.isEmpty {
                parts.append(downloads[idx].speed)
            }
            if !downloads[idx].eta.isEmpty {
                parts.append("còn \(downloads[idx].eta)")
            }
            downloads[idx].statusText = parts.joined(separator: " • ")
            
        } else if output.contains("[ExtractAudio]") {
            downloads[idx].statusText = "Đang trích xuất & chuyển đổi MP3 320k..."
        } else if output.contains("[Merger]") {
            downloads[idx].statusText = "Đang kết hợp video & âm thanh..."
        } else if output.contains("ERROR:") {
            downloads[idx].isError = true
            downloads[idx].statusText = "Lỗi tải về"
            downloads[idx].errorMessage = output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    private func findRecentFile(matching item: DownloadItem) -> String? {
        let dir = downloadDir
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return nil
        }
        
        let expectedExt = item.isAudioOnly ? "mp3" : "mp4"
        let filtered = files.filter { $0.pathExtension.lowercased() == expectedExt }
        
        // Sort by most recently modified
        let sorted = filtered.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            return date1 > date2
        }
        
        return sorted.first?.path
    }
    
    private func notifyCompletion(item: DownloadItem) {
        let notification = NSUserNotification()
        notification.title = "AuraTube: Tải về hoàn tất ✓"
        notification.informativeText = "\(item.title) (\(item.quality))"
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    public func openFileInFinder(for item: DownloadItem) {
        if let path = item.destinationPath, FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            return
        }
        
        if let fallbackPath = findRecentFile(matching: item), FileManager.default.fileExists(atPath: fallbackPath) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: fallbackPath)])
            return
        }
        
        openDownloadFolder()
    }
    
    public func openDownloadFolder() {
        NSWorkspace.shared.open(downloadDir)
    }
}
