using AuraTube.Models;

namespace AuraTube.Services;

/// <summary>
/// Home/trending, category, Shorts and subscription feeds. Port of the feed logic in
/// RecommendationService.swift, NativeShortsFeedView.swift and ChannelSubscriptionManager.swift.
/// </summary>
public sealed class FeedService
{
    public static FeedService Shared { get; } = new();

    public static readonly string[] Categories =
        { "Tất cả", "Thịnh hành", "Âm nhạc", "Giải trí", "Công nghệ", "Trò chơi", "Tin tức", "Ẩm thực & Du lịch", "Bóng đá", "Podcast", "Đã đăng gần đây" };

    private static readonly Dictionary<string, string[]> CategoryQueries = new()
    {
        ["Thịnh hành"] = new[] { "tin tức nóng hôm nay việt nam", "vlog giải trí thịnh hành việt nam", "review công nghệ mới nhất việt nam" },
        ["Âm nhạc"] = new[] { "bài hát thịnh hành mới nhất việt nam triệu view", "top trending âm nhạc việt nam", "mv ca nhạc mới nhất việt nam triệu view" },
        ["Giải trí"] = new[] { "gameshow việt nam triệu view thịnh hành", "rap việt anh trai say hi 2 ngày 1 đêm mới nhất", "show giải trí hot nhất việt nam triệu view" },
        ["Công nghệ"] = new[] { "review công nghệ việt nam vật vờ schannel mới nhất", "đánh giá điện thoại laptop mới thịnh hành việt nam", "đồ chơi công nghệ thông minh mới nhất" },
        ["Trò chơi"] = new[] { "mixigaming cris devil gamer highlight mới nhất", "gameplay bom tấn việt nam highlight", "gaming việt nam triệu view mới nhất" },
        ["Tin tức"] = new[] { "vtv24 chuyển động 24h tin tức thời sự việt nam mới nhất", "thời sự việt nam hôm nay nóng nhất", "tin tức đời sống xã hội việt nam 24h" },
        ["Ẩm thực & Du lịch"] = new[] { "khoai lang thang chan la cà du lịch ẩm thực việt nam", "ẩm thực đường phố khám phá việt nam triệu view", "món ngon vùng miền đặc sản việt nam" },
        ["Bóng đá"] = new[] { "bóng đá việt nam highlight mới nhất", "v-league đội tuyển việt nam mới nhất", "thể thao việt nam highlight" },
        ["Podcast"] = new[] { "podcast việt nam triệu view hay nhất", "phê phim spiderum vietcetera podcast mới nhất", "talkshow phỏng vấn nhân vật truyền cảm hứng" },
    };

    public static readonly string[] ShortsSeeds =
    {
        "shorts trending việt nam", "shorts viral việt nam", "shorts hài hước triệu view", "shorts giải trí hay nhất",
        "shorts công nghệ đời sống", "shorts ẩm thực đường phố việt nam", "shorts tin tức nóng hổi",
        "shorts biến hình tiktok triệu view", "shorts khám phá thế giới kỳ thú", "shorts mẹo hay cuộc sống"
    };

    private List<Video> _trendingCache = new();
    private DateTime _trendingAt = DateTime.MinValue;

    /// <summary>Returns (regular videos, shorts) for the home feed.</summary>
    public async Task<(List<Video> Videos, List<Video> Shorts)> TrendingAsync(bool force = false)
    {
        if (!force && _trendingCache.Count > 0 && DateTime.UtcNow - _trendingAt < TimeSpan.FromMinutes(20))
            return Split(_trendingCache);

        var pillars = new List<(string Q, string? P)>
        {
            ("tin tức nóng hôm nay việt nam", InnerTubeService.FilterThisWeek),
            ("review công nghệ mới nhất việt nam", InnerTubeService.FilterThisWeek),
            ("vlog giải trí thịnh hành việt nam", InnerTubeService.FilterThisWeek),
        };
        if (UserLikesMusic()) pillars.Add(("mv ca nhạc mới nhất việt nam", InnerTubeService.FilterThisWeek));
        // Personalize a little: add a query from the most watched channel.
        var topChannel = AppStore.Shared.History.Take(50).GroupBy(v => v.Uploader).OrderByDescending(g => g.Count()).FirstOrDefault()?.Key;
        if (!string.IsNullOrEmpty(topChannel) && topChannel != "YouTube") pillars.Add((topChannel, null));

        var regularTasks = pillars.Select(p => InnerTubeService.Shared.SearchAsync(p.Q, null, p.P)).ToList();
        // No upload-date filter for Shorts: InnerTube drops the Shorts shelf when filters are present.
        var shortsTask = InnerTubeService.Shared.SearchAsync("shorts trending việt nam viral triệu view");
        await Task.WhenAll(regularTasks.Cast<Task>().Append(shortsTask));

        var watched = AppStore.Shared.History.Take(200).Select(v => v.Id).ToHashSet();
        var streams = regularTasks.Select(t => t.Result.Videos.Where(v => !watched.Contains(v.Id)).ToList()).ToList();
        var combined = Interleave(streams);
        var seen = combined.Select(v => v.Id).ToHashSet();
        var shorts = shortsTask.Result.Shorts.Where(s => seen.Add(s.Id)).Take(14).ToList();

        if (combined.Count == 0)
            combined = (await InnerTubeService.Shared.SearchAsync("top trending việt nam hôm nay")).Videos;

        _trendingCache = combined.Concat(shorts).ToList();
        _trendingAt = DateTime.UtcNow;
        return (combined, shorts);
    }

