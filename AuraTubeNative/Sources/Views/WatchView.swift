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
    @StateObject private var vm = WatchViewModel()
    
    public init(video: Video, onBack: @escaping () -> Void, onSelectRelated: @escaping (Video) -> Void) {
        self.video = video
        self.onBack = onBack
        self.onSelectRelated = onSelectRelated
    }
    
    private var displayVideo: Video {
        playerManager.currentVideo ?? video
    }
    
    public var body: some View {
        Group {
            if playerManager.isVideoFullscreen {
                FullscreenVideoOverlay(video: displayVideo)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Main Two-Column Layout
                        HStack(alignment: .top, spacing: 24) {
                            // Left Column: Player & Details
                            VStack(alignment: .leading, spacing: 14) {
                                // Native Video Player with Interactive Scrubber & Controls
                                ZStack(alignment: .bottom) {
                                    NativePlayerView()
                                    
                                    // Bottom Player Controls (Thanh tua & điều khiển)
                                    PlayerControlOverlay()
                                    
                                    // Autoplay Countdown Overlay
                                    if playerManager.autoplayCountdown != nil, let next = playerManager.nextVideo {
                                        AutoplayCountdownOverlay(video: next)
                                    }
                                }
                                .aspectRatio(16/9, contentMode: .fit)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
                                
                                // Video Title
                                Text(displayVideo.title)
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .padding(.top, 4)
                        
                        // Action Bar: Uploader + Buttons
                        HStack(alignment: .center, spacing: 16) {
                            // Uploader info
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 42, height: 42)
                                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                                    Text(String(displayVideo.uploader.prefix(1)).uppercased())
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(displayVideo.uploader)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(Color(white: 0.95))
                                        .lineLimit(1)
                                    Text(displayVideo.metadataFormatted.isEmpty ? "YouTube" : displayVideo.metadataFormatted)
                                        .font(.system(size: 12.5))
                                        .foregroundColor(Color(white: 0.65))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: 200, alignment: .leading)
                                
                                // Subscribe Button
                                LiquidGlassCapsuleButton(
                                    action: { vm.isSubscribed.toggle() },
                                    isSelected: !vm.isSubscribed
                                ) {
                                    Text(vm.isSubscribed ? "Đã đăng ký" : "Đăng ký")
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .lineLimit(1)
                                        .fixedSize()
                                        .padding(.horizontal, 14)
                                        .frame(height: 32)
                                        .foregroundColor(vm.isSubscribed ? Color.white.opacity(0.85) : Color.black.opacity(0.88))
                                }
                                .padding(.leading, 4)
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
                                    .foregroundColor(Color.white.opacity(0.90))
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
                                    .foregroundColor(Color.white.opacity(0.90))
                                }
                                
                                // 3. Bookmark Button
                                let bookmarked = playerManager.isBookmarked(video)
                                LiquidGlassCapsuleButton(
                                    action: { playerManager.toggleBookmark(video) },
                                    isProminent: bookmarked
                                ) {
                                    HStack(spacing: 5) {
                                        Image(systemName: bookmarked ? "bookmark.fill" : "bookmark")
                                            .font(.system(size: 11.5))
                                        Text(bookmarked ? "Đã lưu" : "Lưu video")
                                            .font(.system(size: 12.5, weight: bookmarked ? .semibold : .medium))
                                            .lineLimit(1)
                                            .fixedSize()
                                    }
                                    .padding(.horizontal, 13)
                                    .frame(height: 32)
                                    .foregroundColor(.white)
                                }
                            }
                            .layoutPriority(1)
                        }
                        
                        // Description Box with Liquid Glass
                        VStack(alignment: .leading, spacing: 8) {
                            Text(video.description ?? "Không có mô tả.")
                                .font(.system(size: 13))
                                .lineSpacing(3.5)
                                .foregroundColor(Color.white.opacity(0.82))
                                .lineLimit(vm.isDescExpanded ? nil : 3)
                            
                            Button(action: { vm.isDescExpanded.toggle() }) {
                                Text(vm.isDescExpanded ? "Thu gọn" : "...xem thêm")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.92))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .liquidGlass(cornerRadius: 12, elevation: 2.5)
                        
                        // Comments Box (Bình luận của viewer - Hiển thị đầy đủ không ẩn/lược)
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .center) {
                                HStack(spacing: 8) {
                                    Text("Bình luận")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                    
                                    if !playerManager.comments.isEmpty {
                                        if playerManager.isLoadingMoreComments {
                                            if let total = playerManager.totalCommentsCountText {
                                                Text("(\(playerManager.comments.count) / \(total))")
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(Color(white: 0.6))
                                            } else {
                                                Text("(\(playerManager.comments.count))")
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(Color(white: 0.6))
                                            }
                                        } else {
                                            if let total = playerManager.totalCommentsCountText {
                                                Text("\(playerManager.comments.count) gốc • Tổng \(total)")
                                                    .font(.system(size: 12.5, weight: .medium))
                                                    .foregroundColor(Color(white: 0.65))
                                            } else {
                                                Text("\(playerManager.comments.count)")
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(Color(white: 0.6))
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
                                                    .foregroundColor(Color(white: 0.6))
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
                                                .foregroundColor(Color(white: 0.75))
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3.5)
                                                .background(Color(white: 0.16))
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
                                            .foregroundColor(Color(white: 0.6))
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
                                            .foregroundColor(Color(white: 0.6))
                                    }
                                    .padding(.vertical, 8)
                                } else {
                                    Text("Chưa có bình luận nào hiển thị hoặc video đã tắt tính năng bình luận.")
                                        .font(.system(size: 13))
                                        .foregroundColor(Color(white: 0.5))
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
                                                        Circle().fill(Color(white: 0.2))
                                                    }
                                                }
                                                .frame(width: 36, height: 36)
                                                .clipShape(Circle())
                                                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                                            } else {
                                                ZStack {
                                                    Circle().fill(Color(white: 0.25))
                                                    Text(String(comment.author.prefix(1)).uppercased())
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundColor(.white)
                                                }
                                                .frame(width: 36, height: 36)
                                            }
                                            
                                            // Comment Detail
                                            VStack(alignment: .leading, spacing: 5) {
                                                HStack(spacing: 8) {
                                                    Text(comment.author)
                                                        .font(.system(size: 13, weight: .semibold))
                                                        .foregroundColor(Color(white: 0.95))
                                                    
                                                    if !comment.publishedTime.isEmpty {
                                                        Text(comment.publishedTime)
                                                            .font(.system(size: 11.5))
                                                            .foregroundColor(Color(white: 0.5))
                                                    }
                                                }
                                                
                                                // FULL text - strictly preserved without truncation
                                                Text(comment.text)
                                                    .font(.system(size: 13.5))
                                                    .lineSpacing(3)
                                                    .foregroundColor(Color(white: 0.88))
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
                                                            .foregroundColor(Color(white: 0.55))
                                                        }
                                                        
                                                        if let replies = comment.replyCount, !replies.isEmpty && replies != "0" {
                                                            HStack(spacing: 5) {
                                                                Image(systemName: "bubble.left.and.bubble.right")
                                                                    .font(.system(size: 11))
                                                                Text("\(replies) phản hồi")
                                                                    .font(.system(size: 11.5, weight: .medium))
                                                            }
                                                            .foregroundColor(Color(white: 0.55))
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
                                                .foregroundColor(Color(white: 0.6))
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
                                            .background(Color.white.opacity(0.06))
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
                        .liquidGlass(cornerRadius: 14, elevation: 3)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Right Column: Related Videos
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Video liên quan")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        
                        ForEach(vm.relatedVideos) { item in
                            Button(action: { onSelectRelated(item) }) {
                                HStack(spacing: 10) {
                                    ZStack(alignment: .bottomTrailing) {
                                        AsyncImage(url: URL(string: item.thumbnail)) { phase in
                                            if let img = phase.image {
                                                img.resizable().scaledToFill()
                                            } else {
                                                Color(white: 0.12)
                                            }
                                        }
                                        .frame(width: 156, height: 88)
                                        .clipped()
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .strokeBorder(
                                                    LinearGradient(
                                                        colors: [Color.white.opacity(0.24), Color.white.opacity(0.06)],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    ),
                                                    lineWidth: 1
                                                )
                                        )
                                        
                                        Text(item.durationFormatted)
                                            .font(.system(size: 11, weight: .medium))
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
                                            .foregroundColor(.white)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        Text(item.uploader)
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(white: 0.65))
                                        if !item.metadataFormatted.isEmpty {
                                            Text(item.metadataFormatted)
                                                .font(.system(size: 11.5))
                                                .foregroundColor(Color(white: 0.5))
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
