import Foundation
import SwiftUI

@MainActor
public final class RecommendationService: ObservableObject {
    public static let shared = RecommendationService()
    
    private let channelsKey = "auratube_user_channel_affinity_v1"
    private let topicsKey = "auratube_user_topic_affinity_v1"
    private let searchesKey = "auratube_recent_searches_v1"
    
    @Published public private(set) var hasPersonalizedProfile: Bool = false
    @Published public private(set) var topChannels: [String] = []
    @Published public private(set) var topKeywords: [String] = []
    
    private init() {
        refreshProfileMetrics()
    }
    
    // MARK: - Signal Collection & Tracking
    
    /// Sync and bootstrap recommendations from existing watch history if available
    public func syncFromExistingHistory(_ videos: [Video]) {
        guard !videos.isEmpty else { return }
        for v in videos {
            recordWatch(video: v, saveImmediately: false)
        }
        refreshProfileMetrics()
    }
    
    /// Record a video watch event
    public func recordWatch(video: Video, saveImmediately: Bool = true) {
        let uploader = video.uploader.trimmingCharacters(in: .whitespacesAndNewlines)
        if !uploader.isEmpty && uploader.lowercased() != "youtube" && uploader.lowercased() != "youtube shorts" {
            var channelCounts = UserDefaults.standard.dictionary(forKey: channelsKey) as? [String: Int] ?? [:]
            channelCounts[uploader] = (channelCounts[uploader] ?? 0) + 1
            UserDefaults.standard.set(channelCounts, forKey: channelsKey)
        }
        
        // Extract meaningful topic keywords from title
        let keywords = extractKeywords(from: video.title)
        if !keywords.isEmpty {
            var topicCounts = UserDefaults.standard.dictionary(forKey: topicsKey) as? [String: Int] ?? [:]
            for kw in keywords {
                topicCounts[kw] = (topicCounts[kw] ?? 0) + 1
            }
            UserDefaults.standard.set(topicCounts, forKey: topicsKey)
        }
        
        if saveImmediately {
            refreshProfileMetrics()
        }
    }
    
    /// Record a user search query
    public func recordSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        var searches = UserDefaults.standard.stringArray(forKey: searchesKey) ?? []
        searches.removeAll(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        searches.insert(trimmed, at: 0)
        if searches.count > 15 { searches.removeLast() }
        UserDefaults.standard.set(searches, forKey: searchesKey)
        
        // Also boost keywords from search
        let keywords = extractKeywords(from: trimmed)
        if !keywords.isEmpty {
            var topicCounts = UserDefaults.standard.dictionary(forKey: topicsKey) as? [String: Int] ?? [:]
            for kw in keywords {
                topicCounts[kw] = (topicCounts[kw] ?? 0) + 2 // Search carries double weight
            }
            UserDefaults.standard.set(topicCounts, forKey: topicsKey)
        }
        
        refreshProfileMetrics()
    }
    
    public func refreshProfileMetrics() {
        let channelCounts = UserDefaults.standard.dictionary(forKey: channelsKey) as? [String: Int] ?? [:]
        let sortedChannels = channelCounts.sorted(by: { $0.value > $1.value }).map { $0.key }
        self.topChannels = Array(sortedChannels.prefix(5))
        
        let topicCounts = UserDefaults.standard.dictionary(forKey: topicsKey) as? [String: Int] ?? [:]
        let sortedTopics = topicCounts.sorted(by: { $0.value > $1.value }).map { $0.key }
        self.topKeywords = Array(sortedTopics.prefix(6))
        
        let subCount = ChannelSubscriptionManager.shared.subscribedChannels.count
        self.hasPersonalizedProfile = !topChannels.isEmpty || !topKeywords.isEmpty || subCount > 0
    }
    
    // MARK: - Keyword Extraction
    
    private func extractKeywords(from text: String) -> [String] {
        let stopWords: Set<String> = [
            "và", "của", "các", "những", "cho", "trong", "với", "tập", "full", "video",
            "official", "lyrics", "audio", "nhạc", "bài", "hát", "trailer", "teaser",
            "preview", "review", "mới", "nhất", "hôm", "nay", "2024", "2025", "2026",
            "hd", "4k", "vietsub", "thuyết", "minh", "lồng", "tiếng", "trên", "tại",
            "một", "người", "được", "không", "này", "khi", "làm", "thế", "nào", "gì",
            "hay", "cực", "quá", "về", "như", "đã", "có", "sẽ", "phải", "đến"
        ]
        
        // Clean special characters
        let cleaned = text.lowercased()
            .replacingOccurrences(of: "[^a-z0-9a-zà-ỹ\\s]", with: " ", options: .regularExpression)
        
        let words = cleaned.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 && !stopWords.contains($0) }
        
