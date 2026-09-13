import Foundation
import AppKit

@MainActor
public final class UpdateService: NSObject, ObservableObject, @preconcurrency URLSessionDownloadDelegate {
    public static let shared = UpdateService()
    
    // Remote update endpoints (supports raw JSON manifest or GitHub release API)
    public var updateFeedUrl: URL = URL(string: "https://raw.githubusercontent.com/tung68nt/AuraTube/main/version.json")!
    public var githubReleaseUrl: URL = URL(string: "https://api.github.com/repos/tung68nt/AuraTube/releases/latest")!
    
    @Published public var status: UpdateStatus = .idle
    @Published public var showUpdateSheet: Bool = false
    @Published public var latestUpdate: AppUpdateInfo? = nil
    @Published public var isScanning: Bool = false
    @Published public var scanFeedbackMessage: String? = nil
    @Published public var isUpdateAvailable: Bool = false
    @Published public var showUpdateBanner: Bool = false
    @Published public var hasDismissedBanner: Bool = false
    @Published public var autoCheckEnabled: Bool = (UserDefaults.standard.object(forKey: "auratube_autocheck_update") as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(autoCheckEnabled, forKey: "auratube_autocheck_update")
        }
    }
    
    private var downloadTask: URLSessionDownloadTask?
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        return URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
    }()
    
    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.6"
    }
    
    public var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "7"
    }
    
    private override init() {
        super.init()
    }
    
    // MARK: - Scan & Check For Updates
    
    public func scanForUpdates(isUserInitiated: Bool = true) {
        self.isScanning = true
        self.scanFeedbackMessage = nil
        
        Task {
            // Small tactile delay when user clicks so the scan feedback feels tangible
            if isUserInitiated {
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
            
            if let update = await fetchLatestVersionInfo() {
                self.latestUpdate = update
                if isVersion(update.version, higherThan: currentVersion) {
                    self.isUpdateAvailable = true
                    self.showUpdateBanner = true
                    self.hasDismissedBanner = false
                    self.status = .available(update)
                    if isUserInitiated {
                        self.showUpdateSheet = true
                    }
                } else {
                    self.isUpdateAvailable = false
                    self.showUpdateBanner = false
                    self.status = .upToDate(currentVersion: currentVersion)
                    if isUserInitiated {
                        self.scanFeedbackMessage = "Bạn đang dùng AuraTube v\(currentVersion) mới nhất! Trải nghiệm âm thanh và video đã được tối ưu hoàn toàn."
                        scheduleDismissFeedback()
                    }
                }
            } else {
                self.status = .error(message: "Không thể kết nối máy chủ cập nhật. Vui lòng kiểm tra lại kết nối mạng.")
                if isUserInitiated {
                    self.scanFeedbackMessage = "Không thể kết nối máy chủ cập nhật. Vui lòng kiểm tra lại kết nối mạng."
                    scheduleDismissFeedback()
                }
            }
            self.isScanning = false
        }
    }
    
    private func scheduleDismissFeedback() {
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self.scanFeedbackMessage = nil
        }
    }
    
    public func checkForUpdates(isUserInitiated: Bool = false) {
        scanForUpdates(isUserInitiated: isUserInitiated)
    }
    
    // MARK: - Remote Version Fetcher
    
    private func fetchLatestVersionInfo() async -> AppUpdateInfo? {
        // Remote Attempt 1: Fetch custom version.json manifest from GitHub
        if let update = await fetchFromManifest(url: updateFeedUrl) {
            return update
        }
        
        // Remote Attempt 2: Fetch GitHub Release API
        if let update = await fetchFromGitHubReleases(url: githubReleaseUrl) {
            return update
        }
        
        #if DEBUG
        // Local developer fallback (only when network/server is unavailable during offline dev)
        let localPath = "/Users/tungnguyen/Code/Youtube/version.json"
        if let localData = try? Data(contentsOf: URL(fileURLWithPath: localPath)),
           let json = try? JSONSerialization.jsonObject(with: localData) as? [String: Any],
           let version = json["version"] as? String {
            return AppUpdateInfo(
                version: version,
                title: (json["title"] as? String) ?? "AuraTube v\(version)",
                releaseNotes: (json["releaseNotes"] as? String) ?? "",
                downloadUrl: json["downloadUrl"] as? String,
                publishedAt: json["publishedAt"] as? String,
                minOSVersion: json["minOSVersion"] as? String,
                fileSize: json["fileSize"] as? String
            )
        }
        #endif
        
        return nil
    }
    
    private func fetchFromManifest(url: URL) async -> AppUpdateInfo? {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 2.5
        
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String else {
            return nil
        }
        
        let title = (json["title"] as? String) ?? "AuraTube v\(version)"
        let notes = (json["releaseNotes"] as? String) ?? (json["changelog"] as? String) ?? ""
        let dl = json["downloadUrl"] as? String
        let pub = json["publishedAt"] as? String
        let minOS = json["minOSVersion"] as? String
        let size = json["fileSize"] as? String
        
        return AppUpdateInfo(
            version: version,
            title: title,
            releaseNotes: notes,
            downloadUrl: dl,
            publishedAt: pub,
            minOSVersion: minOS,
            fileSize: size
        )
    }
    
    private func fetchFromGitHubReleases(url: URL) async -> AppUpdateInfo? {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        req.setValue("AuraTube-AppUpdater", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 6.0
        
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String else {
            return nil
        }
        
        let rawVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let title = (json["name"] as? String) ?? "AuraTube v\(rawVersion)"
        let body = (json["body"] as? String) ?? ""
        let publishedAt = json["published_at"] as? String
        
        var downloadUrl: String? = nil
        var fileSizeStr: String? = nil
        if let assets = json["assets"] as? [[String: Any]] {
            for asset in assets {
                if let name = asset["name"] as? String,
                   (name.hasSuffix(".zip") || name.hasSuffix(".dmg") || name.hasSuffix(".tar.gz")),
                   let url = asset["browser_download_url"] as? String {
                    downloadUrl = url
                    if let bytes = asset["size"] as? Int64 {
                        fileSizeStr = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                    }
                    break
                }
            }
        }
        
        return AppUpdateInfo(
            version: rawVersion,
            title: title,
            releaseNotes: body,
            downloadUrl: downloadUrl,
            publishedAt: publishedAt,
            minOSVersion: "13.0",
            fileSize: fileSizeStr
        )
    }
    
    // MARK: - Semantic Version Comparison
    
    public func isVersion(_ v1: String, higherThan v2: String) -> Bool {
        let clean1 = v1.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).components(separatedBy: "-").first ?? v1
        let clean2 = v2.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).components(separatedBy: "-").first ?? v2
        
        let p1 = clean1.split(separator: ".").compactMap { Int($0) }
        let p2 = clean2.split(separator: ".").compactMap { Int($0) }
        
        let count = max(p1.count, p2.count)
        for i in 0..<count {
            let num1 = i < p1.count ? p1[i] : 0
            let num2 = i < p2.count ? p2[i] : 0
            if num1 > num2 { return true }
            if num1 < num2 { return false }
        }
        return false
    }
    
    // MARK: - Download & In-Place Update
    
    public func startDownload(update: AppUpdateInfo) {
        // Fast-path: If local DMG or ZIP exists, update instantly without slow network download
        let localCandidates = [
            "/Users/tungnguyen/Code/Youtube/AuraTube-v\(update.version).zip",
            "/Users/tungnguyen/Code/Youtube/AuraTube.zip",
            "/Users/tungnguyen/Code/Youtube/AuraTube-v\(update.version).dmg",
            "/Users/tungnguyen/Code/Youtube/AuraTube.dmg"
        ]
        for path in localCandidates {
            if FileManager.default.fileExists(atPath: path) {
                let localUrl = URL(fileURLWithPath: path)
                self.installAndRelaunch(zipUrl: localUrl)
                return
            }
        }
        
        guard let urlStr = update.downloadUrl, let url = URL(string: urlStr) else {
            if let webUrl = URL(string: "https://github.com/tung68nt/AuraTube/releases") {
                NSWorkspace.shared.open(webUrl)
            }
            return
        }
        
        self.status = .downloading(progress: 0.0, bytesWritten: 0, totalBytes: 0)
        let task = urlSession.downloadTask(with: url)
        self.downloadTask = task
        task.resume()
    }
    
    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        if let update = latestUpdate {
            self.status = .available(update)
        } else {
            self.status = .idle
        }
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
        self.status = .downloading(progress: progress, bytesWritten: totalBytesWritten, totalBytes: totalBytesExpectedToWrite)
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let update = latestUpdate else {
            self.status = .idle
            return
        }
        
        // Validate HTTP response code
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            self.status = .error(message: "Không thể tải bản cập nhật (Mã phản hồi: \(http.statusCode)). Bạn có thể tải file DMG trực tiếp từ trang phát hành.")
            return
        }
        
        // Validate file size (> 300KB) to prevent installing 404 text or truncated files
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int64) ?? 0
        guard fileSize > 300_000 else {
            self.status = .error(message: "File cập nhật không hợp lệ (Dung lượng \(fileSize) bytes). Vui lòng thử lại hoặc tải file DMG trực tiếp.")
            return
        }
        
        // Move downloaded archive to a safe persistent temporary location
        let tempDir = FileManager.default.temporaryDirectory
        let isDmg = update.downloadUrl?.lowercased().hasSuffix(".dmg") == true
        let ext = isDmg ? "dmg" : "zip"
        let destination = tempDir.appendingPathComponent("AuraTube_Update_\(update.version).\(ext)")
        
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            self.status = .readyToInstall(zipUrl: destination, update: update)
        } catch {
            self.status = .error(message: "Không thể lưu file cập nhật: \(error.localizedDescription)")
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let err = error as? URLError, err.code == .cancelled {
            return
        }
        if let err = error {
            self.status = .error(message: "Lỗi tải bản cập nhật: \(err.localizedDescription)")
        }
    }
    
    // MARK: - Installation & App Relaunch
    
    public func installAndRelaunch(zipUrl: URL) {
        self.status = .installing
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let currentAppPath = Bundle.main.bundlePath
        let targetApp = (currentAppPath.hasSuffix(".app") && !currentAppPath.contains("/Volumes/")) ? currentAppPath : "/Applications/AuraTube.app"
        
        let scriptContent = """
        #!/bin/bash
        TARGET_APP="\(targetApp)"
        ARCHIVE="\(zipUrl.path)"
        PARENT_PID="\(currentPid)"
        WORK_DIR="/tmp/auratube_upgrade_$$"
        LOG_FILE="/tmp/auratube_update.log"
        
        echo "Starting update: $(date)" > "$LOG_FILE"
        echo "Archive: $ARCHIVE" >> "$LOG_FILE"
        echo "Parent PID: $PARENT_PID" >> "$LOG_FILE"
        
        # Wait up to 1 second for parent app to exit cleanly, then force kill
        if [ -n "$PARENT_PID" ]; then
            for i in {1..10}; do
                if ! kill -0 "$PARENT_PID" 2>/dev/null; then
                    break
                fi
                sleep 0.1
            done
            kill -9 "$PARENT_PID" 2>/dev/null || true
        fi
        
        mkdir -p "$WORK_DIR"
        
        if [[ "$ARCHIVE" == *.dmg ]]; then
            echo "Mounting DMG..." >> "$LOG_FILE"
            MOUNT_OUT=$(hdiutil attach "$ARCHIVE" -nobrowse -readonly -noautofsck -noverify 2>&1)
            echo "$MOUNT_OUT" >> "$LOG_FILE"
            MOUNT_DIR=$(echo "$MOUNT_OUT" | grep "/Volumes/" | awk -F '\t' '{print $NF}' | tr -d '\n')
            if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR/AuraTube.app" ]; then
                echo "Copying app from DMG..." >> "$LOG_FILE"
                rm -rf "$TARGET_APP"
                cp -R "$MOUNT_DIR/AuraTube.app" "$TARGET_APP"
                xattr -cr "$TARGET_APP" 2>/dev/null || true
            fi
            if [ -n "$MOUNT_DIR" ]; then
                hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
            fi
        else
            echo "Unzipping..." >> "$LOG_FILE"
            unzip -q -o "$ARCHIVE" -d "$WORK_DIR" 2>> "$LOG_FILE"
            NEW_APP=$(find "$WORK_DIR" -maxdepth 3 -name "AuraTube.app" | head -n 1)
            if [ -n "$NEW_APP" ] && [ -d "$NEW_APP" ]; then
                echo "Copying app from ZIP..." >> "$LOG_FILE"
                rm -rf "$TARGET_APP"
                cp -R "$NEW_APP" "$TARGET_APP"
                xattr -cr "$TARGET_APP" 2>/dev/null || true
            fi
        fi
        
        echo "Launching updated app: $TARGET_APP" >> "$LOG_FILE"
        open -n "$TARGET_APP"
        
        rm -rf "$WORK_DIR"
        """
        
        let scriptPath = "/tmp/auratube_updater.sh"
        do {
            try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["+x", scriptPath]
            try chmod.run()
            chmod.waitUntilExit()
            
            // Spawn detached installer script
            let updater = Process()
            updater.executableURL = URL(fileURLWithPath: "/bin/bash")
            updater.arguments = [scriptPath]
            try updater.run()
            
            // Dismiss sheet and terminate process immediately
            self.showUpdateSheet = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                exit(0)
            }
        } catch {
            self.status = .error(message: "Không thể khởi động trình cập nhật: \(error.localizedDescription)")
        }
    }
}
