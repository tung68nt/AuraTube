import Foundation

public final class YTDLPService: @unchecked Sendable {
    public static let shared = YTDLPService()
    
    private let ytDlpPaths = [
        Bundle.main.resourcePath.map { "\($0)/bin/yt-dlp" } ?? "",
        "/opt/homebrew/bin/yt-dlp",
        "/usr/local/bin/yt-dlp",
        "/usr/bin/yt-dlp"
    ]
    
    private var binaryPath: String {
        for path in ytDlpPaths where !path.isEmpty && FileManager.default.fileExists(atPath: path) {
            return path
        }
        return "/opt/homebrew/bin/yt-dlp"
    }
    
    private init() {}
    
    // MARK: - Direct Stream Extraction (AVPlayer)
    
    public func getStreamInfo(videoId: String, quality: String = "1080") async throws -> StreamInfo {
        guard videoId.range(of: "^[a-zA-Z0-9_-]{11}$", options: .regularExpression) != nil else {
            throw NSError(domain: "YTDLPService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid video ID format"])
        }
        let ytdlp = binaryPath
        guard FileManager.default.fileExists(atPath: ytdlp) else {
            throw NSError(domain: "YTDLPService", code: 404, userInfo: [NSLocalizedDescriptionKey: "yt-dlp binary not found at \(ytdlp)"])
        }
        
        let formatFilter: String
        switch quality {
        case "audio":
            formatFilter = "bestaudio[protocol=https]/bestaudio/140/best"
        case "mini", "360":
            formatFilter = "best[height<=360][protocol=m3u8_native]/best[height<=360][protocol=m3u8]/bestvideo[height<=360]+bestaudio/best"
        case "shorts":
            formatFilter = "bestvideo[height<=1280][ext=mp4][vcodec^=avc1]+bestaudio[ext=m4a]/bestvideo[height<=1280][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=1280]+bestaudio/best"
        case "720":
            formatFilter = "best[height<=720][protocol=m3u8_native]/best[height<=720][protocol=m3u8]/bestvideo[height<=720]+bestaudio/best"
        default: // 1080p
            formatFilter = "best[height<=1080][protocol=m3u8_native]/best[height<=1080][protocol=m3u8]/best[protocol=m3u8_native]/best[protocol=m3u8]/bestvideo+bestaudio/best"
        }
        
        let output = try await runProcess(executable: ytdlp, arguments: [
            "--get-url",
            "-f", formatFilter,
            "--no-warnings",
            "--no-playlist",
            "--",
            "https://www.youtube.com/watch?v=\(videoId)"
        ])
        
