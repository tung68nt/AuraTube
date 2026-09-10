import SwiftUI

public enum NavigationSection: String, CaseIterable, Identifiable {
    case home = "Trang chủ"
    case bookmarks = "Xem sau"
    case history = "Video đã xem"
    case downloads = "Tệp đã tải về"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .home: return "house.fill"
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
    @Published var searchQuery: String = ""
    @Published var searchResults: [Video] = []
    @Published var isSearching: Bool = false
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

struct MacTrafficLightsView: View {
    @StateObject private var hoverVm = LiquidHoverViewModel()
    @Environment(\.controlActiveState) var controlActiveState
    
    var body: some View {
        HStack(spacing: 8) {
            // Close Button
            trafficButton(
                baseColor: Color(red: 1.0, green: 0.373, blue: 0.337),
                borderColor: Color(red: 0.878, green: 0.267, blue: 0.243),
                icon: "xmark",
                iconSize: 7
            ) {
                if let w = NSApp.keyWindow {
                    w.performClose(nil)
                } else if let w = NSApp.windows.first {
                    w.performClose(nil)
                }
            }
            
            // Minimize Button
            trafficButton(
                baseColor: Color(red: 1.0, green: 0.741, blue: 0.180),
                borderColor: Color(red: 0.871, green: 0.631, blue: 0.137),
                icon: "minus",
                iconSize: 7
            ) {
                if let w = NSApp.keyWindow {
                    w.miniaturize(nil)
                } else if let w = NSApp.windows.first {
                    w.miniaturize(nil)
                }
            }
            
            // Zoom / Maximize Button
            trafficButton(
                baseColor: Color(red: 0.153, green: 0.788, blue: 0.247),
                borderColor: Color(red: 0.102, green: 0.671, blue: 0.161),
                icon: "plus",
                iconSize: 6.5
            ) {
                if let w = NSApp.keyWindow {
                    w.zoom(nil)
                } else if let w = NSApp.windows.first {
                    w.zoom(nil)
                }
            }
        }
        .onHover { hovering in
            hoverVm.isHovered = hovering
        }
    }
    
    private func trafficButton(
        baseColor: Color,
        borderColor: Color,
        icon: String,
        iconSize: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(controlActiveState == .inactive ? Color(white: 0.32) : baseColor)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                controlActiveState == .inactive ? Color(white: 0.26) : borderColor,
                                lineWidth: 0.5
                            )
                    )
                
                if hoverVm.isHovered && controlActiveState != .inactive {
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .bold))
                        .foregroundColor(Color.black.opacity(0.65))
                }
            }
            .frame(width: 13, height: 13)
        }
        .buttonStyle(.plain)
    }
}

