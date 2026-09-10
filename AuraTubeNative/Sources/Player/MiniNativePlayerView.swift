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
                        body, html { margin: 0; padding: 0; background: #000; overflow: hidden; width: 100%; height: 100%; }
                        iframe { width: 100%; height: 100%; border: none; display: block; }
                        .html5-video-player,
                        .html5-video-container {
                            width: 100% !important;
                            height: 100% !important;
                            overflow: hidden !important;
                            background: #000 !important;
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
                        }
                    `;
                    (document.head || document.documentElement).appendChild(s);
                }

                try {
                    var badges = document.querySelectorAll(
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
                        media[i].muted = true;
                        media[i].volume = 0;
                    }
                } catch(e) {}
            }
            enforceMute();
            setInterval(enforceMute, 250);

            // Compress / Force small quality for lightweight silky-smooth playback
            function enforceLowQuality() {
                try {
                    var p = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                    if (p) {
                        if (typeof p.setPlaybackQualityRange === 'function') {
                            p.setPlaybackQualityRange('small', 'medium');
                        }
                        if (typeof p.setPlaybackQuality === 'function') {
                            p.setPlaybackQuality('small');
                        }
                    }
                } catch(e) {}
            }
            enforceLowQuality();
            setInterval(enforceLowQuality, 1500);

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
            setInterval(reportVideoDimensions, 1500);

            document.addEventListener('play', function(e) {
                if (e.target && (e.target.tagName === 'VIDEO' || e.target.tagName === 'AUDIO')) {
                    e.target.muted = true;
                    e.target.volume = 0;
                }
                enforceLowQuality();
                reportVideoDimensions();
            }, true);

            // Silky-Smooth Video Sync (zero jitter, avoids constant seeking)
            window.addEventListener('message', function(e) {
                try {
                    var data = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
                    if (!data || data.event !== 'auratube_sync') return;
                    
                    var v = document.querySelector('video');
                    if (!v) return;
                    
                    v.muted = true;
                    v.volume = 0;
                    
                    var targetTime = data.masterTime;
                    var shouldPlay = data.isPlaying;
                    
                    if (shouldPlay && v.paused) {
                        v.play().catch(function(){});
                    } else if (!shouldPlay && !v.paused) {
                        v.pause();
                    }
                    
                    if (typeof targetTime !== 'number' || targetTime < 0) return;
                    
                    var diff = targetTime - v.currentTime;
                    var absDiff = Math.abs(diff);
                    
                    // 1. Explicit user seek, popover reveal, or video change: instant frame snap
                    if (data.forceSnap) {
                        v.currentTime = targetTime;
                        v.playbackRate = 1.0;
                        return;
                    }
                    
                    // 2. If video is paused, only snap if offset
                    if (!shouldPlay || v.paused) {
                        if (absDiff > 0.05) {
                            v.currentTime = targetTime;
                        }
                        v.playbackRate = 1.0;
                        return;
                    }
                    
                    // 3. Continuous sub-frame lockstep synchronization:
                    // Hard snap only for massive drift (> 1.2s)
                    if (absDiff > 1.2) {
                        v.currentTime = targetTime;
                        v.playbackRate = 1.0;
                    } else if (absDiff > 0.015) {
                        // Proportional rate steering (kP = 1.5):
                        // Smoothly eliminates 20-200ms differences within 100-300ms without buffering or seeking!
                        var correction = diff * 1.5;
                        correction = Math.max(-0.30, Math.min(0.30, correction));
                        v.playbackRate = 1.0 + correction;
                    } else {
                        // Sub-frame deadband (< 15ms) -> 100% lockstep!
                        v.playbackRate = 1.0;
                    }
                } catch(err) {}
            });

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
        })();
        """
        let userScript = WKUserScript(source: cleanScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        contentController.addUserScript(userScript)
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
        
        // 1. Play / Pause observer: instant simultaneous sync & reliable pause
        pm.registerPlayPauseObserver(id: observerId) { [weak self] shouldPlay in
            guard let self = self else { return }
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
                        forceSnap: true
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
        
        // 2. Seek observer: instant seek to target frame and hold until master resumes
        pm.registerSeekObserver(id: observerId) { [weak self] targetSeconds in
            guard let self = self else { return }
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
        
        // 5. Video change observer: loads and starts playing immediately in parallel with main player!
        pm.registerVideoChangeObserver(id: observerId) { [weak self] newVideo, startTime in
            self?.loadVideo(video: newVideo, startPos: startTime)
        }
        
        // If a video is already active right now, load it immediately
        if let current = pm.currentVideo {
            loadVideo(video: current, startPos: pm.currentTime)
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
        
        // Popover opened: enforce small quality and snap immediately to master playback frame
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AuraTubeMenuBarPopoverShown"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isPopoverVisible = true
                let pm = PlayerManager.shared
                let shouldPlay = pm.isPlaying
                let js = """
                (function() {
                    var ifr = document.getElementById('miniYtPlayer');
                    if (ifr && ifr.contentWindow) {
                        ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "mute", args: []}), '*');
                        ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setVolume", args: [0]}), '*');
                        ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setPlaybackQualityRange", args: ["small", "medium"]}), '*');
                        ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setPlaybackQuality", args: ["small"]}), '*');
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
    
    public func loadVideo(video: Video, startPos: Double = 0) {
        guard currentLoadedVideoId != video.id else { return }
        currentLoadedVideoId = video.id
        
        let pos = max(0, Int(startPos))
        let html = generateHTML(for: video, startPos: pos)
        webView.loadHTMLString(html, baseURL: URL(string: "https://auratube.app"))
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
          * { margin: 0; padding: 0; box-sizing: border-box; background: #000; overflow: hidden; }
          html, body { width: 100%; height: 100%; background: #000; overflow: hidden; }
          iframe { 
            position: absolute; 
            top: 0; 
            left: 0; 
            width: 100%; 
            height: 100%; 
            border: none; 
            display: block; 
          }
          .ytp-suggested-action-badge, .ytp-popup, .ytp-ai-info-dialog, [class*="ai-disclosure"], .ytp-spinner, .ytp-spinner-container, .ytp-bezel { display: none !important; opacity: 0 !important; visibility: hidden !important; }
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
                  ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setPlaybackQualityRange", args: ["small", "medium"]}), '*');
                  ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setPlaybackQuality", args: ["small"]}), '*');
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
                        ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setPlaybackQualityRange", args: ["small", "medium"]}), '*');
                        ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setPlaybackQuality", args: ["small"]}), '*');
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
                // CRITICAL: NEVER accept time updates from mini player if main player is active!
                guard !PlayerManager.shared.hasActiveMainPlayer else { return }
                
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
                guard !PlayerManager.shared.hasActiveMainPlayer else { return }
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
