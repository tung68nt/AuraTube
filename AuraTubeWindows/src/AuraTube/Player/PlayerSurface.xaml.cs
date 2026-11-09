using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;
using AuraTube.Services;

namespace AuraTube.Player;

/// <summary>LibVLC video surface with the AuraTube controls overlay (seek bar with SponsorBlock marks,
/// chapters, volume, speed, quality, mini player, fullscreen; auto-hides while playing).</summary>
public partial class PlayerSurface : UserControl
{
    private readonly PlayerService _p = PlayerService.Shared;
    private readonly DispatcherTimer _hideTimer = new() { Interval = TimeSpan.FromSeconds(2.8) };
    private readonly DispatcherTimer _toastTimer = new() { Interval = TimeSpan.FromSeconds(2.5) };
    private readonly DispatcherTimer _clickTimer = new() { Interval = TimeSpan.FromMilliseconds(260) };
    private bool _seeking;
    private bool _active;
    private Point _lastMouse;

    public bool CompactControls { get; set; }

    /// <summary>Raised instead of changing volume when <see cref="CompactControls"/> is set (Shorts swipe).</summary>
    public event Action<int>? Wheel;

    public PlayerSurface()
    {
        InitializeComponent();
        _hideTimer.Tick += (_, _) => { _hideTimer.Stop(); if (_p.IsPlaying && !_seeking) SetChrome(false); };
        _toastTimer.Tick += (_, _) => { _toastTimer.Stop(); ToastBox.Visibility = Visibility.Collapsed; };
        _clickTimer.Tick += (_, _) => { _clickTimer.Stop(); _p.TogglePlay(); };
        VolumeSlider.Value = _p.Volume;
        SizeChanged += (_, _) => { RenderSegments(); UpdateProgress(_p.Position, _p.Length); };
    }

    /// <summary>Route the shared player into this surface and subscribe to its events.</summary>
    public void Activate()
    {
        if (!_active)
        {
            _active = true;
            _p.StateChanged += Render;
            _p.Progress += UpdateProgress;
            _p.Toast += ShowToast;
        }
        _p.Attach(Video);
        MiniButton.Visibility = CompactControls ? Visibility.Collapsed : Visibility.Visible;
        Render();
    }

    public void Deactivate()
    {
        if (!_active) return;
        _active = false;
        _p.StateChanged -= Render;
        _p.Progress -= UpdateProgress;
        _p.Toast -= ShowToast;
        _p.Detach(Video);
    }

    public void SetNextVisible(bool v) => NextButton.Visibility = v ? Visibility.Visible : Visibility.Collapsed;

    private void Render()
    {
        TitleText.Text = _p.Current?.Title ?? "";
        PlayButton.Content = _p.IsPlaying ? "" : "";
        MuteButton.Content = _p.MediaPlayer.Mute || _p.Volume == 0 ? "" : "";
        var q = _p.CurrentQuality;
        QualityButton.Content = (AppStore.Shared.Settings.PreferredQuality == "auto" && q != "shorts" ? "Auto · " : "") + (q is "shorts" or "audio" ? q : q + "p");
        SpeedButton.Content = $"{_p.Rate:0.##}x";
        FullButton.Content = MainWindow.Instance.IsFullscreen ? "" : "";

        if (_p.LastError != null)
        {
            CenterIcon.Text = "";
            CenterText.Text = _p.LastError + "\nBấm để thử lại.";
        }
        else if (_p.IsLoading)
        {
            CenterIcon.Text = "";
            CenterText.Text = "Đang tải video…";
        }
        else
        {
            CenterIcon.Text = "";
            CenterText.Text = "";
        }
        if (!_p.IsPlaying) SetChrome(true);
        RenderSegments();
    }

    private void RenderSegments()
    {
        SegmentCanvas.Children.Clear();
        var len = _p.Length;
        var w = SeekArea.ActualWidth;
        if (len <= 0 || w <= 0) return;
        foreach (var s in _p.Segments)
        {
            var r = new Rectangle { Width = Math.Max(2, (s.End - s.Start) / len * w), Height = 4, Fill = new SolidColorBrush(Color.FromRgb(0x00, 0xD4, 0x00)), ToolTip = s.CategoryVi };
            Canvas.SetLeft(r, s.Start / len * w);
            SegmentCanvas.Children.Add(r);
        }
        foreach (var c in _p.Chapters.Skip(1))
        {
            var r = new Rectangle { Width = 2, Height = 4, Fill = Brushes.Black };
            Canvas.SetLeft(r, c.Start / len * w);
            SegmentCanvas.Children.Add(r);
        }
    }

    private void UpdateProgress(double pos, double len)
    {
        if (_seeking) return;
        SetSeekVisual(len > 0 ? pos / len : 0);
        TimeText.Text = $"{InnerTubeService.FormatDuration(pos)} / {InnerTubeService.FormatDuration(len)}";
        ChapterText.Text = _p.Chapters.LastOrDefault(c => c.Start <= pos)?.Title is { } ch ? "• " + ch : "";
        if (SegmentCanvas.Children.Count == 0 && _p.Segments.Count > 0) RenderSegments();
    }

    private void SetSeekVisual(double frac)
    {
        frac = Math.Clamp(frac, 0, 1);
        var w = SeekArea.ActualWidth;
        SeekFill.Width = w * frac;
        Canvas.SetLeft(SeekThumb, w * frac - 6);
    }

    private void ShowToast(string text)
    {
        ToastText.Text = text;
        ToastBox.Visibility = Visibility.Visible;
        _toastTimer.Stop();
        _toastTimer.Start();
    }

    private void SetChrome(bool visible)
    {
        var v = visible ? Visibility.Visible : Visibility.Hidden;
        TopBar.Visibility = BottomBar.Visibility = v;
        Overlay.Cursor = visible ? null : Cursors.None;
    }

