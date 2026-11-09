using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using AuraTube.Models;
using AuraTube.Services;

namespace AuraTube.Views;

public sealed record FeedPage(List<Video> Videos, List<Video> Shorts, string? Continuation);

/// <summary>Generic scrolling page: heading, optional chips, optional Shorts shelf, video grid, infinite scroll.</summary>
public class VideoGridView : UserControl
{
    public string NavKey { get; init; } = "";
    protected readonly ObservableCollection<Video> Items = new();
    protected readonly ObservableCollection<Video> ShortsItems = new();
    protected readonly StackPanel Content_;
    protected readonly StackPanel HeaderArea = new();
    protected readonly ScrollViewer Scroller;
    private readonly TextBlock _status;
    private readonly StackPanel _shortsShelf;
    private string? _continuation;
    private Func<string, Task<FeedPage>>? _loadMore;
    private int _generation;

    public VideoGridView(string title)
    {
        _status = new TextBlock { Style = Ui.Res<Style>("SubText"), FontSize = 14, Margin = new Thickness(8, 20, 8, 20), HorizontalAlignment = HorizontalAlignment.Center };
        _shortsShelf = new StackPanel { Visibility = Visibility.Collapsed, Margin = new Thickness(0, 0, 0, 16) };
        var shortsTitle = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(8, 0, 0, 8) };
        shortsTitle.Children.Add(new TextBlock { Text = "", Style = Ui.Res<Style>("Icon"), Foreground = Ui.Res<System.Windows.Media.Brush>("AccentBrush"), Margin = new Thickness(0, 0, 8, 0) });
        shortsTitle.Children.Add(new TextBlock { Text = "Shorts", FontSize = 18, FontWeight = FontWeights.Bold });
        _shortsShelf.Children.Add(shortsTitle);
        _shortsShelf.Children.Add(new ScrollViewer
        {
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
            PanningMode = PanningMode.HorizontalOnly, Content = Ui.ShortsRow(ShortsItems)
        });

        Content_ = new StackPanel { Margin = new Thickness(16, 8, 16, 24) };
        if (!string.IsNullOrEmpty(title)) Content_.Children.Add(Ui.Heading(title));
        Content_.Children.Add(HeaderArea);
        Content_.Children.Add(_shortsShelf);
        Content_.Children.Add(Ui.VideoGrid(Items));
        Content_.Children.Add(_status);
        Scroller = new ScrollViewer { Content = Content_, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        Content = Scroller;
        Ui.OnNearBottom(Scroller, LoadMoreAsync);
    }

