import SwiftUI
import AppKit

@MainActor
final class WatchViewModel: ObservableObject {
    @Published var isDescExpanded = false
    @Published var isSubscribed = false
    @Published var showDownloadSheet = false
    @Published var relatedVideos: [Video] = []
    @Published var shareToast: String?
}

public struct WatchView: View {
    let video: Video
    var onBack: () -> Void
    var onSelectRelated: (Video) -> Void
    
    @ObservedObject private var playerManager = PlayerManager.shared
    @ObservedObject private var subManager = ChannelSubscriptionManager.shared
    @StateObject private var vm = WatchViewModel()
    @Environment(\.colorScheme) private var colorScheme
    
    public init(video: Video, onBack: @escaping () -> Void, onSelectRelated: @escaping (Video) -> Void) {
        self.video = video
        self.onBack = onBack
        self.onSelectRelated = onSelectRelated
    }
    
    private var displayVideo: Video {
        playerManager.currentVideo ?? video
    }
    
    private var videoDescriptionText: String {
        if let desc = playerManager.currentVideo?.description, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return desc
        }
        if let desc = video.description, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return desc
        }
        return "Không có mô tả."
    }
    
    public var body: some View {
        Group {
            if playerManager.isVideoFullscreen {
                Color.black.ignoresSafeArea()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Main Two-Column Layout
                        HStack(alignment: .top, spacing: 24) {
                            // Left Column: Player & Details
                            VStack(alignment: .leading, spacing: 14) {
                                // Dedicated Watch Player Container with YouTube-grade hover auto-hide & center flash
                                WatchPlayerContainerView(
                                    displayVideo: displayVideo,
                                    playerManager: playerManager
                                )
                                
                                // Switch to Shorts Mode Banner if this video is a Short
                                if displayVideo.isShort {
                                    Button(action: {
                                        onSelectRelated(displayVideo)
                                    }) {
                                        HStack(spacing: 10) {
                                            Image(systemName: "play.square.stack.fill")
                                                .font(.system(size: 15))
                                                .foregroundColor(.red)
                                            
                                            Text("Đây là video Shorts. Bấm để lướt liên tục trên giao diện dọc chuyên biệt")
                                                .font(.system(size: 12.5, weight: .medium))
                                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                            
                                            Spacer()
                                            
                                            HStack(spacing: 4) {
                                                Text("Mở Shorts")
                                                    .font(.system(size: 11.5, weight: .semibold))
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 10, weight: .semibold))
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4.5)
                                            .background(Color.red)
                                            .clipShape(Capsule())
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(ThemeColor.cardBackground(for: colorScheme))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(ThemeColor.cardBorder(for: colorScheme), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                // Video Title
                                Text(displayVideo.title)
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                    .lineLimit(2)
                                    .padding(.top, 4)
                        
                        // Action Bar: Uploader + Buttons
                        HStack(alignment: .center, spacing: 16) {
                            // Uploader info
                            HStack(spacing: 12) {
                                if let avatarUrl = displayVideo.channelAvatarUrl, !avatarUrl.isEmpty {
                                    AsyncImage(url: URL(string: avatarUrl)) { phase in
                                        if let img = phase.image {
                                            img.resizable().scaledToFill()
                                        } else {
                                            Circle().fill(Color(white: 0.2))
                                        }
                                    }
                                    .frame(width: 42, height: 42)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(ThemeColor.divider(for: colorScheme), lineWidth: 1))
                                } else {
                                    ZStack {
                                        Circle()
                                            .fill(LinearGradient(colors: colorScheme == .dark ? [Color(white: 0.15), Color(white: 0.25)] : [Color(white: 0.82), Color(white: 0.92)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .frame(width: 42, height: 42)
                                            .overlay(Circle().stroke(ThemeColor.divider(for: colorScheme), lineWidth: 1))
                                        Text(String(displayVideo.uploader.prefix(1)).uppercased())
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayVideo.uploader)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                        .lineLimit(1)
                                    Text(displayVideo.metadataFormatted.isEmpty ? "YouTube" : displayVideo.metadataFormatted)
                                        .font(.system(size: 12.5))
                                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                        .lineLimit(1)
                                }
                                
                                // Subscribe Button (Persisted via ChannelSubscriptionManager without login)
                                let isSub = ChannelSubscriptionManager.shared.isSubscribed(displayVideo.uploader)
                                LiquidGlassCapsuleButton(
                                    action: {
                                        ChannelSubscriptionManager.shared.toggleSubscription(
                                            title: displayVideo.uploader,
                                            id: displayVideo.uploaderId,
                                            avatarUrl: displayVideo.channelAvatarUrl
                                        )
                                    },
                                    isSelected: !isSub
                                ) {
                                    HStack(spacing: 5) {
                                        if isSub {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .bold))
                                        }
                                        Text(isSub ? "Đã đăng ký" : "Đăng ký")
                                            .font(.system(size: 12.5, weight: .semibold))
                                    }
                                    .lineLimit(1)
                                    .fixedSize()
                                    .padding(.horizontal, 15)
                                    .frame(height: 32)
                                    .foregroundColor(
                                        !isSub ?
                                            (colorScheme == .dark ? Color.black.opacity(0.92) : Color.white) :
                                            (colorScheme == .dark ? Color.white.opacity(0.90) : Color.black.opacity(0.88))
                                    )
                                }
                                .padding(.leading, 6)
                            }
                            
                            Spacer(minLength: 8)
                            
                            // Action Group Buttons with Liquid Glass
                            HStack(spacing: 7) {
                                // 1. Share Button
                                LiquidGlassCapsuleButton(action: copyShareLink) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "arrowshape.turn.up.right.fill")
                                            .font(.system(size: 11.5))
                                        Text("Chia sẻ")
                                            .font(.system(size: 12.5, weight: .medium))
                                            .lineLimit(1)
                                            .fixedSize()
                                    }
                                    .padding(.horizontal, 13)
                                    .frame(height: 32)
                                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                }
                                
                                // 2. Download Button
                                LiquidGlassCapsuleButton(action: { vm.showDownloadSheet = true }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "arrow.down.to.line")
                                            .font(.system(size: 11.5, weight: .medium))
                                        Text("Tải xuống")
                                            .font(.system(size: 12.5, weight: .medium))
                                            .lineLimit(1)
                                            .fixedSize()
                                    }
                                    .padding(.horizontal, 13)
                                    .frame(height: 32)
                                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                }
                                
                                // 3. Bookmark Button
                                let bookmarked = playerManager.isBookmarked(displayVideo)
                                LiquidGlassCapsuleButton(
                                    action: { playerManager.toggleBookmark(displayVideo) },
                                    isSelected: bookmarked
                                ) {
                                    HStack(spacing: 5) {
                                        Image(systemName: bookmarked ? "bookmark.fill" : "bookmark")
                                            .font(.system(size: 11.5))
                                        Text(bookmarked ? "Đã lưu" : "Lưu video")
                                            .font(.system(size: 12.5, weight: bookmarked ? .semibold : .medium))
                                    }
                                    .padding(.horizontal, 13)
                                    .frame(height: 32)
                                    .foregroundColor(
                                        bookmarked ?
                                            (colorScheme == .dark ? Color.black.opacity(0.92) : Color.white) :
                                            ThemeColor.textPrimary(for: colorScheme)
                                    )
                                }
                            }
                            .layoutPriority(1)
                        }
                        
                        // Description Box with Liquid Glass (Hỗ trợ mở rộng toàn bộ nội dung mô tả)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(videoDescriptionText)
                                .font(.system(size: 13))
                                .lineSpacing(4)
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.9))
                                .lineLimit(vm.isDescExpanded ? nil : 3)
                                .textSelection(.enabled)
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    vm.isDescExpanded.toggle()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(vm.isDescExpanded ? "Thu gọn" : "...xem thêm")
                                        .font(.system(size: 12.5, weight: .semibold))
                                    Image(systemName: vm.isDescExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.85))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ThemeColor.cardBackground(for: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(ThemeColor.cardBorder(for: colorScheme), lineWidth: 0.75)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                vm.isDescExpanded.toggle()
                            }
                        }
                        
                        // Comments Box (Bình luận của viewer - Hiển thị đầy đủ không ẩn/lược)
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .center) {
                                HStack(spacing: 8) {
                                    Text("Bình luận")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                    
                                    if !playerManager.comments.isEmpty {
                                        if playerManager.isLoadingMoreComments {
                                            if let total = playerManager.totalCommentsCountText {
                                                Text("(\(playerManager.comments.count) / \(total))")
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                            } else {
                                                Text("(\(playerManager.comments.count))")
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                            }
                                        } else {
                                            if let total = playerManager.totalCommentsCountText {
                                                Text("\(playerManager.comments.count) gốc • Tổng \(total)")
                                                    .font(.system(size: 12.5, weight: .medium))
                                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                            } else {
                                                Text("\(playerManager.comments.count)")
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                            }
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                if playerManager.isLoadingComments {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 16, height: 16)
                                } else {
                                    HStack(spacing: 10) {
                                        if playerManager.isLoadingMoreComments {
                                            HStack(spacing: 6) {
                                                ProgressView()
                                                    .scaleEffect(0.6)
                                                    .frame(width: 12, height: 12)
                                                Text("Đang tải...")
                                                    .font(.system(size: 11.5))
                                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                            }
                                        }
                                        
                                        // Sort Picker (Hàng đầu / Mới nhất)
                                        if playerManager.sortNewestToken != nil || playerManager.sortTopToken != nil {
                                            Menu {
                                                Button(action: { playerManager.switchCommentSort(to: .top) }) {
                                                    HStack {
                                                        Text("Bình luận hàng đầu")
                                                        if playerManager.commentSortMode == .top {
                                                            Image(systemName: "checkmark")
                                                        }
                                                    }
                                                }
                                                Button(action: { playerManager.switchCommentSort(to: .newest) }) {
                                                    HStack {
                                                        Text("Mới nhất trước (tải tối đa)")
                                                        if playerManager.commentSortMode == .newest {
                                                            Image(systemName: "checkmark")
                                                        }
                                                    }
                                                }
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "line.3.horizontal.decrease")
                                                        .font(.system(size: 10.5))
                                                    Text(playerManager.commentSortMode == .top ? "Hàng đầu" : "Mới nhất")
                                                        .font(.system(size: 11.5, weight: .medium))
                                                    Image(systemName: "chevron.down")
                                                        .font(.system(size: 8.5))
                                                }
                                                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3.5)
                                                .background(ThemeColor.buttonBackground(for: colorScheme, isHovered: false))
                                                .cornerRadius(6)
                                            }
                                            .menuStyle(BorderlessButtonMenuStyle())
                                        }
                                        
                                        Button(action: { playerManager.refreshComments() }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.clockwise")
                                                    .font(.system(size: 11))
                                                Text("Làm mới")
                                                    .font(.system(size: 12))
                                            }
                                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            
                            if playerManager.comments.isEmpty {
                                if playerManager.isLoadingComments {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .scaleEffect(0.75)
                                        Text("Đang tải bình luận của khán giả...")
                                            .font(.system(size: 13))
                                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                    }
                                    .padding(.vertical, 8)
                                } else {
                                    Text("Chưa có bình luận nào hiển thị hoặc video đã tắt tính năng bình luận.")
                                        .font(.system(size: 13))
                                        .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                                        .padding(.vertical, 6)
                                }
                            } else {
                                LazyVStack(alignment: .leading, spacing: 18) {
                                    ForEach(playerManager.comments) { comment in
                                        HStack(alignment: .top, spacing: 12) {
                                            // Avatar
                                            if let avatarUrl = comment.avatarUrl, let url = URL(string: avatarUrl) {
                                                AsyncImage(url: url) { phase in
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
                                                    Circle().fill(colorScheme == .dark ? Color(white: 0.25) : Color(white: 0.85))
                                                    Text(String(comment.author.prefix(1)).uppercased())
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                                }
                                                .frame(width: 36, height: 36)
                                            }
                                            
                                            // Comment Detail
                                            VStack(alignment: .leading, spacing: 5) {
                                                HStack(spacing: 8) {
                                                    Text(comment.author)
                                                        .font(.system(size: 13, weight: .semibold))
                                                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                                    
                                                    if !comment.publishedTime.isEmpty {
                                                        Text(comment.publishedTime)
                                                            .font(.system(size: 11.5))
                                                            .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                                                    }
                                                }
                                                
                                                // FULL text - strictly preserved without truncation
                                                Text(comment.text)
                                                    .font(.system(size: 13.5))
                                                    .lineSpacing(3)
                                                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.92))
                                                    .fixedSize(horizontal: false, vertical: true)
                                                
                                                // Likes & Reply count
                                                if !comment.likeCount.isEmpty || (comment.replyCount != nil && comment.replyCount != "0") {
                                                    HStack(spacing: 16) {
                                                        if !comment.likeCount.isEmpty {
                                                            HStack(spacing: 5) {
                                                                Image(systemName: "hand.thumbsup")
                                                                    .font(.system(size: 11))
                                                                Text(comment.likeCount)
                                                                    .font(.system(size: 11.5, weight: .medium))
                                                            }
                                                            .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                                                        }
                                                        
                                                        if let replies = comment.replyCount, !replies.isEmpty && replies != "0" {
                                                            HStack(spacing: 5) {
                                                                Image(systemName: "bubble.left.and.bubble.right")
                                                                    .font(.system(size: 11))
                                                                Text("\(replies) phản hồi")
                                                                    .font(.system(size: 11.5, weight: .medium))
                                                            }
                                                            .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                                                        }
                                                    }
                                                    .padding(.top, 2)
                                                }
                                            }
                                            Spacer(minLength: 0)
                                        }
                                    }
                                    
                                    // Bottom Infinite Loader / Load More Button
                                    if playerManager.isLoadingMoreComments {
                                        HStack(spacing: 8) {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                            Text("Đang tải thêm bình luận...")
                                                .font(.system(size: 12))
                                                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                        }
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 10)
                                    } else if playerManager.canLoadMoreComments {
                                        Button(action: {
                                            playerManager.loadMoreComments()
                                        }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "arrow.down.circle")
                                                    .font(.system(size: 12))
                                                Text("Tải thêm bình luận")
                                                    .font(.system(size: 12.5, weight: .medium))
                                            }
                                            .foregroundColor(Color(red: 0.2, green: 0.65, blue: 1.0))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(ThemeColor.buttonBackground(for: colorScheme, isHovered: false))
                                            .cornerRadius(8)
                                        }
                                        .buttonStyle(.plain)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 8)
                                        .onAppear {
                                            playerManager.loadMoreComments()
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ThemeColor.cardBackground(for: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(ThemeColor.cardBorder(for: colorScheme), lineWidth: 0.75)
                        )
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Right Column: Related Videos (Hardware-Accelerated LazyVStack for Butter-Smooth 120Hz Scrolling)
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Text("Video liên quan")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                        
                        ForEach(vm.relatedVideos) { item in
                            Button(action: { onSelectRelated(item) }) {
                                HStack(spacing: 10) {
                                    ZStack(alignment: .bottomTrailing) {
                                        ZStack {
                                            (colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.88))
                                            AsyncImage(url: URL(string: item.thumbnail)) { phase in
                                                if let img = phase.image {
                                                    img.resizable()
                                                        .aspectRatio(contentMode: item.isShort ? .fit : .fill)
                                                } else {
                                                    (colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.82))
                                                }
                                            }
                                        }
                                        .frame(width: 156, height: 88)
                                        .clipped()
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .strokeBorder(
                                                    LinearGradient(
                                                        colors: colorScheme == .dark
                                                            ? [Color.white.opacity(0.24), Color.white.opacity(0.06)]
                                                            : [Color.black.opacity(0.12), Color.black.opacity(0.04)],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    ),
                                                    lineWidth: 1
                                                )
                                        )
                                        
                                        HStack(spacing: 3) {
                                            if item.isShort {
                                                Image(systemName: "play.square.stack.fill")
                                                    .font(.system(size: 8.5))
                                                    .foregroundColor(.red)
                                            }
                                            Text(item.durationFormatted)
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.black.opacity(0.85))
                                        .cornerRadius(4)
                                        .foregroundColor(.white)
                                        .padding(4)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        Text(item.uploader)
                                            .font(.system(size: 12))
                                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                        if !item.metadataFormatted.isEmpty {
                                            Text(item.metadataFormatted)
                                                .font(.system(size: 11.5))
                                                .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(4)
                                .background(Color.white.opacity(0.001))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 320)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 40)
                }
            }
        }
        .sheet(isPresented: $vm.showDownloadSheet) {
            DownloadSheetView(video: displayVideo)
        }
        .onAppear {
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .task(id: displayVideo.id) {
            // Load related videos
            let related = await YTDLPService.shared.searchVideos(query: displayVideo.uploader)
            vm.relatedVideos = related
            if let firstNext = related.first(where: { $0.id != displayVideo.id }) {
                playerManager.nextVideo = firstNext
            }
        }
    }

    private func copyShareLink() {
        let url = "https://www.youtube.com/watch?v=\(displayVideo.id)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }
}

