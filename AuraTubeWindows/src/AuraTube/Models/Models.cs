using System.Text.Json.Serialization;

namespace AuraTube.Models;

public sealed class Video
{
    public string Id { get; set; } = "";
    public string Title { get; set; } = "";
    public string Uploader { get; set; } = "YouTube";
    public string? UploaderId { get; set; }
    public double? Duration { get; set; }
    public string DurationFormatted { get; set; } = "";
    public string ViewCountFormatted { get; set; } = "";
    public string? PublishedTime { get; set; }
    public string Thumbnail { get; set; } = "";
    public string? Description { get; set; }
    public bool IsShort { get; set; }
    public string? ChannelAvatarUrl { get; set; }

    [JsonIgnore]
    public string Subtitle => string.Join(" • ", new[] { ViewCountFormatted, PublishedTime }
        .Where(s => !string.IsNullOrWhiteSpace(s)));

    [JsonIgnore]
    public bool HasDuration => !string.IsNullOrWhiteSpace(DurationFormatted) && DurationFormatted != "0:00";

    public string WatchUrl => $"https://www.youtube.com/watch?v={Id}";
}

public sealed class ChannelInfo
{
    public string Id { get; set; } = "";
    public string Title { get; set; } = "";
    public string? Handle { get; set; }
    public string? SubscriberCount { get; set; }
    public string AvatarUrl { get; set; } = "";
    public string? Description { get; set; }
}

public sealed class SearchResultPage
{
    public ChannelInfo? Channel { get; init; }
    public List<Video> Videos { get; init; } = new();
    public List<Video> Shorts { get; init; } = new();
    public string? ContinuationToken { get; init; }
}

public sealed class ChannelDetail
{
    public required ChannelInfo Channel { get; init; }
    public string? BannerUrl { get; init; }
    public List<Video> Videos { get; init; } = new();
    public string? ContinuationToken { get; init; }
}

public sealed class VideoDetails
{
    public string Title { get; set; } = "";
    public string Author { get; set; } = "";
    public string? ChannelId { get; set; }
    public string Description { get; set; } = "";
    public long? Views { get; set; }
    public double LengthSeconds { get; set; }
    public List<int> Heights { get; set; } = new();
    public List<VideoChapter> Chapters { get; set; } = new();
}

public sealed record VideoChapter(string Title, double Start);

public sealed class StreamInfo
{
    public required string VideoId { get; init; }
    public required string VideoUrl { get; init; }
    public string? AudioUrl { get; init; }
    public bool IsCombined => AudioUrl == null;
    public string Quality { get; init; } = "";
    /// <summary>VideoUrl is an HLS master playlist containing audio; cap with MaxHeight.</summary>
    public bool IsManifest { get; init; }
    public int MaxHeight { get; init; } = 1080;
}

public sealed record SponsorSegment(string Category, double Start, double End)
{
    public string CategoryVi => Category switch
    {
        "sponsor" => "Quảng cáo tài trợ",
        "intro" => "Đoạn mở đầu",
        "outro" => "Đoạn kết",
        "interaction" => "Nhắc tương tác",
        "selfpromo" => "Tự quảng bá",
        _ => Category
    };
}

public sealed class SubscribedChannel
{
    public string Title { get; set; } = "";
    public string? Id { get; set; }
    public string? Handle { get; set; }
    public string? AvatarUrl { get; set; }
}

public sealed class AppUpdateInfo
{
    public string Version { get; set; } = "";
    public int Build { get; set; }
    public string Title { get; set; } = "";
    public string ReleaseNotes { get; set; } = "";
    public string? DownloadUrl { get; set; }
    public string? WindowsDownloadUrl { get; set; }
    public string? PublishedAt { get; set; }
    public string? FileSize { get; set; }
}
