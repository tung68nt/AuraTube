import SwiftUI

public enum NavigationSection: String, CaseIterable, Identifiable {
    case home = "Trang chủ"
    case shorts = "Shorts"
    case bookmarks = "Xem sau"
    case history = "Video đã xem"
    case downloads = "Tệp đã tải về"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .shorts: return "play.square.stack.fill"
        case .bookmarks: return "bookmark.fill"
        case .history: return "clock.fill"
        case .downloads: return "arrow.down.circle.fill"
        }
    }
}

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var selectedSection: NavigationSection = .home
    @Published var watchingVideo: Video?
    @Published var selectedShortVideo: Video? = nil
    @Published var searchQuery: String = ""
    @Published var searchResults: [Video] = []
    @Published var isSearching: Bool = false
    
    // Structured Search Results & Categories
    @Published var searchChannel: ChannelInfo? = nil
    @Published var searchVideos: [Video] = []
    @Published var searchShorts: [Video] = []
    @Published var searchFilter: String = "Tất cả"
    
    // Expanded Discovery: Related Searches & Dynamic Contextual Chips
    @Published var relatedSearches: [String] = []
    @Published var contextualChips: [String] = []
    
    // Direct YouTube URL Parsing & Quick Modal
    @Published var detectedURLResult: YouTubeURLParseResult? = nil
    @Published var showOpenURLSheet: Bool = false
    
    // Autocomplete Suggestions & Infinite Scroll Pagination
    @Published var searchSuggestions: [String] = []
    @Published var showSuggestions: Bool = false
    @Published var selectedSuggestionIndex: Int = -1
    @Published var selectedSearchResultIndex: Int = -1
    var isNavigatingSuggestions: Bool = false
    var originalUserQuery: String = ""
    
    @Published var searchContinuationToken: String? = nil
    @Published var isLoadingSearch: Bool = false
    @Published var isLoadingMoreSearch: Bool = false
    @Published var canLoadMoreSearch: Bool = true
    @Published var isSidebarDrawerOpen: Bool = false
    
    private var suggestionTask: Task<Void, Never>? = nil
    
    var currentSuggestionItems: [String] {
        if !searchSuggestions.isEmpty {
            return Array(searchSuggestions.prefix(10))
        } else {
            let recents = Array(RecommendationService.shared.recentSearches.prefix(5))
            let tags = RecommendationService.shared.dynamicInterestTags.prefix(5).filter { t in
                !recents.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame })
            }
            return recents + tags
        }
    }
    
    func selectNextSuggestion() {
        let items = currentSuggestionItems
        let hasURL = (detectedURLResult != nil)
        let totalCount = (hasURL ? 1 : 0) + items.count
        guard totalCount > 0 else { return }
        
        if selectedSuggestionIndex == -1 {
            originalUserQuery = searchQuery
        }
        
        let nextIndex = selectedSuggestionIndex + 1
        if nextIndex < totalCount {
            selectedSuggestionIndex = nextIndex
            let itemIndex = hasURL ? (nextIndex - 1) : nextIndex
            if itemIndex >= 0 && itemIndex < items.count {
                let newText = items[itemIndex]
                if searchQuery != newText {
                    isNavigatingSuggestions = true
                    searchQuery = newText
                }
            } else if hasURL && nextIndex == 0 {
                if searchQuery != originalUserQuery {
                    isNavigatingSuggestions = true
                    searchQuery = originalUserQuery
                }
            }
        } else {
            selectedSuggestionIndex = -1
            if searchQuery != originalUserQuery {
                isNavigatingSuggestions = true
                searchQuery = originalUserQuery
            }
        }
    }
    
    func selectPreviousSuggestion() {
        let items = currentSuggestionItems
        let hasURL = (detectedURLResult != nil)
        let totalCount = (hasURL ? 1 : 0) + items.count
        guard totalCount > 0 else { return }
        
        if selectedSuggestionIndex == -1 {
            originalUserQuery = searchQuery
            selectedSuggestionIndex = totalCount - 1
            let itemIndex = hasURL ? (selectedSuggestionIndex - 1) : selectedSuggestionIndex
            if itemIndex >= 0 && itemIndex < items.count {
                let newText = items[itemIndex]
                if searchQuery != newText {
                    isNavigatingSuggestions = true
                    searchQuery = newText
                }
            } else if hasURL && selectedSuggestionIndex == 0 {
                if searchQuery != originalUserQuery {
                    isNavigatingSuggestions = true
                    searchQuery = originalUserQuery
                }
            }
        } else if selectedSuggestionIndex == 0 {
            selectedSuggestionIndex = -1
            if searchQuery != originalUserQuery {
                isNavigatingSuggestions = true
                searchQuery = originalUserQuery
            }
        } else {
            selectedSuggestionIndex -= 1
            let itemIndex = hasURL ? (selectedSuggestionIndex - 1) : selectedSuggestionIndex
            if itemIndex >= 0 && itemIndex < items.count {
                let newText = items[itemIndex]
                if searchQuery != newText {
                    isNavigatingSuggestions = true
                    searchQuery = newText
                }
            } else if hasURL && selectedSuggestionIndex == 0 {
                if searchQuery != originalUserQuery {
                    isNavigatingSuggestions = true
                    searchQuery = originalUserQuery
                }
            }
        }
    }
    
    func updateSearchSuggestions(for query: String) {
        if isNavigatingSuggestions { return }
        originalUserQuery = query
        selectedSuggestionIndex = -1
        
        suggestionTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Direct URL detection: check if input is a valid YouTube link or raw video ID
        if let parsed = YouTubeURLParser.parse(trimmed) {
            self.detectedURLResult = parsed
            self.searchSuggestions = []
            self.showSuggestions = true
            return
        } else {
            self.detectedURLResult = nil
        }
        
        // 2. Empty query: show recent searches and personalized dynamic interest tags
        guard !trimmed.isEmpty else {
            let recents = RecommendationService.shared.recentSearches
            let tags = RecommendationService.shared.dynamicInterestTags
            var combined = recents
            for t in tags {
                if !combined.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) {
                    combined.append(t)
                }
            }
            self.searchSuggestions = Array(combined.prefix(10))
            self.showSuggestions = !self.searchSuggestions.isEmpty
            return
        }
        
        // 3. Normal search text: fast debounce & fetch autocomplete suggestions
        suggestionTask = Task {
            try? await Task.sleep(nanoseconds: 130_000_000) // 130ms debounce
            guard !Task.isCancelled else { return }
            let suggestions = await YTDLPService.shared.fetchSearchSuggestions(query: trimmed)
            guard !Task.isCancelled else { return }
            self.searchSuggestions = suggestions
            self.showSuggestions = !suggestions.isEmpty
        }
    }
    
    func dismissSuggestions() {
        suggestionTask?.cancel()
        showSuggestions = false
        selectedSuggestionIndex = -1
        isNavigatingSuggestions = false
    }
    
    // MARK: - Channel Detail View State & Navigation
    @Published var selectedChannel: ChannelInfo? = nil
    @Published var channelVideos: [Video] = []
    @Published var channelBannerUrl: String? = nil
    @Published var isLoadingChannel: Bool = false
    @Published var channelContinuationToken: String? = nil
    @Published var isLoadingMoreChannel: Bool = false
    private var channelFetchTask: Task<Void, Never>? = nil
    var previousWatchingVideo: Video? = nil
    
    func openChannel(_ channel: ChannelInfo) {
        dismissSuggestions()
        isSidebarDrawerOpen = false
        
        // Save current watching video if any, so "Quay lại" can restore it
        if watchingVideo != nil {
            previousWatchingVideo = watchingVideo
            watchingVideo = nil
        }
        
        selectedChannel = channel
        channelVideos = []
        channelBannerUrl = nil
        channelContinuationToken = nil
        isLoadingChannel = true
        
        channelFetchTask?.cancel()
        channelFetchTask = Task {
            let result = await YTDLPService.shared.fetchChannelDetails(
                channelIdOrQuery: channel.id.isEmpty ? channel.title : channel.id,
                fallbackInfo: channel
            )
            guard !Task.isCancelled else { return }
            if let result = result {
                self.selectedChannel = result.channel
                self.channelBannerUrl = result.bannerUrl
                self.channelVideos = result.videos
                self.channelContinuationToken = result.continuationToken
            } else {
                let query = (channel.handle?.hasPrefix("@") == true) ? channel.handle! : channel.title
                let fetched = await YTDLPService.shared.searchVideos(query: query, limit: 24)
                guard !Task.isCancelled else { return }
                self.channelVideos = fetched
            }
            self.isLoadingChannel = false
        }
    }
    
    func closeChannel() {
        channelFetchTask?.cancel()
        selectedChannel = nil
        channelVideos = []
        channelBannerUrl = nil
        channelContinuationToken = nil
        isLoadingChannel = false
        
        if let prev = previousWatchingVideo, PlayerManager.shared.currentVideo?.id == prev.id {
            watchingVideo = prev
        }
        previousWatchingVideo = nil
    }
    
    func loadMoreChannelVideos() {
        guard let token = channelContinuationToken, !isLoadingMoreChannel, let channel = selectedChannel else { return }
        isLoadingMoreChannel = true
        Task {
            let result = await YTDLPService.shared.fetchChannelDetails(
                channelIdOrQuery: channel.id,
                fallbackInfo: channel,
                continuationToken: token
            )
            guard let result = result else {
                self.isLoadingMoreChannel = false
                self.channelContinuationToken = nil
                return
            }
            let existingIds = Set(self.channelVideos.map { $0.id })
            let newVideos = result.videos.filter { !existingIds.contains($0.id) }
            self.channelVideos.append(contentsOf: newVideos)
            self.channelContinuationToken = result.continuationToken
            self.isLoadingMoreChannel = false
        }
    }
}

// MARK: - Authentic YouTube Logo Badge (Official Bezier Geometry)
struct YouTubeBadgePath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sx = rect.width / 28.5701
        let sy = rect.height / 20.0
        
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }
        
        path.move(to: p(27.9727, 3.12324))
        path.addCurve(to: p(25.4468, 0.597366), control1: p(27.6435, 1.89323), control2: p(26.6768, 0.926623))
        path.addCurve(to: p(14.285, 0), control1: p(23.2197, 0), control2: p(14.285, 0))
        path.addCurve(to: p(3.12323, 0.597366), control1: p(14.285, 0), control2: p(5.35042, 0))
        path.addCurve(to: p(0.597366, 3.12324), control1: p(1.89323, 0.926623), control2: p(0.926623, 1.89323))
        path.addCurve(to: p(0, 10), control1: p(0, 5.35042), control2: p(0, 10))
        path.addCurve(to: p(0.597366, 16.8768), control1: p(0, 10), control2: p(0, 14.6496))
        path.addCurve(to: p(3.12323, 19.4026), control1: p(0.926623, 18.1068), control2: p(1.89323, 19.0734))
        path.addCurve(to: p(14.285, 20), control1: p(5.35042, 20), control2: p(14.285, 20))
        path.addCurve(to: p(25.4468, 19.4026), control1: p(14.285, 20), control2: p(23.2197, 20))
        path.addCurve(to: p(27.9727, 16.8768), control1: p(26.6768, 19.0734), control2: p(27.6435, 18.1068))
        path.addCurve(to: p(28.5701, 10), control1: p(28.5701, 14.6496), control2: p(28.5701, 10))
        path.addCurve(to: p(27.9727, 3.12324), control1: p(28.5701, 10), control2: p(28.5677, 5.35042))
        path.closeSubpath()
        return path
    }
}

