import SwiftUI
import AppKit
import WebKit

@MainActor
final class NativeShortsViewModel: ObservableObject {
    @Published var shorts: [Video] = []
    @Published var currentIndex: Int = 0
    @Published var isLoading: Bool = false
    @Published var continuationToken: String? = nil
    @Published var likedShorts: Set<String> = []
    @Published var dislikedShorts: Set<String> = []
    @Published var toastMessage: String? = nil
    @Published var isAutoScrollEnabled: Bool = false
    @Published var isCommentsOpen: Bool = false
    
    private let queryPool = [
        "#shorts việt nam",
        "#shorts trending",
        "#shorts hài hước",
        "#shorts ca nhạc",
        "#shorts khám phá"
    ]
    private var poolIndex = 0
    private var snapSettleTask: Task<Void, Never>? = nil
    private var eventMonitor: Any? = nil
    private var lastScrollDate: Date = Date()
    private var accumulatedDeltaY: CGFloat = 0
    private var lastAutoScrolledId: String = ""
    
    func openShort(_ video: Video, proxy: ScrollViewProxy? = nil) {
        if let idx = shorts.firstIndex(where: { $0.id == video.id }) {
            currentIndex = idx
            playCurrentShort()
            if let p = proxy {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    p.scrollTo(video.id, anchor: .center)
                }
            }
        } else {
            shorts.insert(video, at: 0)
            currentIndex = 0
            playCurrentShort()
            if let p = proxy {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    p.scrollTo(video.id, anchor: .center)
                }
            }
            if shorts.count <= 2 {
                Task {
                    let related = await YTDLPService.shared.searchVideos(query: "#shorts " + video.uploader, limit: 12)
                    let newShorts = related.filter { s in !self.shorts.contains(where: { $0.id == s.id }) }
                    self.shorts.append(contentsOf: newShorts)
                    if self.shorts.count < 5 {
                        await self.loadMoreShorts()
                    }
                }
            }
        }
    }
    
    func loadInitialShorts(preferredInitial: Video? = nil) async {
        if let initial = preferredInitial, shorts.isEmpty {
            shorts = [initial]
            currentIndex = 0
            playCurrentShort()
        }
        guard shorts.count <= 1 else { return }
        isLoading = true
        
        let result = await YTDLPService.shared.searchVideosWithContinuation(query: "#shorts việt nam")
        var loaded = result.shorts
        if loaded.isEmpty {
            loaded = result.videos.filter { ($0.duration ?? 0) <= 65 }
        }
        if loaded.isEmpty {
            loaded = await YTDLPService.shared.searchVideos(query: "#shorts trending", limit: 20)
        }
        
        let existingIds = Set(self.shorts.map { $0.id })
        let filtered = loaded.filter { !existingIds.contains($0.id) }
        self.shorts.append(contentsOf: filtered)
        self.continuationToken = result.continuationToken
        self.isLoading = false
        
        if self.currentIndex == 0 && preferredInitial == nil, !self.shorts.isEmpty {
            playCurrentShort()
        }
    }
    
    func loadMoreShorts() async {
        guard !isLoading else { return }
        isLoading = true
        
        var newShorts: [Video] = []
        if let token = continuationToken {
            let res = await YTDLPService.shared.searchVideosWithContinuation(query: "#shorts việt nam", continuationToken: token)
            newShorts = res.shorts.isEmpty ? res.videos.filter { ($0.duration ?? 0) <= 65 } : res.shorts
            self.continuationToken = res.continuationToken
        }
        
        if newShorts.isEmpty {
            poolIndex = (poolIndex + 1) % queryPool.count
            let fallbackQuery = queryPool[poolIndex]
            newShorts = await YTDLPService.shared.searchVideos(query: fallbackQuery, limit: 16)
        }
        
        let existingIds = Set(self.shorts.map { $0.id })
        let filtered = newShorts.filter { !existingIds.contains($0.id) }
        self.shorts.append(contentsOf: filtered)
        self.isLoading = false
    }
    
    // MARK: - Ultra-responsive Mouse Wheel & Trackpad Magnetic Snap (YouTube Shorts Engine)
    
    func startScrollMonitor(proxy: ScrollViewProxy) {
        guard eventMonitor == nil else { return }
        
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self else { return event }
            guard let window = event.window, window.isKeyWindow else { return event }
            
            // Allow normal scrolling when mouse is over sidebar (left 220pt)
            if event.locationInWindow.x <= 220 {
                return event
            }
            
            // Allow normal scrolling when mouse is over comments drawer
            if self.isCommentsOpen {
                let drawerWidth: CGFloat = min(390, max(300, window.frame.width * 0.35))
                if event.locationInWindow.x >= (window.frame.width - drawerWidth) {
                    return event
                }
            }
            
            // Absorb momentum after fingers lift off trackpad (prevents coasting and stopping midway)
            if event.momentumPhase != [] {
                return nil
            }
            
            // Reset accumulator when trackpad gesture ends or trigger if accumulated enough
            if event.phase == .ended || event.phase == .cancelled {
                if abs(self.accumulatedDeltaY) >= 5 {
                    let isDown = self.accumulatedDeltaY < 0
                    self.accumulatedDeltaY = 0
                    self.lastScrollDate = Date()
                    if isDown {
                        self.goToNext(proxy: proxy)
                    } else {
                        self.goToPrev(proxy: proxy)
                    }
                } else {
                    self.accumulatedDeltaY = 0
                }
                return nil
            }
            
            let rawDelta = event.scrollingDeltaY
            guard abs(rawDelta) > 0.05 else { return nil }
            
            // Normalize mouse wheel vs trackpad deltas
            let scaledDelta: CGFloat = event.hasPreciseScrollingDeltas ? rawDelta : (rawDelta * 22.0)
            
            let now = Date()
            if now.timeIntervalSince(self.lastScrollDate) < 0.24 {
                // Cooldown between transitions - absorb event
                return nil
            }
            
            self.accumulatedDeltaY += scaledDelta
            
            // Magnetic Snap Trigger: single wheel click or short trackpad flick
            if abs(self.accumulatedDeltaY) >= 10 {
                let isDown = self.accumulatedDeltaY < 0
                self.accumulatedDeltaY = 0
                self.lastScrollDate = now
                
                if isDown {
                    self.goToNext(proxy: proxy)
                } else {
                    self.goToPrev(proxy: proxy)
                }
            }
            
            // Consume scroll wheel event completely so NSScrollView never free-scrolls or stops midway
            return nil
        }
    }
    
    func stopScrollMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    func goToNext(proxy: ScrollViewProxy) {
        guard currentIndex < shorts.count - 1 else { return }
        let nextIndex = currentIndex + 1
        
        // Snappy, crisp interactive spring animation
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
            proxy.scrollTo(shorts[nextIndex].id, anchor: .center)
        }
        
        self.currentIndex = nextIndex
        self.playCurrentShort()
        
        if nextIndex >= self.shorts.count - 4 {
            Task { await self.loadMoreShorts() }
        }
    }
    
    func goToPrev(proxy: ScrollViewProxy) {
        guard currentIndex > 0 else { return }
        let prevIndex = currentIndex - 1
        
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
            proxy.scrollTo(shorts[prevIndex].id, anchor: .center)
        }
        
        self.currentIndex = prevIndex
        self.playCurrentShort()
    }
    
    func snapToCard(index: Int, proxy: ScrollViewProxy) {
        guard index >= 0 && index < shorts.count, index != currentIndex else { return }
        
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
            proxy.scrollTo(shorts[index].id, anchor: .center)
        }
        
        self.currentIndex = index
        self.playCurrentShort()
    }
    
    // MARK: - Auto Scroll Engine
    
    func toggleAutoScroll() {
        isAutoScrollEnabled.toggle()
        showToast(isAutoScrollEnabled ? "🔄 Đã BẬT Tự động cuộn Shorts" : "⏸ Đã TẮT Tự động cuộn")
    }
    
    var currentShort: Video? {
        guard currentIndex >= 0 && currentIndex < shorts.count else { return nil }
        return shorts[currentIndex]
    }
    
    func toggleComments() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            isCommentsOpen.toggle()
        }
        if isCommentsOpen {
            if let current = currentShort {
                if PlayerManager.shared.currentVideo?.id != current.id {
                    PlayerManager.shared.loadAndPlay(video: current)
                } else if PlayerManager.shared.comments.isEmpty && !PlayerManager.shared.isLoadingComments {
                    PlayerManager.shared.startLoadingComments(for: current.id)
                }
            }
        }
    }
    
    func checkAutoScroll(currentTime: Double, duration: Double, proxy: ScrollViewProxy) {
        guard isAutoScrollEnabled, duration > 3.0, currentIndex < shorts.count - 1 else { return }
        let currentShort = shorts[currentIndex]
        
        // When current video finishes playing (within 0.6s of duration)
        if currentTime >= (duration - 0.6) {
            if lastAutoScrolledId != currentShort.id {
                lastAutoScrolledId = currentShort.id
                goToNext(proxy: proxy)
            }
        }
    }
    
    func playCurrentShort() {
        guard currentIndex >= 0 && currentIndex < shorts.count else { return }
        let current = shorts[currentIndex]
        ShortsPlaybackCoordinator.shared.activateOnly(videoId: current.id)
        playShort(current)
        
        let targetId = current.id
        let targetIdx = currentIndex
        if current.uploader == "YouTube Shorts" || current.uploader == "YouTube Creator" || current.uploader.isEmpty {
            Task {
                if let realAuthor = await YTDLPService.shared.fetchOEmbedAuthor(videoId: targetId) {
                    if targetIdx < self.shorts.count && self.shorts[targetIdx].id == targetId {
                        self.shorts[targetIdx].uploader = realAuthor
                    }
                    if PlayerManager.shared.currentVideo?.id == targetId {
                        PlayerManager.shared.currentVideo?.uploader = realAuthor
                    }
                }
            }
        }
    }
    
    private func playShort(_ video: Video) {
        PlayerManager.shared.currentVideo = video
        PlayerManager.shared.duration = video.totalDurationSeconds
        PlayerManager.shared.currentTime = 0
        PlayerManager.shared.isPlaying = true
        PlayerManager.shared.onPlayPause?(true)
        PlayerManager.shared.addToHistory(video)
        PlayerManager.shared.startLoadingComments(for: video.id)
    }
    
    func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }
}

