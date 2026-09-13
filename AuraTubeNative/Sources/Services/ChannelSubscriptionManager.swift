import Foundation
import SwiftUI

@MainActor
public final class ChannelSubscriptionManager: ObservableObject {
    public static let shared = ChannelSubscriptionManager()
    
    private let userDefaultsKey = "auratube_subscribed_channels_v1"
    
    @Published public private(set) var subscribedChannels: [ChannelInfo] = []
    @Published public private(set) var feedVideos: [Video] = []
    @Published public private(set) var isFeedLoading: Bool = false
    @Published public var lastFeedRefresh: Date? = nil
    
    public init() {
        loadChannels()
    }
    
    // MARK: - Persistence
    
    private func loadChannels() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            self.subscribedChannels = []
            return
        }
        do {
            let decoded = try JSONDecoder().decode([ChannelInfo].self, from: data)
            self.subscribedChannels = decoded
        } catch {
            print("[ChannelSubscriptionManager] Failed to decode saved channels: \(error)")
            self.subscribedChannels = []
        }
    }
    
    private func saveChannels() {
        do {
            let data = try JSONEncoder().encode(subscribedChannels)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("[ChannelSubscriptionManager] Failed to encode saved channels: \(error)")
        }
    }
    
    // MARK: - Subscription Management
    
    public func isSubscribed(_ titleOrId: String) -> Bool {
        let clean = titleOrId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty && clean != "youtube" && clean != "youtube shorts" else { return false }
        return subscribedChannels.contains {
            $0.id.lowercased() == clean ||
            $0.title.lowercased() == clean ||
            ($0.handle?.lowercased() == clean)
        }
    }
    
    public func subscribe(title: String, id: String? = nil, handle: String? = nil, avatarUrl: String? = nil) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty && cleanTitle.lowercased() != "youtube" && cleanTitle.lowercased() != "youtube shorts" else { return }
        
        if isSubscribed(cleanTitle) { return }
        
        let channelId = (id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? id! : cleanTitle
        let newChannel = ChannelInfo(
            id: channelId,
            title: cleanTitle,
            handle: handle,
            subscriberCount: nil,
            avatarUrl: avatarUrl ?? "",
            description: nil
        )
        
        subscribedChannels.insert(newChannel, at: 0)
        saveChannels()
        
        // Refresh feed in background when a new channel is followed
        Task {
            await fetchFeed(forceRefresh: true)
        }
    }
    
    public func unsubscribe(titleOrId: String) {
        let clean = titleOrId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty else { return }
        
        subscribedChannels.removeAll {
            $0.id.lowercased() == clean ||
            $0.title.lowercased() == clean ||
            ($0.handle?.lowercased() == clean)
        }
        saveChannels()
        
        // Filter out videos from this channel from current feed
        feedVideos.removeAll { video in
            video.uploader.lowercased() == clean || (video.uploaderId?.lowercased() == clean)
        }
    }
    
    public func toggleSubscription(title: String, id: String? = nil, handle: String? = nil, avatarUrl: String? = nil) {
        if isSubscribed(title) || (id != nil && isSubscribed(id!)) {
            unsubscribe(titleOrId: id ?? title)
        } else {
            subscribe(title: title, id: id, handle: handle, avatarUrl: avatarUrl)
        }
    }
    
    // MARK: - Feed Aggregation
    
    public func fetchFeed(limitPerChannel: Int = 6, forceRefresh: Bool = false) async {
        guard !subscribedChannels.isEmpty else {
            feedVideos = []
            isFeedLoading = false
            return
        }
        
        // If already loaded recently (< 5 mins) and not forceRefresh, keep existing
        if !forceRefresh, !feedVideos.isEmpty, let last = lastFeedRefresh, Date().timeIntervalSince(last) < 300 {
            return
        }
        
        isFeedLoading = true
        defer { isFeedLoading = false }
        
        let channels = subscribedChannels
        
        // Concurrently fetch recent videos from each channel using InnerTube search
        let allChannelVideos: [[Video]] = await withTaskGroup(of: [Video].self) { group in
            for ch in channels.prefix(12) { // Top 12 channels for fast response
                group.addTask {
                    let query = (ch.handle?.hasPrefix("@") == true) ? ch.handle! : ch.title
                    let res = await YTDLPService.shared.searchVideos(query: query, limit: limitPerChannel)
                    // Keep videos matching the channel title closely or top results for the channel
                    let filtered = res.filter { video in
                        let uploaderLower = video.uploader.lowercased()
                        let chTitleLower = ch.title.lowercased()
                        return uploaderLower.contains(chTitleLower) || chTitleLower.contains(uploaderLower)
                    }
                    return filtered.isEmpty ? Array(res.prefix(limitPerChannel)) : filtered
                }
            }
            
            var collected: [[Video]] = []
            for await list in group {
                if !list.isEmpty {
                    collected.append(list)
                }
            }
            return collected
        }
        
        // Interleave videos so feed has diversity (Channel 1, Channel 2, Channel 3...)
        var interleaved: [Video] = []
        var seenIds = Set<String>()
        var maxCount = 0
        for list in allChannelVideos {
            maxCount = max(maxCount, list.count)
        }
        
        for idx in 0..<maxCount {
            for list in allChannelVideos {
                if idx < list.count {
                    let vid = list[idx]
                    if !seenIds.contains(vid.id) {
                        seenIds.insert(vid.id)
                        interleaved.append(vid)
                    }
                }
            }
        }
        
        self.feedVideos = interleaved
        self.lastFeedRefresh = Date()
    }
}
