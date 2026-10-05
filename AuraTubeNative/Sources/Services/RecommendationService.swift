import Foundation
import SwiftUI

@MainActor
public final class RecommendationService: ObservableObject {
    public static let shared = RecommendationService()
    
    private let channelsKey = "auratube_user_channel_affinity_v1"
    private let topicsKey = "auratube_user_topic_affinity_v2"
    private let decayStampKey = "auratube_affinity_last_decay_v1"
    private let homeFeedCacheKey = "auratube_home_feed_cache_v1"
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
        loadProfile()
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
    
    // MARK: - Affinity Profile (time-decayed)
    
    /// Channel / topic affinity scores. Kept in memory and decayed over time so the feed follows
    /// what the user is into *now* instead of locking onto whatever they watched most months ago.
    private var channelAffinity: [String: Double] = [:]
    private var topicAffinity: [String: Double] = [:]
    private var persistProfileWork: DispatchWorkItem?
    
    private func loadProfile() {
        func load(_ key: String) -> [String: Double] {
            (UserDefaults.standard.dictionary(forKey: key) ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
        }
        channelAffinity = load(channelsKey)
        topicAffinity = load(topicsKey)
        
        // Exponential decay: channel half-life 30 days, topic half-life 14 days
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: decayStampKey)
        guard last > 0 else {
            UserDefaults.standard.set(now, forKey: decayStampKey)
            return
        }
        let days = (now - last) / 86400
        guard days >= 1 else { return }
        let channelFactor = pow(0.5, days / 30)
        let topicFactor = pow(0.5, days / 14)
        channelAffinity = channelAffinity.mapValues { $0 * channelFactor }.filter { $0.value >= 0.25 }
        topicAffinity = topicAffinity.mapValues { $0 * topicFactor }.filter { $0.value >= 0.25 }
        UserDefaults.standard.set(now, forKey: decayStampKey)
        persistProfile()
    }
    