        return Array(Set(words))
    }
    
    // MARK: - Smart Recommendation Algorithm
    
    /// Generates tailored recommendations based on user interests, subscriptions, and balanced discovery
    public func fetchRecommendations() async -> [Video] {
        refreshProfileMetrics()
        
        let history = PlayerManager.shared.historyVideos
        let watchedIds = Set(history.prefix(15).map { $0.id })
        
        if hasPersonalizedProfile {
            return await fetchPersonalizedFeed(watchedIds: watchedIds)
        } else {
            return await fetchDiverseColdStartFeed()
        }
    }
    
    /// Fetch personalized feed tailored to user's favorite channels, subscriptions, and topics
    private func fetchPersonalizedFeed(watchedIds: Set<String>) async -> [Video] {
        // Collect candidate query sources
        var queries: [String] = []
        
        // 1. Subscribed channels
        let subs = ChannelSubscriptionManager.shared.subscribedChannels
        if !subs.isEmpty {
            for ch in subs.prefix(3) {
                let q = (ch.handle?.hasPrefix("@") == true) ? ch.handle! : ch.title
                queries.append(q)
            }
        }
        
        // 2. Favorite watched channels
        for ch in topChannels.prefix(3) {
            if !queries.contains(ch) {
                queries.append(ch)
            }
        }
        
        // 3. Favorite topics / keywords
        for kw in topKeywords.prefix(2) {
            queries.append("\(kw) mới nhất")
        }
        
        // 4. Always add a high-quality non-music baseline for fresh discovery
        queries.append("công nghệ tin tức đời sống hay nhất")
        
        // Concurrently search up to 4 distinct streams
        let selectedQueries = Array(queries.prefix(4))
        
        var streams: [[Video]] = []
        await withTaskGroup(of: [Video].self) { group in
            for q in selectedQueries {
                group.addTask {
                    let results = await YTDLPService.shared.searchVideos(query: q, limit: 12)
                    return results
                }
            }
            for await res in group {
                if !res.isEmpty {
                    streams.append(res)
                }
            }
        }
        
        // Interleave streams to ensure rich variety
        var combined: [Video] = []
        var seenIds = Set<String>()
        
        let maxLen = streams.map { $0.count }.max() ?? 0
        for i in 0..<maxLen {
            for stream in streams {
                if i < stream.count {
                    let v = stream[i]
                    // Do not repeat videos, and avoid showing videos user just finished watching
                    if !seenIds.contains(v.id) && !watchedIds.contains(v.id) {
                        seenIds.insert(v.id)
                        combined.append(v)
                    }
                }
            }
        }
        
        // If results are low (e.g. strict filters), supplement with diverse cold start
        if combined.count < 10 {
            let fallback = await fetchDiverseColdStartFeed()
            for v in fallback {
                if !seenIds.contains(v.id) {
                    seenIds.insert(v.id)
                    combined.append(v)
                }
            }
        }
        
        return combined
    }
    
    /// Diverse multi-pillar feed for new users (Zero pure-music bias)
    private func fetchDiverseColdStartFeed() async -> [Video] {
        let pillars = [
            "công nghệ review sản phẩm mới",           // Pillar 1: Tech, Gadgets, Innovation (ThinkView, Schannel, etc.)
            "tin tức chuyển động thời sự 24h",          // Pillar 2: News & Current Affairs (VTV24, Báo Thanh Niên)
            "khám phá du lịch đời sống văn hóa việt nam", // Pillar 3: Travel, Discovery, Culture (Khoai Lang Thang, Monster Box)
            "podcast phê phim giải trí góc nhìn"         // Pillar 4: Cinema, Podcasts, Meaningful entertainment (Phê Phim, Vietcetera)
        ]
        
        var streams: [[Video]] = []
        await withTaskGroup(of: [Video].self) { group in
            for p in pillars {
                group.addTask {
                    return await YTDLPService.shared.searchVideos(query: p, limit: 8)
                }
            }
            for await res in group {
                if !res.isEmpty {
                    streams.append(res)
                }
            }
        }
        
        // 1:1:1:1 Balanced interleave
        var combined: [Video] = []
        var seenIds = Set<String>()
        
        let maxLen = streams.map { $0.count }.max() ?? 0
        for i in 0..<maxLen {
            for stream in streams {
                if i < stream.count {
                    let v = stream[i]
                    if !seenIds.contains(v.id) {
                        seenIds.insert(v.id)
                        combined.append(v)
                    }
                }
            }
        }
        
        return combined
    }
}
