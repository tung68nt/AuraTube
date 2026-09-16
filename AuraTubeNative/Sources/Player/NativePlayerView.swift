import SwiftUI
import AppKit
import WebKit

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
}

public struct NativePlayerView: NSViewRepresentable {
    @ObservedObject var playerManager: PlayerManager = .shared
    
    public init() {}
    
    public func makeCoordinator() -> Coordinator {
        if let existing = MainWebPlayerPool.shared.coordinator {
            return existing
        }
        let coord = Coordinator()
        MainWebPlayerPool.shared.coordinator = coord
        return coord
    }
    
    public func makeNSView(context: Context) -> WKWebView {
        playerManager.hasActiveMainPlayer = true
        
        if let existing = MainWebPlayerPool.shared.webView {
            existing.removeFromSuperview()
            context.coordinator.targetWebView = existing
            setupBridgeCallbacks(for: existing)
            return existing
        }
        
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.preferences.setValue(true, forKey: "fullScreenEnabled")
        
        // Bypass WebKit user activation restrictions for autoplay and unmuted audio
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
        
        let cleanScript = NativePlayerView.cleanScriptSource
        // Inject cleanScript at document start (in .page, .defaultClient, and default world) so YouTube's top chrome bar
        // (.ytp-chrome-top, channel info, avatar, and Cairo refresh badges) is hidden BEFORE DOM layout or rendering
        let userScriptStartPage = WKUserScript(source: cleanScript, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)
        contentController.addUserScript(userScriptStartPage)
        let userScriptStartClient = WKUserScript(source: cleanScript, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient)
        contentController.addUserScript(userScriptStartClient)
        let userScriptStartDefault = WKUserScript(source: cleanScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(userScriptStartDefault)
        
        let userScriptEndPage = WKUserScript(source: cleanScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: .page)
        contentController.addUserScript(userScriptEndPage)
        let userScriptEndClient = WKUserScript(source: cleanScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: .defaultClient)
        contentController.addUserScript(userScriptEndClient)
        let userScriptEndDefault = WKUserScript(source: cleanScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        contentController.addUserScript(userScriptEndDefault)
        config.userContentController = contentController
        
        let webView = ScrollForwardingWKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        
        MainWebPlayerPool.shared.webView = webView
        context.coordinator.targetWebView = webView
        setupBridgeCallbacks(for: webView)
        
        return webView
    }
    
    private func setupBridgeCallbacks(for webView: WKWebView) {
        // Connect PlayerManager bridge actions
        playerManager.onPlayPause = { [weak webView] shouldPlay in
            let cmd = shouldPlay ? "playVideo" : "pauseVideo"
            let js = """
            var ifr = document.getElementById('ytPlayer');
            if (ifr && ifr.contentWindow) {
                ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "\(cmd)", args: []}), '*');
            }
            """
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
        
        playerManager.onSeek = { [weak webView] targetSeconds in
            let js = """
            currentTime = \(targetSeconds);
            var ifr = document.getElementById('ytPlayer');
            if (ifr && ifr.contentWindow) {
                ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "seekTo", args: [\(targetSeconds), true]}), '*');
            }
            if (typeof postSync === 'function') { postSync(); }
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
            let ytQuality: String
            switch quality {
            case "2160": ytQuality = "hd2160"
            case "1440": ytQuality = "hd1440"
            case "1080": ytQuality = "hd1080"
            case "720": ytQuality = "hd720"
            case "480": ytQuality = "large"
            case "360": ytQuality = "medium"
            case "240": ytQuality = "small"
            case "144": ytQuality = "tiny"
            default: ytQuality = "default"
            }
            let js = """
            (function() {
                var ifr = document.getElementById('ytPlayer');
                if (ifr && ifr.contentWindow) {
                    ifr.contentWindow.postMessage(JSON.stringify({
                        type: 'forceQuality',
                        quality: '\(quality)',
                        ytQuality: '\(ytQuality)'
                    }), '*');
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
            })();
            """
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
    
    public func updateNSView(_ nsView: WKWebView, context: Context) {
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
                // Video switch: Use loadNewVideo with startPos=0 and quality preference
                let q = (playerManager.selectedQuality != "auto") ? playerManager.selectedQuality : "1080"
                let js = "if (typeof window.loadNewVideo === 'function') { window.loadNewVideo('\(video.id)', 0, '\(q)'); } else { location.reload(); }"
                nsView.evaluateJavaScript(js) { [weak nsView, weak coord = context.coordinator] _, err in
                    if err != nil {
                        guard let v = nsView else { return }
                        let html = NativePlayerView.generateHTML(for: video, playerManager: PlayerManager.shared)
                        v.loadHTMLString(html, baseURL: URL(string: "https://auratube.app"))
                    }
                    if let v = nsView, let c = coord {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            c.ensureAutoPlay(on: v)
                        }
                    }
                }
            } else {
                // Initial load
                let html = NativePlayerView.generateHTML(for: video, playerManager: playerManager)
                nsView.loadHTMLString(html, baseURL: URL(string: "https://auratube.app"))
                
                let coord = context.coordinator
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak nsView, weak coord] in
                    guard let v = nsView, let c = coord else { return }
                    c.ensureAutoPlay(on: v)
                }
            }
        }
    }
    
    public static func generateHTML(for video: Video, playerManager: PlayerManager) -> String {
        let startPos = max(0, Int(playerManager.currentTime))
        let qParam = (playerManager.selectedQuality != "auto") ? "hd\(playerManager.selectedQuality)" : "hd1080"
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <meta name="referrer" content="origin">
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          html, body { width: 100%; height: 100%; overflow: hidden; background: #000 !important; }
          .player-wrapper {
            position: relative;
            width: 100%;
            height: 100%;
            overflow: hidden;
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
            src="https://www.youtube.com/embed/\(video.id)?autoplay=1&mute=1&playsinline=1&controls=0&enablejsapi=1&rel=0&modestbranding=1&fs=1&origin=https://auratube.app&widget_referrer=https://auratube.app&start=\(startPos)&vq=\(qParam)" 
            allow="autoplay; encrypted-media; picture-in-picture; fullscreen" 
            allowfullscreen="true">
        </iframe>
        </div>
        <script>
          var isPlaying = true;
          var isMuted = \(playerManager.isMuted ? "true" : "false");
          var currentVolume = \(max(0, min(100, Int(playerManager.volume * 100))));
          var currentVideoId = '\(video.id)';

          function ensureAudioPlayback() {
            var ifr = document.getElementById('ytPlayer');
            if (ifr && ifr.contentWindow) {
              try {
                ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "playVideo", args: []}), '*');
                if (!isMuted) {
                  ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "unMute", args: []}), '*');
                  ifr.contentWindow.postMessage(JSON.stringify({event: "command", func: "setVolume", args: [currentVolume]}), '*');
                }
              } catch(e) {}
            }
          }

          window.loadNewVideo = function(newId, startSec, targetQuality) {
            isPlaying = true;
            currentVideoId = newId;
            var start = startSec || 0;
            var q = targetQuality ? ('hd' + targetQuality) : 'hd1080';
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
                
                setTimeout(ensureAudioPlayback, 80);
                setTimeout(ensureAudioPlayback, 200);
                setTimeout(ensureAudioPlayback, 500);
              } catch(e) {}
            }
            postStateSync();
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
                } else if (state === 2 || state === 0) {
                  isPlaying = false;
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
                  if (data.info.playerState === 1) isPlaying = true;
                  else if (data.info.playerState === 2 || data.info.playerState === 0) isPlaying = false;
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
                `;
                    target.appendChild(s);
                }
            } catch(e) {}

            // Fast targeted cleanup of badges, top channel branding, pause cards and native controls
            try {
                var badges = document.querySelectorAll(
                    '.ytPlayerOverlayVideoDetailsRendererHost, .ytPlayerOverlayVideoDetailsRendererTitle, .ytPlayerOverlayVideoDetailsRendererSubtitle, .ytPlayerOverlayVideoDetailsRendererChannelAvatarContainer, .ytPlayerOverlayVideoDetailsRendererTextContainer, .ytPlayerOverlayVideoDetailsRendererFrostedGlass, [class*="ytPlayerOverlayVideoDetailsRenderer"], [class*="ytwPlayerTopControls"], [class*="ytmWatchPlayerControls"], [class*="ytmVideoInfo"], [class*="VideoDetailsRenderer"], ytw-player-top-controls, yt-player-overlay-video-details-renderer, ytm-video-info-flyout, .ytwPlayerTopControlsHost, .ytmWatchPlayerControlsHost, ' +
                    '.ytp-paid-content-overlay, .ytp-paid-content-overlay-link, [class*="paid-content"], [class*="paid-promotion"], ' +
                    'a[href*="support.google.com/youtube?p=ppp"], a[href*="support.google.com/youtube/answer/154235"], ' +
                    '.ytp-suggested-action-badge, .ytp-suggested-action, .ytp-ai-info-dialog, .ytp-content-disclosure, ' +
                    '[class*="ai-disclosure"], [class*="content-disclosure"], [class*="suggested-action"], [aria-label*="AI" i], ' +
                    '.ytp-popup, .ytp-panel-popup, .ytp-pause-overlay, .ytp-bezel, .ytp-large-play-button, .ytp-large-play-button-bg, ' +
                    '.ytp-chrome-top, .ytp-gradient-top, .ytp-gradient-bottom, .ytp-title, .ytp-title-channel, .ytp-title-channel-logo, .ytp-title-channel-text, .ytp-title-text, .ytp-title-subtext, .ytp-title-link, ' +
                    '.ytp-chrome-bottom, .ytp-progress-bar-container, .ytp-fullscreen-button, ' +
                    '[class*="title-channel"], [class*="channel-logo"], [class*="channel-name"], [class*="channel-avatar"], [class*="channel-subscribers"], [class*="chrome-top"], [class*="cairo-refresh"], ' +
                    '.ytp-cairo-refresh-header, .ytp-cairo-refresh-signature-moments, .ytp-cairo-refresh-channel-avatar, .ytp-cairo-refresh-channel-name'
                );
                for (var b = 0; b < badges.length; b++) {
                    var el = badges[b];
                    try {
                        el.style.setProperty('display', 'none', 'important');
                        el.style.setProperty('opacity', '0', 'important');
                        el.style.setProperty('visibility', 'hidden', 'important');
                        el.style.setProperty('pointer-events', 'none', 'important');
                        el.style.setProperty('height', '0', 'important');
                        el.style.setProperty('width', '0', 'important');
                        el.style.setProperty('max-height', '0', 'important');
                        el.style.setProperty('position', 'absolute', 'important');
                        el.style.setProperty('top', '-9999px', 'important');
                        el.style.setProperty('left', '-9999px', 'important');
                        el.remove();
                    } catch(err) {}
                }
            } catch(err) {}
        }
        try { applyStyles(); } catch(e) {}
        try { document.addEventListener('DOMContentLoaded', applyStyles); } catch(e) {}
        try { window.addEventListener('load', applyStyles); } catch(e) {}
        try { document.addEventListener('pointermove', applyStyles); } catch(e) {}
        try { document.addEventListener('mousemove', applyStyles); } catch(e) {}

        var fastInterval = setInterval(applyStyles, 60);
        setTimeout(function() {
            clearInterval(fastInterval);
            setInterval(applyStyles, 180);
        }, 4000);

        try {
            var mo = new MutationObserver(function() {
                applyStyles();
            });
            if (document.documentElement) {
                mo.observe(document.documentElement, { childList: true, subtree: true });
            } else {
                document.addEventListener('DOMContentLoaded', function() {
                    try {
                        if (document.documentElement) mo.observe(document.documentElement, { childList: true, subtree: true });
                    } catch(e) {}
                });
            }
        } catch(e) {}

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
                var btns = document.querySelectorAll(
                    '.ytp-large-play-button, button.ytp-large-play-button, .ytp-large-play-button-bg, .ytp-cairo-refresh-signature-moments, .ytp-play-button'
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
        function autoStartPlayback() {
            try {
                clickLargePlay();
                var v = document.querySelector('video');
                if (v) {
                    if (v.paused) {
                        var p = v.play();
                        if (p !== undefined) {
                            p.then(function() {
                                autoPlayDone = true;
                            }).catch(function() {});
                        }
                    } else if (v.currentTime > 0.05) {
                        autoPlayDone = true;
                    }
                    if (!v.paused && v.currentTime > 0.02 && !v.__auratube_unmuted) {
                        v.__auratube_unmuted = true;
                        v.muted = false;
                        v.volume = 1.0;
                    }
                }
                var player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                if (player) {
                    if (typeof player.playVideo === 'function') player.playVideo();
                    if (typeof player.unMute === 'function') player.unMute();
                    if (typeof player.setVolume === 'function') player.setVolume(100);
                }
            } catch(err) {}
        }

        var autoPlayInterval = setInterval(autoStartPlayback, 100);
        setTimeout(function() { clearInterval(autoPlayInterval); }, 4000);
        document.addEventListener('DOMContentLoaded', autoStartPlayback);
        window.addEventListener('load', autoStartPlayback);

        // Hook HTML5 video element directly for real-time timeline & playback sync
        function hookVideoDirect() {
            try {
                var v = document.querySelector('video');
                if (!v || v.__auratube_hooked) return;
                v.__auratube_hooked = true;
                
                function emitDirectSync() {
                    try {
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
                                currentTime: v.currentTime,
                                duration: v.duration || 0,
                                isPlaying: !v.paused && !v.ended
                            });
                        }
                    } catch(e) {}
                }
                
                v.addEventListener('timeupdate', emitDirectSync);
                v.addEventListener('play', function() {
                    emitDirectSync();
                    autoStartPlayback();
                });
                v.addEventListener('pause', emitDirectSync);
                v.addEventListener('playing', function() {
                    emitDirectSync();
                    autoStartPlayback();
                });
                v.addEventListener('ended', function() {
                    emitDirectSync();
                    try {
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                            window.webkit.messageHandlers.playerBridge.postMessage({ type: 'playbackEnded' });
                        }
                    } catch(e) {}
                });
                v.addEventListener('seeked', emitDirectSync);
                
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
                
                // High-precision clock tick while playing (every 120ms) to ensure continuous frame-accurate stream
                setInterval(function() {
                    if (!v.paused && !v.ended) {
                        emitDirectSync();
                    }
                }, 120);
            } catch(err) {}
        }
        hookVideoDirect();
        setInterval(hookVideoDirect, 300);

        // Intercept Fullscreen clicks to toggle native macOS window fullscreen
        function triggerFullscreen(e) {
            e.preventDefault();
            e.stopPropagation();
            e.stopImmediatePropagation();
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

        // Quality reporting & active control
        function checkAndReportQualities() {
            try {
                var p = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                if (!p) return;
                var levels = (typeof p.getAvailableQualityLevels === 'function') ? p.getAvailableQualityLevels() : [];
                var cur = (typeof p.getPlaybackQuality === 'function') ? p.getPlaybackQuality() : '';
                if (levels && levels.length > 0) {
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
        setInterval(checkAndReportQualities, 1500);
        setTimeout(checkAndReportQualities, 800);

        function reportVideoDimensions() {
            try {
                var v = document.querySelector('video');
                if (v && v.videoWidth > 0 && v.videoHeight > 0) {
                    var isVertical = v.videoHeight > v.videoWidth;
                    var payload = {
                        type: 'videoDimensions',
                        isVertical: isVertical,
                        width: v.videoWidth,
                        height: v.videoHeight
                    };
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerBridge) {
                        window.webkit.messageHandlers.playerBridge.postMessage(payload);
                    }
                }
            } catch(e) {}
        }
        document.addEventListener('loadedmetadata', reportVideoDimensions, true);
        document.addEventListener('loadeddata', reportVideoDimensions, true);
        document.addEventListener('playing', reportVideoDimensions, true);
        document.addEventListener('timeupdate', reportVideoDimensions, true);
        document.addEventListener('resize', reportVideoDimensions, true);
        setInterval(reportVideoDimensions, 1200);

        function forceQualityChange(targetQuality, retries) {
            retries = retries || 0;
            try {
                var p = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                if (!p) return;

                var ytQuality = 'default';
                switch (targetQuality) {
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
                    default: ytQuality = 'default'; break;
                }

                // 1. Save quality in localStorage so YouTube preserves the user's resolution
                try {
                    if (targetQuality !== 'auto') {
                        localStorage.setItem('yt-player-quality', JSON.stringify({
                            data: ytQuality,
                            creation: Date.now()
                        }));
                    } else {
                        localStorage.removeItem('yt-player-quality');
                    }
                } catch(e) {}

                // 2. Direct player methods with exact matched quality from getAvailableQualityData
                var targetFormatQuality = ytQuality;
                if (typeof p.getAvailableQualityData === 'function') {
                    var qData = p.getAvailableQualityData() || [];
                    for (var i = 0; i < qData.length; i++) {
                        var item = qData[i];
                        if (targetQuality === 'auto') {
                            if (item.quality === 'auto' || item.quality === 'default') {
                                targetFormatQuality = item.quality;
                                break;
                            }
                        } else {
                            var qLbl = (item.qualityLabel || '').toLowerCase();
                            if (qLbl.startsWith(targetQuality) || qLbl.includes(targetQuality + 'p') || item.quality === ytQuality) {
                                targetFormatQuality = item.quality;
                                break;
                            }
                        }
                    }
                }

                if (typeof p.setPlaybackQualityRange === 'function') {
                    p.setPlaybackQualityRange(targetFormatQuality, targetFormatQuality);
                }
                if (typeof p.setPlaybackQuality === 'function') {
                    p.setPlaybackQuality(targetFormatQuality);
                }

                // 3. Seamlessly switch video stream to target resolution using suggestedQuality
                if (targetQuality !== 'auto' && typeof p.loadVideoById === 'function') {
                    var v = document.querySelector('video');
                    var curTime = (v && v.currentTime) ? v.currentTime : 0;
                    var vidData = (typeof p.getVideoData === 'function') ? p.getVideoData() : null;
                    var currentVid = (vidData && vidData.video_id) ? vidData.video_id : '';
                    if (currentVid && v && !v.paused && curTime > 0.05) {
                        p.loadVideoById({
                            videoId: currentVid,
                            startSeconds: curTime,
                            suggestedQuality: targetFormatQuality
                        });
                        p.unMute();
                        p.setVolume(100);
                        p.playVideo();
                    }
                }

                // 4. Fallback settings menu click if present
                var settingsBtn = p.querySelector('.ytp-settings-button');
                if (settingsBtn) {
                    var stealth = document.getElementById('auratube-stealth-style');
                    if (!stealth) {
                        stealth = document.createElement('style');
                        stealth.id = 'auratube-stealth-style';
                        stealth.innerHTML = '.ytp-settings-menu, .ytp-panel-popup { opacity: 0 !important; pointer-events: none !important; }';
                        (document.head || document.documentElement).appendChild(stealth);
                    }

                    settingsBtn.click();
                    setTimeout(function() {
                        var items = p.querySelectorAll('.ytp-menuitem');
                        var qMenu = null;
                        for (var i = 0; i < items.length; i++) {
                            var t = (items[i].textContent || '').toLowerCase();
                            if (t.includes('chất lượng') || t.includes('quality') || 
                                t.includes('1080') || t.includes('720') || t.includes('480') ||
                                t.includes('360') || t.includes('2160') || t.includes('1440') ||
                                t.includes('tự động') || t.includes('auto')) {
                                qMenu = items[i];
                                break;
                            }
                        }
                        if (qMenu) {
                            qMenu.click();
                            setTimeout(function() {
                                var subItems = p.querySelectorAll('.ytp-menuitem');
                                var matched = null;
                                for (var j = 0; j < subItems.length; j++) {
                                    var text = (subItems[j].textContent || '').toLowerCase();
                                    if (targetQuality === 'auto') {
                                        if (text.includes('tự động') || text.includes('auto')) {
                                            matched = subItems[j];
                                            break;
                                        }
                                    } else {
                                        if (text.includes(targetQuality + 'p') || text.startsWith(targetQuality) || text.includes(targetQuality)) {
                                            matched = subItems[j];
                                            break;
                                        }
                                    }
                                }
                                if (matched) {
                                    matched.click();
                                }
                                settingsBtn.click();
                                setTimeout(function() {
                                    if (stealth && stealth.parentNode) {
                                        stealth.parentNode.removeChild(stealth);
                                    }
                                    checkAndReportQualities();
                                }, 50);
                            }, 50);
                        } else {
                            settingsBtn.click();
                            if (stealth && stealth.parentNode) {
                                stealth.parentNode.removeChild(stealth);
                            }
                        }
                    }, 50);
                }

                setTimeout(checkAndReportQualities, 300);
                setTimeout(checkAndReportQualities, 1000);
            } catch(e) {}
        }

        window.addEventListener('message', function(e) {
            try {
                var data = typeof e.data === 'string' ? JSON.parse(e.data) : e.data;
                if (!data) return;
                if (data.type === 'forceQuality') {
                    forceQualityChange(data.quality);
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
            } catch(err) {}
        });
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
                    let isVertical = body["isVertical"] as? Bool ?? false
                    let width = body["width"] as? Double ?? 16
                    let height = body["height"] as? Double ?? 9
                    PlayerManager.shared.updateVideoDimensions(isVertical: isVertical, width: width, height: height)
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
                        if !unique.isEmpty {
                            PlayerManager.shared.availableQualities = unique
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
                            if cleanQ != "auto" && cleanQ != "default" && !cleanQ.isEmpty {
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
    }
}
