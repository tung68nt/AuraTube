using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using AuraTube.Models;
using AuraTube.Player;
using AuraTube.Services;

namespace AuraTube.Views;

/// <summary>Vertical Shorts feed: one 9:16 player, wheel / arrow keys / buttons move between shorts.</summary>
public sealed class ShortsView : UserControl
{
    private readonly PlayerSurface _surface = new() { CompactControls = true };
    private readonly Border _frame;
    private readonly TextBlock _title = new() { FontSize = 17, FontWeight = FontWeights.Bold, TextWrapping = TextWrapping.Wrap };
    private readonly TextBlock _channel = new() { FontSize = 14, FontWeight = FontWeights.SemiBold, Cursor = Cursors.Hand, Margin = new Thickness(0, 8, 0, 0) };
    private readonly TextBlock _views = Ui.Sub("");
    private readonly TextBlock _status = Ui.Sub("Đang tải Shorts…");
    private readonly StackPanel _side;
    private readonly List<Video> _queue = new();
    private int _index = -1;
    private bool _loadingMore;
    private DateTime _lastWheel;

    public ShortsView(Video? start = null)
    {
        _frame = new Border { CornerRadius = new CornerRadius(16), Background = System.Windows.Media.Brushes.Black, ClipToBounds = true, Child = _surface, HorizontalAlignment = HorizontalAlignment.Center };
        _surface.Wheel += d => Step(d < 0 ? 1 : -1);
        _channel.MouseLeftButtonUp += (_, _) => { if (Current is { } v) MainWindow.Instance.OpenChannel(v.UploaderId ?? v.Uploader); };

        var nav = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(16, 0, 0, 0) };
        var up = new Button { Content = "", Style = Ui.Res<Style>("IconButton"), Background = Ui.Res<System.Windows.Media.Brush>("Surface2Brush"), Width = 48, Height = 48, Margin = new Thickness(0, 0, 0, 12), ToolTip = "Short trước (↑)" };
        up.Click += (_, _) => Step(-1);
        var down = new Button { Content = "", Style = Ui.Res<Style>("IconButton"), Background = Ui.Res<System.Windows.Media.Brush>("Surface2Brush"), Width = 48, Height = 48, ToolTip = "Short tiếp theo (↓)" };
        down.Click += (_, _) => Step(1);
        nav.Children.Add(up);
        nav.Children.Add(down);

        _side = new StackPanel { Width = 300, Margin = new Thickness(24, 0, 0, 0), VerticalAlignment = VerticalAlignment.Bottom };
        _side.Children.Add(_title);
        _side.Children.Add(_channel);
        _side.Children.Add(_views);
        var buttons = new WrapPanel { Margin = new Thickness(0, 12, 0, 0) };
        buttons.Children.Add(Ui.Pill("Xem sau", (_, _) => { if (Current is { } v) MainWindow.Instance.ShowToast(AppStore.Shared.ToggleBookmark(v) ? "Đã lưu vào Xem sau" : "Đã bỏ khỏi Xem sau"); }));
        buttons.Children.Add(Ui.Pill("Tải xuống", (_, _) => { if (Current is { } v) DownloadDialog.Show(v); }));
        buttons.Children.Add(Ui.Pill("Sao chép link", (_, _) => { if (Current is { } v) try { Clipboard.SetText($"https://www.youtube.com/shorts/{v.Id}"); } catch { } }));
        _side.Children.Add(buttons);
        _side.Children.Add(_status);

        var row = new Grid { Margin = new Thickness(16) };
        row.ColumnDefinitions.Add(new ColumnDefinition());
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition());
        Grid.SetColumn(_frame, 1);
        Grid.SetColumn(_side, 2);
        row.Children.Add(_frame);
        row.Children.Add(_side);
        var navHost = new Grid();
        navHost.Children.Add(nav);
        nav.HorizontalAlignment = HorizontalAlignment.Left;
        Grid.SetColumn(navHost, 3);
        row.Children.Add(navHost);
        Content = row;
        Focusable = true;

        SizeChanged += (_, _) => LayoutFrame();
        PreviewMouseWheel += (_, e) => { Step(e.Delta < 0 ? 1 : -1); e.Handled = true; };
        if (start != null) _queue.Add(start);
    }

    private Video? Current => _index >= 0 && _index < _queue.Count ? _queue[_index] : null;

    private void LayoutFrame()
    {
        var h = Math.Max(300, ActualHeight - 32);
        _frame.Height = h;
        _frame.Width = h * 9 / 16;
    }

    public void SetFullscreenLayout(bool on) => _side.Visibility = on ? Visibility.Collapsed : Visibility.Visible;

    public async void OnEntering()
    {
        MainWindow.Instance.PreviewKeyDown += OnKey;
        PlayerService.Shared.Ended += OnEnded;
        MiniPlayerWindow.CloseIfOpen();
        _surface.Activate();
        if (_queue.Count == 0 || _queue.Count < 3) await LoadMoreAsync();
        if (_index < 0) Show(0);
        else Show(_index);
    }

    public void OnLeaving()
    {
        MainWindow.Instance.PreviewKeyDown -= OnKey;
        PlayerService.Shared.Ended -= OnEnded;
        PlayerService.Shared.Stop();
        _surface.Deactivate();
    }

    private void OnEnded()
    {
        // Shorts loop, like the YouTube app.
        if (Current is { } v) _ = PlayerService.Shared.PlayAsync(v, isShort: true);
    }

    private void OnKey(object sender, KeyEventArgs e)
    {
        if (Keyboard.FocusedElement is TextBox) return;
        switch (e.Key)
        {
            case Key.Down or Key.PageDown: Step(1); e.Handled = true; break;
            case Key.Up or Key.PageUp: Step(-1); e.Handled = true; break;
            case Key.Space or Key.K: PlayerService.Shared.TogglePlay(); e.Handled = true; break;
            case Key.M: PlayerService.Shared.MediaPlayer.Mute = !PlayerService.Shared.MediaPlayer.Mute; e.Handled = true; break;
        }
    }

    private async Task LoadMoreAsync()
    {
        if (_loadingMore) return;
        _loadingMore = true;
        try
        {
            var more = await FeedService.Shared.ShortsAsync(_queue.Select(v => v.Id));
            _queue.AddRange(more);
            _status.Text = _queue.Count == 0 ? "Không tải được Shorts. Kiểm tra kết nối mạng." : "";
        }
        finally { _loadingMore = false; }
    }

    private void Step(int dir)
    {
        if ((DateTime.UtcNow - _lastWheel).TotalMilliseconds < 450) return;
        _lastWheel = DateTime.UtcNow;
        var next = _index + dir;
        if (next < 0 || next >= _queue.Count) return;
        Show(next);
        if (_queue.Count - next < 4) _ = LoadMoreAsync();
    }

    private void Show(int i)
    {
        if (i < 0 || i >= _queue.Count) return;
        _index = i;
        var v = _queue[i];
        _title.Text = v.Title;
        _channel.Text = v.Uploader;
        _views.Text = v.ViewCountFormatted;
        _ = PlayerService.Shared.PlayAsync(v, isShort: true);
    }
}