public struct NativeShortsFeedView: View {
    @Binding var selectedShort: Video?
    var onSelectVideo: (Video) -> Void
    
    @StateObject private var vm = NativeShortsViewModel()
    @ObservedObject private var subManager = ChannelSubscriptionManager.shared
    @ObservedObject private var playerManager = PlayerManager.shared
    
    public init(selectedShort: Binding<Video?> = .constant(nil), onSelectVideo: @escaping (Video) -> Void) {
        self._selectedShort = selectedShort
        self.onSelectVideo = onSelectVideo
    }
    
    public var body: some View {
        GeometryReader { containerGeo in
            let containerWidth = containerGeo.size.width
            let containerHeight = containerGeo.size.height
            
            // Dynamic responsive video sizing to fit cleanly within available window height
            let cardHeight: CGFloat = max(420, min(675, containerHeight - 56))
            let cardWidth: CGFloat = cardHeight * (9.0 / 16.0)
            let commentsDrawerWidth: CGFloat = min(390, max(300, containerWidth * 0.35))
            
            ZStack {
                Color(white: 0.07).ignoresSafeArea()
                
                if vm.isLoading && vm.shorts.isEmpty {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Đang tải YouTube Shorts...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(white: 0.65))
                    }
                } else if vm.shorts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "play.square.stack")
                            .font(.system(size: 40))
                            .foregroundColor(Color(white: 0.4))
                        Text("Không tìm thấy Shorts nào")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(white: 0.7))
                        Button("Thử lại") {
                            Task { await vm.loadInitialShorts() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    // Two-Column Layout: Video Feed Column + Comments Drawer Column
                    HStack(spacing: 0) {
                        // Column 1: Video Feed (Always perfectly centered within available width)
                        ScrollViewReader { proxy in
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVStack(spacing: 32) {
                                    ForEach(Array(vm.shorts.enumerated()), id: \.element.id) { index, short in
                                        let isActive = (index == vm.currentIndex)
                                        
                                        ShortFeedRowView(
                                            short: short,
                                            index: index,
                                            totalCount: vm.shorts.count,
                                            isActive: isActive,
                                            cardWidth: cardWidth,
                                            cardHeight: cardHeight,
                                            isAutoScrollEnabled: vm.isAutoScrollEnabled,
                                            subManager: subManager,
                                            playerManager: playerManager,
                                            vm: vm,
                                            onSelectVideo: onSelectVideo,
                                            onGoPrev: { vm.goToPrev(proxy: proxy) },
                                            onGoNext: { vm.goToNext(proxy: proxy) },
                                            onTapCard: {
                                                if !isActive {
                                                    vm.snapToCard(index: index, proxy: proxy)
                                                }
                                            }
                                        )
                                        .id(short.id)
                                    }
                                }
                                .padding(.vertical, max(20, (containerHeight - cardHeight) / 2))
                                .frame(maxWidth: .infinity)
                            }
                            .onAppear {
                                vm.startScrollMonitor(proxy: proxy)
                                if !vm.shorts.isEmpty && vm.currentIndex < vm.shorts.count {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        proxy.scrollTo(vm.shorts[vm.currentIndex].id, anchor: .center)
                                    }
                                }
                            }
                            .onDisappear {
                                vm.stopScrollMonitor()
                            }
                            .onChange(of: containerHeight) { _ in
                                if !vm.shorts.isEmpty && vm.currentIndex < vm.shorts.count {
                                    proxy.scrollTo(vm.shorts[vm.currentIndex].id, anchor: .center)
                                }
                            }
                            .onChange(of: vm.shorts.count) { count in
                                if count > 0 && vm.currentIndex < vm.shorts.count {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        proxy.scrollTo(vm.shorts[vm.currentIndex].id, anchor: .center)
                                    }
                                }
                            }
                            .onChange(of: playerManager.currentTime) { curTime in
                                vm.checkAutoScroll(
                                    currentTime: curTime,
                                    duration: playerManager.duration,
                                    proxy: proxy
                                )
                            }
                            .overlay(
                                // Hidden keyboard shortcuts for Up / Down arrows, Auto-Scroll & Comments
                                Group {
                                    Button("") { vm.goToNext(proxy: proxy) }
                                        .keyboardShortcut(.downArrow, modifiers: [])
                                        .opacity(0)
                                    Button("") { vm.goToPrev(proxy: proxy) }
                                        .keyboardShortcut(.upArrow, modifiers: [])
                                        .opacity(0)
                                    Button("") { vm.toggleAutoScroll() }
                                        .keyboardShortcut("a", modifiers: [])
                                        .opacity(0)
                                    Button("") { vm.toggleComments() }
                                        .keyboardShortcut("c", modifiers: [])
                                        .opacity(0)
                                    if vm.isCommentsOpen {
                                        Button("") { vm.toggleComments() }
                                            .keyboardShortcut(.escape, modifiers: [])
                                            .opacity(0)
                                    }
                                }
                                .frame(width: 0, height: 0)
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        // Column 2: Comments Drawer (Positioned alongside video - Zero overlap)
                        if vm.isCommentsOpen {
                            ShortsCommentsDrawer(
                                playerManager: playerManager,
                                onClose: { vm.toggleComments() }
                            )
                            .frame(width: commentsDrawerWidth)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.38, dampingFraction: 0.85), value: vm.isCommentsOpen)
                    
                    // Top Header Quick Action Dock: Auto Scroll Switch (Pinned cleanly to top right)
                    VStack {
                        HStack {
                            Spacer()
                            
                            Button(action: { vm.toggleAutoScroll() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: vm.isAutoScrollEnabled ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(vm.isAutoScrollEnabled ? .green : Color.white.opacity(0.8))
                                    Text(vm.isAutoScrollEnabled ? "Tự động cuộn: BẬT" : "Tự động cuộn")
                                        .font(.system(size: 12, weight: vm.isAutoScrollEnabled ? .bold : .medium))
                                        .foregroundColor(vm.isAutoScrollEnabled ? .white : Color.white.opacity(0.85))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(vm.isAutoScrollEnabled ? Color.green.opacity(0.28) : Color.black.opacity(0.65))
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(vm.isAutoScrollEnabled ? Color.green.opacity(0.7) : Color.white.opacity(0.18), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.35), radius: 6, y: 2)
                            }
                            .buttonStyle(.plain)
                            .help("Bật/Tắt tự động chuyển sang video tiếp theo khi xem xong (Phím tắt: A)")
                            .padding(.trailing, vm.isCommentsOpen ? (commentsDrawerWidth + 20) : 24)
                            .padding(.top, 16)
                            .animation(.spring(response: 0.38, dampingFraction: 0.85), value: vm.isCommentsOpen)
                        }
                        Spacer()
                    }
                }
                
                // Toast Notification Overlay
                if let toast = vm.toastMessage {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color(white: 0.16).opacity(0.95))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 4)
                            .padding(.bottom, 28)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .onAppear {
            if PlayerManager.shared.currentVideo != nil && PlayerManager.shared.isPlaying {
                PlayerManager.shared.pause()
            }
            if let initial = selectedShort {
                vm.openShort(initial)
            }
        }
        .onDisappear {
            vm.stopScrollMonitor()
            ShortsPlaybackCoordinator.shared.silenceAll()
        }
        .onChange(of: selectedShort) { newShort in
            if let s = newShort {
                vm.openShort(s)
            }
        }
        .task {
            await vm.loadInitialShorts(preferredInitial: selectedShort)
        }
    }
}

