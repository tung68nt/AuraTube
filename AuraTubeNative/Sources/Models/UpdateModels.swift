import Foundation

public struct AppUpdateInfo: Identifiable, Codable, Hashable, Sendable {
    public var id: String { version }
    public let version: String
    public let title: String
    public let releaseNotes: String
    public let downloadUrl: String?
    public let publishedAt: String?
    public let minOSVersion: String?
    public let fileSize: String?
    
    public init(
        version: String,
        title: String = "",
        releaseNotes: String = "",
        downloadUrl: String? = nil,
        publishedAt: String? = nil,
        minOSVersion: String? = nil,
        fileSize: String? = nil
    ) {
        self.version = version
        self.title = title.isEmpty ? "AuraTube v\(version)" : title
        self.releaseNotes = releaseNotes
        self.downloadUrl = downloadUrl
        self.publishedAt = publishedAt
        self.minOSVersion = minOSVersion
        self.fileSize = fileSize
    }
}

public enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case available(AppUpdateInfo)
    case downloading(progress: Double, bytesWritten: Int64, totalBytes: Int64)
    case readyToInstall(zipUrl: URL, update: AppUpdateInfo)
    case installing
    case error(message: String)
    
    public static func == (lhs: UpdateStatus, rhs: UpdateStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.checking, .checking), (.installing, .installing):
            return true
        case (.upToDate(let v1), .upToDate(let v2)):
            return v1 == v2
        case (.available(let u1), .available(let u2)):
            return u1.version == u2.version
        case (.downloading(let p1, _, _), .downloading(let p2, _, _)):
            return abs(p1 - p2) < 0.001
        case (.readyToInstall(_, let u1), .readyToInstall(_, let u2)):
            return u1.version == u2.version
        case (.error(let m1), .error(let m2)):
            return m1 == m2
        default:
            return false
        }
    }
}
