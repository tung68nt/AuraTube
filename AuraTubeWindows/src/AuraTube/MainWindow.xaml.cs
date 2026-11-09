using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using AuraTube.Models;
using AuraTube.Player;
using AuraTube.Services;
using AuraTube.Views;

namespace AuraTube;

public partial class MainWindow : Window
{
    public static MainWindow Instance { get; private set; } = null!;

    private readonly Stack<FrameworkElement> _back = new();
    private readonly DispatcherTimer _toastTimer = new() { Interval = TimeSpan.FromSeconds(2.5) };
    private readonly DispatcherTimer _suggestTimer = new() { Interval = TimeSpan.FromMilliseconds(220) };
    private WatchView? _watch;
    private TrayIcon? _tray;
    private bool _isFullscreen;
    private WindowState _preFullscreenState;
    private AppUpdateInfo? _pendingUpdate;
    public bool ReallyClose { get; set; }

    public MainWindow()
    {
        Instance = this;
        InitializeComponent();
        _toastTimer.Tick += (_, _) => { _toastTimer.Stop(); ToastBorder.Visibility = Visibility.Collapsed; };
        _suggestTimer.Tick += async (_, _) => { _suggestTimer.Stop(); await LoadSuggestionsAsync(); };
        SubsList.ItemsSource = AppStore.Shared.Subscriptions;
        AppStore.Shared.Subscriptions.CollectionChanged += (_, _) => UpdateSubsHeader();
        UpdateSubsHeader();
        YtDlpBinary.Shared.StatusChanged += s => Dispatcher.BeginInvoke(() => ShowToast(s));

        Loaded += async (_, _) =>
        {
            App.Log("loaded");
            _tray = new TrayIcon(this);
            (await PlayerService.WarmupAsync()).Ended += OnPlaybackEnded;
            App.Log("player ready");
            _ = DebugSnapshotsAsync();
            ShowPage(new HomeView(), clearHistory: true);
            if (AppStore.Shared.Settings.AutoCheckUpdates) await CheckUpdatesAsync(false);
        };
        PreviewKeyDown += OnPreviewKeyDown;
        PreviewMouseDown += (_, e) => { if (e.ChangedButton == MouseButton.XButton1) GoBack(); };
    }

    private void UpdateSubsHeader()
    {
        var any = AppStore.Shared.Subscriptions.Count > 0;
        SubsHeader.Visibility = any ? Visibility.Visible : Visibility.Collapsed;
    }

    // MARK: - Navigation

    public FrameworkElement? CurrentPage => Host.Content as FrameworkElement;

    public void ShowPage(FrameworkElement page, bool clearHistory = false)
    {
        if (clearHistory) _back.Clear();
        else if (CurrentPage != null && !ReferenceEquals(CurrentPage, page)) _back.Push(CurrentPage);
        SwitchTo(page);
    }

    private void SwitchTo(FrameworkElement page)
    {
        var leaving = CurrentPage;
        if (ReferenceEquals(leaving, page)) return;
        if (leaving is WatchView wv) wv.OnLeaving();
        if (leaving is ShortsView sv) sv.OnLeaving();
        Host.Content = page;
        if (page is WatchView w) w.OnEntering();
        if (page is ShortsView s) s.OnEntering();
        BackButton.Visibility = _back.Count > 0 ? Visibility.Visible : Visibility.Hidden;
        SyncNavSelection(page);
    }

    private void SyncNavSelection(FrameworkElement page)
    {
        RadioButton? nav = page switch
        {
            HomeView => NavHome,
            ShortsView => NavShorts,
            DownloadsView => NavDownloads,
            SettingsView => NavSettings,
            VideoGridView g when g.NavKey == "subs" => NavSubs,
            VideoGridView g when g.NavKey == "bookmarks" => NavBookmarks,
            VideoGridView g when g.NavKey == "history" => NavHistory,
            _ => null
        };
        foreach (var rb in new[] { NavHome, NavShorts, NavSubs, NavBookmarks, NavHistory, NavDownloads, NavSettings })
            rb.IsChecked = ReferenceEquals(rb, nav);
    }

    public void GoBack()
    {
        if (_isFullscreen) { SetFullscreen(false); return; }
        if (_back.Count == 0) return;
        SwitchTo(_back.Pop());
    }