struct YouTubeTrianglePath: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let sx = rect.width / 28.5701
        let sy = rect.height / 20.0
        
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }
        
        path.move(to: p(11.4253, 14.2854))
        path.addLine(to: p(18.8477, 10.0004))
        path.addLine(to: p(11.4253, 5.71533))
        path.closeSubpath()
        return path
    }
}

struct YouTubeBrandBadge: View {
    var width: CGFloat = 24
    
    var body: some View {
        let height = width * (20.0 / 28.5701)
        ZStack {
            YouTubeBadgePath()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.08, blue: 0.12), Color(red: 0.88, green: 0.0, blue: 0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            YouTubeTrianglePath()
                .fill(Color.white)
        }
        .frame(width: width, height: height)
    }
}

struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            if let w = v.window { onWindow(w) }
        }
        return v
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let w = nsView.window { onWindow(w) }
    }
}


struct SidebarNavButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let section: NavigationSection
    let isSelected: Bool
    let action: () -> Void
    @StateObject private var hoverVm = LiquidHoverViewModel()
    
    var body: some View {
        let isDark = (colorScheme == .dark)
        let activeColor = isDark ? Color.white : Color(red: 15/255, green: 15/255, blue: 15/255)
        let inactiveColor = isDark ? Color.white.opacity(0.68) : Color(red: 96/255, green: 96/255, blue: 96/255)
        let hoverColor = isDark ? Color.white : Color(red: 15/255, green: 15/255, blue: 15/255)
        
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.iconName)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? (isDark ? .white : Color(red: 0.95, green: 0.20, blue: 0.20)) : (hoverVm.isHovered ? hoverColor : inactiveColor))
                    .frame(width: 26)
                
                Text(section.rawValue)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? activeColor : (hoverVm.isHovered ? hoverColor : inactiveColor))
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        isDark ?
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.24), Color.white.opacity(0.06)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            ) :
                                            LinearGradient(
                                                colors: [Color.black.opacity(0.12), Color.black.opacity(0.04)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            ),
                                        lineWidth: 0.75
                                    )
                            )
                    } else if hoverVm.isHovered {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.04))
                    } else {
                        Color.clear
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoverVm.isHovered = hovering
        }
        .padding(.horizontal, 10)
    }
}

public struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var playerManager = PlayerManager.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var updateService = UpdateService.shared
    @StateObject private var vm = ContentViewModel()
    
    @AppStorage("isSidebarCollapsedByUser") private var isSidebarCollapsedByUser: Bool = false
    @FocusState private var isSearchFocused: Bool
    @State private var showSettingsSheet: Bool = false
    @State private var searchKeyMonitor: Any? = nil
    
    public init() {}
    
    private var isSidebarVisible: Bool {
        // Auto-hide sidebar when watching video to maximize player width
        if vm.watchingVideo != nil {
            return false
        }
        return !isSidebarCollapsedByUser
    }
    
    private var sidebarToggleTooltip: String {
        if vm.watchingVideo != nil {
            return vm.isSidebarDrawerOpen ? "Đóng danh mục" : "Mở danh mục (Sidebar)"
        } else {
            return isSidebarCollapsedByUser ? "Hiện thanh điều hướng (Sidebar)" : "Ẩn thanh điều hướng (Sidebar)"
        }
    }
    
    private func toggleSidebar() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            if vm.watchingVideo != nil {
                vm.isSidebarDrawerOpen.toggle()
            } else {
                isSidebarCollapsedByUser.toggle()
                if !isSidebarCollapsedByUser {
                    vm.isSidebarDrawerOpen = false
                }
            }
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            if !playerManager.isVideoFullscreen {
                // MARK: - 1. Unified Window Header (Height: 52)
                ZStack {
                    VisualEffectBackground(material: .headerView, blendingMode: .withinWindow)
                    if colorScheme == .dark {
                        Color(red: 16/255, green: 16/255, blue: 20/255)
                    } else {
                        Color(red: 250/255, green: 250/255, blue: 252/255)
                    }
                    
                    // Centered Search Box with macOS HIG styling & high contrast
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                            .font(.system(size: 13, weight: .medium))
                        
                        ZStack(alignment: .leading) {
                            if vm.searchQuery.isEmpty {
                                Text("Tìm kiếm hoặc dán URL YouTube...")
                                     .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                    .font(.system(size: 13))
                                    .allowsHitTesting(false)
                            }
                            
                            TextField("", text: $vm.searchQuery)
                                .focused($isSearchFocused)
                                .textFieldStyle(.plain)
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                .font(.system(size: 13))
                                .onChange(of: isSearchFocused) { focused in
                                    PlayerManager.shared.isSearchFocused = focused
                                    if focused {
                                        vm.updateSearchSuggestions(for: vm.searchQuery)
                                    }
                                }
                                .onChange(of: vm.searchQuery) { newQuery in
                                    if vm.isNavigatingSuggestions {
                                        vm.isNavigatingSuggestions = false
                                        return
                                    }
                                    vm.updateSearchSuggestions(for: newQuery)
                                }
                                .onExitCommand {
                                    vm.dismissSuggestions()
                                    isSearchFocused = false
                                    PlayerManager.shared.isSearchFocused = false
                                    DispatchQueue.main.async {
                                        NSApp.keyWindow?.makeFirstResponder(nil)
                                    }
                                }
                                .onSubmit {
                                    isSearchFocused = false
                                    PlayerManager.shared.isSearchFocused = false
                                    DispatchQueue.main.async {
                                        NSApp.keyWindow?.makeFirstResponder(nil)
                                    }
                                    performSearch()
                                }
                        }
                        
                        if !vm.searchQuery.isEmpty {
                            Button(action: {
                                vm.searchQuery = ""
                                vm.dismissSuggestions()
                                isSearchFocused = false
                                DispatchQueue.main.async {
                                    NSApp.keyWindow?.makeFirstResponder(nil)
                                }
                                if vm.isSearching {
                                    vm.isSearching = false
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Dedicated Paste / Open URL Button
                        Button(action: handleQuickURLPasteOrOpen) {
                            Image(systemName: "link.badge.plus")
                                .foregroundColor(ThemeColor.textSecondary(for: colorScheme).opacity(0.85))
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .help("Dán link YouTube từ Clipboard hoặc nhập URL để xem trực tiếp")
                    }
                    .padding(.horizontal, 12)
                    .frame(width: 440, height: 32)
                    .liquidGlassSearchBar()
                    
                    // Left Controls: Sidebar Toggle + Brand + Navigation
                    HStack(spacing: 0) {
                        HStack(spacing: 8) {
                            // Hamburger Toggle Button (Sidebar / Drawer)
                            LiquidGlassCircleButton(action: toggleSidebar, size: 28) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                            .help(sidebarToggleTooltip)
                            
                            // Brand Logo & Title (Clickable to return Home)
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    vm.watchingVideo = nil
                                    vm.selectedSection = .home
                                    vm.isSearching = false
                                    vm.searchQuery = ""
                                    vm.isSidebarDrawerOpen = false
                                }
                            }) {
                                HStack(spacing: 7) {
                                    YouTubeBrandBadge(width: 25)
                                    
                                    HStack(alignment: .center, spacing: 3.5) {
                                        Text("AuraTube")
                                            .font(AppFont.youTubeSans(size: 18, weight: .bold))
                                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                            .tracking(-0.5)
                                            .lineLimit(1)
                                            .fixedSize()
                                        
                                        Text("VN")
                                            .font(AppFont.youTubeSans(size: 9, weight: .medium))
                                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                            .offset(y: -5)
                                            .lineLimit(1)
                                            .fixedSize()
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Về Trang chủ")
                            
                            if isSidebarVisible {
                                Spacer()
                            }
                        }
                        .padding(.leading, 14)
                        .frame(width: isSidebarVisible ? 220 : nil, height: 52, alignment: .leading)
                        
                        // Vertical Column Separator
                        Rectangle()
                            .fill(ThemeColor.divider(for: colorScheme))
                            .frame(width: 0.75, height: 22)
                            .padding(.horizontal, isSidebarVisible ? 0 : 10)
                        
                        // Navigation Controls (Back / Forward)
                        HStack(spacing: 6) {
                            let canGoBack = vm.watchingVideo != nil || vm.isSearching
                            LiquidGlassCircleButton(
                                action: {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        if vm.watchingVideo != nil {
                                            vm.watchingVideo = nil
                                        } else if vm.isSearching {
                                            vm.isSearching = false
                                            vm.searchQuery = ""
                                        }
                                        vm.isSidebarDrawerOpen = false
                                    }
                                },
                                size: 28
                            ) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .disabled(!canGoBack)
                            .opacity(canGoBack ? 1.0 : 0.35)
                            .help(canGoBack ? "Quay lại" : "")
                            
                            LiquidGlassCircleButton(action: {}, size: 28) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .disabled(true)
                            .opacity(0.35)
                        }
                        .padding(.leading, isSidebarVisible ? 12 : 0)
                        
                        Spacer()
                    }
                    
                    // Right Controls: Clean Uncluttered Toolbar (PiP + Downloads + Update + Settings)
                    HStack(spacing: 8) {
                        Spacer()
                        
                        // 1. Instant One-Click PiP Toggle (Visible when watching a video)
                        if vm.watchingVideo != nil {
                            LiquidGlassCircleButton(
                                action: {
                                    playerManager.togglePictureInPicture()
                                },
                                size: 28,
                                isActive: playerManager.isPictureInPictureActive
                            ) {
                                Image(systemName: playerManager.isPictureInPictureActive ? "pip.exit" : "pip.enter")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(playerManager.isPictureInPictureActive ? .white : ThemeColor.textPrimary(for: colorScheme).opacity(0.85))
                            }
                            .help(playerManager.isPictureInPictureActive ? "Đưa video về cửa sổ chính (P)" : "Chuyển sang cửa sổ nổi PiP (P)")
                        }
                        
                        // 2. Downloads Manager Quick Access Button
                        LiquidGlassCircleButton(
                            action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    vm.watchingVideo = nil
                                    vm.isSearching = false
                                    vm.selectedSection = .downloads
                                }
                            },
                            size: 28,
                            isActive: vm.selectedSection == .downloads
                        ) {
                            ZStack {
                                Image(systemName: downloadManager.hasActiveDownloads ? "arrow.down.circle.fill" : "arrow.down.circle")
                                    .font(.system(size: 12.5))
                                    .foregroundColor(downloadManager.hasActiveDownloads ? Color(red: 0.2, green: 0.65, blue: 1.0) : ThemeColor.textPrimary(for: colorScheme).opacity(0.85))
                                
                                if downloadManager.activeDownloadCount > 0 {
                                    Circle()
                                        .fill(Color(red: 0.2, green: 0.65, blue: 1.0))
                                        .frame(width: 6, height: 6)
                                        .offset(x: 6, y: -6)
                                }
                            }
                        }
                        .help(downloadManager.hasActiveDownloads ? "Đang tải \(downloadManager.activeDownloadCount) tệp..." : "Tệp đã tải về")
                        
                        // 3. Update Available Pill
                        updatePillView
                        
                        // 4. Unified Liquid Glass Settings Button (Theme, PiP, Updates, Info)
                        LiquidGlassCircleButton(
                            action: {
                                showSettingsSheet = true
                            },
                            size: 28,
                            isActive: showSettingsSheet
                        ) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 12.5))
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.85))
                        }
                        .help("Cài đặt & Tùy biến (⌘,)")
                    }
                    .padding(.trailing, 16)
                }
                .frame(height: 52)
            
            // Continuous Top Divider Line with specular highlight
            Rectangle()
                .fill(ThemeColor.divider(for: colorScheme))
                .frame(height: 0.75)
        }
        
        // MARK: - 2. Body Area (Sidebar + Content)
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if !playerManager.isVideoFullscreen && isSidebarVisible {
                    // Left Sidebar Items with Native macOS Styling
                    sidebarView(isDrawer: false)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    
                    // Vertical Content Divider with subtle specular reflection
                    Rectangle()
                        .fill(ThemeColor.divider(for: colorScheme))
                        .frame(width: 0.75)
                }
            
            // Main Content Area (Banner + Content Switcher)
            VStack(spacing: 0) {
                // Update Recommendation Banner
                if !playerManager.isVideoFullscreen,
                   updateService.isUpdateAvailable,
                   updateService.showUpdateBanner,
                   !updateService.hasDismissedBanner,
                   let update = updateService.latestUpdate {
                    UpdateNotificationBanner(update: update)
                }
                
                // Main Content View Switcher
                ZStack(alignment: .bottomTrailing) {
                    if playerManager.isVideoFullscreen {
                        Color.black.ignoresSafeArea()
                    } else {
                        (colorScheme == .dark ? Color(red: 15/255, green: 15/255, blue: 15/255) : Color.white).ignoresSafeArea()
                    }
                
                    mainContentView
                
                // Picture-in-Picture (PiP) Floating Mini-Player at bottom right corner
                if !playerManager.isVideoFullscreen, !playerManager.isPictureInPictureActive, vm.watchingVideo == nil, vm.selectedSection != .shorts, let activeVideo = playerManager.currentVideo {
                    MiniPlayerPiPOverlay(
                        video: activeVideo,
                        onExpand: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                vm.watchingVideo = activeVideo
                            }
                        },
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                playerManager.stop()
                            }
                        }
                    )
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(100)
                }
            }
            .overlay(alignment: .bottomLeading) {
                // Floating Download Progress HUD
                if !playerManager.isVideoFullscreen, downloadManager.showToastHUD, let item = downloadManager.latestDownload {
                    FloatingDownloadHUD(item: item)
                        .padding(.leading, 24)
                        .padding(.bottom, 24)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                        .zIndex(150)
                }
            }
        }
            }
            
            // Slide-out Drawer Panel when triggered
            if !playerManager.isVideoFullscreen && vm.isSidebarDrawerOpen {
                Color.black.opacity(colorScheme == .dark ? 0.45 : 0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            vm.isSidebarDrawerOpen = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(200)
                
                HStack(spacing: 0) {
                    sidebarView(isDrawer: true)
                        .overlay(
                            Rectangle()
                                .fill(ThemeColor.divider(for: colorScheme))
                                .frame(width: 0.75),
                            alignment: .trailing
                        )
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.6 : 0.25), radius: 24, x: 8, y: 0)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading),
                            removal: .move(edge: .leading)
                        ))
                    
                    Spacer()
                }
                .zIndex(201)
            }
        }
    }
    .frame(
        minWidth: playerManager.isVideoFullscreen ? 0 : 980,
        minHeight: playerManager.isVideoFullscreen ? 0 : 640
    )
    .clipShape(RoundedRectangle(cornerRadius: playerManager.isVideoFullscreen ? 0 : 16, style: .continuous))
    .background(
        Group {
            if playerManager.isVideoFullscreen {
                Color.black
            } else {
                ZStack {
                    VisualEffectBackground(
                        material: .underWindowBackground,
                        blendingMode: .behindWindow,
                        state: .active
                    )
                    if colorScheme == .dark {
                        Color(red: 16/255, green: 16/255, blue: 20/255)
                    } else {
                        Color.white
                    }
                }
            }
        }
    )
    .overlay(alignment: .top) {
        ZStack(alignment: .top) {
            if let toast = themeManager.themeToast {
                ThemeFeedbackToast(icon: toast.icon, message: toast.message)
                    .padding(.top, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(305)
            }
            
            if let feedback = updateService.scanFeedbackMessage {
                ScanFeedbackToast(message: feedback)
                    .padding(.top, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(300)
            }
            
            // Global Floating HUD Feedback Badge (Link copied, Direct Play, Seek, Volume)
            if playerManager.isHudVisible {
                HStack(spacing: 8) {
                    Image(systemName: playerManager.hudIcon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text(playerManager.hudText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.88))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.24), lineWidth: 0.8))
                        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
                )
                .padding(.top, 58)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(9999)
            }
            
            if vm.showSuggestions && (vm.detectedURLResult != nil || !vm.searchSuggestions.isEmpty || !RecommendationService.shared.recentSearches.isEmpty || !RecommendationService.shared.dynamicInterestTags.isEmpty) {
                // Invisible backdrop to dismiss suggestions when clicking outside
                Color.black.opacity(0.001)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) {
                            vm.dismissSuggestions()
                        }
                    }
                
                SearchSuggestionsDropdown(
                    detectedURL: vm.detectedURLResult,
                    suggestions: vm.searchSuggestions,
                    selectedIndex: vm.selectedSuggestionIndex,
                    isQueryEmpty: vm.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onHoverIndex: { idx in
                        vm.selectedSuggestionIndex = idx
                    },
                    onSelect: { suggestion in
                        performSearch(with: suggestion)
                    },
                    onSelectURL: { result in
                        playVideoById(result.videoId, startTime: result.startTime, isShort: result.isShort)
                        vm.searchQuery = ""
                    },
                    onRemoveRecent: { query in
                        RecommendationService.shared.removeRecentSearch(query)
                        vm.updateSearchSuggestions(for: vm.searchQuery)
                    },
                    onClearRecents: {
                        RecommendationService.shared.clearRecentSearches()
                        vm.updateSearchSuggestions(for: vm.searchQuery)
                    }
                )
                .padding(.top, 46)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                .zIndex(999)
            }
        }
    }
    .background(
        WindowAccessor { window in
            AppDelegate.configureTitlebar(for: window)
        }
    )
    .overlay {
        if playerManager.isVideoFullscreen, let fsVideo = playerManager.currentVideo ?? vm.watchingVideo ?? vm.selectedShortVideo {
            FullscreenVideoOverlay(video: fsVideo)
                .ignoresSafeArea()
                .zIndex(99999)
                .transition(.opacity)
        }
    }
    .onChange(of: playerManager.isVideoFullscreen) { isFS in
        if let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeKey && $0.isVisible }) ?? NSApp.mainWindow {
            if isFS {
                window.backgroundColor = .black
                window.contentView?.wantsLayer = true
                window.contentView?.layer?.cornerRadius = 0
                window.contentView?.layer?.masksToBounds = false
            } else {
                AppDelegate.configureTitlebar(for: window)
            }
        }
        if isFS, vm.watchingVideo == nil, let active = playerManager.currentVideo {
            vm.watchingVideo = active
        }
    }
    .onChange(of: playerManager.currentVideo?.id) { _ in
        if let active = playerManager.currentVideo, vm.watchingVideo != nil, vm.watchingVideo?.id != active.id {
            if active.isShort {
                vm.watchingVideo = nil
                vm.selectedShortVideo = active
                vm.selectedSection = .shorts
            } else {
                vm.watchingVideo = active
            }
        }
    }
    .onChange(of: playerManager.isPictureInPictureActive) { isPiP in
        if !isPiP, let active = playerManager.currentVideo, vm.watchingVideo == nil, vm.selectedSection != .shorts {
            withAnimation(.easeInOut(duration: 0.2)) {
                vm.watchingVideo = active
            }
        }
    }
    .onChange(of: vm.watchingVideo) { newWatch in
        if newWatch != nil {
            isSearchFocused = false
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }
    .sheet(isPresented: $updateService.showUpdateSheet) {
        UpdateSheetView()
    }
    .sheet(isPresented: $showSettingsSheet) {
        SettingsSheetView()
    }
    .sheet(isPresented: $vm.showOpenURLSheet) {
        OpenYouTubeURLSheet(initialURL: "") { result in
            playVideoById(result.videoId, startTime: result.startTime, isShort: result.isShort)
        }
    }
    .onReceive(NotificationCenter.default.publisher(for: .showSettingsNotification)) { _ in
        showSettingsSheet = true
    }
    .onReceive(NotificationCenter.default.publisher(for: .toggleSidebarNotification)) { _ in
        toggleSidebar()
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AuraTubeNavigateShorts"))) { _ in
        vm.watchingVideo = nil
        vm.selectedSection = .shorts
    }
    .onExitCommand {
        if vm.isSidebarDrawerOpen {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                vm.isSidebarDrawerOpen = false
            }
        } else if vm.showSuggestions {
            vm.dismissSuggestions()
        }
    }
    .onAppear {
        setupSearchKeyMonitor()
    }
    .onDisappear {
        teardownSearchKeyMonitor()
    }
}
    
    @ViewBuilder
    private func sidebarView(isDrawer: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(NavigationSection.allCases) { section in
                SidebarNavButton(
                    section: section,
                    isSelected: vm.selectedSection == section && vm.watchingVideo == nil && vm.selectedChannel == nil
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        if isDrawer {
                            vm.isSidebarDrawerOpen = false
                        }
                        vm.selectedSection = section
                        vm.watchingVideo = nil
                        vm.selectedChannel = nil
                        if section == .shorts {
                            playerManager.stop()
                        }
                    }
                }
            }
            
            // Subscribed channels list in sidebar
            if !ChannelSubscriptionManager.shared.subscribedChannels.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
                
                Text("Kênh đăng ký")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 2)
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(ChannelSubscriptionManager.shared.subscribedChannels) { channel in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if isDrawer {
                                        vm.isSidebarDrawerOpen = false
                                    }
                                    vm.openChannel(channel)
                                }
                            }) {
                                HStack(spacing: 10) {
                                    if !channel.avatarUrl.isEmpty {
                                        CachedAsyncThumbnail(url: channel.avatarUrl, maxPixelSize: 48) { img in
                                            img.resizable().scaledToFill()
                                        } placeholder: {
                                            Circle().fill(Color(white: 0.2))
                                        }
                                        .frame(width: 22, height: 22)
                                        .clipShape(Circle())
                                    } else {
                                        Circle()
                                            .fill(colorScheme == .dark ? Color(white: 0.25) : Color(white: 0.85))
                                            .frame(width: 22, height: 22)
                                            .overlay(
                                                Text(channel.title.prefix(1).uppercased())
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                            )
                                    }
                                    
                                    Text(channel.title)
                                        .font(.system(size: 13, weight: vm.selectedChannel?.id == channel.id ? .semibold : .regular))
                                        .foregroundColor(vm.selectedChannel?.id == channel.id ? .cyan : ThemeColor.textPrimary(for: colorScheme))
                                        .lineLimit(1)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(vm.selectedChannel?.id == channel.id ? ThemeColor.sidebarHover(for: colorScheme) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(.top, 14)
        .frame(width: isDrawer ? 230 : 220)
        .background(
            Group {
                if colorScheme == .dark {
                    ZStack {
                        ThemeColor.headerBackground(for: colorScheme)
                        VisualEffectBackground(material: .sidebar, blendingMode: .withinWindow)
                    }
                } else {
                    Color(red: 250/255, green: 250/255, blue: 250/255)
                }
            }
        )
    }
    
    @ViewBuilder
    private var updatePillView: some View {
        if updateService.isUpdateAvailable, let update = updateService.latestUpdate {
            LiquidGlassButton(action: {
                updateService.showUpdateSheet = true
            }, cornerRadius: 8, isProminent: true) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                    Text("Bản mới v\(update.version)")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
        }
    }
    
    @ViewBuilder
    private var mainContentView: some View {
        if let currentWatch = vm.watchingVideo {
            WatchView(
                video: currentWatch,
                onBack: { 
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vm.watchingVideo = nil 
                    }
                },
                onSelectRelated: { newVideo in
                    playVideo(newVideo)
                },
                onSelectChannel: { channel in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vm.openChannel(channel)
                    }
                }
            )
        } else if let channel = vm.selectedChannel {
            ChannelDetailView(
                channel: channel,
                videos: vm.channelVideos,
                bannerUrl: vm.channelBannerUrl,
                isLoading: vm.isLoadingChannel,
                isLoadingMore: vm.isLoadingMoreChannel,
                onBack: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vm.closeChannel()
                    }
                },
                onSelectVideo: { video in
                    playVideo(video)
                },
                onLoadMore: {
                    vm.loadMoreChannelVideos()
                }
            )
        } else if vm.isSearching {
            SearchResultsView(
                vm: vm,
                onSelectVideo: { playVideo($0) },
                onLoadMore: { loadMoreSearchResults() },
                onQuickURL: { handleQuickURLPasteOrOpen() },
                onPerformSearch: { query in performSearch(with: query) },
                onSelectChannel: { channel in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vm.openChannel(channel)
                    }
                }
            )
        } else {
            sectionContentView
        }
    }
    
    @ViewBuilder
    private var sectionContentView: some View {
        switch vm.selectedSection {
        case .home:
            HomeView(
                onSelectVideo: { playVideo($0) },
                onSelectChannel: { channel in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vm.openChannel(channel)
                    }
                }
            )
        case .shorts:
            NativeShortsFeedView(
                selectedShort: $vm.selectedShortVideo,
                onSelectVideo: { forcePlayLongVideo($0) },
                onOpenChannel: { vm.openChannel($0) }
            )
        case .bookmarks:
            BookmarkListView(onSelectVideo: { playVideo($0) })
        case .history:
            HistoryListView(onSelectVideo: { playVideo($0) })
        case .downloads:
            DownloadListView()
        }
    }
    
    private func playVideoById(_ id: String, startTime: Double? = nil, isShort: Bool = false) {
        vm.dismissSuggestions()
        vm.isSidebarDrawerOpen = false
        isSearchFocused = false
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        
        let placeholder = Video(
            id: id,
            title: "Đang tải video...",
            uploader: "YouTube",
            duration: 0,
            thumbnail: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg",
            isShort: isShort
        )
        
        if isShort {
            vm.watchingVideo = nil
            vm.isSearching = false
            vm.selectedShortVideo = placeholder
            vm.selectedSection = .shorts
            playerManager.stop()
        } else {
            vm.selectedShortVideo = nil
            vm.isSearching = false
            vm.watchingVideo = placeholder
            playerManager.loadAndPlay(video: placeholder)
            if let start = startTime, start > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    playerManager.seek(to: start)
                }
            }
        }
        playerManager.flashHUD(icon: "play.circle.fill", text: "Đang phát video từ liên kết 🔗")
    }
    
    private func handleQuickURLPasteOrOpen() {
        if let clipboardResult = YouTubeURLParser.checkClipboard() {
            playVideoById(clipboardResult.videoId, startTime: clipboardResult.startTime, isShort: clipboardResult.isShort)
        } else {
            vm.showOpenURLSheet = true
        }
    }
    
    private func playVideo(_ video: Video) {
        vm.dismissSuggestions()
        vm.isSidebarDrawerOpen = false
        isSearchFocused = false
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        if video.isShort {
            vm.watchingVideo = nil
            vm.isSearching = false
            vm.selectedShortVideo = video
            vm.selectedSection = .shorts
            playerManager.stop()
        } else {
            vm.selectedShortVideo = nil
            vm.watchingVideo = video
            playerManager.loadAndPlay(video: video)
        }
    }
    
    private func forcePlayLongVideo(_ video: Video) {
        vm.dismissSuggestions()
        vm.isSidebarDrawerOpen = false
        isSearchFocused = false
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        vm.selectedShortVideo = nil
        vm.watchingVideo = video
        playerManager.loadAndPlay(video: video)
    }
    
    private func setupSearchKeyMonitor() {
        guard searchKeyMonitor == nil else { return }
        searchKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handleSearchKeyDown(event) {
                return nil
            }
            return event
        }
    }
    
    private func teardownSearchKeyMonitor() {
        if let monitor = searchKeyMonitor {
            NSEvent.removeMonitor(monitor)
            searchKeyMonitor = nil
        }
    }
    
    private func handleSearchKeyDown(_ event: NSEvent) -> Bool {
        // Case 1: Suggestions dropdown is visible
        if vm.showSuggestions {
            let hasURL = (vm.detectedURLResult != nil)
            let items = vm.currentSuggestionItems
            let totalCount = (hasURL ? 1 : 0) + items.count
            
            switch event.keyCode {
            case 125: // Down Arrow
                if totalCount > 0 {
                    vm.selectNextSuggestion()
                    return true
                }
            case 126: // Up Arrow
                if totalCount > 0 {
                    vm.selectPreviousSuggestion()
                    return true
                }
            case 36, 76: // Return / Enter
                if vm.selectedSuggestionIndex >= 0 {
                    if hasURL && vm.selectedSuggestionIndex == 0, let res = vm.detectedURLResult {
                        playVideoById(res.videoId, startTime: res.startTime, isShort: res.isShort)
                        vm.searchQuery = ""
                        vm.dismissSuggestions()
                        isSearchFocused = false
                        DispatchQueue.main.async {
                            NSApp.keyWindow?.makeFirstResponder(nil)
                        }
                        return true
                    } else {
                        let itemIdx = hasURL ? (vm.selectedSuggestionIndex - 1) : vm.selectedSuggestionIndex
                        if itemIdx >= 0 && itemIdx < items.count {
                            let chosen = items[itemIdx]
                            performSearch(with: chosen)
                            return true
                        }
                    }
                } else if hasURL, let res = vm.detectedURLResult {
                    playVideoById(res.videoId, startTime: res.startTime, isShort: res.isShort)
                    vm.searchQuery = ""
                    vm.dismissSuggestions()
                    isSearchFocused = false
                    DispatchQueue.main.async {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
                    return true
                }
            case 48: // Tab key (autocomplete query)
                if vm.selectedSuggestionIndex >= 0 {
                    let itemIdx = hasURL ? (vm.selectedSuggestionIndex - 1) : vm.selectedSuggestionIndex
                    if itemIdx >= 0 && itemIdx < items.count {
                        let chosen = items[itemIdx]
                        vm.searchQuery = chosen
                        vm.originalUserQuery = chosen
                        vm.selectedSuggestionIndex = -1
                        vm.updateSearchSuggestions(for: chosen)
                        return true
                    }
                }
            case 53: // Escape
                if vm.isNavigatingSuggestions {
                    vm.searchQuery = vm.originalUserQuery
                }
                vm.dismissSuggestions()
                isSearchFocused = false
                DispatchQueue.main.async {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
                return true
            default:
                break
            }
        }
        
        // Case 2: On Search Results page (when not actively editing search box)
        let isEditingSearch = isSearchFocused || PlayerManager.shared.isSearchFocused
        if vm.isSearching && !vm.searchResults.isEmpty && !isEditingSearch && !vm.showSuggestions && vm.watchingVideo == nil {
            let videos = vm.searchVideos
            switch event.keyCode {
            case 125: // Down Arrow
                if !videos.isEmpty && vm.selectedSearchResultIndex < videos.count - 1 {
                    vm.selectedSearchResultIndex += 1
                    return true
                }
            case 126: // Up Arrow
                if vm.selectedSearchResultIndex > 0 {
                    vm.selectedSearchResultIndex -= 1
                    return true
                }
            case 36, 76: // Return / Enter
                if vm.selectedSearchResultIndex >= 0 && vm.selectedSearchResultIndex < videos.count {
                    let target = videos[vm.selectedSearchResultIndex]
                    playVideo(target)
                    return true
                }
            default:
                break
            }
        }
        
        return false
    }
    
    private func performSearch(with queryOverride: String? = nil) {
        if let override = queryOverride {
            vm.searchQuery = override
        }
        let query = vm.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        
        // 1. Direct URL detection: if query is a YouTube URL or 11-char ID, play immediately!
        if let parsed = YouTubeURLParser.parse(query) {
            playVideoById(parsed.videoId, startTime: parsed.startTime, isShort: parsed.isShort)
            vm.searchQuery = ""
            return
        }
        
        RecommendationService.shared.recordSearch(query: query)
        
        vm.dismissSuggestions()
        vm.isSidebarDrawerOpen = false
        isSearchFocused = false
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        vm.isSearching = true
        vm.watchingVideo = nil
        vm.isLoadingSearch = true
        vm.isLoadingMoreSearch = false
        vm.searchContinuationToken = nil
        vm.searchChannel = nil
        vm.searchVideos = []
        vm.searchShorts = []
        vm.searchResults = []
        vm.selectedSearchResultIndex = -1
        vm.relatedSearches = []
        vm.contextualChips = []
        vm.searchFilter = "Tất cả"
        vm.canLoadMoreSearch = true
        
        Task {
            async let pageFetch = YTDLPService.shared.searchVideosWithContinuation(query: query)
            async let relatedQueriesFetch = RecommendationService.shared.fetchRelatedSearchQueries(for: query)
            async let contextualChipsFetch = RecommendationService.shared.fetchContextualSearchChips(for: query)
            
            let page = await pageFetch
            let extraRelated = await relatedQueriesFetch
            let extraChips = await contextualChipsFetch
            
            vm.searchChannel = page.channel
            
            // Personalized taste-aware re-ranking
            let ranked = RecommendationService.shared.rankSearchResults(videos: page.videos, query: query)
            vm.searchVideos = ranked
            vm.searchShorts = page.shorts
            vm.searchResults = ranked + page.shorts
            vm.searchContinuationToken = page.continuationToken
            vm.canLoadMoreSearch = page.continuationToken != nil
            
            // Merge related searches deduplicated
            var combinedRelated = page.relatedSearches
            for r in extraRelated {
                if !combinedRelated.contains(where: { $0.caseInsensitiveCompare(r) == .orderedSame }) && r.caseInsensitiveCompare(query) != .orderedSame {
                    combinedRelated.append(r)
                }
            }
            vm.relatedSearches = Array(combinedRelated.prefix(8))
            
            // Merge contextual chips deduplicated
            var combinedChips = page.contextualChips
            for c in extraChips {
                if !combinedChips.contains(where: { $0.caseInsensitiveCompare(c) == .orderedSame }) {
                    combinedChips.append(c)
                }
            }
            vm.contextualChips = Array(combinedChips.prefix(12))
            
            vm.isLoadingSearch = false
        }
    }
    
    private func loadMoreSearchResults() {
        guard !vm.isLoadingMoreSearch, !vm.isLoadingSearch, vm.canLoadMoreSearch,
              let token = vm.searchContinuationToken, !token.isEmpty else { return }
        
        vm.isLoadingMoreSearch = true
        Task {
            let page = await YTDLPService.shared.searchVideosWithContinuation(query: vm.searchQuery, continuationToken: token)
            var curVideos = vm.searchVideos
            for v in page.videos {
                if !curVideos.contains(where: { $0.id == v.id }) {
                    curVideos.append(v)
                }
            }
            var curShorts = vm.searchShorts
            for s in page.shorts {
                if !curShorts.contains(where: { $0.id == s.id }) {
                    curShorts.append(s)
                }
            }
            vm.searchVideos = curVideos
            vm.searchShorts = curShorts
            vm.searchResults = curVideos + curShorts
            vm.searchContinuationToken = page.continuationToken
            vm.canLoadMoreSearch = page.continuationToken != nil && (!page.videos.isEmpty || !page.shorts.isEmpty)
            vm.isLoadingMoreSearch = false
        }
    }
}

// MARK: - Bookmarks List View
struct BookmarkListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var playerManager = PlayerManager.shared
    let onSelectVideo: (Video) -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Danh sách Xem sau (Bookmarks)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                
                if playerManager.bookmarkedVideos.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 32))
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme).opacity(0.6))
                        Text("Chưa có video nào trong danh sách Xem sau")
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    }
                    .frame(maxWidth: .infinity, minHeight: 250)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 380), spacing: 20, alignment: .top)], alignment: .leading, spacing: 28) {
                        ForEach(playerManager.bookmarkedVideos) { v in
                            VideoCardView(video: v) { onSelectVideo(v) }
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }
}

