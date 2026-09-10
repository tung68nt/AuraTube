import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var selectedTag = "Tất cả"
    @Published var isLoading = true
}

public struct HomeView: View {
    var onSelectVideo: (Video) -> Void
    
    @StateObject private var vm = HomeViewModel()
    
    private let tags = [
        "Tất cả", "Âm nhạc", "Trực tiếp", "Trò chơi",
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
                            LiquidGlassCapsuleButton(
                                action: { selectTag(tag) },
                                isSelected: vm.selectedTag == tag
                            ) {
                                Text(tag)
                                    .font(.system(size: 12.5, weight: vm.selectedTag == tag ? .semibold : .medium))
                                    .foregroundColor(vm.selectedTag == tag ? Color.black.opacity(0.88) : Color.white.opacity(0.80))
                                    .padding(.horizontal, 13)
                                    .frame(height: 28)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                }
                
                // 2. Section Title
                Text("Thịnh hành")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                
                // 3. Video Grid
                if vm.isLoading && vm.videos.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Đang tải danh sách video...")
                            .font(.system(size: 13))
                            .foregroundColor(Color(white: 0.6))
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    LazyVGrid(columns: columns, spacing: 28) {
                        ForEach(vm.videos) { video in
                            VideoCardView(video: video) {
                                onSelectVideo(video)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
            .padding(.bottom, 40)
        }
        .task {
            await loadVideos()
        }
    }
    
    private func selectTag(_ tag: String) {
        vm.selectedTag = tag
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
    
    private func loadVideos() async {
        vm.isLoading = true
        vm.videos = await YTDLPService.shared.fetchTrendingVideos()
        vm.isLoading = false
    }
}

@MainActor
final class CardHoverViewModel: ObservableObject {
    @Published var isHovered = false
}

public struct VideoCardView: View {
    let video: Video
    let onSelect: () -> Void
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
                            Color(white: 0.12)
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
                                        Color.white.opacity(hoverVm.isHovered ? 0.24 : 0.12),
                                        Color.white.opacity(hoverVm.isHovered ? 0.08 : 0.02)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.75
                            )
                    )
                    .shadow(color: .black.opacity(hoverVm.isHovered ? 0.38 : 0.20), radius: hoverVm.isHovered ? 10 : 5, y: hoverVm.isHovered ? 4 : 2)
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
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.26)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 36, height: 36)
                            .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                        Text(String(video.uploader.prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(video.title)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundColor(Color(white: 0.95))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(2)
                        
                        Text(video.uploader)
                            .font(.system(size: 12.5))
                            .foregroundColor(Color(white: 0.65))
                        
                        if !video.metadataFormatted.isEmpty {
                            Text(video.metadataFormatted)
                                .font(.system(size: 12))
                                .foregroundColor(Color(white: 0.45))
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
