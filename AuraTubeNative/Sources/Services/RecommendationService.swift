import Foundation
import SwiftUI

@MainActor
public final class RecommendationService: ObservableObject {
    public static let shared = RecommendationService()
    
    private let channelsKey = "auratube_user_channel_affinity_v1"
    private let topicsKey = "auratube_user_topic_affinity_v1"
    private let searchesKey = "auratube_recent_searches_v1"
    private let channelAvatarsKey = "auratube_channel_avatars_v1"
    
    @Published public private(set) var hasPersonalizedProfile: Bool = false
    @Published public private(set) var topChannels: [String] = []
    @Published public private(set) var topKeywords: [String] = []
    @Published public private(set) var recentSearches: [String] = []
    @Published public private(set) var dynamicInterestTags: [String] = []
    @Published public private(set) var channelAvatars: [String: String] = [:]
    
    // In-memory & Persisted Trending Cache for fast response & 0ms initial render
    private let trendingCacheKey = "auratube_trending_feed_cache_v2"
    private var trendingCache: [Video] = []
    private var lastTrendingFetchTime: Date? = nil
    private let cacheValidityInterval: TimeInterval = 900 // 15 minutes
    
    public func getCachedTrending() -> [Video] {
        if userLikesMusic { return trendingCache }
        return trendingCache.filter { !Self.isMusicCompilation($0) }
    }
    
    private init() {
        if let map = UserDefaults.standard.dictionary(forKey: channelAvatarsKey) as? [String: String] {
            self.channelAvatars = map
        }
        if let data = UserDefaults.standard.data(forKey: trendingCacheKey),
           let cached = try? JSONDecoder().decode([Video].self, from: data),
           !cached.isEmpty {
            self.trendingCache = cached
            self.lastTrendingFetchTime = Date()
        }
        refreshProfileMetrics()
    }
    
    // MARK: - Avatar Management
    
    public func getAvatarUrl(for channelName: String) -> String? {
        let key = channelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let direct = channelAvatars[key], !direct.isEmpty {
            return direct
        }
        if let sub = ChannelSubscriptionManager.shared.subscribedChannels.first(where: { $0.title.caseInsensitiveCompare(channelName) == .orderedSame }),
           !sub.avatarUrl.isEmpty {
            return sub.avatarUrl
        }
        return nil
    }
    
    public func setChannelAvatar(for channelName: String, url: String) {
        let key = channelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty, !url.isEmpty else { return }
        if channelAvatars[key] != url {
            channelAvatars[key] = url
            UserDefaults.standard.set(channelAvatars, forKey: channelAvatarsKey)
        }
    }
    
