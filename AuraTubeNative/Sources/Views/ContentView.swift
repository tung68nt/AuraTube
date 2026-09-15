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
    
    // Autocomplete Suggestions & Infinite Scroll Pagination
    @Published var searchSuggestions: [String] = []
    @Published var showSuggestions: Bool = false
    @Published var searchContinuationToken: String? = nil
    @Published var isLoadingSearch: Bool = false
    @Published var isLoadingMoreSearch: Bool = false
    @Published var canLoadMoreSearch: Bool = true
    
    private var suggestionTask: Task<Void, Never>? = nil
    
    func updateSearchSuggestions(for query: String) {
        suggestionTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchSuggestions = []
            showSuggestions = false
            return
        }
        
        suggestionTask = Task {
            try? await Task.sleep(nanoseconds: 160_000_000) // 160ms debounce
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
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            if !playerManager.isVideoFullscreen {
                // MARK: - 1. Unified Window Header (Height: 52)
                ZStack {
                    if colorScheme == .dark {
                        ThemeColor.headerBackground(for: colorScheme)
                        VisualEffectBackground(material: .headerView, blendingMode: .withinWindow)
                            .overlay(Color.white.opacity(0.02))
                    } else {
                        Color.white
                    }
                    
                    // Centered Search Box with macOS HIG styling & high contrast
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                            .font(.system(size: 13, weight: .medium))
                        
                        ZStack(alignment: .leading) {
                            if vm.searchQuery.isEmpty {
                                Text("Tìm kiếm trên YouTube...")
                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                    .font(.system(size: 13))
                                    .allowsHitTesting(false)
                            }
                            
                            TextField("", text: $vm.searchQuery)
                                .textFieldStyle(.plain)
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                .font(.system(size: 13))
                                .onChange(of: vm.searchQuery) { newQuery in
                                    vm.updateSearchSuggestions(for: newQuery)
                                }
                                .onExitCommand {
                                    vm.dismissSuggestions()
                                }
                                .onSubmit { performSearch() }
                        }
                        
                        if !vm.searchQuery.isEmpty {
                            Button(action: {
                                vm.searchQuery = ""
                                vm.dismissSuggestions()
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
                    }
                    .padding(.horizontal, 12)
                    .frame(width: 400, height: 32)
                    .liquidGlassSearchBar()
                    
                    // Left Controls: Brand (Sidebar Column) + Navigation (Main Content Column)
                    HStack(spacing: 0) {
                        // Sidebar Header Area: Brand Logo & Title (Width: 220, matches sidebar below)
                        HStack(spacing: 9) {
                            YouTubeBrandBadge(width: 26)
                                .padding(.leading, 16)
                            
                            HStack(alignment: .center, spacing: 3.5) {
                                Text("AuraTube")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                    .tracking(-0.35)
                                    .lineLimit(1)
                                    .fixedSize()
                                
                                Text("VN")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                    .offset(y: -4.5)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            
                            Spacer()
                        }
                        .frame(width: 220, height: 52, alignment: .leading)
                        
                        // Vertical Column Separator aligned with Sidebar boundary below
                        Rectangle()
                            .fill(ThemeColor.divider(for: colorScheme))
                            .frame(width: 0.75, height: 24)
                        
                        // Navigation Controls (Back / Forward) cleanly inside Main Content toolbar
                        HStack(spacing: 6) {
                            let canGoBack = vm.watchingVideo != nil || vm.isSearching
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    if vm.watchingVideo != nil {
                                        vm.watchingVideo = nil
                                    } else if vm.isSearching {
                                        vm.isSearching = false
                                        vm.searchQuery = ""
                                    }
                                }
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(canGoBack ? ThemeColor.textPrimary(for: colorScheme) : (colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.22)))
                                    .frame(width: 28, height: 28)
                                    .background(
                                        canGoBack ?
                                            ThemeColor.buttonBackground(for: colorScheme, isHovered: false) :
                                            (colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
                                    )
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle().strokeBorder(
                                            canGoBack ?
                                                ThemeColor.buttonBorder(for: colorScheme, isHovered: false) :
                                                (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)),
                                            lineWidth: 0.75
                                        )
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(!canGoBack)
                            .help(canGoBack ? "Quay lại" : "")
                            
                            Button(action: {}) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.18))
                                    .frame(width: 28, height: 28)
                                    .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
                                    .clipShape(Circle())
                                    .overlay(Circle().strokeBorder(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.75))
                            }
                            .buttonStyle(.plain)
                            .disabled(true)
                        }
                        .padding(.leading, 12)
                        
                        Spacer()
                    }
                    
                    // Right Controls: Quick Actions & Update Status
                    HStack(spacing: 8) {
                        Spacer()
                        
                        // Theme Toggle Button (Light / Dark / Auto System)
                        Button(action: {
                            themeManager.cycleTheme()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(ThemeColor.buttonBackground(for: colorScheme, isHovered: false))
                                Circle()
                                    .strokeBorder(ThemeColor.buttonBorder(for: colorScheme, isHovered: false), lineWidth: 0.75)
                                Image(systemName: themeManager.currentTheme.iconName)
                                    .font(.system(size: 12))
                                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.85))
                            }
                            .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .help("Giao diện: \(themeManager.currentTheme.title) (Bấm để đổi)")
                        
                        if updateService.isUpdateAvailable, let update = updateService.latestUpdate {
                            LiquidGlassButton(action: {
                                updateService.showUpdateSheet = true
                            }, cornerRadius: 8, isProminent: true) {
                                HStack(spacing: 5) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.cyan)
                                    Text("Bản mới v\(update.version)")
                                        .font(.system(size: 11.5, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                            }
                        } else {
                            // Refresh / Update Scan Icon Button
                            Button(action: {
                                updateService.scanForUpdates(isUserInitiated: true)
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(ThemeColor.buttonBackground(for: colorScheme, isHovered: false))
                                    Circle()
                                        .strokeBorder(ThemeColor.buttonBorder(for: colorScheme, isHovered: false), lineWidth: 0.75)
                                    SpinningRefreshIcon(isSpinning: updateService.isScanning, size: 11)
                                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.85))
                                }
                                .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                            .help(updateService.isScanning ? "Đang quét bản mới..." : "Kiểm tra bản cập nhật")
                            
                            // App Info / About Button
                            Button(action: {
                                AppDelegate.showStandardAboutPanel()
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(ThemeColor.buttonBackground(for: colorScheme, isHovered: false))
                                    Circle()
                                        .strokeBorder(ThemeColor.buttonBorder(for: colorScheme, isHovered: false), lineWidth: 0.75)
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 12.5))
                                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme).opacity(0.85))
                                }
                                .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                            .help("Thông tin AuraTube")
                        }
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
        HStack(spacing: 0) {
            if !playerManager.isVideoFullscreen {
                // Left Sidebar Items with Native macOS Styling
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(NavigationSection.allCases) { section in
                        SidebarNavButton(
                            section: section,
                            isSelected: vm.selectedSection == section && vm.watchingVideo == nil
                        ) {
                            vm.selectedSection = section
                            vm.watchingVideo = nil
                            if section == .shorts {
                                playerManager.stop()
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(.top, 14)
                .frame(width: 220)
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
                        }
                    )
                } else if vm.isSearching {
                    SearchResultsView(
                        vm: vm,
                        onSelectVideo: { playVideo($0) },
                        onLoadMore: { loadMoreSearchResults() }
                    )
                } else {
                    switch vm.selectedSection {
                    case .home:
                        HomeView(onSelectVideo: { playVideo($0) })
                    case .shorts:
                        NativeShortsFeedView(
                            selectedShort: $vm.selectedShortVideo,
                            onSelectVideo: { forcePlayLongVideo($0) }
                        )
                    case .bookmarks:
                        BookmarkListView(onSelectVideo: { playVideo($0) })
                    case .history:
                        HistoryListView(onSelectVideo: { playVideo($0) })
                    case .downloads:
                        DownloadListView()
                    }
                }
                
                // Picture-in-Picture (PiP) Floating Mini-Player at bottom right corner
                if !playerManager.isVideoFullscreen, vm.watchingVideo == nil, vm.selectedSection != .shorts, let activeVideo = playerManager.currentVideo {
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
                    .transition(.scale(scale: 0.88).combined(with: .opacity))
                    .zIndex(100)
                }
            }
        }
        }
    }
    .frame(
        minWidth: playerManager.isVideoFullscreen ? 0 : 980,
        minHeight: playerManager.isVideoFullscreen ? 0 : 640
    )
    .background(
        Group {
            if playerManager.isVideoFullscreen {
                Color.black
            } else {
                colorScheme == .dark ? Color(red: 0.09, green: 0.09, blue: 0.10) : Color.white
            }
        }
    )
    .overlay(alignment: .top) {
        ZStack(alignment: .top) {
            if let feedback = updateService.scanFeedbackMessage {
                ScanFeedbackToast(message: feedback)
                    .padding(.top, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(300)
            }
            
            if vm.showSuggestions && !vm.searchSuggestions.isEmpty {
                // Invisible backdrop to dismiss suggestions when clicking outside
                Color.black.opacity(0.001)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) {
                            vm.dismissSuggestions()
                        }
                    }
                
                SearchSuggestionsDropdown(
                    suggestions: vm.searchSuggestions,
                    onSelect: { suggestion in
                        performSearch(with: suggestion)
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
    .onChange(of: playerManager.isVideoFullscreen) { isFS in
        if isFS, vm.watchingVideo == nil, let active = playerManager.currentVideo {
            if !active.isShort {
                vm.watchingVideo = active
            }
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
    .sheet(isPresented: $updateService.showUpdateSheet) {
        UpdateSheetView()
    }
}
    
    private func playVideo(_ video: Video) {
        vm.dismissSuggestions()
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
        vm.selectedShortVideo = nil
        vm.watchingVideo = video
        playerManager.loadAndPlay(video: video)
    }
    
    private func performSearch(with queryOverride: String? = nil) {
        if let override = queryOverride {
            vm.searchQuery = override
        }
        let query = vm.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        
        vm.dismissSuggestions()
        vm.isSearching = true
        vm.watchingVideo = nil
        vm.isLoadingSearch = true
        vm.isLoadingMoreSearch = false
        vm.searchContinuationToken = nil
        vm.searchChannel = nil
        vm.searchVideos = []
        vm.searchShorts = []
        vm.searchResults = []
        vm.searchFilter = "Tất cả"
        vm.canLoadMoreSearch = true
        
        Task {
            let page = await YTDLPService.shared.searchVideosWithContinuation(query: query)
            vm.searchChannel = page.channel
            vm.searchVideos = page.videos
            vm.searchShorts = page.shorts
            vm.searchResults = page.allItems
            vm.searchContinuationToken = page.continuationToken
            vm.canLoadMoreSearch = page.continuationToken != nil
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 380), spacing: 20)], spacing: 28) {
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 380), spacing: 20)], spacing: 28) {
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
                Text("Tệp tải về")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                Spacer()
                Button(action: { downloadManager.openDownloadFolder() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        Text("Mở thư mục trong Finder")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(ThemeColor.buttonBackground(for: colorScheme, isHovered: false))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ThemeColor.buttonBorder(for: colorScheme, isHovered: false), lineWidth: 0.75))
                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            if downloadManager.downloads.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 32))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme).opacity(0.6))
                    Text("Chưa có tác vụ tải về nào")
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(downloadManager.downloads) { item in
                    HStack(spacing: 14) {
                        Image(systemName: item.isComplete ? "checkmark.circle.fill" : "arrow.down.circle")
                            .foregroundColor(item.isComplete ? .green : ThemeColor.textPrimary(for: colorScheme))
                            .font(.system(size: 18))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                .lineLimit(1)
                            
                            HStack {
                                Text(item.quality)
                                    .font(.system(size: 12))
                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                                Text("•")
                                    .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                                Text(item.statusText)
                                    .font(.system(size: 12))
                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                            }
                            
                            if !item.isComplete && item.progress > 0 {
                                ProgressView(value: item.progress)
                                    .progressViewStyle(.linear)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

// MARK: - Picture-in-Picture (PiP) Mini-Player Overlay
@MainActor
final class PiPHoverViewModel: ObservableObject {
    @Published var isHovered = false
}

struct MiniPlayerPiPOverlay: View {
    let video: Video
    let onExpand: () -> Void
    let onClose: () -> Void
    
    @ObservedObject private var playerManager = PlayerManager.shared
    @StateObject private var hoverVm = PiPHoverViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. Video Frame (16:9)
            ZStack(alignment: .center) {
                NativePlayerView()
                    .frame(width: 340, height: 191.25)
                    .background(Color.black)
                
                // Overlay on hover: Expand hint & close button
                if hoverVm.isHovered {
                    ZStack(alignment: .top) {
                        Color.black.opacity(0.25)
                            .allowsHitTesting(false)
                        
                        HStack {
                            Button(action: onExpand) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("Phóng to")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.65))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                            
                            Spacer()
                            
                            Button(action: onClose) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Color.black.opacity(0.65))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                        }
                    }
                    .frame(width: 340, height: 191.25)
                }
            }
            .frame(width: 340, height: 191.25)
            
            // 2. YouTube Red Progress Line
            GeometryReader { geo in
                let pct = playerManager.duration > 0 ? min(1.0, max(0.0, playerManager.currentTime / playerManager.duration)) : 0
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 2.5)
                    Rectangle()
                        .fill(Color(red: 1.0, green: 0.08, blue: 0.12))
                        .frame(width: geo.size.width * CGFloat(pct), height: 2.5)
                }
            }
            .frame(height: 2.5)
            
            // 3. Bottom Controls & Metadata Bar (Height 50)
            HStack(spacing: 12) {
                // Video Info (Clicking title expands video)
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(video.uploader)
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.6))
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onExpand()
                }
                
                Spacer(minLength: 4)
                
                // Play / Pause Button with Liquid Glass
                LiquidGlassCircleButton(action: {
                    playerManager.togglePlayPause()
                }, size: 30) {
                    Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Expand Button with Liquid Glass
                LiquidGlassCircleButton(action: onExpand, size: 28) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(white: 0.88))
                }
                .help("Mở rộng toàn màn hình")
                
                // Close Button with Liquid Glass
                LiquidGlassCircleButton(action: onClose, size: 28) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(white: 0.88))
                }
                .help("Đóng phát")
            }
            .padding(.horizontal, 12)
            .frame(width: 340, height: 50)
        }
        .frame(width: 340)
        .liquidGlass(cornerRadius: 14, isHovered: hoverVm.isHovered, elevation: 14)
        .shadow(color: Color.black.opacity(0.65), radius: 20, x: 0, y: 10)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoverVm.isHovered = hovering
            }
        }
    }
}

