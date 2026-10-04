import SwiftUI
import AppKit
import WebKit

extension NSObject {
    /// KVC for private WebKit switches. Apps linked against the current SDK crash with
    /// NSUnknownKeyException on keys WebKit no longer exposes, so only set keys that still
    /// have a setter.
    func setValueIfSupported(_ value: Any?, forKey key: String) {
        let setter = "set" + key.prefix(1).uppercased() + key.dropFirst() + ":"
        if responds(to: NSSelectorFromString(setter)) || responds(to: NSSelectorFromString("_" + setter)) {
            setValue(value, forKey: key)
        }
    }
}

@MainActor
public final class MainWebPlayerPool {
    public static let shared = MainWebPlayerPool()
    public var webView: WKWebView?
    public var coordinator: NativePlayerView.Coordinator?
    
    private init() {}
    
    public func reset() {
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        coordinator = nil
    }
}

public final class ScrollForwardingWKWebView: WKWebView {
    public override func scrollWheel(with event: NSEvent) {
        // Forward scrollWheel directly up the responder chain so enclosing scroll views / handlers receive it!
        self.nextResponder?.scrollWheel(with: event)
    }
    
    public static var isTransitioning: Bool = false
    private var relayoutWorkItem: DispatchWorkItem?
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let win = window {
            let scale = win.backingScaleFactor
            self.layer?.contentsScale = scale
            for sub in subviews {
                sub.layer?.contentsScale = scale
            }
        }
        if let superview = self.superview, superview.bounds.width > 0 && superview.bounds.height > 0 {
            if self.frame != superview.bounds {
                self.frame = superview.bounds
            }
        }
        needsLayout = true
        if !Self.isTransitioning {
            triggerRelayout()
        }
    }
    
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if let win = window {
            self.layer?.contentsScale = win.backingScaleFactor
        }
        if Self.isTransitioning {
            return
        }
        relayoutWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.triggerRelayout()
        }
        relayoutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
    }
    
    public func triggerRelayout() {
        let js = """
        (function() {
            try {
                if (typeof window.forcePlayerRelayout === 'function') {
                    window.forcePlayerRelayout();
                } else {
                    window.dispatchEvent(new Event('resize'));
                    var ifr = document.getElementById('ytPlayer') || document.querySelector('iframe');
                    if (ifr && ifr.contentWindow) {
                        ifr.contentWindow.dispatchEvent(new Event('resize'));
                    }
                }
            } catch(e) {}
        })();
        """
        self.evaluateJavaScript(js, completionHandler: nil)
    }
}

// MARK: - Auto-resizing WebPlayerHostingView ensuring webView fills bounds 100% and syncs Retina scale
public final class WebPlayerHostingView: NSView {
    public weak var hostedWebView: WKWebView?
    
    public func attach(webView: WKWebView, cornerRadius: CGFloat, maskedCorners: CACornerMask) {
        if webView.superview !== self {
            webView.removeFromSuperview()
            addSubview(webView)
        }
        self.hostedWebView = webView
        
        self.wantsLayer = true
        self.layer?.cornerRadius = cornerRadius
        self.layer?.maskedCorners = maskedCorners
        self.layer?.masksToBounds = cornerRadius > 0
        
        webView.wantsLayer = true
        webView.layer?.cornerRadius = cornerRadius
        webView.layer?.maskedCorners = maskedCorners
        webView.layer?.masksToBounds = cornerRadius > 0
        
        webView.autoresizingMask = [.width, .height]
        webView.translatesAutoresizingMaskIntoConstraints = true
        
        let targetFrame: NSRect
        if bounds.width > 0 && bounds.height > 0 {
            targetFrame = bounds
        } else if let s = superview, s.bounds.width > 0 && s.bounds.height > 0 {
            targetFrame = s.bounds
        } else {
            targetFrame = webView.frame
        }
        
        if targetFrame.width > 0 && targetFrame.height > 0 {
            if webView.frame != targetFrame {
                webView.frame = targetFrame
            }
        }
        webView.isHidden = false
        
        if let win = window {
            webView.layer?.contentsScale = win.backingScaleFactor
        }
        
        needsLayout = true
        layoutSubtreeIfNeeded()
        
        if bounds.width > 0 && bounds.height > 0 {
            if webView.frame != bounds {
                webView.frame = bounds
            }
            if !ScrollForwardingWKWebView.isTransitioning, let wv = webView as? ScrollForwardingWKWebView {
                wv.triggerRelayout()
            }
        }
    }
    
    public override func layout() {
        super.layout()
        guard let wv = hostedWebView, wv.superview === self else { return }
        if bounds.width > 0 && bounds.height > 0 {
            if wv.frame != bounds {
                wv.frame = bounds
            }
            wv.isHidden = false
            
            // Record screen frame if this hosting view is in the main window
            if let win = window, !(win is NSPanel) {
                let screenRect = win.convertToScreen(convert(bounds, to: nil))
                if screenRect.width > 200 && screenRect.height > 100 {
                    PiPWindowController.shared.mainPlayerScreenFrame = screenRect
                }
            }
        }
        if let win = window {
            let scale = win.backingScaleFactor
            layer?.contentsScale = scale
            wv.layer?.contentsScale = scale
        }
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let wv = hostedWebView, wv.superview === self else { return }
        if let win = window {
            let scale = win.backingScaleFactor
            layer?.contentsScale = scale
            wv.layer?.contentsScale = scale
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        if let swv = wv as? ScrollForwardingWKWebView {
            swv.triggerRelayout()
        }
    }
}

public struct NativePlayerView: NSViewRepresentable {
    @ObservedObject var playerManager: PlayerManager = .shared
    public var cornerRadius: CGFloat
    public var maskedCorners: CACornerMask
    
    public init(
        cornerRadius: CGFloat = 0,
        maskedCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    ) {
        self.cornerRadius = cornerRadius
        self.maskedCorners = maskedCorners
    }
    
    public func makeCoordinator() -> Coordinator {
        if let existing = MainWebPlayerPool.shared.coordinator {
            return existing
        }
        let coord = Coordinator()
        MainWebPlayerPool.shared.coordinator = coord
        return coord
    }
    
    private func getOrCreateWebView(context: Context) -> ScrollForwardingWKWebView {
        if let existing = MainWebPlayerPool.shared.webView as? ScrollForwardingWKWebView {
            existing.autoresizingMask = [.width, .height]
            existing.translatesAutoresizingMaskIntoConstraints = true
            context.coordinator.targetWebView = existing
            setupBridgeCallbacks(for: existing)
            return existing
        }
        
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.setValueIfSupported(false, forKey: "allowFileAccessFromFileURLs")
        config.preferences.setValueIfSupported(true, forKey: "fullScreenEnabled")
        
        // Bypass WebKit user activation restrictions for autoplay and unmuted audio
        config.setValueIfSupported(false, forKey: "requiresUserActionForAudioPlayback")
        config.setValueIfSupported(false, forKey: "requiresUserActionForVideoPlayback")
        config.setValueIfSupported(true, forKey: "mainContentUserGestureOverrideEnabled")
        config.setValueIfSupported(false, forKey: "invisibleAutoplayNotPermitted")
        config.setValueIfSupported(false, forKey: "pageVisibilityBasedProcessSuppressionEnabled")
        config.setValueIfSupported(false, forKey: "backgroundFetchAndProcessTimerThrottlingEnabled")
        
        let pref = config.preferences
        pref.setValueIfSupported(false, forKey: "requiresUserGestureForAudioPlayback")
        pref.setValueIfSupported(false, forKey: "requiresUserGestureForVideoPlayback")
        pref.setValueIfSupported(true, forKey: "mainContentUserGestureOverrideEnabled")
        pref.setValueIfSupported(false, forKey: "invisibleMediaAutoplayNotPermitted")
        pref.setValueIfSupported(false, forKey: "pageVisibilityBasedProcessSuppressionEnabled")
        pref.setValueIfSupported(false, forKey: "backgroundFetchAndProcessTimerThrottlingEnabled")
        
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, contentWorld: .page, name: "playerBridge")
        contentController.add(context.coordinator, contentWorld: .defaultClient, name: "playerBridge")
        