// MARK: - History List View
struct HistoryListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var playerManager = PlayerManager.shared
    let onSelectVideo: (Video) -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Video đã xem gần đây")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                
                if playerManager.historyVideos.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 32))
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme).opacity(0.6))
                        Text("Lịch sử xem đang trống")
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    }
                    .frame(maxWidth: .infinity, minHeight: 250)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 380), spacing: 20, alignment: .top)], alignment: .leading, spacing: 28) {
                        ForEach(playerManager.historyVideos) { v in
                            VideoCardView(video: v) { onSelectVideo(v) }
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }
}

// MARK: - Download List View
struct DownloadListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var downloadManager = DownloadManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tệp đã tải về")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    Text("Lưu trữ cục bộ tại ~/Downloads/YouTube_Adfree")
                        .font(.system(size: 12))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                }
                
                Spacer()
                
                HStack(spacing: 10) {
                    if !downloadManager.downloads.isEmpty {
                        Button(action: { downloadManager.clearCompleted() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "trash")
                                Text("Xóa tệp đã hoàn tất")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(8)
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button(action: { downloadManager.openDownloadFolder() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                            Text("Mở thư mục trong Finder")
                        }
                        .font(.system(size: 12.5, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(ThemeColor.buttonBackground(for: colorScheme, isHovered: false))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ThemeColor.buttonBorder(for: colorScheme, isHovered: false), lineWidth: 0.75))
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            if downloadManager.downloads.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 40))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme).opacity(0.45))
                    Text("Chưa có tệp tải về nào")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    Text("Bấm nút 'Tải xuống' dưới bất kỳ video nào để tải MP4 hoặc trích xuất MP3.")
                        .font(.system(size: 12.5))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(downloadManager.downloads) { item in
                            DownloadRowCard(item: item)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
        }
    }
}

