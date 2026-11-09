using System.Diagnostics;
using System.Net.NetworkInformation;
using AuraTube.Player;

namespace AuraTube.Services;

public enum NetworkTier { Low, Medium, High, VeryHigh, Ultra }

/// <summary>Measures download speed (Cloudflare 1 MB probe) and maps it to a playback quality. Port of NetworkSpeedService.swift.</summary>
public sealed class NetworkSpeedService
{
    public static NetworkSpeedService Shared { get; } = new();

    public double CurrentSpeedMbps { get; private set; }
    public double LatencyMs { get; private set; }
    public NetworkTier Tier { get; private set; } = NetworkTier.High;
    public DateTime? LastTest { get; private set; }
    public bool IsTesting { get; private set; }
    public event Action? Updated;

    private NetworkSpeedService()
    {
        NetworkChange.NetworkAddressChanged += (_, _) => _ = MeasureAsync(true);
    }

    public string TierLabel => Tier switch
    {
        NetworkTier.Ultra => "Rất nhanh",
        NetworkTier.VeryHigh => "Nhanh",
        NetworkTier.High => "Tốt",
        NetworkTier.Medium => "Trung bình",
        _ => "Chậm"
    };

    public async Task MeasureAsync(bool force = false)
    {
        if (IsTesting) return;
        if (!force && LastTest is DateTime t && DateTime.UtcNow - t < TimeSpan.FromMinutes(5)) return;
        IsTesting = true;
        try
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10));
            var sw = Stopwatch.StartNew();
            using (await InnerTubeService.Http.GetAsync("https://speed.cloudflare.com/__down?bytes=0", cts.Token)) { }
            var latency = sw.Elapsed.TotalMilliseconds;
            sw.Restart();
            var bytes = await InnerTubeService.Http.GetByteArrayAsync("https://speed.cloudflare.com/__down?bytes=2097152", cts.Token);
            var secs = Math.Max(0.05, sw.Elapsed.TotalSeconds - latency / 1000 * 0.5);
            Apply(bytes.Length * 8 / secs / 1_000_000, latency);
        }
        catch
        {
            if (CurrentSpeedMbps == 0) Apply(8, 0);
        }
        finally { IsTesting = false; }
    }

    private void Apply(double mbps, double latency)
    {
        LastTest = DateTime.UtcNow;
        LatencyMs = latency;
        var smoothed = CurrentSpeedMbps > 0 ? 0.75 * mbps + 0.25 * CurrentSpeedMbps : mbps;
        CurrentSpeedMbps = Math.Max(2.0, smoothed);
        Tier = CurrentSpeedMbps switch
        {
            >= 22 => NetworkTier.Ultra,
            >= 13 => NetworkTier.VeryHigh,
            >= 5.5 => NetworkTier.High,
            >= 2.5 => NetworkTier.Medium,
            _ => NetworkTier.Low
        };
        System.Windows.Application.Current?.Dispatcher.BeginInvoke(() =>
        {
            Updated?.Invoke();
            PlayerService.Shared.ReevaluateAutoQuality();
        });
    }

    /// <summary>Best height the connection sustains; 1080p cap unless the user prefers max quality.</summary>
    public string RecommendedQuality(List<int> available, bool preferMax)
    {
        var s = CurrentSpeedMbps <= 0 ? 10 : CurrentSpeedMbps;
        int target = s switch
        {
            >= 40 when preferMax => 2160,
            >= 25 when preferMax => 1440,
            >= 5.5 => 1080,
            >= 2.5 => 720,
            >= 1.2 => 480,
            _ => 360
        };
        if (available.Count == 0) return target.ToString();
        var pick = available.Where(h => h <= target).DefaultIfEmpty(available.Min()).Max();
        return pick.ToString();
    }
}