// MARK: - Centralized Shorts Playback & Audio Coordinator (Eliminates Audio Overlap)
@MainActor
final class ShortsPlaybackCoordinator {
    static let shared = ShortsPlaybackCoordinator()
    
    private var registeredWebViews: [String: ScrollForwardingWKWebView] = [:]
    
    private init() {}
    
    func register(videoId: String, webView: ScrollForwardingWKWebView) {
        registeredWebViews[videoId] = webView
    }
    
    func unregister(videoId: String) {
        if let webView = registeredWebViews.removeValue(forKey: videoId) {
            silenceWebView(webView)
        }
    }
    
    func activateOnly(videoId: String) {
        for (id, webView) in registeredWebViews {
            if id != videoId {
                silenceWebView(webView)
            }
        }
        
        // Also ensure regular player in PlayerManager doesn't clash with Shorts audio
        if let cur = PlayerManager.shared.currentVideo, cur.id != videoId, PlayerManager.shared.isPlaying {
            PlayerManager.shared.pause()
        }
    }
    
    func silenceWebView(_ webView: WKWebView) {
        let js = """
        try {
            isActive = false;
            isPreload = true;
            var ifr = document.getElementById('ytPlayer');
            if (ifr && ifr.contentWindow) {
                ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "pauseVideo", args: []}), '*');
                ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "mute", args: []}), '*');
            }
            var vids = document.querySelectorAll('video');
            for (var i = 0; i < vids.length; i++) {
                vids[i].pause();
                vids[i].muted = true;
            }
        } catch(e) {}
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    
    func silenceAll() {
        for (_, webView) in registeredWebViews {
            silenceWebView(webView)
        }
    }
}

// MARK: - Dedicated Preloading Shorts Card Player (0s latency instant playback)
struct ShortsCardPlayerView: NSViewRepresentable {
    let videoId: String
    let isActive: Bool
    let isPreload: Bool
    @ObservedObject var playerManager: PlayerManager = .shared
    
    static let cleanShortsScriptSource: String = """
    (function() {
        var css = `
            .ytp-shorts-player-overlay,
            .ytp-shorts-title,
            .ytp-shorts-channel-name,
            .ytp-shorts-channel-avatar,
            .ytp-shorts-subscribe-button,
            .ytp-shorts-like-button,
            .ytp-shorts-dislike-button,
            .ytp-shorts-share-button,
            .ytp-modern-title,
            .ytp-modern-title-channel,
            .ytp-chrome-top,
            .ytp-chrome-bottom,
            .ytp-gradient-top,
            .ytp-gradient-bottom,
            .ytp-title,
            .ytp-title-channel,
            .ytp-title-channel-logo,
            .ytp-title-text,
            .ytp-title-subtext,
            .ytp-title-link,
            .ytp-show-cards-title,
            .ytp-watermark,
            .ytp-pause-overlay,
            .ytp-large-play-button,
            .ytp-play-button,
            .ytp-bezel,
            .ytp-bezel-container,
            .ytp-bezel-icon,
            .ytp-bezel-text,
            [class*="bezel"],
            [class*="pause-overlay"],
            [class*="play-button"],
            [aria-label="Pause"],
            [aria-label="Tạm dừng"],
            .ytp-cairo-refresh-signature-moments,
            .ytp-unmute,
            .ytp-volume-control,
            .annotation,
            .iv-branding,
            [class*="shorts-player"],
            [class*="shorts-overlay"],
            [class*="shorts-title"],
            [class*="shorts-channel"],
            [class*="shorts-metadata"],
            [class*="channel-name"],
            [class*="channel-avatar"],
            [class*="channel-logo"],
            [class*="title-channel"],
            [class*="paid-content"],
            [class*="paid-promotion"] {
                display: none !important;
                opacity: 0 !important;
                visibility: hidden !important;
                pointer-events: none !important;
                width: 0 !important;
                height: 0 !important;
                max-width: 0 !important;
                max-height: 0 !important;
                position: absolute !important;
                left: -9999px !important;
                top: -9999px !important;
            }
        `;

        function applyShortsStyles() {
            try {
                if (!document.getElementById('__auratube_shorts_styles')) {
                    var s = document.createElement('style');
                    s.id = '__auratube_shorts_styles';
                    s.textContent = css;
                    (document.head || document.documentElement).appendChild(s);
                }
                var targets = document.querySelectorAll(
                    '.ytp-shorts-player-overlay, .ytp-shorts-title, .ytp-shorts-channel-name, ' +
                    '.ytp-shorts-channel-avatar, .ytp-modern-title, .ytp-chrome-top, .ytp-gradient-top, ' +
                    '.ytp-gradient-bottom, .ytp-title, .ytp-title-channel, .ytp-watermark, ' +
                    '.ytp-bezel, .ytp-bezel-container, .ytp-bezel-icon, .ytp-bezel-text, [class*="bezel"], ' +
                    '[class*="shorts-player"], [class*="shorts-overlay"], [class*="title-channel"], ' +
                    '[class*="channel-avatar"], [class*="channel-name"]'
                );
                for (var i = 0; i < targets.length; i++) {
                    targets[i].remove();
                }
            } catch(e) {}
        }

        applyShortsStyles();
        document.addEventListener('DOMContentLoaded', applyShortsStyles);
        window.addEventListener('load', applyShortsStyles);
        setInterval(applyShortsStyles, 200);
    })();
    """
    
    init(videoId: String, isActive: Bool, isPreload: Bool) {
        self.videoId = videoId
        self.isActive = isActive
        self.isPreload = isPreload
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(videoId: videoId, isActive: isActive, isPreload: isPreload)
    }
    
    func makeNSView(context: Context) -> ScrollForwardingWKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.preferences.setValue(true, forKey: "fullScreenEnabled")
        
        config.setValue(false, forKey: "requiresUserActionForAudioPlayback")
        config.setValue(false, forKey: "requiresUserActionForVideoPlayback")
        config.setValue(true, forKey: "mainContentUserGestureOverrideEnabled")
        config.setValue(false, forKey: "invisibleAutoplayNotPermitted")
        
        let pref = config.preferences
        pref.setValue(false, forKey: "requiresUserGestureForAudioPlayback")
        pref.setValue(false, forKey: "requiresUserGestureForVideoPlayback")
        pref.setValue(true, forKey: "mainContentUserGestureOverrideEnabled")
        pref.setValue(false, forKey: "invisibleMediaAutoplayNotPermitted")
        
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, contentWorld: .page, name: "playerBridge")
        contentController.add(context.coordinator, contentWorld: .defaultClient, name: "playerBridge")
        
        // Inject shorts cleanup scripts directly at document start into both worlds
        let shortsScript = WKUserScript(source: ShortsCardPlayerView.cleanShortsScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)
        contentController.addUserScript(shortsScript)
        
        let clientShortsScript = WKUserScript(source: ShortsCardPlayerView.cleanShortsScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient)
        contentController.addUserScript(clientShortsScript)
        
        let cleanScript = NativePlayerView.cleanScriptSource
        let userScript = WKUserScript(source: cleanScript, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)
        contentController.addUserScript(userScript)
        config.userContentController = contentController
        
        let webView = ScrollForwardingWKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.targetWebView = webView
        
        let mute = isPreload || playerManager.isMuted
        let html = ShortsCardPlayerView.generateHTML(videoId: videoId, isPreload: isPreload, isMuted: mute)
        webView.loadHTMLString(html, baseURL: URL(string: "https://auratube.app"))
        
        ShortsPlaybackCoordinator.shared.register(videoId: videoId, webView: webView)
        if isActive {
            setupActiveBindings(context: context)
            ShortsPlaybackCoordinator.shared.activateOnly(videoId: videoId)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak coord = context.coordinator] in
                guard let coord = coord, coord.isActive else { return }
                coord.startActivePlayback()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak coord = context.coordinator] in
                guard let coord = coord, coord.isActive else { return }
                coord.startActivePlayback()
            }
        }
        
        return webView
    }
    
    func updateNSView(_ nsView: ScrollForwardingWKWebView, context: Context) {
        let wasActive = context.coordinator.isActive
        context.coordinator.isActive = isActive
        context.coordinator.isPreload = isPreload
        
        ShortsPlaybackCoordinator.shared.register(videoId: videoId, webView: nsView)
        
        if isActive {
            setupActiveBindings(context: context)
            ShortsPlaybackCoordinator.shared.activateOnly(videoId: videoId)
            if !wasActive || !context.coordinator.hasStartedPlayback {
                context.coordinator.startActivePlayback()
            }
        } else if wasActive && !isActive {
            context.coordinator.pausePlayback()
        }
    }
    
    @MainActor
    static func dismantleNSView(_ nsView: ScrollForwardingWKWebView, coordinator: Coordinator) {
        ShortsPlaybackCoordinator.shared.unregister(videoId: coordinator.videoId)
        coordinator.pausePlayback()
        ShortsPlaybackCoordinator.shared.silenceWebView(nsView)
        nsView.stopLoading()
        nsView.loadHTMLString("<!DOCTYPE html><html><body></body></html>", baseURL: nil)
    }
    
    private func setupActiveBindings(context: Context) {
        playerManager.onPlayPause = { [weak coord = context.coordinator] shouldPlay in
            if shouldPlay {
                coord?.startActivePlayback()
            } else {
                coord?.pausePlayback()
            }
        }
        playerManager.onVolumeChange = { [weak coord = context.coordinator] vol in
            coord?.setVolume(vol)
        }
    }
    
    static func generateHTML(videoId: String, isPreload: Bool, isMuted: Bool) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <meta name="referrer" content="origin">
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; overflow: hidden; }
          html, body { width: 100%; height: 100%; background: transparent !important; }
          #ytPlayer, iframe { width: 100% !important; height: 100% !important; border: none; display: block; }
          .ytp-shorts-player-overlay, .ytp-shorts-title, .ytp-shorts-channel-name, .ytp-modern-title, .ytp-suggested-action-badge, .ytp-popup, .ytp-ai-info-dialog, [class*="ai-disclosure"], .ytp-paid-content-overlay, [class*="paid-content"], [class*="paid-promotion"], .ytp-chrome-top, [class*="title-channel"], [class*="shorts"], .ytp-bezel, .ytp-bezel-container, .ytp-bezel-icon, .ytp-bezel-text, [class*="bezel"], .ytp-pause-overlay, .ytp-large-play-button, .ytp-large-play-button-red-bg, button.ytp-large-play-button, .ytp-play-button, [class*="pause-overlay"], [class*="play-button"], [aria-label*="Play" i], [aria-label*="Phát" i], [title*="Play" i], .ytp-impression-link, .ytp-title, .ytp-title-text, .ytp-title-channel, .ytp-title-channel-logo, .ytp-cairo-refresh-signature-moments { display: none !important; opacity: 0 !important; visibility: hidden !important; pointer-events: none !important; }
        </style>
        </head>
        <body>
        <iframe 
            id="ytPlayer"
            src="https://www.youtube.com/embed/\(videoId)?autoplay=1&mute=1&playsinline=1&controls=0&enablejsapi=1&rel=0&modestbranding=1&fs=0&iv_load_policy=3&showinfo=0&origin=https://auratube.app&widget_referrer=https://auratube.app" 
            allow="autoplay; encrypted-media; picture-in-picture; fullscreen" 
            allowfullscreen="true">
        </iframe>
        <script>
          var isPreload = \(isPreload ? "true" : "false");
          var isActive = \(isPreload ? "false" : "true");
          var currentVideoId = '\(videoId)';
          var hasFrozen = false;
          var isUserMuted = \(isMuted ? "true" : "false");

          function sendBridge(msg) {
            try {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                window.webkit.messageHandlers.playerBridge.postMessage(msg);
              }
            } catch(e) {}
          }

          function triggerPlayback() {
            var ifr = document.getElementById('ytPlayer');
            if (ifr && ifr.contentWindow) {
              ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "playVideo", args: []}), '*');
              if (!isUserMuted) {
                ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "unMute", args: []}), '*');
                ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setVolume", args: [100]}), '*');
              }
            }
          }

          function pingIframe() {
            var ifr = document.getElementById('ytPlayer');
            if (ifr && ifr.contentWindow) {
              try {
                ifr.contentWindow.postMessage(JSON.stringify({event: "listening"}), '*');
                if (isActive) {
                  triggerPlayback();
                }
              } catch(e) {}
            }
          }

          var ifr = document.getElementById('ytPlayer');
          if (ifr) {
            ifr.onload = function() {
              pingIframe();
              setTimeout(pingIframe, 150);
              setTimeout(pingIframe, 400);
              setTimeout(pingIframe, 900);
            };
          }

          var handshakeTimer = setInterval(function() {
            pingIframe();
          }, 350);

          window.addEventListener('message', function(e) {
            try {
              var data = JSON.parse(e.data);
              if (data.event === 'onReady') {
                if (isActive) {
                  triggerPlayback();
                }
              }
              if (data.event === 'infoDelivery' && data.info) {
                if (data.info.playerState === 1) {
                  clearInterval(handshakeTimer);
                }
                if (isPreload && !hasFrozen) {
                  if (data.info.playerState === 1 || (data.info.currentTime && data.info.currentTime > 0.01)) {
                    hasFrozen = true;
                    var ifr = document.getElementById('ytPlayer');
                    if (ifr && ifr.contentWindow) {
                      ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "pauseVideo", args: []}), '*');
                      ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "mute", args: []}), '*');
                    }
                    sendBridge({ type: 'preloadReady', videoId: currentVideoId });
                    return;
                  }
                }
                
                if (data.info.currentTime !== undefined) {
                  sendBridge({
                    type: 'timeUpdate',
                    videoId: currentVideoId,
                    currentTime: data.info.currentTime,
                    duration: data.info.duration || 0,
                    isPlaying: data.info.playerState === 1
                  });
                }
                if (data.info.playerState !== undefined) {
                  sendBridge({
                    type: 'stateChange',
                    videoId: currentVideoId,
                    isPlaying: data.info.playerState === 1
                  });
                }
              }
            } catch(err) {}
          });
        </script>
        </body>
        </html>
        """
    }
    
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var targetWebView: WKWebView?
        var isPreload: Bool
        var isActive: Bool
        var videoId: String
        var hasPreparedPreload: Bool = false
        var hasStartedPlayback: Bool = false
        