    /// <summary>Load (or reload) the page. Older in-flight loads are discarded.</summary>
    public async Task LoadAsync(Func<Task<FeedPage>> load, Func<string, Task<FeedPage>>? loadMore = null, string emptyText = "Không có video nào")
    {
        var gen = ++_generation;
        _loadMore = loadMore;
        _continuation = null;
        Items.Clear();
        ShortsItems.Clear();
        _shortsShelf.Visibility = Visibility.Collapsed;
        _status.Text = "Đang tải…";
        _status.Visibility = Visibility.Visible;
        FeedPage page;
        try { page = await load(); }
        catch (Exception e) { if (gen == _generation) _status.Text = "Lỗi: " + e.Message; return; }
        if (gen != _generation) return;
        Append(page);
        _status.Text = Items.Count == 0 && ShortsItems.Count == 0 ? emptyText : "";
        _status.Visibility = _status.Text.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void Append(FeedPage page)
    {
        var known = Items.Select(v => v.Id).Concat(ShortsItems.Select(v => v.Id)).ToHashSet();
        foreach (var v in page.Videos) if (known.Add(v.Id)) Items.Add(v);
        foreach (var v in page.Shorts) if (known.Add(v.Id)) ShortsItems.Add(v);
        _shortsShelf.Visibility = ShortsItems.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        _continuation = page.Continuation;
    }

    private async Task LoadMoreAsync()
    {
        if (_loadMore == null || string.IsNullOrEmpty(_continuation)) return;
        var gen = _generation;
        _status.Text = "Đang tải thêm…";
        _status.Visibility = Visibility.Visible;
        var page = await _loadMore(_continuation);
        if (gen != _generation) return;
        Append(page);
        _status.Visibility = Visibility.Collapsed;
    }

    /// <summary>Show a static, live-updating collection (history, bookmarks) instead of a loaded feed.</summary>
    protected void BindStatic(ObservableCollection<Video> source, string emptyText)
    {
        var grid = Content_.Children.OfType<ItemsControl>().First(ic => ReferenceEquals(ic.ItemsSource, Items));
        grid.ItemsSource = source;
        void Refresh()
        {
            _status.Text = source.Count == 0 ? emptyText : "";
            _status.Visibility = source.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        }
        source.CollectionChanged += (_, _) => Refresh();
        Refresh();
    }

    // MARK: - Factories

    public static VideoGridView SearchResults(string query)
    {
        var v = new VideoGridView($"Kết quả cho \"{query}\"");
        _ = v.LoadAsync(async () =>
        {
            var r = await InnerTubeService.Shared.SearchAsync(query);
            if (r.Channel != null) v.HeaderArea.Children.Add(ChannelBanner(r.Channel));
            return new FeedPage(r.Videos, r.Shorts, r.ContinuationToken);
        }, async token =>
        {
            var r = await InnerTubeService.Shared.SearchAsync(query, token);
            return new FeedPage(r.Videos, r.Shorts, r.ContinuationToken);
        }, "Không tìm thấy kết quả");
        return v;
    }

    private static FrameworkElement ChannelBanner(ChannelInfo ch)
    {
        var grid = new Grid { Margin = new Thickness(8, 0, 8, 16), Cursor = System.Windows.Input.Cursors.Hand };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        var avatar = new System.Windows.Shapes.Ellipse { Width = 72, Height = 72, Margin = new Thickness(0, 0, 16, 0) };
        if (Ui.Image(ch.AvatarUrl) is { } img) avatar.Fill = new System.Windows.Media.ImageBrush(img) { Stretch = System.Windows.Media.Stretch.UniformToFill };
        grid.Children.Add(avatar);
        var info = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        info.Children.Add(new TextBlock { Text = ch.Title, FontSize = 18, FontWeight = FontWeights.Bold });
        info.Children.Add(Ui.Sub(string.Join(" • ", new[] { ch.Handle, ch.SubscriberCount }.Where(s => !string.IsNullOrEmpty(s)))));
        Grid.SetColumn(info, 1);
        grid.Children.Add(info);
        grid.MouseLeftButtonUp += (_, _) => MainWindow.Instance.OpenChannel(ch.Id, ch);
        return grid;
    }

    public static VideoGridView Subscriptions()
    {
        var v = new VideoGridView("Kênh đăng ký") { NavKey = "subs" };
        var refresh = Ui.Pill("Làm mới", async (_, _) => await v.LoadAsync(Load, null, EmptySubs));
        var signIn = Ui.Pill("Đồng bộ từ tài khoản Google", (_, _) => MainWindow.Instance.StartGoogleSync());
        var bar = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(8, 0, 8, 12) };
        bar.Children.Add(refresh);
        bar.Children.Add(signIn);
        v.HeaderArea.Children.Add(bar);
        _ = v.LoadAsync(Load, null, EmptySubs);
        return v;

        static async Task<FeedPage> Load() => new(await FeedService.Shared.SubscriptionFeedAsync(), new(), null);
    }

    private const string EmptySubs = "Chưa đăng ký kênh nào. Mở một kênh và bấm \"Đăng ký\", hoặc đồng bộ từ tài khoản Google.";

    public static VideoGridView Bookmarks()
    {
        var v = new VideoGridView("Xem sau") { NavKey = "bookmarks" };
        v.BindStatic(AppStore.Shared.Bookmarks, "Chưa có video nào trong Xem sau. Nhấp chuột phải vào video để lưu.");
        return v;
    }

    public static VideoGridView History()
    {
        var v = new VideoGridView("Video đã xem") { NavKey = "history" };
        var bar = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(8, 0, 8, 12) };
        bar.Children.Add(Ui.Pill("Xoá lịch sử", (_, _) =>
        {
            if (MessageBox.Show("Xoá toàn bộ lịch sử xem?", "AuraTube", MessageBoxButton.YesNo) == MessageBoxResult.Yes)
                AppStore.Shared.ClearHistory();
        }));
        v.HeaderArea.Children.Add(bar);
        v.BindStatic(AppStore.Shared.History, "Chưa xem video nào.");
        return v;
    }
}

/// <summary>Home: category chips + Vietnam trending feed with a Shorts shelf.</summary>
public sealed class HomeView : VideoGridView
{
    public HomeView() : base("")
    {
        NavKey = "home";
        var chips = new WrapPanel { Margin = new Thickness(8, 0, 8, 16) };
        foreach (var cat in FeedService.Categories)
        {
            var rb = new RadioButton { Content = cat, Style = Ui.Res<Style>("ChipButton"), GroupName = "homeChips", IsChecked = cat == "Tất cả", Margin = new Thickness(0, 0, 8, 8) };
            rb.Checked += async (_, _) => await LoadCategory(cat);
            chips.Children.Add(rb);
        }
        HeaderArea.Children.Add(chips);
        _ = LoadCategory("Tất cả");
    }

    private Task LoadCategory(string cat) => cat == "Tất cả"
        ? LoadAsync(async () =>
        {
            var (videos, shorts) = await FeedService.Shared.TrendingAsync();
            return new FeedPage(videos, shorts, null);
        }, null, "Không tải được video. Kiểm tra kết nối mạng.")
        : LoadAsync(async () => new FeedPage(await FeedService.Shared.CategoryAsync(cat), new(), null));
}
