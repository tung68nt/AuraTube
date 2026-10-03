import SwiftUI

struct RecommendedChannel: Identifiable {
    let id: String
    let title: String
    let handle: String
    let desc: String
    
    init(title: String, handle: String, desc: String) {
        self.id = title
        self.title = title
        self.handle = handle
        self.desc = desc
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var videos: [Video] = [] {
        didSet {
            regularVideos = videos.filter { !$0.isShort }
            shortVideos = videos.filter { $0.isShort }
            AuraImageCache.shared.prefetchImages(for: videos.prefix(12).map { $0.thumbnail })
        }
    }
    @Published private(set) var regularVideos: [Video] = []
    @Published private(set) var shortVideos: [Video] = []
    @Published var selectedTag = "Thịnh hành"
    @Published var selectedChannel: ChannelInfo? = nil
    @Published var channelVideos: [Video] = [] {
        didSet {
            channelRegularVideos = channelVideos.filter { !$0.isShort }
            channelShortVideos = channelVideos.filter { $0.isShort }
            AuraImageCache.shared.prefetchImages(for: channelVideos.prefix(8).map { $0.thumbnail })
        }
    }
    @Published private(set) var channelRegularVideos: [Video] = []
    @Published private(set) var channelShortVideos: [Video] = []
    @Published var isLoading = true
    @Published var isChannelLoading = false
    
    let recommendedChannels: [RecommendedChannel] = [
        RecommendedChannel(title: "MixiGaming", handle: "@MixiGamingOfficial", desc: "Gaming, Vlog & Giải trí"),
        RecommendedChannel(title: "Khoai Lang Thang", handle: "@KhoaiLangThang", desc: "Du lịch & Ẩm thực"),
        RecommendedChannel(title: "VTV24", handle: "@vtv24official", desc: "Tin tức Chuyển động 24h"),
        RecommendedChannel(title: "Phê Phim", handle: "@phephim", desc: "Review & Phân tích phim"),
        RecommendedChannel(title: "F8 Official", handle: "@F8VNOfficial", desc: "Lập trình & Công nghệ"),
        RecommendedChannel(title: "Monster Box", handle: "@MonsterBoxChannel", desc: "Khoa học & Xã hội"),
        RecommendedChannel(title: "Schannel", handle: "@SchannelVN", desc: "Công nghệ & Giới trẻ")
    ]
}

private struct FrequentChannelItem: View {
    let channelName: String
    let isSelected: Bool
    let avatarUrl: String?
    let onSelect: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                ZStack {
                    if let url = avatarUrl, !url.isEmpty {
                        CachedAsyncThumbnail(url: url, maxPixelSize: 120) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Circle()
                                .fill(colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.90))
                        }
                        .frame(width: 46, height: 46)
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.90))
                            .frame(width: 46, height: 46)
                        Text(String(channelName.prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    }
                }
                .overlay(
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.cyan : (isHovered ? (colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.25)) : ThemeColor.divider(for: colorScheme)),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: isHovered ? 4 : 2, y: 1)
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
                
                Text(channelName)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .cyan : ThemeColor.textPrimary(for: colorScheme))
                    .frame(width: 68)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

public struct HomeView: View {
    var onSelectVideo: (Video) -> Void
    var onSelectChannel: ((ChannelInfo) -> Void)? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var vm = HomeViewModel()
    @ObservedObject private var subManager = ChannelSubscriptionManager.shared
    @ObservedObject private var recService = RecommendationService.shared
    
    private let trendingTag = "Thịnh hành"
    private let followingTag = "Đang theo dõi"
    private let allTag = "Tất cả"
    
