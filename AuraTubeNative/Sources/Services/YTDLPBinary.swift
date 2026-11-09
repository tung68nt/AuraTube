import Foundation

/// Finds the yt-dlp binary and, when the machine has none, downloads the standalone
/// `yt-dlp_macos` build (universal, no Python needed) into Application Support.
/// This lets the app work on Macs without Homebrew.
public final class YTDLPBinary: @unchecked Sendable {
    public static let shared = YTDLPBinary()

    private static let downloadURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
    private static let updateInterval: TimeInterval = 3 * 24 * 3600

    private let lock = NSLock()
    private var installTask: Task<String, Error>?

    private init() {}

    /// App-managed copy: ~/Library/Application Support/AuraTube/bin/yt-dlp
    public var managedPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("AuraTube/bin/yt-dlp").path
    }

    private var candidates: [String] {
        [
            managedPath,
            Bundle.main.resourcePath.map { "\($0)/bin/yt-dlp" } ?? "",
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ].filter { !$0.isEmpty }
    }

    /// Returns an existing, executable yt-dlp path without touching the network.
    public var existingPath: String? {
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) && isValidBinary(path) {
            return path
        }
        return nil
    }

    /// Returns a usable yt-dlp path, downloading it on first use if needed.
    public func resolve() async throws -> String {
        if let path = existingPath { return path }
        return try await install()
    }

    /// Called at launch: installs if missing, refreshes the managed copy when it is old
    /// (YouTube changes often break outdated yt-dlp).
    public func prepareInBackground() {
        Task.detached(priority: .utility) {
            if self.existingPath == nil {
                _ = try? await self.install()
                return
            }
            let path = self.managedPath
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let modified = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(modified) > Self.updateInterval {
                _ = try? await self.install(force: true)
            }
        }
    }

    @discardableResult
    public func install(force: Bool = false) async throws -> String {
        lock.lock()
        let task: Task<String, Error>
        if let running = installTask {
            task = running
        } else {
            task = Task<String, Error> { try await self.performInstall(force: force) }
            installTask = task
        }
        lock.unlock()
        defer {
            lock.lock()
            installTask = nil
            lock.unlock()
        }
        return try await task.value
    }

    private func performInstall(force: Bool) async throws -> String {
        let fm = FileManager.default
        let dest = URL(fileURLWithPath: managedPath)
        if !force, fm.isExecutableFile(atPath: dest.path), isValidBinary(dest.path) {
            return dest.path
        }
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

        var request = URLRequest(url: Self.downloadURL, timeoutInterval: 120)
        request.setValue("AuraTube", forHTTPHeaderField: "User-Agent")

        var lastError: Error?
        for attempt in 0..<3 {
            do {
                let (tmp, response) = try await URLSession.shared.download(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw NSError(domain: "YTDLPBinary", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Tải yt-dlp thất bại (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1))"])
                }
                guard isValidBinary(tmp.path) else {
                    throw NSError(domain: "YTDLPBinary", code: 500,
                                  userInfo: [NSLocalizedDescriptionKey: "File yt-dlp tải về không hợp lệ"])
                }
                let staged = dest.deletingLastPathComponent().appendingPathComponent("yt-dlp.new")
                try? fm.removeItem(at: staged)
                try fm.moveItem(at: tmp, to: staged)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)
                removexattr(staged.path, "com.apple.quarantine", 0)
                if fm.fileExists(atPath: dest.path) {
                    _ = try fm.replaceItemAt(dest, withItemAt: staged)
                } else {
                    try fm.moveItem(at: staged, to: dest)
                }
                return dest.path
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_500_000_000)
            }
        }
        // A failed refresh should not hide a still-working older copy.
        if let path = existingPath { return path }
        throw lastError ?? NSError(domain: "YTDLPBinary", code: 404,
                                   userInfo: [NSLocalizedDescriptionKey: "Không thể tải yt-dlp. Vui lòng kiểm tra kết nối mạng."])
    }

    /// Mach-O (thin or fat) or a script with a shebang, and not a tiny HTML error page.
    private func isValidBinary(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4), head.count == 4 else { return false }
        let magic = head.withUnsafeBytes { $0.load(as: UInt32.self) }
        let machO: Set<UInt32> = [0xfeedfacf, 0xcffaedfe, 0xcafebabe, 0xbebafeca, 0xfeedface, 0xcefaedfe]
        if machO.contains(magic) { return true }
        return head.starts(with: [0x23, 0x21]) // "#!"
    }
}