        init(videoId: String, isActive: Bool, isPreload: Bool) {
            self.videoId = videoId
            self.isActive = isActive
            self.isPreload = isPreload
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if isActive {
                startActivePlayback()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self, self.isActive else { return }
                    self.startActivePlayback()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    guard let self = self, self.isActive else { return }
                    self.startActivePlayback()
                }
            }
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            
            if isPreload {
                if let type = body["type"] as? String, type == "preloadReady" {
                    hasPreparedPreload = true
                }
                return
            }
            
            guard isActive else { return }
            
            if let type = body["type"] as? String {
                if type == "stateChange" {
                    if let playing = body["isPlaying"] as? Bool {
                        PlayerManager.shared.isPlaying = playing
                    }
                } else if type == "timeUpdate" {
                    if let cur = body["currentTime"] as? Double, !cur.isNaN {
                        let dur = body["duration"] as? Double ?? PlayerManager.shared.duration
                        let playing = body["isPlaying"] as? Bool ?? PlayerManager.shared.isPlaying
                        PlayerManager.shared.updatePlaybackSync(
                            currentTime: cur,
                            duration: dur,
                            isPlaying: playing,
                            isMuted: nil,
                            source: "shorts",
                            videoId: videoId
                        )
                    }
                }
            }
        }
        
        func startActivePlayback() {
            hasStartedPlayback = true
            let muteCmd = PlayerManager.shared.isMuted ? "mute" : "unMute"
            let js = """
            isActive = true;
            isPreload = false;
            isUserMuted = \(PlayerManager.shared.isMuted ? "true" : "false");
            function doPlay() {
                var ifr = document.getElementById('ytPlayer');
                if (ifr && ifr.contentWindow) {
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "playVideo", args: []}), '*');
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "\(muteCmd)", args: []}), '*');
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setVolume", args: [100]}), '*');
                }
            }
            doPlay();
            """
            targetWebView?.evaluateJavaScript(js, completionHandler: nil)
            
            // Fast follow-up at 120ms to ensure playback command applies
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self = self, self.isActive else { return }
                let retryJs = """
                var ifr = document.getElementById('ytPlayer');
                if (ifr && ifr.contentWindow) {
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "playVideo", args: []}), '*');
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "\(muteCmd)", args: []}), '*');
                }
                """
                self.targetWebView?.evaluateJavaScript(retryJs, completionHandler: nil)
            }
        }
        
        func pausePlayback() {
            let js = """
            isActive = false;
            isPreload = true;
            var ifr = document.getElementById('ytPlayer');
            if (ifr && ifr.contentWindow) {
                ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "pauseVideo", args: []}), '*');
                ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "mute", args: []}), '*');
            }
            """
            targetWebView?.evaluateJavaScript(js, completionHandler: nil)
        }
        
        func setVolume(_ volume: Double) {
            let pct = Int(volume * 100)
            let js = """
            var ifr = document.getElementById('ytPlayer');
            if (ifr && ifr.contentWindow) {
                ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setVolume", args: [\(pct)]}), '*');
            }
            """
            targetWebView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

// MARK: - Individual Short Feed Row (Card + Floating Action Dock)
struct ShortFeedRowView: View {
    let short: Video
    let index: Int
    let totalCount: Int
    let isActive: Bool
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let isAutoScrollEnabled: Bool
    @ObservedObject var subManager: ChannelSubscriptionManager
    @ObservedObject var playerManager: PlayerManager
    @ObservedObject var vm: NativeShortsViewModel
    let onSelectVideo: (Video) -> Void
    let onGoPrev: () -> Void
    let onGoNext: () -> Void
    let onTapCard: () -> Void
    
    var body: some View {
        let isPreloadNext = (index == vm.currentIndex + 1)
        let isPreloadPrev = (index == vm.currentIndex - 1)
        let isPlayerNeeded = isActive || isPreloadNext || isPreloadPrev
        
        return HStack(alignment: .bottom, spacing: 18) {
            // Main 9:16 Video Card
            ZStack(alignment: .bottom) {
                // Layer 1: Permanent High-Res Thumbnail (Always present underneath, guarantees 0% black screen)
                ZStack {
                    Color(white: 0.10)
                    AsyncImage(url: URL(string: short.thumbnail)) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            Color(white: 0.12)
                        }
                    }
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                
                // Layer 2: Preloaded & Active Video Player (0s latency instant playback)
                if isPlayerNeeded {
                    ShortsCardPlayerView(
                        videoId: short.id,
                        isActive: isActive,
                        isPreload: !isActive
                    )
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .opacity(isActive ? 1.0 : 0.0)
                }
                
                // Play indicator: ONLY shown when video is paused (to differentiate from lagging), never while playing
                let showPlayIndicator: Bool = {
                    if isActive {
                        // When video is active: show play icon ONLY when user has paused the video
                        return !playerManager.isPlaying
                    } else {
                        // When distant card: show play icon to indicate click to play
                        return !isPreloadNext && !isPreloadPrev
                    }
                }()
                
                if showPlayIndicator {
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 62, height: 62)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.white)
                                .offset(x: 2)
                        )
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.18), value: playerManager.isPlaying)
                }
                
                // Top Bar inside Video: Sound Mute Button
                if isActive {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: { playerManager.isMuted.toggle() }) {
                                Image(systemName: playerManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .padding([.top, .trailing], 14)
                        }
                        Spacer()
                    }
                    .frame(width: cardWidth, height: cardHeight)
                }
                
                // Bottom Overlay Metadata
                let uploaderDisplay: String = {
                    if isActive, let pCur = playerManager.currentVideo, pCur.id == short.id, !pCur.uploader.isEmpty, pCur.uploader != "YouTube Shorts", pCur.uploader != "YouTube Creator" {
                        return pCur.uploader
                    }
                    if !short.uploader.isEmpty, short.uploader != "YouTube Shorts", short.uploader != "YouTube Creator" {
                        return short.uploader
                    }
                    return "Kênh Shorts"
                }()
                
                VStack(alignment: .leading, spacing: 10) {
                    // Channel Info Row with real creator avatar
                    HStack(spacing: 10) {
                        if let avatar = short.channelAvatarUrl, let url = URL(string: avatar), !avatar.isEmpty {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img.resizable().scaledToFill()
                                } else {
                                    Circle()
                                        .fill(LinearGradient(colors: [Color.red.opacity(0.8), Color.purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .overlay(
                                            Text(String(uploaderDisplay.prefix(1)).uppercased())
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.white)
                                        )
                                }
                            }
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(LinearGradient(colors: [Color.red.opacity(0.8), Color.purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Text(String(uploaderDisplay.prefix(1)).uppercased())
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        }
                        
                        Text(uploaderDisplay)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        // Subscribe button (saved locally without login)
                        let isSub = subManager.isSubscribed(uploaderDisplay)
                        Button(action: {
                            subManager.toggleSubscription(
                                title: uploaderDisplay,
                                id: short.uploaderId,
                                avatarUrl: short.channelAvatarUrl
                            )
                            if isSub {
                                vm.showToast("Đã hủy lưu kênh: \(uploaderDisplay)")
                            } else {
                                vm.showToast("🔔 Đã lưu kênh: \(uploaderDisplay)")
                            }
                        }) {
                            HStack(spacing: 4) {
                                if isSub {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                Text(isSub ? "Đã đăng ký" : "Đăng ký")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(isSub ? .white : .black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(isSub ? Color.white.opacity(0.25) : Color.white)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Short Title
                    Text(short.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(Color(white: 0.95))
                        .lineLimit(2)
                        .lineSpacing(2)
                    
                    // Sound Row
                    HStack(spacing: 6) {
                        Image(systemName: "music.note")
                            .font(.system(size: 11))
                        Text("Âm thanh gốc - \(uploaderDisplay)")
                            .font(.system(size: 11.5))
                            .lineLimit(1)
                    }
                    .foregroundColor(Color.white.opacity(0.8))
                }
                .padding(16)
                .frame(width: cardWidth)
                .background(
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .frame(width: cardWidth, height: cardHeight)
            .contentShape(Rectangle())
            .onTapGesture {
                if !isActive {
                    onTapCard()
                } else {
                    playerManager.togglePlayPause()
                }
            }
            .shadow(color: Color.black.opacity(isActive ? 0.6 : 0.3), radius: isActive ? 24 : 12, x: 0, y: isActive ? 10 : 4)
            .scaleEffect(isActive ? 1.0 : 0.985)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isActive)
            
            // Right Side Action Buttons & Navigation Arrows (YouTube Web Layout)
            VStack(spacing: 14) {
                // Navigation Up Arrow
                Button(action: onGoPrev) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(index > 0 ? .white : Color(white: 0.3))
                        .frame(width: 44, height: 44)
                        .background(Color(white: 0.18).opacity(0.9))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(index <= 0)
                .help("Short trước (Mũi tên lên)")
                
                // Navigation Down Arrow
                Button(action: onGoNext) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(index < totalCount - 1 ? .white : Color(white: 0.3))
                        .frame(width: 44, height: 44)
                        .background(Color(white: 0.18).opacity(0.9))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(index >= totalCount - 1)
                .help("Short tiếp theo (Mũi tên xuống)")
                
                Spacer()
                
                // Like Button
                let isLiked = vm.likedShorts.contains(short.id)
                ActionButton(
                    icon: "hand.thumbsup.fill",
                    label: isLiked ? "Đã thích" : (short.viewCountFormatted.isEmpty ? "Thích" : short.viewCountFormatted),
                    isActive: isLiked,
                    activeColor: .red
                ) {
                    if isLiked {
                        vm.likedShorts.remove(short.id)
                    } else {
                        vm.likedShorts.insert(short.id)
                        vm.dislikedShorts.remove(short.id)
                        vm.showToast("👍 Đã thích Short!")
                    }
                }
                
                // Dislike Button
                let isDisliked = vm.dislikedShorts.contains(short.id)
                ActionButton(
                    icon: "hand.thumbsdown.fill",
                    label: "Không thích",
                    isActive: isDisliked,
                    activeColor: .gray
                ) {
                    if isDisliked {
                        vm.dislikedShorts.remove(short.id)
                    } else {
                        vm.dislikedShorts.insert(short.id)
                        vm.likedShorts.remove(short.id)
                    }
                }
                
                // Comments Button
                let commentCountText: String = {
                    if isActive {
                        if let total = playerManager.totalCommentsCountText, !total.isEmpty {
                            return total
                        } else if !playerManager.comments.isEmpty {
                            return "\(playerManager.comments.count)"
                        }
                    }
                    return "Bình luận"
                }()
                ActionButton(
                    icon: "ellipsis.bubble.fill",
                    label: commentCountText,
                    isActive: vm.isCommentsOpen && isActive,
                    activeColor: .cyan
                ) {
                    if !isActive {
                        onTapCard()
                    }
                    vm.toggleComments()
                }
                
                // Share Button
                ActionButton(
                    icon: "arrowshape.turn.up.right.fill",
                    label: "Chia sẻ",
                    isActive: false,
                    activeColor: .white
                ) {
                    let url = "https://www.youtube.com/shorts/\(short.id)"
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                    vm.showToast("🔗 Đã sao chép liên kết Short!")
                }
                
                // Full Player Button
                ActionButton(
                    icon: "arrow.up.left.and.arrow.down.right",
                    label: "Xem đủ",
                    isActive: false,
                    activeColor: .white
                ) {
                    onSelectVideo(short)
                }
            }
            .frame(width: 56)
            .padding(.bottom, 12)
        }
    }
}

private struct ActionButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isActive ? activeColor : .white)
                    .frame(width: 44, height: 44)
                    .background(Color(white: 0.18).opacity(0.9))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Color(white: 0.85))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shorts Comments Drawer & Rows

struct ShortsCommentsDrawer: View {
    @ObservedObject var playerManager: PlayerManager
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "ellipsis.bubble.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.cyan)
                    Text("Bình luận")
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundColor(.white)
                    
                    if let total = playerManager.totalCommentsCountText, !total.isEmpty {
                        Text("(\(total))")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(Color(white: 0.6))
                    } else if !playerManager.comments.isEmpty {
                        Text("(\(playerManager.comments.count))")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(Color(white: 0.6))
                    }
                }
                
                Spacer()
                
                // Sort Menu (Hàng đầu / Mới nhất)
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
                                Text("Mới nhất trước")
                                if playerManager.commentSortMode == .newest {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 11))
                            Text(playerManager.commentSortMode == .top ? "Hàng đầu" : "Mới nhất")
                                .font(.system(size: 11.5, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8.5))
                        }
                        .foregroundColor(Color(white: 0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(white: 0.2))
                        .cornerRadius(6)
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                }
                
                // Refresh Button
                Button(action: { playerManager.refreshComments() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(white: 0.7))
                        .frame(width: 28, height: 28)
                        .background(Color(white: 0.18))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Làm mới bình luận")
                
                // Close Button
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(white: 0.85))
                        .frame(width: 28, height: 28)
                        .background(Color(white: 0.22))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Đóng (Phím Esc / C)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(white: 0.12))
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1),
                alignment: .bottom
            )
            
            // Content
            if playerManager.comments.isEmpty {
                if playerManager.isLoadingComments {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView()
                            .controlSize(.regular)
                        Text("Đang tải bình luận Shorts...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(white: 0.6))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 36))
                            .foregroundColor(Color(white: 0.35))
                        Text("Chưa có bình luận nào")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(white: 0.75))
                        Text("Video này chưa có bình luận hoặc tác giả đã tắt tính năng bình luận.")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.45))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Button("Thử tải lại") {
                            playerManager.refreshComments()
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 6)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(playerManager.comments) { comment in
                            ShortsCommentRow(comment: comment)
                        }
                        
                        // Load More indicator / button
                        if playerManager.isLoadingMoreComments {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 14, height: 14)
                                Text("Đang tải thêm bình luận...")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(white: 0.6))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        } else if playerManager.canLoadMoreComments {
                            Button(action: { playerManager.loadMoreComments() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.system(size: 12))
                                    Text("Xem thêm bình luận")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(.cyan)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color(white: 0.16))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
        }
        .background(
            Color(white: 0.09)
                .opacity(0.97)
        )
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1),
            alignment: .leading
        )
        .shadow(color: Color.black.opacity(0.55), radius: 24, x: -6, y: 0)
    }
}

struct ShortsCommentRow: View {
    let comment: VideoComment
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Avatar
            if let avatarUrl = comment.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        Circle().fill(Color(white: 0.2))
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            } else {
                ZStack {
                    Circle().fill(Color(white: 0.25))
                    Text(String(comment.author.prefix(1)).uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: 32, height: 32)
            }
            
            // Details
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.author)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(Color(white: 0.95))
                    
                    if !comment.publishedTime.isEmpty {
                        Text("•  \(comment.publishedTime)")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.5))
                    }
                }
                
                Text(comment.text)
                    .font(.system(size: 12.5))
                    .lineSpacing(2.5)
                    .foregroundColor(Color(white: 0.88))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                
                if !comment.likeCount.isEmpty || (comment.replyCount != nil && comment.replyCount != "0") {
                    HStack(spacing: 14) {
                        if !comment.likeCount.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "hand.thumbsup")
                                    .font(.system(size: 10))
                                Text(comment.likeCount)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(Color(white: 0.55))
                        }
                        
                        if let replies = comment.replyCount, !replies.isEmpty && replies != "0" {
                            HStack(spacing: 4) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 10))
                                Text("\(replies) phản hồi")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(Color(white: 0.55))
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