        let cleanScript = NativePlayerView.cleanScriptSource
        let userScriptEnd = WKUserScript(source: cleanScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        contentController.addUserScript(userScriptEnd)
        config.userContentController = contentController
        
        let webView = ScrollForwardingWKWebView(frame: .zero, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        webView.setValueIfSupported(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        
        MainWebPlayerPool.shared.webView = webView
        context.coordinator.targetWebView = webView
        setupBridgeCallbacks(for: webView)
        
        return webView
    }
    
    public func makeNSView(context: Context) -> WebPlayerHostingView {
        playerManager.hasActiveMainPlayer = true
        let container = WebPlayerHostingView()
        let webView = getOrCreateWebView(context: context)
        container.attach(webView: webView, cornerRadius: cornerRadius, maskedCorners: maskedCorners)
        return container
    }
    
    private func setupBridgeCallbacks(for webView: WKWebView) {
        // Connect PlayerManager bridge actions
        playerManager.onPlayPause = { [weak webView] shouldPlay in
            let cmd = shouldPlay ? "playVideo" : "pauseVideo"
            let js = """
            (function() {
                try {
                    var ifr = document.getElementById('ytPlayer') || document.querySelector('iframe');
                    if (ifr && ifr.contentWindow) {
                        ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "\(cmd)", args: []}), '*');
                        ifr.contentWindow.postMessage(JSON.stringify({type: "\(cmd)"}), '*');
                    }
                    var v = document.querySelector('video');
                    if (v) {
                        if (\(shouldPlay)) { v.play().catch(function(){}); }
                        else { v.pause(); }
                    }
                    var p = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                    if (p) {
                        if (\(shouldPlay) && typeof p.playVideo === 'function') { p.playVideo(); }
                        else if (!\(shouldPlay) && typeof p.pauseVideo === 'function') { p.pauseVideo(); }
                    }
                } catch(e) {}
            })();
            """
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
        
        playerManager.onSeek = { [weak webView] targetSeconds in
            let js = """
            (function() {
                try {
                    currentTime = \(targetSeconds);
                    var ifr = document.getElementById('ytPlayer') || document.querySelector('iframe');
                    if (ifr && ifr.contentWindow) {
                        ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "seekTo", args: [\(targetSeconds), true]}), '*');
                        ifr.contentWindow.postMessage(JSON.stringify({type: "seekTo", seconds: \(targetSeconds)}), '*');
                    }
                    var v = document.querySelector('video');
                    if (v) {
                        v.currentTime = \(targetSeconds);
                    }
                    var p = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                    if (p && typeof p.seekTo === 'function') {
                        p.seekTo(\(targetSeconds), true);
                    }
                } catch(e) {}
            })();
            """
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
        
        playerManager.onMuteToggle = { [weak webView] isMuted in
            let cmd = isMuted ? "mute" : "unMute"
            let js = """
            isMuted = \(isMuted);
            var ifr = document.getElementById('ytPlayer');
            if (ifr && ifr.contentWindow) {
                ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "\(cmd)", args: []}), '*');
            }
            if (typeof postSync === 'function') { postSync(); }
            """
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
        
        playerManager.onVolumeChange = { [weak webView] vol in
            let intVol = max(0, min(100, Int(vol * 100)))
            let js = """
            var ifr = document.getElementById('ytPlayer');
            if (ifr && ifr.contentWindow) {
                ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setVolume", args: [\(intVol)]}), '*');
            }
            """
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
        
        playerManager.onQualityChange = { [weak webView] quality in
            let effectiveQ = (quality == "auto") ? PlayerManager.shared.resolvedOptimalQuality : quality
            let ytQuality: String
            switch effectiveQ {
            case "4320": ytQuality = "highres"
            case "2880": ytQuality = "hd2880"
            case "2160": ytQuality = "hd2160"
            case "1440": ytQuality = "hd1440"
            case "1080": ytQuality = "hd1080"
            case "720": ytQuality = "hd720"
            case "480": ytQuality = "large"
            case "360": ytQuality = "medium"
            case "240": ytQuality = "small"
            case "144": ytQuality = "tiny"
            default: ytQuality = "hd1080"
            }
            let js = """
            (function() {
                var ifr = document.getElementById('ytPlayer');
                if (ifr && ifr.contentWindow) {
                    ifr.contentWindow.postMessage(JSON.stringify({
                        type: 'forceQuality',
                        quality: '\(quality)',
                        optimalQuality: '\(effectiveQ)',
                        ytQuality: '\(ytQuality)'
                    }), '*');
                    if ('\(quality)' !== 'auto') {
                        ifr.contentWindow.postMessage(JSON.stringify({
                            event: "command",
                            func: "setPlaybackQualityRange",
                            args: ['\(ytQuality)', '\(ytQuality)']
                        }), '*');
                        ifr.contentWindow.postMessage(JSON.stringify({
                            event: "command",
                            func: "setPlaybackQuality",
                            args: ['\(ytQuality)']
                        }), '*');
                    }
                }
            })();
            """
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
        
        playerManager.onPlaybackRateChange = { [weak webView] rate in
            let js = """
            (function() {
                if (typeof currentPlaybackRate !== 'undefined') {
                    currentPlaybackRate = \(rate);
                }
                var ifr = document.getElementById('ytPlayer') || document.querySelector('iframe');
                if (ifr && ifr.contentWindow) {
                    ifr.contentWindow.postMessage(JSON.stringify({
                        event: "command",
                        func: "setPlaybackRate",
                        args: [\(rate)]
                    }), '*');
                    ifr.contentWindow.postMessage(JSON.stringify({
                        type: 'setPlaybackRate',
                        rate: \(rate)
                    }), '*');
                }
                var v = document.querySelector('video');
                if (v) {
                    v.playbackRate = \(rate);
                    v.defaultPlaybackRate = \(rate);
                }
                var p = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                if (p && typeof p.setPlaybackRate === 'function') {
                    p.setPlaybackRate(\(rate));
                }
            })();
            """
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
    
    public func updateNSView(_ nsView: WebPlayerHostingView, context: Context) {
        let webView = getOrCreateWebView(context: context)
        nsView.attach(webView: webView, cornerRadius: cornerRadius, maskedCorners: maskedCorners)
        
        if !playerManager.hasActiveMainPlayer {
            playerManager.hasActiveMainPlayer = true
        }
        guard let video = playerManager.currentVideo else { return }
        
        if context.coordinator.currentLoadedVideoId != video.id {
            let wasLoaded = context.coordinator.currentLoadedVideoId != nil
            context.coordinator.currentLoadedVideoId = video.id
            context.coordinator.isActuallyPlaying = false
            context.coordinator.didClickAutoPlay = false
            context.coordinator.clickAttempts = 0
            
            if wasLoaded {
                // Video switch: Use loadNewVideo with resume startSec and quality preference
                let effectiveQ = (playerManager.selectedQuality != "auto") ? playerManager.selectedQuality : playerManager.resolvedOptimalQuality
                let rate = playerManager.playbackRate
                let startSec = Int(playerManager.currentTime)
                let js = "if (typeof window.loadNewVideo === 'function') { window.loadNewVideo('\(video.id)', \(startSec), '\(effectiveQ)', \(rate)); } else { location.reload(); }"
                webView.evaluateJavaScript(js) { [weak webView, weak coord = context.coordinator] _, err in
                    if err != nil {
                        guard let v = webView else { return }
                        let html = NativePlayerView.generateHTML(for: video, playerManager: PlayerManager.shared)
                        v.loadHTMLString(html, baseURL: URL(string: "https://auratube.app"))
                    }
                    if let v = webView, let c = coord {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            c.ensureAutoPlay(on: v)
                        }
                    }
                }
            } else {
                // Initial load
                let html = NativePlayerView.generateHTML(for: video, playerManager: playerManager)
                webView.loadHTMLString(html, baseURL: URL(string: "https://auratube.app"))
                
                let coord = context.coordinator
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak webView, weak coord] in
                    guard let v = webView, let c = coord else { return }
                    c.ensureAutoPlay(on: v)
                }
            }
        }
    }
    
    public static func generateHTML(for video: Video, playerManager: PlayerManager) -> String {
        let startPos = max(0, Int(playerManager.currentTime))
        let effectiveQ = (playerManager.selectedQuality != "auto") ? playerManager.selectedQuality : playerManager.resolvedOptimalQuality
        let qParam: String = {
            switch effectiveQ {
            case "4320": return "highres"
            case "2880": return "hd2880"
            case "2160": return "hd2160"
            case "1440": return "hd1440"
            case "1080": return "hd1080"
            case "720": return "hd720"
            case "480": return "large"
            case "360": return "medium"
            default: return "hd1080"
            }
        }()
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <meta name="referrer" content="origin">
        <link rel="preconnect" href="https://www.youtube.com">
        <link rel="preconnect" href="https://i.ytimg.com">
        <link rel="preconnect" href="https://www.google.com">
        <link rel="dns-prefetch" href="https://googlevideo.com">
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          html, body { width: 100%; height: 100%; overflow: hidden !important; background: #000 !important; }
          .player-wrapper {
            position: relative;
            width: 100%;
            height: 100%;
            overflow: hidden !important;
            background: #000;
          }
          #ytPlayer, iframe {
            position: absolute;
            top: 0;
            left: 0;
            width: 100% !important;
            height: 100% !important;
            border: none;
            display: block;
          }
          #player, #movie_player, .html5-video-player, .html5-video-container {
            width: 100% !important;
            height: 100% !important;
            position: absolute !important;
            top: 0 !important;
            left: 0 !important;
            overflow: hidden !important;
            background: #000 !important;
          }
          .ytp-fit-cover-video,
          .ytp-fit-cover-video video,
          .ytp-fit-cover-video .html5-main-video,
          .html5-video-player .html5-main-video,
          video.video-stream.html5-main-video,
          video.html5-main-video,
          video {
            display: block !important;
            width: 100% !important;
            height: 100% !important;
            position: absolute !important;
            top: 0px !important;
            left: 0px !important;
            object-fit: contain !important;
            object-position: center center !important;
            background: #000 !important;
          }
          .ytp-large-play-button,
          .ytp-large-play-button-bg,
          .ytp-button.ytp-large-play-button,
          button.ytp-large-play-button,
          .ytp-cairo-refresh-signature-moments,
          .ytp-suggested-action-badge,
          .ytp-popup,
          .ytp-ai-info-dialog,
          [class*="ai-disclosure"],
          .ytp-paid-content-overlay,
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
          .ytp-chrome-top,
          .ytp-chrome-bottom,
          .ytp-gradient-top,
          .ytp-gradient-bottom,
          [class*="title-channel"],
          .ytp-bezel {
            display: none !important;
            opacity: 0 !important;
            visibility: hidden !important;
            pointer-events: none !important;
          }
        </style>
        </head>
        <body>
        <div class="player-wrapper">
        <iframe 
            id="ytPlayer"
            src="https://www.youtube.com/embed/\(video.id)?autoplay=1&mute=1&playsinline=1&controls=0&enablejsapi=1&rel=0&modestbranding=1&fs=0&origin=https://auratube.app&widget_referrer=https://auratube.app&start=\(startPos)&vq=\(qParam)" 
            allow="autoplay; encrypted-media; picture-in-picture; fullscreen" 
            allowfullscreen="true">
        </iframe>
        </div>
        <script>
          var isPlaying = true;
          var isMuted = \(playerManager.isMuted ? "true" : "false");
          var currentVolume = \(max(0, min(100, Int(playerManager.volume * 100))));
          var currentVideoId = '\(video.id)';
          var currentPlaybackRate = \(playerManager.playbackRate);
          var initialStartPos = \(startPos);

          window.forcePlayerRelayout = function() {
            try {
              window.dispatchEvent(new Event('resize'));
              var ifr = document.getElementById('ytPlayer') || document.querySelector('iframe');
              if (ifr) {
                ifr.style.width = '100%';
                ifr.style.height = '100%';
                if (ifr.contentWindow) {
                  ifr.contentWindow.dispatchEvent(new Event('resize'));
                  ifr.contentWindow.postMessage(JSON.stringify({event: "listening"}), '*');
                }
              }
              var v = document.querySelector('video');
              if (v) {
                v.style.setProperty('width', '100%', 'important');
                v.style.setProperty('height', '100%', 'important');
                v.style.setProperty('top', '0px', 'important');
                v.style.setProperty('left', '0px', 'important');
                v.style.setProperty('position', 'absolute', 'important');
              }
            } catch(e) {}
          };
          window.addEventListener('resize', window.forcePlayerRelayout);

          function ensureAudioPlayback() {
            var ifr = document.getElementById('ytPlayer');
            if (ifr && ifr.contentWindow) {
              try {
                ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "playVideo", args: []}), '*');
                ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setPlaybackRate", args: [currentPlaybackRate]}), '*');
                ifr.contentWindow.postMessage(JSON.stringify({type: 'setPlaybackRate', rate: currentPlaybackRate}), '*');
                if (!isMuted) {
                  ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "unMute", args: []}), '*');
                  ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setVolume", args: [currentVolume]}), '*');
                }
              } catch(e) {}
            }
          }