// MARK: - Dedicated Watch Player Container View with YouTube-Grade Hover & Auto-Hide
@MainActor
final class WatchPlayerViewModel: ObservableObject {
    @Published var isControlsVisible: Bool = true
    @Published var isMouseOverPlayer: Bool = false
    var hideTimer: Timer? = nil
    var mouseMonitor: Any? = nil
    var keyMonitor: Any? = nil
    weak var playerManager: PlayerManager?
    
    // Animated HUD State (Space / Arrow Seek Feedback)
    @Published var hudIcon: String = ""
    @Published var hudText: String = ""
    @Published var isHudVisible: Bool = false
    private var hudTimer: Timer? = nil
    
    func flashFeedback(icon: String, text: String) {
        hudTimer?.invalidate()
        hudIcon = icon
        hudText = text
        withAnimation(.easeOut(duration: 0.12)) {
            isHudVisible = true
        }
        hudTimer = Timer.scheduledTimer(withTimeInterval: 0.85, repeats: false) { [weak self] _ in
            Task { @MainActor in
                withAnimation(.easeIn(duration: 0.2)) {
                    self?.isHudVisible = false
                }
            }
        }
    }
    
    func scheduleAutoHide(delay: Double = 1.8) {
        hideTimer?.invalidate()
        hideTimer = nil
        // Khi chuột đang đặt trong frame player, TUYỆT ĐỐI không tự auto-hide toolbar
        guard !isMouseOverPlayer else { return }
        guard playerManager?.isPlaying == true else { return }
        
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                guard !self.isMouseOverPlayer else { return }
                if self.playerManager?.isPlaying == true {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.isControlsVisible = false
                    }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }
    