    private var allTags: [String] {
        var list = [trendingTag, allTag, followingTag]
        for t in recService.dynamicInterestTags {
            if !list.contains(t) && t != trendingTag {
                list.append(t)
            }
        }
        let baseCategories = [
            "Âm nhạc", "Giải trí", "Công nghệ", "Gaming",
            "Tin tức", "Ẩm thực", "Thể thao", "Podcast"
        ]
        for c in baseCategories {
            if !list.contains(c) {
                list.append(c)
            }
        }
        return list
    }
    
    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 380), spacing: 20, alignment: .top)
    ]
    
    public init(
        onSelectVideo: @escaping (Video) -> Void,
        onSelectChannel: ((ChannelInfo) -> Void)? = nil
    ) {
        self.onSelectVideo = onSelectVideo
        self.onSelectChannel = onSelectChannel
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Tag Chips Bar with macOS HIG Styling
                SmartHorizontalScrollView(showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(allTags, id: \.self) { tag in
                            let isFollowedTag = (tag == followingTag)
                            let displayTitle = (isFollowedTag && !subManager.subscribedChannels.isEmpty)
                                ? "\(followingTag) (\(subManager.subscribedChannels.count))"
                                : tag
                            
                            LiquidGlassCapsuleButton(
                                action: { selectTag(tag) },
                                isSelected: vm.selectedTag == tag
                            ) {
                                HStack(spacing: 5) {
                                    if tag == trendingTag {
                                        Image(systemName: "flame.fill")
                                            .font(.system(size: 11, weight: .semibold))
                                    } else if tag == followingTag {
                                        Image(systemName: "bell.fill")
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    
                                    Text(displayTitle)
                                        .font(.system(size: 12.5, weight: vm.selectedTag == tag ? .bold : .medium))
                                }
                                .foregroundColor(
                                    vm.selectedTag == tag ?
                                        (colorScheme == .dark ? Color(red: 15/255, green: 15/255, blue: 15/255) : Color.white) :
                                        (colorScheme == .dark ? Color(red: 241/255, green: 241/255, blue: 241/255) : Color(red: 15/255, green: 15/255, blue: 15/255))
                                )
                                .padding(.horizontal, 13)
                                .frame(height: 28)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                }
                
                // 2. Following Shelf (When user is on "Tất cả" or "Đang theo dõi")
                if !subManager.subscribedChannels.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center) {
                            Text("Kênh của bạn")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            
                            Text("• Không cần đăng nhập")
                                .font(.system(size: 11))
                                .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                            
                            Spacer()
                            
                            if vm.selectedTag == followingTag {
                                Button(action: {
                                    Task {
                                        await subManager.fetchFeed(forceRefresh: true)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        SpinningRefreshIcon(isSpinning: subManager.isFeedLoading, size: 10.5)
                                        Text(subManager.isFeedLoading ? "Đang tải..." : "Làm mới")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(ThemeColor.buttonBackground(for: colorScheme, isHovered: false))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().strokeBorder(ThemeColor.buttonBorder(for: colorScheme, isHovered: false), lineWidth: 0.75))
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button(action: { selectTag(followingTag) }) {
                                    HStack(spacing: 4) {
                                        Text("Xem tất cả video")
                                            .font(.system(size: 12, weight: .medium))
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .foregroundColor(Color.cyan)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        // Horizontal Subscribed Channels Scroll
                        SmartHorizontalScrollView(showsIndicators: false) {
                            HStack(spacing: 14) {
                                // "All channels" chip (when in Following view)
                                if vm.selectedTag == followingTag {
                                    Button(action: {
                                        vm.selectedChannel = nil
                                    }) {
                                        VStack(spacing: 6) {
                                            ZStack {
                                                Circle()
                                                    .fill(vm.selectedChannel == nil ? (colorScheme == .dark ? Color(white: 0.9) : Color(white: 0.15)) : (colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.88)))
                                                    .frame(width: 52, height: 52)
                                                Image(systemName: "square.grid.2x2.fill")
                                                    .font(.system(size: 20))
                                                    .foregroundColor(vm.selectedChannel == nil ? (colorScheme == .dark ? Color.black : Color.white) : ThemeColor.textPrimary(for: colorScheme))
                                            }
                                            .overlay(Circle().strokeBorder(ThemeColor.divider(for: colorScheme), lineWidth: 1.5))
                                            
                                            Text("Tất cả")
                                                .font(.system(size: 11.5, weight: vm.selectedChannel == nil ? .bold : .medium))
                                                .foregroundColor(vm.selectedChannel == nil ? ThemeColor.textPrimary(for: colorScheme) : ThemeColor.textSecondary(for: colorScheme))
                                                .frame(width: 64)
                                                .lineLimit(1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                ForEach(subManager.subscribedChannels) { channel in
                                    let isSelected = vm.selectedChannel?.id == channel.id
                                    Button(action: {
                                        if vm.selectedTag != followingTag {
                                            vm.selectedTag = followingTag
                                        }
                                        if isSelected {
                                            vm.selectedChannel = nil
                                        } else {
                                            selectChannel(channel)
                                        }
                                    }) {
                                        VStack(spacing: 6) {
                                            ZStack {
                                                if !channel.avatarUrl.isEmpty {
                                                    CachedAsyncThumbnail(url: channel.avatarUrl, maxPixelSize: 120) { img in
                                                        img.resizable().scaledToFill()
                                                    } placeholder: {
                                                        Circle().fill(Color(white: 0.22))
                                                    }
                                                    .frame(width: 52, height: 52)
                                                    .clipShape(Circle())
                                                } else {
                                                    Circle()
                                                        .fill(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.88))
                                                        .frame(width: 52, height: 52)
                                                    Text(String(channel.title.prefix(1)).uppercased())
                                                        .font(.system(size: 18, weight: .bold))
                                                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                                }
                                            }
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(
                                                        isSelected ? Color.cyan : Color.white.opacity(0.18),
                                                        lineWidth: isSelected ? 2.5 : 1
                                                    )
                                            )
                                            .shadow(color: isSelected ? Color.cyan.opacity(0.35) : Color.black.opacity(0.3), radius: isSelected ? 6 : 3)
                                            
                                            Text(channel.title)
                                                .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                                                .foregroundColor(isSelected ? .cyan : ThemeColor.textPrimary(for: colorScheme))
                                                .frame(width: 72)
                                                .lineLimit(1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive, action: {
                                            subManager.unsubscribe(titleOrId: channel.id)
                                            if vm.selectedChannel?.id == channel.id {
                                                vm.selectedChannel = nil
                                            }
                                        }) {
                                            Label("Hủy lưu kênh \(channel.title)", systemImage: "bell.slash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.top, 2)
                }
                
                // 2.5. Frequent Channels & Habit Shelf (Personalized Learning)
                let topChannelsToShow = recService.topChannels.filter { ch in
                    !subManager.subscribedChannels.contains(where: { $0.title.caseInsensitiveCompare(ch) == .orderedSame })
                }
                if !topChannelsToShow.isEmpty && (vm.selectedTag == allTag || vm.selectedTag == trendingTag) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Text("Kênh bạn xem nhiều")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            Text("• Dựa trên thói quen")
                                .font(.system(size: 11))
                                .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        
                        SmartHorizontalScrollView(showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(topChannelsToShow, id: \.self) { ch in
                                    FrequentChannelItem(
                                        channelName: ch,
                                        isSelected: vm.selectedTag == ch,
                                        avatarUrl: recService.getAvatarUrl(for: ch),
                                        onSelect: { selectTag(ch) }
                                    )
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.top, 2)
                }
                
                // 3. Section Title
                HStack {
                    if vm.selectedTag == followingTag {
                        if let selectedCh = vm.selectedChannel {
                            HStack(spacing: 8) {
                                Text("Video từ:")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                Text(selectedCh.title)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            }
                        } else {
                            Text("Video từ các kênh bạn theo dõi")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                        }
                    } else if vm.selectedTag == trendingTag {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 10) {
                                Text("Thịnh hành tại Việt Nam")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 5, height: 5)
                                    Text("Mới nhất")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Color.red)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.red.opacity(0.12))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.red.opacity(0.2), lineWidth: 0.75)
                                )
                            }
                            Text("Tổng hợp video và Shorts xu hướng nổi bật tại Việt Nam")
                                .font(.system(size: 12))
                                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        }
                    } else if vm.selectedTag == allTag {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(recService.hasPersonalizedProfile ? "Đề xuất cho bạn" : "Khám phá & Nổi bật")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            
                            let subtitleText: String = {
                                if !recService.topChannels.isEmpty {
                                    return "Dựa trên sở thích: " + recService.topChannels.prefix(3).joined(separator: ", ")
                                } else if recService.hasPersonalizedProfile {
                                    return "Được cá nhân hóa theo các kênh và nội dung bạn quan tâm"
                                } else {
                                    return "Video đa dạng từ công nghệ, đời sống, tin tức và giải trí"
                                }
                            }()
                            
                            Text(subtitleText)
                                .font(.system(size: 12))
                                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        }
                    } else {
                        Text("Chủ đề: \(vm.selectedTag)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    }
                    
                    Spacer()
                    
                    // Refresh Feed Button
                    Button(action: {
                        Task {
                            if vm.selectedTag == followingTag {
                                if let ch = vm.selectedChannel {
                                    selectChannel(ch)
                                } else {
                                    await subManager.fetchFeed(forceRefresh: true)
                                }
                            } else if vm.selectedTag == trendingTag {
                                vm.isLoading = true
                                let fresh = await recService.fetchVietnamTrendingFeed(forceRefresh: true)
                                if !fresh.isEmpty {
                                    vm.videos = fresh
                                }
                                vm.isLoading = false
                            } else if vm.selectedTag == allTag {
                                vm.isLoading = true
                                vm.videos = await recService.fetchRecommendations()
                                vm.isLoading = false
                            } else {
                                selectTag(vm.selectedTag)
                            }
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                                .rotationEffect(.degrees(vm.isLoading ? 360 : 0))
                                .animation(vm.isLoading ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: vm.isLoading)
                            Text("Làm mới")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(ThemeColor.cardBackground(for: colorScheme))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(ThemeColor.cardBorder(for: colorScheme), lineWidth: 0.8)
                        )
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    }
                    .buttonStyle(.plain)
                    .help("Làm mới danh sách video")
                }
                .padding(.horizontal, 24)
                
                // 4. Content Area: Empty State vs Video Grid
                if vm.selectedTag == followingTag && subManager.subscribedChannels.isEmpty {
                    // Empty state for Following tab
                    VStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(ThemeColor.cardBackground(for: colorScheme))
                                .frame(width: 80, height: 80)
                                .overlay(Circle().strokeBorder(ThemeColor.cardBorder(for: colorScheme), lineWidth: 1))
                            Image(systemName: "bell.badge")
                                .font(.system(size: 34))
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.85))
                        }
                        .padding(.top, 24)
                        
                        VStack(spacing: 8) {
                            Text("Chưa lưu kênh nào")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            
                            Text("Bấm 'Đăng ký' ở bất kỳ video nào bạn xem để lưu kênh vào danh sách này.\nVideo mới nhất từ các kênh đó sẽ tự động tập hợp tại đây mà không cần đăng nhập Google!")
                                .font(.system(size: 13))
                                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                                .frame(maxWidth: 520)
                        }
                        
                        Divider()
                            .background(ThemeColor.divider(for: colorScheme))
                            .padding(.horizontal, 48)
                            .padding(.vertical, 8)
                        
                        // Suggested channels quick add
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Gợi ý các kênh hay theo dõi:")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                .padding(.horizontal, 24)
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                                ForEach(vm.recommendedChannels) { rec in
                                    let isSub = subManager.isSubscribed(rec.title)
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.88))
                                                .frame(width: 44, height: 44)
                                            Text(String(rec.title.prefix(1)).uppercased())
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(rec.title)
                                                .font(.system(size: 13.5, weight: .semibold))
                                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                                .lineLimit(1)
                                            Text(rec.desc)
                                                .font(.system(size: 11.5))
                                                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                                .lineLimit(1)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            subManager.toggleSubscription(title: rec.title, handle: rec.handle)
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: isSub ? "checkmark" : "plus")
                                                    .font(.system(size: 11, weight: .bold))
                                                Text(isSub ? "Đã lưu" : "Theo dõi")
                                                    .font(.system(size: 12, weight: .semibold))
                                            }
                                            .foregroundColor(isSub ? (colorScheme == .dark ? Color.white.opacity(0.85) : Color.white) : (colorScheme == .dark ? Color.black : Color.white))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(isSub ? (colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.5)) : (colorScheme == .dark ? Color.white : Color(white: 0.15)))
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(12)
                                    .background(ThemeColor.cardBackground(for: colorScheme))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(ThemeColor.cardBorder(for: colorScheme), lineWidth: 0.75)
                                    )
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    // Video Grid display
                    let currentList: [Video] = {
                        if vm.selectedTag == followingTag {
                            if vm.selectedChannel != nil {
                                return vm.channelVideos
                            } else {
                                return subManager.feedVideos
                            }
                        } else {
                            return vm.videos
                        }
                    }()
                    
                    let isCurrentLoading: Bool = {
                        if vm.selectedTag == followingTag {
                            if vm.selectedChannel != nil {
                                return vm.isChannelLoading
                            } else {
                                return subManager.isFeedLoading && subManager.feedVideos.isEmpty
                            }
                        } else {
                            return vm.isLoading && vm.videos.isEmpty
                        }
                    }()
                    
                    if isCurrentLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Đang tải danh sách video...")
                                .font(.system(size: 13))
                                .foregroundColor(Color(white: 0.6))
                        }
                        .frame(maxWidth: .infinity, minHeight: 300)
                    } else if currentList.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "film")
                                .font(.system(size: 36))
                                .foregroundColor(Color(white: 0.4))
                            Text("Chưa tải được danh sách video")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(white: 0.6))
                            Button(action: {
                                Task { await loadInitial() }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Thử lại")
                                }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.cyan.opacity(0.8))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        let regularVideos: [Video] = {
                            if vm.selectedTag == followingTag {
                                return (vm.selectedChannel != nil) ? vm.channelRegularVideos : subManager.feedVideos.filter { !$0.isShort }
                            } else {
                                return vm.regularVideos
                            }
                        }()
                        let shortVideos: [Video] = {
                            if vm.selectedTag == followingTag {
                                return (vm.selectedChannel != nil) ? vm.channelShortVideos : subManager.feedVideos.filter { $0.isShort }
                            } else {
                                return vm.shortVideos
                            }
                        }()
                        
                        if shortVideos.isEmpty {
                            // Only regular 16:9 videos
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                                ForEach(regularVideos) { video in
                                    VideoCardView(
                                        video: video,
                                        onSelect: { onSelectVideo(video) },
                                        onSelectChannel: onSelectChannel
                                    )
                                }
                            }
                            .padding(.horizontal, 24)
                        } else if regularVideos.isEmpty {
                            // Only Shorts available
                            VStack(alignment: .leading, spacing: 16) {
                                HomeShortsShelfHeader()
                                    .padding(.horizontal, 24)
                                
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16, alignment: .top)], alignment: .leading, spacing: 22) {
                                    ForEach(shortVideos) { short in
                                        SearchShortCardView(video: short) {
                                            onSelectVideo(short)
                                        }
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                        } else {
                            // Integrated YouTube-style layout: Top long videos -> Shorts shelf -> Remaining long videos
                            let topVideos = Array(regularVideos.prefix(6))
                            let remainingVideos = Array(regularVideos.dropFirst(6))
                            
                            VStack(alignment: .leading, spacing: 28) {
                                // 1. Top regular videos (16:9 grid)
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                                    ForEach(topVideos) { video in
                                        VideoCardView(
                                            video: video,
                                            onSelect: { onSelectVideo(video) },
                                            onSelectChannel: onSelectChannel
                                        )
                                    }
                                }
                                .padding(.horizontal, 24)
                                
                                // 2. Distinct YouTube Shorts Shelf
                                HomeShortsShelfView(
                                    shorts: Array(shortVideos.prefix(14)),
                                    onSelectShort: { onSelectVideo($0) }
                                )
                                
                                // 3. Remaining regular videos (16:9 grid)
                                if !remainingVideos.isEmpty {
                                    LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                                        ForEach(remainingVideos) { video in
                                            VideoCardView(
                                                video: video,
                                                onSelect: { onSelectVideo(video) },
                                                onSelectChannel: onSelectChannel
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 24)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .task {
            await loadInitial()
        }
    }
    
    private func selectTag(_ tag: String) {
        vm.selectedTag = tag
        vm.selectedChannel = nil
        
        if tag == followingTag {
            Task {
                await subManager.fetchFeed()
            }
            return
        }
        
        Task {
            vm.isLoading = true
            if tag == allTag {
                vm.videos = await RecommendationService.shared.fetchRecommendations()
            } else if tag == trendingTag {
                let feed = await RecommendationService.shared.fetchVietnamTrendingFeed(forceRefresh: true)
                vm.videos = feed.isEmpty ? await RecommendationService.shared.fetchRecommendations() : feed
            } else if RecommendationService.shared.isVietnamCategory(tag) {
                vm.videos = await RecommendationService.shared.fetchVietnamCategoryFeed(category: tag)
            } else if tag == "Hệ sinh thái Apple" {
                vm.videos = await YTDLPService.shared.searchVideos(query: "apple iphone macbook ipad phụ kiện mới nhất")
            } else if tag == "Setup góc làm việc" {
                vm.videos = await YTDLPService.shared.searchVideos(query: "setup góc làm việc tối giản bàn phím decor")
            } else if tag == "Kính VR & AI" {
                vm.videos = await YTDLPService.shared.searchVideos(query: "kính thực tế ảo vr ar apple vision pro meta quest ai")
            } else if tag == "Gaming Gear" {
                vm.videos = await YTDLPService.shared.searchVideos(query: "chuột bàn phím tai nghe gaming gear máy chơi game")
            } else if tag == "Xe & Công nghệ" {
                vm.videos = await YTDLPService.shared.searchVideos(query: "xe hơi ô tô thông minh xe điện công nghệ")
            } else if recService.topChannels.contains(tag) {
                vm.videos = await YTDLPService.shared.searchVideos(query: "\(tag) video mới nhất")
            } else {
                vm.videos = await YTDLPService.shared.searchVideos(query: tag)
            }
            vm.isLoading = false
        }
    }
    
    private func selectChannel(_ channel: ChannelInfo) {
        vm.selectedChannel = channel
        Task {
            vm.isChannelLoading = true
            let query = (channel.handle?.hasPrefix("@") == true) ? channel.handle! : channel.title
            let fetched = await YTDLPService.shared.searchVideos(query: query, limit: 16)
            vm.channelVideos = fetched
            vm.isChannelLoading = false
        }
    }
    
    private func loadInitial() async {
        let cached = RecommendationService.shared.getCachedTrending()
        if !cached.isEmpty {
            vm.videos = cached
            vm.isLoading = false
        } else {
            vm.isLoading = true
        }
        
        let feed = await RecommendationService.shared.fetchVietnamTrendingFeed(forceRefresh: cached.isEmpty)
        if !feed.isEmpty {
            vm.videos = feed
        } else if vm.videos.isEmpty {
            vm.videos = await RecommendationService.shared.fetchRecommendations()
        }
        vm.isLoading = false
        
        // Background pre-fetch followed channels feed if user has subscriptions
        if !subManager.subscribedChannels.isEmpty {
            await subManager.fetchFeed()
        }
    }
}

public struct VideoCardView: View {
    let video: Video
    let onSelect: () -> Void
    var onSelectChannel: ((ChannelInfo) -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Thumbnail Wrap (Clicking thumbnail plays video)
            Button(action: onSelect) {
                ZStack(alignment: .bottomTrailing) {
                    Color.clear
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay(
                            CachedAsyncThumbnail(
                                url: video.thumbnail,
                                maxPixelSize: 640,
                                placeholderColor: colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.88)
                            )
                        )
                        .overlay(
                            Group {
                                if let ratio = PlayerManager.shared.watchProgressRatio(for: video.id) {
                                    VStack(spacing: 0) {
                                        Spacer()
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                Rectangle()
                                                    .fill(Color.black.opacity(0.6))
                                                    .frame(height: 3.5)
                                                Rectangle()
                                                    .fill(Color.red)
                                                    .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(ratio))), height: 3.5)
                                            }
                                        }
                                        .frame(height: 3.5)
                                    }
                                }
                            }
                        )
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(
                                    (colorScheme == .dark ? Color.white : Color.black).opacity(isHovered ? 0.30 : 0.08),
                                    lineWidth: 0.75
                                )
                        )
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 4, y: 2)
                    
                    Text(video.durationFormatted)
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2.5)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(4)
                        .foregroundColor(.white)
                        .padding(6)
                }
            }
            .buttonStyle(.plain)
            
            // Card Details
            HStack(alignment: .top, spacing: 12) {
                // Channel Avatar (Clicking opens channel)
                Button(action: {
                    let ch = ChannelInfo(
                        id: video.uploaderId ?? "",
                        title: video.uploader,
                        avatarUrl: video.channelAvatarUrl ?? ""
                    )
                    onSelectChannel?(ch)
                }) {
                    if let avatar = video.channelAvatarUrl, !avatar.isEmpty {
                        CachedAsyncThumbnail(
                            url: avatar,
                            maxPixelSize: 80,
                            placeholderColor: colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.85)
                        )
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(ThemeColor.divider(for: colorScheme), lineWidth: 1))
                    } else {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [Color(white: 0.16), Color(white: 0.26)]
                                        : [Color(white: 0.82), Color(white: 0.92)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 36, height: 36)
                                .overlay(Circle().stroke(ThemeColor.divider(for: colorScheme), lineWidth: 1))
                            Text(String(video.uploader.prefix(1)).uppercased())
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Xem kênh \(video.uploader)")
                
                VStack(alignment: .leading, spacing: 3) {
                    // Title (Clicking plays video)
                    Button(action: onSelect) {
                        Text(video.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(2)
                            .frame(height: 38, alignment: .topLeading)
                    }
                    .buttonStyle(.plain)
                    
                    // Uploader Name (Clicking opens channel)
                    Button(action: {
                        let ch = ChannelInfo(
                            id: video.uploaderId ?? "",
                            title: video.uploader,
                            avatarUrl: video.channelAvatarUrl ?? ""
                        )
                        onSelectChannel?(ch)
                    }) {
                        Text(video.uploader)
                            .font(.system(size: 12.5))
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .help("Xem kênh \(video.uploader)")
                    
                    Text(!video.metadataFormatted.isEmpty ? video.metadataFormatted : " ")
                        .font(.system(size: 12))
                        .foregroundColor(video.metadataFormatted.isEmpty ? .clear : ThemeColor.textTertiary(for: colorScheme))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                Spacer(minLength: 0)
            }
        }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Home Shorts Shelf Header & View
struct HomeShortsShelfHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    var onScrollLeft: (() -> Void)? = nil
    var onScrollRight: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.15, blue: 0.15))
                    .frame(width: 26, height: 26)
                Image(systemName: "play.rectangle.fill")
                    .foregroundColor(.white)
                    .font(.system(size: 13, weight: .bold))
            }
            
            Text("Shorts")
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
            
            Text("• Video ngắn nổi bật")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
            
            Spacer()
            
            if let onLeft = onScrollLeft, let onRight = onScrollRight {
                HStack(spacing: 6) {
                    Button(action: onLeft) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            .frame(width: 28, height: 28)
                            .background(ThemeColor.cardBackground(for: colorScheme))
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(ThemeColor.cardBorder(for: colorScheme), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Cuộn xem Shorts trước")
                    
                    Button(action: onRight) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            .frame(width: 28, height: 28)
                            .background(ThemeColor.cardBackground(for: colorScheme))
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(ThemeColor.cardBorder(for: colorScheme), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Cuộn xem Shorts kế tiếp")
                }
            }
        }
    }
}