// MARK: - Update Notification Banner
struct UpdateNotificationBanner: View {
    let update: AppUpdateInfo
    @ObservedObject private var updateService = UpdateService.shared
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.blue.opacity(0.35), Color.purple.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 38, height: 38)
                Image(systemName: "sparkles")
                    .foregroundColor(.cyan)
                    .font(.system(size: 16, weight: .bold))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Đã có bản cập nhật mới AuraTube v\(update.version)!")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("KHUYÊN DÙNG")
                        .font(.system(size: 9, weight: .black))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.green.opacity(0.25))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
                
                Text("Vui lòng cập nhật ngay để khắc phục triệt để lỗi âm thanh (mute/unmute) và tận hưởng trải nghiệm mượt mà nhất.")
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(white: 0.75))
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
                        .foregroundColor(Color(white: 0.7))
                }
                .help("Bỏ qua thông báo này")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .liquidGlass(cornerRadius: 12, elevation: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LinearGradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)], startPoint: .leading, endPoint: .trailing),
                    lineWidth: 1
                )
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
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
    let suggestions: [String]
    let onSelect: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(suggestions.prefix(10)), id: \.self) { item in
                SearchSuggestionRow(text: item) {
                    onSelect(item)
                }
            }
        }
        .padding(.vertical, 6)
        .frame(width: 440)
        .liquidGlass(cornerRadius: 12, elevation: 10)
    }
}