          window.loadNewVideo = function(newId, startSec, targetQuality, targetRate) {
            isPlaying = true;
            currentVideoId = newId;
            if (typeof targetRate === 'number' && targetRate > 0) {
              currentPlaybackRate = targetRate;
            }
            var start = startSec || 0;
            var q = 'hd1080';
            if (targetQuality === '4320') q = 'highres';
            else if (targetQuality === '2880') q = 'hd2880';
            else if (targetQuality === '2160') q = 'hd2160';
            else if (targetQuality === '1440') q = 'hd1440';
            else if (targetQuality === '1080') q = 'hd1080';
            else if (targetQuality === '720') q = 'hd720';
            else if (targetQuality === '480') q = 'large';
            else if (targetQuality === '360') q = 'medium';
            
            try {
              localStorage.setItem('yt-player-quality', JSON.stringify({
                data: q,
                creation: Date.now(),
                expiration: Date.now() + 864000000
              }));
              localStorage.setItem('yt-player-av-quality', JSON.stringify({
                data: q,
                creation: Date.now()
              }));
            } catch(e) {}
            var ifr = document.getElementById('ytPlayer');
            
            clearTimeout(window._loadFallbackTimer);

            if (ifr && ifr.contentWindow) {
              try {
                ifr.contentWindow.postMessage(JSON.stringify({
                  event: "command",
                  func: "loadVideoById",
                  args: [{
                    videoId: newId,
                    startSeconds: start,
                    suggestedQuality: q
                  }]
                }), '*');
                ifr.contentWindow.postMessage(JSON.stringify({
                  event: "command",
                  func: "loadVideoById",
                  args: [newId, start, q]
                }), '*');
                ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "playVideo", args: []}), '*');
                if (start > 0) {
                  setTimeout(function() {
                    try {
                      ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "seekTo", args: [start, true]}), '*');
                      ifr.contentWindow.postMessage(JSON.stringify({type: "seekTo", seconds: start}), '*');
                    } catch(e) {}
                  }, 250);
                }
                ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setPlaybackRate", args: [currentPlaybackRate]}), '*');
                ifr.contentWindow.postMessage(JSON.stringify({type: 'setPlaybackRate', rate: currentPlaybackRate}), '*');
                
                setTimeout(ensureAudioPlayback, 80);
                setTimeout(ensureAudioPlayback, 200);
                setTimeout(ensureAudioPlayback, 500);
              } catch(e) {}
            }
            postStateSync();
            window.forcePlayerRelayout();
          };

          window.reloadPlayer = function(startSec) {
            var ifr = document.getElementById('ytPlayer');
            var start = (typeof startSec === 'number') ? startSec : Math.floor(lastReportedTime || 0);
            if (ifr) {
              var baseSrc = "https://www.youtube.com/embed/" + currentVideoId + "?autoplay=1&enablejsapi=1&origin=https://auratube.app&playsinline=1&rel=0&iv_load_policy=3&modestbranding=1&start=" + start + "&_t=" + Date.now();
              ifr.src = baseSrc;
              setTimeout(function() {
                ensureAudioPlayback();
              }, 350);
            } else {
              location.reload();
            }
          };

          function postStateSync() {
            try {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                window.webkit.messageHandlers.playerBridge.postMessage({
                  type: 'stateChange',
                  videoId: currentVideoId,
                  isPlaying: isPlaying
                });
              }
            } catch(e) {}
          }

          window.addEventListener('message', function(e) {
            try {
              var data = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
              if (!data) return;
              var ifr = document.getElementById('ytPlayer');

              if (data.type === 'videoDimensions') {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                  window.webkit.messageHandlers.playerBridge.postMessage(data);
                }
              }

              if (data.type === 'availableQualities' && data.levels && data.levels.length > 0) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                  window.webkit.messageHandlers.playerBridge.postMessage({
                    type: 'availableQualities',
                    levels: data.levels,
                    currentQuality: data.currentQuality || ''
                  });
                }
              }

              if (data.type === 'qualityChange' && data.quality) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                  window.webkit.messageHandlers.playerBridge.postMessage({
                    type: 'qualityChange',
                    quality: data.quality
                  });
                }
              }

              if (data.event === 'onReady') {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                  window.webkit.messageHandlers.playerBridge.postMessage({ type: 'playerReady' });
                }
                if (initialStartPos > 0) {
                  try {
                    if (ifr && ifr.contentWindow) {
                      ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "seekTo", args: [initialStartPos, true]}), '*');
                      ifr.contentWindow.postMessage(JSON.stringify({type: "seekTo", seconds: initialStartPos}), '*');
                    }
                  } catch(e) {}
                  initialStartPos = 0;
                }
                ensureAudioPlayback();
                setTimeout(ensureAudioPlayback, 120);
                setTimeout(ensureAudioPlayback, 350);
                if (ifr && ifr.contentWindow) {
                  ifr.contentWindow.postMessage(JSON.stringify({event: "listening"}), '*');
                }
                postStateSync();
              }

              if (data.event === 'onStateChange') {
                var state = data.info;
                if (state === 1) {
                  isPlaying = true;
                  ensureAudioPlayback();
                  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                    window.webkit.messageHandlers.playerBridge.postMessage({ type: 'buffering', isBuffering: false });
                  }
                } else if (state === 3) {
                  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                    window.webkit.messageHandlers.playerBridge.postMessage({ type: 'buffering', isBuffering: true });
                  }
                } else if (state === 2 || state === 0) {
                  isPlaying = false;
                  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                    window.webkit.messageHandlers.playerBridge.postMessage({ type: 'buffering', isBuffering: false });
                  }
                  if (state === 0) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                      window.webkit.messageHandlers.playerBridge.postMessage({ type: 'playbackEnded' });
                    }
                  }
                }
                postStateSync();
              }

              if (data.event === 'onPlaybackQualityChange' && data.info) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                  window.webkit.messageHandlers.playerBridge.postMessage({
                    type: 'qualityChange',
                    quality: data.info
                  });
                }
              }

              if (data.event === 'infoDelivery' && data.info) {
                if (typeof data.info.playerState === 'number') {
                  if (data.info.playerState === 1) {
                    isPlaying = true;
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                      window.webkit.messageHandlers.playerBridge.postMessage({ type: 'buffering', isBuffering: false });
                    }
                  } else if (data.info.playerState === 3) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                      window.webkit.messageHandlers.playerBridge.postMessage({ type: 'buffering', isBuffering: true });
                    }
                  } else if (data.info.playerState === 2 || data.info.playerState === 0) {
                    isPlaying = false;
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                      window.webkit.messageHandlers.playerBridge.postMessage({ type: 'buffering', isBuffering: false });
                    }
                  }
                }
                if (data.info.availableQualityLevels && data.info.availableQualityLevels.length > 0) {
                  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                    window.webkit.messageHandlers.playerBridge.postMessage({
                      type: 'availableQualities',
                      levels: data.info.availableQualityLevels,
                      currentQuality: data.info.playbackQuality || ''
                    });
                  }
                }
                if (data.info.playbackQuality && typeof data.info.playbackQuality === 'string') {
                  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                    window.webkit.messageHandlers.playerBridge.postMessage({
                      type: 'qualityChange',
                      quality: data.info.playbackQuality
                    });
                  }
                }
              }
            } catch(err) {}
          });
        </script>
        </body>
        </html>
        """
    }
    
    public static let cleanScriptSource: String = """
    (function() {
        if (window.__auratube_clean_script_injected) return;
        window.__auratube_clean_script_injected = true;
        
        try {
            Object.defineProperty(window, 'devicePixelRatio', { get: function() { return 2.0; } });
        } catch(e) {}

        // Prevent YouTube player from throttling/dropping frame rate when switching to other apps or in PiP
        try {
            Object.defineProperty(document, 'hidden', {
                get: function() { return false; },
                configurable: true
            });
            Object.defineProperty(document, 'visibilityState', {
                get: function() { return 'visible'; },
                configurable: true
            });
            document.addEventListener('visibilitychange', function(e) {
                e.stopImmediatePropagation();
            }, true);
        } catch(e) {}

        function applyStyles() {
            try {
                var target = document.head || document.documentElement || document.body;
                if (target && !document.getElementById('auratube-clean-style')) {
                    var s = document.createElement('style');
                    s.id = 'auratube-clean-style';
                    s.innerHTML = `
                    /* 1. Remove YouTube logo at bottom right and any watermark */
                    .ytp-youtube-button,
                    a.ytp-youtube-button,
                    .ytp-impression-link,
                    a.ytp-watermark,
                    .ytp-watermark,
                    a[href*="youtube.com"],
                    a[aria-label*="YouTube" i],
                    a[title*="YouTube" i],
                    .ytp-title-channel-logo,
                    .ytp-branding-logo,
                    .ytp-branding-icon,
                    [class*="ytp-youtube"],
                    [class*="youtube-button"],
                    [class*="watermark"] {
                        display: none !important;
                        opacity: 0 !important;
                        visibility: hidden !important;
                        pointer-events: none !important;
                        width: 0 !important;
                        height: 0 !important;
                    }
                    
                    /* 2. Remove big chain link / copy link / share button at bottom left */
                    .ytp-copy-link-button,
                    .ytp-share-button,
                    .ytp-share-panel,
                    .ytp-overflow-button,
                    button[aria-label*="Copy" i],
                    button[aria-label*="Sao chép" i],
                    button[aria-label*="Share" i],
                    button[aria-label*="Chia sẻ" i],
                    button[aria-label*="link" i],
                    button[title*="Copy" i],
                    button[title*="Sao chép" i],
                    button[title*="Share" i],
                    button[title*="Chia sẻ" i],
                    button[title*="link" i],
                    [class*="copy-link"],
                    [class*="share-button"],
                    [class*="share-panel"],
                    [class*="overflow-button"] {
                        display: none !important;
                        opacity: 0 !important;
                        visibility: hidden !important;
                        pointer-events: none !important;
                        width: 0 !important;
                        height: 0 !important;
                    }
                    
                    /* 3. Remove "More videos" and pause overlays */
                    .ytp-pause-overlay,
                    .ytp-pause-overlay-container,
                    .ytp-show-cards-title,
                    .ytp-cards-teaser,
                    .ytp-cards-button,
                    .ytp-suggestion-set,
                    .ytp-expand-pause-overlay,
                    .ytp-endscreen-content,
                    .ytp-ce-element,
                    [class*="cards-teaser"],
                    [class*="cards-button"],
                    [class*="pause-overlay"],
                    [aria-label*="More videos" i],
                    [aria-label*="Video khác" i],
                    [title*="More videos" i],
                    [title*="Video khác" i] {
                        display: none !important;
                        opacity: 0 !important;
                        visibility: hidden !important;
                        pointer-events: none !important;
                        width: 0 !important;
                        height: 0 !important;
                    }
                    
                    /* 4. Clean top chrome, channel info, avatar, title, top details renderer and top gradient */
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
                    .ytwPlayerTopControlsContainerWithLeftContent,
                    .ytwPlayerTopControlsPlayerControlsTopRight,
                    .ytmWatchPlayerControlsHost,
                    .ytmVideoInfoFlyoutChannelTitle,
                    .ytmVideoInfoFlyoutChannelSubtitle,
                    .ytp-chrome-top,
                    .ytp-gradient-top,
                    .ytp-title,
                    .ytp-title-channel,
                    .ytp-title-channel-logo,
                    .ytp-title-text,
                    .ytp-title-subtext,
                    .ytp-title-expanded-title,
                    .ytp-title-link,
                    .ytp-copylink-title,
                    .ytp-show-cards-title,
                    a.ytp-title-link,
                    a.ytp-title-channel,
                    [class*="title-channel"],
                    [class*="ytp-title"],
                    [class*="channel-logo"],
                    [class*="channel-name"],
                    [class*="channel-avatar"],
                    [class*="channel-subscribers"],
                    [class*="chrome-top"],
                    [class*="cairo-refresh"],
                    .ytp-title-channel-text,
                    .ytp-cairo-refresh-signature-moments,
                    .ytp-cairo-refresh-signature-moments-title,
                    .ytp-cairo-refresh-signature-moments-avatar,
                    .ytp-cairo-refresh-signature-moments-creator,
                    .ytp-cairo-refresh-signature-moments-channel,
                    .ytp-cairo-refresh-signature-moments-channel-logo,
                    .ytp-cairo-refresh-channel-avatar,
                    .ytp-cairo-refresh-channel-name,
                    .ytp-cairo-refresh-channel-info,
                    .ytp-cairo-refresh-header,
                    .ytp-cairo-refresh-header-title {
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

                    /* 5. Complete removal of YouTube AI disclosures, badges, and popups */
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
                    [title*="Made with AI" i] {
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

                    /* 6. Complete removal of Paid Content / Paid Promotion overlays */
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
                    a[href*="support.google.com/youtube/answer/154235"] {
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

                    /* 7. Completely hide any YouTube native bottom bar controls, timelines, duplicate fullscreen and pause bezels */
                    .ytp-chrome-bottom,
                    .ytp-progress-bar-container,
                    .ytp-progress-bar,
                    .ytp-time-display,
                    .ytp-chapter-title,
                    .ytp-fullscreen-button,
                    .ytp-bezel,
                    .ytp-bezel-text,
                    .ytp-bezel-icon,
                    .ytp-gradient-bottom,
                    .ytp-large-play-button,
                    .ytp-large-play-button-bg,
                    button.ytp-large-play-button,
                    .ytp-button.ytp-large-play-button {
                        display: none !important;
                        opacity: 0 !important;
                        visibility: hidden !important;
                        pointer-events: none !important;
                        width: 0 !important;
                        height: 0 !important;
                    }
                    
                    /* 8. Always contain video without cropping or zoom distortion */
                    #player, #movie_player, .html5-video-player, .html5-video-container {
                        width: 100% !important;
                        height: 100% !important;
                        position: absolute !important;
                        top: 0 !important;
                        left: 0 !important;
                        overflow: hidden !important;
                        background: #000 !important;
                    }
                    .ytp-fit-cover-video,
                    .ytp-fit-cover-video .html5-main-video,
                    .html5-video-player .html5-main-video,
                    video.video-stream.html5-main-video,
                    video.html5-main-video,
                    video {
                        display: block !important;
                        width: 100% !important;
                        height: 100% !important;
                        position: absolute !important;
                        top: 0px !important;
                        left: 0px !important;
                        object-fit: contain !important;
                        object-position: center center !important;
                        background: #000 !important;
                        -webkit-font-smoothing: antialiased !important;
                        image-rendering: -webkit-optimize-contrast !important;
                        transform: translateZ(0) !important;
                        backface-visibility: hidden !important;
                    }
                `;
                    target.appendChild(s);
                }
                try {
                    localStorage.setItem('yt-player-audio-quality', JSON.stringify({
                        data: 'high',
                        creation: Date.now()
                    }));
                } catch(e) {}
            } catch(e) {}
        }
        applyStyles();
        document.addEventListener('DOMContentLoaded', applyStyles);
        window.addEventListener('load', applyStyles);

        // Pointer event simulation to satisfy modern browser user activation
        function simulatePointerClick(elem) {
            if (!elem) return;
            try {
                var rect = elem.getBoundingClientRect();
                var cx = rect.left + rect.width / 2;
                var cy = rect.top + rect.height / 2;
                var opts = {
                    bubbles: true,
                    cancelable: true,
                    view: window,
                    clientX: cx,
                    clientY: cy,
                    screenX: cx,
                    screenY: cy,
                    pointerId: 1,
                    pointerType: 'mouse',
                    isPrimary: true,
                    button: 0,
                    buttons: 1
                };
                elem.dispatchEvent(new PointerEvent('pointerdown', opts));
                elem.dispatchEvent(new MouseEvent('mousedown', opts));
                elem.dispatchEvent(new PointerEvent('pointerup', opts));
                elem.dispatchEvent(new MouseEvent('mouseup', opts));
                elem.dispatchEvent(new MouseEvent('click', opts));
                if (typeof elem.click === 'function') {
                    elem.click();
                }
            } catch(e) {}
        }

        function clickLargePlay() {
            try {
                var v = document.querySelector('video');
                if (v && !v.paused && v.currentTime > 0.05) return;
                var btns = document.querySelectorAll(
                    '.ytp-large-play-button, button.ytp-large-play-button, .ytp-large-play-button-bg'
                );
                for (var i = 0; i < btns.length; i++) {
                    var btn = btns[i];
                    if (btn && (btn.offsetParent !== null || btn.offsetWidth > 0)) {
                        simulatePointerClick(btn);
                        if (typeof btn.click === 'function') btn.click();
                    }
                }
            } catch(e) {}
        }

        // Safely start playback once ready without interfering with audio track
        var autoPlayDone = false;
        var autoPlayInterval = null;
        function autoStartPlayback() {
            if (autoPlayDone) return;
            try {
                var v = document.querySelector('video');
                if (v) {
                    if (!v.paused && v.currentTime > 0.05) {
                        autoPlayDone = true;
                        if (autoPlayInterval) { clearInterval(autoPlayInterval); autoPlayInterval = null; }
                        return;
                    }
                    clickLargePlay();
                    if (v.paused) {
                        var p = v.play();
                        if (p !== undefined) {
                            p.then(function() {
                                autoPlayDone = true;
                                if (autoPlayInterval) { clearInterval(autoPlayInterval); autoPlayInterval = null; }
                            }).catch(function() {});
                        }
                    }
                    if (!v.paused && v.currentTime > 0.02 && !v.__auratube_unmuted) {
                        v.__auratube_unmuted = true;
                        v.muted = false;
                        v.volume = 1.0;
                    }
                } else {
                    clickLargePlay();
                }
                var player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                if (player) {
                    if (typeof player.playVideo === 'function') player.playVideo();
                    if (typeof player.unMute === 'function') player.unMute();
                    if (typeof player.setVolume === 'function') player.setVolume(100);
                }
            } catch(err) {}
        }

        autoPlayInterval = setInterval(autoStartPlayback, 200);
        setTimeout(function() { if (autoPlayInterval) { clearInterval(autoPlayInterval); autoPlayInterval = null; } }, 3500);
        document.addEventListener('DOMContentLoaded', autoStartPlayback);
        window.addEventListener('load', autoStartPlayback);

        // Hook HTML5 video element directly for real-time timeline & playback sync
        function hookVideoDirect() {
            try {
                var v = document.querySelector('video');
                if (!v || v.__auratube_hooked) return;
                v.__auratube_hooked = true;
                
                var lastEmittedTime = -1;
                var lastEmittedPlaying = null;
                function emitDirectSync(force) {
                    try {
                        var isPlaying = !v.paused && !v.ended;
                        var curTime = v.currentTime || 0;
                        if (!force && lastEmittedPlaying === isPlaying && Math.abs(curTime - lastEmittedTime) < 0.1) {
                            return;
                        }
                        lastEmittedTime = curTime;
                        lastEmittedPlaying = isPlaying;
                        var vidId = '';
                        var player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                        if (player && typeof player.getVideoData === 'function') {
                            var vd = player.getVideoData();
                            if (vd && vd.video_id) vidId = vd.video_id;
                        }
                        if (!vidId) {
                            var parts = (location.pathname || '').split('/');
                            var embIdx = parts.indexOf('embed');
                            if (embIdx !== -1 && parts[embIdx + 1]) vidId = parts[embIdx + 1].slice(0, 11);
                        }
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                            window.webkit.messageHandlers.playerBridge.postMessage({
                                type: 'directSync',
                                videoId: vidId,
                                currentTime: curTime,
                                duration: v.duration || 0,
                                isPlaying: isPlaying
                            });
                        }
                    } catch(e) {}
                }
                
                function onWaitingOrStalled(e) {
                    try {
                        if (v.paused || v.ended) return;
                        if (e && e.type === 'waiting') { noteStall(v); }
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                            window.webkit.messageHandlers.playerBridge.postMessage({ type: 'buffering', isBuffering: true });
                        }
                    } catch(e) {}
                }

                v.addEventListener('waiting', onWaitingOrStalled);
                v.addEventListener('stalled', onWaitingOrStalled);

                v.addEventListener('timeupdate', function() { emitDirectSync(false); });
                v.addEventListener('play', function() {
                    emitDirectSync(true);
                    if (window.__auratube_playback_rate && Math.abs(v.playbackRate - window.__auratube_playback_rate) > 0.01) {
                        v.playbackRate = window.__auratube_playback_rate;
                    }
                    autoPlayDone = true;
                    if (autoPlayInterval) { clearInterval(autoPlayInterval); autoPlayInterval = null; }
                });
                v.addEventListener('pause', function() { emitDirectSync(true); });
                v.addEventListener('playing', function() {
                    emitDirectSync(true);
                    if (window.__auratube_playback_rate && Math.abs(v.playbackRate - window.__auratube_playback_rate) > 0.01) {
                        v.playbackRate = window.__auratube_playback_rate;
                    }
                    autoPlayDone = true;
                    if (autoPlayInterval) { clearInterval(autoPlayInterval); autoPlayInterval = null; }
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                        window.webkit.messageHandlers.playerBridge.postMessage({ type: 'buffering', isBuffering: false });
                    }
                });
                v.addEventListener('ended', function() {
                    emitDirectSync(true);
                    try {
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                            window.webkit.messageHandlers.playerBridge.postMessage({ type: 'playbackEnded' });
                        }
                    } catch(e) {}
                });
                v.addEventListener('seeked', function() { emitDirectSync(true); });
                v.addEventListener('seeking', function() { lastSeekAt = Date.now(); });
                v.addEventListener('loadstart', function() { lastLoadAt = Date.now(); stallTimes = []; healthySince = 0; lastQualityKey = ''; lastDimKey = ''; });
                
                // Picture-in-Picture event hooks
                v.addEventListener('enterpictureinpicture', function() {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                        window.webkit.messageHandlers.playerBridge.postMessage({ type: 'pipStateChange', isActive: true });
                    }
                });
                v.addEventListener('leavepictureinpicture', function() {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                        window.webkit.messageHandlers.playerBridge.postMessage({ type: 'pipStateChange', isActive: false });
                    }
                });
                v.addEventListener('webkitpresentationmodechanged', function() {
                    var isPiP = v.webkitPresentationMode === 'picture-in-picture';
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                        window.webkit.messageHandlers.playerBridge.postMessage({ type: 'pipStateChange', isActive: isPiP });
                    }
                });
                
                // High-precision clock tick while playing (every 80ms) to ensure continuous frame-accurate stream
                setInterval(function() {
                    if (!v.paused && !v.ended) {
                        emitDirectSync();
                    }
                }, 80);
            } catch(err) {}
        }
        hookVideoDirect();
        setInterval(hookVideoDirect, 300);

        // Intercept Fullscreen clicks to toggle native macOS window fullscreen
        function triggerFullscreen(e) {
            if (e) {
                try { e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation(); } catch(err) {}
            }
            try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                    window.webkit.messageHandlers.playerBridge.postMessage({ type: 'toggleFullscreen' });
                }
                window.parent.postMessage(JSON.stringify({ type: 'toggleFullscreen' }), '*');
            } catch(err) {}
        }


        function isFsTarget(target) {
            if (!target) return false;
            if (target.closest) {
                var btn = target.closest(
                    '.ytp-fullscreen-button, .ytp-size-button, [aria-label*="Full screen" i], [aria-label*="fullscreen" i], [aria-label*="màn hình" i], [title*="Full screen" i], [title*="màn hình" i], [data-title-no-tooltip*="Full screen" i], [data-title-no-tooltip*="màn hình" i]'
                );
                if (btn) return true;
            }
            return false;
        }

        ['click', 'pointerup', 'mouseup'].forEach(function(evtName) {
            document.addEventListener(evtName, function(e) {
                if (isFsTarget(e.target)) {
                    triggerFullscreen(e);
                }
            }, true);
        });

        // Forward double click on video to fullscreen
        document.addEventListener('dblclick', function(e) {
            if (e.target && !e.target.closest('.ytp-chrome-bottom, .ytp-progress-bar-container, .ytp-volume-panel, .ytp-settings-menu, .ytp-menuitem')) {
                triggerFullscreen(e);
            }
        }, true);

        // Quality reporting & active high-resolution control
        var isManualQualityLocked = false;
        var qualityCap = 1080;
        var lastQualityKey = '';
        var qualityReportTick = 0;

        // ---- Adaptive smoothness controller (Auto mode) ----
        // YouTube's own ABR picks the rendition per segment inside [tiny … cap]. This controller
        // moves the cap from real playback health: repeated rebuffering or sustained dropped
        // frames step the cap down one rung (the range change never flushes the buffer, so the
        // switch is seamless); a long healthy stretch with a comfortable buffer steps it back up.
        // Step-ups back off exponentially after each failed attempt to avoid oscillation.
        var QUALITY_LADDER = [144, 240, 360, 480, 720, 1080, 1440, 2160, 2880, 4320];
        var YT_QUALITY_NAME = {144: 'tiny', 240: 'small', 360: 'medium', 480: 'large', 720: 'hd720', 1080: 'hd1080', 1440: 'hd1440', 2160: 'hd2160', 2880: 'hd2880', 4320: 'highres'};
        var YT_QUALITY_HEIGHT = {tiny: 144, small: 240, medium: 360, large: 480, hd720: 720, hd1080: 1080, hd1440: 1440, hd2160: 2160, hd2880: 2880, highres: 4320};
        var isAutoQuality = true;
        var adaptiveCap = 0;          // 0 = no extra restriction beyond qualityCap
        var stallTimes = [];
        var lastSeekAt = 0;
        var lastLoadAt = Date.now();
        var lastCapChangeAt = 0;
        var healthySince = 0;
        var stepUpHoldMs = 45000;
        var lastStepUpAt = 0;
        var badFrameTicks = 0;
        var prevFrames = null;

        function ytPlayer() {
            return document.getElementById('movie_player') || document.querySelector('.html5-video-player');
        }

        function effectiveCap() {
            return (adaptiveCap > 0 && adaptiveCap < qualityCap) ? adaptiveCap : qualityCap;
        }

        function applyAutoRange() {
            var p = ytPlayer();
            if (!p || typeof p.setPlaybackQualityRange !== 'function') return false;
            p.setPlaybackQualityRange('tiny', YT_QUALITY_NAME[effectiveCap()] || 'hd1080');
            return true;
        }

        function noteStall(v) {
            var now = Date.now();
            // Seeks and the initial load always buffer; only mid-playback stalls count
            if (v.seeking || now - lastSeekAt < 3000 || now - lastLoadAt < 4000) return;
            stallTimes.push(now);
            healthySince = 0;
        }

        function currentPlayingHeight(v) {
            var p = ytPlayer();
            var name = (p && typeof p.getPlaybackQuality === 'function') ? p.getPlaybackQuality() : '';
            if (YT_QUALITY_HEIGHT[name]) return YT_QUALITY_HEIGHT[name];
            var h = Math.min(v.videoWidth || 0, v.videoHeight || 0);
            var best = 0;
            for (var i = 0; i < QUALITY_LADDER.length; i++) {
                if (QUALITY_LADDER[i] <= h * 1.15) best = QUALITY_LADDER[i];
            }
            return best;
        }

        function bufferAhead(v) {
            try {
                var t = v.currentTime;
                for (var i = 0; i < v.buffered.length; i++) {
                    if (v.buffered.start(i) <= t + 0.25 && v.buffered.end(i) >= t) {
                        return v.buffered.end(i) - t;
                    }
                }
            } catch(e) {}
            return 0;
        }

        function stepCapDown(v, now) {
            var playing = currentPlayingHeight(v) || effectiveCap();
            var target = 0;
            for (var i = QUALITY_LADDER.length - 1; i >= 0; i--) {
                if (QUALITY_LADDER[i] < Math.min(playing, effectiveCap())) { target = QUALITY_LADDER[i]; break; }
            }
            if (target < 360) return;
            // A stall soon after stepping up means that rung is not sustainable yet
            if (lastStepUpAt && now - lastStepUpAt < 60000) {
                stepUpHoldMs = Math.min(stepUpHoldMs * 2, 300000);
            }
            adaptiveCap = target;
            lastCapChangeAt = now;
            stallTimes = [];
            badFrameTicks = 0;
            healthySince = 0;
            applyAutoRange();
        }

        function stepCapUp(now) {
            var next = 0;
            for (var i = 0; i < QUALITY_LADDER.length; i++) {
                if (QUALITY_LADDER[i] > adaptiveCap) { next = QUALITY_LADDER[i]; break; }
            }
            adaptiveCap = (!next || next >= qualityCap) ? 0 : next;
            lastCapChangeAt = now;
            lastStepUpAt = now;
            healthySince = now;
            applyAutoRange();
        }

        setInterval(function() {
            try {
                if (!isAutoQuality) return;
                var v = document.querySelector('video');
                if (!v) return;
                var now = Date.now();

                var frames = (typeof v.getVideoPlaybackQuality === 'function') ? v.getVideoPlaybackQuality() : null;
                var dropRatio = 0;
                if (frames && prevFrames && frames.totalVideoFrames >= prevFrames.total) {
                    var dTotal = frames.totalVideoFrames - prevFrames.total;
                    var dDropped = frames.droppedVideoFrames - prevFrames.dropped;
                    if (dTotal >= 30) dropRatio = dDropped / dTotal;
                }
                prevFrames = frames ? { total: frames.totalVideoFrames, dropped: frames.droppedVideoFrames } : null;

                if (v.paused || v.ended || v.seeking || now - lastSeekAt < 3000) {
                    healthySince = 0;
                    badFrameTicks = 0;
                    return;
                }

                while (stallTimes.length && now - stallTimes[0] > 30000) stallTimes.shift();
                badFrameTicks = (dropRatio > 0.12) ? badFrameTicks + 1 : 0;

                var canChange = now - lastCapChangeAt > 8000;
                if (canChange && (stallTimes.length >= 2 || badFrameTicks >= 3)) {
                    stepCapDown(v, now);
                    return;
                }

                var ahead = bufferAhead(v);
                var bufferedToEnd = v.duration > 0 && (v.currentTime + ahead) >= v.duration - 1;
                var healthy = stallTimes.length === 0 && dropRatio < 0.03 && (ahead >= 12 || bufferedToEnd);
                if (!healthy) { healthySince = 0; return; }
                if (!healthySince) healthySince = now;

                if (adaptiveCap > 0 && canChange && now - healthySince >= stepUpHoldMs) {
                    stepCapUp(now);
                } else if (adaptiveCap === 0 && now - healthySince > 180000) {
                    stepUpHoldMs = 45000;
                }
            } catch(e) {}
        }, 2000);

        function checkAndReportQualities() {
            try {
                var p = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                if (!p) return;
                var levels = (typeof p.getAvailableQualityLevels === 'function') ? p.getAvailableQualityLevels() : [];
                var cur = (typeof p.getPlaybackQuality === 'function') ? p.getPlaybackQuality() : '';
                if (levels && levels.length > 0) {
                    var qKey = levels.join(',') + '|' + cur;
                    qualityReportTick += 1;
                    if (qKey === lastQualityKey && qualityReportTick % 8 !== 0) return;
                    lastQualityKey = qKey;
                    var payload = {
                        type: 'availableQualities',
                        levels: levels,
                        currentQuality: cur
                    };
                    try { window.parent.postMessage(payload, '*'); } catch(e) {}
                    try { window.parent.postMessage(JSON.stringify(payload), '*'); } catch(e) {}
                    try {
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                            window.webkit.messageHandlers.playerBridge.postMessage(payload);
                        }
                    } catch(e) {}
                }
            } catch(e) {}
        }
        setInterval(checkAndReportQualities, 2000);
        setTimeout(checkAndReportQualities, 800);

        var lastDimKey = '';
        function reportVideoDimensions(force) {
            try {
                var v = document.querySelector('video');
                if (v && v.videoWidth > 0 && v.videoHeight > 0) {
                    var dimKey = v.videoWidth + 'x' + v.videoHeight;
                    if (!force && dimKey === lastDimKey) return;
                    lastDimKey = dimKey;
                    var isVertical = v.videoHeight > v.videoWidth;
                    var payload = {
                        type: 'videoDimensions',
                        isVertical: isVertical,
                        width: v.videoWidth,
                        height: v.videoHeight
                    };
                    try { window.parent.postMessage(JSON.stringify(payload), '*'); } catch(e) {}
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                        window.webkit.messageHandlers.playerBridge.postMessage(payload);
                    }
                }
            } catch(e) {}
        }
        document.addEventListener('loadedmetadata', function() { reportVideoDimensions(true); }, true);
        document.addEventListener('loadeddata', function() { reportVideoDimensions(true); }, true);
        document.addEventListener('playing', function() { reportVideoDimensions(false); }, true);
        document.addEventListener('resize', function() { reportVideoDimensions(false); }, true);
        setInterval(function() { reportVideoDimensions(false); }, 1500);

        function forceQualityChange(targetQuality, optimalQuality, ytQualityHint, retries) {
            retries = retries || 0;
            try {
                var p = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                if (!p) {
                    if (retries < 15) {
                        setTimeout(function() { forceQualityChange(targetQuality, optimalQuality, ytQualityHint, retries + 1); }, 250);
                    }
                    return;
                }

                if (targetQuality !== 'auto') {
                    isManualQualityLocked = (targetQuality === '360' || targetQuality === '480' || targetQuality === '240' || targetQuality === '144');
                    isAutoQuality = false;
                    adaptiveCap = 0;
                } else {
                    isManualQualityLocked = false;
                    isAutoQuality = true;
                }

                var effectiveQ = targetQuality;
                if (effectiveQ === 'auto') {
                    effectiveQ = optimalQuality || '1080';
                }
                
                var hNum = parseInt(effectiveQ, 10);
                if (!isNaN(hNum) && hNum > 0) {
                    qualityCap = hNum;
                }

                var ytQuality = ytQualityHint;
                if (!ytQuality || ytQuality === 'default') {
                    switch (effectiveQ) {
                        case '4320': ytQuality = 'highres'; break;
                        case '2880': ytQuality = 'hd2880'; break;
                        case '2160': ytQuality = 'hd2160'; break;
                        case '1440': ytQuality = 'hd1440'; break;
                        case '1080': ytQuality = 'hd1080'; break;
                        case '720': ytQuality = 'hd720'; break;
                        case '480': ytQuality = 'large'; break;
                        case '360': ytQuality = 'medium'; break;
                        case '240': ytQuality = 'small'; break;
                        case '144': ytQuality = 'tiny'; break;
                        default: ytQuality = 'hd1080'; break;
                    }
                }

                // AUTO MODE = YouTube native ABR (Adaptive Bitrate), same as youtube.com.
                // Only set an upper cap so the player can step down/up seamlessly per segment
                // WITHOUT flushing the buffer. Never pin min==max in auto mode.
                if (targetQuality === 'auto') {
                    try {
                        localStorage.removeItem('yt-player-quality');
                        localStorage.removeItem('yt-player-av-quality');
                    } catch(e) {}
                    applyAutoRange();
                    setTimeout(checkAndReportQualities, 400);
                    return;
                }

                // MANUAL MODE: user explicitly chose a resolution → lock it.
                try {
                    localStorage.setItem('yt-player-quality', JSON.stringify({
                        data: ytQuality,
                        creation: Date.now(),
                        expiration: Date.now() + 864000000
                    }));
                } catch(e) {}

                var targetFormatQuality = ytQuality;
                if (typeof p.getAvailableQualityData === 'function') {
                    var qData = p.getAvailableQualityData() || [];
                    for (var i = 0; i < qData.length; i++) {
                        var item = qData[i];
                        var qLbl = (item.qualityLabel || '').toLowerCase();
                        if (qLbl.startsWith(effectiveQ) || qLbl.includes(effectiveQ + 'p') || item.quality === ytQuality) {
                            targetFormatQuality = item.quality;
                            break;
                        }
                    }
                }

                if (typeof p.setPlaybackQualityRange === 'function') {
                    p.setPlaybackQualityRange(targetFormatQuality, targetFormatQuality);
                }
                if (typeof p.setPlaybackQuality === 'function') {
                    p.setPlaybackQuality(targetFormatQuality);
                }
                if (typeof p.setPreferredQuality === 'function') {
                    p.setPreferredQuality(targetFormatQuality);
                }

                setTimeout(checkAndReportQualities, 400);
            } catch(e) {}
        }

        window.addEventListener('message', function(e) {
            try {
                var data = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
                if (!data) return;
                if (data.type === 'forceQuality') {
                    if (data.optimalQuality) {
                        var hNum = parseInt(data.optimalQuality, 10);
                        if (!isNaN(hNum) && hNum > 0) {
                            qualityCap = hNum;
                        }
                    }
                    forceQualityChange(data.quality, data.optimalQuality, data.ytQuality);
                }
                if (data.type === 'togglePiP') {
                    var v = document.querySelector('video');
                    if (v) {
                        if (document.pictureInPictureElement) {
                            document.exitPictureInPicture().catch(function(){});
                        } else if (typeof v.requestPictureInPicture === 'function') {
                            v.requestPictureInPicture().catch(function(){
                                if (typeof v.webkitSetPresentationMode === 'function') {
                                    var mode = v.webkitPresentationMode === 'picture-in-picture' ? 'inline' : 'picture-in-picture';
                                    v.webkitSetPresentationMode(mode);
                                }
                            });
                        } else if (typeof v.webkitSetPresentationMode === 'function') {
                            var mode = v.webkitPresentationMode === 'picture-in-picture' ? 'inline' : 'picture-in-picture';
                            v.webkitSetPresentationMode(mode);
                        }
                    }
                }
                if (data.type === 'seekTo' || (data.event === 'command' && data.func === 'seekTo')) {
                    var sec = typeof data.seconds === 'number' ? data.seconds : (data.args && typeof data.args[0] === 'number' ? data.args[0] : parseFloat(data.args ? data.args[0] : (data.seconds || 0)));
                    if (!isNaN(sec)) {
                        var v = document.querySelector('video');
                        if (v) { v.currentTime = sec; }
                        var player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                        if (player && typeof player.seekTo === 'function') { player.seekTo(sec, true); }
                    }
                }
                if (data.type === 'playVideo' || (data.event === 'command' && data.func === 'playVideo')) {
                    var v = document.querySelector('video');
                    if (v && v.paused) { v.play().catch(function(){}); }
                    var player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                    if (player && typeof player.playVideo === 'function') { player.playVideo(); }
                }
                if (data.type === 'pauseVideo' || (data.event === 'command' && data.func === 'pauseVideo')) {
                    var v = document.querySelector('video');
                    if (v && !v.paused) { v.pause(); }
                    var player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                    if (player && typeof player.pauseVideo === 'function') { player.pauseVideo(); }
                }
                if (data.type === 'togglePlayPause' || (data.event === 'command' && data.func === 'togglePlayPause')) {
                    var v = document.querySelector('video');
                    if (v) {
                        if (v.paused) { v.play().catch(function(){}); } else { v.pause(); }
                    }
                    var player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                    if (player && typeof player.getPlayerState === 'function') {
                        var st = player.getPlayerState();
                        if (st === 1) {
                            if (typeof player.pauseVideo === 'function') player.pauseVideo();
                        } else {
                            if (typeof player.playVideo === 'function') player.playVideo();
                        }
                    }
                }
                if (data.type === 'setPlaybackRate' || (data.event === 'command' && data.func === 'setPlaybackRate')) {
                    var rate = typeof data.rate === 'number' ? data.rate : (data.args && typeof data.args[0] === 'number' ? data.args[0] : parseFloat(data.args ? data.args[0] : (data.rate || 1.0)));
                    if (!isNaN(rate) && rate > 0) {
                        window.__auratube_playback_rate = rate;
                        var v = document.querySelector('video');
                        if (v) {
                            v.playbackRate = rate;
                            v.defaultPlaybackRate = rate;
                        }
                        var player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                        if (player && typeof player.setPlaybackRate === 'function') {
                            player.setPlaybackRate(rate);
                        }
                    }
                }
            } catch(err) {}
        });

        // Intercept Space and K inside the iframe to prevent unwanted browser scrolling or duplicate handling
        window.addEventListener('keydown', function(e) {
            if (e.code === 'Space' || e.keyCode === 32 || e.code === 'KeyK' || e.keyCode === 75) {
                e.preventDefault();
                e.stopPropagation();
                e.stopImmediatePropagation();
                try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                        window.webkit.messageHandlers.playerBridge.postMessage({ type: 'togglePlayPause' });
                    }
                } catch(err) {}
            }
        }, true);
    })();
    """
    
    public final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var currentLoadedVideoId: String?
        weak var targetWebView: WKWebView?
        var isActuallyPlaying: Bool = false
        var didClickAutoPlay: Bool = false
        var clickAttempts: Int = 0
        
        deinit {
            Task { @MainActor in
                if PlayerManager.shared.currentVideo == nil {
                    PlayerManager.shared.hasActiveMainPlayer = false
                }
            }
        }
        
        func ensureAutoPlay(on view: WKWebView) {
            guard !isActuallyPlaying else { return }
            guard clickAttempts < 20 else { return }
            clickAttempts += 1
            
            // 1. Direct JavaScript commands to player and iframe
            let js = """
            (function() {
                var ifr = document.querySelector('iframe');
                if (ifr && ifr.contentWindow) {
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "playVideo", args: []}), '*');
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "unMute", args: []}), '*');
                    ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setVolume", args: [100]}), '*');
                    ifr.contentWindow.postMessage(JSON.stringify({event: "listening"}), '*');
                }
            })();
            """
            view.evaluateJavaScript(js, completionHandler: nil)
            
            // Direct postMessage already triggers playback without UI bezel side-effects
            
            // Retry after 0.25s until isActuallyPlaying becomes true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak view] in
                guard let self = self, let v = view else { return }
                if !self.isActuallyPlaying && self.clickAttempts < 20 {
                    self.ensureAutoPlay(on: v)
                }
            }
        }
        
        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "playerBridge",
                  let body = message.body as? [String: Any] else { return }
            
            DispatchQueue.main.async {
                if let type = body["type"] as? String, type == "videoDimensions" {
                    let isVertical = (body["isVertical"] as? Bool) 
                        ?? ((body["isVertical"] as? NSNumber)?.boolValue) 
                        ?? false
                    let width: Double = {
                        if let d = body["width"] as? Double { return d }
                        if let n = body["width"] as? NSNumber { return n.doubleValue }
                        if let i = body["width"] as? Int { return Double(i) }
                        return 16.0
                    }()
                    let height: Double = {
                        if let d = body["height"] as? Double { return d }
                        if let n = body["height"] as? NSNumber { return n.doubleValue }
                        if let i = body["height"] as? Int { return Double(i) }
                        return 9.0
                    }()
                    PlayerManager.shared.updateVideoDimensions(
                        isVertical: isVertical || (height > width && height > 0),
                        width: width,
                        height: height
                    )
                    return
                }
                
                if let type = body["type"] as? String, type == "toggleFullscreen" {
                    PlayerManager.shared.toggleFullscreen()
                    return
                }
                
                if let type = body["type"] as? String, type == "pipStateChange", let isActive = body["isActive"] as? Bool {
                    PlayerManager.shared.isPictureInPictureActive = isActive
                    return
                }
                
                if let type = body["type"] as? String, type == "playbackEnded" {
                    PlayerManager.shared.handlePlaybackEnded()
                    return
                }
                
                if let type = body["type"] as? String, type == "buffering", let isBuff = body["isBuffering"] as? Bool {
                    PlayerManager.shared.handleBufferingChange(isBuffering: isBuff)
                    return
                }
                
                if let type = body["type"] as? String, type == "togglePlayPause" {
                    PlayerManager.shared.togglePlayPause()
                    return
                }
                
                if let type = body["type"] as? String, type == "playerReady" {
                    self.clickAttempts = 0
                    if let wv = self.targetWebView {
                        self.ensureAutoPlay(on: wv)
                    }
                    return
                }
                
                if let type = body["type"] as? String, type == "qualityChange",
                   let q = body["quality"] as? String {
                    let cleanQ: String
                    switch q.lowercased() {
                    case "highres": cleanQ = "4320"
                    case "hd2880": cleanQ = "2880"
                    case "hd2160": cleanQ = "2160"
                    case "hd1440": cleanQ = "1440"
                    case "hd1080": cleanQ = "1080"
                    case "hd720": cleanQ = "720"
                    case "large": cleanQ = "480"
                    case "medium": cleanQ = "360"
                    case "small": cleanQ = "240"
                    case "tiny": cleanQ = "144"
                    default: cleanQ = q
                    }
                    DispatchQueue.main.async {
                        if PlayerManager.shared.currentQuality != cleanQ && cleanQ != "auto" && cleanQ != "default" {
                            PlayerManager.shared.currentQuality = cleanQ
                        }
                    }
                    return
                }
                
                if let type = body["type"] as? String, type == "availableQualities" {
                    var rawLevels: [String] = []
                    if let strLevels = body["levels"] as? [String] {
                        rawLevels = strLevels
                    } else if let arr = body["levels"] as? [Any] {
                        rawLevels = arr.compactMap { "\($0)" }
                    }
                    let heights: [Int] = rawLevels.compactMap { lvl in
                        switch lvl.lowercased() {
                        case "highres": return 4320
                        case "hd2880": return 2880
                        case "hd2160": return 2160
                        case "hd1440": return 1440
                        case "hd1080": return 1080
                        case "hd720": return 720
                        case "large": return 480
                        case "medium": return 360
                        case "small": return 240
                        case "tiny": return 144
                        default: return nil
                        }
                    }
                    let unique = Array(Set(heights)).sorted(by: >)
                    DispatchQueue.main.async {
                        if !unique.isEmpty && PlayerManager.shared.availableQualities != unique {
                            PlayerManager.shared.availableQualities = unique
                            PlayerManager.shared.reevaluateAndApplyOptimalQuality()
                        }
                        if let cur = body["currentQuality"] as? String, !cur.isEmpty {
                            let cleanQ: String
                            switch cur.lowercased() {
                            case "highres": cleanQ = "4320"
                            case "hd2880": cleanQ = "2880"
                            case "hd2160": cleanQ = "2160"
                            case "hd1440": cleanQ = "1440"
                            case "hd1080": cleanQ = "1080"
                            case "hd720": cleanQ = "720"
                            case "large": cleanQ = "480"
                            case "medium": cleanQ = "360"
                            case "small": cleanQ = "240"
                            case "tiny": cleanQ = "144"
                            default: cleanQ = cur
                            }
                            if cleanQ != "auto" && cleanQ != "default" && !cleanQ.isEmpty && PlayerManager.shared.currentQuality != cleanQ {
                                PlayerManager.shared.currentQuality = cleanQ
                            }
                        }
                    }
                    return
                }
                
                if let type = body["type"] as? String, type == "stateChange" {
                    let msgVideoId = body["videoId"] as? String
                    if let msgVid = msgVideoId, !msgVid.isEmpty, let currentVid = PlayerManager.shared.currentVideo?.id, msgVid != currentVid {
                        return
                    }
                    if let playing = body["isPlaying"] as? Bool {
                        PlayerManager.shared.updatePlaybackSync(
                            currentTime: PlayerManager.shared.currentTime,
                            duration: PlayerManager.shared.duration,
                            isPlaying: playing,
                            isMuted: nil,
                            source: "main",
                            videoId: msgVideoId
                        )
                    }
                    return
                }
                
                if let type = body["type"] as? String, type == "directSync" {
                    let msgVideoId = body["videoId"] as? String
                    if let msgVid = msgVideoId, !msgVid.isEmpty, let currentVid = PlayerManager.shared.currentVideo?.id, msgVid != currentVid {
                        return
                    }
                    guard let currentTime = body["currentTime"] as? Double, !currentTime.isNaN else { return }
                    let duration = body["duration"] as? Double ?? PlayerManager.shared.duration
                    let isPlaying = body["isPlaying"] as? Bool
                    
                    if let playing = isPlaying, playing && currentTime > 0.05 {
                        self.isActuallyPlaying = true
                        self.didClickAutoPlay = true
                    }
                    
                    PlayerManager.shared.updatePlaybackSync(
                        currentTime: currentTime,
                        duration: duration,
                        isPlaying: isPlaying,
                        isMuted: nil,
                        source: "main",
                        videoId: msgVideoId
                    )
                    return
                }
                
                // Fallback: Only accept explicit currentTime if it is a valid number
                if let cur = body["currentTime"] as? Double, !cur.isNaN {
                    let msgVideoId = body["videoId"] as? String
                    if let msgVid = msgVideoId, !msgVid.isEmpty, let currentVid = PlayerManager.shared.currentVideo?.id, msgVid != currentVid {
                        return
                    }
                    let duration = body["duration"] as? Double ?? PlayerManager.shared.duration
                    let isPlaying = body["isPlaying"] as? Bool
                    PlayerManager.shared.updatePlaybackSync(
                        currentTime: cur,
                        duration: duration,
                        isPlaying: isPlaying,
                        isMuted: nil,
                        source: "main",
                        videoId: msgVideoId
                    )
                }
            }
        }
        
        public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            let host = url.host?.lowercased() ?? ""
            let scheme = url.scheme?.lowercased() ?? ""
            
            if scheme == "about" || scheme == "blob" || scheme == "data" {
                decisionHandler(.allow)
                return
            }
            
            let isAllowed = host == "auratube.app" ||
                            host.hasSuffix(".youtube.com") || host == "youtube.com" ||
                            host.hasSuffix(".youtube-nocookie.com") || host == "youtube-nocookie.com" ||
                            host.hasSuffix(".googlevideo.com") || host == "googlevideo.com" ||
                            host.hasSuffix(".ytimg.com") || host == "ytimg.com"
                            
            if isAllowed {
                decisionHandler(.allow)
            } else {
                if navigationAction.navigationType == .linkActivated {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
            }
        }
    }
}
