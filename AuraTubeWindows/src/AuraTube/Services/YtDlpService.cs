using System.Diagnostics;
using System.Text;
using System.Text.Json;
using AuraTube.Models;

namespace AuraTube.Services;

/// <summary>Resolves direct stream URLs via yt-dlp (ad-free playback). Port of getStreamInfo in YTDLPService.swift.</summary>
public sealed class YtDlpService
{
    public static YtDlpService Shared { get; } = new();
    private YtDlpService() { }

    private readonly Dictionary<string, (StreamInfo Info, DateTime At)> _cache = new();

    public static bool IsValidId(string id) => System.Text.RegularExpressions.Regex.IsMatch(id, "^[A-Za-z0-9_-]{11}$");

    /// <summary>
    /// quality: "audio", "360", "480", "720", "1080", "1440", "2160", "shorts".
    /// LibVLC plays separate video+audio (via input-slave) and HLS, so we prefer DASH avc1/vp9 + m4a
    /// for the requested height and fall back to HLS / combined formats.
    /// </summary>
    public async Task<StreamInfo> GetStreamInfoAsync(string videoId, string quality, CancellationToken ct = default)
    {
        if (!IsValidId(videoId)) throw new ArgumentException("ID video không hợp lệ");
        var key = videoId + "|" + quality;
        lock (_cache)
            if (_cache.TryGetValue(key, out var c) && DateTime.UtcNow - c.At < TimeSpan.FromMinutes(90)) return c.Info;

        var ytdlp = await YtDlpBinary.Shared.ResolveAsync();
        var js = await YtDlpBinary.Shared.JsRuntimeArgsAsync();

        var h = quality is "audio" or "shorts" ? "1920" : quality;
        var url = $"https://www.youtube.com/watch?v={videoId}";

        // Preferred: YouTube HLS master playlist (video variants + audio rendition groups in one
        // manifest). VLC adaptive streaming keeps A/V in sync and caps resolution via :adaptive-maxheight.
        // Two separate inputs (video + audio slave) drift / deadlock in VLC, so that is only a fallback.
        if (quality != "audio")
        {
            try
            {
                var m = await RunAsync(ytdlp, js.Concat(new[] { "-f", "bv*[protocol^=m3u8]/b[protocol^=m3u8]", "--print", "%(manifest_url)s", "--no-warnings", "--no-playlist", "--", url }), ct);
                var master = m.Split('\n',StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).LastOrDefault(l => l.StartsWith("http"));
                if (master != null)
                {
                    var hi = new StreamInfo { VideoId = videoId, VideoUrl = master, Quality = quality, IsManifest = true, MaxHeight = int.TryParse(h, out var mh) ? mh : 1080 };
                    lock (_cache) _cache[key] = (hi, DateTime.UtcNow);
                    return hi;
                }
            }
            catch (OperationCanceledException) { throw; }
            catch { /* fall through to direct formats */ }
        }
        // HLS first: VLC streams googlevideo HLS reliably, while plain DASH https URLs get throttled/cut
        // after a few seconds. Separate video+audio is fine (audio is added as an input slave).
        var filter = quality switch
        {
            "audio" => "bestaudio[ext=m4a]/bestaudio/140/best",
            // Muxed single file first (no A/V sync issues), then separate streams.
            _ => $"best[height<={h}][acodec!=none][vcodec!=none]/bestvideo[height<={h}][vcodec^=avc1]+bestaudio[ext=m4a]/bestvideo[height<={h}]+bestaudio"
        };

        string output;
        try
        {
            output = await RunAsync(ytdlp, js.Concat(new[] { "--get-url", "-f", filter + "/bv*+ba/b", "--no-warnings", "--no-playlist", "--", $"https://www.youtube.com/watch?v={videoId}" }), ct);
        }
        catch (Exception e) when (e.Message.Contains("format is not available", StringComparison.OrdinalIgnoreCase))
        {
            output = await RunAsync(ytdlp, js.Concat(new[] { "--get-url", "-f", quality == "audio" ? "ba/b" : "b/bv*+ba/bv*", "--no-warnings", "--no-playlist", "--", $"https://www.youtube.com/watch?v={videoId}" }), ct);
        }

        var lines = output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(l => l.StartsWith("http")).ToList();
        if (lines.Count == 0) throw new InvalidOperationException("Không lấy được luồng video");
        var info = new StreamInfo { VideoId = videoId, VideoUrl = lines[0], AudioUrl = lines.Count > 1 ? lines[1] : null, Quality = quality };
        lock (_cache) _cache[key] = (info, DateTime.UtcNow);
        return info;
    }

    internal static async Task<string> RunAsync(string exe, IEnumerable<string> args, CancellationToken ct = default)
    {
        var psi = new ProcessStartInfo(exe)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };
        foreach (var a in args) psi.ArgumentList.Add(a);
        psi.Environment["PYTHONIOENCODING"] = "utf-8";
        using var p = Process.Start(psi) ?? throw new InvalidOperationException("Không chạy được yt-dlp");
        using var reg = ct.Register(() => { try { p.Kill(true); } catch { } });
        var outTask = p.StandardOutput.ReadToEndAsync();
        var errTask = p.StandardError.ReadToEndAsync();
        var timeout = Task.Delay(TimeSpan.FromSeconds(60), ct);
        var exit = p.WaitForExitAsync(ct);
        if (await Task.WhenAny(exit, timeout) != exit)
        {
            try { p.Kill(true); } catch { }
            ct.ThrowIfCancellationRequested();
            throw new TimeoutException("yt-dlp quá thời gian phản hồi");
        }
        var stdout = await outTask;
        var stderr = await errTask;
        if (p.ExitCode != 0)
        {
            var msg = stderr.Split('\n').LastOrDefault(l => l.Contains("ERROR")) ?? stderr.Trim();
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(msg) ? $"yt-dlp lỗi (mã {p.ExitCode})" : msg.Trim());
        }
        return stdout;
    }
}

public sealed class SponsorBlockService
{
    public static SponsorBlockService Shared { get; } = new();

    public async Task<List<SponsorSegment>> FetchSegmentsAsync(string videoId)
    {
        try
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(4));
            var cats = Uri.EscapeDataString("[\"sponsor\",\"intro\",\"outro\",\"interaction\",\"selfpromo\"]");
            using var resp = await InnerTubeService.Http.GetAsync($"https://sponsor.ajay.app/api/skipSegments?videoID={videoId}&categories={cats}", cts.Token);
            if (!resp.IsSuccessStatusCode) return new();
            using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync(cts.Token));
            return doc.RootElement.EnumerateArray().Select(e =>
            {
                var seg = e.GetProperty("segment");
                return new SponsorSegment(e.GetProperty("category").GetString() ?? "", seg[0].GetDouble(), seg[1].GetDouble());
            }).ToList();
        }
        catch { return new(); }
    }
}
