using System.Collections;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using AuraTube.Models;
using AuraTube.Services;

namespace AuraTube.Views;

/// <summary>Small helpers for building the code-behind views consistently.</summary>
public static class Ui
{
    public static T Res<T>(string key) => (T)Application.Current.Resources[key];

    public static TextBlock Heading(string text, double size = 22) => new()
    {
        Text = text, FontSize = size, FontWeight = FontWeights.Bold, Margin = new Thickness(8, 4, 8, 12), TextTrimming = TextTrimming.CharacterEllipsis
    };

    public static TextBlock Sub(string text) => new() { Text = text, Style = Res<Style>("SubText"), TextWrapping = TextWrapping.Wrap };

    public static Button Pill(string text, RoutedEventHandler onClick, bool accent = false)
    {
        var b = new Button { Content = text, Style = Res<Style>(accent ? "AccentButton" : "PillButton"), Margin = new Thickness(0, 0, 8, 0) };
        b.Click += onClick;
        return b;
    }

    /// <summary>Wrap grid of video cards bound to the given collection.</summary>
    public static ItemsControl VideoGrid(IEnumerable source)
    {
        var ic = new ItemsControl
        {
            ItemsSource = source,
            ItemTemplate = Res<DataTemplate>("VideoCard"),
            ItemsPanel = new ItemsPanelTemplate(new FrameworkElementFactory(typeof(WrapPanel))),
        };
        Wire(ic);
        return ic;
    }

    public static ItemsControl ShortsRow(IEnumerable source)
    {
        var panel = new FrameworkElementFactory(typeof(StackPanel));
        panel.SetValue(StackPanel.OrientationProperty, Orientation.Horizontal);
        var ic = new ItemsControl { ItemsSource = source, ItemTemplate = Res<DataTemplate>("ShortCard"), ItemsPanel = new ItemsPanelTemplate(panel) };
        Wire(ic);
        return ic;
    }

    public static ItemsControl VideoRows(IEnumerable source)
    {
        var ic = new ItemsControl { ItemsSource = source, ItemTemplate = Res<DataTemplate>("VideoRow") };
        Wire(ic);
        return ic;
    }

    public static Video? VideoFrom(object? source)
    {
        var d = source as DependencyObject;
        while (d != null)
        {
            if (d is FrameworkElement { Tag: Video v }) return v;
            d = d is Visual ? VisualTreeHelper.GetParent(d) : LogicalTreeHelper.GetParent(d);
        }
        return null;
    }

    /// <summary>Left click opens the video; right click shows the context menu.</summary>
    public static void Wire(ItemsControl ic)
    {
        Point? down = null;
        ic.PreviewMouseLeftButtonDown += (_, e) => down = e.GetPosition(ic);
        ic.PreviewMouseLeftButtonUp += (_, e) =>
        {
            if (down is not Point p || (e.GetPosition(ic) - p).Length > 6) return;
            if (VideoFrom(e.OriginalSource) is Video v) { e.Handled = true; MainWindow.Instance.OpenVideo(v); }
        };
        ic.PreviewMouseRightButtonUp += (_, e) =>
        {
            if (VideoFrom(e.OriginalSource) is not Video v) return;
            e.Handled = true;
            var menu = VideoMenu(v);
            menu.PlacementTarget = ic;
            menu.IsOpen = true;
        };
    }

    public static ContextMenu VideoMenu(Video v)
    {
        var menu = new ContextMenu();
        void Add(string header, Action a)
        {
            var mi = new MenuItem { Header = header };
            mi.Click += (_, _) => a();
            menu.Items.Add(mi);
        }
        Add("Phát", () => MainWindow.Instance.OpenVideo(v));
        Add(AppStore.Shared.IsBookmarked(v.Id) ? "Bỏ khỏi Xem sau" : "Lưu vào Xem sau", () =>
            MainWindow.Instance.ShowToast(AppStore.Shared.ToggleBookmark(v) ? "Đã lưu vào Xem sau" : "Đã bỏ khỏi Xem sau"));
        Add("Tải xuống…", () => DownloadDialog.Show(v));
        if (!string.IsNullOrEmpty(v.Uploader) && v.Uploader != "YouTube")
            Add($"Mở kênh {v.Uploader}", () => MainWindow.Instance.OpenChannel(v.UploaderId ?? v.Uploader));
        Add("Sao chép link", () => { try { Clipboard.SetText(v.WatchUrl); } catch { } });
        Add("Mở trên trình duyệt", () => OpenUrl(v.WatchUrl));
        return menu;
    }

    public static void OpenUrl(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { }
    }

    /// <summary>Calls <paramref name="onEnd"/> when a ScrollViewer gets near the bottom.</summary>
    public static void OnNearBottom(ScrollViewer sv, Func<Task> onEnd)
    {
        var busy = false;
        sv.ScrollChanged += async (_, _) =>
        {
            if (busy || sv.ScrollableHeight <= 0 || sv.VerticalOffset < sv.ScrollableHeight - 600) return;
            busy = true;
            try { await onEnd(); } finally { busy = false; }
        };
    }

    public static ImageSource? Image(string? url)
    {
        if (string.IsNullOrWhiteSpace(url)) return null;
        try { return new System.Windows.Media.Imaging.BitmapImage(new Uri(url)); } catch { return null; }
    }
}
