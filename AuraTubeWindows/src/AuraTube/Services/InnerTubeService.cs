using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using AuraTube.Models;

namespace AuraTube.Services;

/// <summary>
/// Talks to YouTube's InnerTube JSON API directly (search, related, channel browse, player details).
/// Port of the request/parsing logic in the macOS YTDLPService.swift.
/// </summary>
public sealed class InnerTubeService
{
    public static InnerTubeService Shared { get; } = new();

    public const string FilterToday = "EgQIAhAB";
    public const string FilterThisWeek = "EgQIAxAB";
    public const string FilterThisMonth = "EgQIBBAB";
    private const string ChannelVideosParams = "EgZ2aWRlb3PyBgQKAjoA";
    public const string UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36";

    internal static readonly HttpClient Http = CreateClient();

    private static HttpClient CreateClient()
    {
        var c = new HttpClient(new SocketsHttpHandler
        {
            AutomaticDecompression = System.Net.DecompressionMethods.All,
            PooledConnectionLifetime = TimeSpan.FromMinutes(5)
        });
        c.DefaultRequestHeaders.UserAgent.ParseAdd(UserAgent);
        c.DefaultRequestHeaders.AcceptLanguage.ParseAdd("vi,en;q=0.9");
        return c;
    }

    private InnerTubeService() { }

    private static JsonObject Context() => new()
    {
        ["context"] = new JsonObject
        {
            ["client"] = new JsonObject
            {
                ["clientName"] = "WEB",
                ["clientVersion"] = "2.20240101.00.00",
                ["hl"] = "vi",
                ["gl"] = "VN"
            }
        }
    };

