import Foundation
import AVKit
import MediaPlayer
import Combine

@MainActor
public final class PlayerManager: ObservableObject {
    public static let shared = PlayerManager()
    
    public let player: AVPlayer = AVPlayer()
    
    @Published public var currentVideo: Video?
    @Published public var isPlaying: Bool = false
    @Published public var currentTime: Double = 0
    @Published public var duration: Double = 0
    @Published public var volume: Double = 1.0 {
        didSet {
            player.volume = Float(volume)
            onVolumeChange?(volume)
        }
    }
    @Published public var isMuted: Bool = false {
        didSet { player.isMuted = isMuted }
    }
    @Published public var currentQuality: String = "1080"
    @Published public var selectedQuality: String = "auto"
    @Published public var availableQualities: [Int] = []
    @Published public var chapters: [VideoChapter] = []
    @Published public var sponsorSegments: [SponsorSegment] = []
    @Published public var isAudioOnly: Bool = false
    @Published public var bookmarkedVideos: [Video] = []
    @Published public var historyVideos: [Video] = []
    @Published public var isLoadingStream: Bool = false
    @Published public var errorMessage: String?
    @Published public var isVideoFullscreen: Bool = false
    @Published public var isCurrentVideoVertical: Bool = false
    
    // MARK: - Autoplay Next Video State
    @Published public var isAutoplayEnabled: Bool = (UserDefaults.standard.object(forKey: "auratube_autoplay") as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(isAutoplayEnabled, forKey: "auratube_autoplay")
        }
    }
    @Published public var nextVideo: Video?
    @Published public var autoplayCountdown: Int? = nil
    private var autoplayTimer: Timer? = nil
    
    // MARK: - Viewer Comments State
    public enum CommentSortMode: String, CaseIterable, Sendable {
        case top = "top"
        case newest = "newest"
        
        public var title: String {
            switch self {
            case .top: return "Hàng đầu"
            case .newest: return "Mới nhất"
            }
        }
    }
    
    @Published public var comments: [VideoComment] = []
    @Published public var isLoadingComments: Bool = false
    @Published public var isLoadingMoreComments: Bool = false
    @Published public var canLoadMoreComments: Bool = false
    @Published public var totalCommentsCountText: String? = nil
    @Published public var commentSortMode: CommentSortMode = .top
    @Published public var sortNewestToken: String? = nil
    @Published public var sortTopToken: String? = nil
    
    private var currentCommentContinuationToken: String? = nil
    private var commentsLoadingTask: Task<Void, Never>? = nil
    
    @Published public var hasActiveMainPlayer: Bool = false {
        didSet {
            for observer in muteObservers.values {
                observer(isMuted)
            }
        }
    }
    
    // Seek debounce & lock to prevent stale WebKit timeupdates from reverting the timeline
    private var isSeekingLock: Bool = false
    private var seekTargetTime: Double = 0
    private var lastSeekTimestamp: TimeInterval = 0
    private var lastMiniSyncUptime: TimeInterval = 0
    
    // Multicast bridge callbacks to active players (NativePlayerView and MenuBar MiniNativePlayerView)
    public var onPlayPause: ((Bool) -> Void)?
    public var onSeek: ((Double) -> Void)?
    public var onMuteToggle: ((Bool) -> Void)?
    public var onVolumeChange: ((Double) -> Void)?
    public var onQualityChange: ((String) -> Void)?
    
    private var playPauseObservers: [UUID: (Bool) -> Void] = [:]
    private var seekObservers: [UUID: (Double) -> Void] = [:]
    private var muteObservers: [UUID: (Bool) -> Void] = [:]
    private var qualityObservers: [UUID: (String) -> Void] = [:]
    private var timeSyncObservers: [UUID: (Double, Bool) -> Void] = [:]
    private var videoChangeObservers: [UUID: (Video, Double) -> Void] = [:]
    
    public func registerPlayPauseObserver(id: UUID, _ block: @escaping (Bool) -> Void) {
        playPauseObservers[id] = block
    }
    public func unregisterPlayPauseObserver(id: UUID) {
        playPauseObservers.removeValue(forKey: id)
    }
    
    public func registerSeekObserver(id: UUID, _ block: @escaping (Double) -> Void) {
        seekObservers[id] = block
    }
    public func unregisterSeekObserver(id: UUID) {
        seekObservers.removeValue(forKey: id)
    }
    
    public func registerMuteObserver(id: UUID, _ block: @escaping (Bool) -> Void) {
        muteObservers[id] = block
    }
    public func unregisterMuteObserver(id: UUID) {
        muteObservers.removeValue(forKey: id)
    }
    
    public func registerQualityObserver(id: UUID, _ block: @escaping (String) -> Void) {
        qualityObservers[id] = block
    }
    public func unregisterQualityObserver(id: UUID) {
        qualityObservers.removeValue(forKey: id)
    }
    
    public func registerTimeSyncObserver(id: UUID, _ block: @escaping (Double, Bool) -> Void) {
        timeSyncObservers[id] = block
    }
    public func unregisterTimeSyncObserver(id: UUID) {
        timeSyncObservers.removeValue(forKey: id)
    }
    
    public func registerVideoChangeObserver(id: UUID, _ block: @escaping (Video, Double) -> Void) {
        videoChangeObservers[id] = block
    }
    public func unregisterVideoChangeObserver(id: UUID) {
        videoChangeObservers.removeValue(forKey: id)
    }
    
    public var currentChapter: VideoChapter? {
        guard !chapters.isEmpty else { return nil }
        return chapters.first { currentTime >= $0.start && currentTime < $0.end }
    }
    
    public func chapter(at seconds: Double) -> VideoChapter? {
        guard !chapters.isEmpty else { return nil }
        return chapters.first { seconds >= $0.start && seconds < $0.end }
    }
    
    private var timeObserverToken: Any?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        loadBookmarks()
        loadHistory()
        setupTimeObserver()
        setupRemoteCommands()
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.willEnterFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.currentVideo != nil {
                    self?.isVideoFullscreen = true
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.currentVideo != nil {
                    self?.isVideoFullscreen = true
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isVideoFullscreen = false
            }
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("app.auratube.triggerAutoplay"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePlaybackEnded()
            }
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("app.auratube.testPlayVideo"),
            object: nil,
            queue: .main
        ) { [weak self] notif in
            Task { @MainActor in
                if let videoId = notif.userInfo?["videoId"] as? String {
                    let title = (notif.userInfo?["title"] as? String) ?? "Video Đang Phát"
                    let uploader = (notif.userInfo?["uploader"] as? String) ?? "AuraTube"
                    let video = Video(id: videoId, title: title, uploader: uploader, duration: 180, durationFormatted: "3:00", viewCount: 1200000, viewCountFormatted: "1.2M", publishedTime: "hôm nay")
                    self?.loadAndPlay(video: video)
                }
            }
        }
    }
    
    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
    }
    
    // MARK: - Playback Control
    
    public func toggleFullscreen() {
        let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeKey && $0.isVisible })
            ?? NSApp.mainWindow 
            ?? NSApp.keyWindow
            
        if let w = window {
            if !w.collectionBehavior.contains(.fullScreenPrimary) {
                w.collectionBehavior.insert(.fullScreenPrimary)
            }
            w.collectionBehavior.remove(.fullScreenNone)
        }
        
        isVideoFullscreen.toggle()
        
        if isVideoFullscreen {
            if let w = window, !w.styleMask.contains(.fullScreen) {
                w.toggleFullScreen(nil)
            }
        } else {
            if let w = window, w.styleMask.contains(.fullScreen) {
                w.toggleFullScreen(nil)
            }
        }
    }
    
    public func updatePlaybackSync(currentTime: Double, duration: Double, isPlaying: Bool?, isMuted: Bool?, source: String = "main") {
        let now = ProcessInfo.processInfo.systemUptime
        
        // 1. Seeking lock: prevent stale pre-seek time updates from snapping back the timeline
        if isSeekingLock {
            if abs(currentTime - seekTargetTime) < 2.5 {
                // Master player has reached the seek target and started playing! Unlock early.
                self.isSeekingLock = false
                self.currentTime = currentTime
                
                // Immediately synchronize mini player to master's exact landing frame!
                let now = ProcessInfo.processInfo.systemUptime
                lastMiniSyncUptime = now
                if hasActiveMainPlayer {
                    let playing = isPlaying ?? self.isPlaying
                    for observer in timeSyncObservers.values {
                        observer(self.currentTime, playing)
                    }
                }
            } else if now - lastSeekTimestamp > 1.2 {
                // Lock timed out
                self.isSeekingLock = false
                self.currentTime = currentTime
                
                let now = ProcessInfo.processInfo.systemUptime
                lastMiniSyncUptime = now
                if hasActiveMainPlayer {
                    let playing = isPlaying ?? self.isPlaying
                    for observer in timeSyncObservers.values {
                        observer(self.currentTime, playing)
                    }
                }
            } else {
                // Discard stale incoming update during seek lock
                return
            }
        } else {
            if source == "main" {
                // Safeguard: If the video is currently playing (> 1.0s) and an incoming update reports 0.0s,
                // discard the bogus 0.0s timestamp to eliminate timeline jitter.
                if currentTime == 0 && self.currentTime > 1.0 && (self.isPlaying || isPlaying == true) {
                    // Bogus uninitialized 0.0s update ignored
                } else {
                    self.currentTime = currentTime
                }
                
                let now = ProcessInfo.processInfo.systemUptime
                // Fast convergence phase for 2.5s post-seek: sync every 150ms to lockstep eliminate any ms drift!
                let isPostSeekConvergence = (now - lastSeekTimestamp < 2.5)
                let syncInterval = isPostSeekConvergence ? 0.15 : 0.8
                
                if hasActiveMainPlayer && (now - lastMiniSyncUptime >= syncInterval) {
                    lastMiniSyncUptime = now
                    let playing = self.isPlaying
                    for observer in timeSyncObservers.values {
                        observer(self.currentTime, playing)
                    }
                }
            } else if source == "mini" {
                // If main player is NOT active, mini player is the master clock
                if !hasActiveMainPlayer {
                    self.currentTime = currentTime
                } else {
                    // Main player is active: only accept mini time if main player is NOT playing
                    // and mini time jumped by more than 3s (e.g. user dragged mini slider)
                    if !self.isPlaying && abs(self.currentTime - currentTime) > 3.0 {
                        self.currentTime = currentTime
                    }
                }
            }
        }
        
        if duration > 0 {
            if self.duration == 0 || abs(self.duration - duration) > 1.0 {
                self.duration = duration
            }
        }
        
        // 2. Play/pause synchronization
        if let playing = isPlaying {
            if source == "main" {
                if playing != self.isPlaying {
                    self.isPlaying = playing
                    // Notify mini player observers to match main player state
                    for observer in playPauseObservers.values {
                        observer(playing)
                    }
                }
            } else if source == "mini" {
                if !hasActiveMainPlayer {
                    // When main player is not active, mini player controls play/pause
                    if playing != self.isPlaying {
                        self.isPlaying = playing
                    }
                } else {
                    // When main player IS active:
                    // If main player is playing, but mini reports false (e.g. buffering/unstarted),
                    // NEVER allow mini to pause the main player!
                    // Instead, tell mini player to catch up and play!
                    if self.isPlaying && !playing {
                        for observer in playPauseObservers.values {
                            observer(true)
                        }
                    }
                }
            }
        }
        
        // Note: PlayerManager is the authoritative source of truth for isMuted.
        // Asynchronous WebKit events are ignored here to prevent mute/unmute flickering.
        updateNowPlaying()
        
        // 3. Fallback end-of-video check for Autoplay
        if isAutoplayEnabled && duration > 5 && currentTime >= (duration - 0.8) && !isSeekingLock {
            if isPlaying == false || abs(currentTime - duration) < 0.25 {
                handlePlaybackEnded()
            }
        }
    }
    
    public func loadAndPlay(video: Video, quality: String = "1080", startTime: Double = 0) {
        cancelAutoplay()
        commentsLoadingTask?.cancel()
        self.currentVideo = video
        self.isCurrentVideoVertical = video.isShort
        self.selectedQuality = "auto"
        self.currentQuality = quality
        self.availableQualities = []
        self.currentTime = startTime
        self.duration = video.totalDurationSeconds
        self.chapters = []
        self.comments = []
        self.isLoadingComments = true
        self.isLoadingMoreComments = false
        self.canLoadMoreComments = false
        self.totalCommentsCountText = nil
        self.isLoadingStream = false
        self.isPlaying = true
        self.isMuted = false
        self.volume = 1.0
        self.errorMessage = nil
        self.addToHistory(video)
        
        onPlayPause?(true)
        for observer in playPauseObservers.values {
            observer(true)
        }
        for observer in videoChangeObservers.values {
            observer(video, startTime)
        }
        
        // Start streaming all viewer comments in background
        self.startLoadingComments(for: video.id)
        
        Task {
            // 1. Fetch SponsorBlock segments
            let segments = await SponsorBlockService.shared.fetchSegments(videoId: video.id)
            if self.currentVideo?.id == video.id {
                self.sponsorSegments = segments
            }
            
            // 2. Fetch full metadata, heights, and chapters in the background
            let details = await YTDLPService.shared.fetchVideoDetailsAndChapters(videoId: video.id, duration: self.duration)
            if self.currentVideo?.id == video.id {
                if !details.heights.isEmpty {
                    self.availableQualities = details.heights
                }
                self.currentVideo?.description = details.desc
                self.chapters = details.chapters
                self.updateNowPlaying()
            }
        }
    }
    
    // MARK: - Viewer Comments Loading (Streaming All Comments)
    
    public func startLoadingComments(for videoId: String, initialToken: String? = nil) {
        commentsLoadingTask?.cancel()
        commentsLoadingTask = Task { @MainActor in
            self.comments = []
            self.isLoadingComments = true
            self.isLoadingMoreComments = false
            self.canLoadMoreComments = false
            self.currentCommentContinuationToken = nil
            if initialToken == nil {
                self.totalCommentsCountText = nil
                self.sortNewestToken = nil
                self.sortTopToken = nil
            }
            
            // 1. Fetch first batch
            let firstBatch = await YTDLPService.shared.fetchCommentsBatch(
                videoId: initialToken == nil ? videoId : nil,
                continuationToken: initialToken
            )
            
            guard !Task.isCancelled, self.currentVideo?.id == videoId else { return }
            
            self.comments = firstBatch.comments
            self.isLoadingComments = false
            if let total = firstBatch.totalCountText, !total.isEmpty {
                self.totalCommentsCountText = total
            }
            if let newest = firstBatch.sortNewestToken {
                self.sortNewestToken = newest
            }
            if let top = firstBatch.sortTopToken {
                self.sortTopToken = top
            }
            self.currentCommentContinuationToken = firstBatch.nextToken
            self.canLoadMoreComments = firstBatch.nextToken != nil
            
            // 2. Automatically continue streaming remaining comments progressively in background
            var currentToken = firstBatch.nextToken
            var seenIds = Set(firstBatch.comments.map { $0.id })
            
            while let token = currentToken, !Task.isCancelled, self.currentVideo?.id == videoId {
                self.isLoadingMoreComments = true
                
                // Gentle sleep between requests to avoid rate limits and let UI render
                try? await Task.sleep(nanoseconds: 180_000_000)
                if Task.isCancelled || self.currentVideo?.id != videoId { break }
                
                let nextBatch = await YTDLPService.shared.fetchCommentsBatch(continuationToken: token)
                if Task.isCancelled || self.currentVideo?.id != videoId { break }
                
                if nextBatch.comments.isEmpty && nextBatch.nextToken == nil {
                    currentToken = nil
                    self.currentCommentContinuationToken = nil
                    self.canLoadMoreComments = false
                    break
                }
                
                var newComments: [VideoComment] = []
                for c in nextBatch.comments {
                    if !seenIds.contains(c.id) {
                        seenIds.insert(c.id)
                        newComments.append(c)
                    }
                }
                
                if !newComments.isEmpty {
                    self.comments.append(contentsOf: newComments)
                }
                
                if let total = nextBatch.totalCountText, !total.isEmpty {
                    self.totalCommentsCountText = total
                }
                if let newest = nextBatch.sortNewestToken {
                    self.sortNewestToken = newest
                }
                if let top = nextBatch.sortTopToken {
                    self.sortTopToken = top
                }
                
                currentToken = nextBatch.nextToken
                self.currentCommentContinuationToken = nextBatch.nextToken
                self.canLoadMoreComments = nextBatch.nextToken != nil
            }
            
            self.isLoadingMoreComments = false
        }
    }
    
    public func switchCommentSort(to mode: CommentSortMode) {
        guard mode != commentSortMode, let video = currentVideo else { return }
        self.commentSortMode = mode
        let tokenToUse: String? = (mode == .newest) ? sortNewestToken : sortTopToken
        startLoadingComments(for: video.id, initialToken: tokenToUse)
    }
    
    public func loadMoreComments() {
        guard !isLoadingComments, !isLoadingMoreComments, let token = currentCommentContinuationToken, let videoId = currentVideo?.id else { return }
        
        Task { @MainActor in
            self.isLoadingMoreComments = true
            let nextBatch = await YTDLPService.shared.fetchCommentsBatch(continuationToken: token)
            guard !Task.isCancelled, self.currentVideo?.id == videoId else { return }
            
            var seenIds = Set(self.comments.map { $0.id })
            var newComments: [VideoComment] = []
            for c in nextBatch.comments {
                if !seenIds.contains(c.id) {
                    seenIds.insert(c.id)
                    newComments.append(c)
                }
            }
            
            if !newComments.isEmpty {
                self.comments.append(contentsOf: newComments)
            }
            if let total = nextBatch.totalCountText, !total.isEmpty {
                self.totalCommentsCountText = total
            }
            if let newest = nextBatch.sortNewestToken {
                self.sortNewestToken = newest
            }
            if let top = nextBatch.sortTopToken {
                self.sortTopToken = top
            }
            self.currentCommentContinuationToken = nextBatch.nextToken
            self.canLoadMoreComments = nextBatch.nextToken != nil
            self.isLoadingMoreComments = false
        }
    }
    
    public func refreshComments() {
        guard let video = currentVideo else { return }
        let tokenToUse: String? = (commentSortMode == .newest) ? sortNewestToken : nil
        startLoadingComments(for: video.id, initialToken: tokenToUse)
    }
    
    public func setQuality(_ quality: String) {
        self.selectedQuality = quality
        if quality != "auto" {
            self.currentQuality = quality
        }
        onQualityChange?(quality)
        for observer in qualityObservers.values {
            observer(quality)
        }
    }
    
    public func togglePlayPause() {
        isPlaying.toggle()
        onPlayPause?(isPlaying)
        for observer in playPauseObservers.values {
            observer(isPlaying)
        }
        
        let cmd = isPlaying ? "playVideo" : "pauseVideo"
        let js = """
        var ifr = document.getElementById('ytPlayer');
        if (ifr && ifr.contentWindow) {
            ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "\(cmd)", args: []}), '*');
        }
        """
        MainWebPlayerPool.shared.webView?.evaluateJavaScript(js, completionHandler: nil)
        
        if isPlaying {
            player.play()
        } else {
            player.pause()
        }
        updateNowPlaying()
    }
    
    public func seek(to seconds: Double) {
        let maxD = duration > 0 ? duration : 86400
        let clampedTime = max(0, min(maxD, seconds))
        
        self.currentTime = clampedTime
        self.seekTargetTime = clampedTime
        self.lastSeekTimestamp = ProcessInfo.processInfo.systemUptime
        self.isSeekingLock = true
        
        onSeek?(clampedTime)
        for observer in seekObservers.values {
            observer(clampedTime)
        }
        let time = CMTime(seconds: clampedTime, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
        
        // Auto release seek lock after 1.2s max
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self else { return }
            if ProcessInfo.processInfo.systemUptime - self.lastSeekTimestamp >= 1.1 {
                self.isSeekingLock = false
            }
        }
    }
    
    public func seekRelative(_ offset: Double) {
        let maxD = duration > 0 ? duration : 86400
        let newTime = max(0, min(maxD, currentTime + offset))
        seek(to: newTime)
    }
    
    public func toggleMute() {
        isMuted.toggle()
        onMuteToggle?(isMuted)
        for observer in muteObservers.values {
            observer(isMuted)
        }
    }
    
    public func changeQuality(_ quality: String) {
        guard let video = currentVideo else { return }
        let currentPos = currentTime
        loadAndPlay(video: video, quality: quality, startTime: currentPos)
    }
    
    public func stop() {
        cancelAutoplay()
        commentsLoadingTask?.cancel()
        commentsLoadingTask = nil
        comments = []
        isLoadingComments = false
        isLoadingMoreComments = false
        canLoadMoreComments = false
        totalCommentsCountText = nil
        currentCommentContinuationToken = nil
        isVideoFullscreen = false
        isPlaying = false
        currentVideo = nil
        currentTime = 0
        duration = 0
        hasActiveMainPlayer = false
        player.pause()
        onPlayPause?(false)
        for observer in playPauseObservers.values {
            observer(false)
        }
        updateNowPlaying()
    }
    
    // MARK: - Autoplay Control Methods
    
    public func toggleAutoplay() {
        isAutoplayEnabled.toggle()
        if !isAutoplayEnabled {
            cancelAutoplay()
        }
    }
    
    public func handlePlaybackEnded() {
        guard isAutoplayEnabled else { return }
        guard autoplayCountdown == nil else { return }
        guard let cur = currentVideo else { return }
        
        // If next video is not yet set or points to current video, find related one
        if nextVideo == nil || nextVideo?.id == cur.id {
            Task {
                let related = await YTDLPService.shared.searchVideos(query: cur.uploader)
                if let firstNext = related.first(where: { $0.id != cur.id }) {
                    self.nextVideo = firstNext
                    self.startAutoplayCountdown()
                }
            }
            return
        }
        
        startAutoplayCountdown()
    }
    
    public func startAutoplayCountdown() {
        cancelAutoplay()
        guard isAutoplayEnabled, nextVideo != nil else { return }
        self.autoplayCountdown = 5
        
        self.autoplayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                guard self.isAutoplayEnabled else {
                    self.cancelAutoplay()
                    return
                }
                if let count = self.autoplayCountdown {
                    if count > 1 {
                        self.autoplayCountdown = count - 1
                    } else {
                        self.playNextVideo()
                    }
                } else {
                    timer.invalidate()
                }
            }
        }
    }
    
    public func cancelAutoplay() {
        autoplayTimer?.invalidate()
        autoplayTimer = nil
        autoplayCountdown = nil
    }
    
    public func playNextVideo() {
        cancelAutoplay()
        guard let next = nextVideo else { return }
        self.nextVideo = nil
        self.loadAndPlay(video: next)
    }
    
    // MARK: - Bookmarks & History
    
    public func isBookmarked(_ video: Video) -> Bool {
        bookmarkedVideos.contains(where: { $0.id == video.id })
    }
    
    public func toggleBookmark(_ video: Video) {
        if let idx = bookmarkedVideos.firstIndex(where: { $0.id == video.id }) {
            bookmarkedVideos.remove(at: idx)
        } else {
            bookmarkedVideos.insert(video, at: 0)
        }
        saveBookmarks()
    }
    
    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarkedVideos) {
            UserDefaults.standard.set(data, forKey: "auratube_bookmarks")
        }
    }
    
    private func loadBookmarks() {
        if let data = UserDefaults.standard.data(forKey: "auratube_bookmarks"),
           let list = try? JSONDecoder().decode([Video].self, from: data) {
            self.bookmarkedVideos = list
        }
    }
    
    private func addToHistory(_ video: Video) {
        historyVideos.removeAll(where: { $0.id == video.id })
        historyVideos.insert(video, at: 0)
        if historyVideos.count > 50 { historyVideos.removeLast() }
        if let data = try? JSONEncoder().encode(historyVideos) {
            UserDefaults.standard.set(data, forKey: "auratube_history")
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "auratube_history"),
           let list = try? JSONDecoder().decode([Video].self, from: data) {
            self.historyVideos = list
        }
    }
    
    // MARK: - Time Observation & SponsorBlock
    
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // AVPlayer is only active in audio-only streaming mode. If no item is loaded, ignore!
                guard let item = self.player.currentItem, item.status == .readyToPlay else { return }
                let seconds = time.seconds
                if !seconds.isNaN {
                    self.currentTime = seconds
                    
                    if item.duration.isValid {
                        let d = item.duration.seconds
                        if !d.isNaN { self.duration = d }
                    }
                    
                    // SponsorBlock check
                    for segment in self.sponsorSegments {
                        if seconds >= segment.start && seconds < (segment.end - 0.2) {
                            let target = CMTime(seconds: segment.end + 0.1, preferredTimescale: 600)
                            self.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                            break
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - macOS Now Playing & Media Keys
    
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayPause()
            }
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayPause()
            }
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayPause()
            }
            return .success
        }
        
        commandCenter.skipForwardCommand.preferredIntervals = [10]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.seekRelative(10)
            }
            return .success
        }
        
        commandCenter.skipBackwardCommand.preferredIntervals = [10]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.seekRelative(-10)
            }
            return .success
        }
    }
    
    private func updateNowPlaying() {
        guard let video = currentVideo else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: video.title,
            MPMediaItemPropertyArtist: video.uploader,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration > 0 ? duration : (video.duration ?? 0),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
