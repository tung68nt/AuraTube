import SwiftUI
import AppKit
import WebKit

@MainActor
final class NativeShortsViewModel: ObservableObject {
    @Published var shorts: [Video] = []
    @Published var currentIndex: Int = 0
    @Published var activePlayerIndex: Int = 0
    @Published var isLoading: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var continuationToken: String? = nil
    @Published var likedShorts: Set<String> = []
    @Published var dislikedShorts: Set<String> = []
    @Published var toastMessage: String? = nil
    @Published var isAutoScrollEnabled: Bool = false
    @Published var isCommentsOpen: Bool = false
    
    // Persistent anti-repetition memory: remember recently seen short IDs across app sessions
    private var seenShortIds: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: "auratube_seen_shorts_ids_v2") ?? [])
        }
        set {
            var arr = Array(newValue)
            if arr.count > 300 { arr = Array(arr.suffix(200)) }
            UserDefaults.standard.set(arr, forKey: "auratube_seen_shorts_ids_v2")
        }
    }
    
    private let smartDiscoverySeeds = [
        "shorts trending việt nam",
        "shorts viral việt nam",
        "shorts hài hước triệu view",
        "shorts giải trí hay nhất",
        "shorts công nghệ đời sống",
        "shorts ẩm thực đường phố việt nam",
        "shorts tin tức nóng hổi",
        "shorts biến hình tiktok triệu view",
        "shorts khám phá thế giới kỳ thú",
        "shorts mẹo hay cuộc sống",
        "shorts âm nhạc hot trend"
    ]
    private var streamIndex: Int = Int.random(in: 0...10)
    private var snapSettleTask: Task<Void, Never>? = nil
    private var pendingPlayTask: Task<Void, Never>? = nil
    private var eventMonitor: Any? = nil
    private var keyboardMonitor: Any? = nil
    private var lastScrollDate: Date = Date()
    private var accumulatedDeltaY: CGFloat = 0
    private var isPageTransitioning: Bool = false
    private var hasTriggeredInCurrentGesture: Bool = false
    private var lastAutoScrolledId: String = ""
    public var isFeedActive: Bool = false
    
    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let km = keyboardMonitor {
            NSEvent.removeMonitor(km)
        }
    }
    
    func openShort(_ video: Video, proxy: ScrollViewProxy? = nil) {
        if let idx = shorts.firstIndex(where: { $0.id == video.id }) {
            currentIndex = idx
            activePlayerIndex = idx
            playCurrentShort()
            if let p = proxy {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    p.scrollTo(video.id, anchor: .center)
                }
            }
        } else {
            shorts.insert(video, at: 0)
            currentIndex = 0
            activePlayerIndex = 0
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
    
    // Smart AI/Personalized Recommendation Engine (No manual tags needed)
    func loadInitialShorts(preferredInitial: Video? = nil, forceRefresh: Bool = false) async {
        if let initial = preferredInitial, shorts.isEmpty {
            shorts = [initial]
            currentIndex = 0
            playCurrentShort()
        }
        if !forceRefresh && shorts.count > 1 { return }
        
        isLoading = true
        if forceRefresh { isRefreshing = true }
        
        var queriesToFetch: [String] = []
        
        if let initial = preferredInitial {
            queriesToFetch.append("shorts " + initial.uploader)
        }
        
        // 1. Channel & Creator Affinity: Favorite channels watched or subscribed
        let topChannels = RecommendationService.shared.topChannels
        let subs = ChannelSubscriptionManager.shared.subscribedChannels
        if let ch = topChannels.randomElement() {
            queriesToFetch.append("shorts \(ch)")
        } else if let sub = subs.randomElement() {
            let name = sub.handle ?? sub.title
            queriesToFetch.append("shorts \(name)")
        }
        
        // 2. Interest & Search Intent: Topics user searches for or watches
        let topKw = RecommendationService.shared.topKeywords
        let recentSearches = RecommendationService.shared.recentSearches
        if let kw = topKw.randomElement() ?? recentSearches.randomElement() {
            queriesToFetch.append("shorts \(kw)")
        }
        
        // 3. Dynamic Viral Discovery: Pick varied seeds
        let seed = smartDiscoverySeeds.shuffled().first ?? "shorts trending việt nam"
        if !queriesToFetch.contains(seed) {
            queriesToFetch.append(seed)
        }
        
        var candidateVideos: [Video] = []
        var primaryContinuation: String? = nil
        
        let queries = Array(queriesToFetch.prefix(3))
        await withTaskGroup(of: (Int, [Video], String?).self) { group in
            for (idx, q) in queries.enumerated() {
                group.addTask {
                    let res = await YTDLPService.shared.searchVideosWithContinuation(query: q, params: nil, limit: 16)
                    var extracted = res.shorts
                    if extracted.isEmpty {
                        extracted = res.videos.filter { $0.isShort || $0.durationFormatted == "Shorts" || $0.isExplicitShort == true }
                    }
                    let filtered = extracted.filter { RecommendationService.isFreshTrendingVideo($0) }
                    return (idx, filtered, res.continuationToken)
                }
            }
            for await (idx, vids, token) in group {
                if idx == 0 {
                    primaryContinuation = token
                }
                candidateVideos.append(contentsOf: vids)
            }
        }
        
        if candidateVideos.isEmpty {
            let fallbackQuery = smartDiscoverySeeds.randomElement() ?? "shorts trending việt nam"
            let fallbackRes = await YTDLPService.shared.searchVideosWithContinuation(query: fallbackQuery, params: nil, limit: 20)
            let valid = fallbackRes.shorts.isEmpty ? fallbackRes.videos.filter { $0.isShort || $0.durationFormatted == "Shorts" || $0.isExplicitShort == true } : fallbackRes.shorts
            candidateVideos.append(contentsOf: valid.filter { RecommendationService.isFreshTrendingVideo($0) })
        }
        
        // Smart Deduplication & Non-Repetition against past sessions
        let existingIds = Set(self.shorts.map { $0.id })
        var freshSeen = self.seenShortIds
        
        var unseenVideos = candidateVideos.filter { !existingIds.contains($0.id) && !freshSeen.contains($0.id) }
        if unseenVideos.count < 8 {
            unseenVideos = candidateVideos.filter { !existingIds.contains($0.id) }
        }
        
        unseenVideos.shuffle()
        for v in unseenVideos.prefix(15) {
            freshSeen.insert(v.id)
        }
        self.seenShortIds = freshSeen
        AuraImageCache.shared.prefetchImages(for: unseenVideos.prefix(15).map { $0.thumbnail }, maxPixelSize: 720)
        
        if forceRefresh {
            if let initial = preferredInitial {
                let filtered = unseenVideos.filter { $0.id != initial.id }
                self.shorts = [initial] + filtered
            } else {
                self.shorts = unseenVideos
            }
            self.currentIndex = 0
            self.activePlayerIndex = 0
            if !self.shorts.isEmpty {
                playCurrentShort()
            }
        } else {
            self.shorts.append(contentsOf: unseenVideos)
            if self.currentIndex == 0 && preferredInitial == nil, !self.shorts.isEmpty {
                self.activePlayerIndex = 0
                playCurrentShort()
            }
        }
        
        self.continuationToken = primaryContinuation
        self.isLoading = false
        self.isRefreshing = false
    }
    
    func loadMoreShorts() async {
        guard !isLoading else { return }
        isLoading = true
        
        var newShorts: [Video] = []
        let nextQuery = smartDiscoverySeeds[streamIndex % smartDiscoverySeeds.count]
        
        if let token = continuationToken {
            let res = await YTDLPService.shared.searchVideosWithContinuation(query: nextQuery, continuationToken: token, params: nil)
            newShorts = res.shorts.isEmpty ? res.videos.filter { $0.isShort || $0.durationFormatted == "Shorts" || $0.isExplicitShort == true } : res.shorts
            self.continuationToken = res.continuationToken
        }
        
        if newShorts.isEmpty {
            streamIndex = (streamIndex + 1) % smartDiscoverySeeds.count
            let fallbackQuery = smartDiscoverySeeds[streamIndex]
            let res = await YTDLPService.shared.searchVideosWithContinuation(query: fallbackQuery, params: nil, limit: 16)
            newShorts = res.shorts.isEmpty ? res.videos.filter { $0.isShort || $0.durationFormatted == "Shorts" || $0.isExplicitShort == true } : res.shorts
        }
        
        newShorts = newShorts.filter { RecommendationService.isFreshTrendingVideo($0) }
        
        let existingIds = Set(self.shorts.map { $0.id })
        var freshSeen = self.seenShortIds
        let filtered = newShorts.filter { !existingIds.contains($0.id) }
        
        for v in filtered {
            freshSeen.insert(v.id)
        }
        self.seenShortIds = freshSeen
        
        self.shorts.append(contentsOf: filtered)
        AuraImageCache.shared.prefetchImages(for: filtered.map { $0.thumbnail }, maxPixelSize: 720)
        self.isLoading = false
    }
    
    func refreshFeed(proxy: ScrollViewProxy? = nil) {
        showToast("🔀 Đang đổi gợi ý Shorts mới...")
        Task {
            streamIndex = (streamIndex + 1) % smartDiscoverySeeds.count
            currentIndex = 0
            activePlayerIndex = 0
            await loadInitialShorts(forceRefresh: true)
            if let p = proxy, let first = shorts.first {
                withAnimation {
                    p.scrollTo(first.id, anchor: .center)
                }
            }
        }
    }
    
    // MARK: - Ultra-responsive Mouse Wheel & Trackpad Magnetic Snap (YouTube Shorts Engine)
    
    func startScrollMonitor(proxy: ScrollViewProxy) {
        isFeedActive = true
        guard eventMonitor == nil else { return }
        
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, self.isFeedActive else { return event }
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
            
            // Absorb momentum after fingers lift off trackpad (prevents runaway coasting and multi-skipping)
            if event.momentumPhase != [] {
                return nil
            }
            
            // Trackpad gesture start / end lifecycle
            if event.phase == .began {
                self.hasTriggeredInCurrentGesture = false
                self.accumulatedDeltaY = 0
                return nil
            }
            
            if event.phase == .ended || event.phase == .cancelled {
                self.hasTriggeredInCurrentGesture = false
                self.accumulatedDeltaY = 0
                return nil
            }
            
            // If already transitioning between cards, absorb event to prevent queue pile-up
            if self.isPageTransitioning {
                return nil
            }
            
            // For trackpad: once triggered during current swipe, wait until finger lifts
            if event.hasPreciseScrollingDeltas && self.hasTriggeredInCurrentGesture {
                return nil
            }
            
            let rawDelta = event.scrollingDeltaY
            guard abs(rawDelta) > 0.08 else { return nil }
            
            let now = Date()
            if now.timeIntervalSince(self.lastScrollDate) < 0.32 {
                return nil
            }
            
            let scaledDelta: CGFloat = event.hasPreciseScrollingDeltas ? rawDelta : (rawDelta * 14.0)
            self.accumulatedDeltaY += scaledDelta
            
            let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 16.0 : 10.0
            
            if abs(self.accumulatedDeltaY) >= threshold {
                let isDown = self.accumulatedDeltaY < 0
                self.accumulatedDeltaY = 0
                self.hasTriggeredInCurrentGesture = true
                self.isPageTransitioning = true
                self.lastScrollDate = now
                
                if isDown {
                    self.goToNext(proxy: proxy)
                } else {
                    self.goToPrev(proxy: proxy)
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { [weak self] in
                    self?.isPageTransitioning = false
                }
            }
            
            // Consume scroll wheel event completely so NSScrollView never free-scrolls or stops midway
            return nil
        }
        
        if keyboardMonitor == nil {
            keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, self.isFeedActive else { return event }
                guard let window = event.window, window.isKeyWindow else { return event }
                
                // Do not intercept if user is typing in a text field
                if let responder = window.firstResponder as? NSTextView, responder.isFieldEditor {
                    return event
                }
                if let responder = window.firstResponder as? NSTextField {
                    return event
                }
                
                let key = event.keyCode
                // Left arrow (123) or 'j' / 'J' (38) -> Seek backward 5s
                if key == 123 || key == 38 {
                    let cur = PlayerManager.shared.currentTime
                    let target = max(0, cur - 5.0)
                    PlayerManager.shared.seek(to: target)
                    if self.currentIndex < self.shorts.count {
                        ShortsPlaybackCoordinator.shared.seek(videoId: self.shorts[self.currentIndex].id, to: target)
                    }
                    PlayerManager.shared.flashHUD(icon: "gobackward.5", text: "-5 giây")
                    return nil
                }
                // Right arrow (124) or 'l' / 'L' (37) -> Seek forward 5s
                if key == 124 || key == 37 {
                    let cur = PlayerManager.shared.currentTime
                    let dur = PlayerManager.shared.duration > 0 ? PlayerManager.shared.duration : 60.0
                    let target = min(dur, cur + 5.0)
                    PlayerManager.shared.seek(to: target)
                    if self.currentIndex < self.shorts.count {
                        ShortsPlaybackCoordinator.shared.seek(videoId: self.shorts[self.currentIndex].id, to: target)
                    }
                    PlayerManager.shared.flashHUD(icon: "goforward.5", text: "+5 giây")
                    return nil
                }
                // Up arrow (126) -> Previous Short
                if key == 126 {
                    self.goToPrev(proxy: proxy)
                    return nil
                }
                // Down arrow (125) -> Next Short
                if key == 125 {
                    self.goToNext(proxy: proxy)
                    return nil
                }
                // Space (49) or 'k' / 'K' (40) -> Play / Pause
                if (key == 49 || key == 40) {
                    if event.isARepeat { return nil }
                    PlayerManager.shared.togglePlayPause()
                    return nil
                }
                // 'm' / 'M' (46) -> Toggle Mute
                if key == 46 {
                    PlayerManager.shared.toggleMute()
                    return nil
                }
                
                return event
            }
        }
    }
    
    func stopScrollMonitor() {
        isFeedActive = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let km = keyboardMonitor {
            NSEvent.removeMonitor(km)
            keyboardMonitor = nil
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
        self.schedulePlayCurrentShort(immediate: false)
        
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
        self.schedulePlayCurrentShort(immediate: false)
    }
    
    func snapToCard(index: Int, proxy: ScrollViewProxy) {
        guard index >= 0 && index < shorts.count, index != currentIndex else { return }
        
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
            proxy.scrollTo(shorts[index].id, anchor: .center)
        }
        
        self.currentIndex = index
        self.schedulePlayCurrentShort(immediate: false)
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
    
    func schedulePlayCurrentShort(immediate: Bool = false) {
        pendingPlayTask?.cancel()
        if immediate {
            self.activePlayerIndex = self.currentIndex
            playCurrentShort()
            return
        }
        pendingPlayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000) // 180ms settle debounce
            guard !Task.isCancelled else { return }
            self.activePlayerIndex = self.currentIndex
            self.playCurrentShort()
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
    var onOpenChannel: ((ChannelInfo) -> Void)? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var vm = NativeShortsViewModel()
    @ObservedObject private var subManager = ChannelSubscriptionManager.shared
    @ObservedObject private var playerManager = PlayerManager.shared
    @ObservedObject private var clock = PlaybackClock.shared
    
    public init(
        selectedShort: Binding<Video?> = .constant(nil),
        onSelectVideo: @escaping (Video) -> Void,
        onOpenChannel: ((ChannelInfo) -> Void)? = nil
    ) {
        self._selectedShort = selectedShort
        self.onSelectVideo = onSelectVideo
        self.onOpenChannel = onOpenChannel
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
                Color(nsColor: ThemeColor.windowBackground(for: colorScheme)).ignoresSafeArea()
                
                if vm.isLoading && vm.shorts.isEmpty {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Đang tải YouTube Shorts...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    }
                } else if vm.shorts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "play.square.stack")
                            .font(.system(size: 40))
                            .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                        Text("Không tìm thấy Shorts nào")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
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
                            ZStack(alignment: .top) {
                                ScrollView(.vertical, showsIndicators: false) {
                                    LazyVStack(spacing: 32) {
                                        ForEach(Array(vm.shorts.enumerated()), id: \.element.id) { index, short in
                                            let isActive = (index == vm.currentIndex)
                                            let isPlayerNeeded = (index == vm.activePlayerIndex)
                                            
                                            ShortFeedRowView(
                                                short: short,
                                                index: index,
                                                totalCount: vm.shorts.count,
                                                isActive: isActive,
                                                isPlayerNeeded: isPlayerNeeded,
                                                cardWidth: cardWidth,
                                                cardHeight: cardHeight,
                                                isAutoScrollEnabled: vm.isAutoScrollEnabled,
                                                subManager: subManager,
                                                playerManager: playerManager,
                                                vm: vm,
                                                onSelectVideo: onSelectVideo,
                                                onOpenChannel: onOpenChannel,
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
                                    .padding(.top, max(24, (containerHeight - cardHeight) / 2) + 24)
                                    .padding(.bottom, max(20, (containerHeight - cardHeight) / 2))
                                    .frame(maxWidth: .infinity)
                                }
                                .onAppear {
                                    DispatchQueue.main.async {
                                        NSApp.keyWindow?.makeFirstResponder(nil)
                                    }
                                    vm.startScrollMonitor(proxy: proxy)
                                    if !vm.shorts.isEmpty && vm.currentIndex < vm.shorts.count {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                            proxy.scrollTo(vm.shorts[vm.currentIndex].id, anchor: .center)
                                        }
                                    }
                                }
                                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AuraTubeShortEnded"))) { notif in
                                    if let vid = notif.object as? String, vm.isAutoScrollEnabled, vm.currentShort?.id == vid {
                                        vm.goToNext(proxy: proxy)
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
                                .onChange(of: clock.currentTime) { curTime in
                                    vm.checkAutoScroll(
                                        currentTime: curTime,
                                        duration: clock.duration > 0 ? clock.duration : playerManager.duration,
                                        proxy: proxy
                                    )
                                }
                                .overlay(
                                    // Hidden keyboard shortcuts for Up / Down arrows, Auto-Scroll, Refresh & Comments
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
                                        Button("") { vm.refreshFeed(proxy: proxy) }
                                            .keyboardShortcut("r", modifiers: [])
                                            .opacity(0)
                                        Button("") { vm.toggleComments() }
                                            .keyboardShortcut("c", modifiers: [])
                                            .opacity(0)
                                        Button("") { PlayerManager.shared.toggleFullscreen() }
                                            .keyboardShortcut("f", modifiers: [])
                                            .opacity(0)
                                        if vm.isCommentsOpen {
                                            Button("") { vm.toggleComments() }
                                                .keyboardShortcut(.escape, modifiers: [])
                                                .opacity(0)
                                        }
                                    }
                                    .frame(width: 0, height: 0)
                                )
                                
                                // Floating Clean Control Bar (Minimalist & Unobtrusive)
                                HStack {
                                    // Refresh / Shuffle Recommendations Button
                                    Button(action: {
                                        vm.refreshFeed(proxy: proxy)
                                    }) {
                                        HStack(spacing: 5) {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                                .font(.system(size: 11, weight: .bold))
                                                .rotationEffect(.degrees(vm.isRefreshing ? 360 : 0))
                                                .animation(vm.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: vm.isRefreshing)
                                            Text("Đổi gợi ý")
                                                .font(.system(size: 11.5, weight: .semibold))
                                        }
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(colorScheme == .dark ? Color(white: 0.16).opacity(0.85) : Color.white.opacity(0.92))
                                                .overlay(
                                                    Capsule()
                                                        .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12), lineWidth: 0.8)
                                                )
                                        )
                                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 6, y: 2)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Tải danh sách Shorts gợi ý mới ngẫu nhiên (Phím tắt: R)")
                                    
                                    Spacer()
                                    
                                    // Auto Scroll Switch
                                    Button(action: { vm.toggleAutoScroll() }) {
                                        HStack(spacing: 5) {
                                            Image(systemName: vm.isAutoScrollEnabled ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(vm.isAutoScrollEnabled ? .green : (colorScheme == .dark ? Color.white.opacity(0.8) : Color(red: 96/255, green: 96/255, blue: 96/255)))
                                            Text(vm.isAutoScrollEnabled ? "Tự cuộn: BẬT" : "Tự cuộn")
                                                .font(.system(size: 11.5, weight: vm.isAutoScrollEnabled ? .bold : .medium))
                                                .foregroundColor(vm.isAutoScrollEnabled ? (colorScheme == .dark ? .white : .green) : ThemeColor.textPrimary(for: colorScheme))
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(vm.isAutoScrollEnabled ? Color.green.opacity(colorScheme == .dark ? 0.28 : 0.18) : (colorScheme == .dark ? Color(white: 0.14).opacity(0.8) : Color.white.opacity(0.92)))
                                        )
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(vm.isAutoScrollEnabled ? Color.green.opacity(0.7) : (colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12)), lineWidth: 0.8)
                                        )
                                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 6, y: 2)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Bật/Tắt tự động chuyển sang video tiếp theo khi xem xong (Phím tắt: A)")
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 14)
                            }
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
    
    func seek(videoId: String, to seconds: Double) {
        if let webView = registeredWebViews[videoId] {
            let clamped = max(0, seconds)
            let js = """
            try {
                var ifr = document.getElementById('ytPlayer');
                if (ifr && ifr.contentWindow) {
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "seekTo", args: [\(clamped), true]}), '*');
                }
                var vids = document.querySelectorAll('video');
                for (var i = 0; i < vids.length; i++) {
                    vids[i].currentTime = \(clamped);
                }
            } catch(e) {}
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
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
            html, body {
                width: 100% !important;
                height: 100% !important;
                margin: 0 !important;
                padding: 0 !important;
                overflow: hidden !important;
                background: transparent !important;
            }
            #movie_player, .html5-video-player, .html5-video-container {
                display: block !important;
                visibility: visible !important;
                opacity: 1 !important;
                width: 100% !important;
                height: 100% !important;
            }
            video, .html5-main-video,
            .ytp-fit-cover-video video,
            .html5-video-player.ytp-fit-cover-video video {
                display: block !important;
                visibility: visible !important;
                opacity: 1 !important;
                object-fit: contain !important;
                object-position: center center !important;
            }
            /* 1. YouTube Mobile & Embedded Player Controls, Info, and Overlays */
            embedded-player-video-details,
            player-top-controls,
            player-fullscreen-controls,
            player-fullscreen-top-controls,
            ytm-watch-player-controls,
            video-cover,
            cued-overlay,
            ytm-custom-control,
            ytm-button-renderer,
            .new-controls,
            .player-controls-content,
            .player-controls-background-container,
            .player-controls-background,
            .ytPlayerControlsContainerHost,
            .ytmVideoInfoHost,
            .ytmVideoInfoVideoDetailsContainer,
            .ytmVideoInfoVideoTitleContainer,
            .ytmVideoInfoVideoTitle,
            .ytmVideoInfoChannelTitle,
            .ytmVideoInfoChannelContainer,
            .ytmVideoInfoChannelAvatar,
            .ytmVideoInfoChannelLogo,
            .ytmVideoInfoOverlay,
            .ytmVideoInfoChannelInfo,
            .ytmVideoInfoFlyoutChannelTitle,
            .ytmVideoInfoFlyoutChannelSubtitle,
            .ytwPlayerTopControlsHost,
            .ytwPlayerFullscreenTopControlsHost,
            .ytwPlayerFullscreenTopControlsFullscreenControlsVideoTitle,
            .ytwPlayerFullscreenTopControlsFullscreenCloseButtonWrapper,
            .ytwPlayerFullscreenControlsHost,
            .ytwPlayerTopControlsContainerWithLeftContent,
            .ytmWatchPlayerControlsHost,
            .ytmWatchPlayerControlsBackgroundActionItems,
            .action-menu-engagement-buttons-wrapper,
            .watch-on-youtube-button-wrapper,
            .circle-buttons,
            .icon-share_arrow,
            .icon-close,
            [class*="VideoInfo"],
            [class*="ytmVideoInfo"],
            [class*="ytwPlayer"],
            [class*="ytmWatch"],
            [class*="player-controls"],
            [class*="fullscreen-controls"],
            [class*="FullscreenTopControls"],
            [class*="engagement-buttons"],
            [class*="circle-buttons"],
            [class*="share_arrow"],
            [class*="icon-share"],
            
            /* 2. YouTube Desktop Player Controls, Overlays, and Metadata */
            .ytp-shorts-title,
            .ytp-shorts-channel-name,
            .ytp-shorts-channel-avatar,
            .ytp-shorts-subscribe-button,
            .ytp-shorts-like-button,
            .ytp-shorts-dislike-button,
            .ytp-shorts-share-button,
            .ytp-modern-title,
            .ytPlayerOverlayVideoDetailsRendererHost,
            .ytPlayerOverlayVideoDetailsRendererTitle,
            .ytPlayerOverlayVideoDetailsRendererSubtitle,
            .ytPlayerOverlayVideoDetailsRendererChannelAvatarContainer,
            .ytPlayerOverlayVideoDetailsRendererTextContainer,
            .ytPlayerOverlayVideoDetailsRendererFrostedGlass,
            [class*="ytPlayerOverlayVideoDetailsRenderer"],
            [class*="VideoDetailsRenderer"],
            ytw-player-top-controls,
            yt-player-overlay-video-details-renderer,
            ytm-video-info-flyout,
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
            .ytp-pause-overlay-container,
            .ytp-bezel,
            .ytp-bezel-container,
            .ytp-bezel-icon,
            .ytp-bezel-text,
            .ytp-cairo-refresh-signature-moments,
            .ytp-cairo-refresh-signature-moments-title,
            .ytp-unmute,
            .ytp-unmute-inner,
            .ytp-unmute-icon,
            .ytp-unmute-text,
            .ytp-unmute-box,
            .ytp-volume-control,
            .annotation,
            .iv-branding,
            .ytp-paid-content-overlay,
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
                z-index: -9999 !important;
            }
            .ytp-large-play-button,
            button.ytp-large-play-button {
                opacity: 0.001 !important;
                width: 100% !important;
                height: 100% !important;
                position: absolute !important;
                top: 0 !important;
                left: 0 !important;
                z-index: 99 !important;
                cursor: pointer !important;
                border: none !important;
                background: transparent !important;
            }
            .ytp-large-play-button-bg,
            .ytp-large-play-button-red-bg,
            svg.ytp-large-play-button-svg,
            .ytp-button.ytp-large-play-button-bg {
                opacity: 0 !important;
                display: none !important;
            }
        `;

        function applyShortsStyles() {
            try {
                var target = document.head || document.documentElement || document.body;
                if (target && !document.getElementById('__auratube_shorts_styles')) {
                    var s = document.createElement('style');
                    s.id = '__auratube_shorts_styles';
                    s.textContent = css;
                    target.appendChild(s);
                }
            } catch(e) {}
        }

        function removeEmbedOverlays() {
            try {
                var selectors = [
                    'embedded-player-video-details',
                    'player-top-controls',
                    'player-fullscreen-controls',
                    'player-fullscreen-top-controls',
                    'ytm-watch-player-controls',
                    'video-cover',
                    'cued-overlay',
                    'ytm-custom-control',
                    'ytm-button-renderer',
                    '.new-controls',
                    '.player-controls-content',
                    '.player-controls-background-container',
                    '.ytPlayerControlsContainerHost',
                    '.ytmVideoInfoHost',
                    '.ytwPlayerTopControlsHost',
                    '.ytwPlayerFullscreenTopControlsHost',
                    '.action-menu-engagement-buttons-wrapper',
                    '.watch-on-youtube-button-wrapper',
                    '.circle-buttons',
                    '.icon-share_arrow',
                    '.icon-close',
                    '.ytp-unmute',
                    '.ytp-chrome-top',
                    '.ytp-chrome-bottom',
                    '.ytp-pause-overlay',
                    '.ytp-pause-overlay-container',
                    '.ytp-gradient-top',
                    '.ytp-gradient-bottom',
                    '.ytp-title',
                    '.ytp-title-channel'
                ];
                var els = document.querySelectorAll(selectors.join(','));
                for (var i = 0; i < els.length; i++) {
                    var el = els[i];
                    el.style.setProperty('display', 'none', 'important');
                    el.style.setProperty('opacity', '0', 'important');
                    el.style.setProperty('visibility', 'hidden', 'important');
                    el.style.setProperty('pointer-events', 'none', 'important');
                    el.style.setProperty('width', '0px', 'important');
                    el.style.setProperty('height', '0px', 'important');
                }
            } catch(e) {}
        }

        applyShortsStyles();
        removeEmbedOverlays();
        document.addEventListener('DOMContentLoaded', function() {
            applyShortsStyles();
            removeEmbedOverlays();
        });
        window.addEventListener('load', function() {
            applyShortsStyles();
            removeEmbedOverlays();
        });
        
        if (window.MutationObserver) {
            var removeDebounce = null;
            var observer = new MutationObserver(function() {
                if (!removeDebounce) {
                    removeDebounce = setTimeout(function() {
                        removeDebounce = null;
                        applyShortsStyles();
                        removeEmbedOverlays();
                    }, 400);
                }
            });
            try {
                observer.observe(document.documentElement || document.body, { childList: true, subtree: true });
                setTimeout(function() {
                    try { observer.disconnect(); } catch(e) {}
                }, 3500);
            } catch(e) {}
        }
    })();
    """
    
    var onActuallyPlaying: (() -> Void)? = nil
    
    init(videoId: String, isActive: Bool, isPreload: Bool = false, onActuallyPlaying: (() -> Void)? = nil) {
        self.videoId = videoId
        self.isActive = isActive
        self.isPreload = isPreload
        self.onActuallyPlaying = onActuallyPlaying
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(videoId: videoId, isActive: isActive, isPreload: isPreload, onActuallyPlaying: onActuallyPlaying)
    }
    
    func makeNSView(context: Context) -> ScrollForwardingWKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.setValue(false, forKey: "allowFileAccessFromFileURLs")
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
        
        // Inject shorts cleanup scripts directly at document start and document end into both worlds
        let shortsScript = WKUserScript(source: ShortsCardPlayerView.cleanShortsScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)
        contentController.addUserScript(shortsScript)
        
        let clientShortsScript = WKUserScript(source: ShortsCardPlayerView.cleanShortsScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient)
        contentController.addUserScript(clientShortsScript)
        
        let shortsScriptEnd = WKUserScript(source: ShortsCardPlayerView.cleanShortsScriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: .page)
        contentController.addUserScript(shortsScriptEnd)
        
        let clientShortsScriptEnd = WKUserScript(source: ShortsCardPlayerView.cleanShortsScriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: .defaultClient)
        contentController.addUserScript(clientShortsScriptEnd)
        config.userContentController = contentController
        
        let webView = ScrollForwardingWKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.targetWebView = webView
        
        let mute = isPreload || playerManager.isMuted
        let html = ShortsCardPlayerView.generateHTML(videoId: videoId, isPreload: isPreload, isMuted: mute)
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
        
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
        context.coordinator.onActuallyPlaying = onActuallyPlaying
        context.coordinator.targetWebView = nsView
        
        ShortsPlaybackCoordinator.shared.register(videoId: videoId, webView: nsView)
        
        if isActive {
            setupActiveBindings(context: context)
            ShortsPlaybackCoordinator.shared.activateOnly(videoId: videoId)
            if !wasActive || !context.coordinator.isActuallyPlaying {
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
        playerManager.onMuteToggle = { [weak coord = context.coordinator] isMuted in
            coord?.setMuted(isMuted)
        }
        playerManager.onSeek = { [weak coord = context.coordinator] targetSec in
            coord?.seek(to: targetSec)
        }
    }
    
    static func generateHTML(videoId: String, isPreload: Bool, isMuted: Bool) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; overflow: hidden; }
          html, body { width: 100%; height: 100%; background: transparent !important; margin: 0; padding: 0; }
          #ytPlayer, iframe { width: 100% !important; height: 100% !important; border: none; display: block; }
          .ytp-large-play-button, button.ytp-large-play-button {
            opacity: 0.001 !important;
            width: 100% !important;
            height: 100% !important;
            position: absolute !important;
            top: 0 !important;
            left: 0 !important;
            z-index: 10 !important;
            cursor: pointer !important;
            border: none !important;
            background: transparent !important;
          }
          embedded-player-video-details, player-top-controls, player-fullscreen-controls, player-fullscreen-top-controls, ytm-watch-player-controls, video-cover, cued-overlay, ytm-custom-control, ytm-button-renderer, .new-controls, .player-controls-content, .player-controls-background-container, .player-controls-background, .ytPlayerControlsContainerHost, .ytmVideoInfoHost, .ytmVideoInfoVideoDetailsContainer, .ytmVideoInfoVideoTitleContainer, .ytmVideoInfoVideoTitle, .ytmVideoInfoChannelTitle, .ytmVideoInfoChannelContainer, .ytmVideoInfoChannelAvatar, .ytmVideoInfoChannelLogo, .ytmVideoInfoOverlay, .ytmVideoInfoChannelInfo, .ytmVideoInfoFlyoutChannelTitle, .ytmVideoInfoFlyoutChannelSubtitle, .ytwPlayerTopControlsHost, .ytwPlayerFullscreenTopControlsHost, .ytwPlayerFullscreenControlsHost, .ytwPlayerTopControlsContainerWithLeftContent, .ytmWatchPlayerControlsHost, .action-menu-engagement-buttons-wrapper, .watch-on-youtube-button-wrapper, .circle-buttons, .icon-share_arrow, .icon-close, [class*="VideoInfo"], [class*="ytmVideoInfo"], [class*="ytwPlayer"], [class*="ytmWatch"], [class*="player-controls"], [class*="fullscreen-controls"], [class*="engagement-buttons"], [class*="circle-buttons"], [class*="share_arrow"], .ytPlayerOverlayVideoDetailsRendererHost, .ytPlayerOverlayVideoDetailsRendererTitle, .ytPlayerOverlayVideoDetailsRendererSubtitle, .ytPlayerOverlayVideoDetailsRendererChannelAvatarContainer, .ytPlayerOverlayVideoDetailsRendererTextContainer, .ytPlayerOverlayVideoDetailsRendererFrostedGlass, [class*="ytPlayerOverlayVideoDetailsRenderer"], [class*="VideoDetailsRenderer"], ytw-player-top-controls, yt-player-overlay-video-details-renderer, ytm-video-info-flyout, .ytp-shorts-title, .ytp-shorts-channel-name, .ytp-modern-title, .ytp-suggested-action-badge, .ytp-popup, .ytp-ai-info-dialog, [class*="ai-disclosure"], .ytp-paid-content-overlay, [class*="paid-content"], [class*="paid-promotion"], .ytp-chrome-top, .ytp-chrome-bottom, [class*="title-channel"], .ytp-bezel, .ytp-bezel-container, .ytp-pause-overlay, .ytp-pause-overlay-container, .ytp-impression-link, .ytp-title, .ytp-title-text, .ytp-title-channel, .ytp-title-channel-logo, .ytp-cairo-refresh-signature-moments, .ytp-cairo-refresh-signature-moments-title, .ytp-unmute, .ytp-unmute-inner, .ytp-unmute-icon, .ytp-unmute-text, .ytp-unmute-box { display: none !important; opacity: 0 !important; visibility: hidden !important; pointer-events: none !important; width: 0 !important; height: 0 !important; max-width: 0 !important; max-height: 0 !important; position: absolute !important; left: -9999px !important; top: -9999px !important; z-index: -9999 !important; }
        </style>
        </head>
        <body>
        <iframe 
            id="ytPlayer"
            src="https://www.youtube-nocookie.com/embed/\(videoId)?autoplay=1&mute=\(isMuted ? 1 : 0)&playsinline=1&controls=0&enablejsapi=1&rel=0&modestbranding=1&fs=0&loop=1&playlist=\(videoId)" 
            referrerpolicy="strict-origin-when-cross-origin"
            allow="autoplay; encrypted-media; picture-in-picture; fullscreen" 
            allowfullscreen="true">
        </iframe>
        <script>
          var isPreload = \(isPreload ? "true" : "false");
          var isActive = \(isPreload ? "false" : "true");
          var currentVideoId = '\(videoId)';
          var hasFrozen = false;
          var isUserMuted = \(isMuted ? "true" : "false");
          var hasPlaybackStarted = false;

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
              ifr.contentWindow.postMessage(JSON.stringify({event: "listening"}), '*');
            }
          }

          function unmuteIfPlaying() {
            if (!isUserMuted && isActive) {
              var ifr = document.getElementById('ytPlayer');
              if (ifr && ifr.contentWindow) {
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
              setTimeout(pingIframe, 100);
              setTimeout(pingIframe, 300);
            };
          }

          var handshakeCount = 0;
          var handshakeTimer = setInterval(function() {
            handshakeCount++;
            if (hasPlaybackStarted || handshakeCount > 15) {
              clearInterval(handshakeTimer);
              return;
            }
            if (isActive) {
              triggerPlayback();
            } else if (!isActive) {
              pingIframe();
            }
          }, 350);

          document.addEventListener('click', function() {
            if (isActive) {
              triggerPlayback();
              unmuteIfPlaying();
            }
          });

          window.addEventListener('message', function(e) {
            try {
              var data = e.data;
              if (typeof data === 'string') {
                try { data = JSON.parse(data); } catch(ex) { return; }
              }
              if (!data || typeof data !== 'object') return;
              if (data.event === 'onReady') {
                if (isActive) {
                  triggerPlayback();
                }
              }
              if (data.event === 'infoDelivery' && data.info) {
                if (data.info.playerState === 1 || (data.info.currentTime && data.info.currentTime > 0.03)) {
                  if (isActive) {
                    hasPlaybackStarted = true;
                    clearInterval(handshakeTimer);
                    unmuteIfPlaying();
                    sendBridge({ type: 'actuallyPlaying', videoId: currentVideoId, isPlaying: true });
                  }
                }
                if (data.info.playerState === 0) {
                  // Loop short instantly so it never halts on a black screen
                  var ifr = document.getElementById('ytPlayer');
                  if (ifr && ifr.contentWindow) {
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "seekTo", args: [0, true]}), '*');
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "playVideo", args: []}), '*');
                  }
                  sendBridge({ type: 'shortEnded', videoId: currentVideoId });
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
        var onActuallyPlaying: (() -> Void)?
        var hasPreparedPreload: Bool = false
        var hasStartedPlayback: Bool = false
        var isActuallyPlaying: Bool = false
        var isUserPaused: Bool = false
        var autoPlayAttempts: Int = 0
        
        init(videoId: String, isActive: Bool, isPreload: Bool = false, onActuallyPlaying: (() -> Void)? = nil) {
            self.videoId = videoId
            self.isActive = isActive
            self.isPreload = isPreload
            self.onActuallyPlaying = onActuallyPlaying
        }
        
        func seek(to seconds: Double) {
            let clamped = max(0, seconds)
            let js = """
            try {
                var ifr = document.getElementById('ytPlayer');
                if (ifr && ifr.contentWindow) {
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "seekTo", args: [\(clamped), true]}), '*');
                }
                var vids = document.querySelectorAll('video');
                for (var i = 0; i < vids.length; i++) {
                    vids[i].currentTime = \(clamped);
                }
            } catch(e) {}
            """
            targetWebView?.evaluateJavaScript(js, completionHandler: nil)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            targetWebView = webView
            if isActive {
                startActivePlayback()
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
                if type == "toggleFullscreen" {
                    PlayerManager.shared.toggleFullscreen()
                    return
                }
                if type == "shortEnded" {
                    NotificationCenter.default.post(name: NSNotification.Name("AuraTubeShortEnded"), object: videoId)
                    return
                }
                if type == "actuallyPlaying" {
                    isActuallyPlaying = true
                    PlayerManager.shared.isPlaying = true
                    DispatchQueue.main.async { [weak self] in
                        self?.onActuallyPlaying?()
                    }
                } else if type == "stateChange" {
                    if let playing = body["isPlaying"] as? Bool {
                        if playing {
                            isActuallyPlaying = true
                            PlayerManager.shared.isPlaying = true
                            DispatchQueue.main.async { [weak self] in
                                self?.onActuallyPlaying?()
                            }
                        } else if !isUserPaused {
                            if let wv = targetWebView {
                                ensureShortAutoPlay(on: wv)
                            }
                        } else {
                            PlayerManager.shared.isPlaying = false
                        }
                    }
                } else if type == "timeUpdate" {
                    if let cur = body["currentTime"] as? Double, !cur.isNaN {
                        if cur > 0.03 && !isActuallyPlaying {
                            isActuallyPlaying = true
                            DispatchQueue.main.async { [weak self] in
                                self?.onActuallyPlaying?()
                            }
                        }
                        let dur = body["duration"] as? Double ?? PlayerManager.shared.duration
                        let playing = body["isPlaying"] as? Bool ?? (cur > 0.03)
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
            isUserPaused = false
            isActuallyPlaying = false
            autoPlayAttempts = 0
            hasStartedPlayback = true
            
            if let wv = targetWebView {
                ensureShortAutoPlay(on: wv)
            }
        }
        
        func ensureShortAutoPlay(on view: WKWebView) {
            guard isActive && !isUserPaused else { return }
            guard !isActuallyPlaying else { return }
            guard autoPlayAttempts < 8 else { return }
            autoPlayAttempts += 1
            
            let isUserMuted = PlayerManager.shared.isMuted
            let js = """
            (function() {
                var ifr = document.getElementById('ytPlayer');
                if (ifr && ifr.contentWindow) {
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "playVideo", args: []}), '*');
                    ifr.contentWindow.postMessage(JSON.stringify({event: "listening"}), '*');
                    if (!\(isUserMuted ? "true" : "false")) {
                        ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "unMute", args: []}), '*');
                        ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setVolume", args: [100]}), '*');
                    }
                }
            })();
            """
            view.evaluateJavaScript(js, completionHandler: nil)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak view] in
                guard let self = self, let v = view else { return }
                if self.isActive && !self.isUserPaused && !self.isActuallyPlaying && self.autoPlayAttempts < 8 {
                    self.ensureShortAutoPlay(on: v)
                }
            }
        }
        
        func pausePlayback() {
            isUserPaused = true
            isActuallyPlaying = false
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
        
        func setMuted(_ isMuted: Bool) {
            let cmd = isMuted ? "mute" : "unMute"
            let js = """
            var ifr = document.getElementById('ytPlayer');
            if (ifr && ifr.contentWindow) {
                ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "\(cmd)", args: []}), '*');
                if (!\(isMuted)) {
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setVolume", args: [100]}), '*');
                }
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

// MARK: - Interactive Shorts Scrubbing Timeline Bar
struct ShortsTimelineBarView: View {
    let currentTime: Double
    let duration: Double
    let cardWidth: CGFloat
    let onSeek: (Double) -> Void
    
    @State private var isHovering: Bool = false
    @State private var isDragging: Bool = false
    @State private var dragProgress: Double? = nil
    @State private var hoverLocationX: CGFloat? = nil
    
    private var effectiveDuration: Double {
        duration > 0 ? duration : 15.0
    }
    
    private var progress: Double {
        if let drag = dragProgress {
            return max(0, min(1, drag))
        }
        guard effectiveDuration > 0 else { return 0 }
        return max(0, min(1, currentTime / effectiveDuration))
    }
    
    private var displayTime: Double {
        if let drag = dragProgress {
            return drag * effectiveDuration
        }
        return currentTime
    }
    
    private func formatTime(_ sec: Double) -> String {
        let total = Int(max(0, sec))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
    
    var body: some View {
        let isExpanded = isHovering || isDragging
        let barHeight: CGFloat = isExpanded ? 7 : 3.5
        let hitHeight: CGFloat = 26
        
        ZStack(alignment: .bottomLeading) {
            // Floating timestamp tooltip when hovering or scrubbing
            if isExpanded {
                let badgeX: CGFloat = {
                    let rawX = (dragProgress != nil ? (dragProgress! * cardWidth) : (hoverLocationX ?? (CGFloat(progress) * cardWidth)))
                    return max(50, min(cardWidth - 50, rawX))
                }()
                
                HStack(spacing: 3) {
                    Text(formatTime(displayTime))
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("/")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text(formatTime(effectiveDuration))
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                )
                .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
                .position(x: badgeX, y: -16)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .animation(.easeOut(duration: 0.15), value: isExpanded)
            }
            
            // Background track
            Rectangle()
                .fill(Color.white.opacity(isExpanded ? 0.38 : 0.24))
                .frame(width: cardWidth, height: barHeight)
            
            // Red Progress Fill
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.red, Color(red: 1.0, green: 0.25, blue: 0.25)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: max(0, cardWidth * CGFloat(progress)), height: barHeight)
            
            // Scrubbing Knob / Thumb
            if isExpanded {
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .fill(Color.red)
                            .frame(width: 5, height: 5)
                    )
                    .shadow(color: Color.black.opacity(0.5), radius: 3, x: 0, y: 1)
                    .offset(x: max(0, min(cardWidth - 14, cardWidth * CGFloat(progress) - 7)), y: (barHeight - 14) / 2)
                    .transition(.scale.combined(with: .opacity))
            }
            
            // Expanded Interactive Hit Area
            Color.clear
                .frame(width: cardWidth, height: hitHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            isDragging = true
                            let pct = max(0, min(1, Double(val.location.x / cardWidth)))
                            dragProgress = pct
                            hoverLocationX = val.location.x
                            onSeek(pct * effectiveDuration)
                        }
                        .onEnded { val in
                            let pct = max(0, min(1, Double(val.location.x / cardWidth)))
                            isDragging = false
                            dragProgress = nil
                            onSeek(pct * effectiveDuration)
                        }
                )
        }
        .frame(width: cardWidth, height: hitHeight, alignment: .bottom)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                isHovering = true
                hoverLocationX = location.x
            case .ended:
                isHovering = false
                hoverLocationX = nil
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isExpanded)
    }
}

// MARK: - Individual Short Feed Row (Card + Floating Action Dock)
struct ShortFeedRowView: View {
    let short: Video
    let index: Int
    let totalCount: Int
    let isActive: Bool
    let isPlayerNeeded: Bool
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let isAutoScrollEnabled: Bool
    @ObservedObject var subManager: ChannelSubscriptionManager
    @ObservedObject var playerManager: PlayerManager
    @ObservedObject var vm: NativeShortsViewModel
    let onSelectVideo: (Video) -> Void
    var onOpenChannel: ((ChannelInfo) -> Void)? = nil
    let onGoPrev: () -> Void
    let onGoNext: () -> Void
    let onTapCard: () -> Void
    
    @State private var isVideoReady: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        return HStack(alignment: .bottom, spacing: 18) {
            // Main 9:16 Video Card
            ZStack(alignment: .bottom) {
                // Layer 1: Permanent High-Res Thumbnail (Always present underneath, guarantees 0% black screen)
                ZStack {
                    Color(white: 0.10)
                    CachedAsyncThumbnail(
                        url: short.thumbnail,
                        maxPixelSize: 720,
                        placeholderColor: Color(white: 0.12)
                    )
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                
                // Layer 2: Active Video Player (Fades in smoothly when video actually renders)
                if isPlayerNeeded {
                    ShortsCardPlayerView(
                        videoId: short.id,
                        isActive: isActive,
                        isPreload: false,
                        onActuallyPlaying: {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                isVideoReady = true
                            }
                        }
                    )
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .opacity(isVideoReady ? 1.0 : 0.001)
                }
                
                // Subtle frosted-glass buffering spinner over thumbnail
                if isActive && !isVideoReady {
                    ZStack {
                        ProgressView()
                            .controlSize(.small)
                            .colorScheme(.dark)
                    }
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
                    .frame(width: cardWidth, height: cardHeight, alignment: .center)
                    .transition(.opacity)
                }
                
                // Play indicator: ONLY shown for the currently active card when paused by user, centered cleanly in the video
                if isActive && !playerManager.isPlaying {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.55))
                            .frame(width: 68, height: 68)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                                    .offset(x: 2.5)
                            )
                            .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 4)
                    }
                    .frame(width: cardWidth, height: cardHeight, alignment: .center)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.18), value: playerManager.isPlaying)
                }
                
                // Top Bar inside Video: Fullscreen & Sound Mute Button
                if isActive {
                    VStack {
                        HStack {
                            Button(action: { PlayerManager.shared.toggleFullscreen() }) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Toàn màn hình (F)")
                            .padding([.top, .leading], 14)

                            Spacer()
                            Button(action: { playerManager.toggleMute() }) {
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
                        Button(action: {
                            let cid: String = {
                                if let uid = short.uploaderId, !uid.isEmpty { return uid }
                                return short.uploader
                            }()
                            let ch = ChannelInfo(
                                id: cid,
                                title: uploaderDisplay,
                                handle: cid.hasPrefix("@") ? cid : nil,
                                avatarUrl: short.channelAvatarUrl ?? ""
                            )
                            onOpenChannel?(ch)
                        }) {
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
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Xem kênh \(uploaderDisplay)")
                        
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
                .padding(.bottom, 4)
                .frame(width: cardWidth)
                .background(
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                
                // Interactive Timeline Scrubbing Bar (flush with bottom edge)
                if isActive {
                    let curT = playerManager.currentTime
                    let durT = playerManager.duration > 0 ? playerManager.duration : max(15.0, short.totalDurationSeconds)
                    ShortsTimelineBarView(
                        currentTime: curT,
                        duration: durT,
                        cardWidth: cardWidth,
                        onSeek: { targetSec in
                            let clamped = max(0, min(durT, targetSec))
                            playerManager.seek(to: clamped)
                            ShortsPlaybackCoordinator.shared.seek(videoId: short.id, to: clamped)
                        }
                    )
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                LiquidGlassCircleButton(
                    action: onGoPrev,
                    size: 44
                ) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(index > 0 ? ThemeColor.textPrimary(for: colorScheme) : ThemeColor.textTertiary(for: colorScheme).opacity(0.4))
                }
                .disabled(index <= 0)
                .opacity(index <= 0 ? 0.45 : 1.0)
                .help("Short trước (Mũi tên lên)")
                
                // Navigation Down Arrow
                LiquidGlassCircleButton(
                    action: onGoNext,
                    size: 44
                ) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(index < totalCount - 1 ? ThemeColor.textPrimary(for: colorScheme) : ThemeColor.textTertiary(for: colorScheme).opacity(0.4))
                }
                .disabled(index >= totalCount - 1)
                .opacity(index >= totalCount - 1 ? 0.45 : 1.0)
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
                
                // PiP Button
                ActionButton(
                    icon: "pip.enter",
                    label: "PiP",
                    isActive: false,
                    activeColor: .white
                ) {
                    PlayerManager.shared.loadAndPlay(video: short)
                    PlayerManager.shared.enterPictureInPicture()
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
        .onChange(of: isPlayerNeeded) { needed in
            if !needed {
                isVideoReady = false
            }
        }
    }
}

private struct ActionButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 5) {
            LiquidGlassCircleButton(
                action: action,
                size: 44,
                isActive: isActive,
                activeTint: activeColor
            ) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isActive ? (activeColor == .white ? .black : .white) : ThemeColor.textPrimary(for: colorScheme))
            }
            
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                .lineLimit(1)
        }
    }
}

// MARK: - Shorts Comments Drawer & Rows

struct ShortsCommentsDrawer: View {
    @ObservedObject var playerManager: PlayerManager
    let onClose: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
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
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    
                    if let total = playerManager.totalCommentsCountText, !total.isEmpty {
                        Text("(\(total))")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                    } else if !playerManager.comments.isEmpty {
                        Text("(\(playerManager.comments.count))")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
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
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(colorScheme == .dark ? Color(white: 0.2) : Color.black.opacity(0.06))
                        .cornerRadius(6)
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                }
                
                // Refresh Button
                Button(action: { playerManager.refreshComments() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        .frame(width: 28, height: 28)
                        .background(colorScheme == .dark ? Color(white: 0.18) : Color.black.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Làm mới bình luận")
                
                // Close Button
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                        .frame(width: 28, height: 28)
                        .background(colorScheme == .dark ? Color(white: 0.22) : Color.black.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Đóng (Phím Esc / C)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(colorScheme == .dark ? Color(white: 0.12) : Color.white.opacity(0.96))
            .overlay(
                Rectangle()
                    .fill(ThemeColor.divider(for: colorScheme))
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
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 36))
                            .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                        Text("Chưa có bình luận nào")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                        Text("Video này chưa có bình luận hoặc tác giả đã tắt tính năng bình luận.")
                            .font(.system(size: 12))
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
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
                                    .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
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
                                .background(colorScheme == .dark ? Color(white: 0.16) : Color.black.opacity(0.06))
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
            (colorScheme == .dark ? Color(white: 0.09).opacity(0.97) : Color(white: 0.98).opacity(0.98))
        )
        .overlay(
            Rectangle()
                .fill(ThemeColor.divider(for: colorScheme))
                .frame(width: 1),
            alignment: .leading
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.55 : 0.15), radius: 24, x: -6, y: 0)
    }
}

struct ShortsCommentRow: View {
    let comment: VideoComment
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Avatar
            if let avatarUrl = comment.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        Circle().fill(colorScheme == .dark ? Color(white: 0.2) : Color.black.opacity(0.1))
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .overlay(Circle().stroke(ThemeColor.divider(for: colorScheme), lineWidth: 1))
            } else {
                ZStack {
                    Circle().fill(colorScheme == .dark ? Color(white: 0.25) : Color.black.opacity(0.12))
                    Text(String(comment.author.prefix(1)).uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                }
                .frame(width: 32, height: 32)
            }
            
            // Details
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.author)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
                    
                    if !comment.publishedTime.isEmpty {
                        Text("•  \(comment.publishedTime)")
                            .font(.system(size: 11))
                            .foregroundColor(ThemeColor.textTertiary(for: colorScheme))
                    }
                }
                
                Text(comment.text)
                    .font(.system(size: 12.5))
                    .lineSpacing(2.5)
                    .foregroundColor(ThemeColor.textPrimary(for: colorScheme))
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
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
                        }
                        
                        if let replies = comment.replyCount, !replies.isEmpty && replies != "0" {
                            HStack(spacing: 4) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 10))
                                Text("\(replies) phản hồi")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(ThemeColor.textSecondary(for: colorScheme))
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