// MARK: - Download Row Card
struct DownloadRowCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var downloadManager = DownloadManager.shared
    let item: DownloadItem
    
    var body: some View {
        HStack(spacing: 14) {
            // Thumbnail Preview
            ZStack {
                CachedAsyncThumbnail(url: item.thumbnail, maxPixelSize: 192, placeholderColor: Color(white: 0.15))
                .frame(width: 96, height: 54)
                .cornerRadius(6)
                .clipped()
                
                if item.isAudioOnly {
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.blue.opacity(0.85))
                        .clipShape(Circle())
                        .offset(x: 32, y: 16)
                }
            }
            
            // Details & Progress
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(item.quality)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(4)
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                }
                
                // Progress Bar (when downloading)
                if !item.isComplete && !item.isError {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.08))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(LinearGradient(colors: [Color(red: 0.1, green: 0.6, blue: 1.0), Color(red: 0.4, green: 0.85, blue: 1.0)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(4, geo.size.width * CGFloat(min(1.0, max(0.0, item.progress)))))
                                .animation(.linear(duration: 0.2), value: item.progress)
                        }
                    }
                    .frame(height: 5)
                }
                
                // Status subtext
                HStack(spacing: 8) {
                    if item.isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                        Text("Hoàn tất")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                    } else if item.isError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 12))
                        Text(item.errorMessage ?? "Lỗi tải về")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .lineLimit(1)
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(Color(red: 0.2, green: 0.65, blue: 1.0))
                            .font(.system(size: 12))
                        Text(item.statusText)
                            .font(.system(size: 12))
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    if !item.totalSize.isEmpty {
                        Text(item.totalSize)
                            .font(.system(size: 11.5))
                            .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                    }
                }
            }
            
            // Action Buttons
            HStack(spacing: 8) {
                if item.isComplete {
                    Button(action: {
                        downloadManager.openFileInFinder(for: item)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text("Mở tệp")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(6)
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    }
                    .buttonStyle(.plain)
                } else if !item.isError {
                    Button(action: {
                        downloadManager.cancelDownload(id: item.id)
                    }) {
                        Text("Hủy")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.45))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red.opacity(0.12))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                
                Button(action: {
                    downloadManager.removeDownload(id: item.id)
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme).opacity(0.7))
                        .padding(6)
                        .background(Color.white.opacity(0.04))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(ThemeColor.cardBackground(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(ThemeColor.cardBorder(for: colorScheme), lineWidth: 0.75)
        )
    }
}