    private void Poke()
    {
        SetChrome(true);
        _hideTimer.Stop();
        _hideTimer.Start();
    }

    private void Overlay_MouseMove(object sender, MouseEventArgs e)
    {
        var pt = e.GetPosition(this);
        if ((pt - _lastMouse).Length < 2) return;
        _lastMouse = pt;
        Poke();
    }

    private void Overlay_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.OriginalSource is not Grid g || g != Overlay) return;
        if (_p.LastError != null && _p.Current != null) { _ = _p.PlayAsync(_p.Current); return; }
        if (e.ClickCount == 2)
        {
            _clickTimer.Stop();
            if (!CompactControls) MainWindow.Instance.SetFullscreen(!MainWindow.Instance.IsFullscreen);
            return;
        }
        _clickTimer.Start();
    }

    private void Overlay_MouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (CompactControls) { Wheel?.Invoke(e.Delta); return; }
        _p.Volume += e.Delta > 0 ? 5 : -5;
        VolumeSlider.Value = _p.Volume;
        ShowToast($"Âm lượng {_p.Volume}%");
    }

    // MARK: - Seek bar

    private double FracAt(MouseEventArgs e) => Math.Clamp(e.GetPosition(SeekArea).X / Math.Max(1, SeekArea.ActualWidth), 0, 1);

    private void Seek_MouseDown(object sender, MouseButtonEventArgs e)
    {
        _seeking = true;
        SeekArea.CaptureMouse();
        SetSeekVisual(FracAt(e));
        e.Handled = true;
    }

    private void Seek_MouseMove(object sender, MouseEventArgs e)
    {
        var len = _p.Length;
        var frac = FracAt(e);
        SeekArea.ToolTip = len > 0 ? InnerTubeService.FormatDuration(frac * len) : null;
        if (_seeking) SetSeekVisual(frac);
    }

    private void Seek_MouseUp(object sender, MouseButtonEventArgs e)
    {
        if (!_seeking) return;
        _seeking = false;
        SeekArea.ReleaseMouseCapture();
        _p.Seek(FracAt(e) * _p.Length);
        e.Handled = true;
    }

    // MARK: - Buttons

    private void Play_Click(object sender, RoutedEventArgs e) => _p.TogglePlay();
    private void Next_Click(object sender, RoutedEventArgs e) => MainWindow.Instance.PlayNext();
    private void Mini_Click(object sender, RoutedEventArgs e) => MainWindow.Instance.OpenMiniPlayer();
    private void Full_Click(object sender, RoutedEventArgs e) => MainWindow.Instance.SetFullscreen(!MainWindow.Instance.IsFullscreen);

    private void Mute_Click(object sender, RoutedEventArgs e)
    {
        _p.MediaPlayer.Mute = !_p.MediaPlayer.Mute;
        Render();
    }

    private void Volume_Changed(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!IsLoaded) return;
        _p.Volume = (int)e.NewValue;
        if (_p.MediaPlayer.Mute && e.NewValue > 0) _p.MediaPlayer.Mute = false;
        MuteButton.Content = _p.Volume == 0 ? "" : "";
    }

    private void Speed_Click(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu { PlacementTarget = SpeedButton, Placement = System.Windows.Controls.Primitives.PlacementMode.Top };
        foreach (var r in new[] { 0.25f, 0.5f, 0.75f, 1f, 1.25f, 1.5f, 1.75f, 2f })
        {
            var mi = new MenuItem { Header = r == 1f ? "Bình thường" : $"{r:0.##}x", IsCheckable = true, IsChecked = Math.Abs(_p.Rate - r) < 0.01 };
            mi.Click += (_, _) => { _p.Rate = r; Render(); };
            menu.Items.Add(mi);
        }
        menu.IsOpen = true;
    }

    private void Quality_Click(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu { PlacementTarget = QualityButton, Placement = System.Windows.Controls.Primitives.PlacementMode.Top };
        var settings = AppStore.Shared.Settings;
        var auto = new MenuItem
        {
            Header = $"Tự động theo mạng ({NetworkSpeedService.Shared.TierLabel}, {NetworkSpeedService.Shared.CurrentSpeedMbps:0} Mbps)",
            IsCheckable = true, IsChecked = settings.PreferredQuality == "auto"
        };
        auto.Click += async (_, _) =>
        {
            settings.PreferredQuality = "auto";
            AppStore.Shared.SaveSettings();
            await _p.ChangeQualityAsync(_p.ResolveQuality());
        };
        menu.Items.Add(auto);
        menu.Items.Add(new Separator());
        var heights = _p.AvailableHeights.Count > 0 ? _p.AvailableHeights : new List<int> { 2160, 1440, 1080, 720, 480, 360 };
        foreach (var h in heights.Where(h => h >= 144).Distinct().OrderByDescending(h => h))
        {
            var label = h switch { >= 2160 => "2160p (4K)", >= 1440 => "1440p (2K)", _ => $"{h}p" };
            var mi = new MenuItem { Header = label, IsCheckable = true, IsChecked = settings.PreferredQuality != "auto" && _p.CurrentQuality == h.ToString() };
            mi.Click += async (_, _) =>
            {
                settings.PreferredQuality = h.ToString();
                AppStore.Shared.SaveSettings();
                await _p.ChangeQualityAsync(h.ToString());
            };
            menu.Items.Add(mi);
        }
        var audio = new MenuItem { Header = "Chỉ âm thanh", IsCheckable = true, IsChecked = _p.CurrentQuality == "audio" };
        audio.Click += async (_, _) => await _p.ChangeQualityAsync("audio");
        menu.Items.Add(audio);
        menu.IsOpen = true;
    }
}