    private void Back_Click(object sender, RoutedEventArgs e) => GoBack();

    private void Nav_Click(object sender, RoutedEventArgs e)
    {
        FrameworkElement page = sender switch
        {
            _ when sender == NavHome => new HomeView(),
            _ when sender == NavShorts => new ShortsView(),
            _ when sender == NavSubs => VideoGridView.Subscriptions(),
            _ when sender == NavBookmarks => VideoGridView.Bookmarks(),
            _ when sender == NavHistory => VideoGridView.History(),
            _ when sender == NavDownloads => new DownloadsView(),
            _ => new SettingsView()
        };
        ShowPage(page);
    }

    private void SubItem_Click(object sender, MouseButtonEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is SubscribedChannel ch)
            OpenChannel(ch.Id ?? ch.Handle ?? ch.Title, new ChannelInfo { Id = ch.Id ?? "", Title = ch.Title, Handle = ch.Handle, AvatarUrl = ch.AvatarUrl ?? "" });
    }

    public void OpenVideo(Video video, double startAt = 0)
    {
        if (video.IsShort && CurrentPage is not WatchView)
        {
            ShowPage(new ShortsView(video));
            return;
        }
        MiniPlayerWindow.CloseIfOpen();
        _watch ??= new WatchView();
        if (!ReferenceEquals(CurrentPage, _watch)) ShowPage(_watch);
        _watch.Load(video, startAt);
    }

    public void OpenVideoById(string id) =>
        OpenVideo(new Video { Id = id, Title = "Đang tải…", Thumbnail = $"https://i.ytimg.com/vi/{id}/hqdefault.jpg" });

    /// <summary>Return from the mini player to the watch page without reloading the stream.</summary>
    public void ReturnToWatch()
    {
        ShowAndActivate();
        MiniPlayerWindow.CloseIfOpen();
        if (_watch == null || PlayerService.Shared.Current == null) return;
        if (!ReferenceEquals(CurrentPage, _watch)) ShowPage(_watch);
        else _watch.OnEntering();
    }

    public void OpenChannel(string idOrQuery, ChannelInfo? fallback = null) => ShowPage(new ChannelView(idOrQuery, fallback));

    public void Search(string query)
    {
        query = query.Trim();
        if (query.Length == 0) return;
        SuggestPopup.IsOpen = false;
        var id = query.Contains("youtu") || query.Length == 11 ? InnerTubeService.ParseVideoId(query) : null;
        if (id != null) { OpenVideoById(id); return; }
        AppStore.Shared.RecordSearch(query);
        ShowPage(VideoGridView.SearchResults(query));
    }

    private void OnPlaybackEnded()
    {
        if (CurrentPage is ShortsView) return;
        if (!AppStore.Shared.Settings.AutoplayNext) return;
        _watch?.PlayNextFromRelated();
    }

    public void PlayNext() => _watch?.PlayNextFromRelated();

    // MARK: - Search

    private void SearchBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) Search(SearchBox.Text);
        else if (e.Key == Key.Down && SuggestPopup.IsOpen && SuggestList.Items.Count > 0)
        {
            SuggestList.SelectedIndex = 0;
            (SuggestList.ItemContainerGenerator.ContainerFromIndex(0) as ListBoxItem)?.Focus();
        }
        else if (e.Key == Key.Escape) SuggestPopup.IsOpen = false;
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        SearchPlaceholder.Visibility = SearchBox.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        if (SearchBox.IsKeyboardFocused) { _suggestTimer.Stop(); _suggestTimer.Start(); }
    }

    private void SearchBox_GotFocus(object sender, KeyboardFocusChangedEventArgs e)
    {
        if (SearchBox.Text.Length == 0 && AppStore.Shared.RecentSearches.Count > 0)
        {
            SuggestList.ItemsSource = AppStore.Shared.RecentSearches.Take(10).ToList();
            SuggestPopup.IsOpen = true;
        }
    }

    private async Task LoadSuggestionsAsync()
    {
        var q = SearchBox.Text;
        var list = q.Trim().Length == 0 ? AppStore.Shared.RecentSearches.Take(10).ToList() : await InnerTubeService.Shared.SuggestionsAsync(q);
        if (q != SearchBox.Text) return;
        SuggestList.ItemsSource = list;
        SuggestPopup.IsOpen = list.Count > 0 && SearchBox.IsKeyboardFocused;
    }

    private void SuggestList_Click(object sender, MouseButtonEventArgs e)
    {
        if (SuggestList.SelectedItem is string s) { SearchBox.Text = s; Search(s); }
    }

    private void SuggestList_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter && SuggestList.SelectedItem is string s) { SearchBox.Text = s; Search(s); }
        if (e.Key == Key.Escape) { SuggestPopup.IsOpen = false; SearchBox.Focus(); }
    }

    private void ClearSearch_Click(object sender, RoutedEventArgs e) { SearchBox.Clear(); SearchBox.Focus(); }

    private void OpenLink_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new InputDialog("Mở link YouTube", "Dán link video, Shorts hoặc kênh YouTube:") { Owner = this };
        if (dlg.ShowDialog() != true) return;
        var text = dlg.Value.Trim();
        var id = InnerTubeService.ParseVideoId(text);
        if (id != null) { OpenVideoById(id); return; }
        var m = System.Text.RegularExpressions.Regex.Match(text, @"youtube\.com/(?:channel/(UC[\w-]{20,})|(@[\w.\-]+))");
        if (m.Success) OpenChannel(m.Groups[1].Success ? m.Groups[1].Value : m.Groups[2].Value);
        else ShowToast("Link không hợp lệ");
    }

    private void SignIn_Click(object sender, RoutedEventArgs e) => StartGoogleSync();

    public async void StartGoogleSync()
    {
        var win = new SignInWindow { Owner = this };
        win.ShowDialog();
        if (win.ImportedCount > 0)
        {
            ShowToast($"Đã đồng bộ {win.ImportedCount} kênh đăng ký");
            await Task.Delay(100);
            ShowPage(VideoGridView.Subscriptions());
        }
    }

    // MARK: - Toast

    public void ShowToast(string text)
    {
        ToastText.Text = text;
        ToastBorder.Visibility = Visibility.Visible;
        _toastTimer.Stop();
        _toastTimer.Start();
    }

    // MARK: - Fullscreen

    public bool IsFullscreen => _isFullscreen;

    public void SetFullscreen(bool on)
    {
        if (on == _isFullscreen) return;
        _isFullscreen = on;
        TopBar.Visibility = Sidebar.Visibility = on ? Visibility.Collapsed : Visibility.Visible;
        if (on)
        {
            _preFullscreenState = WindowState;
            WindowState = WindowState.Normal; // required for borderless to cover the taskbar
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.NoResize;
            WindowState = WindowState.Maximized;
        }
        else
        {
            WindowStyle = WindowStyle.SingleBorderWindow;
            ResizeMode = ResizeMode.CanResize;
            WindowState = _preFullscreenState;
        }
        _watch?.SetFullscreenLayout(on);
        if (CurrentPage is ShortsView sv) sv.SetFullscreenLayout(on);
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (Keyboard.FocusedElement is TextBox) return;
        var p = PlayerService.Shared;
        var onPlayer = CurrentPage is WatchView;
        switch (e.Key)
        {
            case Key.Escape when _isFullscreen: SetFullscreen(false); e.Handled = true; break;
            case Key.F when onPlayer: SetFullscreen(!_isFullscreen); e.Handled = true; break;
            case Key.Space or Key.K when onPlayer: p.TogglePlay(); e.Handled = true; break;
            case Key.Left when onPlayer: p.SeekBy(-5); e.Handled = true; break;
            case Key.Right when onPlayer: p.SeekBy(5); e.Handled = true; break;
            case Key.J when onPlayer: p.SeekBy(-10); e.Handled = true; break;
            case Key.L when onPlayer: p.SeekBy(10); e.Handled = true; break;
            case Key.Up when onPlayer: p.Volume += 5; e.Handled = true; break;
            case Key.Down when onPlayer: p.Volume -= 5; e.Handled = true; break;
            case Key.M when onPlayer: p.MediaPlayer.Mute = !p.MediaPlayer.Mute; e.Handled = true; break;
            case Key.N when Keyboard.Modifiers == ModifierKeys.Shift && onPlayer: PlayNext(); e.Handled = true; break;
            case Key.I when onPlayer: OpenMiniPlayer(); e.Handled = true; break;
            case Key.Left when Keyboard.Modifiers == ModifierKeys.Alt: GoBack(); e.Handled = true; break;
            case Key.BrowserBack: GoBack(); e.Handled = true; break;
            case Key.MediaPlayPause: p.TogglePlay(); e.Handled = true; break;
            case Key.MediaNextTrack: PlayNext(); e.Handled = true; break;
        }
    }

    // MARK: - Mini player / tray

    public void OpenMiniPlayer()
    {
        if (PlayerService.Shared.Current == null) return;
        if (_isFullscreen) SetFullscreen(false);
        MiniPlayerWindow.ShowShared();
        if (CurrentPage is WatchView)
        {
            if (_back.Count > 0) SwitchTo(_back.Pop());
            else ShowPage(new HomeView(), clearHistory: true);
        }
    }

    public void ShowAndActivate()
    {
        Show();
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        if (!ReallyClose && AppStore.Shared.Settings.MinimizeToTray)
        {
            e.Cancel = true;
            if (_isFullscreen) SetFullscreen(false);
            Hide();
            _tray?.ShowHint();
            return;
        }
        base.OnClosing(e);
    }

    protected override void OnClosed(EventArgs e)
    {
        _tray?.Dispose();
        MiniPlayerWindow.CloseIfOpen();
        Application.Current.Shutdown();
        base.OnClosed(e);
    }

    public void ExitApp()
    {
        ReallyClose = true;
        Close();
    }

    /// <summary>Diagnostics: AURATUBE_SNAPSHOT=dir renders pages to PNG (used to verify UI without screen access).</summary>
    private async Task DebugSnapshotsAsync()
    {
        var dir = Environment.GetEnvironmentVariable("AURATUBE_SNAPSHOT");
        if (string.IsNullOrEmpty(dir)) return;
        System.IO.Directory.CreateDirectory(dir);
        void Snap(string name)
        {
            var bmp = new System.Windows.Media.Imaging.RenderTargetBitmap((int)ActualWidth, (int)ActualHeight, 96, 96, System.Windows.Media.PixelFormats.Pbgra32);
            bmp.Render(this);
            var enc = new System.Windows.Media.Imaging.PngBitmapEncoder();
            enc.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(bmp));
            using var fs = System.IO.File.Create(System.IO.Path.Combine(dir, name + ".png"));
            enc.Save(fs);
            App.Log("snapshot " + name);
        }
        await Task.Delay(12000); Snap("1-home");
        ShowPage(new ShortsView()); await Task.Delay(10000); Snap("2-shorts");
        Search("sơn tùng"); await Task.Delay(8000); Snap("3-search");
        OpenChannel("@SonTungMTP"); await Task.Delay(8000); Snap("4-channel");
        OpenVideoById("jNQXAC9IVRw");
        for (var i = 0; i < 10; i++) { await Task.Delay(2500); App.Log($"t+{i}: state={PlayerService.Shared.MediaPlayer.State} pos={PlayerService.Shared.Position:0.0} len={PlayerService.Shared.Length:0.0} err={PlayerService.Shared.LastError}"); }
        Snap("5-watch");
        App.Log("player state: " + PlayerService.Shared.MediaPlayer.State + " err=" + PlayerService.Shared.LastError + " pos=" + PlayerService.Shared.Position);
        ShowPage(new SettingsView()); await Task.Delay(4000); Snap("6-settings");
        ShowPage(new DownloadsView()); await Task.Delay(1000); Snap("7-downloads");
    }

    // MARK: - Updates

    public async Task<bool> CheckUpdatesAsync(bool userInitiated)
    {
        var info = await UpdateService.Shared.CheckAsync();
        if (info == null)
        {
            if (userInitiated) ShowToast($"Bạn đang dùng bản mới nhất ({UpdateService.CurrentVersion})");
            return false;
        }
        _pendingUpdate = info;
        UpdateBadge.Visibility = Visibility.Visible;
        if (userInitiated || AppStore.Shared.Settings.SkippedUpdateVersion != info.Version)
            new UpdateWindow(info) { Owner = this }.ShowDialog();
        return true;
    }

    private void UpdateBadge_Click(object sender, RoutedEventArgs e)
    {
        if (_pendingUpdate != null) new UpdateWindow(_pendingUpdate) { Owner = this }.ShowDialog();
    }
}