// MARK: - Floating Download HUD
struct FloatingDownloadHUD: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var downloadManager = DownloadManager.shared
    let item: DownloadItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail Preview
            ZStack {
                CachedAsyncThumbnail(url: item.thumbnail, maxPixelSize: 108, placeholderColor: Color(white: 0.15))
                .frame(width: 54, height: 36)
                .cornerRadius(6)
                .clipped()
                
                if item.isAudioOnly {
                    Image(systemName: "music.note")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.white)
                        .padding(3)
                        .background(Color.blue.opacity(0.85))
                        .clipShape(Circle())
                        .offset(x: 18, y: 10)
                }
            }
            
            // Text & Progress Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                        .lineLimit(1)
                    
                    Spacer(minLength: 4)
                    
                    Text("\(Int(item.progress * 100))%")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(item.isComplete ? .green : (item.isError ? .red : Color(red: 0.2, green: 0.65, blue: 1.0)))
                }
                
                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(Color.white.opacity(0.12))
                        
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(
                                item.isComplete ?
                                    LinearGradient(colors: [Color.green, Color(red: 0.2, green: 0.85, blue: 0.4)], startPoint: .leading, endPoint: .trailing) :
                                item.isError ?
                                    LinearGradient(colors: [Color.red, Color.orange], startPoint: .leading, endPoint: .trailing) :
                                    LinearGradient(colors: [Color(red: 0.1, green: 0.6, blue: 1.0), Color(red: 0.4, green: 0.85, blue: 1.0)], startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: max(4, geo.size.width * CGFloat(min(1.0, max(0.0, item.progress)))))
                            .animation(.linear(duration: 0.2), value: item.progress)
                    }
                }
                .frame(height: 4)
                
                // Status subtext
                HStack(spacing: 8) {
                    Text(item.statusText)
                        .font(.system(size: 10.5))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if item.isComplete {
                        HStack(spacing: 8) {
                            Button(action: {
                                downloadManager.openFile(for: item)
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 8, weight: .bold))
                                    Text("Phát")
                                        .font(.system(size: 10.5, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(LinearGradient(colors: [Color.green, Color(red: 0.16, green: 0.70, blue: 0.32)], startPoint: .top, endPoint: .bottom))
                                )
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                downloadManager.openFileInFinder(for: item)
                            }) {
                                Text("Finder ↗")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(width: 240)
            
            // Close / Dismiss button
            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    downloadManager.showToastHUD = false
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme).opacity(0.8))
                    .padding(5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            ZStack {
                VisualEffectBackground(material: .popover, blendingMode: .withinWindow)
                (colorScheme == .dark ? Color.black.opacity(0.7) : Color.white.opacity(0.85))
            }
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(ThemeColor.divider(for: colorScheme), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Picture-in-Picture (PiP) Mini-Player Overlay
@MainActor
final class PiPHoverViewModel: ObservableObject {
    @Published var isHovered = false
    @Published var keyMonitor: Any? = nil
    @Published var hudText: String = ""
    @Published var hudIcon: String = ""
    @Published var isHudVisible: Bool = false
    var hudTimer: Timer? = nil
}

@MainActor
final class MiniProgressBarViewModel: ObservableObject {
    @Published var isHovered: Bool = false
    @Published var isDragging: Bool = false
}

struct MiniPlayerInteractiveProgressBar: View {
    @ObservedObject private var playerManager = PlayerManager.shared
    @ObservedObject private var clock = PlaybackClock.shared
    @StateObject private var barVm = MiniProgressBarViewModel()
    
    private var effectiveDuration: Double {
        clock.duration > 0 ? clock.duration : playerManager.duration
    }
    
    private var effectiveTime: Double {
        clock.currentTime > 0 ? clock.currentTime : playerManager.currentTime
    }
    
    var body: some View {
        GeometryReader { geo in
            let total = max(1.0, effectiveDuration)
            let progress = max(0.0, min(1.0, effectiveTime / total))
            
            ZStack(alignment: .leading) {
                // Background Track
                Rectangle()
                    .fill(Color.white.opacity(barVm.isHovered || barVm.isDragging ? 0.32 : 0.18))
                    .frame(height: barVm.isHovered || barVm.isDragging ? 5 : 2.5)
                
                // Played Progress (YouTube Red gradient)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color(red: 1.0, green: 0.25, blue: 0.25)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(2, geo.size.width * CGFloat(progress)), height: barVm.isHovered || barVm.isDragging ? 5 : 2.5)
                
                // Scrub thumb circle
                if barVm.isHovered || barVm.isDragging {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                        .offset(x: max(0, min(geo.size.width - 10, geo.size.width * CGFloat(progress) - 5)))
                }
            }
            .frame(height: 12)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        barVm.isDragging = true
                        let pct = max(0.0, min(1.0, val.location.x / geo.size.width))
                        let targetSec = pct * total
                        playerManager.seek(to: targetSec)
                    }
                    .onEnded { _ in
                        barVm.isDragging = false
                    }
            )
            .onHover { h in
                withAnimation(.easeInOut(duration: 0.12)) {
                    barVm.isHovered = h
                }
            }
        }
        .frame(height: 12)
    }
}

struct MiniPlayerPiPOverlay: View {
    let video: Video
    let onExpand: () -> Void
    let onClose: () -> Void
    
    @ObservedObject private var playerManager = PlayerManager.shared
    @StateObject private var hoverVm = PiPHoverViewModel()
    
    private func flashHUD(icon: String, text: String) {
        hoverVm.hudTimer?.invalidate()
        hoverVm.hudIcon = icon
        hoverVm.hudText = text
        withAnimation(.easeOut(duration: 0.15)) {
            hoverVm.isHudVisible = true
        }
        hoverVm.hudTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { [weak hoverVm] _ in
            Task { @MainActor in
                withAnimation(.easeIn(duration: 0.2)) {
                    hoverVm?.isHudVisible = false
                }
            }
        }
    }
    
    var body: some View {
        let isVertical: Bool = {
            if video.totalDurationSeconds > 65 || playerManager.duration > 65 { return false }
            return video.isShort || playerManager.isCurrentVideoVertical
        }()
        let pipWidth: CGFloat = round(isVertical ? 230 : 360)
        let videoHeight: CGFloat = round(isVertical ? (pipWidth * 16.0 / 9.0) : (pipWidth * 9.0 / 16.0))
        
        VStack(spacing: 0) {
            // 1. Video Frame (Edge-to-edge with 0 inner corner radius, naturally clipped by outer container)
            ZStack(alignment: .center) {
                NativePlayerView(cornerRadius: 0)
                    .frame(width: pipWidth, height: videoHeight)
                    .background(Color.black)
                
                // Double tap gestures for seeking left/right + single tap for play/pause
                HStack(spacing: 0) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            playerManager.seekRelative(-10)
                            flashHUD(icon: "gobackward.10", text: "-10s")
                        }
                        .simultaneousGesture(
                            TapGesture(count: 1).onEnded {
                                playerManager.togglePlayPause()
                            }
                        )
                    
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            playerManager.seekRelative(10)
                            flashHUD(icon: "goforward.10", text: "+10s")
                        }
                        .simultaneousGesture(
                            TapGesture(count: 1).onEnded {
                                playerManager.togglePlayPause()
                            }
                        )
                }
                .frame(width: pipWidth, height: videoHeight)
                
                // Center HUD Feedback Badge (Seek / Space feedback)
                if hoverVm.isHudVisible {
                    VStack(spacing: 4) {
                        Image(systemName: hoverVm.hudIcon)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        if !hoverVm.hudText.isEmpty {
                            Text(hoverVm.hudText)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.black.opacity(0.80))
                    )
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
                
                // Top Overlay on hover: Expand hint & close button
                if hoverVm.isHovered {
                    ZStack(alignment: .top) {
                        LinearGradient(
                            colors: [Color.black.opacity(0.25), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 50)
                        .allowsHitTesting(false)
                        
                        HStack(spacing: 6) {
                            Button(action: onExpand) {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 10.5, weight: .bold))
                                    Text("Phóng to")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4.5)
                                .background(PlayerGlassShape(shape: Capsule(), tint: 0.18, blur: 0))
                            }
                            .buttonStyle(.plain)
                            .help("Phóng to video vào giao diện xem chính")
                            
                            Button(action: {
                                playerManager.togglePictureInPicture()
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "pip.enter")
                                        .font(.system(size: 10.5, weight: .bold))
                                    Text("PiP")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4.5)
                                .background(PlayerGlassShape(shape: Capsule(), tint: 0.18, blur: 0))
                            }
                            .buttonStyle(.plain)
                            .help("Chuyển video sang cửa sổ nổi Picture-in-Picture (P)")
                            
                            Spacer()
                            
                            Button(action: onClose) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 24, height: 24)
                                    .background(PlayerGlassShape(shape: Circle(), tint: 0.18, blur: 0))
                            }
                            .buttonStyle(.plain)
                            .help("Đóng phát")
                        }
                        .padding(8)
                    }
                    .frame(width: pipWidth, height: videoHeight, alignment: .top)
                }
            }
            .frame(width: pipWidth, height: videoHeight)
            
            // 2. Interactive High-Precision Progress Scrubber (Click & Drag to Seek)
            MiniPlayerInteractiveProgressBar()
            
            // 3. Bottom Controls & Metadata Bar
            HStack(spacing: 6) {
                // Video Info (Clicking title expands video)
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(video.uploader)
                        .font(.system(size: 10.5))
                        .foregroundColor(Color.white.opacity(0.78))
                        .lineLimit(1)
                }
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    onExpand()
                }
                
                // Seek Backward 10s Button
                Button(action: {
                    playerManager.seekRelative(-10)
                    flashHUD(icon: "gobackward.10", text: "-10s")
                }) {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.85))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help("Lùi 10 giây (← / J)")
                
                // Play / Pause Button
                Button(action: {
                    playerManager.togglePlayPause()
                    flashHUD(
                        icon: playerManager.isPlaying ? "pause.fill" : "play.fill",
                        text: playerManager.isPlaying ? "Tạm dừng" : "Phát"
                    )
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.26))
                        Circle()
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                        Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(playerManager.isPlaying ? "Tạm dừng (Space / K)" : "Phát (Space / K)")
                
                // Seek Forward 10s Button
                Button(action: {
                    playerManager.seekRelative(10)
                    flashHUD(icon: "goforward.10", text: "+10s")
                }) {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.85))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help("Tua tiếp 10 giây (→ / L)")
                
                // Close Button
                Button(action: onClose) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.14))
                        Circle()
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.85))
                    }
                    .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Đóng phát")
            }
            .padding(.horizontal, 12)
            .frame(width: pipWidth, height: 52)
        }
        .frame(width: pipWidth)
        // Glass card: the toolbar under the video blurs the app content behind the mini player
        .background(PlayerGlassBackground(cornerRadius: 14, tint: 0.12, blur: 0.45))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(hoverVm.isHovered ? 0.32 : 0.18),
                            Color.white.opacity(hoverVm.isHovered ? 0.12 : 0.06)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.32), radius: hoverVm.isHovered ? 26 : 18, x: 0, y: 10)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isVertical)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoverVm.isHovered = hovering
            }
        }
        .onAppear {
            setupKeyMonitor()
        }
        .onDisappear {
            if let km = hoverVm.keyMonitor {
                NSEvent.removeMonitor(km)
                hoverVm.keyMonitor = nil
            }
            hoverVm.hudTimer?.invalidate()
        }
    }
    
    private func setupKeyMonitor() {
        if hoverVm.keyMonitor != nil { return }
        hoverVm.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak playerManager] event in
            guard let pm = playerManager else { return event }
            // Skip if user is typing in a search bar or text input
            if pm.isSearchFocused || isUserTyping(in: event) {
                if event.keyCode == 53 {
                    pm.isSearchFocused = false
                    DispatchQueue.main.async {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
                    return nil
                }
                // Khi đang nhập văn bản, không chặn phím tắt để gõ bình thường
                return event
            }
            switch event.keyCode {
            case 35: // P: Toggle PiP
                pm.togglePictureInPicture()
                return nil
            case 53: // Esc: Close mini player
                onClose()
                return nil
            case 49, 40: // Space or K: Toggle Play/Pause
                if event.isARepeat { return nil }
                pm.togglePlayPause()
                return nil
            case 123, 38: // Left Arrow or J: Seek -10s
                pm.seekRelative(-10)
                flashHUD(icon: "gobackward.10", text: "-10s")
                return nil
            case 124, 37: // Right Arrow or L: Seek +10s
                pm.seekRelative(10)
                flashHUD(icon: "goforward.10", text: "+10s")
                return nil
            case 126: // Up Arrow: Volume Up
                let newVol = min(1.0, pm.volume + 0.05)
                pm.volume = newVol
                pm.isMuted = false
                flashHUD(icon: "speaker.wave.3.fill", text: "\(Int(newVol * 100))%")
                return nil
            case 125: // Down Arrow: Volume Down
                let newVol = max(0.0, pm.volume - 0.05)
                pm.volume = newVol
                flashHUD(icon: "speaker.wave.1.fill", text: "\(Int(newVol * 100))%")
                return nil
            case 46: // M: Toggle Mute
                pm.toggleMute()
                flashHUD(icon: pm.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", text: pm.isMuted ? "Tắt tiếng" : "Bật tiếng")
                return nil
            default:
                return event
            }
        }
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
}

// MARK: - Update Notification Banner
struct UpdateNotificationBanner: View {
    let update: AppUpdateInfo
    @ObservedObject private var updateService = UpdateService.shared
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                Circle()
                    .strokeBorder(ThemeColor.buttonBorder(for: colorScheme, isHovered: false), lineWidth: 0.75)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(width: 36, height: 36)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Đã có bản cập nhật mới AuraTube v\(update.version)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    
                    Text("KHUYÊN DÙNG")
                        .font(.system(size: 9, weight: .black))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.green.opacity(colorScheme == .dark ? 0.25 : 0.15))
                        .foregroundColor(colorScheme == .dark ? .green : Color(red: 0.1, green: 0.6, blue: 0.25))
                        .cornerRadius(4)
                }
                
                Text("Vui lòng cập nhật ngay để khắc phục triệt để lỗi âm thanh và tận hưởng trải nghiệm mượt mà nhất.")
                    .font(.system(size: 11.5))
                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    .lineLimit(1)
            }
            
            Spacer()
            
            HStack(spacing: 10) {
                LiquidGlassButton(action: {
                    updateService.showUpdateSheet = true
                }, cornerRadius: 8, isProminent: true) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12))
                        Text("Cập nhật ngay")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                }
                
                LiquidGlassCircleButton(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        updateService.hasDismissedBanner = true
                    }
                }, size: 26) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                }
                .help("Bỏ qua thông báo này")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .liquidGlass(cornerRadius: 14, elevation: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(ThemeColor.cardBorder(for: colorScheme), lineWidth: 0.75)
        )
        .frame(maxWidth: 780)
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Scan Feedback Toast HUD
struct ScanFeedbackToast: View {
    let message: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green)
                .font(.system(size: 13, weight: .bold))
            Text(message)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color(red: 241/255, green: 241/255, blue: 241/255) : Color(red: 15/255, green: 15/255, blue: 15/255))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color(red: 30/255, green: 30/255, blue: 30/255) : Color.white)
                .overlay(
                    Capsule()
                        .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.12), lineWidth: 0.75)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 10, y: 4)
        )
    }
}

// MARK: - Theme Feedback Toast HUD
struct ThemeFeedbackToast: View {
    let icon: String
    let message: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(icon == "sun.max.fill" ? .orange : (icon == "moon.stars.fill" ? .cyan : Color(red: 0.2, green: 0.65, blue: 1.0)))
                .font(.system(size: 13.5, weight: .bold))
            Text(message)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color(red: 30/255, green: 30/255, blue: 30/255) : Color.white)
                .overlay(
                    Capsule()
                        .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.12), lineWidth: 0.75)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 10, y: 4)
        )
    }
}

// MARK: - Spinning Refresh Icon (Rotates 100% in place without layout drift)
struct SpinningRefreshIcon: View {
    let isSpinning: Bool
    var size: CGFloat = 11
    
    var body: some View {
        ZStack {
            if isSpinning {
                TimelineView(.animation) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let angle = (time.truncatingRemainder(dividingBy: 0.85) / 0.85) * 360.0
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: size, weight: .semibold))
                        .rotationEffect(.degrees(angle), anchor: .center)
                }
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: size, weight: .semibold))
            }
        }
        .frame(width: size + 4, height: size + 4, alignment: .center)
    }
}

// MARK: - Search Suggestions Dropdown (Liquid Glass with Backdrop Blur)
struct SearchSuggestionsDropdown: View {
    @Environment(\.colorScheme) private var colorScheme
    let detectedURL: YouTubeURLParseResult?
    let suggestions: [String]
    var selectedIndex: Int = -1
    let isQueryEmpty: Bool
    var onHoverIndex: ((Int) -> Void)? = nil
    let onSelect: (String) -> Void
    let onSelectURL: (YouTubeURLParseResult) -> Void
    let onRemoveRecent: (String) -> Void
    let onClearRecents: () -> Void
    
