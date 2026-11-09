using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using AuraTube.Models;
using AuraTube.Player;
using AuraTube.Services;

namespace AuraTube.Views;

public sealed record ChapterRow(string Time, string Title, double Start);

public partial class WatchView : UserControl
{
    private readonly PlayerService _p = PlayerService.Shared;
    private readonly ObservableCollection<Video> _related = new();
    private Video? _video;
    private VideoDetails? _details;
    private bool _descExpanded;
    private int _loadGen;

    public WatchView()
    {
        InitializeComponent();
        RelatedHost.Content = Ui.VideoRows(_related);
        AutoplayCheck.IsChecked = AppStore.Shared.Settings.AutoplayNext;
        SizeChanged += (_, _) => Layout();
        MainScroll.SizeChanged += (_, _) => Layout();
    }

    private void Layout()
    {
        var full = MainWindow.Instance.IsFullscreen;
        SideColumn.Width = full || ActualWidth < 1000 ? new GridLength(0) : new GridLength(400);
        SideScroll.Visibility = SideColumn.Width.Value == 0 ? Visibility.Collapsed : Visibility.Visible;
        if (full)
        {
            PlayerFrame.Height = MainScroll.ActualHeight;
            PlayerFrame.Width = MainScroll.ActualWidth;
        }
        else
        {
            var w = Math.Max(320, MainScroll.ActualWidth - 32);
            PlayerFrame.Width = double.NaN;
            PlayerFrame.Height = Math.Min(w * 9 / 16, Math.Max(240, ActualHeight - 120));
        }
    }

    public void SetFullscreenLayout(bool on)
    {
        Details.Visibility = on ? Visibility.Collapsed : Visibility.Visible;
        MainStack.Margin = on ? new Thickness(0) : new Thickness(16, 8, 16, 24);
        PlayerFrame.CornerRadius = new CornerRadius(on ? 0 : 14);
        MainScroll.VerticalScrollBarVisibility = on ? ScrollBarVisibility.Disabled : ScrollBarVisibility.Auto;
        if (on) MainScroll.ScrollToTop();
        Dispatcher.BeginInvoke(Layout, System.Windows.Threading.DispatcherPriority.Loaded);
    }

    public void OnEntering()
    {
        Surface.Activate();
        Layout();
    }

    public void OnLeaving()
    {
        // Keep audio going in the mini player when leaving the watch page mid-playback.
        if (_p.Current != null && (_p.IsPlaying || _p.IsLoading) && !MiniPlayerWindow.IsOpen)
        {
            Surface.Deactivate();
            MiniPlayerWindow.ShowShared();
        }
        else Surface.Deactivate();
    }

    public void Load(Video video, double startAt = 0)
    {
        var gen = ++_loadGen;
        _video = video;
        _details = null;
        _descExpanded = false;
        TitleText.Text = video.Title;
        ChannelText.Text = video.Uploader;
        ViewsText.Text = video.ViewCountFormatted;
        MetaText.Text = video.Subtitle;
        DescText.Text = video.Description ?? "";
        DescText.MaxHeight = 80;
        MoreText.Text = "Xem thêm";
        AvatarEllipse.Fill = Ui.Image(video.ChannelAvatarUrl) is { } img ? new ImageBrush(img) { Stretch = Stretch.UniformToFill } : null;
        ChaptersPanel.Visibility = Visibility.Collapsed;
        _p.Chapters = new();
        UpdateButtons();
        MainScroll.ScrollToTop();
        Surface.Activate();
        _ = _p.PlayAsync(video, null, startAt);
        _ = LoadDetailsAsync(video, gen);
        _ = LoadRelatedAsync(video, gen);
    }

    private async Task LoadDetailsAsync(Video video, int gen)
    {
        var d = await InnerTubeService.Shared.VideoDetailsAsync(video.Id);
        if (gen != _loadGen) return;
        _details = d;
        if (d.Title.Length > 0) TitleText.Text = video.Title = d.Title;
        if (d.Author.Length > 0) ChannelText.Text = video.Uploader = d.Author;
        if (!string.IsNullOrEmpty(d.ChannelId)) video.UploaderId = d.ChannelId;
        if (d.LengthSeconds > 0) { video.Duration = d.LengthSeconds; video.DurationFormatted = InnerTubeService.FormatDuration(d.LengthSeconds); }
        if (d.Views is long v)
        {
            video.ViewCountFormatted = InnerTubeService.FormatViews(v);
            ViewsText.Text = video.ViewCountFormatted;
        }
        MetaText.Text = video.Subtitle;
        DescText.Text = d.Description;
        MoreText.Visibility = d.Description.Length > 200 ? Visibility.Visible : Visibility.Collapsed;
        if (d.Heights.Count > 0) _p.SetAvailableHeights(d.Heights);
        _p.Chapters = d.Chapters;
        ChaptersList.ItemsSource = d.Chapters.Select(c => new ChapterRow(InnerTubeService.FormatDuration(c.Start), c.Title, c.Start)).ToList();
        ChaptersPanel.Visibility = d.Chapters.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        UpdateButtons();

        if (string.IsNullOrEmpty(video.ChannelAvatarUrl) && !string.IsNullOrEmpty(d.ChannelId))
        {
            var ch = await InnerTubeService.Shared.ChannelAsync(d.ChannelId);
            if (gen == _loadGen && Ui.Image(ch?.Channel.AvatarUrl) is { } img)
            {
                video.ChannelAvatarUrl = ch!.Channel.AvatarUrl;
                AvatarEllipse.Fill = new ImageBrush(img) { Stretch = Stretch.UniformToFill };
            }
        }
    }

