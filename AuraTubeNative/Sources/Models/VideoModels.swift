import Foundation

public struct ChannelInfo: Identifiable, Codable, Hashable {
    public let id: String
    public var title: String
    public var handle: String?
    public var subscriberCount: String?
    public var avatarUrl: String
    public var description: String?
    
    public init(
        id: String,
        title: String,
        handle: String? = nil,
        subscriberCount: String? = nil,
        avatarUrl: String = "",
        description: String? = nil
    ) {
        self.id = id
        self.title = title
        self.handle = handle
        self.subscriberCount = subscriberCount
        self.avatarUrl = avatarUrl
        self.description = description
    }
}

public struct Video: Identifiable, Codable, Hashable {
    public let id: String
    public var title: String
    public var uploader: String
    public var uploaderId: String?
    public var duration: Double?
    public var durationFormatted: String
    public var viewCount: Int?
    public var viewCountFormatted: String
    public var publishedTime: String?
    public var thumbnail: String
    public var description: String?
    public var isExplicitShort: Bool?
    public var channelAvatarUrl: String?
    
    public init(
        id: String,
        title: String,
        uploader: String,
        uploaderId: String? = nil,
        duration: Double? = nil,
        durationFormatted: String = "0:00",
        viewCount: Int? = nil,
        viewCountFormatted: String = "",
        publishedTime: String? = nil,
        thumbnail: String = "",
        description: String? = nil,
        isShort: Bool? = nil,
        channelAvatarUrl: String? = nil
    ) {
        self.id = id
        self.title = title
        self.uploader = uploader
        self.uploaderId = uploaderId
        self.duration = duration
        self.durationFormatted = durationFormatted
        self.viewCount = viewCount
        self.viewCountFormatted = viewCountFormatted
        self.publishedTime = publishedTime
        self.thumbnail = thumbnail.isEmpty ? "https://i.ytimg.com/vi/\(id)/hqdefault.jpg" : thumbnail
        self.description = description
        self.isExplicitShort = isShort
        self.channelAvatarUrl = channelAvatarUrl
    }
    
    public var metadataFormatted: String {
        let hasViews = !viewCountFormatted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasDate = !(publishedTime ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        if hasViews && hasDate {
            return "\(viewCountFormatted) • \(publishedTime!)"
        } else if hasDate {
            return publishedTime!
        } else {
            return viewCountFormatted
        }
    }
    
    public var totalDurationSeconds: Double {
        if let d = duration, d > 0 { return d }
        let parts = durationFormatted.split(separator: ":").compactMap { Double($0) }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        } else if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        return 0
    }
    
    public var isShort: Bool {
        if let explicit = isExplicitShort { return explicit }
        let lower = title.lowercased()
        return lower.contains("#shorts") || lower.contains("#short") || lower.contains("/shorts/") || durationFormatted == "Shorts"
    }
}

public struct StreamInfo: Sendable {
    public let videoId: String
    public let title: String
    public let videoUrl: URL
    public let audioUrl: URL?
    public let isCombined: Bool
    public let resolution: String
    public let availableHeights: [Int]
    
    public init(
        videoId: String,
        title: String,
        videoUrl: URL,
        audioUrl: URL? = nil,
        isCombined: Bool = true,
        resolution: String = "1080p",
        availableHeights: [Int] = [1080, 720, 480, 360]
    ) {
        self.videoId = videoId
        self.title = title
        self.videoUrl = videoUrl
        self.audioUrl = audioUrl
        self.isCombined = isCombined
        self.resolution = resolution
        self.availableHeights = availableHeights
    }
}

public struct SponsorSegment: Codable, Sendable {
    public let category: String
    public let segment: [Double]
    
    public var start: Double { segment.first ?? 0 }
    public var end: Double { segment.count > 1 ? segment[1] : 0 }
    
    public init(category: String, start: Double, end: Double) {
        self.category = category
        self.segment = [start, end]
    }
}

public struct DownloadTier: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let height: Int
    public let estSize: String
    public let isAudioOnly: Bool
    
    public init(id: String, label: String, height: Int, estSize: String, isAudioOnly: Bool = false) {
        self.id = id
        self.label = label
        self.height = height
        self.estSize = estSize
        self.isAudioOnly = isAudioOnly
    }
}

public struct VideoChapter: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(start)-\(title)" }
    public let title: String
    public let start: Double
    public let end: Double
    
    public init(title: String, start: Double, end: Double) {
        self.title = title
        self.start = start
        self.end = end
    }
}

public struct VideoComment: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let author: String
    public let avatarUrl: String?
    public let text: String
    public let publishedTime: String
    public let likeCount: String
    public let replyCount: String?
    
    public init(
        id: String = UUID().uuidString,
        author: String,
        avatarUrl: String? = nil,
        text: String,
        publishedTime: String = "",
        likeCount: String = "",
        replyCount: String? = nil
    ) {
        self.id = id
        self.author = author
        self.avatarUrl = avatarUrl
        self.text = text
        self.publishedTime = publishedTime
        self.likeCount = likeCount
        self.replyCount = replyCount
    }
}