    func wakeControls() {
        if !isControlsVisible {
            withAnimation(.easeInOut(duration: 0.18)) {
                isControlsVisible = true
            }
        }
        if !isMouseOverPlayer {
            scheduleAutoHide(delay: 1.8)
        } else {
            hideTimer?.invalidate()
            hideTimer = nil
        }
    }
    
    func hideControlsImmediately() {
        hideTimer?.invalidate()
        hideTimer = nil
        if playerManager?.isPlaying == true {
            withAnimation(.easeInOut(duration: 0.15)) {
                isControlsVisible = false
            }
        }
    }
    
    func setupMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            if self.isMouseOverPlayer {
                Task { @MainActor in
                    self.wakeControls()
                }
            }
            return event
        }
    }
    
    func setupKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let pm = self.playerManager else { return event }
            
            // Check if user is currently typing in search bar or any text input
            if pm.isSearchFocused || self.isUserTyping(in: event) {
                if event.keyCode == 53 {
                    pm.isSearchFocused = false
                    DispatchQueue.main.async {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
                    return nil
                }
                // Khi người dùng đang nhập văn bản, vô hiệu hóa toàn bộ phím tắt video
                return event
            }
            
            guard pm.currentVideo != nil else { return event }
            
            // Khi PiP đang hoạt động hoặc sự kiện đến từ cửa sổ nổi PiP, nhường xử lý phím tắt cho PiPWindowController
            if pm.isPictureInPictureActive || (event.window is NSPanel) {
                return event
            }
            
            switch event.keyCode {
            case 49, 40: // Space (49) or K (40): Toggle Play / Pause
                pm.togglePlayPause()
                Task { @MainActor in
                    self.wakeControls()
                    self.flashFeedback(
                        icon: pm.isPlaying ? "play.fill" : "pause.fill",
                        text: pm.isPlaying ? "Đang phát" : "Tạm dừng"
                    )
                }
                return nil
                
            case 123, 38: // Left Arrow (123) or J (38): Seek -5s
                pm.seekRelative(-5)
                Task { @MainActor in
                    self.wakeControls()
                    self.flashFeedback(icon: "gobackward.5", text: "-5 giây")
                }
                return nil
                
            case 124, 37: // Right Arrow (124) or L (37): Seek +5s
                pm.seekRelative(5)
                Task { @MainActor in
                    self.wakeControls()
                    self.flashFeedback(icon: "goforward.5", text: "+5 giây")
                }
                return nil
                
            case 126: // Up Arrow (126): Volume Up
                let newVol = min(1.0, pm.volume + 0.05)
                pm.volume = newVol
                pm.isMuted = false
                Task { @MainActor in
                    self.wakeControls()
                    self.flashFeedback(icon: "speaker.wave.3.fill", text: "\(Int(newVol * 100))%")
                }
                return nil
                
            case 125: // Down Arrow (125): Volume Down
                let newVol = max(0.0, pm.volume - 0.05)
                pm.volume = newVol
                let iconName = newVol <= 0.01 ? "speaker.slash.fill" : (newVol < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")
                Task { @MainActor in
                    self.wakeControls()
                    self.flashFeedback(icon: iconName, text: "\(Int(newVol * 100))%")
                }
                return nil
                
            case 46: // M: Mute
                pm.isMuted.toggle()
                Task { @MainActor in
                    self.wakeControls()
                    self.flashFeedback(
                        icon: pm.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        text: pm.isMuted ? "Đã tắt tiếng" : "Bật âm thanh"
                    )
                }
                return nil
                
            case 3: // F: Fullscreen
                pm.toggleFullscreen()
                return nil
                
            case 35: // P: Picture-in-Picture
                pm.togglePictureInPicture()
                return nil
                
            case 29: pm.seek(to: 0); return nil // 0
            case 18: pm.seek(to: pm.duration * 0.1); return nil // 1
            case 19: pm.seek(to: pm.duration * 0.2); return nil // 2
            case 20: pm.seek(to: pm.duration * 0.3); return nil // 3
            case 21: pm.seek(to: pm.duration * 0.4); return nil // 4
            case 23: pm.seek(to: pm.duration * 0.5); return nil // 5
            case 22: pm.seek(to: pm.duration * 0.6); return nil // 6
            case 26: pm.seek(to: pm.duration * 0.7); return nil // 7
            case 28: pm.seek(to: pm.duration * 0.8); return nil // 8
            case 25: pm.seek(to: pm.duration * 0.9); return nil // 9
                
            default:
                return event
            }
        }
    }
    
    func cleanup() {
        if let mm = mouseMonitor {
            NSEvent.removeMonitor(mm)
            mouseMonitor = nil
        }
        if let km = keyMonitor {
            NSEvent.removeMonitor(km)
            keyMonitor = nil
        }
        hideTimer?.invalidate()
        hideTimer = nil
        hudTimer?.invalidate()
        hudTimer = nil
    }
    
    private func isUserTyping(in event: NSEvent) -> Bool {
        guard let window = event.window ?? NSApp.keyWindow else { return false }
        guard let responder = window.firstResponder else { return false }
        if responder is NSTextView || responder is NSTextField || responder is NSText {
            return true
        }
        let name = String(describing: type(of: responder))
        if name.contains("Text") || name.contains("Field") || name.contains("Editor") {
            return true
        }
        return false
    }
    
    deinit {
        if let mm = mouseMonitor {
            NSEvent.removeMonitor(mm)
        }
        if let km = keyMonitor {
            NSEvent.removeMonitor(km)
        }
        hideTimer?.invalidate()
        hudTimer?.invalidate()
    }
}