    private async Task LoadRelatedAsync(Video video, int gen)
    {
        _related.Clear();
        RelatedStatus.Text = "Đang tải…";
        RelatedStatus.Visibility = Visibility.Visible;
        var list = await InnerTubeService.Shared.RelatedAsync(video.Id);
        if (list.Count == 0)
            list = (await InnerTubeService.Shared.SearchAsync(video.Uploader + " " + video.Title.Split(' ').Take(4).Aggregate("", (a, b) => a + " " + b))).Videos;
        if (gen != _loadGen) return;
        foreach (var v in list.Where(v => v.Id != video.Id && !v.IsShort)) _related.Add(v);
        RelatedStatus.Visibility = _related.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        RelatedStatus.Text = "Không có video liên quan";
    }

    public void PlayNextFromRelated()
    {
        var watched = AppStore.Shared.History.Take(50).Select(v => v.Id).ToHashSet();
        var next = _related.FirstOrDefault(v => !watched.Contains(v.Id)) ?? _related.FirstOrDefault();
        if (next == null) return;
        if (MiniPlayerWindow.IsOpen)
        {
            Load(next);
            Surface.Deactivate();
            MiniPlayerWindow.ShowShared();
        }
        else Load(next);
    }

    private void UpdateButtons()
    {
        if (_video == null) return;
        BookmarkButton.Content = AppStore.Shared.IsBookmarked(_video.Id) ? "Đã lưu" : "Xem sau";
        var subbed = AppStore.Shared.IsSubscribed(_video.UploaderId ?? _video.Uploader) || AppStore.Shared.IsSubscribed(_video.Uploader);
        SubscribeButton.Content = subbed ? "Đã đăng ký" : "Đăng ký";
        SubscribeButton.Style = Ui.Res<Style>(subbed ? "PillButton" : "AccentButton");
    }

    private void Channel_Click(object sender, MouseButtonEventArgs e)
    {
        if (_video == null) return;
        MainWindow.Instance.OpenChannel(_video.UploaderId ?? _video.Uploader,
            new ChannelInfo { Id = _video.UploaderId ?? "", Title = _video.Uploader, AvatarUrl = _video.ChannelAvatarUrl ?? "" });
    }

    private void Subscribe_Click(object sender, RoutedEventArgs e)
    {
        if (_video == null) return;
        var key = _video.UploaderId ?? _video.Uploader;
        if (AppStore.Shared.IsSubscribed(key) || AppStore.Shared.IsSubscribed(_video.Uploader))
        {
            AppStore.Shared.Unsubscribe(key);
            AppStore.Shared.Unsubscribe(_video.Uploader);
        }
        else AppStore.Shared.Subscribe(new SubscribedChannel { Id = _video.UploaderId, Title = _video.Uploader, AvatarUrl = _video.ChannelAvatarUrl });
        UpdateButtons();
    }

    private void Bookmark_Click(object sender, RoutedEventArgs e)
    {
        if (_video == null) return;
        MainWindow.Instance.ShowToast(AppStore.Shared.ToggleBookmark(_video) ? "Đã lưu vào Xem sau" : "Đã bỏ khỏi Xem sau");
        UpdateButtons();
    }

    private void Download_Click(object sender, RoutedEventArgs e) { if (_video != null) DownloadDialog.Show(_video, _details?.Heights); }

    private void Copy_Click(object sender, RoutedEventArgs e)
    {
        if (_video == null) return;
        try { Clipboard.SetText(_video.WatchUrl); MainWindow.Instance.ShowToast("Đã sao chép link"); } catch { }
    }

    private void Mini_Click(object sender, RoutedEventArgs e) => MainWindow.Instance.OpenMiniPlayer();

    private void More_Click(object sender, MouseButtonEventArgs e)
    {
        _descExpanded = !_descExpanded;
        DescText.MaxHeight = _descExpanded ? double.PositiveInfinity : 80;
        MoreText.Text = _descExpanded ? "Ẩn bớt" : "Xem thêm";
    }

    private void Chapter_Click(object sender, MouseButtonEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is ChapterRow c) _p.Seek(c.Start);
    }

    private void Autoplay_Changed(object sender, RoutedEventArgs e)
    {
        AppStore.Shared.Settings.AutoplayNext = AutoplayCheck.IsChecked == true;
        AppStore.Shared.SaveSettings();
    }
}