    private func persistProfile() {
        persistProfileWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            UserDefaults.standard.set(self.channelAffinity, forKey: self.channelsKey)
            UserDefaults.standard.set(self.topicAffinity, forKey: self.topicsKey)
        }
        persistProfileWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }
    
    private func bump(_ dict: inout [String: Double], key: String, by delta: Double) {
        let value = (dict[key] ?? 0) + delta
        if value <= 0.05 {
            dict.removeValue(forKey: key)
        } else {
            dict[key] = min(value, 60)
        }
    }
    
    /// Applies one engagement signal (positive or negative) to the channel and topics of a video.
    private func applySignal(video: Video, weight: Double) {
        let uploader = video.uploader.trimmingCharacters(in: .whitespacesAndNewlines)
        if !uploader.isEmpty && uploader.lowercased() != "youtube" && uploader.lowercased() != "youtube shorts" {
            bump(&channelAffinity, key: uploader, by: weight)
            if weight > 0, let avatar = video.channelAvatarUrl, !avatar.isEmpty {
                setChannelAvatar(for: uploader, url: avatar)
            }
        }
        for kw in extractKeywordsAndPhrases(from: video.title) {
            bump(&topicAffinity, key: kw, by: weight)
        }
        persistProfile()
    }
    
    // MARK: - Signal Collection & Tracking
    
    /// Bootstrap the profile from existing watch history (only when there is nothing learned yet —
    /// re-adding the whole history on every launch would inflate the scores).
    public func syncFromExistingHistory(_ videos: [Video]) {
        guard !videos.isEmpty else { return }
        for v in videos {
            if let avatar = v.channelAvatarUrl, !avatar.isEmpty {
                setChannelAvatar(for: v.uploader, url: avatar)
            }
        }
        let needsChannels = channelAffinity.isEmpty
        let needsTopics = topicAffinity.isEmpty
        if needsChannels || needsTopics {
            for (idx, v) in videos.enumerated() {
                let weight = idx < 15 ? 1.0 : 0.5
                let uploader = v.uploader.trimmingCharacters(in: .whitespacesAndNewlines)
                if needsChannels, !uploader.isEmpty, uploader.lowercased() != "youtube", uploader.lowercased() != "youtube shorts" {
                    bump(&channelAffinity, key: uploader, by: weight)
                }
                if needsTopics {
                    for kw in extractKeywordsAndPhrases(from: v.title) {
                        bump(&topicAffinity, key: kw, by: weight)
                    }
                }
            }
            persistProfile()
        }
        refreshProfileMetrics()
    }
    
    /// Record a video watch event (a click — the weakest positive signal)
    public func recordWatch(video: Video, saveImmediately: Bool = true) {
        applySignal(video: video, weight: 1.0)
        if saveImmediately {
            refreshProfileMetrics()
        }
    }
    
    /// Record high-retention watch completion (> 50% or finished) with enhanced signal weight
    public func recordWatchCompletion(video: Video) {
        applySignal(video: video, weight: 2.0)
        refreshProfileMetrics()
    }
    
    /// Record a quick abandon (clicked, then left within seconds): cancels the click and counts
    /// slightly against the channel/topic, like YouTube's "not satisfied" watch-time signal.
    public func recordSkip(video: Video) {
        applySignal(video: video, weight: -1.5)
        impressionCounts[video.id, default: 0] += 3
        refreshProfileMetrics()
    }
    
    /// Record bookmark as high explicit affinity
    public func recordBookmark(video: Video) {
        recordWatchCompletion(video: video)
    }
    
    /// Reset learned preferences
    public func resetLearnedPreferences() {
        persistProfileWork?.cancel()
        channelAffinity = [:]
        topicAffinity = [:]
        impressionCounts = [:]
        UserDefaults.standard.removeObject(forKey: channelsKey)
        UserDefaults.standard.removeObject(forKey: topicsKey)
        UserDefaults.standard.removeObject(forKey: searchesKey)
        UserDefaults.standard.removeObject(forKey: homeFeedCacheKey)
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
        
        // Boost keywords and the search phrase itself (explicit intent = strong signal)
        bump(&topicAffinity, key: trimmed.lowercased(), by: 3)
        for kw in extractKeywordsAndPhrases(from: trimmed) where kw != trimmed.lowercased() {
            bump(&topicAffinity, key: kw, by: 2)
        }
        persistProfile()
        
        refreshProfileMetrics()
    }
    
    public func refreshProfileMetrics() {
        let sortedChannels = channelAffinity.sorted(by: { $0.value > $1.value }).map { $0.key }
        self.topChannels = Array(sortedChannels.prefix(8))
        
        let sortedTopics = topicAffinity.sorted(by: { $0.value > $1.value }).map { $0.key }
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
    
    private static let keywordStopWords: Set<String> = [
        "và", "của", "các", "những", "cho", "trong", "với", "tập", "full", "video",
        "official", "lyrics", "audio", "nhạc", "bài", "hát", "trailer", "teaser",
        "preview", "review", "mới", "nhất", "hôm", "nay", "2024", "2025", "2026",
        "hd", "4k", "vietsub", "thuyết", "minh", "lồng", "tiếng", "trên", "tại",
        "một", "người", "được", "không", "này", "khi", "làm", "thế", "nào", "gì",
        "hay", "cực", "quá", "về", "như", "đã", "có", "sẽ", "phải", "đến", "chính",
        "thức", "bởi", "từ", "nhiều", "lại", "ra", "vào", "ngày", "năm", "tháng",
        "là", "thì", "mà", "để", "rồi", "cũng", "rất", "sau", "trước", "nhưng", "vì",
        "the", "and", "for", "with", "you", "this", "that", "from", "how", "what",
        "shorts", "short", "part", "ep", "live", "new"
    ]
    
    /// Extracts topic keys from a title. Vietnamese words are mostly two syllables, so single
    /// syllables ("công", "thẩm") carry no meaning — topics are therefore adjacent-word phrases,
    /// plus standalone Latin words (brands / English terms such as "iphone", "macbook").
    private func extractKeywordsAndPhrases(from text: String) -> [String] {
        let stopWords = Self.keywordStopWords
        func isMeaningful(_ token: String) -> Bool {
            token.count >= 2 && !stopWords.contains(token) && Double(token) == nil
        }
        
        // Split on punctuation first so a phrase never straddles "|", "-", ":" …
        let separators = CharacterSet(charactersIn: "|-–—:·•,.!?()[]{}\"“”/\\#")
        let segments = text.precomposedStringWithCanonicalMapping.lowercased().components(separatedBy: separators)
        
        var results = Set<String>()
        for segment in segments {
            let cleaned = segment.replacingOccurrences(of: "[^a-z0-9à-ỹ\\s]", with: " ", options: .regularExpression)
            let tokens = cleaned.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            for (i, token) in tokens.enumerated() {
                guard isMeaningful(token) else { continue }
                let isLatin = token.allSatisfy { $0.isASCII }
                if isLatin && token.count >= 4 {
                    results.insert(token)
                }
                guard i + 1 < tokens.count else { continue }
                let next = tokens[i + 1]
                if isMeaningful(next) || (isLatin && token.count >= 3 && Double(next) != nil) {
                    results.insert("\(token) \(next)")
                }
            }
        }
        return Array(results)
    }
    
    // MARK: - Smart Recommendation Algorithm
    //
    // Modeled on YouTube's two-stage recommender:
    //   1. Candidate generation — several independent sources (watch-next graph of recent watches,
    //      subscriptions, favourite channels, topic intent, trending, ecosystem exploration).
    //   2. Ranking — one score per candidate from source strength, co-occurrence across sources,
    //      time-decayed channel/topic affinity, freshness, popularity and impression fatigue.
    //   3. Re-ranking — greedy diversity pass (channel + topic spread, reserved exploration slots).
    
    private enum CandidateSource {
        case graph, subscription, channel, topic, trending, explore
        
        var prior: Double {
            switch self {
            case .graph: return 3.0
            case .subscription: return 2.0
            case .channel: return 2.2
            case .topic: return 2.0
            case .trending: return 1.2
            case .explore: return 1.0
            }
        }
        
        var isDiscovery: Bool { self == .trending || self == .explore }
    }
    
    private struct Candidate {
        var video: Video
        var source: CandidateSource
        var rank: Int
        var hits: Int
    }
    
    /// Home feed ("Tất cả"): personalized when there is a profile, trending-based otherwise.
    public enum HomeFeedFilter {
        case all
        /// Uploaded within the last week
        case recentlyUploaded
        /// From channels the user has never watched and is not subscribed to
        case newToYou
    }
    
    public func fetchRecommendations(filter: HomeFeedFilter) async -> [Video] {
        guard filter != .all else { return await fetchRecommendations() }
        refreshProfileMetrics()
        let watchedIds = Set(PlayerManager.shared.historyVideos.prefix(200).map { $0.id })
        var candidates = hasPersonalizedProfile ? await gatherPersonalizedCandidates(excluded: watchedIds) : []
        let trending = await fetchVietnamTrendingFeed(forceRefresh: false)
        let known = Set(candidates.map { $0.video.id })
        candidates += mergeCandidates([(.trending, trending)], excluded: watchedIds.union(known))
        
        switch filter {
        case .recentlyUploaded:
            candidates = candidates.filter { (Self.ageInDays($0.video.publishedTime) ?? 999) <= 7 }
        case .newToYou:
            let watchedChannels = Set(PlayerManager.shared.historyVideos.map { $0.uploader.lowercased() })
            candidates = candidates.filter { c in
                let channel = c.video.uploader.trimmingCharacters(in: .whitespacesAndNewlines)
                return channelAffinity[channel] == nil
                    && !watchedChannels.contains(channel.lowercased())
                    && !ChannelSubscriptionManager.shared.isSubscribed(channel)
            }
        case .all:
            break
        }
        return rankAndDiversify(candidates, limit: 60)
    }
    
    public func fetchRecommendations() async -> [Video] {
        refreshProfileMetrics()
        
        let watchedIds = Set(PlayerManager.shared.historyVideos.prefix(200).map { $0.id })
        
        var candidates: [Candidate]
        if hasPersonalizedProfile {
            candidates = await gatherPersonalizedCandidates(excluded: watchedIds)
        } else {
            candidates = []
        }
        if candidates.filter({ !$0.video.isShort }).count < 12 {
            let trending = await fetchVietnamTrendingFeed(forceRefresh: false)
            let known = Set(candidates.map { $0.video.id })
            candidates += mergeCandidates([(.trending, trending)], excluded: watchedIds.union(known))
        }
        
        let ranked = rankAndDiversify(candidates, limit: 72)
        recordImpressions(ranked.prefix(24))
        if !ranked.isEmpty, let data = try? JSONEncoder().encode(Array(ranked.prefix(48))) {
            UserDefaults.standard.set(data, forKey: homeFeedCacheKey)
        }
        return ranked
    }
    
    /// Last computed home feed, for an instant first render before the fresh one arrives.
    public func getCachedRecommendations() -> [Video] {
        guard let data = UserDefaults.standard.data(forKey: homeFeedCacheKey),
              let cached = try? JSONDecoder().decode([Video].self, from: data) else { return [] }
        let watched = Set(PlayerManager.shared.historyVideos.prefix(200).map { $0.id })
        return cached.filter { !watched.contains($0.id) }
    }
    
    /// Next page for an endless home feed: expands the watch-next graph from what is already on
    /// screen (plus one history seed), then ranks with the same scorer so it stays on-taste.
    public func fetchMoreRecommendations(shown: [Video]) async -> [Video] {
        let longShown = shown.filter { !$0.isShort }
        let history = PlayerManager.shared.historyVideos.filter { !$0.isShort }
        
        var seeds: [Video] = []
        seeds += longShown.suffix(12).shuffled().prefix(2)
        seeds += longShown.prefix(12).shuffled().prefix(1)
        seeds += history.prefix(20).shuffled().prefix(1)
        var seenSeeds = Set<String>()
        seeds = seeds.filter { seenSeeds.insert($0.id).inserted }
        guard !seeds.isEmpty else { return [] }
        
        let lists = await relatedLists(for: seeds, perSeed: 18)
        let excluded = Set(shown.map { $0.id }).union(history.prefix(200).map { $0.id })
        let candidates = mergeCandidates(lists.map { (CandidateSource.graph, $0) }, excluded: excluded)
        let ranked = rankAndDiversify(candidates, limit: 36).filter { !$0.isShort }
        recordImpressions(ranked.prefix(12))
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
    
    // MARK: - Candidate Generation
    
    private func relatedLists(for seeds: [Video], perSeed: Int) async -> [[Video]] {
        await withTaskGroup(of: [Video].self) { group in
            for seed in seeds {
                let seedId = seed.id
                group.addTask {
                    let related = await YTDLPService.shared.fetchRelatedVideosViaInnerTube(videoId: seedId)
                    return Array(related.prefix(perSeed))
                }
            }
            var all: [[Video]] = []
            for await list in group where !list.isEmpty { all.append(list) }
            return all
        }
    }
    
    private func searchLists(queries: [String], limitPerQuery: Int) async -> [[Video]] {
        await withTaskGroup(of: [Video].self) { group in
            for q in queries {
                group.addTask {
                    await YTDLPService.shared.searchVideos(query: q, limit: limitPerQuery)
                }
            }
            var all: [[Video]] = []
            for await list in group where !list.isEmpty { all.append(list) }
            return all
        }
    }
    
    /// Merges source lists into unique candidates. A video surfaced by several sources/seeds keeps
    /// its strongest source and counts the extra hits (co-visitation = strong relevance evidence).
    private func mergeCandidates(_ streams: [(CandidateSource, [Video])], excluded: Set<String>) -> [Candidate] {
        var byId: [String: Candidate] = [:]
        var order: [String] = []
        for (source, videos) in streams {
            for (rank, video) in videos.enumerated() where !excluded.contains(video.id) {
                if var existing = byId[video.id] {
                    existing.hits += 1
                    if source.prior > existing.source.prior { existing.source = source }
                    existing.rank = min(existing.rank, rank)
                    byId[video.id] = existing
                } else {
                    byId[video.id] = Candidate(video: video, source: source, rank: rank, hits: 1)
                    order.append(video.id)
                }
            }
        }
        return order.compactMap { byId[$0] }
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
    
    private func gatherPersonalizedCandidates(excluded: Set<String>) async -> [Candidate] {
        // Source 1 — watch-next graph. Seeds are recency-weighted: the latest watch always counts,
        // the rest are sampled so every refresh explores a different part of the history.
        let history = PlayerManager.shared.historyVideos.filter { !$0.isShort }
        var seeds: [Video] = []
        seeds += history.prefix(1)
        seeds += history.dropFirst().prefix(5).shuffled().prefix(2)
        seeds += history.dropFirst(6).prefix(20).shuffled().prefix(2)
        
        // Source 2 — favourite channels (and known peer creators in the same niche)
        var channelQueries: [String] = []
        for ch in sampleInterests(topChannels, count: 2) {
            channelQueries.append("\(ch) mới nhất")
            if channelQueries.count < 3, let peers = PeerCreatorGraph.findPeers(for: ch) {
                channelQueries.append("\(peers) mới nhất")
            }
        }
        
        // Source 3 — topic intent: the latest search plus sampled learned topics
        var topicQueries: [String] = []
        if let latestSearch = recentSearches.first {
            topicQueries.append(latestSearch)
        }
        for kw in sampleInterests(topKeywords, count: 2) where !topicQueries.contains(where: { $0.caseInsensitiveCompare(kw) == .orderedSame }) {
            topicQueries.append(kw)
        }
        
        // Source 4 — exploration: adjacent ecosystems of the user's interests (no generic filler)
        var exploreQueries: [String] = []
        for seed in (recentSearches + topKeywords).prefix(4) {
            if let expanded = SemanticClusterEngine.expand(query: seed).randomElement(), !exploreQueries.contains(expanded) {
                exploreQueries.append(expanded)
            }
            if exploreQueries.count >= 2 { break }
        }
        
        if userLikesMusic, let musicQuery = VietnamTrendingEngine.musicTrendingQueries.randomElement() {
            topicQueries.append(musicQuery)
        }
        
        let graphSeeds = seeds
        let channelQ = Array(channelQueries.prefix(3))
        let topicQ = Array(topicQueries.prefix(4))
        let exploreQ = exploreQueries
        async let graphTask = relatedLists(for: graphSeeds, perSeed: 16)
        async let channelTask = searchLists(queries: channelQ, limitPerQuery: 8)
        async let topicTask = searchLists(queries: topicQ, limitPerQuery: 10)
        async let exploreTask = searchLists(queries: exploreQ, limitPerQuery: 8)
        async let trendingTask = fetchVietnamTrendingFeed(forceRefresh: false)
        
        let (graph, channels, topics, explore, trending) = await (graphTask, channelTask, topicTask, exploreTask, trendingTask)
        
        // Source 5 — newest uploads from subscriptions (already fetched by the Following tab)
        let subscriptionFeed = Array(ChannelSubscriptionManager.shared.feedVideos.prefix(24))
        
        var streams: [(CandidateSource, [Video])] = []
        streams += graph.map { (.graph, $0) }
        streams.append((.subscription, subscriptionFeed))
        streams += channels.map { (.channel, $0) }
        streams += topics.map { (.topic, $0) }
        streams += explore.map { (.explore, $0) }
        streams.append((.trending, trending))
        return mergeCandidates(streams, excluded: excluded)
    }
    
    // MARK: - Ranking
    
    /// Approximate age in days from YouTube's relative date text ("3 ngày trước", "2 weeks ago").
    nonisolated static func ageInDays(_ published: String?) -> Double? {
        guard let p = published?.lowercased(),
              let match = p.range(of: "\\d+", options: .regularExpression),
              let n = Double(p[match]) else { return nil }
        if p.contains("giây") || p.contains("second") || p.contains("phút") || p.contains("minute") || p.contains("giờ") || p.contains("hour") {
            return 0.2
        }
        if p.contains("ngày") || p.contains("day") { return n }
        if p.contains("tuần") || p.contains("week") { return n * 7 }
        if p.contains("tháng") || p.contains("month") { return n * 30 }
        if p.contains("năm") || p.contains("year") { return n * 365 }
        return nil
    }
    
    private func score(_ c: Candidate, keywords: Set<String>) -> Double {
        let v = c.video
        var s = c.source.prior
        
        // Position inside its own source list, and agreement between sources/seeds
        s -= 0.05 * Double(min(c.rank, 20))
        s += 1.2 * Double(min(c.hits - 1, 3))
        
        // Channel affinity (log-damped so one binge doesn't own the feed)
        let uploader = v.uploader.trimmingCharacters(in: .whitespacesAndNewlines)
        if let aff = channelAffinity[uploader] {
            s += min(2.5, log2(1 + aff) * 0.9)
        }
        if ChannelSubscriptionManager.shared.isSubscribed(uploader) {
            s += 0.4
        }
        
        // Topic affinity
        var topic = 0.0
        for kw in keywords {
            if let aff = topicAffinity[kw] { topic += 0.5 * log2(1 + aff) }
        }
        s += min(2.0, topic)
        
        // Freshness: a real YouTube home feed is ~80% videos from the last week and has
        // almost nothing older than a few months
        if let age = Self.ageInDays(v.publishedTime) {
            switch age {
            case ..<2: s += 1.6
            case ..<7: s += 1.3
            case ..<30: s += 0.6
            case ..<90: break
            case ..<365: s -= 0.5
            case ..<1095: s -= 0.9
            default: s -= 1.2
            }
        }
        
        // Popularity only guards against dead uploads; it saturates at ~100K views so
        // mid-size creators that match the user's taste are not outranked by viral videos
        if let views = v.viewCount, views > 0 {
            s += max(-0.3, min(0.3, (log10(Double(views)) - 4) * 0.3))
        }
        
        // Length: home feeds are dominated by 5–60 minute videos
        let seconds = v.totalDurationSeconds
        if seconds > 0 && !v.isShort {
            if seconds < 300 {
                s -= 0.5
            } else if seconds <= 3600 {
                s += 0.2
            }
        }
        
        // Impression fatigue: shown before but never clicked
        let impressions = impressionCounts[v.id] ?? 0
        s -= 0.9 * Double(min(impressions, 2))
        if impressions >= 3 { s -= 3.0 }
        
        // Small jitter so two refreshes are never identical
        s += Double.random(in: 0..<0.6)
        return s
    }
    
    /// Scores every candidate, then greedily builds the feed: each pick is the best remaining
    /// item after penalising repeated channels and near-duplicate topics among recent picks.
    /// Every 6th slot favours a discovery item so the feed never collapses into one bubble.
    private func rankAndDiversify(_ candidates: [Candidate], limit: Int) -> [Video] {
        let likesMusic = userLikesMusic
        struct Scored {
            let candidate: Candidate
            let keywords: Set<String>
            let score: Double
        }
        let scored: [Scored] = candidates
            .filter { likesMusic || !Self.isMusicCompilation($0.video) }
            .map { c in
                let kws = Set(extractKeywordsAndPhrases(from: c.video.title))
                return Scored(candidate: c, keywords: kws, score: score(c, keywords: kws))
            }
            .sorted { $0.score > $1.score }
        
        let shorts = scored.filter { $0.candidate.video.isShort }.map { $0.candidate.video }
        var remaining = scored.filter { !$0.candidate.video.isShort }
        
        var picked: [Scored] = []
        var perChannel: [String: Int] = [:]
        
        while !remaining.isEmpty && picked.count < limit {
            let recent = picked.suffix(3)
            let recentChannels = Set(recent.map { $0.candidate.video.uploader.lowercased() })
            let wantsDiscovery = picked.count % 6 == 5
            // Music lovers get roughly every fourth slot as music (mixes, playlists, MVs) and
            // no more than that, instead of leaving the share to chance
            let wantsMusic = likesMusic && picked.count % 4 == 2
            let isFirstScreen = picked.count < 24
            
            var bestIndex = 0
            var bestValue = -Double.infinity
            for (i, item) in remaining.prefix(48).enumerated() {
                var value = item.score
                let channel = item.candidate.video.uploader.lowercased()
                let count = perChannel[channel] ?? 0
                value -= Double(count) * 1.5
                // No channel twice on the first screen; at most three overall
                if count >= (isFirstScreen ? 1 : 3) { value -= 100 }
                if likesMusic {
                    let isMusic = Self.isMusicVideo(item.candidate.video)
                    if wantsMusic && isMusic { value += 2.5 }
                    if !wantsMusic && isMusic { value -= 1.5 }
                }
                if recentChannels.contains(channel) { value -= 2.5 }
                if !item.keywords.isEmpty {
                    for other in recent where !other.keywords.isEmpty {
                        let overlap = Double(item.keywords.intersection(other.keywords).count)
                        let union = Double(item.keywords.union(other.keywords).count)
                        if overlap / union > 0.4 { value -= 1.0 }
                    }
                }
                if wantsDiscovery && item.candidate.source.isDiscovery { value += 2.0 }
                if value > bestValue {
                    bestValue = value
                    bestIndex = i
                }
            }
            let choice = remaining.remove(at: bestIndex)
            perChannel[choice.candidate.video.uploader.lowercased(), default: 0] += 1
            picked.append(choice)
        }
        
        return picked.map { $0.candidate.video } + shorts
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
    
    /// More related videos once the list is exhausted: second hop of the watch-next graph,
    /// seeded from the top of what is already listed.
    public func fetchMoreRelatedVideos(for video: Video, shown: [Video]) async -> [Video] {
        let pool = shown.filter { $0.isShort == video.isShort }
        let seeds = Array(pool.prefix(8).shuffled().prefix(2))
        guard !seeds.isEmpty else { return [] }
        let lists = await relatedLists(for: seeds, perSeed: 20)
        var excluded = Set(shown.map { $0.id })
        excluded.insert(video.id)
        let candidates = mergeCandidates(lists.map { (CandidateSource.graph, $0) }, excluded: excluded)
        return rankAndDiversify(candidates, limit: 24).filter { $0.isShort == video.isShort }
    }
    
    /// Autoplay target: the best related long-form video the user has not just watched
    /// (prevents A → B → A ping-pong loops).
    public func pickUpNext(from related: [Video], current: Video) -> Video? {
        let recentlyWatched = Set(PlayerManager.shared.historyVideos.prefix(30).map { $0.id })
        let pool = related.filter { $0.id != current.id && $0.isShort == current.isShort }
        return pool.first(where: { !recentlyWatched.contains($0.id) })
            ?? pool.first
            ?? related.first(where: { $0.id != current.id })
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
    
    /// Music content in general (MVs, live sets, playlists, mixes), not only compilations.
    nonisolated public static func isMusicVideo(_ video: Video) -> Bool {
        if isMusicCompilation(video) { return true }
        let t = video.title.lowercased()
        let hints = ["official mv", "music video", " mv ", "lyrics", "lyric video", "acoustic",
                     "nhạc", "bài hát", "ca khúc", "medley", "fancam", "concert", "liveshow"]
        return hints.contains { t.contains($0) }
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
        
        // No known ecosystem: no expansion (never pad the feed with unrelated filler)
        return []
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
        let channelCounts = channelAffinity
        let topicCounts = topicAffinity
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
                score += min(12.0, count * 2.5)
            }
            
            // Matching user topic keywords
            let keywords = extractKeywordsAndPhrases(from: video.title)
            for kw in keywords {
                if let count = topicCounts[kw] {
                    score += min(4.0, count * 0.8)
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