@MainActor
struct WatchPlayerContainerView: View {
    let displayVideo: Video
    @ObservedObject var playerManager: PlayerManager
    @StateObject private var vm = WatchPlayerViewModel()
    
    var body: some View {
        let isVertical: Bool = {
            let dur = displayVideo.totalDurationSeconds
            let pDur = playerManager.duration
            // Video dài hơn 65s chắc chắn là video ngang truyền thống (16:9)
            if dur > 65 || pDur > 65 {
                return false
            }
            if playerManager.isCurrentVideoVertical {
                return true
            }
            if displayVideo.durationFormatted == "Shorts" || displayVideo.isExplicitShort == true || displayVideo.isShort {
                return true
            }
            if playerManager.currentVideoAspectRatio > 0 && playerManager.currentVideoAspectRatio < 0.95 {
                return true
            }
            return false
        }()
        
        ZStack {
            if !playerManager.isPictureInPictureActive {
                if isVertical {
                    verticalPlayer
                } else {
                    horizontalPlayer
                }
            } else {
                pipPlaceholder
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playerManager.exitPictureInPicture()
                    }
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .onHover { isHovered in
            vm.isMouseOverPlayer = isHovered
            if isHovered {
                vm.wakeControls()
                if PlayerManager.shared.isSearchFocused {
                    PlayerManager.shared.isSearchFocused = false
                    DispatchQueue.main.async {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
                }
            } else {
                vm.hideControlsImmediately()
            }
        }
        .onAppear {
            vm.playerManager = playerManager
            vm.setupMouseMonitor()
            vm.setupKeyMonitor()
            vm.scheduleAutoHide(delay: 2.0)
        }
        .onDisappear {
            vm.cleanup()
        }
        .onChange(of: playerManager.isPlaying) { isPlaying in
            if isPlaying {
                vm.scheduleAutoHide(delay: 1.8)
            } else {
                withAnimation(.easeInOut(duration: 0.18)) {
                    vm.isControlsVisible = true
                }
                vm.hideTimer?.invalidate()
                vm.hideTimer = nil
            }
        }
    }
    
    // MARK: - Picture-in-Picture Placeholder (Exact 1:1 Match with Native Player Frame & Rounded Corners)
    private var pipPlaceholder: some View {
        let isVertical: Bool = {
            let dur = displayVideo.totalDurationSeconds
            let pDur = playerManager.duration
            if dur > 65 || pDur > 65 { return false }
            return playerManager.isCurrentVideoVertical || displayVideo.isShort
        }()
        
        let content = ZStack {
            // 1. Dark Base
            Color(red: 16/255, green: 16/255, blue: 18/255)
            
            // 2. Hardware-Constrained Blurred Thumbnail (Never overflows or distorts column layout)
            GeometryReader { geo in
                AsyncImage(url: URL(string: displayVideo.thumbnail)) { phase in
                    if let img = phase.image {
                        img.resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                }
                .blur(radius: 28)
                .opacity(0.32)
            }
            .allowsHitTesting(false)
            
            // 3. Cinematic Vignette
            LinearGradient(
                colors: [Color.black.opacity(0.4), Color.black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            
            // 4. Centered PiP Status & Action
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 60, height: 60)
                    Image(systemName: "pip")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text("Video đang phát ở chế độ Picture-in-Picture")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Cửa sổ nổi đang hiển thị trên màn hình của bạn")
                    .font(.system(size: 12.5))
                    .foregroundColor(.white.opacity(0.70))
                
                Button(action: {
                    playerManager.togglePictureInPicture()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "pip.exit")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Đưa video về cửa sổ chính")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8.5)
                    .background(Color.red)
                    .clipShape(Capsule())
                    .shadow(color: Color.red.opacity(0.4), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(20)
        }
        
        return Group {
            if isVertical {
                content
                    .frame(maxWidth: .infinity)
                    .frame(height: 580)
            } else {
                content
                    .aspectRatio(16/9, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
    }
    
    // MARK: - Vertical Player (Strict 9:16 Centered Card, No Horizontal Zoom Fit)
    private var verticalPlayer: some View {
        let verticalRatio: CGFloat = 9.0 / 16.0
        let playerHeight: CGFloat = 580
        let playerWidth: CGFloat = playerHeight * verticalRatio
        
        return HStack {
            Spacer(minLength: 0)
            
            ZStack(alignment: .bottom) {
                // Centered 9:16 Video Player
                NativePlayerView(cornerRadius: 16)
                    .frame(width: playerWidth, height: playerHeight)
                
                // Click to play/pause, double click for fullscreen
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .frame(width: playerWidth, height: playerHeight)
                    .onTapGesture(count: 2) {
                        DispatchQueue.main.async {
                            NSApp.keyWindow?.makeFirstResponder(nil)
                        }
                        playerManager.toggleFullscreen()
                    }
                    .simultaneousGesture(
                        TapGesture(count: 1).onEnded {
                            DispatchQueue.main.async {
                                NSApp.keyWindow?.makeFirstResponder(nil)
                            }
                            playerManager.togglePlayPause()
                        }
                    )
                
                // Center Play/Pause Indicator
                centerPlayPauseOverlay
                
                // Autoplay Countdown Overlay
                if playerManager.autoplayCountdown != nil, let next = playerManager.nextVideo {
                    AutoplayCountdownOverlay(video: next)
                }
                
                // Bottom Controls fitted to the 9:16 player frame
                PlayerControlOverlay()
                    .frame(width: playerWidth)
                    .opacity(vm.isControlsVisible ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.18), value: vm.isControlsVisible)
                    .allowsHitTesting(vm.isControlsVisible)
                
                // Top Corner Badge for Vertical Video
                VStack {
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "rectangle.portrait.fill")
                                .font(.system(size: 10.5))
                            Text("Khổ dọc 9:16")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(Color.white.opacity(0.92))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(Color.black.opacity(0.65))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                        )
                        .padding(12)
                        
                        Spacer()
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
                .opacity(vm.isControlsVisible ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.18), value: vm.isControlsVisible)
            }
            .frame(width: playerWidth, height: playerHeight)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Horizontal 16:9 Player
    private var horizontalPlayer: some View {
        ZStack(alignment: .bottom) {
            NativePlayerView(cornerRadius: 16)
            
            // Click to play/pause, double click for fullscreen
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    DispatchQueue.main.async {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
                    playerManager.toggleFullscreen()
                }
                .simultaneousGesture(
                    TapGesture(count: 1).onEnded {
                        DispatchQueue.main.async {
                            NSApp.keyWindow?.makeFirstResponder(nil)
                        }
                        playerManager.togglePlayPause()
                    }
                )
            
            // Top Channel & Video Info Header (Positioned properly with safe margins)
            topChannelHeaderOverlay
            
            // Center Play/Pause Indicator (Synchronized with Timeline)
            centerPlayPauseOverlay
            
            // Bottom Controls with YouTube Auto-Hide
            PlayerControlOverlay()
                .opacity(vm.isControlsVisible ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.18), value: vm.isControlsVisible)
                .allowsHitTesting(vm.isControlsVisible)
            
            // Autoplay Countdown Overlay
            if playerManager.autoplayCountdown != nil, let next = playerManager.nextVideo {
                AutoplayCountdownOverlay(video: next)
            }
            
            // HUD Feedback Badge (Space / Arrow Seek / Volume)
            if vm.isHudVisible {
                VStack(spacing: 6) {
                    Image(systemName: vm.hudIcon)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    if !vm.hudText.isEmpty {
                        Text(vm.hudText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.80))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                        )
                )
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
    }
    
    // MARK: - Top Channel Header Overlay (Clean Apple-Style Capsule)
    private var topChannelHeaderOverlay: some View {
        VStack {
            HStack(alignment: .center, spacing: 10) {
                // Channel Avatar
                if let avatarUrl = displayVideo.channelAvatarUrl, !avatarUrl.isEmpty {
                    AsyncImage(url: URL(string: avatarUrl)) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            Circle().fill(Color.white.opacity(0.15))
                        }
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "play.tv.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.8))
                        )
                }
                
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(displayVideo.uploader)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
                    
                    if !displayVideo.title.isEmpty {
                        Text(displayVideo.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.82))
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
                    }
                }
                .frame(maxWidth: 320, alignment: .leading)
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    Capsule()
                        .fill(Color.black.opacity(0.65))
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                }
            )
            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 3)
            .padding(.leading, 16)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(vm.isControlsVisible ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.18), value: vm.isControlsVisible)
        .allowsHitTesting(false)
    }
    
    // MARK: - Center Play / Pause Indicator (Synchronized with Timeline)
    private var centerPlayPauseOverlay: some View {
        Group {
            if !playerManager.isPlaying {
                Button(action: {
                    playerManager.togglePlayPause()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.62))
                            .frame(width: 68, height: 68)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.4), Color.white.opacity(0.12)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.2
                                    )
                            )
                            .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 4)
                        
                        Image(systemName: "play.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: 2)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .opacity(vm.isControlsVisible ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.18), value: vm.isControlsVisible)
                .allowsHitTesting(vm.isControlsVisible)
            }
        }
    }
}