struct SidebarNavButton: View {
    let section: NavigationSection
    let isSelected: Bool
    let action: () -> Void
    @StateObject private var hoverVm = LiquidHoverViewModel()
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.iconName)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : (hoverVm.isHovered ? .white : Color.white.opacity(0.68)))
                    .frame(width: 26)
                
                Text(section.rawValue)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : (hoverVm.isHovered ? .white : Color.white.opacity(0.72)))
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.24), Color.white.opacity(0.06)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 0.75
                                    )
                            )
                    } else if hoverVm.isHovered {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.07))
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
                    // Solid dark header base to completely prevent background apps from showing through
                    Color(red: 0.12, green: 0.12, blue: 0.13)
                    VisualEffectBackground(material: .headerView, blendingMode: .withinWindow)
                        .overlay(Color.white.opacity(0.02))
                    
                    // Centered Search Box with macOS HIG styling & high contrast
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(Color.white.opacity(0.68))
                            .font(.system(size: 13, weight: .medium))
                        
                        ZStack(alignment: .leading) {
                            if vm.searchQuery.isEmpty {
                                Text("Tìm kiếm trên YouTube...")
                                    .foregroundColor(Color.white.opacity(0.48))
                                    .font(.system(size: 13))
                                    .allowsHitTesting(false)
                            }
                            
                            TextField("", text: $vm.searchQuery)
                                .textFieldStyle(.plain)
                                .foregroundColor(.white)
                                .font(.system(size: 13))
                                .onSubmit { performSearch() }
                        }
                        
                        if !vm.searchQuery.isEmpty {
                            Button(action: {
                                vm.searchQuery = ""
                                if vm.isSearching {
                                    vm.isSearching = false
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(Color.white.opacity(0.65))
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(width: 440, height: 32)
                    .liquidGlassSearchBar()
                    
                    // Left Controls: Traffic Lights + Brand + Navigation
                    HStack(spacing: 0) {
                        HStack(spacing: 10) {
                            MacTrafficLightsView()
                                .padding(.leading, 14)
                            
                            YouTubeBrandBadge(width: 20)
                            
                            HStack(alignment: .center, spacing: 3) {
                                Text("AuraTube")
                                    .font(.system(size: 13.5, weight: .bold))
                                    .foregroundColor(.white)
                                    .tracking(-0.3)
                                    .lineLimit(1)
                                    .fixedSize()
                                
                                Text("VN")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(Color.white.opacity(0.60))
                                    .offset(y: -4)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            
                            Spacer()
                        }
                        .frame(width: 220, height: 52, alignment: .leading)
                        
                        // Vertical Separator
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 0.75, height: 20)
                        
                        // Navigation Controls (Back / Forward)
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
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(canGoBack ? .white : Color.white.opacity(0.28))
                                    .frame(width: 28, height: 28)
                                    .background(Color.white.opacity(canGoBack ? 0.08 : 0.03))
                                    .clipShape(Circle())
                                    .overlay(Circle().strokeBorder(Color.white.opacity(canGoBack ? 0.20 : 0.06), lineWidth: 0.75))
                            }
                            .buttonStyle(.plain)
                            .disabled(!canGoBack)
                            .help(canGoBack ? "Quay lại" : "")
                            
                            Button(action: {}) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.20))
                                    .frame(width: 28, height: 28)
                                    .background(Color.white.opacity(0.02))
                                    .clipShape(Circle())
                                    .overlay(Circle().strokeBorder(Color.white.opacity(0.05), lineWidth: 0.75))
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
                                        .fill(Color.white.opacity(0.06))
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
                                    SpinningRefreshIcon(isSpinning: updateService.isScanning, size: 11)
                                        .foregroundColor(Color.white.opacity(0.85))
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
                                        .fill(Color.white.opacity(0.06))
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 12.5))
                                        .foregroundColor(Color.white.opacity(0.85))
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
                .fill(Color.white.opacity(0.08))
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
                        }
                    }
                    
                    Spacer()
                    
                    // Sidebar Footer: Version & Scan Card with Liquid Glass
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: { AppDelegate.showStandardAboutPanel() }) {
                            HStack(spacing: 6) {
                                Text("AuraTube v\(updateService.currentVersion)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.75))
                                
                                Image(systemName: "info.circle")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color.white.opacity(0.40))
                                
                                if updateService.isUpdateAvailable {
                                    Circle()
                                        .fill(Color.cyan)
                                        .frame(width: 5.5, height: 5.5)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Xem thông tin ứng dụng AuraTube")
                        
                        LiquidGlassButton(
                            action: { updateService.scanForUpdates(isUserInitiated: true) },
                            cornerRadius: 7,
                            isProminent: updateService.isUpdateAvailable
                        ) {
                            HStack(spacing: 5) {
                                SpinningRefreshIcon(isSpinning: updateService.isScanning, size: 10)
                                Text(updateService.isScanning ? "Đang quét..." : (updateService.isUpdateAvailable ? "Có bản mới!" : "Quét cập nhật"))
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(updateService.isUpdateAvailable ? .white : Color.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                        }
                        
                        Text("© 2026 AuraTube • macOS")
                            .font(.system(size: 9.5))
                            .foregroundColor(Color.white.opacity(0.35))
                    }
                    .padding(10)
                    .liquidGlass(cornerRadius: 10, elevation: 2)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 16)
                }
                .padding(.top, 14)
                .frame(width: 220)
                .background(
                    ZStack {
                        Color(red: 0.13, green: 0.13, blue: 0.14)
                        VisualEffectBackground(material: .sidebar, blendingMode: .withinWindow)
                    }
                )
                
                // Vertical Content Divider with subtle specular reflection
                Rectangle()
                    .fill(Color.white.opacity(0.06))
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
                        Color(red: 0.09, green: 0.09, blue: 0.10).ignoresSafeArea()
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
                    // Search Results Grid
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Kết quả tìm kiếm cho: \"\(vm.searchQuery)\"")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.top, 16)
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 380), spacing: 20)], spacing: 28) {
                                ForEach(vm.searchResults) { v in
                                    VideoCardView(video: v) { playVideo(v) }
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                        .padding(.bottom, 40)
                    }
                } else {
                    switch vm.selectedSection {
                    case .home:
                        HomeView(onSelectVideo: { playVideo($0) })
                    case .bookmarks:
                        BookmarkListView(onSelectVideo: { playVideo($0) })
                    case .history:
                        HistoryListView(onSelectVideo: { playVideo($0) })
                    case .downloads:
                        DownloadListView()
                    }
                }
                
                // Picture-in-Picture (PiP) Floating Mini-Player at bottom right corner
                if !playerManager.isVideoFullscreen, vm.watchingVideo == nil, let activeVideo = playerManager.currentVideo {
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
                Color(red: 0.09, green: 0.09, blue: 0.10)
            }
        }
    )
    .overlay(alignment: .top) {
        if let feedback = updateService.scanFeedbackMessage {
            ScanFeedbackToast(message: feedback)
                .padding(.top, 58)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(300)
        }
    }
    .background(
        WindowAccessor { window in
            AppDelegate.configureTitlebar(for: window)
        }
    )
    .onChange(of: playerManager.isVideoFullscreen) { isFS in
        if isFS, vm.watchingVideo == nil, let active = playerManager.currentVideo {
            vm.watchingVideo = active
        }
    }
    .onChange(of: playerManager.currentVideo?.id) { _ in
        if let active = playerManager.currentVideo, vm.watchingVideo?.id != active.id {
            vm.watchingVideo = active
        }
    }
    .sheet(isPresented: $updateService.showUpdateSheet) {
        UpdateSheetView()
    }
}
    
    private func playVideo(_ video: Video) {
        vm.watchingVideo = video
        playerManager.loadAndPlay(video: video)
    }
    
    private func performSearch() {
        guard !vm.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        vm.isSearching = true
        vm.watchingVideo = nil
        Task {
            vm.searchResults = await YTDLPService.shared.searchVideos(query: vm.searchQuery)
        }
    }
}

