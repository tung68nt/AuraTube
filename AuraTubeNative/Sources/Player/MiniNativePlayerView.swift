import SwiftUI
import AppKit
import WebKit

// MARK: - MiniPlayerEngine: Persistent Dual-Player Engine
@MainActor
public final class MiniPlayerEngine: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    public static let shared = MiniPlayerEngine()
    
    public let webView: WKWebView
    private let offscreenWindow: NSWindow
    private let observerId = UUID()
    public private(set) var currentLoadedVideoId: String?
    public private(set) var isPopoverVisible: Bool = false
    private var pendingVideo: (video: Video, startPos: Double)? = nil
    
    public override init() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = false
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
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
        
        let cleanScript = """
        (function() {
            function applyStyles() {
                if (!document.getElementById('auratube-mini-clean-style')) {
                    var s = document.createElement('style');
                    s.id = 'auratube-mini-clean-style';
                    s.innerHTML = `
                        .ytPlayerOverlayVideoDetailsRendererHost,
                        .ytPlayerOverlayVideoDetailsRendererTitle,
                        .ytPlayerOverlayVideoDetailsRendererSubtitle,
                        .ytPlayerOverlayVideoDetailsRendererChannelAvatarContainer,
                        .ytPlayerOverlayVideoDetailsRendererTextContainer,
                        .ytPlayerOverlayVideoDetailsRendererFrostedGlass,
                        [class*="ytPlayerOverlayVideoDetailsRenderer"],
                        [class*="ytwPlayerTopControls"],
                        [class*="ytmWatchPlayerControls"],
                        [class*="ytmVideoInfo"],
                        [class*="VideoDetailsRenderer"],
                        ytw-player-top-controls,
                        yt-player-overlay-video-details-renderer,
                        ytm-video-info-flyout,
                        .ytwPlayerTopControlsHost,
                        .ytmWatchPlayerControlsHost,
                        .ytp-chrome-bottom,
                        .ytp-chrome-top,
                        .ytp-gradient-top,
                        .ytp-gradient-bottom,
                        .ytp-title,
                        .ytp-title-channel,
                        .ytp-title-channel-logo,
                        .ytp-title-text,
                        .ytp-title-subtext,
                        .ytp-title-expanded-title,
                        .ytp-title-link,
                        a.ytp-title-link,
                        a.ytp-title-channel,
                        [class*="title-channel"],
                        [class*="ytp-title"],
                        [class*="channel-logo"],
                        [class*="channel-name"],
                        [class*="channel-avatar"],
                        [class*="chrome-top"],
                        [class*="cairo-refresh"],
                        .ytp-watermark,
                        .ytp-youtube-button,
                        a.ytp-youtube-button,
                        .ytp-large-play-button,
                        .ytp-button.ytp-large-play-button-bg,
                        .ytp-pause-overlay,
                        .ytp-cards-teaser,
                        .ytp-ce-element,
                        [class*="watermark"],
                        [class*="youtube-button"],
                        [class*="cards-teaser"],
                        [class*="pause-overlay"],
                        .ytp-suggested-action-badge,
                        .ytp-suggested-action-badge-container,
                        .ytp-suggested-action,
                        .ytp-ai-info-dialog,
                        .ytp-content-disclosure,
                        .ytp-popup,
                        .ytp-panel-popup,
                        [class*="ai-disclosure"],
                        [class*="content-disclosure"],
                        [class*="suggested-action"],
                        [aria-label*="AI" i],
                        [aria-label*="Made with AI" i],
                        [aria-label*="Được tạo bằng AI" i],
                        [aria-label*="Nội dung do AI" i],
                        [title*="AI" i],
                        [title*="Made with AI" i],
                        .ytp-paid-content-overlay,
                        .ytp-paid-content-overlay-link,
                        .ytp-paid-content-overlay-text,
                        .ytp-paid-content-overlay-icon,
                        .ytp-paid-content-overlay-chevron,
                        .ytm-paid-content-overlay-renderer,
                        .YtmPaidContentOverlayHost,
                        [class*="paid-content"],
                        [class*="paid-promotion"],
                        [aria-label*="paid promotion" i],
                        [aria-label*="paid-promotion" i],
                        [aria-label*="quảng cáo" i],
                        [aria-label*="quảng bá" i],
                        [title*="paid promotion" i],
                        a[href*="support.google.com/youtube?p=ppp"],
                        a[href*="support.google.com/youtube/answer/154235"],
                        .ytp-spinner,
                        .ytp-spinner-container,
                        .ytp-spinner-rotator,
                        .ytp-spinner-left,
                        .ytp-spinner-right,
                        .ytp-bezel,
                        .ytp-bezel-icon,
                        .ytp-bezel-text,
                        [class*="ytp-spinner"],
                        [class*="spinner-container"],
                        [class*="bezel"] {
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
                        body, html { margin: 0; padding: 0; background: #000; overflow: hidden; width: 100%; height: 100%; pointer-events: none !important; }
                        iframe { width: 100%; height: 100%; border: none; display: block; pointer-events: none !important; }
                        .html5-video-player,
                        .html5-video-container {
                            width: 100% !important;
                            height: 100% !important;
                            overflow: hidden !important;
                            background: #000 !important;
                            pointer-events: none !important;
                        }
                        video.video-stream.html5-main-video,
                        video.html5-main-video,
                        video {
                            object-fit: contain !important;
                            width: 100% !important;
                            height: 100% !important;
                            top: 0 !important;
                            left: 0 !important;
                            border-radius: 0 !important;
                            background: #000 !important;
                            pointer-events: none !important;
                        }
                    `;
                    (document.head || document.documentElement).appendChild(s);
                }

                try {
                    var badges = document.querySelectorAll(
                        '.ytPlayerOverlayVideoDetailsRendererHost, [class*="ytPlayerOverlayVideoDetailsRenderer"], [class*="ytwPlayerTopControls"], [class*="ytmWatchPlayerControls"], [class*="ytmVideoInfo"], [class*="VideoDetailsRenderer"], ytw-player-top-controls, yt-player-overlay-video-details-renderer, ytm-video-info-flyout, .ytwPlayerTopControlsHost, .ytmWatchPlayerControlsHost, ' +
                        '.ytp-paid-content-overlay, .ytp-paid-content-overlay-link, [class*="paid-content"], [class*="paid-promotion"], ' +
                        'a[href*="support.google.com/youtube?p=ppp"], .ytp-suggested-action-badge, .ytp-suggested-action, .ytp-ai-info-dialog, ' +
                        '[class*="ai-disclosure"], [aria-label*="AI" i], .ytp-popup, .ytp-chrome-top, .ytp-gradient-top, ' +
                        '.ytp-title, .ytp-title-channel, .ytp-title-channel-logo, [class*="title-channel"], [class*="channel-logo"], [class*="channel-name"], [class*="channel-avatar"], [class*="cairo-refresh"], .ytp-spinner, .ytp-spinner-container, .ytp-bezel'
                    );
                    for (var b = 0; b < badges.length; b++) {
                        badges[b].remove();
                    }
                } catch(e) {}
            }
            applyStyles();
            var obs = new MutationObserver(applyStyles);
            if (document.documentElement) {
                obs.observe(document.documentElement, { childList: true, subtree: true });
            }
            function enforceMute() {
                try {
                    var media = document.querySelectorAll('video, audio');
                    for (var i = 0; i < media.length; i++) {
                        if (!media[i].muted) media[i].muted = true;
                        if (media[i].volume > 0) media[i].volume = 0;
                    }
                } catch(e) {}
            }
            enforceMute();


            function reportVideoDimensions() {
                try {
                    var v = document.querySelector('video');
                    if (v && v.videoWidth > 0 && v.videoHeight > 0) {
                        var isVertical = v.videoHeight > v.videoWidth;
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.miniPlayerBridge) {
                            window.webkit.messageHandlers.miniPlayerBridge.postMessage({
                                type: 'videoDimensions',
                                isVertical: isVertical,
                                width: v.videoWidth,
                                height: v.videoHeight
                            });
                        }
                    }
                } catch(e) {}
            }
            document.addEventListener('loadedmetadata', reportVideoDimensions, true);
            document.addEventListener('resize', reportVideoDimensions, true);

            document.addEventListener('play', function(e) {
                if (e.target && (e.target.tagName === 'VIDEO' || e.target.tagName === 'AUDIO')) {
                    e.target.muted = true;
                    e.target.volume = 0;
                }
                enforceLowQuality();
                reportVideoDimensions();
            }, true);

            // Rock-Solid, Butter-Smooth 60fps Dual-Player Phase-Locked Synchronizer
            var isSeekingState = false;
            var lastSeekTimestamp = 0;

            function handleSync(data) {
                try {
                    var v = document.querySelector('video');
                    if (!v) return;
                    
                    if (!v.muted) v.muted = true;
                    if (v.volume > 0) v.volume = 0;
                    
                    var targetTime = data.masterTime;
                    var shouldPlay = data.isPlaying === true;
                    var forceSnap = data.forceSnap === true;
                    var now = performance.now();
                    
                    // 1. Play / Pause state sync
                    if (shouldPlay && v.paused && !isSeekingState) {
                        v.play().catch(function(){});
                    } else if (!shouldPlay && !v.paused) {
                        v.pause();
                    }
                    
                    if (typeof targetTime !== 'number' || targetTime < 0) return;
                    
                    var diff = targetTime - v.currentTime;
                    var absDiff = Math.abs(diff);
                    
                    // 2. Explicit force snap (User scrubbed slider, opened popover, or switched video)
                    if (forceSnap) {
                        if (absDiff > 0.08 || v.paused) {
                            isSeekingState = true;
                            lastSeekTimestamp = now;
                            v.currentTime = targetTime;
                            v.playbackRate = 1.0;
                        }
                        return;
                    }
                    
                    // If video is paused, only snap if offset is noticeable (> 80ms)
                    if (!shouldPlay || v.paused) {
                        if (absDiff > 0.08 && !isSeekingState && (now - lastSeekTimestamp > 800)) {
                            isSeekingState = true;
                            lastSeekTimestamp = now;
                            v.currentTime = targetTime;
                            v.playbackRate = 1.0;
                        }
                        return;
                    }
                    
                    // 3. Active Playback Synchronization:
                    // If currently seeking or within the 1.5s post-seek stabilization window:
                    // DO NOT adjust playbackRate or seek again! Let video play smoothly!
                    if (isSeekingState || (now - lastSeekTimestamp < 1500)) {
                        v.playbackRate = 1.0;
                        return;
                    }
                    
                    // A. Emergency Hard Resync: only if drift is massive (> 2.5s) AND at least 3.5s since last seek
                    if (absDiff > 2.5 && (now - lastSeekTimestamp > 3500)) {
                        isSeekingState = true;
                        lastSeekTimestamp = now;
                        v.currentTime = targetTime;
                        v.playbackRate = 1.0;
                        return;
                    }
                    
                    // B. Deadband: within 75ms (< 2 frames), video is in perfect perceptual sync.
                    // Absolutely keep at pure 1.00x native 60fps! Zero stutter!
                    if (absDiff <= 0.075) {
                        if (v.playbackRate !== 1.0) {
                            v.playbackRate = 1.0;
                        }
                        return;
                    }
                    
                    // C. Micro proportional rate steering:
                    // For differences between 75ms and 600ms, apply tiny imperceptible ±3.5% adjustment.
                    // For differences between 600ms and 2500ms, apply ±6% adjustment max.
                    var kP = 0.12;
                    var correction = diff * kP;
                    var maxAdj = (absDiff > 0.6) ? 0.06 : 0.035;
                    correction = Math.max(-maxAdj, Math.min(maxAdj, correction));
                    
                    v.playbackRate = 1.0 + correction;
                } catch(err) {}
            }

            window.addEventListener('message', function(e) {
                try {
                    var data = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
                    if (!data || data.event !== 'auratube_sync') return;
                    handleSync(data);
                } catch(err) {}
            });

            function hookVideoSyncEvents() {
                try {
                    var v = document.querySelector('video');
                    if (!v || v.__auratube_synchooked) return;
                    v.__auratube_synchooked = true;
                    
                    v.addEventListener('seeking', function() {
                        isSeekingState = true;
                    });
                    v.addEventListener('seeked', function() {
                        isSeekingState = false;
                        lastSeekTimestamp = performance.now();
                        v.playbackRate = 1.0;
                    });
                    v.addEventListener('volumechange', function() {
                        if (!v.muted) v.muted = true;
                        if (v.volume > 0) v.volume = 0;
                    });
                    v.addEventListener('play', function() {
                        if (!v.muted) v.muted = true;
                        if (v.volume > 0) v.volume = 0;
                    });
                } catch(e) {}
            }
            hookVideoSyncEvents();
            setInterval(hookVideoSyncEvents, 800);

            window.addEventListener('keydown', function(e) {
                if (e.code === 'Space' || e.keyCode === 32) {
                    e.preventDefault();
                    e.stopPropagation();
                    try {
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.miniPlayerBridge) {
                            window.webkit.messageHandlers.miniPlayerBridge.postMessage({ type: 'togglePlayPause' });
                        }
                    } catch(err) {}
                }
            }, true);

            window.addEventListener('click', function(e) {
                e.preventDefault();
                e.stopPropagation();
                try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.miniPlayerBridge) {
                        window.webkit.messageHandlers.miniPlayerBridge.postMessage({ type: 'togglePlayPause' });
                    }
                } catch(err) {}
            }, true);
        })();
        """
        let userScriptStart = WKUserScript(source: cleanScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        let userScriptEnd = WKUserScript(source: cleanScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        contentController.addUserScript(userScriptStart)
        contentController.addUserScript(userScriptEnd)
        config.userContentController = contentController
        
        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 288, height: 162), configuration: config)
        
        // Persistent standby window to keep WebKit media playback alive continuously in parallel.
        // Intersects screen coordinates with 0.002 alpha so WindowServer & WebKit do NOT throttle video decoding/timers!
        let offscreen = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 288, height: 162),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        offscreen.isReleasedWhenClosed = false
        offscreen.alphaValue = 0.002
        offscreen.ignoresMouseEvents = true
        offscreen.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        offscreen.contentView?.addSubview(self.webView)
        offscreen.orderBack(nil)
        self.offscreenWindow = offscreen
        
        super.init()
        
        contentController.add(self, contentWorld: .page, name: "miniPlayerBridge")
        contentController.add(self, contentWorld: .defaultClient, name: "miniPlayerBridge")
        self.webView.navigationDelegate = self
        
        setupPlayerManagerBridge()
    }
    
    private func setupPlayerManagerBridge() {
        let pm = PlayerManager.shared
        
        // 1. Play / Pause observer: instant simultaneous sync (only when popover is visible)
        pm.registerPlayPauseObserver(id: observerId) { [weak self] shouldPlay in
            guard let self = self, self.isPopoverVisible else { return }
            let masterTime = PlayerManager.shared.currentTime
            let cmd = shouldPlay ? "playVideo" : "pauseVideo"
            let js = """
            (function() {
                var ifr = document.getElementById('miniYtPlayer');
                if (ifr && ifr.contentWindow) {
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "\(cmd)", args: []}), '*');
                    ifr.contentWindow.postMessage(JSON.stringify({
                        event: 'auratube_sync',
                        masterTime: \(masterTime),
                        isPlaying: \(shouldPlay),
                        forceSnap: false
                    }), '*');
                }
                var v = document.querySelector('video');
                if (v) {
                    if (\(shouldPlay)) {
                        v.play().catch(function(){});
                    } else {
                        v.pause();
                    }
                }
            })();
            """
            self.webView.evaluateJavaScript(js, completionHandler: nil)
        }
        
        // 2. Seek observer: only when popover is visible
        pm.registerSeekObserver(id: observerId) { [weak self] targetSeconds in
            guard let self = self, self.isPopoverVisible else { return }
            let shouldPlayImmediately = !PlayerManager.shared.hasActiveMainPlayer && PlayerManager.shared.isPlaying
            let js = """
            (function() {
                var ifr = document.getElementById('miniYtPlayer');
                if (ifr && ifr.contentWindow) {
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "seekTo", args: [\(targetSeconds), true]}), '*');
                    if (!\(shouldPlayImmediately)) {
                        ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "pauseVideo", args: []}), '*');
                    }
                    ifr.contentWindow.postMessage(JSON.stringify({
                        event: 'auratube_sync',
                        masterTime: \(targetSeconds),
                        isPlaying: \(shouldPlayImmediately),
                        forceSnap: true
                    }), '*');
                }
                var v = document.querySelector('video');
                if (v) {
                    v.currentTime = \(targetSeconds);
                    if (!\(shouldPlayImmediately)) {
                        v.pause();
                    }
                }
            })();
            """
            self.webView.evaluateJavaScript(js, completionHandler: nil)
        }
        
        // 3. Time sync observer: only sync when popover is actually visible
        pm.registerTimeSyncObserver(id: observerId) { [weak self] masterTime, isPlaying in
            guard let self = self, self.isPopoverVisible else { return }
            let js = """
            (function() {
                var ifr = document.getElementById('miniYtPlayer');
                if (ifr && ifr.contentWindow) {
                    if (!\(isPlaying)) {
                        ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "pauseVideo", args: []}), '*');
                    }
                    ifr.contentWindow.postMessage(JSON.stringify({
                        event: 'auratube_sync',
                        masterTime: \(masterTime),
                        isPlaying: \(isPlaying),
                        forceSnap: false
                    }), '*');
                }
            })();
            """
            self.webView.evaluateJavaScript(js, completionHandler: nil)
        }
        
        // 4. Mute observer: mini player is strictly a visual preview and must ALWAYS remain muted to prevent echo
        pm.registerMuteObserver(id: observerId) { [weak self] _ in
            guard let self = self else { return }
            let js = """
            (function() {
                var ifr = document.getElementById('miniYtPlayer');
                if (ifr && ifr.contentWindow) {
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "mute", args: []}), '*');
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setVolume", args: [0]}), '*');
                }
            })();
            """
            self.webView.evaluateJavaScript(js, completionHandler: nil)
        }
        
        // 5. Video change observer: only loads and starts playing if popover is visible!
        pm.registerVideoChangeObserver(id: observerId) { [weak self] newVideo, startTime in
            guard let self = self else { return }
            if self.isPopoverVisible {
                self.loadVideo(video: newVideo, startPos: startTime)
            } else {
                self.pendingVideo = (newVideo, startTime)
            }
        }
        
        // If a video is already active and popover is visible, load it; otherwise save as pending
        if let current = pm.currentVideo {
            if isPopoverVisible {
                loadVideo(video: current, startPos: pm.currentTime)
            } else {
                pendingVideo = (current, pm.currentTime)
            }
        }
        
        // Handle MenuBar popover notifications:
        // Popover closed: move webView back to standby window and pause video to eliminate CPU/GPU/network drain!
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AuraTubeMenuBarPopoverClosed"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isPopoverVisible = false
                self.detachToOffscreen()
                let js = """
                (function() {
                    var ifr = document.getElementById('miniYtPlayer');
                    if (ifr && ifr.contentWindow) {
                        ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "pauseVideo", args: []}), '*');
                    }
                    var v = document.querySelector('video');
                    if (v) { v.pause(); }
                })();
                """
                self.webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }
        
        // Popover opened: snap smoothly to master playback frame
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AuraTubeMenuBarPopoverShown"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isPopoverVisible = true
                let pm = PlayerManager.shared
                
                if let current = pm.currentVideo, self.currentLoadedVideoId != current.id {
                    self.loadVideo(video: current, startPos: pm.currentTime)
                } else if let pending = self.pendingVideo {
                    self.loadVideo(video: pending.video, startPos: pending.startPos)
                } else {
                    let shouldPlay = pm.isPlaying
                    let js = """
                    (function() {
                        var ifr = document.getElementById('miniYtPlayer');
                        if (ifr && ifr.contentWindow) {
                            ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "mute", args: []}), '*');
                            ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setVolume", args: [0]}), '*');
                            ifr.contentWindow.postMessage(JSON.stringify({
                                event: 'auratube_sync',
                                masterTime: \(pm.currentTime),
                                isPlaying: \(shouldPlay),
                                forceSnap: true
                            }), '*');
                            if (\(shouldPlay)) {
                                ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "playVideo", args: []}), '*');
                            }
                        }
                    })();
                    """
                    self.webView.evaluateJavaScript(js, completionHandler: nil)
                }
            }
        }
    }
    
    public func loadVideo(video: Video, startPos: Double = 0) {
        if !isPopoverVisible {
            pendingVideo = (video, startPos)
            return
        }
        guard currentLoadedVideoId != video.id else { return }
        currentLoadedVideoId = video.id
        pendingVideo = nil
        
        let pos = max(0, Int(startPos))
        let html = generateHTML(for: video, startPos: pos)
        webView.loadHTMLString(html, baseURL: URL(string: "https://auratube.app"))
    }
    
    public func stop() {
        currentLoadedVideoId = nil
        let js = """
        (function() {
            try {
                var ifr = document.getElementById('miniYtPlayer');
                if (ifr && ifr.contentWindow) {
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "mute", args: []}), '*');
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "pauseVideo", args: []}), '*');
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "stopVideo", args: []}), '*');
                }
                var medias = document.querySelectorAll('video, audio');
                for (var i = 0; i < medias.length; i++) {
                    medias[i].pause();
                    medias[i].muted = true;
                    medias[i].src = '';
                    medias[i].load();
                }
            } catch(e) {}
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
        webView.stopLoading()
        webView.loadHTMLString("<!DOCTYPE html><html><body style='background:#000;'></body></html>", baseURL: nil)
        detachToOffscreen()
    }
    
    public func attach(to container: NSView) {
        isPopoverVisible = true
        if webView.superview != container {
            webView.removeFromSuperview()
            container.addSubview(webView)
        }
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
    }
    
    public func detachToOffscreen() {
        isPopoverVisible = false
        if webView.superview != offscreenWindow.contentView {
            webView.removeFromSuperview()
            offscreenWindow.contentView?.addSubview(webView)
            webView.frame = NSRect(x: 0, y: 0, width: 288, height: 162)
            offscreenWindow.orderBack(nil)
        }
    }
    
    private func generateHTML(for video: Video, startPos: Int) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <meta name="referrer" content="origin">
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; background: #000; overflow: hidden; pointer-events: none !important; }
          html, body { width: 100%; height: 100%; background: #000; overflow: hidden; pointer-events: none !important; }
          iframe { 
            position: absolute; 
            top: 0; 
            left: 0; 
            width: 100%; 
            height: 100%; 
            border: none; 
            display: block; 
            pointer-events: none !important;
          }
          .ytp-suggested-action-badge, .ytp-popup, .ytp-ai-info-dialog, [class*="ai-disclosure"], .ytp-spinner, .ytp-spinner-container, .ytp-bezel { display: none !important; opacity: 0 !important; visibility: hidden !important; pointer-events: none !important; }
        </style>
        </head>
        <body>
        <iframe 
            id="miniYtPlayer"
            src="https://www.youtube.com/embed/\(video.id)?autoplay=1&mute=1&playsinline=1&controls=0&modestbranding=1&rel=0&enablejsapi=1&origin=https://auratube.app&widget_referrer=https://auratube.app&start=\(startPos)&vq=small" 
            allow="autoplay; encrypted-media; picture-in-picture; fullscreen">
        </iframe>
        <script>
          window.addEventListener('keydown', function(e) {
            if (e.code === 'Space' || e.keyCode === 32) {
              e.preventDefault();
              e.stopPropagation();
              try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.miniPlayerBridge) {
                  window.webkit.messageHandlers.miniPlayerBridge.postMessage({ type: 'togglePlayPause' });
                }
              } catch(err) {}
            }
          }, true);

          window.addEventListener('message', function(e) {
            try {
              var data = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
              if (!data) return;
              var ifr = document.getElementById('miniYtPlayer');
              if (data.event === 'onReady') {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.miniPlayerBridge) {
                  window.webkit.messageHandlers.miniPlayerBridge.postMessage({ type: 'playerReady' });
                }
                if (ifr && ifr.contentWindow) {
                  ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "mute", args: []}), '*');
                  ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setVolume", args: [0]}), '*');
                  ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "playVideo", args: []}), '*');
                  ifr.contentWindow.postMessage(JSON.stringify({event: "listening"}), '*');
                }
              }
              
              if (data.event === 'onStateChange') {
                window.__miniPlayerState = data.info;
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.miniPlayerBridge) {
                  window.webkit.messageHandlers.miniPlayerBridge.postMessage({
                    type: 'stateChange',
                    state: data.info
                  });
                }
              }
              
              if (data.event === 'infoDelivery' && data.info) {
                if (typeof data.info.currentTime === 'number') {
                  window.__miniCurrentTime = data.info.currentTime;
                }
                if (typeof data.info.playerState === 'number') {
                  window.__miniPlayerState = data.info.playerState;
                }
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.miniPlayerBridge) {
                  window.webkit.messageHandlers.miniPlayerBridge.postMessage({
                    type: 'playbackSync',
                    currentTime: data.info.currentTime,
                    duration: data.info.duration,
                    playerState: data.info.playerState
                  });
                }
              }
            } catch(err) {}
          });
          
          var retryListen = setInterval(function() {
            var ifr = document.getElementById('miniYtPlayer');
            if (ifr && ifr.contentWindow) {
              ifr.contentWindow.postMessage(JSON.stringify({event: "listening"}), '*');
            }
          }, 500);
          setTimeout(function() { clearInterval(retryListen); }, 4000);
        </script>
        </body>
        </html>
        """
    }
    
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "miniPlayerBridge",
              let body = message.body as? [String: Any] else { return }
        
        DispatchQueue.main.async {
            guard let type = body["type"] as? String else { return }
            
            if type == "togglePlayPause" {
                PlayerManager.shared.togglePlayPause()
                return
            }
            
            if type == "videoDimensions", let isVertical = body["isVertical"] as? Bool {
                if PlayerManager.shared.isCurrentVideoVertical != isVertical {
                    PlayerManager.shared.isCurrentVideoVertical = isVertical
                }
                return
            }
            
            if type == "playerReady" {
                let pm = PlayerManager.shared
                let shouldPlay = self.isPopoverVisible && pm.isPlaying
                let js = """
                (function() {
                    var ifr = document.getElementById('miniYtPlayer');
                    if (ifr && ifr.contentWindow) {
                        ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "mute", args: []}), '*');
                        ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setVolume", args: [0]}), '*');
                        ifr.contentWindow.postMessage(JSON.stringify({
                            event: 'auratube_sync',
                            masterTime: \(pm.currentTime),
                            isPlaying: \(shouldPlay),
                            forceSnap: true
                        }), '*');
                        if (\(shouldPlay)) {
                            ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "playVideo", args: []}), '*');
                        }
                    }
                })();
                """
                self.webView.evaluateJavaScript(js, completionHandler: nil)
                return
            }
            
            if type == "playbackSync" {
                // CRITICAL: NEVER accept time updates from mini player if main player is active or no video is active!
                guard !PlayerManager.shared.hasActiveMainPlayer, PlayerManager.shared.currentVideo != nil else { return }
                
                let cur = body["currentTime"] as? Double
                let dur = body["duration"] as? Double ?? 0
                let state = body["playerState"] as? Int
                let isPlaying = (state == 1) ? true : ((state == 2 || state == 0) ? false : nil)
                
                if let cur = cur {
                    PlayerManager.shared.updatePlaybackSync(
                        currentTime: cur,
                        duration: dur,
                        isPlaying: isPlaying,
                        isMuted: nil,
                        source: "mini"
                    )
                }
                return
            }
            
            if type == "stateChange", let state = body["state"] as? Int {
                guard !PlayerManager.shared.hasActiveMainPlayer, PlayerManager.shared.currentVideo != nil else { return }
                let isPlaying = (state == 1)
                PlayerManager.shared.updatePlaybackSync(
                    currentTime: PlayerManager.shared.currentTime,
                    duration: PlayerManager.shared.duration,
                    isPlaying: isPlaying,
                    isMuted: nil,
                    source: "mini"
                )
                if state == 0 {
                    PlayerManager.shared.handlePlaybackEnded()
                }
                return
            }
        }
    }
}

// MARK: - MiniPlayerContainerView: Auto-resizing view ensuring webView fills bounds exactly
final class MiniPlayerContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Must return nil so that all mouse clicks and cursor events pass cleanly to SwiftUI buttons/gestures
        return nil
    }
    
    override func layout() {
        super.layout()
        if let webView = subviews.first as? WKWebView {
            webView.frame = bounds
        }
    }
}

// MARK: - MiniNativePlayerView: SwiftUI View Representable hosting MiniPlayerEngine
public struct MiniNativePlayerView: NSViewRepresentable {
    @ObservedObject var playerManager: PlayerManager = .shared
    
    public init() {}
    
    public func makeNSView(context: Context) -> NSView {
        let container = MiniPlayerContainerView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        
        MiniPlayerEngine.shared.attach(to: container)
        
        return container
    }
    
    public func updateNSView(_ nsView: NSView, context: Context) {
        MiniPlayerEngine.shared.attach(to: nsView)
        
        if let video = playerManager.currentVideo {
            MiniPlayerEngine.shared.loadVideo(video: video, startPos: playerManager.currentTime)
        }
    }
}