struct SearchSuggestionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    let action: () -> Void
    @StateObject private var hoverVm = LiquidHoverViewModel()
    
    var body: some View {
        let isDark = (colorScheme == .dark)
        
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme).opacity(hoverVm.isHovered ? 1.0 : 0.6))
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                
                Text(text)
                    .font(.system(size: 13, weight: hoverVm.isHovered ? .semibold : .regular))
                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    .lineLimit(1)
                
                Spacer()
                
                Image(systemName: "arrow.up.left")
                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme).opacity(hoverVm.isHovered ? 0.7 : 0.3))
                    .font(.system(size: 10.5, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hoverVm.isHovered ? (isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.06)) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering in
            hoverVm.isHovered = hovering
        }
    }
}

// MARK: - Search Results View (Authentic YouTube Search Architecture)
struct SearchResultsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var vm: ContentViewModel
    let onSelectVideo: (Video) -> Void
    let onLoadMore: () -> Void
    
    private let filterOptions = ["Tất cả", "Video", "Shorts"]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Filter Chips Bar
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
                .padding(.top, 14)
                
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
                    // 2. Channel Card (if found and in "Tất cả" tab)
                    if (vm.searchFilter == "Tất cả" || vm.searchFilter == "Video"), let channel = vm.searchChannel {
                        SearchChannelCardView(channel: channel)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 6)
                        
                        Divider()
                            .background(ThemeColor.divider(for: colorScheme))
                            .padding(.horizontal, 28)
                    }
                    
                    // 3. Content Display based on Filter
                    if vm.searchFilter == "Shorts" {
                        // Shorts Grid View
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)], spacing: 22) {
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
                                SearchVideoRowView(video: video) {
                                    onSelectVideo(video)
                                }
                                .onAppear {
                                    if index >= vm.searchVideos.count - 4 {
                                        onLoadMore()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 28)
                    } else {
                        // "Tất cả" Tab: Integrated View (Videos list + Shorts shelf in between)
                        VStack(alignment: .leading, spacing: 20) {
                            let topVideos = Array(vm.searchVideos.prefix(3))
                            let remainingVideos = Array(vm.searchVideos.dropFirst(3))
                            
                            LazyVStack(spacing: 16) {
                                ForEach(topVideos) { video in
                                    SearchVideoRowView(video: video) {
                                        onSelectVideo(video)
                                    }
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
                            
                            // Remaining videos
                            LazyVStack(spacing: 16) {
                                ForEach(Array(remainingVideos.enumerated()), id: \.element.id) { index, video in
                                    SearchVideoRowView(video: video) {
                                        onSelectVideo(video)
                                    }
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
    }
}

// MARK: - Search Channel Card View (Top of Search Results)
struct SearchChannelCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let channel: ChannelInfo
    @StateObject private var hoverVm = LiquidHoverViewModel()
    
    var body: some View {
        HStack(spacing: 24) {
            // Large Circular Avatar
            AsyncImage(url: URL(string: channel.avatarUrl)) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    Circle().fill(Color(white: 0.18))
                }
            }
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
                    Image(systemName: isSub ? "checkmark" : "bell.fill")
                        .font(.system(size: 11.5, weight: .semibold))
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
                .fill(hoverVm.isHovered ? ThemeColor.sidebarHover(for: colorScheme) : Color.clear)
        )
        .onHover { hovering in
            hoverVm.isHovered = hovering
        }
    }
}

// MARK: - Search Video Row View (Authentic Horizontal Search Card)
struct SearchVideoRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    let video: Video
    let onSelect: () -> Void
    @StateObject private var hoverVm = LiquidHoverViewModel()
    
    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 18) {
                // Left: 16:9 Thumbnail
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: URL(string: video.thumbnail)) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            (colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.88))
                        }
                    }
                    .frame(width: 320, height: 180)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        (colorScheme == .dark ? Color.white : Color.black).opacity(hoverVm.isHovered ? 0.28 : 0.10),
                                        (colorScheme == .dark ? Color.white : Color.black).opacity(hoverVm.isHovered ? 0.10 : 0.02)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    
                    // Duration badge
                    Text(video.durationFormatted)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .padding(8)
                }
                
                // Right: Details
                VStack(alignment: .leading, spacing: 6) {
                    // Title
                    Text(video.title)
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                    
                    // Metadata: Views & Date
                    Text(video.metadataFormatted)
                        .font(.system(size: 12))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    
                    // Channel
                    HStack(spacing: 8) {
                        if let avatar = video.channelAvatarUrl, !avatar.isEmpty {
                            AsyncImage(url: URL(string: avatar)) { phase in
                                if let img = phase.image {
                                    img.resizable().scaledToFill()
                                } else {
                                    Circle().fill(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.85))
                                }
                            }
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
                    .fill(hoverVm.isHovered ? ThemeColor.sidebarHover(for: colorScheme) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoverVm.isHovered = hovering
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
    @StateObject private var hoverVm = LiquidHoverViewModel()
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                // 9:16 Vertical Thumbnail
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: URL(string: video.thumbnail)) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            (colorScheme == .dark ? Color(white: 0.14) : Color(white: 0.85))
                        }
                    }
                    .frame(width: 170, height: 285)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        (colorScheme == .dark ? Color.white : Color.black).opacity(hoverVm.isHovered ? 0.35 : 0.12),
                                        (colorScheme == .dark ? Color.white : Color.black).opacity(hoverVm.isHovered ? 0.12 : 0.03)
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
                    .foregroundColor(hoverVm.isHovered ? ThemeColor.textPrimary(for: colorScheme) : ThemeColor.textPrimary(for: colorScheme).opacity(0.88))
                    .lineLimit(2)
                    .frame(width: 170, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoverVm.isHovered = hovering
        }
    }
}