struct HomeShortsShelfView: View {
    @Environment(\.colorScheme) private var colorScheme
    let shorts: [Video]
    let onSelectShort: (Video) -> Void
    @State private var currentShortIndex: Int = 0
    
    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 14) {
                // Subtle top divider
                Divider()
                    .background(ThemeColor.divider(for: colorScheme))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 2)
                
                // Header with navigation arrows
                HomeShortsShelfHeader(
                    onScrollLeft: {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            currentShortIndex = max(0, currentShortIndex - 3)
                            proxy.scrollTo(currentShortIndex, anchor: .leading)
                        }
                    },
                    onScrollRight: {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            currentShortIndex = min(max(0, shorts.count - 1), currentShortIndex + 3)
                            proxy.scrollTo(currentShortIndex, anchor: .leading)
                        }
                    }
                )
                .padding(.horizontal, 24)
                
                // Smart Horizontal Scrollable Shorts (Zero Nested Scroll Trap)
                SmartHorizontalScrollView(showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(Array(shorts.enumerated()), id: \.element.id) { index, short in
                            SearchShortCardView(video: short) {
                                onSelectShort(short)
                            }
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 4)
                }
                
                // Subtle bottom divider
                Divider()
                    .background(ThemeColor.divider(for: colorScheme))
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
            }
        }
    }
}

