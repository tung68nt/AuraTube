import SwiftUI

public struct ChannelDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    let channel: ChannelInfo
    let videos: [Video]
    let bannerUrl: String?
    let isLoading: Bool
    let isLoadingMore: Bool
    let onBack: () -> Void
    let onSelectVideo: (Video) -> Void
    let onLoadMore: () -> Void
    
    @State private var selectedFilter: String = "Tất cả"
    @State private var isDescriptionExpanded: Bool = false
    @ObservedObject private var subManager = ChannelSubscriptionManager.shared
    
    private let filterOptions = ["Tất cả", "Video", "Shorts"]
    
    public init(
        channel: ChannelInfo,
        videos: [Video],
        bannerUrl: String? = nil,
        isLoading: Bool = false,
        isLoadingMore: Bool = false,
        onBack: @escaping () -> Void,
        onSelectVideo: @escaping (Video) -> Void,
        onLoadMore: @escaping () -> Void = {}
    ) {
        self.channel = channel
        self.videos = videos
        self.bannerUrl = bannerUrl
        self.isLoading = isLoading
        self.isLoadingMore = isLoadingMore
        self.onBack = onBack
        self.onSelectVideo = onSelectVideo
        self.onLoadMore = onLoadMore
    }
    
    private var displayedVideos: [Video] {
        switch selectedFilter {
        case "Video":
            return videos.filter { !$0.isShort }
        case "Shorts":
            return videos.filter { $0.isShort }
        default:
            return videos
        }
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Top Navigation Bar
                HStack(spacing: 12) {
                    LiquidGlassButton(action: onBack, cornerRadius: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .bold))
                            Text("Quay lại")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.top, 14)
                
                // 1. Channel Header Banner (if available)
                if let bUrl = bannerUrl, !bUrl.isEmpty {
                    CachedAsyncThumbnail(
                        url: bUrl,
                        maxPixelSize: 1280,
                        placeholderColor: colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.88)
                    )
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(ThemeColor.divider(for: colorScheme), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 8, y: 3)
                    .padding(.horizontal, 28)
                }
                
                // 2. Channel Profile Identity
                HStack(alignment: .top, spacing: 20) {
                    // Large Circular Avatar
                    CachedAsyncThumbnail(
                        url: channel.avatarUrl,
                        maxPixelSize: 180,
                        placeholderColor: colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.85)
                    )
                    .frame(width: 76, height: 76)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(ThemeColor.divider(for: colorScheme), lineWidth: 1.5))
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 6, y: 3)
                    
                    // Identity details
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(channel.title)
                                .font(AppFont.youTubeSans(size: 24, weight: .bold))
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                .lineLimit(1)
                            
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(Color.cyan)
                                .font(.system(size: 15))
                        }
                        
                        HStack(spacing: 8) {
                            if let handle = channel.handle, !handle.isEmpty {
                                Text(handle)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                            }
                            
                            if let subs = channel.subscriberCount, !subs.isEmpty {
                                Text("•")
                                    .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                                Text(subs)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                            }
                            
                            if !videos.isEmpty {
                                Text("•")
                                    .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                                Text("\(videos.count) video")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                            }
                        }
                        
                        // Description snippet
                        if let desc = channel.description, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(desc)
                                .font(.system(size: 12.5))
                                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                .lineLimit(isDescriptionExpanded ? nil : 2)
                                .multilineTextAlignment(.leading)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        isDescriptionExpanded.toggle()
                                    }
                                }
                        }
                        
                        // Action Buttons: Subscribe & Share
                        HStack(spacing: 10) {
                            let isSub = subManager.isSubscribed(channel.title) || subManager.isSubscribed(channel.id)
                            LiquidGlassCapsuleButton(
                                action: {
                                    subManager.toggleSubscription(
                                        title: channel.title,
                                        id: channel.id,
                                        handle: channel.handle,
                                        avatarUrl: channel.avatarUrl
                                    )
                                },
                                isSelected: !isSub
                            ) {
                                HStack(spacing: 6) {
                                    if isSub {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                    Text(isSub ? "Đã đăng ký" : "Đăng ký")
                                        .font(.system(size: 12.5, weight: .semibold))
                                }
                                .foregroundColor(
                                    !isSub ?
                                        (colorScheme == .dark ? Color.black.opacity(0.92) : Color.white) :
                                        (colorScheme == .dark ? Color.white.opacity(0.90) : Color.black.opacity(0.88))
                                )
                                .padding(.horizontal, 15)
                                .frame(height: 32)
                            }
                            
                            Button(action: {
                                let shareUrl = (channel.handle?.hasPrefix("@") == true) ?
                                    "https://www.youtube.com/\(channel.handle!)" :
                                    "https://www.youtube.com/channel/\(channel.id)"
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(shareUrl, forType: .string)
                                PlayerManager.shared.flashHUD(icon: "link", text: "Đã sao chép liên kết kênh 📋")
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Chia sẻ")
                                        .font(.system(size: 12.5, weight: .medium))
                                }
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                .padding(.horizontal, 14)
                                .frame(height: 32)
                                .background(
                                    Capsule()
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.05))
                                        .overlay(Capsule().strokeBorder(ThemeColor.divider(for: colorScheme), lineWidth: 0.75))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 28)
                
                Divider()
                    .background(ThemeColor.divider(for: colorScheme))
                    .padding(.horizontal, 28)
                
                // 3. Filter Chips
                HStack(spacing: 8) {
                    ForEach(filterOptions, id: \.self) { opt in
                        LiquidGlassCapsuleButton(
                            action: { selectedFilter = opt },
                            isSelected: selectedFilter == opt
                        ) {
                            Text(opt)
                                .font(.system(size: 12.5, weight: selectedFilter == opt ? .semibold : .medium))
                                .foregroundColor(
                                    selectedFilter == opt ?
                                        (colorScheme == .dark ? Color(red: 15/255, green: 15/255, blue: 15/255) : Color.white) :
                                        (colorScheme == .dark ? Color(red: 241/255, green: 241/255, blue: 241/255) : Color(red: 15/255, green: 15/255, blue: 15/255))
                                )
                                .padding(.horizontal, 14)
                                .frame(height: 28)
                        }
                    }
                    
                    Spacer()
                    
                    if !displayedVideos.isEmpty {
                        Text("\(displayedVideos.count) video")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    }
                }
                .padding(.horizontal, 28)
                
                // 4. Videos Grid
                if isLoading && videos.isEmpty {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Đang tải danh sách video của kênh \(channel.title)...")
                            .font(.system(size: 13))
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    }
                    .frame(maxWidth: .infinity, minHeight: 350)
                } else if displayedVideos.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 36))
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme).opacity(0.6))
                        Text("Chưa có video nào")
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 20, alignment: .top)
                        ],
                        spacing: 24
                    ) {
                        ForEach(Array(displayedVideos.enumerated()), id: \.element.id) { index, video in
                            ChannelVideoCardView(video: video) {
                                onSelectVideo(video)
                            }
                            .onAppear {
                                if index >= displayedVideos.count - 4 {
                                    onLoadMore()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    
                    if isLoadingMore {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Đang tải thêm video...")
                                .font(.system(size: 12.5))
                                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                }
            }
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Channel Video Card View
struct ChannelVideoCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let video: Video
    let onSelect: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                // 16:9 Thumbnail
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
                            GeometryReader { geo in
                                if let ratio = PlayerManager.shared.watchProgressRatio(for: video.id) {
                                    VStack(spacing: 0) {
                                        Spacer()
                                        ZStack(alignment: .leading) {
                                            Rectangle()
                                                .fill(Color.black.opacity(0.6))
                                                .frame(height: 3.5)
                                            Rectangle()
                                                .fill(Color.red)
                                                .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(ratio))), height: 3.5)
                                        }
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
                
                // Metadata
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                        .frame(height: 36, alignment: .topLeading)
                    
                    Text(video.metadataFormatted.isEmpty ? "YouTube" : video.metadataFormatted)
                        .font(.system(size: 12))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