// MARK: - Bookmarks List View
struct BookmarkListView: View {
    @ObservedObject private var playerManager = PlayerManager.shared
    let onSelectVideo: (Video) -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Danh sách Xem sau (Bookmarks)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                
                if playerManager.bookmarkedVideos.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 32))
                            .foregroundColor(Color(white: 0.4))
                        Text("Chưa có video nào trong danh sách Xem sau")
                            .foregroundColor(Color(white: 0.6))
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
    @ObservedObject private var playerManager = PlayerManager.shared
    let onSelectVideo: (Video) -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Video đã xem gần đây")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                
                if playerManager.historyVideos.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 32))
                            .foregroundColor(Color(white: 0.4))
                        Text("Lịch sử xem đang trống")
                            .foregroundColor(Color(white: 0.6))
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
    @ObservedObject private var downloadManager = DownloadManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Tệp tải về")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { downloadManager.openDownloadFolder() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        Text("Mở thư mục trong Finder")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(8)
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            if downloadManager.downloads.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 32))
                        .foregroundColor(Color(white: 0.4))
                    Text("Chưa có tác vụ tải về nào")
                        .foregroundColor(Color(white: 0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(downloadManager.downloads) { item in
                    HStack(spacing: 14) {
                        Image(systemName: item.isComplete ? "checkmark.circle.fill" : "arrow.down.circle")
                            .foregroundColor(item.isComplete ? .green : .white)
                            .font(.system(size: 18))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            HStack {
                                Text(item.quality)
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(white: 0.6))
                                Text("•")
                                    .foregroundColor(Color(white: 0.4))
                                Text(item.statusText)
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(white: 0.7))
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
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green)
                .font(.system(size: 13, weight: .bold))
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .liquidGlassCapsule(elevation: 8)
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