    var body: some View {
        let hasURL = (detectedURL != nil)
        
        VStack(alignment: .leading, spacing: 2) {
            // 1. Prominent Direct URL Action Card (if a YouTube link or ID was pasted/typed)
            if let result = detectedURL {
                let isURLSelected = (selectedIndex == 0)
                Button(action: { onSelectURL(result) }) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.1, blue: 0.1), Color(red: 0.85, green: 0.0, blue: 0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 34, height: 34)
                            Image(systemName: "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .offset(x: 1)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Phát video từ liên kết")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                
                                if result.isShort {
                                    Text("Shorts")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.red))
                                }
                            }
                            
                            Text("ID: \(result.videoId)" + (result.startTime != nil ? " • Bắt đầu tại \(Int(result.startTime!))s" : ""))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Text("Phát ngay")
                                .font(.system(size: 11.5, weight: .semibold))
                            Image(systemName: "return")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(red: 1.0, green: 0.1, blue: 0.1)))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isURLSelected ? (colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)) : Color(red: 1.0, green: 0.1, blue: 0.1).opacity(colorScheme == .dark ? 0.18 : 0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(isURLSelected ? (colorScheme == .dark ? Color.white.opacity(0.28) : Color.black.opacity(0.20)) : Color.red.opacity(colorScheme == .dark ? 0.35 : 0.2), lineWidth: isURLSelected ? 1.5 : 0.75)
                            )
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .onHover { hovering in
                    if hovering { onHoverIndex?(0) }
                }
            }
            
            // 2. Empty Query State or Recents State: Recent Searches & Interests Tags
            if suggestions.isEmpty {
                let recents = Array(RecommendationService.shared.recentSearches.prefix(5))
                let tags = RecommendationService.shared.dynamicInterestTags.prefix(5).filter { t in
                    !recents.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame })
                }
                
                if !recents.isEmpty {
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                            Text("Tìm kiếm gần đây")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        }
                        
                        Spacer()
                        
                        Button("Xoá tất cả") {
                            onClearRecents()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                    
                    ForEach(Array(recents.enumerated()), id: \.element) { i, item in
                        let globalIdx = (hasURL ? 1 : 0) + i
                        RecentSearchRow(
                            text: item,
                            isSelected: (selectedIndex == globalIdx),
                            onSelect: { onSelect(item) },
                            onDelete: { onRemoveRecent(item) },
                            onHover: { hovering in
                                if hovering { onHoverIndex?(globalIdx) }
                            }
                        )
                    }
                }
                
                if !tags.isEmpty {
                    Text("Gợi ý theo gu của bạn")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        .padding(.horizontal, 14)
                        .padding(.top, recents.isEmpty ? 4 : 8)
                        .padding(.bottom, 2)
                    
                    ForEach(Array(tags.enumerated()), id: \.element) { j, tag in
                        let globalIdx = (hasURL ? 1 : 0) + recents.count + j
                        SearchSuggestionRow(
                            text: tag,
                            isInterestTag: true,
                            isSelected: (selectedIndex == globalIdx),
                            action: { onSelect(tag) },
                            onHover: { hovering in
                                if hovering { onHoverIndex?(globalIdx) }
                            }
                        )
                    }
                }
            } else {
                // 3. Normal Autocomplete Suggestions
                let displayed = Array(suggestions.prefix(10))
                ForEach(Array(displayed.enumerated()), id: \.element) { i, item in
                    let globalIdx = (hasURL ? 1 : 0) + i
                    SearchSuggestionRow(
                        text: item,
                        isInterestTag: false,
                        isSelected: (selectedIndex == globalIdx),
                        action: { onSelect(item) },
                        onHover: { hovering in
                            if hovering { onHoverIndex?(globalIdx) }
                        }
                    )
                }
            }
        }
        .padding(.vertical, 6)
        .frame(width: 440)
        .liquidGlass(cornerRadius: 12, elevation: 10)
    }
}

struct RecentSearchRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    var isSelected: Bool = false
    let onSelect: () -> Void
    let onDelete: () -> Void
    var onHover: ((Bool) -> Void)? = nil
    @StateObject private var hoverVm = LiquidHoverViewModel()
    
    var body: some View {
        let isDark = (colorScheme == .dark)
        let isActive = isSelected || hoverVm.isHovered
        
        HStack(spacing: 10) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "arrow.right.circle.fill" : "clock")
                        .foregroundColor(
                            isSelected ? ThemeColor.textPrimary(for: colorScheme) :
                            ThemeColor.textSecondary(for: colorScheme).opacity(isActive ? 0.9 : 0.6)
                        )
                        .font(.system(size: 12, weight: isActive ? .bold : .medium))
                        .frame(width: 16)
                    
                    Text(text)
                        .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isSelected ? (isDark ? Color.white : Color.black) : ThemeColor.textPrimary(for: colorScheme))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if isSelected {
                        Text("⏎")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.85))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08))
                            )
                    }
                }
            }
            .buttonStyle(.plain)
            
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme).opacity(0.6))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Xoá khỏi lịch sử")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? (isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.07)) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? (isDark ? Color.white.opacity(0.22) : Color.black.opacity(0.16)) : Color.clear, lineWidth: 1)
                )
        )
        .padding(.horizontal, 6)
        .onHover { hovering in
            hoverVm.isHovered = hovering
            onHover?(hovering)
        }
    }
}

struct SearchSuggestionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    var isInterestTag: Bool = false
    var isSelected: Bool = false
    let action: () -> Void
    var onHover: ((Bool) -> Void)? = nil
    @StateObject private var hoverVm = LiquidHoverViewModel()
    
    var body: some View {
        let isDark = (colorScheme == .dark)
        let isActive = isSelected || hoverVm.isHovered
        
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "arrow.right.circle.fill" : "magnifyingglass")
                    .foregroundColor(
                        isSelected ? ThemeColor.textPrimary(for: colorScheme) :
                        ThemeColor.textSecondary(for: colorScheme).opacity(isActive ? 0.9 : 0.6)
                    )
                    .font(.system(size: 12, weight: isActive ? .bold : .medium))
                    .frame(width: 16)
                
                Text(text)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isSelected ? (isDark ? Color.white : Color.black) : ThemeColor.textPrimary(for: colorScheme))
                    .lineLimit(1)
                
                Spacer()
                
                if isSelected {
                    Text("⏎")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08))
                        )
                } else {
                    Image(systemName: "arrow.up.left")
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme).opacity(hoverVm.isHovered ? 0.7 : 0.3))
                        .font(.system(size: 10.5, weight: .medium))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? (isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.07)) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? (isDark ? Color.white.opacity(0.22) : Color.black.opacity(0.16)) : Color.clear, lineWidth: 1)
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering in
            hoverVm.isHovered = hovering
            onHover?(hovering)
        }
    }
}

// MARK: - Search Quick URL Bar (Top of Search Results View)
struct SearchQuickURLBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let onOpenSheet: () -> Void
    let onPasteAndPlay: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(Color.cyan)
                .frame(width: 20)
            
            Text("Xem trực tiếp bằng link YouTube (watch, shorts, youtu.be) không cần gõ tìm kiếm:")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.88))
                .lineLimit(1)
            
            Spacer()
            
            Button(action: onPasteAndPlay) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Dán từ Clipboard & Xem")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(red: 1.0, green: 0.1, blue: 0.1))
                )
            }
            .buttonStyle(.plain)
            
            Button(action: onOpenSheet) {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 11, weight: .medium))
                    Text("Nhập URL...")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .liquidGlass(cornerRadius: 10, elevation: 4)
        .padding(.horizontal, 28)
    }
}

// MARK: - Search Related Queries Shelf View ("Mọi người cũng tìm kiếm")
struct SearchRelatedQueriesShelfView: View {
    @Environment(\.colorScheme) private var colorScheme
    let queries: [String]
    let onSelect: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .foregroundColor(Color.cyan)
                    .font(.system(size: 15, weight: .semibold))
                
                Text("Mọi người cũng tìm kiếm")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                
                Spacer()
            }
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 10)], spacing: 10) {
                ForEach(queries, id: \.self) { query in
                    Button(action: { onSelect(query) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                            
                            Text(query)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06), lineWidth: 0.75)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .liquidGlass(cornerRadius: 12, elevation: 4)
        .padding(.vertical, 6)
    }
}