    private static async Task<JsonNode?> PostAsync(string endpoint, JsonObject body, double timeoutSeconds = 8)
    {
        try
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(timeoutSeconds));
            using var content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json");
            using var resp = await Http.PostAsync($"https://www.youtube.com/youtubei/v1/{endpoint}?prettyPrint=false", content, cts.Token);
            if (!resp.IsSuccessStatusCode) return null;
            var text = await resp.Content.ReadAsStringAsync(cts.Token);
            return JsonNode.Parse(text);
        }
        catch { return null; }
    }

    // MARK: - Search

    public async Task<SearchResultPage> SearchAsync(string query, string? continuation = null, string? searchParams = null)
    {
        var body = Context();
        if (!string.IsNullOrEmpty(continuation)) body["continuation"] = continuation;
        else
        {
            body["query"] = query;
            if (!string.IsNullOrEmpty(searchParams)) body["params"] = searchParams;
        }
        var root = await PostAsync("search", body, 7);
        if (root == null) return new SearchResultPage();

        var videos = new List<Video>();
        ExtractVideos(root, videos);
        var shorts = new List<Video>();
        ExtractShorts(root, shorts, videos.Select(v => v.Id).ToHashSet());
        return new SearchResultPage
        {
            Channel = continuation == null ? ExtractChannel(root) : null,
            Videos = videos.Where(v => !v.IsShort).ToList(),
            Shorts = shorts.Concat(videos.Where(v => v.IsShort)).ToList(),
            ContinuationToken = ExtractContinuation(root)
        };
    }

    public async Task<List<string>> SuggestionsAsync(string query)
    {
        var q = query.Trim();
        if (q.Length == 0) return new();
        try
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(3));
            var url = "https://suggestqueries-clients6.youtube.com/complete/search?client=firefox&ds=yt&hl=vi&gl=VN&q=" + Uri.EscapeDataString(q);
            var text = await Http.GetStringAsync(url, cts.Token);
            var arr = JsonNode.Parse(text) as JsonArray;
            return (arr?[1] as JsonArray)?.Select(n => n?.GetValue<string>() ?? "").Where(s => s.Length > 0).ToList() ?? new();
        }
        catch { return new(); }
    }

    // MARK: - Related (/next)

    public async Task<List<Video>> RelatedAsync(string videoId)
    {
        var body = Context();
        body["videoId"] = videoId;
        var root = await PostAsync("next", body);
        if (root == null) return new();
        var secondary = FindKey(root, "secondaryResults") ?? root;
        var list = new List<Video>();
        ExtractVideos(secondary, list);
        return list.Where(v => v.Id != videoId).ToList();
    }

    // MARK: - Player details

    public async Task<VideoDetails> VideoDetailsAsync(string videoId)
    {
        var details = new VideoDetails();
        var body = Context();
        body["videoId"] = videoId;
        var playerTask = PostAsync("player", body);
        var nextBody = Context();
        nextBody["videoId"] = videoId;
        var nextTask = PostAsync("next", nextBody);
        await Task.WhenAll(playerTask, nextTask);

        var player = playerTask.Result;
        if (player?["videoDetails"] is JsonObject vd)
        {
            details.Title = Str(vd["title"]);
            details.Author = Str(vd["author"]);
            details.ChannelId = Str(vd["channelId"]);
            details.Description = Str(vd["shortDescription"]);
            if (long.TryParse(Str(vd["viewCount"]), out var views)) details.Views = views;
            if (double.TryParse(Str(vd["lengthSeconds"]), out var len)) details.LengthSeconds = len;
        }
        if (player?["streamingData"]?["adaptiveFormats"] is JsonArray formats)
        {
            details.Heights = formats.Select(f => f?["height"]?.GetValue<int>() ?? 0)
                .Where(h => h > 0).Distinct().OrderByDescending(h => h).ToList();
        }

        var next = nextTask.Result;
        if (next != null)
        {
            if (string.IsNullOrEmpty(details.Description))
            {
                var desc = FindKey(FindKey(next, "videoSecondaryInfoRenderer") ?? new JsonObject(), "attributedDescription");
                if (desc != null) details.Description = Str(desc["content"]);
            }
            details.Chapters = ParseChapters(next);
        }
        if (details.Chapters.Count == 0)
            details.Chapters = ParseChaptersFromDescription(details.Description);
        return details;
    }

    private static List<VideoChapter> ParseChapters(JsonNode root)
    {
        var chapters = new List<VideoChapter>();
        Walk(root, obj =>
        {
            if (obj["chapterRenderer"] is JsonObject ch)
            {
                var title = Text(ch["title"]);
                var ms = ch["timeRangeStartMillis"]?.GetValue<double>() ?? 0;
                if (title.Length > 0 && !chapters.Any(c => Math.Abs(c.Start - ms / 1000) < 0.5))
                    chapters.Add(new VideoChapter(title, ms / 1000));
            }
            return true;
        });
        return chapters.OrderBy(c => c.Start).ToList();
    }

    private static readonly Regex ChapterLine = new(@"^\s*\(?((?:\d{1,2}:)?\d{1,2}:\d{2})\)?\s*[-–—:]?\s*(.+)$", RegexOptions.Multiline);

    public static List<VideoChapter> ParseChaptersFromDescription(string text)
    {
        var list = new List<VideoChapter>();
        foreach (Match m in ChapterLine.Matches(text ?? ""))
        {
            var t = ParseTimecode(m.Groups[1].Value);
            if (t != null) list.Add(new VideoChapter(m.Groups[2].Value.Trim(), t.Value));
        }
        return list.Count >= 3 && list[0].Start == 0 ? list : new();
    }

    public static double? ParseTimecode(string s)
    {
        var parts = s.Split(':').Select(p => double.TryParse(p, out var d) ? d : double.NaN).ToArray();
        if (parts.Any(double.IsNaN)) return null;
        return parts.Length switch
        {
            2 => parts[0] * 60 + parts[1],
            3 => parts[0] * 3600 + parts[1] * 60 + parts[2],
            _ => null
        };
    }

    // MARK: - Channel (/browse)

    public async Task<ChannelDetail?> ChannelAsync(string channelIdOrQuery, ChannelInfo? fallback = null, string? continuation = null)
    {
        var clean = channelIdOrQuery.Trim();
        if (clean.Length == 0) return null;
        var target = clean;
        var meta = fallback;

        if (continuation == null && (!target.StartsWith("UC") || target.Length < 20))
        {
            var search = await SearchAsync(clean);
            if (search.Channel != null && search.Channel.Id.StartsWith("UC"))
            {
                target = search.Channel.Id;
                meta = search.Channel;
            }
            else if (search.Videos.FirstOrDefault(v => v.UploaderId?.StartsWith("UC") == true
                         && (clean.StartsWith('@') || v.Uploader.Contains(clean, StringComparison.OrdinalIgnoreCase))) is { } owned)
            {
                target = owned.UploaderId!;
                meta ??= new ChannelInfo { Id = target, Title = owned.Uploader, AvatarUrl = owned.ChannelAvatarUrl ?? "" };
            }
            else if (search.Videos.Count > 0)
            {
                return new ChannelDetail
                {
                    Channel = meta ?? new ChannelInfo { Id = clean, Title = clean, Handle = clean.StartsWith('@') ? clean : null, AvatarUrl = search.Videos[0].ChannelAvatarUrl ?? "" },
                    Videos = search.Videos,
                    ContinuationToken = search.ContinuationToken
                };
            }
        }

        var body = Context();
        if (!string.IsNullOrEmpty(continuation)) body["continuation"] = continuation;
        else
        {
            body["browseId"] = target;
            body["params"] = ChannelVideosParams;
        }
        var root = await PostAsync("browse", body);
        if (root == null)
        {
            if (meta == null) return null;
            var res = await SearchAsync(meta.Title);
            return new ChannelDetail { Channel = meta, Videos = res.Videos };
        }

        var channel = meta ?? new ChannelInfo { Id = target, Title = clean };
        channel.Id = target;
        string? banner = null;

        if (root["header"] is JsonNode header)
        {
            if (FindKey(header, "pageHeaderViewModel") is JsonObject vm)
            {
                var t = Str(vm["title"]?["dynamicTextViewModel"]?["text"]?["content"]);
                if (t.Length > 0) channel.Title = t;
                var avatarSources = FindKey(vm["image"] ?? new JsonObject(), "sources") as JsonArray;
                var av = avatarSources?.LastOrDefault()?["url"];
                if (av != null) channel.AvatarUrl = FixUrl(Str(av));
                var bannerSources = FindKey(vm["banner"] ?? new JsonObject(), "sources") as JsonArray;
                var b = bannerSources?.LastOrDefault()?["url"];
                if (b != null) banner = FixUrl(Str(b));
                if (vm["metadata"]?["contentMetadataViewModel"]?["metadataRows"] is JsonArray rows)
                {
                    foreach (var part in rows.SelectMany(r => (r?["metadataParts"] as JsonArray) ?? new JsonArray()))
                    {
                        var c = Str(part?["text"]?["content"]);
                        if (c.StartsWith('@')) channel.Handle = c;
                        else if (c.Contains("người đăng ký") || c.Contains("subscriber")) channel.SubscriberCount = c;
                    }
                }
                var d = Str(vm["description"]?["descriptionPreviewViewModel"]?["description"]?["content"]);
                if (d.Length > 0) channel.Description = d;
            }
            else if (header["c4TabbedHeaderRenderer"] is JsonObject c4)
            {
                var t = Str(c4["title"]);
                if (t.Length > 0) channel.Title = t;
                var av = (c4["avatar"]?["thumbnails"] as JsonArray)?.LastOrDefault()?["url"];
                if (av != null) channel.AvatarUrl = FixUrl(Str(av));
                var b = (c4["banner"]?["thumbnails"] as JsonArray)?.LastOrDefault()?["url"];
                if (b != null) banner = FixUrl(Str(b));
                var subs = Text(c4["subscriberCountText"]);
                if (subs.Length > 0) channel.SubscriberCount = subs;
                var handle = Text(c4["channelHandleText"]);
                if (handle.Length > 0) channel.Handle = handle;
            }
        }
        if (root["metadata"]?["channelMetadataRenderer"] is JsonObject cmr)
        {
            if (string.IsNullOrEmpty(channel.Description)) channel.Description = Str(cmr["description"]);
            if (string.IsNullOrEmpty(channel.AvatarUrl))
                channel.AvatarUrl = FixUrl(Str((cmr["avatar"]?["thumbnails"] as JsonArray)?.LastOrDefault()?["url"]));
        }

        var videos = new List<Video>();
        ExtractVideos(root, videos, channel.Title, target);
        foreach (var v in videos)
        {
            if (v.Uploader == "YouTube") v.Uploader = channel.Title;
            v.UploaderId ??= target;
            if (string.IsNullOrEmpty(v.ChannelAvatarUrl)) v.ChannelAvatarUrl = channel.AvatarUrl;
        }
        return new ChannelDetail { Channel = channel, BannerUrl = banner, Videos = videos, ContinuationToken = ExtractContinuation(root) };
    }

    // MARK: - Parsing helpers

    internal static string Str(JsonNode? n)
    {
        if (n is JsonValue v && v.TryGetValue<string>(out var s)) return s;
        return n is JsonValue v2 ? v2.ToString() : "";
    }

    internal static string Text(JsonNode? n)
    {
        if (n == null) return "";
        if (n is JsonValue) return Str(n);
        var simple = Str(n["simpleText"]);
        if (simple.Length > 0) return simple;
        if (n["runs"] is JsonArray runs) return string.Concat(runs.Select(r => Str(r?["text"])));
        return Str(n["content"]);
    }

    internal static string FixUrl(string u) => u.StartsWith("//") ? "https:" + u : u;

    /// <summary>Depth-first visit of every JSON object. Return false from the visitor to skip children.</summary>
    internal static void Walk(JsonNode? node, Func<JsonObject, bool> visit)
    {
        switch (node)
        {
            case JsonObject obj:
                if (!visit(obj)) return;
                foreach (var kv in obj.ToList()) Walk(kv.Value, visit);
                break;
            case JsonArray arr:
                foreach (var item in arr.ToList()) Walk(item, visit);
                break;
        }
    }

    internal static JsonNode? FindKey(JsonNode node, string key)
    {
        JsonNode? found = null;
        Walk(node, obj =>
        {
            if (found != null) return false;
            if (obj.TryGetPropertyValue(key, out var v) && v != null) { found = v; return false; }
            return true;
        });
        return found;
    }

    public static string? ExtractContinuation(JsonNode root)
    {
        string? token = null;
        Walk(root, obj =>
        {
            if (token != null) return false;
            var t = Str(obj["continuationCommand"]?["token"]);
            if (t.Length > 0) { token = t; return false; }
            return true;
        });
        return token;
    }

    public static ChannelInfo? ExtractChannel(JsonNode root)
    {
        ChannelInfo? ch = null;
        Walk(root, obj =>
        {
            if (ch != null) return false;
            if (obj["channelRenderer"] is JsonObject cr && Str(cr["channelId"]) is { Length: > 0 } cid)
            {
                var subsText = Text(cr["subscriberCountText"]);
                var title = Text(cr["title"]);
                ch = new ChannelInfo
                {
                    Id = cid,
                    Title = title.Length > 0 ? title : "YouTube Channel",
                    Handle = subsText.StartsWith('@') ? subsText : null,
                    SubscriberCount = subsText.StartsWith('@') ? Text(cr["videoCountText"]) : subsText,
                    AvatarUrl = FixUrl(Str((cr["thumbnail"]?["thumbnails"] as JsonArray)?.LastOrDefault()?["url"])),
                    Description = Text(cr["descriptionSnippet"])
                };
                return false;
            }
            return true;
        });
        return ch;
    }

    private static readonly HashSet<string> ShortsKeys = new() { "reelShelfRenderer", "reelItemRenderer", "shortsLockupViewModel" };

    public static void ExtractVideos(JsonNode root, List<Video> results, string? channelTitle = null, string? channelId = null)
    {
        var seen = results.Select(r => r.Id).ToHashSet();
        void Visit(JsonNode? node)
        {
            if (node is JsonArray arr) { foreach (var i in arr) Visit(i); return; }
            if (node is not JsonObject dict) return;

            if (dict["lockupViewModel"] is JsonObject vm && Str(vm["contentId"]) is { Length: 11 } cid && !seen.Contains(cid))
            {
                var v = ParseLockup(vm, cid);
                if (v != null) { seen.Add(cid); results.Add(v); }
            }
            if (Str(dict["videoId"]) is { Length: 11 } vid && dict.ContainsKey("title") && !seen.Contains(vid))
            {
                var v = ParseLegacy(dict, vid);
                if (v != null) { seen.Add(vid); results.Add(v); }
            }
            foreach (var kv in dict.ToList())
            {
                if (ShortsKeys.Contains(kv.Key)) continue;
                Visit(kv.Value);
            }
        }
        Visit(root);
    }

    private static Video? ParseLockup(JsonObject vm, string cid)
    {
        var lockupMeta = vm["metadata"]?["lockupMetadataViewModel"];
        var title = Str(lockupMeta?["title"]?["content"]);
        var contentType = Str(vm["contentType"]);
        if (title.Length == 0 || contentType == "LOCKUP_CONTENT_TYPE_PLAYLIST") return null;

        var v = new Video { Id = cid, Title = title, Thumbnail = $"https://i.ytimg.com/vi/{cid}/hqdefault.jpg" };
        if (lockupMeta?["metadata"]?["contentMetadataViewModel"]?["metadataRows"] is JsonArray rows)
        {
            // Rows vary by surface (search, /next, channel); classify parts by content instead of position.
            foreach (var part in rows.SelectMany(r => (r?["metadataParts"] as JsonArray) ?? new JsonArray()))
            {
                var t = Str(part?["text"]?["content"]).Trim();
                if (t.Length == 0) continue;
                var lower = t.ToLowerInvariant();
                if (lower.Contains("lượt xem") || lower.Contains("view") || lower.Contains("đang xem") || lower.Contains("watching")) v.ViewCountFormatted = t;
                else if (lower.Contains("trước") || lower.Contains("ago") || lower.Contains("phát trực tiếp") || lower.Contains("streamed")) v.PublishedTime = t;
                else if (v.Uploader == "YouTube") v.Uploader = t;
            }
        }
        var dec = lockupMeta?["image"]?["decoratedAvatarViewModel"];
        if (dec != null)
        {
            var src = (dec["avatar"]?["avatarViewModel"]?["image"]?["sources"] as JsonArray)?.FirstOrDefault()?["url"];
            if (src != null) v.ChannelAvatarUrl = FixUrl(Str(src));
            var bid = Str(dec["rendererContext"]?["commandContext"]?["onTap"]?["innertubeCommand"]?["browseEndpoint"]?["browseId"]);
            if (bid.Length > 0) v.UploaderId = bid;
        }
        var thumbVm = vm["contentImage"]?["thumbnailViewModel"];
        if (thumbVm != null)
        {
            var last = (thumbVm["image"]?["sources"] as JsonArray)?.LastOrDefault()?["url"];
            if (last != null) v.Thumbnail = FixUrl(Str(last));
            Walk(thumbVm["overlays"], o =>
            {
                if (o["thumbnailBadgeViewModel"] is JsonObject b && Str(b["text"]) is { Length: > 0 } t) v.DurationFormatted = t;
                return true;
            });
        }
        v.Duration = ParseTimecode(v.DurationFormatted);
        v.IsShort = contentType == "LOCKUP_CONTENT_TYPE_SHORTS" || v.DurationFormatted == "Shorts";
        return v;
    }

    private static Video? ParseLegacy(JsonObject dict, string vid)
    {
        var title = Text(dict["title"]);
        if (title.Length == 0) return null;
        var v = new Video { Id = vid, Title = title, Thumbnail = $"https://i.ytimg.com/vi/{vid}/hqdefault.jpg" };
        var owner = (dict["ownerText"]?["runs"] ?? dict["shortBylineText"]?["runs"] ?? dict["longBylineText"]?["runs"]) as JsonArray;
        if (owner?.FirstOrDefault() is JsonNode run)
        {
            v.Uploader = Str(run["text"]);
            var bid = Str(run["navigationEndpoint"]?["browseEndpoint"]?["browseId"]);
            if (bid.Length > 0) v.UploaderId = bid;
        }
        v.DurationFormatted = Text(dict["lengthText"]);
        v.Duration = ParseTimecode(v.DurationFormatted);
        v.ViewCountFormatted = Text(dict["shortViewCountText"]);
        if (v.ViewCountFormatted.Length == 0) v.ViewCountFormatted = Text(dict["viewCountText"]);
        v.PublishedTime = Text(dict["publishedTimeText"]);
        var thumb = (dict["thumbnail"]?["thumbnails"] as JsonArray)?.LastOrDefault()?["url"];
        if (thumb != null) v.Thumbnail = FixUrl(Str(thumb));
        var av = (dict["channelThumbnailSupportedRenderers"]?["channelThumbnailWithLinkRenderer"]?["thumbnail"]?["thumbnails"] as JsonArray)?.LastOrDefault()?["url"];
        if (av != null) v.ChannelAvatarUrl = FixUrl(Str(av));
        var snippet = (dict["detailedMetadataSnippets"] as JsonArray)?.FirstOrDefault()?["snippetText"];
        v.Description = snippet != null ? Text(snippet) : Text(dict["descriptionSnippet"]);
        return v;
    }

    public static void ExtractShorts(JsonNode root, List<Video> results, HashSet<string> existing)
    {
        Walk(root, obj =>
        {
            if (obj["shortsLockupViewModel"] is JsonObject sl)
            {
                var id = Str(sl["entityId"]);
                id = id.StartsWith("shorts-shelf-item-") ? id["shorts-shelf-item-".Length..] : "";
                if (id.Length == 0)
                {
                    var url = Str(sl["onTap"]?["innertubeCommand"]?["commandMetadata"]?["webCommandMetadata"]?["url"]);
                    if (url.StartsWith("/shorts/")) id = url["/shorts/".Length..];
                }
                if (id.Length == 11 && !existing.Contains(id) && results.All(r => r.Id != id))
                {
                    var title = Str(sl["overlayMetadata"]?["primaryText"]?["content"]);
                    var views = Str(sl["overlayMetadata"]?["secondaryText"]?["content"]);
                    var a11y = Str(sl["accessibilityText"]);
                    if (title.Length == 0) title = a11y;
                    var thumb = (sl["thumbnailViewModel"]?["thumbnailViewModel"]?["image"]?["sources"] as JsonArray)?.LastOrDefault()?["url"];
                    results.Add(new Video
                    {
                        Id = id,
                        Title = title,
                        Uploader = GuessShortUploader(a11y.Length > 0 ? a11y : title),
                        ViewCountFormatted = views,
                        DurationFormatted = "Shorts",
                        Thumbnail = thumb != null ? FixUrl(Str(thumb)) : $"https://i.ytimg.com/vi/{id}/hqdefault.jpg",
                        IsShort = true
                    });
                }
                return false;
            }
            if (obj["reelItemRenderer"] is JsonObject reel && Str(reel["videoId"]) is { Length: 11 } rid && !existing.Contains(rid) && results.All(r => r.Id != rid))
            {
                results.Add(new Video
                {
                    Id = rid,
                    Title = Text(reel["headline"]),
                    ViewCountFormatted = Text(reel["viewCountText"]),
                    DurationFormatted = "Shorts",
                    Thumbnail = $"https://i.ytimg.com/vi/{rid}/hqdefault.jpg",
                    IsShort = true
                });
                return false;
            }
            return true;
        });
    }

    private static string GuessShortUploader(string text)
    {
        if (text.Contains('|'))
        {
            foreach (var p in text.Split('|').Skip(1))
            {
                var clean = Regex.Replace(p, "#shorts?", "", RegexOptions.IgnoreCase).Trim();
                if (clean.Length > 0 && clean.Length <= 35 && !clean.ToLowerInvariant().Contains("lượt xem") && !clean.ToLowerInvariant().Contains("views"))
                    return clean;
            }
        }
        return "YouTube Creator";
    }

    private static readonly System.Globalization.CultureInfo Vi = new("vi-VN");

    public static string FormatViews(long views) => views switch
    {
        >= 1_000_000_000 => (views / 1_000_000_000.0).ToString("0.#", Vi) + " Tỷ lượt xem",
        >= 1_000_000 => (views / 1_000_000.0).ToString("0.#", Vi) + " Tr lượt xem",
        >= 1_000 => (views / 1_000.0).ToString("0.#", Vi) + " N lượt xem",
        _ => views + " lượt xem"
    };

    public static string FormatDuration(double seconds)
    {
        if (double.IsNaN(seconds) || seconds < 0) seconds = 0;
        var t = TimeSpan.FromSeconds(seconds);
        return t.TotalHours >= 1 ? $"{(int)t.TotalHours}:{t.Minutes:00}:{t.Seconds:00}" : $"{t.Minutes}:{t.Seconds:00}";
    }

    /// <summary>Extract the 11-char id from a youtube URL / youtu.be / shorts link or bare id.</summary>
    public static string? ParseVideoId(string input)
    {
        var s = input.Trim();
        if (Regex.IsMatch(s, "^[A-Za-z0-9_-]{11}$")) return s;
        var m = Regex.Match(s, @"(?:v=|youtu\.be/|/shorts/|/embed/|/live/)([A-Za-z0-9_-]{11})");
        return m.Success ? m.Groups[1].Value : null;
    }
}
