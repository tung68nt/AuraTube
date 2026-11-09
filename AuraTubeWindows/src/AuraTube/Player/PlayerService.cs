using System.Windows;
using System.Windows.Threading;
using AuraTube.Models;
using AuraTube.Services;
using LibVLCSharp.Shared;
using LibVLCSharp.WPF;

namespace AuraTube.Player;

/// <summary>
/// Single LibVLC media player shared by the watch page, Shorts, fullscreen and the mini player.
/// LibVLC plays YouTube's separate DASH video + audio streams (audio added as an input slave)
/// and HLS manifests natively, so no ads and no WebView are involved.
/// </summary>
public sealed class PlayerService
{
    private static readonly Lazy<PlayerService> _shared = new(() => new PlayerService(), LazyThreadSafetyMode.ExecutionAndPublication);
    public static PlayerService Shared => _shared.Value;

    /// <summary>LibVLC scans plugins on first run (seconds); build it off the UI thread at startup.</summary>
    public static Task<PlayerService> WarmupAsync() => Task.Run(() => _shared.Value);

    public LibVLC LibVLC { get; }
    public MediaPlayer MediaPlayer { get; }

    public Video? Current { get; private set; }
    public string CurrentQuality { get; private set; } = "1080";
    public List<int> AvailableHeights { get; private set; } = new();
    public List<SponsorSegment> Segments { get; private set; } = new();
    public List<VideoChapter> Chapters { get; set; } = new();
    public bool IsLoading { get; private set; }
    public string? LastError { get; private set; }

    /// <summary>Raised on the UI thread whenever state worth re-rendering changes.</summary>
    public event Action? StateChanged;
    public event Action<string>? Toast;
    public event Action? Ended;
    /// <summary>Position in seconds, raised ~4x/second on the UI thread.</summary>
    public event Action<double, double>? Progress;

    private readonly HashSet<SponsorSegment> _skipped = new();
    private VideoView? _view;
    private CancellationTokenSource? _loadCts;
    private readonly Dispatcher _ui;
    private long _lastProgressTick;
    private Media? _media;

    private PlayerService()
    {
        _ui = Application.Current.Dispatcher;
        App.Log("libvlc init");
        Core.Initialize();
        LibVLC = new LibVLC("--network-caching=1500", "--no-video-title-show", "--quiet",
            $"--http-user-agent={InnerTubeService.UserAgent}");
        if (Environment.GetEnvironmentVariable("AURATUBE_VLCLOG") == "1")
            LibVLC.Log += (_, e) => { if (e.Level >= LogLevel.Warning) App.Log($"vlc {e.Level} {e.Module}: {e.Message}"); };
        MediaPlayer = new MediaPlayer(LibVLC) { EnableHardwareDecoding = true };
        MediaPlayer.Volume = (int)AppStore.Shared.Settings.Volume;
        MediaPlayer.TimeChanged += (_, e) => OnTime(e.Time / 1000.0);
        MediaPlayer.Playing += (_, _) => Ui(() => { IsLoading = false; StateChanged?.Invoke(); });
        MediaPlayer.Paused += (_, _) => Ui(() => StateChanged?.Invoke());
        MediaPlayer.Stopped += (_, _) => Ui(() => StateChanged?.Invoke());
        MediaPlayer.EndReached += (_, _) => Ui(() => { StateChanged?.Invoke(); Ended?.Invoke(); });
        MediaPlayer.EncounteredError += (_, _) => Ui(() => { IsLoading = false; LastError = "Lỗi phát video"; StateChanged?.Invoke(); });
    }

    private void Ui(Action a) => _ui.BeginInvoke(a);

    public bool IsPlaying => MediaPlayer.IsPlaying;
    public double Position => Math.Max(0, MediaPlayer.Time / 1000.0);
    public double Length => Current?.Duration is double d && d > 0 ? d : Math.Max(0, MediaPlayer.Length / 1000.0);

    /// <summary>Attach the player output to a VideoView. Moving between views restarts the stream at the same position.</summary>
    public void Attach(VideoView view)
    {
        if (ReferenceEquals(_view, view)) return;
        var resume = _media != null && (MediaPlayer.IsPlaying || MediaPlayer.State == VLCState.Paused);
        var pos = Position;
        var wasPlaying = MediaPlayer.IsPlaying;
        if (_view != null) _view.MediaPlayer = null;
        _view = view;
        if (resume)
        {
            MediaPlayer.Stop();
            view.MediaPlayer = MediaPlayer;
            // VideoView assigns its HWND once loaded; give it a tick before restarting playback.
            _ui.BeginInvoke(DispatcherPriority.Loaded, () =>
            {
                if (_media == null) return;
                MediaPlayer.Play(_media);
                SeekAfterStart(pos, wasPlaying);
            });
        }
        else view.MediaPlayer = MediaPlayer;
    }

    public void Detach(VideoView view)
    {
        if (!ReferenceEquals(_view, view)) return;
        view.MediaPlayer = null;
        _view = null;
    }

    private void SeekAfterStart(double pos, bool play)
    {
        void Handler(object? s, EventArgs e)
        {
            MediaPlayer.Playing -= Handler;
            ThreadPool.QueueUserWorkItem(_ =>
            {
                if (pos > 1) MediaPlayer.Time = (long)(pos * 1000);
                if (!play) MediaPlayer.SetPause(true);
            });
        }
        MediaPlayer.Playing += Handler;
    }