        let lines = output.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let firstUrlStr = lines.first, let firstUrl = URL(string: firstUrlStr) else {
            throw NSError(domain: "YTDLPService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to extract video stream URL"])
        }
        
        let secondUrl = lines.count > 1 ? URL(string: lines[1]) : nil
        return StreamInfo(
            videoId: videoId,
            title: "",
            videoUrl: firstUrl,
            audioUrl: secondUrl,
            isCombined: secondUrl == nil,
            resolution: "\(quality)p"
        )
    }
    
    // MARK: - InnerTube Fast Search & Trending API (<1s, pure native)
    
    public struct SearchResultPage {
        public let channel: ChannelInfo?
        public let videos: [Video]
        public let shorts: [Video]
        public let continuationToken: String?
        public let relatedSearches: [String]
        public let contextualChips: [String]
        
        public init(
            channel: ChannelInfo? = nil,
            videos: [Video],
            shorts: [Video] = [],
            continuationToken: String? = nil,
            relatedSearches: [String] = [],
            contextualChips: [String] = []
        ) {
            self.channel = channel
            self.videos = videos
            self.shorts = shorts
            self.continuationToken = continuationToken
            self.relatedSearches = relatedSearches
            self.contextualChips = contextualChips
        }
        
        public var allItems: [Video] {
            return videos + shorts
        }
    }
    
    public struct ChannelDetailResult {
        public let channel: ChannelInfo
        public let bannerUrl: String?
        public let videos: [Video]
        public let continuationToken: String?
        
        public init(
            channel: ChannelInfo,
            bannerUrl: String? = nil,
            videos: [Video] = [],
            continuationToken: String? = nil
        ) {
            self.channel = channel
            self.bannerUrl = bannerUrl
            self.videos = videos
            self.continuationToken = continuationToken
        }
    }
    
    // InnerTube filter parameters for fresh trending content
    public static let filterThisWeek = "EgQIAxAB"
    public static let filterThisMonth = "EgQIBBAB"
    public static let filterToday = "EgQIAhAB"
    
    public func fetchTrendingVideos(region: String = "VN") async -> [Video] {
        return await RecommendationService.shared.fetchVietnamTrendingFeed()
    }
    
    public func fetchTrendingVideosWithContinuation(region: String = "VN", continuationToken: String? = nil) async -> SearchResultPage {
        let trending = await RecommendationService.shared.fetchVietnamTrendingFeed()
        let regular = trending.filter { !$0.isShort }
        let shorts = trending.filter { $0.isShort }
        return SearchResultPage(channel: nil, videos: regular, shorts: shorts, continuationToken: nil)
    }
    
    public func searchVideos(query: String, params: String? = nil, limit: Int = 24) async -> [Video] {
        let page = await searchVideosWithContinuation(query: query, continuationToken: nil, params: params, limit: limit)
        return page.allItems
    }
    
    public func searchVideosWithContinuation(query: String, continuationToken: String? = nil, params: String? = nil, limit: Int = 24) async -> SearchResultPage {
        // 1. Try high-speed InnerTube API first
        if let result = await searchViaInnerTube(query: query, continuationToken: continuationToken, params: params),
           (!result.videos.isEmpty || !result.shorts.isEmpty || result.channel != nil) {
            
            // If this is initial search page (not continuation), enrich with related searches & taste re-ranking
            if continuationToken == nil {
                async let relatedTask = RecommendationService.shared.fetchRelatedSearchQueries(for: query)
                async let chipsTask = RecommendationService.shared.fetchContextualSearchChips(for: query)
                let (related, chips) = await (relatedTask, chipsTask)
                let rankedVideos = await RecommendationService.shared.rankSearchResults(videos: result.videos, query: query)
                
                return SearchResultPage(
                    channel: result.channel,
                    videos: rankedVideos,
                    shorts: result.shorts,
                    continuationToken: result.continuationToken,
                    relatedSearches: related,
                    contextualChips: chips
                )
            }
            
            return result
        }
        
        // If continuation was requested but InnerTube didn't return results, don't fallback to flat playlist
        if continuationToken != nil {
            return SearchResultPage(channel: nil, videos: [], shorts: [], continuationToken: nil)
        }
        
        // If params was specified (filtered trending/date filter), never fallback to slow unfiltered yt-dlp
        if params != nil {
            return SearchResultPage(channel: nil, videos: [], shorts: [], continuationToken: nil)
        }
        
        // 2. Fallback to local yt-dlp flat-playlist CLI (initial query only)
        let fallback = await searchViaYtDlp(query: query, limit: limit)
        let rankedFallback = await RecommendationService.shared.rankSearchResults(videos: fallback, query: query)
        async let relatedTask = RecommendationService.shared.fetchRelatedSearchQueries(for: query)
        async let chipsTask = RecommendationService.shared.fetchContextualSearchChips(for: query)
        let (related, chips) = await (relatedTask, chipsTask)
        
        return SearchResultPage(
            channel: nil,
            videos: rankedFallback,
            shorts: [],
            continuationToken: nil,
            relatedSearches: related,
            contextualChips: chips
        )
    }
    
    /// Fast YouTube search suggestions autocomplete (<50ms)
    public func fetchSearchSuggestions(query: String) async -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        var components = URLComponents(string: "https://suggestqueries-clients6.youtube.com/complete/search")
        components?.queryItems = [
            URLQueryItem(name: "client", value: "firefox"),
            URLQueryItem(name: "ds", value: "yt"),
            URLQueryItem(name: "hl", value: "vi"),
            URLQueryItem(name: "gl", value: "VN"),
            URLQueryItem(name: "q", value: trimmed)
        ]
        guard let url = components?.url else { return [] }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 3.0
        
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count > 1,
              let suggestions = json[1] as? [String] else {
            return []
        }
        
        return suggestions
    }
    
    private func searchViaInnerTube(query: String, continuationToken: String? = nil, params: String? = nil) async -> SearchResultPage? {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/search?prettyPrint=false") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("vi,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 7.0
        
        var body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": "2.20240101.00.00",
                    "hl": "vi",
                    "gl": "VN"
                ]
            ]
        ]
        
        if let continuation = continuationToken, !continuation.isEmpty {
            body["continuation"] = continuation
        } else {
            body["query"] = query
            if let p = params, !p.isEmpty {
                body["params"] = p
            }
        }
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody
        
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        var videos: [Video] = []
        extractInnerTubeVideos(from: root, results: &videos)
        
        var shorts: [Video] = []
        let videoIds = Set(videos.map { $0.id })
        extractInnerTubeShorts(from: root, results: &shorts, existingIds: videoIds)
        
        let channel = (continuationToken == nil) ? extractInnerTubeChannel(from: root) : nil
        let nextContinuation = extractContinuationToken(from: root)
        return SearchResultPage(channel: channel, videos: videos, shorts: shorts, continuationToken: nextContinuation)
    }
    
    // MARK: - Official YouTube InnerTube Related Videos Endpoint
    public func fetchRelatedVideosViaInnerTube(videoId: String) async -> [Video] {
        guard !videoId.isEmpty, videoId.range(of: "^[a-zA-Z0-9_-]{11}$", options: .regularExpression) != nil,
              let url = URL(string: "https://www.youtube.com/youtubei/v1/next") else {
            return []
        }
        
        let clientContext: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": "2.20240101.00.00",
                    "hl": "vi",
                    "gl": "VN"
                ]
            ],
            "videoId": videoId
        ]
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        req.setValue("vi,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.timeoutInterval = 4.5
        req.httpBody = try? JSONSerialization.data(withJSONObject: clientContext)
        
        guard let (data, res) = try? await URLSession.shared.data(for: req),
              let http = res as? HTTPURLResponse, http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        
        var videos: [Video] = []
        if let contents = (root["contents"] as? [String: Any])?["twoColumnWatchNextResults"] as? [String: Any],
           let secondary = contents["secondaryResults"] as? [String: Any] {
            extractInnerTubeVideos(from: secondary, results: &videos)
        } else {
            extractInnerTubeVideos(from: root, results: &videos)
        }
        
        return videos.filter { $0.id != videoId }
    }
    
    private func extractContinuationToken(from obj: Any) -> String? {
        if let dict = obj as? [String: Any] {
            if let cir = dict["continuationItemRenderer"] as? [String: Any] {
                if let endpoint = cir["continuationEndpoint"] as? [String: Any],
                   let cmd = endpoint["continuationCommand"] as? [String: Any],
                   let token = cmd["token"] as? String, !token.isEmpty {
                    return token
                }
                if let cmd = cir["continuationCommand"] as? [String: Any],
                   let token = cmd["token"] as? String, !token.isEmpty {
                    return token
                }
            }
            if let cmd = dict["continuationCommand"] as? [String: Any],
               let token = cmd["token"] as? String, !token.isEmpty {
                return token
            }
            for (_, value) in dict {
                if let token = extractContinuationToken(from: value) {
                    return token
                }
            }
        } else if let array = obj as? [Any] {
            for element in array {
                if let token = extractContinuationToken(from: element) {
                    return token
                }
            }
        }
        return nil
    }
    
    private func extractInnerTubeChannel(from obj: Any) -> ChannelInfo? {
        if let dict = obj as? [String: Any] {
            if let cr = dict["channelRenderer"] as? [String: Any],
               let cid = cr["channelId"] as? String {
                var title = ""
                if let titleDict = cr["title"] as? [String: Any] {
                    title = titleDict["simpleText"] as? String ?? ""
                    if title.isEmpty, let runs = titleDict["runs"] as? [[String: Any]] {
                        title = runs.compactMap { $0["text"] as? String }.joined()
                    }
                }
                var handle: String? = nil
                var subs: String? = nil
                if let subDict = cr["subscriberCountText"] as? [String: Any] {
                    let text = subDict["simpleText"] as? String
                    if text?.hasPrefix("@") == true {
                        handle = text
                    } else {
                        subs = text
                    }
                }
                var avatar = ""
                if let thumbDict = cr["thumbnail"] as? [String: Any],
                   let thumbs = thumbDict["thumbnails"] as? [[String: Any]],
                   let lastUrl = thumbs.last?["url"] as? String {
                    avatar = lastUrl.hasPrefix("//") ? "https:" + lastUrl : lastUrl
                }
                var desc: String? = nil
                if let descDict = cr["descriptionSnippet"] as? [String: Any],
                   let runs = descDict["runs"] as? [[String: Any]] {
                    desc = runs.compactMap { $0["text"] as? String }.joined()
                }
                return ChannelInfo(
                    id: cid,
                    title: title.isEmpty ? "YouTube Channel" : title,
                    handle: handle,
                    subscriberCount: subs,
                    avatarUrl: avatar,
                    description: desc
                )
            }
            for (_, value) in dict {
                if let ch = extractInnerTubeChannel(from: value) {
                    return ch
                }
            }
        } else if let array = obj as? [Any] {
            for element in array {
                if let ch = extractInnerTubeChannel(from: element) {
                    return ch
                }
            }
        }
        return nil
    }
    
    private func extractInnerTubeShorts(from obj: Any, results: inout [Video], existingIds: Set<String>) {
        if let dict = obj as? [String: Any] {
            if let sl = dict["shortsLockupViewModel"] as? [String: Any] {
                var videoId = ""
                if let eid = sl["entityId"] as? String, eid.hasPrefix("shorts-shelf-item-") {
                    videoId = String(eid.dropFirst("shorts-shelf-item-".count))
                }
                if videoId.isEmpty,
                   let onTap = sl["onTap"] as? [String: Any],
                   let itCmd = onTap["innertubeCommand"] as? [String: Any],
                   let cmdMeta = itCmd["commandMetadata"] as? [String: Any],
                   let webMeta = cmdMeta["webCommandMetadata"] as? [String: Any],
                   let url = webMeta["url"] as? String, url.hasPrefix("/shorts/") {
                    videoId = String(url.dropFirst("/shorts/".count))
                }
                
                if videoId.count == 11, !existingIds.contains(videoId), !results.contains(where: { $0.id == videoId }) {
                    var title = ""
                    var views = ""
                    if let om = sl["overlayMetadata"] as? [String: Any] {
                        if let pt = om["primaryText"] as? [String: Any], let c = pt["content"] as? String {
                            title = c
                        }
                        if let st = om["secondaryText"] as? [String: Any], let c = st["content"] as? String {
                            views = c
                        }
                    }
                    let a11y = (sl["accessibilityText"] as? String) ?? ""
                    if title.isEmpty && !a11y.isEmpty {
                        title = a11y
                    }
                    
                    var thumb = "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
                    if let tvm = sl["thumbnailViewModel"] as? [String: Any],
                       let innerTvm = tvm["thumbnailViewModel"] as? [String: Any],
                       let img = innerTvm["image"] as? [String: Any],
                       let srcs = img["sources"] as? [[String: Any]],
                       let last = srcs.last?["url"] as? String {
                        thumb = last.hasPrefix("//") ? "https:" + last : last
                    }
                    
                    var uploader = ""
                    let fullText = !a11y.isEmpty ? a11y : title
                    if fullText.contains("|") {
                        let parts = fullText.split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        if parts.count >= 2 {
                            for p in parts[1...] {
                                let clean = p.replacingOccurrences(of: "#shorts", with: "", options: .caseInsensitive)
                                             .replacingOccurrences(of: "#short", with: "", options: .caseInsensitive)
                                             .trimmingCharacters(in: .whitespacesAndNewlines)
                                if !clean.isEmpty && clean.count <= 35 && !clean.lowercased().contains("lượt xem") && !clean.lowercased().contains("views") {
                                    uploader = clean
                                    break
                                }
                            }
                        }
                    }
                    if uploader.isEmpty {
                        uploader = "YouTube Creator"
                    }
                    
                    if !title.isEmpty {
                        results.append(Video(
                            id: videoId,
                            title: title,
                            uploader: uploader,
                            duration: nil,
                            durationFormatted: "Shorts",
                            viewCount: nil,
                            viewCountFormatted: views,
                            publishedTime: nil,
                            thumbnail: thumb,
                            description: nil,
                            isShort: true
                        ))
                    }
                }
            }
            
            if let rir = dict["reelItemRenderer"] as? [String: Any],
               let videoId = rir["videoId"] as? String, videoId.count == 11,
               !existingIds.contains(videoId), !results.contains(where: { $0.id == videoId }) {
                var title = ""
                if let hl = rir["headline"] as? [String: Any], let s = hl["simpleText"] as? String {
                    title = s
                }
                var views = ""
                if let vct = rir["viewCountText"] as? [String: Any], let s = vct["simpleText"] as? String {
                    views = s
                }
                var thumb = "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
                if let td = rir["thumbnail"] as? [String: Any],
                   let thumbs = td["thumbnails"] as? [[String: Any]],
                   let last = thumbs.last?["url"] as? String {
                    thumb = last.hasPrefix("//") ? "https:" + last : last
                }
                
                var uploader = ""
                if let sbt = rir["shortBylineText"] as? [String: Any],
                   let runs = sbt["runs"] as? [[String: Any]],
                   let t = runs.first?["text"] as? String, !t.isEmpty {
                    uploader = t
                } else if let ot = rir["ownerText"] as? [String: Any],
                          let runs = ot["runs"] as? [[String: Any]],
                          let t = runs.first?["text"] as? String, !t.isEmpty {
                    uploader = t
                } else if title.contains("|") {
                    let parts = title.split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if parts.count >= 2 {
                        for p in parts[1...] {
                            let clean = p.replacingOccurrences(of: "#shorts", with: "", options: .caseInsensitive)
                                         .replacingOccurrences(of: "#short", with: "", options: .caseInsensitive)
                                         .trimmingCharacters(in: .whitespacesAndNewlines)
                            if !clean.isEmpty && clean.count <= 35 {
                                uploader = clean
                                break
                            }
                        }
                    }
                }
                if uploader.isEmpty {
                    uploader = "YouTube Creator"
                }
                
                if !title.isEmpty {
                    results.append(Video(
                        id: videoId,
                        title: title,
                        uploader: uploader,
                        duration: nil,
                        durationFormatted: "Shorts",
                        viewCount: nil,
                        viewCountFormatted: views,
                        publishedTime: nil,
                        thumbnail: thumb,
                        description: nil,
                        isShort: true
                    ))
                }
            }
            
            for (_, value) in dict {
                extractInnerTubeShorts(from: value, results: &results, existingIds: existingIds)
            }
        } else if let array = obj as? [Any] {
            for element in array {
                extractInnerTubeShorts(from: element, results: &results, existingIds: existingIds)
            }
        }
    }
    
    private func extractInnerTubeVideos(from obj: Any, results: inout [Video]) {
        if let dict = obj as? [String: Any] {
            // 1. Modern lockupViewModel (YouTube Web standard for /next and search)
            if let vm = dict["lockupViewModel"] as? [String: Any],
               let cid = vm["contentId"] as? String, cid.count == 11,
               !results.contains(where: { $0.id == cid }) {
                let meta = vm["metadata"] as? [String: Any]
                let lockupMeta = meta?["lockupMetadataViewModel"] as? [String: Any]
                let title = (lockupMeta?["title"] as? [String: Any])?["content"] as? String ?? ""
                let contentType = vm["contentType"] as? String ?? ""
                
                if !title.isEmpty && contentType != "LOCKUP_CONTENT_TYPE_PLAYLIST" {
                    var uploader = "YouTube"
                    var uploaderId: String? = nil
                    var viewStr = ""
                    var publishedStr: String? = nil
                    var channelAvatar: String? = nil
                    
                    if let contentMeta = lockupMeta?["metadata"] as? [String: Any],
                       let rows = (contentMeta["contentMetadataViewModel"] as? [String: Any])?["metadataRows"] as? [[String: Any]] {
                        if let firstRow = rows.first,
                           let parts0 = firstRow["metadataParts"] as? [[String: Any]],
                           let firstPart = parts0.first,
                           let textObj = firstPart["text"] as? [String: Any],
                           let author = textObj["content"] as? String, !author.isEmpty {
                            uploader = author
                        }
                        if rows.count > 1,
                           let secondRow = rows[1]["metadataParts"] as? [[String: Any]] {
                            if secondRow.indices.contains(0) {
                                viewStr = (secondRow[0]["accessibilityLabel"] as? String)
                                    ?? ((secondRow[0]["text"] as? [String: Any])?["content"] as? String)
                                    ?? ""
                            }
                            if secondRow.indices.contains(1) {
                                publishedStr = (secondRow[1]["text"] as? [String: Any])?["content"] as? String
                            }
                        }
                    }
                    
                    if let metaImg = lockupMeta?["image"] as? [String: Any],
                       let decAvatar = metaImg["decoratedAvatarViewModel"] as? [String: Any] {
                        if let avm = decAvatar["avatar"] as? [String: Any],
                           let innerAvm = avm["avatarViewModel"] as? [String: Any],
                           let imgDict = innerAvm["image"] as? [String: Any],
                           let sources = imgDict["sources"] as? [[String: Any]],
                           let u = sources.first?["url"] as? String {
                            channelAvatar = u.hasPrefix("//") ? "https:" + u : u
                        }
                        if let ctx = decAvatar["rendererContext"] as? [String: Any],
                           let cmdCtx = ctx["commandContext"] as? [String: Any],
                           let onTap = cmdCtx["onTap"] as? [String: Any],
                           let innerCmd = onTap["innertubeCommand"] as? [String: Any],
                           let bEnd = innerCmd["browseEndpoint"] as? [String: Any],
                           let bId = bEnd["browseId"] as? String {
                            uploaderId = bId
                        }
                    }
                    
                    var thumb = "https://i.ytimg.com/vi/\(cid)/hqdefault.jpg"
                    var durationStr = "0:00"
                    if let contentImg = vm["contentImage"] as? [String: Any],
                       let thumbVM = contentImg["thumbnailViewModel"] as? [String: Any] {
                        if let imgDict = thumbVM["image"] as? [String: Any],
                           let sources = imgDict["sources"] as? [[String: Any]],
                           let lastUrl = sources.last?["url"] as? String {
                            thumb = lastUrl.hasPrefix("//") ? "https:" + lastUrl : lastUrl
                        }
                        if let overlays = thumbVM["overlays"] as? [[String: Any]] {
                            for ov in overlays {
                                if let bottom = ov["thumbnailBottomOverlayViewModel"] as? [String: Any],
                                   let badges = bottom["badges"] as? [[String: Any]] {
                                    for b in badges {
                                        if let badgeVM = b["thumbnailBadgeViewModel"] as? [String: Any],
                                           let txt = badgeVM["text"] as? String {
                                            durationStr = txt
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    let parts = durationStr.split(separator: ":").compactMap { Double($0) }
                    var parsedDuration: Double? = nil
                    if parts.count == 2 {
                        parsedDuration = parts[0] * 60 + parts[1]
                    } else if parts.count == 3 {
                        parsedDuration = parts[0] * 3600 + parts[1] * 60 + parts[2]
                    }
                    
                    let isShort = (contentType == "LOCKUP_CONTENT_TYPE_SHORTS") || (durationStr == "Shorts")
                    
                    results.append(Video(
                        id: cid,
                        title: title,
                        uploader: uploader,
                        uploaderId: uploaderId,
                        duration: parsedDuration,
                        durationFormatted: durationStr,
                        viewCount: nil,
                        viewCountFormatted: viewStr,
                        publishedTime: publishedStr,
                        thumbnail: thumb,
                        description: nil,
                        isShort: isShort ? true : (parsedDuration != nil && parsedDuration! > 65 ? false : nil),
                        channelAvatarUrl: channelAvatar
                    ))
                }
            }
            
            // 2. Legacy videoRenderer / compactVideoRenderer
            if let videoId = dict["videoId"] as? String, videoId.count == 11,
               !results.contains(where: { $0.id == videoId }) {
                
                var title = ""
                if let titleDict = dict["title"] as? [String: Any] {
                    if let runs = titleDict["runs"] as? [[String: Any]] {
                        title = runs.compactMap { $0["text"] as? String }.joined()
                    } else if let simple = titleDict["simpleText"] as? String {
                        title = simple
                    }
                }
                
                var uploader = "YouTube"
                var uploaderId: String? = nil
                if let ownerDict = dict["ownerText"] as? [String: Any],
                   let runs = ownerDict["runs"] as? [[String: Any]],
                   let firstRun = runs.first {
                    uploader = firstRun["text"] as? String ?? "YouTube"
                    if let nav = firstRun["navigationEndpoint"] as? [String: Any],
                       let browse = nav["browseEndpoint"] as? [String: Any],
                       let bId = browse["browseId"] as? String {
                        uploaderId = bId
                    }
                } else if let bylineDict = dict["shortBylineText"] as? [String: Any],
                          let runs = bylineDict["runs"] as? [[String: Any]],
                          let firstRun = runs.first {
                    uploader = firstRun["text"] as? String ?? "YouTube"
                    if let nav = firstRun["navigationEndpoint"] as? [String: Any],
                       let browse = nav["browseEndpoint"] as? [String: Any],
                       let bId = browse["browseId"] as? String {
                        uploaderId = bId
                    }
                }
                
                var durationStr = "0:00"
                if let lenDict = dict["lengthText"] as? [String: Any],
                   let simple = lenDict["simpleText"] as? String {
                    durationStr = simple
                }
                
                let parts = durationStr.split(separator: ":").compactMap { Double($0) }
                var parsedDuration: Double? = nil
                if parts.count == 2 {
                    parsedDuration = parts[0] * 60 + parts[1]
                } else if parts.count == 3 {
                    parsedDuration = parts[0] * 3600 + parts[1] * 60 + parts[2]
                }
                
                var viewStr = ""
                if let viewDict = dict["viewCountText"] as? [String: Any],
                   let simple = viewDict["simpleText"] as? String {
                    viewStr = simple
                } else if let viewDict = dict["shortViewCountText"] as? [String: Any],
                          let simple = viewDict["simpleText"] as? String {
                    viewStr = simple
                }
                
                var publishedStr: String? = nil
                if let pubDict = dict["publishedTimeText"] as? [String: Any] {
                    if let simple = pubDict["simpleText"] as? String {
                        publishedStr = simple
                    } else if let runs = pubDict["runs"] as? [[String: Any]] {
                        publishedStr = runs.compactMap { $0["text"] as? String }.joined()
                    }
                }
                
                var thumb = "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
                if let thumbDict = dict["thumbnail"] as? [String: Any],
                   let thumbs = thumbDict["thumbnails"] as? [[String: Any]],
                   let lastUrl = thumbs.last?["url"] as? String {
                    thumb = lastUrl
                }
                
                var channelAvatar: String? = nil
                if let ct = dict["channelThumbnailSupportedRenderers"] as? [String: Any],
                   let linkRenderer = ct["channelThumbnailWithLinkRenderer"] as? [String: Any],
                   let thumb = linkRenderer["thumbnail"] as? [String: Any],
                   let thumbs = thumb["thumbnails"] as? [[String: Any]],
                   let lastThumb = thumbs.last?["url"] as? String {
                    channelAvatar = lastThumb.hasPrefix("//") ? "https:" + lastThumb : lastThumb
                }
                
                var desc: String? = nil
                if let descSnippets = dict["detailedMetadataSnippets"] as? [[String: Any]],
                   let textDict = descSnippets.first?["snippetText"] as? [String: Any],
                   let runs = textDict["runs"] as? [[String: Any]] {
                    desc = runs.compactMap { $0["text"] as? String }.joined()
                } else if let descDict = dict["descriptionSnippet"] as? [String: Any],
                          let runs = descDict["runs"] as? [[String: Any]] {
                    desc = runs.compactMap { $0["text"] as? String }.joined()
                }
                
                if !title.isEmpty {
                    results.append(Video(
                        id: videoId,
                        title: title,
                        uploader: uploader,
                        uploaderId: uploaderId,
                        duration: parsedDuration,
                        durationFormatted: durationStr,
                        viewCount: nil,
                        viewCountFormatted: viewStr,
                        publishedTime: publishedStr,
                        thumbnail: thumb,
                        description: desc,
                        isShort: nil,
                        channelAvatarUrl: channelAvatar
                    ))
                }
            }
            
            for (key, value) in dict {
                // Skip reels / shorts shelves when extracting regular video results
                if key == "reelShelfRenderer" || key == "reelItemRenderer" || key == "shortsLockupViewModel" {
                    continue
                }
                extractInnerTubeVideos(from: value, results: &results)
            }
        } else if let array = obj as? [Any] {
            for element in array {
                extractInnerTubeVideos(from: element, results: &results)
            }
        }
    }
    
    // MARK: - Modern Channel Browse (InnerTube /youtubei/v1/browse)
    
    private func extractInnerTubeLockupVideos(from obj: Any, channelTitle: String = "", channelId: String? = nil, results: inout [Video]) {
        if let dict = obj as? [String: Any] {
            if let vm = dict["lockupViewModel"] as? [String: Any],
               let cid = vm["contentId"] as? String, !cid.isEmpty {
                let meta = vm["metadata"] as? [String: Any]
                let lockupMeta = meta?["lockupMetadataViewModel"] as? [String: Any]
                let title = (lockupMeta?["title"] as? [String: Any])?["content"] as? String ?? ""
                
                var viewStr = ""
                var publishedStr: String? = nil
                if let contentMeta = lockupMeta?["metadata"] as? [String: Any],
                   let rows = (contentMeta["contentMetadataViewModel"] as? [String: Any])?["metadataRows"] as? [[String: Any]] {
                    var parts: [String] = []
                    for r in rows {
                        if let pArray = r["metadataParts"] as? [[String: Any]] {
                            for p in pArray {
                                if let textDict = p["text"] as? [String: Any],
                                   let c = textDict["content"] as? String {
                                    parts.append(c)
                                }
                            }
                        }
                    }
                    if !parts.isEmpty { viewStr = parts[0] }
                    if parts.count > 1 { publishedStr = parts[1] }
                }
                
                var thumb = "https://i.ytimg.com/vi/\(cid)/hqdefault.jpg"
                var durationStr = "0:00"
                if let contentImg = vm["contentImage"] as? [String: Any],
                   let thumbVM = contentImg["thumbnailViewModel"] as? [String: Any] {
                    if let imgDict = thumbVM["image"] as? [String: Any],
                       let sources = imgDict["sources"] as? [[String: Any]],
                       let lastUrl = sources.last?["url"] as? String {
                        thumb = lastUrl
                    }
                    if let overlays = thumbVM["overlays"] as? [[String: Any]] {
                        for ov in overlays {
                            if let bottom = ov["thumbnailBottomOverlayViewModel"] as? [String: Any],
                               let badges = bottom["badges"] as? [[String: Any]] {
                                for b in badges {
                                    if let badgeVM = b["thumbnailBadgeViewModel"] as? [String: Any],
                                       let txt = badgeVM["text"] as? String {
                                        durationStr = txt
                                    }
                                }
                            }
                        }
                    }
                }
                
                let parts = durationStr.split(separator: ":").compactMap { Double($0) }
                var parsedDuration: Double? = nil
                if parts.count == 2 {
                    parsedDuration = parts[0] * 60 + parts[1]
                } else if parts.count == 3 {
                    parsedDuration = parts[0] * 3600 + parts[1] * 60 + parts[2]
                }
                
                if !title.isEmpty {
                    results.append(Video(
                        id: cid,
                        title: title,
                        uploader: channelTitle.isEmpty ? "YouTube" : channelTitle,
                        uploaderId: channelId,
                        duration: parsedDuration,
                        durationFormatted: durationStr,
                        viewCount: nil,
                        viewCountFormatted: viewStr,
                        publishedTime: publishedStr,
                        thumbnail: thumb,
                        description: nil,
                        isShort: nil,
                        channelAvatarUrl: nil
                    ))
                }
            }
            
            for (_, value) in dict {
                extractInnerTubeLockupVideos(from: value, channelTitle: channelTitle, channelId: channelId, results: &results)
            }
        } else if let array = obj as? [Any] {
            for element in array {
                extractInnerTubeLockupVideos(from: element, channelTitle: channelTitle, channelId: channelId, results: &results)
            }
        }
    }
    
    public func fetchChannelDetails(channelIdOrQuery: String, fallbackInfo: ChannelInfo? = nil, continuationToken: String? = nil) async -> ChannelDetailResult? {
        let clean = channelIdOrQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        
        var targetChannelId = clean
        var channelMeta = fallbackInfo
        
        // If not a standard UC... ID, search first to find the real channel ID
        if !targetChannelId.hasPrefix("UC") || targetChannelId.count < 20 {
            if let searchRes = await searchViaInnerTube(query: targetChannelId) {
                if let foundChannel = searchRes.channel, foundChannel.id.hasPrefix("UC") {
                    targetChannelId = foundChannel.id
                    channelMeta = foundChannel
                } else if !searchRes.videos.isEmpty {
                    let resolvedChannel = channelMeta ?? ChannelInfo(
                        id: clean,
                        title: clean,
                        handle: clean.hasPrefix("@") ? clean : nil,
                        avatarUrl: searchRes.videos.first?.channelAvatarUrl ?? ""
                    )
                    return ChannelDetailResult(
                        channel: resolvedChannel,
                        bannerUrl: nil,
                        videos: searchRes.videos,
                        continuationToken: searchRes.continuationToken
                    )
                }
            }
        }
        
        // Request InnerTube Browse endpoint
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/browse?prettyPrint=false") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("vi,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 8.0
        
        var body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": "2.20240101.00.00",
                    "hl": "vi",
                    "gl": "VN"
                ]
            ]
        ]
        
        if let cont = continuationToken, !cont.isEmpty {
            body["continuation"] = cont
        } else {
            body["browseId"] = targetChannelId
            body["params"] = "EgZ2aWRlb3PyBgQKAjoA"
        }
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody
        
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if let meta = channelMeta {
                let searchRes = await searchVideos(query: meta.title, limit: 25)
                return ChannelDetailResult(channel: meta, bannerUrl: nil, videos: searchRes, continuationToken: nil)
            }
            return nil
        }
        
        // Parse Header (pageHeaderRenderer / c4TabbedHeaderRenderer)
        var parsedTitle = channelMeta?.title ?? ""
        var parsedAvatar = channelMeta?.avatarUrl ?? ""
        var parsedBanner: String? = nil
        var parsedHandle = channelMeta?.handle
        var parsedSubs = channelMeta?.subscriberCount
        var parsedDesc = channelMeta?.description
        
        if let header = root["header"] as? [String: Any] {
            if let ph = header["pageHeaderRenderer"] as? [String: Any],
               let content = ph["content"] as? [String: Any],
               let vm = content["pageHeaderViewModel"] as? [String: Any] {
                if let titleObj = vm["title"] as? [String: Any],
                   let dyn = titleObj["dynamicTextViewModel"] as? [String: Any],
                   let tDict = dyn["text"] as? [String: Any],
                   let t = tDict["content"] as? String, !t.isEmpty {
                    parsedTitle = t
                }
                if let img = vm["image"] as? [String: Any],
                   let dec = img["decoratedAvatarViewModel"] as? [String: Any],
                   let av = dec["avatar"] as? [String: Any],
                   let avVM = av["avatarViewModel"] as? [String: Any],
                   let image = avVM["image"] as? [String: Any],
                   let sources = image["sources"] as? [[String: Any]],
                   let last = sources.last?["url"] as? String {
                    parsedAvatar = last
                }
                if let bannerObj = vm["banner"] as? [String: Any],
                   let imgBanner = bannerObj["imageBannerViewModel"] as? [String: Any],
                   let image = imgBanner["image"] as? [String: Any],
                   let sources = image["sources"] as? [[String: Any]],
                   let last = sources.last?["url"] as? String {
                    parsedBanner = last
                }
                if let metaObj = vm["metadata"] as? [String: Any],
                   let cMeta = metaObj["contentMetadataViewModel"] as? [String: Any],
                   let rows = cMeta["metadataRows"] as? [[String: Any]] {
                    for r in rows {
                        if let parts = r["metadataParts"] as? [[String: Any]] {
                            for p in parts {
                                if let textDict = p["text"] as? [String: Any],
                                   let c = textDict["content"] as? String {
                                    if c.hasPrefix("@") {
                                        parsedHandle = c
                                    } else if c.contains("người đăng ký") || c.contains("subscribers") {
                                        parsedSubs = c
                                    }
                                }
                            }
                        }
                    }
                }
                if let descObj = vm["description"] as? [String: Any],
                   let descVM = descObj["descriptionViewModel"] as? [String: Any],
                   let descText = descVM["description"] as? [String: Any],
                   let c = descText["content"] as? String {
                    parsedDesc = c
                }
            } else if let c4 = header["c4TabbedHeaderRenderer"] as? [String: Any] {
                if let t = c4["title"] as? String, !t.isEmpty {
                    parsedTitle = t
                }
                if let avatarDict = c4["avatar"] as? [String: Any],
                   let thumbs = avatarDict["thumbnails"] as? [[String: Any]],
                   let last = thumbs.last?["url"] as? String {
                    parsedAvatar = last
                }
                if let bannerDict = c4["banner"] as? [String: Any],
                   let thumbs = bannerDict["thumbnails"] as? [[String: Any]],
                   let last = thumbs.last?["url"] as? String {
                    parsedBanner = last
                }
                if let subDict = c4["subscriberCountText"] as? [String: Any],
                   let s = subDict["simpleText"] as? String {
                    parsedSubs = s
                }
            }
        }
        
        let finalChannel = ChannelInfo(
            id: targetChannelId,
            title: parsedTitle.isEmpty ? "YouTube Channel" : parsedTitle,
            handle: parsedHandle,
            subscriberCount: parsedSubs,
            avatarUrl: parsedAvatar,
            description: parsedDesc
        )
        
        var videos: [Video] = []
        extractInnerTubeLockupVideos(from: root, channelTitle: finalChannel.title, channelId: finalChannel.id, results: &videos)
        
        if videos.isEmpty {
            extractInnerTubeVideos(from: root, results: &videos)
        }
        
        var uniqueVideos: [Video] = []
        var seen = Set<String>()
        for v in videos {
            if !seen.contains(v.id) {
                seen.insert(v.id)
                uniqueVideos.append(v)
            }
        }
        
        let nextContinuation = extractContinuationToken(from: root)
        return ChannelDetailResult(
            channel: finalChannel,
            bannerUrl: parsedBanner,
            videos: uniqueVideos,
            continuationToken: nextContinuation
        )
    }
    
    private func searchViaYtDlp(query: String, limit: Int = 18) async -> [Video] {
        let ytdlp = binaryPath
        guard FileManager.default.fileExists(atPath: ytdlp) else { return [] }
        
        do {
            let output = try await runProcess(executable: ytdlp, arguments: [
                "--flat-playlist",
                "--dump-json",
                "--no-warnings",
                "ytsearch\(limit):\(query)"
            ])
            
            var results: [Video] = []
            let lines = output.components(separatedBy: .newlines)
            for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let data = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let id = json["id"] as? String,
                   let title = json["title"] as? String {
                    let uploader = json["uploader"] as? String ?? (json["channel"] as? String ?? "YouTube")
                    let duration = json["duration"] as? Double
                    let viewCount = json["view_count"] as? Int
                    
                    var pubStr: String? = nil
                    if let uploadDate = json["upload_date"] as? String, uploadDate.count == 8 {
                        let y = String(uploadDate.prefix(4))
                        let m = String(uploadDate.dropFirst(4).prefix(2))
                        let d = String(uploadDate.suffix(2))
                        pubStr = "\(d)/\(m)/\(y)"
                    }
                    
                    let thumb = "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"
                    let durStr = duration.map { formatDuration($0) } ?? "0:00"
                    let viewStr = viewCount.map { formatViews($0) } ?? ""
                    
                    results.append(Video(
                        id: id,
                        title: title,
                        uploader: uploader,
                        duration: duration,
                        durationFormatted: durStr,
                        viewCount: viewCount,
                        viewCountFormatted: viewStr,
                        publishedTime: pubStr,
                        thumbnail: thumb,
                        description: json["description"] as? String
                    ))
                }
            }
            return results
        } catch {
            return []
        }
    }
    
    public func fetchOEmbedAuthor(videoId: String) async -> String? {
        guard let url = URL(string: "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoId)&format=json") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2.5
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let author = json["author_name"] as? String, !author.isEmpty else {
            return nil
        }
        return author
    }
    
    public func fetchVideoDetails(videoId: String) async -> (title: String, author: String, desc: String, views: Int?, heights: [Int]) {
        let res = await fetchVideoDetailsAndChapters(videoId: videoId, duration: 0)
        return (res.title, res.author, res.desc, res.views, res.heights)
    }
    
    public func fetchVideoDetailsAndChapters(videoId: String, duration: Double) async -> (title: String, author: String, desc: String, views: Int?, heights: [Int], chapters: [VideoChapter]) {
        var extractedChapters: [VideoChapter] = []
        var desc = ""
        var title = "Video YouTube"
        var author = "YouTube"
        var viewCount: Int? = nil
        var totalDur = duration
        
        var extractedHeights: [Int] = []
        // 1. Fetch v1/player for shortDescription, title, author, lengthSeconds, and streamingData formats
        if let playerUrl = URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false") {
            var req = URLRequest(url: playerUrl)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            req.setValue("vi,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            req.timeoutInterval = 4.0
            let body: [String: Any] = [
                "context": [
                    "client": [
                        "clientName": "WEB",
                        "clientVersion": "2.20240101.00.00",
                        "hl": "vi",
                        "gl": "VN"
                    ]
                ],
                "videoId": videoId
            ]
            if let httpBody = try? JSONSerialization.data(withJSONObject: body) {
                req.httpBody = httpBody
                if let (data, resp) = try? await URLSession.shared.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let vd = json["videoDetails"] as? [String: Any] {
                        if let t = vd["title"] as? String, !t.isEmpty { title = t }
                        if let a = vd["author"] as? String, !a.isEmpty { author = a }
                        if let d = vd["shortDescription"] as? String { desc = d }
                        if let vStr = vd["viewCount"] as? String, let v = Int(vStr) { viewCount = v }
                        if let secStr = vd["lengthSeconds"] as? String, let secs = Double(secStr), secs > 0 {
                            totalDur = secs
                        }
                    }
                    if let sd = json["streamingData"] as? [String: Any] {
                        var hSet = Set<Int>()
                        if let formats = sd["formats"] as? [[String: Any]] {
                            for f in formats {
                                if let h = f["height"] as? Int, h > 0 { hSet.insert(h) }
                            }
                        }
                        if let af = sd["adaptiveFormats"] as? [[String: Any]] {
                            for f in af {
                                if let h = f["height"] as? Int, h > 0 { hSet.insert(h) }
                            }
                        }
                        if !hSet.isEmpty {
                            extractedHeights = Array(hSet).sorted(by: >)
                        }
                    }
                }
            }
        }
        
        // 2. Fetch official chapters from v1/next
        if let nextUrl = URL(string: "https://www.youtube.com/youtubei/v1/next?prettyPrint=false") {
            var req = URLRequest(url: nextUrl)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            req.setValue("vi,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            req.timeoutInterval = 4.0
            let body: [String: Any] = [
                "context": [
                    "client": [
                        "clientName": "WEB",
                        "clientVersion": "2.20240101.00.00",
                        "hl": "vi",
                        "gl": "VN"
                    ]
                ],
                "videoId": videoId
            ]
            if let httpBody = try? JSONSerialization.data(withJSONObject: body) {
                req.httpBody = httpBody
                if let (data, resp) = try? await URLSession.shared.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    extractedChapters = self.parseChaptersFromNextAPI(root: root, totalDuration: totalDur)
                    if desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if let nextDesc = self.parseDescriptionFromNextAPI(root: root), !nextDesc.isEmpty {
                            desc = nextDesc
                        }
                    }
                }
            }
        }
        
        // 3. Fallback: Parse description timestamps if no official chapters found
        if extractedChapters.isEmpty && !desc.isEmpty {
            extractedChapters = self.parseChaptersFromDescription(desc, totalDuration: totalDur)
        }
        
        return (title, author, desc, viewCount, extractedHeights, extractedChapters)
    }
    
    private func parseChaptersFromNextAPI(root: [String: Any], totalDuration: Double) -> [VideoChapter] {
        var markers: [(Double, String)] = []
        
        func scan(obj: Any) {
            if let d = obj as? [String: Any] {
                if let renderer = d["macroMarkersListItemRenderer"] as? [String: Any] {
                    var title = ""
                    if let tObj = renderer["title"] as? [String: Any] {
                        if let simple = tObj["simpleText"] as? String {
                            title = simple
                        } else if let runs = tObj["runs"] as? [[String: Any]] {
                            title = runs.compactMap { $0["text"] as? String }.joined()
                        }
                    }
                    var timeStr = ""
                    if let timeObj = renderer["timeDescription"] as? [String: Any],
                       let simple = timeObj["simpleText"] as? String {
                        timeStr = simple
                    }
                    if let seconds = parseTimecode(timeStr), !title.isEmpty {
                        markers.append((seconds, title))
                    }
                }
                for v in d.values { scan(obj: v) }
            } else if let arr = obj as? [Any] {
                for item in arr { scan(obj: item) }
            }
        }
        
        scan(obj: root)
        
        guard markers.count >= 2 else { return [] }
        markers.sort { $0.0 < $1.0 }
        
        var chapters: [VideoChapter] = []
        for i in 0..<markers.count {
            let start = markers[i].0
            let title = markers[i].1
            let end = (i + 1 < markers.count) ? markers[i + 1].0 : (totalDuration > start ? totalDuration : start + 300)
            if end > start {
                chapters.append(VideoChapter(title: title, start: start, end: end))
            }
        }
        return chapters
    }
    
    private func parseDescriptionFromNextAPI(root: [String: Any]) -> String? {
        var foundDesc: String? = nil
        
        func scan(obj: Any) {
            if foundDesc != nil { return }
            if let d = obj as? [String: Any] {
                if let renderer = d["expandableVideoDescriptionBodyRenderer"] as? [String: Any],
                   let descObj = renderer["description"] as? [String: Any],
                   let runs = descObj["runs"] as? [[String: Any]] {
                    let text = runs.compactMap { $0["text"] as? String }.joined()
                    if !text.isEmpty {
                        foundDesc = text
                        return
                    }
                }
                if let attr = d["attributedDescription"] as? [String: Any],
                   let content = attr["content"] as? String, !content.isEmpty {
                    foundDesc = content
                    return
                }
                for v in d.values { scan(obj: v) }
            } else if let arr = obj as? [Any] {
                for item in arr { scan(obj: item) }
            }
        }
        
        scan(obj: root)
        return foundDesc
    }
    
    private func parseChaptersFromDescription(_ text: String, totalDuration: Double) -> [VideoChapter] {
        let lines = text.components(separatedBy: .newlines)
        var markers: [(Double, String)] = []
        
        guard let regex = try? NSRegularExpression(pattern: "(?:^|\\s)(?:(\\d{1,2}):)?(\\d{1,2}):(\\d{2})(?:\\s*[-–:]?\\s*)(.+)$") else {
            return []
        }
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let range = NSRange(location: 0, length: trimmed.utf16.count)
            if let match = regex.firstMatch(in: trimmed, options: [], range: range) {
                let nsStr = trimmed as NSString
                var hours = 0.0
                if match.range(at: 1).location != NSNotFound {
                    hours = Double(nsStr.substring(with: match.range(at: 1))) ?? 0
                }
                let mins = Double(nsStr.substring(with: match.range(at: 2))) ?? 0
                let secs = Double(nsStr.substring(with: match.range(at: 3))) ?? 0
                let title = nsStr.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)
                let totalSecs = hours * 3600 + mins * 60 + secs
                if !title.isEmpty {
                    markers.append((totalSecs, title))
                }
            }
        }
        
        guard markers.count >= 2 else { return [] }
        markers.sort { $0.0 < $1.0 }
        
        var chapters: [VideoChapter] = []
        for i in 0..<markers.count {
            let start = markers[i].0
            let title = markers[i].1
            let end = (i + 1 < markers.count) ? markers[i + 1].0 : (totalDuration > start ? totalDuration : start + 300)
            if end > start {
                chapters.append(VideoChapter(title: title, start: start, end: end))
            }
        }
        return chapters
    }
    
    private func parseTimecode(_ str: String) -> Double? {
        let parts = str.components(separatedBy: ":").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        } else if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        return nil
    }
    
    // MARK: - Process Execution
    
    private func runProcess(executable: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                
                do {
                    try process.run()
                    
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        let errStr = String(data: errData, encoding: .utf8) ?? "Unknown process error"
                        continuation.resume(throwing: NSError(domain: "YTDLPService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errStr]))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
    
    private func formatViews(_ views: Int) -> String {
        if views >= 1_000_000 {
            return String(format: "%.1fM lượt xem", Double(views) / 1_000_000.0)
        } else if views >= 1_000 {
            return String(format: "%.1fK lượt xem", Double(views) / 1_000.0)
        } else {
            return "\(views) lượt xem"
        }
    }
    
    // MARK: - Viewer Comments via InnerTube (Supports Pagination & Loading ALL Comments)
    
    public struct CommentsBatch: Sendable {
        public let comments: [VideoComment]
        public let nextToken: String?
        public let totalCountText: String?
        public let sortNewestToken: String?
        public let sortTopToken: String?
        
        public init(
            comments: [VideoComment] = [],
            nextToken: String? = nil,
            totalCountText: String? = nil,
            sortNewestToken: String? = nil,
            sortTopToken: String? = nil
        ) {
            self.comments = comments
            self.nextToken = nextToken
            self.totalCountText = totalCountText
            self.sortNewestToken = sortNewestToken
            self.sortTopToken = sortTopToken
        }
    }
    
    public func fetchComments(videoId: String) async -> [VideoComment] {
        let batch = await fetchCommentsBatch(videoId: videoId)
        return batch.comments
    }
    
    public func fetchCommentsBatch(videoId: String? = nil, continuationToken: String? = nil) async -> CommentsBatch {
        guard let url = URL(string: "https://www.youtube.com/youtubei/v1/next") else {
            return CommentsBatch()
        }
        
        let clientContext: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": "2.20240101.00.00",
                    "hl": "vi",
                    "gl": "VN"
                ]
            ]
        ]
        
        var targetToken = continuationToken
        var initialTotalCountText: String? = nil
        
        // If continuationToken is nil, query initial next endpoint to resolve comment continuation token
        if targetToken == nil {
            guard let vid = videoId, !vid.isEmpty else { return CommentsBatch() }
            var body1 = clientContext
            body1["videoId"] = vid
            
            var req1 = URLRequest(url: url)
            req1.httpMethod = "POST"
            req1.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req1.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            req1.setValue("vi,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            req1.timeoutInterval = 5.0
            req1.httpBody = try? JSONSerialization.data(withJSONObject: body1)
            
            guard let (data1, res1) = try? await URLSession.shared.data(for: req1),
                  let http1 = res1 as? HTTPURLResponse, http1.statusCode == 200,
                  let root1 = try? JSONSerialization.jsonObject(with: data1) as? [String: Any] else {
                return CommentsBatch()
            }
            
            if let contents = (root1["contents"] as? [String: Any])?["twoColumnWatchNextResults"] as? [String: Any],
               let results = (contents["results"] as? [String: Any])?["results"] as? [String: Any],
               let contentList = results["contents"] as? [[String: Any]] {
                for item in contentList {
                    if let itemSection = item["itemSectionRenderer"] as? [String: Any],
                       let sectionId = itemSection["sectionIdentifier"] as? String,
                       sectionId == "comment-item-section",
                       let sectionContents = itemSection["contents"] as? [[String: Any]] {
                        for sectionItem in sectionContents {
                            if let continuation = sectionItem["continuationItemRenderer"] as? [String: Any],
                               let endpoint = continuation["continuationEndpoint"] as? [String: Any],
                               let command = endpoint["continuationCommand"] as? [String: Any],
                               let token = command["token"] as? String {
                                targetToken = token
                                break
                            }
                        }
                    }
                    if targetToken != nil { break }
                }
            }
            
            if targetToken == nil, let panels = root1["engagementPanels"] as? [[String: Any]] {
                for panel in panels {
                    if let renderer = panel["engagementPanelSectionListRenderer"] as? [String: Any],
                       let pid = renderer["panelIdentifier"] as? String,
                       pid.contains("comments") {
                        if let content = renderer["content"] as? [String: Any],
                           let sectionList = content["sectionListRenderer"] as? [String: Any],
                           let secContents = sectionList["contents"] as? [[String: Any]] {
                            for sec in secContents {
                                if let itemSec = sec["itemSectionRenderer"] as? [String: Any],
                                   let items = itemSec["contents"] as? [[String: Any]] {
                                    for it in items {
                                        if let cont = it["continuationItemRenderer"] as? [String: Any],
                                           let ep = cont["continuationEndpoint"] as? [String: Any],
                                           let cmd = ep["continuationCommand"] as? [String: Any],
                                           let tok = cmd["token"] as? String {
                                            targetToken = tok
                                            break
                                        }
                                    }
                                }
                                if targetToken != nil { break }
                            }
                        }
                    }
                    if targetToken != nil { break }
                }
            }
        }
        
        guard let token = targetToken, !token.isEmpty else {
            return CommentsBatch()
        }
        
        // Request comments with continuation token
        var body2 = clientContext
        body2["continuation"] = token
        
        var req2 = URLRequest(url: url)
        req2.httpMethod = "POST"
        req2.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req2.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        req2.setValue("vi,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        req2.timeoutInterval = 5.5
        req2.httpBody = try? JSONSerialization.data(withJSONObject: body2)
        
        guard let (data2, res2) = try? await URLSession.shared.data(for: req2),
              let http2 = res2 as? HTTPURLResponse, http2.statusCode == 200,
              let root2 = try? JSONSerialization.jsonObject(with: data2) as? [String: Any] else {
            return CommentsBatch()
        }
        
        var comments: [VideoComment] = []
        var seenCommentIds = Set<String>()
        var nextContinuationToken: String? = nil
        var sortNewestToken: String? = nil
        var sortTopToken: String? = nil
        
        // Extract Next Continuation Token, Total Comments Count Header, and Sort Tokens
        if let endpoints = root2["onResponseReceivedEndpoints"] as? [[String: Any]] {
            for ep in endpoints {
                let items = (ep["reloadContinuationItemsCommand"] as? [String: Any])?["continuationItems"] as? [[String: Any]]
                    ?? (ep["appendContinuationItemsAction"] as? [String: Any])?["continuationItems"] as? [[String: Any]]
                    ?? []
                
                for item in items {
                    // Check next continuation token
                    if let continuation = item["continuationItemRenderer"] as? [String: Any] {
                        let endpoint = continuation["continuationEndpoint"] as? [String: Any]
                        let command = endpoint?["continuationCommand"] as? [String: Any]
                        let button = continuation["button"] as? [String: Any]
                        let btnRenderer = button?["buttonRenderer"] as? [String: Any]
                        let btnCmd = (btnRenderer?["command"] as? [String: Any])?["continuationCommand"] as? [String: Any]
                        
                        let tok = (command?["token"] as? String) ?? (btnCmd?["token"] as? String)
                        if let tok = tok, !tok.isEmpty {
                            nextContinuationToken = tok
                        }
                    }
                    
                    // Check comments header count and sort options
                    if let header = item["commentsHeaderRenderer"] as? [String: Any] {
                        if let countDict = header["countText"] as? [String: Any] {
                            if let runs = countDict["runs"] as? [[String: Any]] {
                                initialTotalCountText = runs.compactMap { $0["text"] as? String }.joined()
                            } else if let simple = countDict["simpleText"] as? String {
                                initialTotalCountText = simple
                            }
                        }
                        
                        if let sortMenu = header["sortMenu"] as? [String: Any],
                           let subMenu = sortMenu["sortFilterSubMenuRenderer"] as? [String: Any],
                           let subMenuItems = subMenu["subMenuItems"] as? [[String: Any]] {
                            for subItem in subMenuItems {
                                let title = (subItem["title"] as? String) ?? ""
                                let ep = subItem["serviceEndpoint"] as? [String: Any]
                                let cmd = ep?["continuationCommand"] as? [String: Any]
                                let tok = cmd?["token"] as? String
                                if title.contains("Mới") || title.localizedCaseInsensitiveContains("newest") {
                                    sortNewestToken = tok
                                } else if title.contains("Nổi") || title.localizedCaseInsensitiveContains("top") {
                                    sortTopToken = tok
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Strategy A: mutations (Modern YouTube Entity Batch)
        if let framework = root2["frameworkUpdates"] as? [String: Any],
           let batch = framework["entityBatchUpdate"] as? [String: Any],
           let mutations = batch["mutations"] as? [[String: Any]] {
            for m in mutations {
                guard let payload = m["payload"] as? [String: Any],
                      let commentPayload = payload["commentEntityPayload"] as? [String: Any] else { continue }
                
                let propDict = commentPayload["properties"] as? [String: Any]
                let commentId = (propDict?["commentId"] as? String) ?? (m["entityKey"] as? String) ?? UUID().uuidString
                
                let authorDict = commentPayload["author"] as? [String: Any]
                let author = (authorDict?["displayName"] as? String) ?? "Người dùng"
                let avatarUrl = authorDict?["avatarThumbnailUrl"] as? String
                
                let textDict = propDict?["content"] as? [String: Any]
                let text = (textDict?["content"] as? String) ?? ""
                let pub = (propDict?["publishedTime"] as? String) ?? ""
                
                let toolbar = commentPayload["toolbar"] as? [String: Any]
                let likes = (toolbar?["likeCountNotliked"] as? String) ?? ""
                let replies = toolbar?["replyCount"] as? String
                
                // Deduplicate strictly by commentId so identical user texts (e.g. "Hay quá", "❤️") are preserved
                if !text.isEmpty && !seenCommentIds.contains(commentId) {
                    seenCommentIds.insert(commentId)
                    comments.append(VideoComment(
                        id: commentId,
                        author: author,
                        avatarUrl: avatarUrl,
                        text: text,
                        publishedTime: pub,
                        likeCount: likes,
                        replyCount: replies
                    ))
                }
            }
        }
        
        // Strategy B: Legacy commentThreadRenderer
        if comments.isEmpty, let endpoints = root2["onResponseReceivedEndpoints"] as? [[String: Any]] {
            for ep in endpoints {
                let items = (ep["reloadContinuationItemsCommand"] as? [String: Any])?["continuationItems"] as? [[String: Any]]
                    ?? (ep["appendContinuationItemsAction"] as? [String: Any])?["continuationItems"] as? [[String: Any]]
                    ?? []
                
                for item in items {
                    guard let thread = item["commentThreadRenderer"] as? [String: Any],
                          let commentObj = thread["comment"] as? [String: Any],
                          let renderer = commentObj["commentRenderer"] as? [String: Any] else { continue }
                    
                    let commentId = (renderer["commentId"] as? String) ?? UUID().uuidString
                    
                    var author = "Người dùng"
                    if let authorText = renderer["authorText"] as? [String: Any] {
                        if let simple = authorText["simpleText"] as? String {
                            author = simple
                        } else if let runs = authorText["runs"] as? [[String: Any]] {
                            author = runs.compactMap { $0["text"] as? String }.joined()
                        }
                    }
                    
                    var avatarUrl: String?
                    if let authorThumb = renderer["authorThumbnail"] as? [String: Any],
                       let thumbs = authorThumb["thumbnails"] as? [[String: Any]] {
                        avatarUrl = thumbs.last?["url"] as? String
                    }
                    
                    var text = ""
                    if let contentText = renderer["contentText"] as? [String: Any],
                       let runs = contentText["runs"] as? [[String: Any]] {
                        text = runs.compactMap { $0["text"] as? String }.joined()
                    }
                    
                    var publishedTime = ""
                    if let pubText = renderer["publishedTimeText"] as? [String: Any],
                       let runs = pubText["runs"] as? [[String: Any]] {
                        publishedTime = runs.first?["text"] as? String ?? ""
                    }
                    
                    var likes = ""
                    if let voteCount = renderer["voteCount"] as? [String: Any] {
                        likes = (voteCount["simpleText"] as? String) ?? ""
                    }
                    
                    let replyCount = (renderer["replyCount"] as? Int).map { "\($0)" }
                    
                    // Deduplicate strictly by commentId
                    if !text.isEmpty && !seenCommentIds.contains(commentId) {
                        seenCommentIds.insert(commentId)
                        comments.append(VideoComment(
                            id: commentId,
                            author: author,
                            avatarUrl: avatarUrl,
                            text: text,
                            publishedTime: publishedTime,
                            likeCount: likes,
                            replyCount: replyCount
                        ))
                    }
                }
            }
        }
        
        return CommentsBatch(
            comments: comments,
            nextToken: nextContinuationToken,
            totalCountText: initialTotalCountText,
            sortNewestToken: sortNewestToken,
            sortTopToken: sortTopToken
        )
    }
}

