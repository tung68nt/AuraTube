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
    @Published var videos: [Video] = []
    @Published var selectedTag = "Tất cả"
    @Published var selectedChannel: ChannelInfo? = nil
    @Published var channelVideos: [Video] = []
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

public struct HomeView: View {
    var onSelectVideo: (Video) -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var vm = HomeViewModel()
    @ObservedObject private var subManager = ChannelSubscriptionManager.shared
    
    private let tags = [
        "Tất cả", "🔔 Đang theo dõi", "Âm nhạc", "Trực tiếp", "Trò chơi",
        "Tin tức", "Podcast", "Khoa học", "Bóng đá"
    ]
    
    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 380), spacing: 20)
    ]
    
    public init(onSelectVideo: @escaping (Video) -> Void) {
        self.onSelectVideo = onSelectVideo
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Tag Chips Bar with macOS HIG Styling
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(tags, id: \.self) { tag in
                            let isFollowedTag = tag.contains("Đang theo dõi")
                            let displayTitle = (isFollowedTag && !subManager.subscribedChannels.isEmpty)
                                ? "🔔 Đang theo dõi (\(subManager.subscribedChannels.count))"
                                : tag
                            
                            LiquidGlassCapsuleButton(
                                action: { selectTag(tag) },
                                isSelected: vm.selectedTag == tag
                            ) {
                                Text(displayTitle)
                                    .font(.system(size: 12.5, weight: vm.selectedTag == tag ? .bold : .medium))
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
                
                // 2. Following Shelf (When user is on "Tất cả" or "🔔 Đang theo dõi")
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
                            
                            if vm.selectedTag == "🔔 Đang theo dõi" {
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
                                Button(action: { selectTag("🔔 Đang theo dõi") }) {
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
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                // "All channels" chip (when in Following view)
                                if vm.selectedTag == "🔔 Đang theo dõi" {
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
                                        if vm.selectedTag != "🔔 Đang theo dõi" {
                                            vm.selectedTag = "🔔 Đang theo dõi"
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
                                                    AsyncImage(url: URL(string: channel.avatarUrl)) { phase in
                                                        if let img = phase.image {
                                                            img.resizable().scaledToFill()
                                                        } else {
                                                            Circle().fill(Color(white: 0.22))
                                                        }
                                                    }
                                                    .frame(width: 52, height: 52)
                                                    .clipShape(Circle())
                                                } else {
                                                    Circle()
                                                        .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                        .frame(width: 52, height: 52)
                                                    Text(String(channel.title.prefix(1)).uppercased())
                                                        .font(.system(size: 18, weight: .bold))
                                                        .foregroundColor(.white)
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
                
                // 3. Section Title
                HStack {
                    if vm.selectedTag == "🔔 Đang theo dõi" {
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
                    } else if vm.selectedTag == "Tất cả" {
                        Text("Thịnh hành")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    } else {
                        Text("Chủ đề: \(vm.selectedTag)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                
                // 4. Content Area: Empty State vs Video Grid
                if vm.selectedTag == "🔔 Đang theo dõi" && subManager.subscribedChannels.isEmpty {
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
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 14)], spacing: 14) {
                                ForEach(vm.recommendedChannels) { rec in
                                    let isSub = subManager.isSubscribed(rec.title)
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(LinearGradient(colors: [Color.cyan.opacity(0.3), Color.blue.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                .frame(width: 44, height: 44)
                                            Text(String(rec.title.prefix(1)).uppercased())
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(.white)
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
                        if vm.selectedTag == "🔔 Đang theo dõi" {
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
                        if vm.selectedTag == "🔔 Đang theo dõi" {
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
                        VStack(spacing: 12) {
                            Image(systemName: "film")
                                .font(.system(size: 32))
                                .foregroundColor(Color(white: 0.4))
                            Text("Chưa tìm thấy video nào")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(white: 0.6))
                        }
                        .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        LazyVGrid(columns: columns, spacing: 28) {
                            ForEach(currentList) { video in
                                VideoCardView(video: video) {
                                    onSelectVideo(video)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
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
        
        if tag == "🔔 Đang theo dõi" {
            Task {
                await subManager.fetchFeed()
            }
            return
        }
        
        Task {
            vm.isLoading = true
            if tag == "Tất cả" {
                vm.videos = await YTDLPService.shared.fetchTrendingVideos()
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
        vm.isLoading = true
        vm.videos = await YTDLPService.shared.fetchTrendingVideos()
        vm.isLoading = false
        
        // Background pre-fetch followed channels feed if user has subscriptions
        if !subManager.subscribedChannels.isEmpty {
            await subManager.fetchFeed()
        }
    }
}

@MainActor
final class CardHoverViewModel: ObservableObject {
    @Published var isHovered = false
}

public struct VideoCardView: View {
    let video: Video
    let onSelect: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var hoverVm = CardHoverViewModel()
    
    public var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                // Thumbnail Wrap
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: URL(string: video.thumbnail)) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            (colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.88))
                        }
                    }
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        (colorScheme == .dark ? Color.white : Color.black).opacity(hoverVm.isHovered ? 0.22 : 0.10),
                                        (colorScheme == .dark ? Color.white : Color.black).opacity(hoverVm.isHovered ? 0.08 : 0.02)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.75
                            )
                    )
                    .shadow(color: (colorScheme == .dark ? Color.black : Color.black.opacity(0.12)).opacity(hoverVm.isHovered ? 0.35 : 0.15), radius: hoverVm.isHovered ? 10 : 5, y: hoverVm.isHovered ? 4 : 2)
                    .scaleEffect(hoverVm.isHovered ? 1.015 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: hoverVm.isHovered)
                    
                    Text(video.durationFormatted)
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2.5)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(4)
                        .foregroundColor(.white)
                        .padding(6)
                }
                
                // Card Details
                HStack(alignment: .top, spacing: 12) {
                    // Channel Avatar
                    if let avatar = video.channelAvatarUrl, !avatar.isEmpty {
                        AsyncImage(url: URL(string: avatar)) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFill()
                            } else {
                                Circle().fill(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.85))
                            }
                        }
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
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(video.title)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(2)
                        
                        Text(video.uploader)
                            .font(.system(size: 12.5))
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        
                        if !video.metadataFormatted.isEmpty {
                            Text(video.metadataFormatted)
                                .font(.system(size: 12))
                                .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hoverVm.isHovered = $0 }
    }
}