    private static (List<Video>, List<Video>) Split(List<Video> all) => (all.Where(v => !v.IsShort).ToList(), all.Where(v => v.IsShort).ToList());

    private static bool UserLikesMusic() =>
        AppStore.Shared.History.Take(60).Count(v => v.Title.Contains("MV", StringComparison.OrdinalIgnoreCase)
            || v.Title.Contains("official", StringComparison.OrdinalIgnoreCase) || v.Title.Contains("lyric", StringComparison.OrdinalIgnoreCase)) >= 3;

    public async Task<List<Video>> CategoryAsync(string category)
    {
        if (category == "Đã đăng gần đây")
        {
            var res = await Task.WhenAll(CategoryQueries["Thịnh hành"].Select(q => InnerTubeService.Shared.SearchAsync(q, null, InnerTubeService.FilterToday)));
            return Interleave(res.Select(r => r.Videos).ToList());
        }
        var queries = CategoryQueries.TryGetValue(category, out var q2) ? q2 : new[] { $"{category} việt nam mới nhất", $"{category} triệu view" };
        var pages = await Task.WhenAll(queries.Take(2).Select(q => InnerTubeService.Shared.SearchAsync(q)));
        return Interleave(pages.Select(p => p.Videos).ToList());
    }

    public async Task<List<Video>> ShortsAsync(IEnumerable<string>? exclude = null)
    {
        var excluded = exclude?.ToHashSet() ?? new HashSet<string>();
        var seeds = ShortsSeeds.OrderBy(_ => Random.Shared.Next()).Take(3).ToList();
        var pages = await Task.WhenAll(seeds.Select(s => InnerTubeService.Shared.SearchAsync(s)));
        return Interleave(pages.Select(p => p.Shorts).ToList()).Where(v => excluded.Add(v.Id)).ToList();
    }

    public async Task<List<Video>> SubscriptionFeedAsync(int perChannel = 6)
    {
        var channels = AppStore.Shared.Subscriptions.Take(12).ToList();
        if (channels.Count == 0) return new();
        var lists = await Task.WhenAll(channels.Select(async ch =>
        {
            if (!string.IsNullOrEmpty(ch.Id) && ch.Id.StartsWith("UC"))
            {
                var detail = await InnerTubeService.Shared.ChannelAsync(ch.Id, new ChannelInfo { Id = ch.Id, Title = ch.Title, AvatarUrl = ch.AvatarUrl ?? "" });
                if (detail != null && detail.Videos.Count > 0) return detail.Videos.Take(perChannel).ToList();
            }
            var query = ch.Handle?.StartsWith('@') == true ? ch.Handle : ch.Title;
            var res = await InnerTubeService.Shared.SearchAsync(query);
            var filtered = res.Videos.Where(v => v.Uploader.Contains(ch.Title, StringComparison.OrdinalIgnoreCase)
                                              || ch.Title.Contains(v.Uploader, StringComparison.OrdinalIgnoreCase)).ToList();
            return (filtered.Count > 0 ? filtered : res.Videos).Take(perChannel).ToList();
        }));
        return Interleave(lists.ToList());
    }

    public static List<Video> Interleave(List<List<Video>> streams)
    {
        var seen = new HashSet<string>();
        var result = new List<Video>();
        var max = streams.Count == 0 ? 0 : streams.Max(s => s.Count);
        for (var i = 0; i < max; i++)
            foreach (var s in streams)
                if (i < s.Count && seen.Add(s[i].Id)) result.Add(s[i]);
        return result;
    }
}