    public func fetchMissingAvatars(for channels: [String]) {
        for ch in channels {
            let key = ch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if channelAvatars[key] == nil || channelAvatars[key]?.isEmpty == true {
                Task {
                    let vids = await YTDLPService.shared.searchVideos(query: ch, limit: 3)
                    if let match = vids.first(where: { ($0.channelAvatarUrl != nil && !$0.channelAvatarUrl!.isEmpty) }) {
                        DispatchQueue.main.async {
                            self.setChannelAvatar(for: ch, url: match.channelAvatarUrl!)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Signal Collection & Tracking
    
    /// Sync and bootstrap recommendations from existing watch history if available
    public func syncFromExistingHistory(_ videos: [Video]) {
        guard !videos.isEmpty else { return }
        for v in videos {
            recordWatch(video: v, saveImmediately: false)
            if let avatar = v.channelAvatarUrl, !avatar.isEmpty {
                setChannelAvatar(for: v.uploader, url: avatar)
            }
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
            
            if let avatar = video.channelAvatarUrl, !avatar.isEmpty {
                setChannelAvatar(for: uploader, url: avatar)
            }
        }
        
        // Extract meaningful topic keywords & intact phrases from title
        let keywords = extractKeywordsAndPhrases(from: video.title)
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
    
    /// Record high-retention watch completion (> 50% or finished) with enhanced signal weight
    public func recordWatchCompletion(video: Video) {
        let uploader = video.uploader.trimmingCharacters(in: .whitespacesAndNewlines)
        if !uploader.isEmpty && uploader.lowercased() != "youtube" && uploader.lowercased() != "youtube shorts" {
            var channelCounts = UserDefaults.standard.dictionary(forKey: channelsKey) as? [String: Int] ?? [:]
            channelCounts[uploader] = (channelCounts[uploader] ?? 0) + 2
            UserDefaults.standard.set(channelCounts, forKey: channelsKey)
        }
        
        let keywords = extractKeywordsAndPhrases(from: video.title)
        if !keywords.isEmpty {
            var topicCounts = UserDefaults.standard.dictionary(forKey: topicsKey) as? [String: Int] ?? [:]
            for kw in keywords {
                topicCounts[kw] = (topicCounts[kw] ?? 0) + 2
            }
            UserDefaults.standard.set(topicCounts, forKey: topicsKey)
        }
        
        refreshProfileMetrics()
    }
    
    /// Record bookmark as high explicit affinity
    public func recordBookmark(video: Video) {
        recordWatchCompletion(video: video)
    }
    
    /// Reset learned preferences
    public func resetLearnedPreferences() {
        UserDefaults.standard.removeObject(forKey: channelsKey)
        UserDefaults.standard.removeObject(forKey: topicsKey)
        UserDefaults.standard.removeObject(forKey: searchesKey)
        refreshProfileMetrics()
    }
    
    /// Record a user search query
    public func recordSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        var searches = UserDefaults.standard.stringArray(forKey: searchesKey) ?? []
        searches.removeAll(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        searches.insert(trimmed, at: 0)
        if searches.count > 20 { searches.removeLast() }
        UserDefaults.standard.set(searches, forKey: searchesKey)
        
        // Boost keywords and the search phrase itself
        var topicCounts = UserDefaults.standard.dictionary(forKey: topicsKey) as? [String: Int] ?? [:]
        topicCounts[trimmed.lowercased()] = (topicCounts[trimmed.lowercased()] ?? 0) + 3 // High weight for full search phrase
        
        let keywords = extractKeywordsAndPhrases(from: trimmed)
        for kw in keywords {
            topicCounts[kw] = (topicCounts[kw] ?? 0) + 2
        }
        UserDefaults.standard.set(topicCounts, forKey: topicsKey)
        
        refreshProfileMetrics()
    }
    
    public func refreshProfileMetrics() {
        let channelCounts = UserDefaults.standard.dictionary(forKey: channelsKey) as? [String: Int] ?? [:]
        let sortedChannels = channelCounts.sorted(by: { $0.value > $1.value }).map { $0.key }
        self.topChannels = Array(sortedChannels.prefix(8))
        
        let topicCounts = UserDefaults.standard.dictionary(forKey: topicsKey) as? [String: Int] ?? [:]
        let sortedTopics = topicCounts.sorted(by: { $0.value > $1.value }).map { $0.key }
        self.topKeywords = Array(sortedTopics.prefix(10))
        
        self.recentSearches = UserDefaults.standard.stringArray(forKey: searchesKey) ?? []
        
        let subCount = ChannelSubscriptionManager.shared.subscribedChannels.count
        self.hasPersonalizedProfile = !topChannels.isEmpty || !topKeywords.isEmpty || !recentSearches.isEmpty || subCount > 0
        
        // Fetch missing channel avatars in background
        fetchMissingAvatars(for: self.topChannels)
        
        buildDynamicInterestTags()
    }
    
    /// Remove an individual query from recent search history
    public func removeRecentSearch(_ query: String) {
        var searches = UserDefaults.standard.stringArray(forKey: searchesKey) ?? []
        searches.removeAll(where: { $0.caseInsensitiveCompare(query) == .orderedSame })
        UserDefaults.standard.set(searches, forKey: searchesKey)
        self.recentSearches = searches
        buildDynamicInterestTags()
    }
    
    /// Clear all recent search history
    public func clearRecentSearches() {
        UserDefaults.standard.removeObject(forKey: searchesKey)
        self.recentSearches = []
        buildDynamicInterestTags()
    }
    
    // MARK: - Dynamic Interest Tags Generation
    
    private func buildDynamicInterestTags() {
        var tags: [String] = []
        var seen = Set<String>()
        
        let topChannelSet = Set(topChannels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        
        func addTag(_ t: String) {
            let clean = t.trimmingCharacters(in: .whitespacesAndNewlines)
            guard clean.count >= 2 && clean.count <= 18 else { return }
            let lower = clean.lowercased()
            // Avoid duplication with topChannels row which already has its own dedicated shelf
            if !seen.contains(lower) && !topChannelSet.contains(lower) {
                seen.insert(lower)
                let formatted = clean.prefix(1).uppercased() + clean.dropFirst()
                tags.append(formatted)
            }
        }
        
        // 1. Recent searches: only allow short concise phrases, or extract keywords from long queries
        for s in recentSearches.prefix(5) {
            let clean = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.count <= 18 && clean.split(separator: " ").count <= 3 {
                addTag(clean)
            } else {
                let kws = extractKeywordsAndPhrases(from: clean)
                for kw in kws.prefix(1) {
                    if kw.count >= 3 && kw.count <= 16 {
                        addTag(kw)
                    }
                }
            }
        }
        
        // 2. Top interest keywords
        for kw in topKeywords.prefix(4) {
            if kw.count <= 16 {
                addTag(kw)
            }
        }
        
        // 3. Semantic ecosystem suggestions
        for kw in topKeywords.prefix(2) {
            if let ecosystem = SemanticClusterEngine.suggestTag(for: kw) {
                if ecosystem.count <= 18 {
                    addTag(ecosystem)
                }
            }
        }
        
        self.dynamicInterestTags = Array(tags.prefix(6))
    }
    
    // MARK: - Keyword & Entity Extraction
    
    private func extractKeywordsAndPhrases(from text: String) -> [String] {
        let stopWords: Set<String> = [
            "và", "của", "các", "những", "cho", "trong", "với", "tập", "full", "video",
            "official", "lyrics", "audio", "nhạc", "bài", "hát", "trailer", "teaser",
            "preview", "review", "mới", "nhất", "hôm", "nay", "2024", "2025", "2026",
            "hd", "4k", "vietsub", "thuyết", "minh", "lồng", "tiếng", "trên", "tại",
            "một", "người", "được", "không", "này", "khi", "làm", "thế", "nào", "gì",
            "hay", "cực", "quá", "về", "như", "đã", "có", "sẽ", "phải", "đến", "chính",
            "thức", "bởi", "từ", "nhiều", "lại", "ra", "vào", "ngày", "năm", "tháng"
        ]
        
        let cleaned = text.lowercased()
            .replacingOccurrences(of: "[^a-z0-9a-zà-ỹ\\s]", with: " ", options: .regularExpression)
        
        let tokens = cleaned.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        var results: [String] = []
        
        // 1. Single keywords
        for token in tokens {
            if token.count >= 3 && !stopWords.contains(token) && Double(token) == nil {
                results.append(token)
            }
        }
        
        // 2. Recognized bigrams / tech phrases (e.g. "iphone 16", "apple watch", "vision pro")
        if tokens.count >= 2 {
            for i in 0..<(tokens.count - 1) {
                let bi = "\(tokens[i]) \(tokens[i+1])"
                if bi.contains("iphone") || bi.contains("macbook") || bi.contains("apple") ||
                   bi.contains("samsung") || bi.contains("galaxy") || bi.contains("vision pro") ||
                   bi.contains("tai nghe") || bi.contains("bàn phím") || bi.contains("pc gaming") {
                    results.append(bi)
                }
            }
        }
        
        return Array(Set(results))
    }
    
    // MARK: - Smart Recommendation Algorithm
    
    /// Generates multi-stream recommendations balancing:
    /// 1. Channel Loyalty (videos from favorite channels & related creators)
    /// 2. Direct Topic Affinity (exact user search & watch interests)
    /// 3. Semantic Ecosystem Expansion (e.g. iPhone -> accessories, cases, MacBooks, AR/VR glasses)
    /// 4. Fresh Serendipitous Discovery (non-music quality content)
    public func fetchRecommendations() async -> [Video] {
        refreshProfileMetrics()
        
        let history = PlayerManager.shared.historyVideos
        let watchedIds = Set(history.prefix(200).map { $0.id })
        
        let raw: [Video]
        if hasPersonalizedProfile {
            raw = await fetchPersonalizedMultiStreamFeed(watchedIds: watchedIds)
        } else {
            raw = await fetchDiverseColdStartFeed()
        }
        let ranked = diversifyAndRank(raw)
        recordImpressions(ranked.prefix(24))
        return ranked
    }
    
    // MARK: - Impression Discounting (YouTube: "shown but not clicked" = negative signal)
    private var impressionCounts: [String: Int] = [:]
    
    private func recordImpressions<S: Sequence>(_ videos: S) where S.Element == Video {
        for v in videos { impressionCounts[v.id, default: 0] += 1 }
        if impressionCounts.count > 3000 {
            impressionCounts = impressionCounts.filter { $0.value >= 2 }
        }
    }
    
    /// Ranking stage, modeled on YouTube's two-stage recommender:
    /// 1. Demote items already shown ≥2 times without a click (stale impressions).
    /// 2. Channel diversity: max 2 per channel in the visible feed, never back-to-back same channel.
    /// 3. Shorts are kept out of the main long-form grid (they have their own shelf).
    private func diversifyAndRank(_ input: [Video]) -> [Video] {
        var seen = Set<String>()
        let likesMusic = userLikesMusic
        let unique = input.filter { seen.insert($0.id).inserted && (likesMusic || !Self.isMusicCompilation($0)) }
        
        let fresh = unique.filter { (impressionCounts[$0.id] ?? 0) < 2 }
        let stale = unique.filter { (impressionCounts[$0.id] ?? 0) >= 2 }
        let longForm = fresh.filter { !$0.isShort }
        let shorts = fresh.filter { $0.isShort }
        
        var result: [Video] = []
        var perChannel: [String: Int] = [:]
        var overflow: [Video] = []
        var pool = longForm
        
        while !pool.isEmpty {
            var pickedIndex: Int? = nil
            for (idx, v) in pool.enumerated() {
                let ch = v.uploader.lowercased()
                let lastCh = result.last?.uploader.lowercased()
                if (perChannel[ch] ?? 0) < 2 && ch != lastCh {
                    pickedIndex = idx
                    break
                }
            }
            guard let idx = pickedIndex else {
                overflow.append(contentsOf: pool)
                break
            }
            let v = pool.remove(at: idx)
            perChannel[v.uploader.lowercased(), default: 0] += 1
            result.append(v)
        }
        
        return result + overflow + shorts + stale
    }
    
    /// Weighted random pick from a ranked interest list (exploit top interests, still explore the tail).
    private func sampleInterests(_ items: [String], count: Int) -> [String] {
        let pool = Array(items.prefix(8))
        guard pool.count > count else { return pool }
        var weighted: [(String, Double)] = pool.enumerated().map { (i, s) in
            (s, Double.random(in: 0..<1) * (1.0 / Double(i + 1)).squareRoot())
        }
        weighted.sort { $0.1 > $1.1 }
        return weighted.prefix(count).map { $0.0 }
    }
    
    /// Multi-stream personalized recommendation engine
    private func fetchPersonalizedMultiStreamFeed(watchedIds: Set<String>) async -> [Video] {
        // Stream 1: Channel Loyalty & Peer Creators (30% weight)
        var stream1Queries: [String] = []
        
        // Favorite watched channels — sampled (not always the same top 2) for feed variety
        for ch in sampleInterests(topChannels, count: 2) {
            stream1Queries.append("\(ch) mới nhất")
            // Peer creators in the same niche
            if let peers = PeerCreatorGraph.findPeers(for: ch) {
                stream1Queries.append("\(peers) mới nhất")
            }
        }
        
        // Subscriptions if available
        let subs = ChannelSubscriptionManager.shared.subscribedChannels
        if !subs.isEmpty && stream1Queries.count < 3 {
            for sub in subs.prefix(2) {
                let q = (sub.handle?.hasPrefix("@") == true) ? sub.handle! : sub.title
                if !stream1Queries.contains(where: { $0.contains(q) }) {
                    stream1Queries.append("\(q) mới nhất")
                }
            }
        }
        
        // Stream 2: Direct Search & Topic Intent (25% weight)
        var stream2Queries: [String] = []
        if let latestSearch = recentSearches.first {
            stream2Queries.append(latestSearch)
        }
        if let topKw = sampleInterests(topKeywords, count: 1).first {
            stream2Queries.append(topKw)
        }
        if stream2Queries.isEmpty && recentSearches.count > 1 {
            stream2Queries.append(recentSearches[1])
        }
        
        // Stream 3: Vietnam Market Trending Blend (25% weight)
        // Dynamically blends what is trending right now in Vietnam with user topics
        var stream3Queries: [String] = []
        let seedKeywords = Array((recentSearches + topKeywords).prefix(3))
        for seed in seedKeywords {
            let matched = VietnamTrendingEngine.queries(for: seed)
            if let first = matched.first, !stream3Queries.contains(first) {
                stream3Queries.append(first)
            }
        }
        // Always inject top viral Vietnam trending queries to catch hot national trends
        for g in VietnamTrendingEngine.generalTrendingQueries {
            if !stream3Queries.contains(g) && stream3Queries.count < 3 {
                stream3Queries.append(g)
            }
        }
        
        // Stream 4: Semantic Ecosystem Expansion & Fresh Discovery (20% weight)
        var stream4Queries: [String] = []
        for seed in seedKeywords {
            let expanded = SemanticClusterEngine.expand(query: seed)
            for exp in expanded {
                if !stream4Queries.contains(exp) && stream4Queries.count < 2 {
                    stream4Queries.append(exp)
                }
            }
            if stream4Queries.count >= 2 { break }
        }
        if stream4Queries.isEmpty {
            stream4Queries = [
                "khám phá công nghệ tương lai việt nam triệu view",
                "ký sự đời sống ẩm thực việt nam triệu view"
            ]
        }
        
        // Assemble target search tasks (2 queries per stream = 8 parallel fast queries)
        let s1 = Array(stream1Queries.prefix(2))
        let s2 = Array(stream2Queries.prefix(2))
        let s3 = Array(stream3Queries.prefix(2))
        let s4 = Array(stream4Queries.prefix(2))
        
        // Stream 0: Item-to-item "Watch Next" graph — YouTube's strongest candidate source.
        // Pull YouTube's own related-video graph for a random sample of recently watched videos.
        let recentWatched = Array(PlayerManager.shared.historyVideos.filter { !$0.isShort }.prefix(8))
        let seedVideos = Array(recentWatched.shuffled().prefix(3))
        async let fetchGraph: [Video] = withTaskGroup(of: [Video].self) { group in
            for seed in seedVideos {
                group.addTask {
                    let rel = await YTDLPService.shared.fetchRelatedVideosViaInnerTube(videoId: seed.id)
                    return Array(rel.filter { !$0.isShort }.prefix(10))
                }
            }
            var all: [[Video]] = []
            for await r in group { all.append(r) }
            // Round-robin across seeds so one seed doesn't dominate
            var merged: [Video] = []
            var idx = 0
            while all.contains(where: { idx < $0.count }) {
                for list in all where idx < list.count { merged.append(list[idx]) }
                idx += 1
            }
            return merged
        }
        
        // Concurrent multi-stream execution
        async let fetchStream1 = fetchBatch(queries: s1, limitPerQuery: 8)
        async let fetchStream2 = fetchBatch(queries: s2, limitPerQuery: 8)
        async let fetchStream3 = fetchBatch(queries: s3, limitPerQuery: 8)
        async let fetchStream4 = fetchBatch(queries: s4, limitPerQuery: 6)
        
        let (v0, v1, v2, v3, v4) = await (fetchGraph, fetchStream1, fetchStream2, fetchStream3, fetchStream4)
        
        // Weighted Interleaving: 2 from S1, 2 from S2, 2 from S3, 1 from S4
        var combined: [Video] = []
        var seenIds = Set<String>()
        
        var i0 = 0, i1 = 0, i2 = 0, i3 = 0, i4 = 0
        let totalCount = v0.count + v1.count + v2.count + v3.count + v4.count
        
        func appendIfValid(_ video: Video) {
            if !seenIds.contains(video.id) && !watchedIds.contains(video.id) {
                seenIds.insert(video.id)
                combined.append(video)
            }
        }
        
        while combined.count < totalCount && (i0 < v0.count || i1 < v1.count || i2 < v2.count || i3 < v3.count || i4 < v4.count) {
            // Pick from Stream 0 (Watch-next graph) — highest weight, like YouTube home
            for _ in 0..<3 {
                if i0 < v0.count { appendIfValid(v0[i0]); i0 += 1 }
            }
            // Pick from Stream 1 (Channel loyalty)
            for _ in 0..<2 {
                if i1 < v1.count { appendIfValid(v1[i1]); i1 += 1 }
            }
            // Pick from Stream 2 (Direct intent)
            for _ in 0..<2 {
                if i2 < v2.count { appendIfValid(v2[i2]); i2 += 1 }
            }
            // Pick from Stream 3 (Vietnam Market Trending)
            if i3 < v3.count { appendIfValid(v3[i3]); i3 += 1 }
            // Pick from Stream 4 (Ecosystem & Discovery)
            if i4 < v4.count { appendIfValid(v4[i4]); i4 += 1 }
            
            // Safety break if no advancement
            if i0 >= v0.count && i1 >= v1.count && i2 >= v2.count && i3 >= v3.count && i4 >= v4.count {
                break
            }
        }
        
        // If results are low, supplement with Vietnam Trending feed
        if combined.count < 12 {
            let fallback = await fetchVietnamTrendingFeed(forceRefresh: false)
            for v in fallback {
                if !seenIds.contains(v.id) && !watchedIds.contains(v.id) {
                    seenIds.insert(v.id)
                    combined.append(v)
                }
            }
        }
        
        return combined
    }
    
    // MARK: - Intelligent Personalized Related Videos Engine
    public func fetchRelatedVideos(for video: Video) async -> [Video] {
        // 1. Try official YouTube InnerTube 'next' recommendation endpoint first (<0.6s)
        var related = await YTDLPService.shared.fetchRelatedVideosViaInnerTube(videoId: video.id)
        
        // 2. Fallback to smart semantic keywords search if next endpoint had 0 results
        if related.isEmpty {
            let keywords = extractKeywordsAndPhrases(from: video.title)
            let query: String
            if !keywords.isEmpty {
                query = "\(video.uploader) \(keywords.prefix(3).joined(separator: " "))"
            } else {
                query = video.title
            }
            let searchPage = await YTDLPService.shared.searchVideosWithContinuation(query: query, limit: 16)
            if !video.isShort && !searchPage.videos.isEmpty {
                // When watching long video, only use regular long videos from search
                related = searchPage.videos
            } else {
                related = searchPage.allItems
            }
            related.removeAll(where: { $0.id == video.id })
        }
        
        // 3. User-Affinity Personalized Re-ranking:
        // Score videos higher if user frequently watches the creator or topic
        if hasPersonalizedProfile && !related.isEmpty {
            let userChannels = Set(topChannels.map { $0.lowercased() })
            let userKws = Set(topKeywords.map { $0.lowercased() })
            
            // YouTube's own position is the primary signal; personal affinity is a light boost.
            // Stable: ties keep YouTube's original order.
            let scored: [(Video, Double)] = related.enumerated().map { (idx, v) in
                var s = -Double(idx) * 0.35
                let up = v.uploader.lowercased()
                if userChannels.contains(up) { s += 2.0 }
                let t = v.title.lowercased()
                var kwHits = 0
                for kw in userKws where t.contains(kw) { kwHits += 1 }
                s += Double(min(kwHits, 2)) * 0.8
                if (impressionCounts[v.id] ?? 0) >= 3 { s -= 3.0 }
                return (v, s)
            }
            related = scored.sorted { $0.1 > $1.1 }.map { $0.0 }
        }
        
        // 4. Format-Aware Separation & Prioritization (Long Video vs Shorts)
        if !video.isShort {
            // When watching a regular long video, ALWAYS place regular videos first!
            let regular = related.filter { !$0.isShort }
            let shorts = related.filter { $0.isShort }
            if !regular.isEmpty {
                return regular + Array(shorts.prefix(2))
            }
        } else {
            // When watching a Short, show other Shorts first
            let shorts = related.filter { $0.isShort }
            let regular = related.filter { !$0.isShort }
            if !shorts.isEmpty {
                return shorts + Array(regular.prefix(4))
            }
        }
        
        return related
    }
    
    private func fetchBatch(queries: [String], limitPerQuery: Int) async -> [Video] {
        guard !queries.isEmpty else { return [] }
        var results: [Video] = []
        await withTaskGroup(of: [Video].self) { group in
            for q in queries {
                group.addTask {
                    return await YTDLPService.shared.searchVideos(query: q, limit: limitPerQuery)
                }
            }
            for await res in group {
                results.append(contentsOf: res)
            }
        }
        return results
    }
    
    /// Detects low-signal music compilations (remix mixes, TikTok playlists, BXH, lofi…) that flood
    /// search results for "triệu view" queries.
    nonisolated public static func isMusicCompilation(_ video: Video) -> Bool {
        let t = video.title.lowercased()
        let ch = video.uploader.lowercased()
        let strong = ["remix", "nonstop", "vinahouse", "nhạc trẻ", "nhạc tiktok", "lofi", "lo-fi",
                      "bxh nhạc", "playlist", "liên khúc", "nhạc hot", "nhạc chill", "mashup",
                      "edm", "bolero", "karaoke", "nhạc hay nhất", "tuyển tập", "album"]
        if strong.contains(where: { t.contains($0) }) { return true }
        if ch.contains(" mix") || ch.hasSuffix("mix") || ch.contains("music") || ch.contains("remix") { return true }
        let musicHint = t.contains("nhạc") || t.contains("music") || t.contains("mv") || t.contains("official")
        return musicHint && video.totalDurationSeconds > 1800
    }
    
    /// True only if the user's own behavior shows interest in music.
    public var userLikesMusic: Bool {
        let words = ["nhạc", "music", "remix", "bài hát", "mv", "lofi", "karaoke", "ca sĩ", "rap", "edm"]
        let signals = (recentSearches + topKeywords + topChannels).map { $0.lowercased() }
        return signals.contains { s in words.contains { s.contains($0) } }
    }
    
    /// Ensure videos in Trending are fresh (within 1 week to 1 month, strictly excluding 2+ months or years old)
    nonisolated public static func isFreshTrendingVideo(_ video: Video) -> Bool {
        guard let pub = video.publishedTime?.lowercased() else { return true }
        
        // Exclude older than 1 month
        if pub.contains("năm") || pub.contains("year") { return false }
        
        let oldIndicators = [
            "2 tháng trước", "3 tháng trước", "4 tháng trước", "5 tháng trước",
            "6 tháng trước", "7 tháng trước", "8 tháng trước", "9 tháng trước",
            "10 tháng trước", "11 tháng trước", "12 tháng trước",
            "2 months ago", "3 months ago", "4 months ago", "5 months ago",
            "6 months ago", "7 months ago", "8 months ago", "9 months ago",
            "10 months ago", "11 months ago", "12 months ago"
        ]
        for indicator in oldIndicators {
            if pub.contains(indicator) { return false }
        }
        return true
    }
    
    /// Multi-pillar Vietnam Trending Feed for instant discovery (Both Long Videos & Shorts within 1 week / 1 month)
    public func fetchVietnamTrendingFeed(forceRefresh: Bool = false) async -> [Video] {
        if !forceRefresh, let last = lastTrendingFetchTime, Date().timeIntervalSince(last) < 1200, !trendingCache.isEmpty {
            return getCachedTrending()
        }
        
        // Core trending pillars — general interest, NOT music (music only if the user actually likes music)
        let likesMusic = userLikesMusic
        var trendingPillars: [(query: String, params: String)] = [
            ("tin tức nóng hôm nay việt nam", YTDLPService.filterThisWeek),
            ("review công nghệ mới nhất việt nam", YTDLPService.filterThisWeek),
            ("vlog giải trí thịnh hành việt nam", YTDLPService.filterThisWeek)
        ]
        if likesMusic {
            trendingPillars.append(("mv ca nhạc mới nhất việt nam", YTDLPService.filterThisWeek))
        }
        
        let shortsPillars: [String] = [
            "shorts trending việt nam viral triệu view"
        ]
        
        var regularStreams: [[Video]] = []
        var shortsCollected: [Video] = []
        
        await withTaskGroup(of: (isShorts: Bool, videos: [Video]).self) { group in
            for p in trendingPillars {
                group.addTask {
                    let res = await YTDLPService.shared.searchVideosWithContinuation(query: p.query, params: p.params, limit: 12)
                    let freshRegular = res.videos.filter {
                        Self.isFreshTrendingVideo($0) && (likesMusic || !Self.isMusicCompilation($0))
                    }
                    return (isShorts: false, videos: freshRegular)
                }
            }
            for sp in shortsPillars {
                group.addTask {
                    // Do not pass upload date filter params: InnerTube removes the Shorts shelf when filters are present!
                    let res = await YTDLPService.shared.searchVideosWithContinuation(query: sp, params: nil, limit: 16)
                    let candidates = res.shorts
                    let freshShorts = candidates.filter { Self.isFreshTrendingVideo($0) }
                    return (isShorts: true, videos: freshShorts)
                }
            }
            
            for await (isShorts, videos) in group {
                if !videos.isEmpty {
                    if isShorts {
                        shortsCollected.append(contentsOf: videos)
                    } else {
                        regularStreams.append(videos)
                    }
                }
            }
        }
        
        var seenIds = Set<String>()
        
        // Interleave regular videos
        let maxLen = regularStreams.map { $0.count }.max() ?? 0
        var regularCombined: [Video] = []
        for i in 0..<maxLen {
            for stream in regularStreams {
                if i < stream.count {
                    let v = stream[i]
                    if !seenIds.contains(v.id) {
                        seenIds.insert(v.id)
                        regularCombined.append(v)
                    }
                }
            }
        }
        
        // Deduplicate shorts
        var cleanShorts: [Video] = []
        for s in shortsCollected {
            if !seenIds.contains(s.id) {
                seenIds.insert(s.id)
                var markedShort = s
                markedShort.isExplicitShort = true
                cleanShorts.append(markedShort)
            }
        }
        
        // Structure final list: Top 6 regular videos -> Up to 14 Shorts -> Remaining regular videos
        var combined: [Video] = []
        let topRegular = Array(regularCombined.prefix(6))
        let remainingRegular = Array(regularCombined.dropFirst(6))
        
        combined.append(contentsOf: topRegular)
        combined.append(contentsOf: cleanShorts.prefix(14))
        combined.append(contentsOf: remainingRegular)
        
        // Failsafe: if combined is still empty (e.g. network hiccup), load base trending
        if combined.isEmpty {
            let fallbackRes = await YTDLPService.shared.searchVideosWithContinuation(query: "top trending việt nam hôm nay", limit: 20)
            combined = fallbackRes.videos
        }
        
        if !combined.isEmpty {
            self.trendingCache = combined
            self.lastTrendingFetchTime = Date()
            if let encoded = try? JSONEncoder().encode(combined) {
                UserDefaults.standard.set(encoded, forKey: self.trendingCacheKey)
            }
        }
        return combined
    }
    
    /// Diverse multi-pillar feed for new users (delegates to Vietnam Trending)
    private func fetchDiverseColdStartFeed() async -> [Video] {
        return await fetchVietnamTrendingFeed(forceRefresh: false)
    }
    
    /// Targeted feed for category pills mapped to Vietnamese high-engagement content
    public func fetchVietnamCategoryFeed(category: String) async -> [Video] {
        let queries = VietnamTrendingEngine.queries(for: category)
        let s = Array(queries.prefix(2))
        return await fetchBatch(queries: s, limitPerQuery: 14)
    }
    
    /// Check if a given chip tag represents a curated Vietnamese content category
    public func isVietnamCategory(_ category: String) -> Bool {
        let lower = category.lowercased()
        return lower.contains("thịnh hành") ||
               lower.contains("nhạc") ||
               lower.contains("giải trí") ||
               lower.contains("show") ||
               lower.contains("công nghệ") ||
               lower.contains("gaming") ||
               lower.contains("game") ||
               lower.contains("trò chơi") ||
               lower.contains("tin tức") ||
               lower.contains("thời sự") ||
               lower.contains("ẩm thực") ||
               lower.contains("du lịch") ||
               lower.contains("bóng đá") ||
               lower.contains("thể thao") ||
               lower.contains("podcast")
    }
}

// MARK: - Semantic Topic & Ecosystem Expansion Engine

private struct SemanticClusterEngine {
    /// Expand a query or keyword into rich ecosystem exploration queries
    static func expand(query: String) -> [String] {
        let q = query.lowercased()
        
        // 1. Apple & iPhone Ecosystem
        if q.contains("iphone") || q.contains("apple") || q.contains("ios") || q.contains("airpod") || q.contains("ipad") {
            return [
                "phụ kiện iphone case ốp lưng sạc magsafe đẹp nhất",
                "hệ sinh thái macbook air pro m3 m4 bàn phím",
                "kính thực tế ảo apple vision pro vr ar trải nghiệm",
                "so sánh camera iphone flagship công nghệ mới"
            ]
        }
        
        // 2. Android & Smartphones
        if q.contains("samsung") || q.contains("galaxy") || q.contains("xiaomi") || q.contains("pixel") || q.contains("oppo") || q.contains("android") {
            return [
                "phụ kiện đồ chơi công nghệ điện thoại thông minh",
                "so sánh hiệu năng camera smartphone flagship mới",
                "smartwatch tai nghe không dây bluetooth chống ồn",
                "đánh giá công nghệ màn hình gập mới nhất"
            ]
        }
        
        // 3. PC, Laptop, Setup & Desk Decor
        if q.contains("laptop") || q.contains("macbook") || q.contains("pc") || q.contains("bàn phím") || q.contains("setup") || q.contains("chuột") {
            return [
                "setup góc làm việc tối giản công nghệ desk setup",
                "bàn phím cơ bluetooth chuột công thái học",
                "đánh giá laptop ultrabook mỏng nhẹ pin trâu",
                "màn hình đồ họa rời góc làm việc hiện đại"
            ]
        }
        
        // 4. VR / AR & Artificial Intelligence (AI)
        if q.contains("vr") || q.contains("ar") || q.contains("vision pro") || q.contains("ai") || q.contains("chatgpt") || q.contains("thực tế ảo") {
            return [
                "kính thực tế ảo VR AR Apple Vision Pro Meta Quest 3",
                "trí tuệ nhân tạo AI đột phá công nghệ mới nhất",
                "đồ chơi công nghệ thông minh tương lai",
                "tiện ích AI thay đổi cuộc sống và công việc"
            ]
        }
        
        // 5. Gaming & Esports
        if q.contains("game") || q.contains("gaming") || q.contains("gta") || q.contains("fifa") || q.contains("lien quan") || q.contains("pubg") || q.contains("wukong") {
            return [
                "highlight khoảnh khắc gaming đỉnh cao hài hước",
                "đánh giá game bom tấn đồ họa đỉnh cao mới nhất",
                "tay cầm máy chơi game console ps5 nintendo switch",
                "tin tức làng game cập nhật mới nhất"
            ]
        }
        
        // 6. Automotive & Electric Vehicles
        if q.contains("xe") || q.contains("ô tô") || q.contains("vinfast") || q.contains("tesla") || q.contains("xe điện") {
            return [
                "trải nghiệm lái thử xe điện thông minh công nghệ mới",
                "phụ kiện đồ chơi xe hơi tiện ích thông minh",
                "so sánh ô tô suv sedan gia đình công nghệ an toàn"
            ]
        }
        
        // 7. Cinema & Movies
        if q.contains("phim") || q.contains("cinema") || q.contains("movie") || q.contains("review phim") {
            return [
                "phân tích phim chi tiết easter egg ý nghĩa ẩn giấu",
                "top phim điện ảnh bom tấn xuất sắc nhất",
                "hậu trường kỹ xảo điện ảnh hollywood hậu trường phim"
            ]
        }
        
        // 8. Travel, Food & Culture
        if q.contains("du lịch") || q.contains("ẩm thực") || q.contains("ăn") || q.contains("món") || q.contains("khoai") {
            return [
                "ẩm thực đường phố ký sự du lịch trải nghiệm",
                "khám phá cảnh đẹp văn hóa đời sống con người",
                "món ngon vùng miền đặc sản việt nam"
            ]
        }
        
        // Generic Tech / Gadget expansion
        return [
            "đồ chơi công nghệ review sản phẩm mới thông minh",
            "top tiện ích thiết bị công nghệ đáng mua nhất"
        ]
    }
    
    /// Suggest dynamic chip tag from keyword
    static func suggestTag(for keyword: String) -> String? {
        let k = keyword.lowercased()
        if k.contains("iphone") || k.contains("apple") {
            return "Hệ sinh thái Apple"
        } else if k.contains("laptop") || k.contains("macbook") || k.contains("setup") {
            return "Setup góc làm việc"
        } else if k.contains("vr") || k.contains("ar") || k.contains("ai") {
            return "Kính VR & AI"
        } else if k.contains("game") || k.contains("gaming") {
            return "Gaming Gear"
        } else if k.contains("xe") || k.contains("ô tô") {
            return "Xe & Công nghệ"
        }
        return nil
    }
}

// MARK: - Peer Creator & Related Channels Graph

private struct PeerCreatorGraph {
    /// Mapping of top creator niches to related creators
    static func findPeers(for channel: String) -> String? {
        let c = channel.lowercased()
        
        // Tech Reviewers
        if c.contains("schannel") || c.contains("duy thẩm") || c.contains("vật vờ") || c.contains("thinkview") || c.contains("tony phùng") || c.contains("relab") || c.contains("hải triều") {
            return "ThinkView Schannel Vật Vờ Studio công nghệ"
        }
        
        // Gaming / Streamers
        if c.contains("mixigaming") || c.contains("cris devil") || c.contains("rambo") || c.contains("bomman") || c.contains("dũng ct") || c.contains("độ mixi") {
            return "MixiGaming Cris Devil Gamer giải trí game"
        }
        
        // Travel / Food
        if c.contains("khoai lang thang") || c.contains("chan la cà") || c.contains("fahoka") || c.contains("ninh titô") {
            return "Khoai Lang Thang Chan La Cà du lịch ẩm thực"
        }
        
        // Cinema
        if c.contains("phê phim") || c.contains("w2w") || c.contains("cuồng phim") {
            return "Phê Phim W2W Movie review phim điện ảnh"
        }
        
        // News
        if c.contains("vtv24") || c.contains("thanh niên") || c.contains("tuổi trẻ") || c.contains("vnexpress") {
            return "VTV24 Chuyển động 24h tin tức thời sự"
        }
        
        // Science & Knowledge
        if c.contains("monster box") || c.contains("spiderum") || c.contains("dế mèn") {
            return "Monster Box Spiderum kiến thức khoa học đời sống"
        }
        
        return nil
    }
}

// MARK: - Vietnam Trending Intelligence Engine

public struct VietnamTrendingEngine {
    /// Core trending queries across Vietnam
    public static let generalTrendingQueries = [
        "tin tức nóng hôm nay việt nam",
        "vlog giải trí thịnh hành việt nam",
        "review công nghệ mới nhất việt nam"
    ]
    
    public static let musicTrendingQueries = [
        "bài hát thịnh hành mới nhất việt nam triệu view",
        "top trending âm nhạc việt nam",
        "mv ca nhạc mới nhất việt nam triệu view"
    ]
    
    public static let entertainmentTrendingQueries = [
        "gameshow việt nam triệu view thịnh hành",
        "rap việt anh trai say hi 2 ngày 1 đêm mới nhất",
        "show giải trí hot nhất việt nam triệu view"
    ]
    
    public static let techTrendingQueries = [
        "review công nghệ việt nam vật vờ schannel mới nhất",
        "đánh giá điện thoại laptop mới thịnh hành việt nam",
        "đồ chơi công nghệ thông minh mới nhất"
    ]
    
    public static let gamingTrendingQueries = [
        "mixigaming cris devil gamer highlight mới nhất",
        "gameplay bom tấn việt nam highlight",
        "gaming việt nam triệu view mới nhất"
    ]
    
    public static let newsTrendingQueries = [
        "vtv24 chuyển động 24h tin tức thời sự việt nam mới nhất",
        "thời sự việt nam hôm nay nóng nhất",
        "tin tức đời sống xã hội việt nam 24h"
    ]
    
    public static let foodAndTravelTrendingQueries = [
        "khoai lang thang chan la cà du lịch ẩm thực việt nam",
        "ẩm thực đường phố khám phá việt nam triệu view",
        "món ngon vùng miền đặc sản việt nam"
    ]
    
    public static let sportsTrendingQueries = [
        "bóng đá việt nam highlight mới nhất",
        "v-league đội tuyển việt nam mới nhất",
        "thể thao việt nam highlight"
    ]
    
    public static let podcastTrendingQueries = [
        "podcast việt nam triệu view hay nhất",
        "phê phim spiderum vietcetera podcast mới nhất",
        "talkshow phỏng vấn nhân vật truyền cảm hứng"
    ]
    
    /// Maps a search topic or category title to targeted Vietnam trending queries
    public static func queries(for category: String) -> [String] {
        let lower = category.lowercased()
        if lower.contains("thịnh hành") || lower.contains("trending") {
            return generalTrendingQueries
        } else if lower.contains("nhạc") || lower.contains("music") || lower.contains("bài hát") {
            return musicTrendingQueries
        } else if lower.contains("giải trí") || lower.contains("show") || lower.contains("hài") {
            return entertainmentTrendingQueries
        } else if lower.contains("công nghệ") || lower.contains("tech") || lower.contains("điện thoại") || lower.contains("laptop") {
            return techTrendingQueries
        } else if lower.contains("game") || lower.contains("trò chơi") || lower.contains("gaming") {
            return gamingTrendingQueries
        } else if lower.contains("tin tức") || lower.contains("thời sự") || lower.contains("tin") {
            return newsTrendingQueries
        } else if lower.contains("ẩm thực") || lower.contains("du lịch") || lower.contains("ăn") || lower.contains("món") {
            return foodAndTravelTrendingQueries
        } else if lower.contains("bóng đá") || lower.contains("thể thao") {
            return sportsTrendingQueries
        } else if lower.contains("podcast") || lower.contains("phim") {
            return podcastTrendingQueries
        }
        return ["\(category) việt nam mới nhất", "\(category) triệu view"]
    }
}

// MARK: - Search Expansion & Related Queries Intelligence

extension RecommendationService {
    /// Fetches rich related queries for a given search query (simulating YouTube's search expansion)
    public func fetchRelatedSearchQueries(for query: String) async -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        // 1. Fetch suggestions for query with trailing space (YouTube's next-word completion)
        async let nextWordSuggestions = YTDLPService.shared.fetchSearchSuggestions(query: "\(trimmed) ")
        // 2. Fetch direct suggestions
        async let directSuggestions = YTDLPService.shared.fetchSearchSuggestions(query: trimmed)
        
        let (nw, direct) = await (nextWordSuggestions, directSuggestions)
        
        let combined = nw + direct
        var results: [String] = []
        var seen = Set<String>()
        let lowerQuery = trimmed.lowercased()
        
        for item in combined {
            let clean = item.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = clean.lowercased()
            if lower != lowerQuery && !seen.contains(lower) && clean.count > 2 {
                seen.insert(lower)
                results.append(clean)
            }
        }
        
        // If results are few, append smart topical expansions
        if results.count < 4 {
            let templates = ["mới nhất", "hay nhất", "remix", "full", "review"]
            for t in templates {
                let candidate = "\(trimmed) \(t)"
                if !seen.contains(candidate.lowercased()) {
                    results.append(candidate)
                    seen.insert(candidate.lowercased())
                }
            }
        }
        
        return Array(results.prefix(8))
    }
    
    /// Generates short contextual topic refinement chips (e.g. for "nhạc chill": ["Không lời", "Tiktok", "Học bài", "Mới nhất", "Dễ ngủ"])
    public func fetchContextualSearchChips(for query: String) async -> [String] {
        let related = await fetchRelatedSearchQueries(for: query)
        var chips: [String] = []
        var seen = Set<String>()
        let lowerQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        for item in related {
            var suffix = item
            if suffix.lowercased().hasPrefix(lowerQuery) {
                suffix = String(suffix.dropFirst(lowerQuery.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Strip leading dashes or punctuation
            suffix = suffix.trimmingCharacters(in: CharacterSet(charactersIn: "-•|:"))
            let clean = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = clean.lowercased()
            if clean.count >= 2 && clean.count <= 24 && !seen.contains(lower) {
                seen.insert(lower)
                let capitalized = clean.prefix(1).uppercased() + clean.dropFirst()
                chips.append(capitalized)
            }
        }
        
        // Always add "Mới nhất" if not present
        if !seen.contains("mới nhất") {
            chips.append("Mới nhất")
        }
        
        return Array(chips.prefix(8))
    }
    
    /// Re-ranks search results to boost creators and topics the user has demonstrated affinity for
    public func rankSearchResults(videos: [Video], query: String) -> [Video] {
        guard !videos.isEmpty else { return [] }
        let channelCounts = UserDefaults.standard.dictionary(forKey: channelsKey) as? [String: Int] ?? [:]
        let topicCounts = UserDefaults.standard.dictionary(forKey: topicsKey) as? [String: Int] ?? [:]
        let subManager = ChannelSubscriptionManager.shared
        
        // Calculate personalization score for each video
        let scored = videos.map { video -> (video: Video, score: Double) in
            var score: Double = 0.0
            
            // Subscribed channels get a strong boost
            if subManager.isSubscribed(video.uploader) {
                score += 15.0
            }
            
            // Frequently watched channels get proportional boost
            if let count = channelCounts[video.uploader] {
                score += min(12.0, Double(count) * 2.5)
            }
            
            // Matching user topic keywords
            let keywords = extractKeywordsAndPhrases(from: video.title)
            for kw in keywords {
                if let count = topicCounts[kw] {
                    score += min(4.0, Double(count) * 0.8)
                }
            }
            
            return (video, score)
        }
        
        // Stable sort: higher score floats toward top while preserving original relevance order
        let sorted = scored.sorted { a, b in
            if abs(a.score - b.score) >= 3.0 {
                return a.score > b.score
            }
            return false // Preserve original search ranking order
        }
        
        return sorted.map { $0.video }
    }
}