// MARK: - Search Results View (Authentic YouTube Search Architecture)
struct SearchResultsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var vm: ContentViewModel
    let onSelectVideo: (Video) -> Void
    let onLoadMore: () -> Void
    let onQuickURL: () -> Void
    let onPerformSearch: (String) -> Void
    var onSelectChannel: ((ChannelInfo) -> Void)? = nil
    
    private let filterOptions = ["Tất cả", "Video", "Shorts"]
    
    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 1. Quick URL Direct Play Bar (Paste or enter URL to play instantly)
                    SearchQuickURLBar(
                        onOpenSheet: { vm.showOpenURLSheet = true },
                        onPasteAndPlay: onQuickURL
                    )
                    .padding(.top, 14)
                    
                    // 2. Filter Chips Bar
                    HStack(spacing: 8) {
                        ForEach(filterOptions, id: \.self) { option in
                            LiquidGlassCapsuleButton(
                                action: { vm.searchFilter = option },
                                isSelected: vm.searchFilter == option
                            ) {
                                Text(option)
                                    .font(.system(size: 12.5, weight: vm.searchFilter == option ? .semibold : .medium))
                                    .foregroundColor(
                                        vm.searchFilter == option ?
                                            (colorScheme == .dark ? Color(red: 15/255, green: 15/255, blue: 15/255) : Color.white) :
                                            (colorScheme == .dark ? Color(red: 241/255, green: 241/255, blue: 241/255) : Color(red: 15/255, green: 15/255, blue: 15/255))
                                    )
                                    .padding(.horizontal, 14)
                                    .frame(height: 28)
                            }
                        }
                        
                        Spacer()
                        
                        if !vm.searchResults.isEmpty {
                            Text("\(vm.searchVideos.count) video • \(vm.searchShorts.count) Shorts")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        }
                    }
                    .padding(.horizontal, 28)
                    
                    // 3. Dynamic Contextual Expansion Chips Bar ("càng tìm càng ra kết quả hay")
                    if !vm.contextualChips.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Text("Gợi ý liên quan:")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                    .padding(.trailing, 2)
                                
                                ForEach(vm.contextualChips, id: \.self) { chip in
                                    Button(action: {
                                        onPerformSearch("\(vm.searchQuery) \(chip)")
                                    }) {
                                        HStack(spacing: 4) {
                                            Text(chip)
                                                .font(.system(size: 12, weight: .medium))
                                            Image(systemName: "arrow.up.right")
                                                .font(.system(size: 8.5, weight: .semibold))
                                                .opacity(0.55)
                                        }
                                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule()
                                                .fill(colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.05))
                                                .overlay(
                                                    Capsule()
                                                        .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 0.75)
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 1)
                        }
                    }
                    
                    if vm.isLoadingSearch && vm.searchResults.isEmpty {
                        VStack(spacing: 14) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Đang tìm kiếm video và kênh...")
                                .font(.system(size: 13))
                                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        }
                        .frame(maxWidth: .infinity, minHeight: 350)
                    } else if vm.searchResults.isEmpty && vm.searchChannel == nil {
                        VStack(spacing: 14) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 38))
                                .foregroundColor(ThemeColor.textSecondary(for: colorScheme).opacity(0.6))
                            Text("Không tìm thấy kết quả nào cho \"\(vm.searchQuery)\"")
                                .font(.system(size: 14.5, weight: .medium))
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            Text("Hãy thử kiểm tra lại chính tả hoặc tìm kiếm từ khoá khác")
                                .font(.system(size: 12))
                                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        }
                        .frame(maxWidth: .infinity, minHeight: 350)
                    } else {
                        // 4. Channel Card (if found and in "Tất cả" tab)
                        if (vm.searchFilter == "Tất cả" || vm.searchFilter == "Video"), let channel = vm.searchChannel {
                            SearchChannelCardView(channel: channel, onSelect: { onSelectChannel?(channel) })
                                .padding(.horizontal, 28)
                                .padding(.vertical, 6)
                            
                            Divider()
                                .background(ThemeColor.divider(for: colorScheme))
                                .padding(.horizontal, 28)
                        }
                        
                        // 5. Content Display based on Filter
                        if vm.searchFilter == "Shorts" {
                            // Shorts Grid View
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16, alignment: .top)], alignment: .leading, spacing: 22) {
                                ForEach(Array(vm.searchShorts.enumerated()), id: \.element.id) { index, short in
                                    SearchShortCardView(video: short) {
                                        onSelectVideo(short)
                                    }
                                    .onAppear {
                                        if index >= vm.searchShorts.count - 4 {
                                            onLoadMore()
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 28)
                        } else if vm.searchFilter == "Video" {
                            // Videos List View
                            LazyVStack(spacing: 16) {
                                ForEach(Array(vm.searchVideos.enumerated()), id: \.element.id) { index, video in
                                    SearchVideoRowView(
                                        video: video,
                                        isSelected: (vm.selectedSearchResultIndex == index),
                                        onSelect: { onSelectVideo(video) },
                                        onSelectChannel: onSelectChannel
                                    )
                                    .id("search_video_\(index)")
                                    .onAppear {
                                        if index >= vm.searchVideos.count - 4 {
                                            onLoadMore()
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 28)
                        } else {
                            // "Tất cả" Tab: Integrated View (Videos list + Shorts shelf + Related Queries shelf)
                            VStack(alignment: .leading, spacing: 20) {
                                let topVideos = Array(vm.searchVideos.prefix(3))
                                let remainingVideos = Array(vm.searchVideos.dropFirst(3))
                                
                                LazyVStack(spacing: 16) {
                                    ForEach(Array(topVideos.enumerated()), id: \.element.id) { index, video in
                                        SearchVideoRowView(
                                            video: video,
                                            isSelected: (vm.selectedSearchResultIndex == index),
                                            onSelect: { onSelectVideo(video) },
                                            onSelectChannel: onSelectChannel
                                        )
                                        .id("search_video_\(index)")
                                    }
                                }
                                
                                // Shorts Shelf (if available)
                                if !vm.searchShorts.isEmpty {
                                    SearchShortsShelfView(
                                        title: "Shorts",
                                        shorts: Array(vm.searchShorts.prefix(14)),
                                        onSelectShort: { onSelectVideo($0) }
                                    )
                                }
                                
                                // "Mọi người cũng tìm kiếm" (Related Searches Shelf)
                                if !vm.relatedSearches.isEmpty {
                                    SearchRelatedQueriesShelfView(
                                        queries: vm.relatedSearches,
                                        onSelect: { query in
                                            onPerformSearch(query)
                                        }
                                    )
                                }
                                
                                // Remaining videos
                                LazyVStack(spacing: 16) {
                                    ForEach(Array(remainingVideos.enumerated()), id: \.element.id) { index, video in
                                        let globalIdx = topVideos.count + index
                                        SearchVideoRowView(
                                            video: video,
                                            isSelected: (vm.selectedSearchResultIndex == globalIdx),
                                            onSelect: { onSelectVideo(video) },
                                            onSelectChannel: onSelectChannel
                                        )
                                        .id("search_video_\(globalIdx)")
                                        .onAppear {
                                            if index >= remainingVideos.count - 4 {
                                                onLoadMore()
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 28)
                        }
                        
                        // 4. Loading More Footer / End of results
                        if vm.isLoadingMoreSearch {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Đang tải thêm kết quả từ YouTube...")
                                    .font(.system(size: 12.5))
                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        } else if !vm.canLoadMoreSearch && !vm.searchResults.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                                    .font(.system(size: 12))
                                Text("Đã hiển thị hết kết quả tìm kiếm")
                                    .font(.system(size: 12))
                                    .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .onChange(of: vm.selectedSearchResultIndex) { idx in
                if idx >= 0 {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scrollProxy.scrollTo("search_video_\(idx)", anchor: .center)
                    }
                }
            }
        }
    }
}

// MARK: - Search Channel Card View (Top of Search Results)
struct SearchChannelCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let channel: ChannelInfo
    var onSelect: (() -> Void)? = nil
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 24) {
            Button(action: { onSelect?() }) {
                HStack(spacing: 24) {
                    // Large Circular Avatar
                    CachedAsyncThumbnail(
                        url: channel.avatarUrl,
                        maxPixelSize: 164,
                        placeholderColor: Color(white: 0.18)
                    )
                    .frame(width: 82, height: 82)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(ThemeColor.divider(for: colorScheme), lineWidth: 1.5))
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.10), radius: 8, x: 0, y: 4)
                    
                    // Channel Info
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(channel.title)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                            
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(Color.cyan)
                                .font(.system(size: 13))
                        }
                        
                        HStack(spacing: 8) {
                            if let handle = channel.handle, !handle.isEmpty {
                                Text(handle)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                            }
                            if let subs = channel.subscriberCount, !subs.isEmpty {
                                Text("•")
                                    .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                                Text(subs)
                                    .font(.system(size: 13))
                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                            }
                        }
                        
                        if let desc = channel.description, !desc.isEmpty {
                            Text(desc)
                                .font(.system(size: 12))
                                .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                                .lineLimit(2)
                                .padding(.top, 2)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Xem toàn bộ video của kênh \(channel.title)")
            
            Spacer()
            
            // Channel Subscribe Button
            let isSub = ChannelSubscriptionManager.shared.isSubscribed(channel.title) || ChannelSubscriptionManager.shared.isSubscribed(channel.id)
            Button(action: {
                ChannelSubscriptionManager.shared.toggleSubscription(
                    title: channel.title,
                    id: channel.id,
                    handle: channel.handle,
                    avatarUrl: channel.avatarUrl
                )
            }) {
                HStack(spacing: 6) {
                    if isSub {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    Text(isSub ? "Đã đăng ký" : "Đăng ký")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundColor(isSub ? ThemeColor.textPrimary(for: colorScheme) : (colorScheme == .dark ? Color.black : Color.white))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSub ? ThemeColor.buttonBackground(for: colorScheme, isHovered: false) : (colorScheme == .dark ? Color.white : Color(red: 15/255, green: 15/255, blue: 15/255)))
                        .overlay(Capsule().strokeBorder(ThemeColor.buttonBorder(for: colorScheme, isHovered: false), lineWidth: 0.75))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isHovered ? ThemeColor.sidebarHover(for: colorScheme) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Search Video Row View (Authentic Horizontal Search Card)
struct SearchVideoRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    let video: Video
    var isSelected: Bool = false
    let onSelect: () -> Void
    var onSelectChannel: ((ChannelInfo) -> Void)? = nil
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            // Left: 16:9 Thumbnail (Clicking plays video)
            Button(action: onSelect) {
                ZStack(alignment: .bottomTrailing) {
                    CachedAsyncThumbnail(
                        url: video.thumbnail,
                        maxPixelSize: 640,
                        placeholderColor: colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.88)
                    )
                    .frame(width: 320, height: 180)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        (colorScheme == .dark ? Color.white : Color.black).opacity((isSelected || isHovered) ? 0.35 : 0.10),
                                        (colorScheme == .dark ? Color.white : Color.black).opacity((isSelected || isHovered) ? 0.15 : 0.02)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    
                    // Duration badge
                    Text(video.durationFormatted)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .padding(8)
                }
            }
            .buttonStyle(.plain)
            
            // Right: Details
            VStack(alignment: .leading, spacing: 6) {
                // Title (Clicking plays video)
                Button(action: onSelect) {
                    Text(video.title)
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                }
                .buttonStyle(.plain)
                
                // Metadata: Views & Date
                Text(video.metadataFormatted)
                    .font(.system(size: 12))
                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                
                // Channel (Clicking opens Channel View)
                Button(action: {
                    let ch = ChannelInfo(
                        id: video.uploaderId ?? "",
                        title: video.uploader,
                        avatarUrl: video.channelAvatarUrl ?? ""
                    )
                    onSelectChannel?(ch)
                }) {
                    HStack(spacing: 8) {
                        if let avatar = video.channelAvatarUrl, !avatar.isEmpty {
                            CachedAsyncThumbnail(
                                url: avatar,
                                maxPixelSize: 64,
                                placeholderColor: colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.85)
                            )
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.85))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Text(video.uploader.prefix(1).uppercased())
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                )
                        }
                        
                        Text(video.uploader)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.88))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Xem toàn bộ video của kênh \(video.uploader)")
                .padding(.vertical, 4)
                
                // Description Preview Snippet
                if let desc = video.description, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                }
                
                Spacer(minLength: 0)
            }
            
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill((isSelected || isHovered) ? ThemeColor.sidebarHover(for: colorScheme) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? (colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.25)) : Color.clear, lineWidth: 1.5)
                )
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button {
                let url = YouTubeURLParser.makeShareURL(videoId: video.id)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
                PlayerManager.shared.flashHUD(icon: "link", text: "Đã sao chép liên kết video 📋")
            } label: {
                Label("Sao chép liên kết video", systemImage: "link")
            }
            
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(video.id, forType: .string)
                PlayerManager.shared.flashHUD(icon: "number", text: "Đã sao chép ID: \(video.id) 📋")
            } label: {
                Label("Sao chép Video ID", systemImage: "number")
            }
            
            Divider()
            
            Button {
                if let url = URL(string: "https://www.youtube.com/watch?v=\(video.id)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Mở trên YouTube (Trình duyệt)", systemImage: "safari")
            }
            
            Button {
                _ = DownloadManager.shared.startDownload(video: video, quality: "1080", isAudioOnly: false)
                PlayerManager.shared.flashHUD(icon: "arrow.down.circle.fill", text: "Đang tải xuống video...")
            } label: {
                Label("Tải xuống video (1080p)", systemImage: "arrow.down.to.line")
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Search Shorts Shelf View (Horizontal Scrollable Shorts)
struct SearchShortsShelfView: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let shorts: [Video]
    let onSelectShort: (Video) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .foregroundColor(Color(red: 1.0, green: 0.1, blue: 0.1))
                    .font(.system(size: 17, weight: .bold))
                
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
            }
            .padding(.top, 6)
            
            // Horizontal scrollable Shorts cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(shorts) { short in
                        SearchShortCardView(video: short) {
                            onSelectShort(short)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Search Short Card View (9:16 Vertical Card)
struct SearchShortCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let video: Video
    let onSelect: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                // 9:16 Vertical Thumbnail
                ZStack(alignment: .bottomTrailing) {
                    CachedAsyncThumbnail(
                        url: video.thumbnail,
                        maxPixelSize: 500,
                        placeholderColor: colorScheme == .dark ? Color(white: 0.14) : Color(white: 0.85)
                    )
                    .frame(width: 170, height: 285)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        (colorScheme == .dark ? Color.white : Color.black).opacity(isHovered ? 0.35 : 0.12),
                                        (colorScheme == .dark ? Color.white : Color.black).opacity(isHovered ? 0.12 : 0.03)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.2
                            )
                    )
                    
                    // Subtle dark gradient at bottom for contrast
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.8)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(width: 170, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
                    if !video.viewCountFormatted.isEmpty {
                        Text(video.viewCountFormatted)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(8)
                    }
                }
                
                // Short Title
                Text(video.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isHovered ? ThemeColor.textPrimary(for: colorScheme) : ThemeColor.textPrimary(for: colorScheme).opacity(0.88))
                    .lineLimit(2)
                    .frame(width: 170, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                let url = "https://www.youtube.com/shorts/\(video.id)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
                PlayerManager.shared.flashHUD(icon: "link", text: "Đã sao chép link Shorts 📋")
            } label: {
                Label("Sao chép liên kết Shorts", systemImage: "link")
            }
            
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(video.id, forType: .string)
                PlayerManager.shared.flashHUD(icon: "number", text: "Đã sao chép ID: \(video.id) 📋")
            } label: {
                Label("Sao chép Video ID", systemImage: "number")
            }
            
            Divider()
            
            Button {
                if let url = URL(string: "https://www.youtube.com/shorts/\(video.id)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Mở trên YouTube (Trình duyệt)", systemImage: "safari")
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

