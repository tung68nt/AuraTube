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
    /// True when the previous in-app update did not take effect (shown in the error sheet).
    @Published public var lastInstallFailed: Bool = false
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
        if isUserInitiated { self.lastInstallFailed = false }
        
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
                        self.showUpdateSheet = true
                    }
                }
            } else {
                self.status = .error(message: "Không thể kết nối máy chủ cập nhật. Vui lòng kiểm tra lại kết nối mạng.")
                if isUserInitiated {
                    self.showUpdateSheet = true
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
        // 1. Check local version.json manifest if present in development environment
        #if DEBUG
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
        
        // 2. Remote Attempt 1: Fetch custom version.json manifest from GitHub
        if let update = await fetchFromManifest(url: updateFeedUrl) {
            return update
        }
        
        // 3. Remote Attempt 2: Fetch GitHub Release API
        if let update = await fetchFromGitHubReleases(url: githubReleaseUrl) {
            return update
        }
        
        return nil
    }
    
    private func fetchFromManifest(url: URL) async -> AppUpdateInfo? {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 10.0
        
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
        req.timeoutInterval = 10.0
        
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
        self.lastInstallFailed = false
        #if DEBUG
        // Dev fast-path: install a locally built archive of exactly this version
        let localCandidates = [
            "/Users/tungnguyen/Code/Youtube/AuraTube-v\(update.version).zip",
            "/Users/tungnguyen/Code/Youtube/AuraTube-v\(update.version).dmg"
        ]
        for path in localCandidates {
            if FileManager.default.fileExists(atPath: path) {
                let localUrl = URL(fileURLWithPath: path)
                self.installAndRelaunch(zipUrl: localUrl)
                return
            }
        }
        #endif
        
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
        let targetApp = Self.resolveInstallTarget()
        let expectedVersion = latestUpdate?.version ?? ""
        let logUrl = Self.updateLogUrl
        try? FileManager.default.createDirectory(at: logUrl.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Installer runs after this process exits. It never aborts silently: every failure is logged,
        // the previous app is restored, and the app is relaunched so verifyPendingUpdate() can report it.
        let scriptContent = #"""
        #!/bin/bash
        TARGET_APP="$1"
        ARCHIVE="$2"
        PARENT_PID="$3"
        EXPECTED="$4"
        LOG_FILE="$5"
        WORK_DIR=$(mktemp -d /tmp/auratube_upgrade.XXXXXX)
        MOUNT_DIR=""

        log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
        bundle_version() { /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$1/Contents/Info.plist" 2>/dev/null; }
        finish() {
            if [ -n "$MOUNT_DIR" ]; then hdiutil detach "$MOUNT_DIR" -force >> "$LOG_FILE" 2>&1 || true; fi
            rm -rf "$WORK_DIR"
            /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$TARGET_APP" >/dev/null 2>&1 || true
            log "Launching: $TARGET_APP (installed version: $(bundle_version "$TARGET_APP"))"
            open "$TARGET_APP" >> "$LOG_FILE" 2>&1 || true
            exit "$1"
        }

        echo "" >> "$LOG_FILE"
        log "=== Update to $EXPECTED -> $TARGET_APP (archive: $ARCHIVE)"

        # Wait up to 10s for the app to exit, then force kill
        if [ -n "$PARENT_PID" ]; then
            for i in $(seq 1 100); do
                kill -0 "$PARENT_PID" 2>/dev/null || break
                sleep 0.1
            done
            kill -9 "$PARENT_PID" 2>/dev/null || true
        fi

        SRC_APP=""
        if [[ "$ARCHIVE" == *.dmg ]]; then
            MOUNT_DIR="$WORK_DIR/mnt"
            mkdir -p "$MOUNT_DIR"
            if ! hdiutil attach "$ARCHIVE" -nobrowse -readonly -noautoopen -noverify -mountpoint "$MOUNT_DIR" >> "$LOG_FILE" 2>&1; then
                log "ERROR: cannot mount DMG"
                MOUNT_DIR=""
                finish 1
            fi
            SRC_APP="$MOUNT_DIR/AuraTube.app"
        else
            mkdir -p "$WORK_DIR/zip"
            if ! ditto -x -k "$ARCHIVE" "$WORK_DIR/zip" >> "$LOG_FILE" 2>&1; then
                log "ERROR: cannot unzip archive"
                finish 1
            fi
            SRC_APP=$(find "$WORK_DIR/zip" -maxdepth 3 -name "AuraTube.app" -type d | head -n 1)
        fi

        if [ -z "$SRC_APP" ] || [ ! -d "$SRC_APP" ]; then
            log "ERROR: AuraTube.app not found in archive"
            finish 1
        fi
        SRC_VERSION=$(bundle_version "$SRC_APP")
        log "Archive contains version: $SRC_VERSION"
        if [ -n "$EXPECTED" ] && [ "$SRC_VERSION" != "$EXPECTED" ]; then
            log "ERROR: archive version ($SRC_VERSION) does not match expected ($EXPECTED)"
            finish 1
        fi

        # Atomic swap: copy to a staging bundle next to the target, then rename; restore on failure
        INSTALL_SH="$WORK_DIR/install.sh"
        cat > "$INSTALL_SH" <<'INSTALL'
        SRC="$1"; TARGET="$2"
        PARENT=$(dirname "$TARGET")
        STAGE="$PARENT/.AuraTube-update-$$.app"
        OLD="$PARENT/.AuraTube-old-$$.app"
        mkdir -p "$PARENT" || exit 10
        rm -rf "$STAGE"
        ditto "$SRC" "$STAGE" || { rm -rf "$STAGE"; exit 11; }
        xattr -cr "$STAGE" 2>/dev/null || true
        if [ -e "$TARGET" ]; then
            mv "$TARGET" "$OLD" || { rm -rf "$STAGE"; exit 12; }
        fi
        if ! mv "$STAGE" "$TARGET"; then
            [ -e "$OLD" ] && mv "$OLD" "$TARGET"
            rm -rf "$STAGE"
            exit 13
        fi
        rm -rf "$OLD"
        exit 0
        INSTALL

        PARENT_DIR=$(dirname "$TARGET_APP")
        if [ -w "$PARENT_DIR" ] && { [ ! -e "$TARGET_APP" ] || [ -w "$TARGET_APP" ]; }; then
            log "Installing as current user"
            /bin/bash "$INSTALL_SH" "$SRC_APP" "$TARGET_APP" >> "$LOG_FILE" 2>&1
            RC=$?
        else
            # Standard (non-admin) accounts, or an app copied by another user: ask for admin rights
            log "Target not writable by $(whoami); requesting administrator privileges"
            osascript - "$INSTALL_SH" "$SRC_APP" "$TARGET_APP" >> "$LOG_FILE" 2>&1 <<'OSA'
        on run argv
            do shell script "/bin/bash " & quoted form of (item 1 of argv) & " " & quoted form of (item 2 of argv) & " " & quoted form of (item 3 of argv) with prompt "AuraTube cần quyền quản trị để cài bản cập nhật." with administrator privileges
        end run
        OSA
            RC=$?
        fi

        INSTALLED=$(bundle_version "$TARGET_APP")
        if [ $RC -ne 0 ] || [ -n "$EXPECTED" -a "$INSTALLED" != "$EXPECTED" ]; then
            log "ERROR: install failed (rc=$RC, installed version: $INSTALLED)"
            finish 1
        fi
        log "SUCCESS: installed $INSTALLED"
        finish 0
        """#

        let secureDir = FileManager.default.temporaryDirectory.appendingPathComponent("updater_\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: secureDir, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
            let scriptUrl = secureDir.appendingPathComponent("updater.sh")
            try scriptContent.write(to: scriptUrl, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptUrl.path)

            // Remember what we are installing so the next launch can confirm it actually happened
            let defaults = UserDefaults.standard
            defaults.set(expectedVersion, forKey: Self.pendingVersionKey)
            defaults.set(targetApp, forKey: Self.pendingTargetKey)

            let updater = Process()
            updater.executableURL = URL(fileURLWithPath: "/bin/bash")
            updater.arguments = [scriptUrl.path, targetApp, zipUrl.path, "\(currentPid)", expectedVersion, logUrl.path]
            try updater.run()

            self.showUpdateSheet = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                exit(0)
            }
        } catch {
            self.status = .error(message: "Không thể khởi động trình cập nhật: \(error.localizedDescription)")
        }
    }

    // MARK: - Post-update verification

    private static let pendingVersionKey = "auratube_pending_update_version"
    private static let pendingTargetKey = "auratube_pending_update_target"
    public static let updateLogUrl = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/AuraTube/update.log")

    /// Where the update should be installed. A translocated (Gatekeeper) or DMG-mounted copy is
    /// read-only, so writing there fails and the user keeps launching the old version.
    private static func resolveInstallTarget() -> String {
        let path = Bundle.main.bundlePath
        let isReadOnlyLocation = path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/")
        if path.hasSuffix(".app") && !isReadOnlyLocation {
            return path
        }
        return "/Applications/AuraTube.app"
    }

    private static func bundleVersion(atPath appPath: String) -> String? {
        let plist = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plist) else { return nil }
        return dict["CFBundleShortVersionString"] as? String
    }

    /// Call once at launch. Returns true when the last in-app update did not take effect,
    /// in which case an explanatory error is shown and the caller should skip the auto-check.
    @discardableResult
    public func verifyPendingUpdate() -> Bool {
        let defaults = UserDefaults.standard
        guard let pending = defaults.string(forKey: Self.pendingVersionKey), !pending.isEmpty else { return false }
        let target = defaults.string(forKey: Self.pendingTargetKey) ?? ""
        defaults.removeObject(forKey: Self.pendingVersionKey)
        defaults.removeObject(forKey: Self.pendingTargetKey)

        if !isVersion(pending, higherThan: currentVersion) {
            return false // update applied
        }

        let message: String
        if !target.isEmpty, target != Bundle.main.bundlePath,
           let installed = Self.bundleVersion(atPath: target), !isVersion(pending, higherThan: installed) {
            message = "Bản v\(pending) đã được cài tại \(target), nhưng bạn đang mở một bản AuraTube cũ khác (\(Bundle.main.bundlePath)). Hãy mở AuraTube trong thư mục Applications và xoá bản cũ."
        } else {
            message = "Cập nhật lên v\(pending) chưa thành công nên AuraTube vẫn là v\(currentVersion). Hãy tải file DMG ở trang phát hành và kéo AuraTube vào thư mục Applications. Nhật ký: \(Self.updateLogUrl.path)"
        }
        self.lastInstallFailed = true
        self.status = .error(message: message)
        // Present once the main window is up; a sheet requested before that can be dropped
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.showUpdateSheet = true
        }
        return true
    }

    public func openReleasesPage() {
        if let url = URL(string: "https://github.com/tung68nt/AuraTube/releases/latest") {
            NSWorkspace.shared.open(url)
        }
    }
}
