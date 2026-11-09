using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using AuraTube.Models;
using AuraTube.Services;

namespace AuraTube.Views;

/// <summary>Channel page: banner, avatar, subscribe button and the channel's videos (InnerTube /browse).</summary>
public sealed class ChannelView : VideoGridView
{
    private readonly Border _banner = new() { Height = 170, CornerRadius = new CornerRadius(16), Margin = new Thickness(8, 0, 8, 16), Background = Ui.Res<Brush>("SurfaceBrush"), Visibility = Visibility.Collapsed };
    private readonly Ellipse _avatar = new() { Width = 96, Height = 96, Margin = new Thickness(0, 0, 20, 0), Fill = Ui.Res<Brush>("Surface2Brush") };
    private readonly TextBlock _title = new() { FontSize = 26, FontWeight = FontWeights.Bold, TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly TextBlock _meta = Ui.Sub("");
    private readonly TextBlock _desc = Ui.Sub("");
    private readonly Button _subscribe;
    private ChannelInfo? _channel;

    public ChannelView(string idOrQuery, ChannelInfo? fallback) : base("")
    {
        _subscribe = Ui.Pill("Đăng ký", (_, _) => ToggleSubscribe(), accent: true);
        _desc.MaxHeight = 40;
        _desc.TextTrimming = TextTrimming.CharacterEllipsis;
        _desc.Margin = new Thickness(0, 6, 0, 10);

        HeaderArea.Children.Add(_banner);
        var row = new Grid { Margin = new Thickness(8, 0, 8, 20) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition());
        row.Children.Add(_avatar);
        var info = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        info.Children.Add(_title);
        info.Children.Add(_meta);
        info.Children.Add(_desc);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal };
        buttons.Children.Add(_subscribe);
        buttons.Children.Add(Ui.Pill("Mở trên YouTube", (_, _) =>
            Ui.OpenUrl(_channel?.Id.StartsWith("UC") == true ? $"https://www.youtube.com/channel/{_channel.Id}" : $"https://www.youtube.com/results?search_query={Uri.EscapeDataString(idOrQuery)}")));
        info.Children.Add(buttons);
        Grid.SetColumn(info, 1);
        row.Children.Add(info);
        HeaderArea.Children.Add(row);
        HeaderArea.Children.Add(new TextBlock { Text = "Video", FontSize = 18, FontWeight = FontWeights.Bold, Margin = new Thickness(8, 0, 8, 8) });

        if (fallback != null) Apply(fallback, null);
        else _title.Text = idOrQuery;

        _ = LoadAsync(async () =>
        {
            var d = await InnerTubeService.Shared.ChannelAsync(idOrQuery, fallback);
            if (d == null) return new FeedPage(new(), new(), null);
            Apply(d.Channel, d.BannerUrl);
            return new FeedPage(d.Videos, new(), d.ContinuationToken);
        }, async token =>
        {
            var d = await InnerTubeService.Shared.ChannelAsync(_channel?.Id ?? idOrQuery, _channel, token);
            return new FeedPage(d?.Videos ?? new(), new(), d?.ContinuationToken);
        }, "Kênh này chưa có video");
    }

    private void Apply(ChannelInfo ch, string? banner)
    {
        _channel = ch;
        _title.Text = ch.Title;
        _meta.Text = string.Join(" • ", new[] { ch.Handle, ch.SubscriberCount }.Where(s => !string.IsNullOrEmpty(s)));
        _desc.Text = ch.Description ?? "";
        if (Ui.Image(ch.AvatarUrl) is { } img) _avatar.Fill = new ImageBrush(img) { Stretch = Stretch.UniformToFill };
        if (Ui.Image(banner) is { } b)
        {
            _banner.Background = new ImageBrush(b) { Stretch = Stretch.UniformToFill };
            _banner.Visibility = Visibility.Visible;
        }
        UpdateSubscribe();
    }

    private void UpdateSubscribe()
    {
        var subbed = _channel != null && (AppStore.Shared.IsSubscribed(_channel.Id) || AppStore.Shared.IsSubscribed(_channel.Title));
        _subscribe.Content = subbed ? "Đã đăng ký" : "Đăng ký";
        _subscribe.Style = Ui.Res<Style>(subbed ? "PillButton" : "AccentButton");
    }

    private void ToggleSubscribe()
    {
        if (_channel == null) return;
        if (AppStore.Shared.IsSubscribed(_channel.Id) || AppStore.Shared.IsSubscribed(_channel.Title))
        {
            AppStore.Shared.Unsubscribe(_channel.Id);
            AppStore.Shared.Unsubscribe(_channel.Title);
        }
        else
            AppStore.Shared.Subscribe(new SubscribedChannel { Id = _channel.Id, Title = _channel.Title, Handle = _channel.Handle, AvatarUrl = _channel.AvatarUrl });
        UpdateSubscribe();
    }
}