    public string ResolveQuality(string? requested = null)
    {
        var pref = requested ?? AppStore.Shared.Settings.PreferredQuality;
        if (pref != "auto") return pref;
        return NetworkSpeedService.Shared.RecommendedQuality(AvailableHeights, AppStore.Shared.Settings.PreferMaxQuality);
    }

    public async Task PlayAsync(Video video, string? quality = null, double startAt = 0, bool isShort = false)
    {
        _loadCts?.Cancel();
        var cts = _loadCts = new CancellationTokenSource();
        Current = video;
        IsLoading = true;
        LastError = null;
        Segments = new();
        _skipped.Clear();
        if (quality == null) AvailableHeights = new();
        StateChanged?.Invoke();
        ThreadPool.QueueUserWorkItem(_ => MediaPlayer.Stop());
        AppStore.Shared.AddHistory(video);

        var q = isShort ? "shorts" : ResolveQuality(quality);
        CurrentQuality = q;
        try
        {
            var info = await YtDlpService.Shared.GetStreamInfoAsync(video.Id, q, cts.Token);
            if (cts.IsCancellationRequested) return;
            var media = new Media(LibVLC, new Uri(info.VideoUrl));
            media.AddOption($":http-user-agent={InnerTubeService.UserAgent}");
            media.AddOption(":http-reconnect");
            if (info.IsManifest)
            {
                media.AddOption($":adaptive-maxheight={info.MaxHeight}");
                media.AddOption(":adaptive-logic=highest");
            }
            if (info.AudioUrl != null) media.AddSlave(MediaSlaveType.Audio, 4, info.AudioUrl);
            var old = _media;
            _media = media;
            MediaPlayer.Play(media);
            old?.Dispose();
            if (startAt > 1) SeekAfterStart(startAt, true);
            StateChanged?.Invoke();

            if (AppStore.Shared.Settings.SponsorBlockEnabled && !isShort)
            {
                var segs = await SponsorBlockService.Shared.FetchSegmentsAsync(video.Id);
                if (!cts.IsCancellationRequested) { Segments = segs; StateChanged?.Invoke(); }
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception e)
        {
            if (cts.IsCancellationRequested) return;
            IsLoading = false;
            LastError = e.Message;
            StateChanged?.Invoke();
        }
    }

    public void SetAvailableHeights(List<int> heights)
    {
        AvailableHeights = heights;
        StateChanged?.Invoke();
    }

    public Task ChangeQualityAsync(string quality)
    {
        if (Current == null) return Task.CompletedTask;
        var pos = Position;
        return PlayAsync(Current, quality, pos);
    }

    /// <summary>Called by NetworkSpeedService when the measured tier changes and quality is on Auto.</summary>
    public void ReevaluateAutoQuality()
    {
        if (Current == null || AppStore.Shared.Settings.PreferredQuality != "auto" || CurrentQuality is "shorts" or "audio") return;
        var q = ResolveQuality();
        if (q != CurrentQuality && int.TryParse(q, out var nq) && int.TryParse(CurrentQuality, out var cq) && nq < cq)
        {
            Toast?.Invoke($"Mạng chậm, tự chuyển sang {q}p");
            _ = ChangeQualityAsync(q);
        }
    }

    public void TogglePlay()
    {
        if (_media == null) return;
        ThreadPool.QueueUserWorkItem(_ =>
        {
            if (MediaPlayer.State == VLCState.Ended) { MediaPlayer.Stop(); MediaPlayer.Play(_media); }
            else MediaPlayer.Pause();
        });
    }

    public void Pause() => ThreadPool.QueueUserWorkItem(_ => MediaPlayer.SetPause(true));

    public void Seek(double seconds)
    {
        var len = Length;
        if (len > 0) seconds = Math.Clamp(seconds, 0, len - 0.5);
        ThreadPool.QueueUserWorkItem(_ => MediaPlayer.Time = (long)(Math.Max(0, seconds) * 1000));
    }

    public void SeekBy(double delta) => Seek(Position + delta);

    public int Volume
    {
        get => MediaPlayer.Volume;
        set
        {
            MediaPlayer.Volume = Math.Clamp(value, 0, 100);
            AppStore.Shared.Settings.Volume = MediaPlayer.Volume;
        }
    }

    public float Rate
    {
        get => MediaPlayer.Rate;
        set => MediaPlayer.SetRate(value);
    }

    public void Stop()
    {
        _loadCts?.Cancel();
        Current = null;
        ThreadPool.QueueUserWorkItem(_ => MediaPlayer.Stop());
        StateChanged?.Invoke();
    }

    private void OnTime(double t)
    {
        foreach (var seg in Segments)
        {
            if (t >= seg.Start && t < seg.End - 0.3 && !_skipped.Contains(seg))
            {
                _skipped.Add(seg);
                ThreadPool.QueueUserWorkItem(_ => MediaPlayer.Time = (long)(seg.End * 1000));
                Ui(() => Toast?.Invoke($"Đã bỏ qua: {seg.CategoryVi}"));
                break;
            }
        }
        var now = Environment.TickCount64;
        if (now - _lastProgressTick < 250) return;
        _lastProgressTick = now;
        Ui(() => Progress?.Invoke(t, Length));
    }
}
