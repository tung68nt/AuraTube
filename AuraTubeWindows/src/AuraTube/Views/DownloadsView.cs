using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using AuraTube.Models;
using AuraTube.Services;

namespace AuraTube.Views;

public sealed class DownloadsView : UserControl
{
    public DownloadsView()
    {
        var root = new StackPanel { Margin = new Thickness(24, 8, 24, 24) };
        root.Children.Add(Ui.Heading("Tệp đã tải về"));
        var bar = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(8, 0, 8, 6) };
        bar.Children.Add(Ui.Pill("Mở thư mục tải về", (_, _) => OpenFolder(DownloadManager.Shared.DownloadDir)));
        bar.Children.Add(Ui.Pill("Xoá mục đã xong", (_, _) =>
        {
            foreach (var d in DownloadManager.Shared.Downloads.Where(d => !d.IsActive).ToList()) DownloadManager.Shared.Downloads.Remove(d);
        }));
        root.Children.Add(bar);
        root.Children.Add(new TextBlock
        {
            Text = DownloadManager.FfmpegDir() == null
                ? "Không tìm thấy ffmpeg: video tải về dạng MP4 một luồng (tối đa ~720p) và âm thanh dạng M4A."
                : "Đã tìm thấy ffmpeg: hỗ trợ MP4 chất lượng cao và MP3.",
            Style = Ui.Res<Style>("SubText"), Margin = new Thickness(8, 0, 8, 12), TextWrapping = TextWrapping.Wrap
        });

        var empty = Ui.Sub("Chưa có tệp nào. Bấm \"Tải xuống\" ở trang xem video.");
        empty.Margin = new Thickness(8, 16, 8, 0);
        root.Children.Add(empty);
        var list = new ItemsControl { ItemsSource = DownloadManager.Shared.Downloads, ItemTemplate = BuildTemplate() };
        root.Children.Add(list);
        void Refresh() => empty.Visibility = DownloadManager.Shared.Downloads.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        DownloadManager.Shared.Downloads.CollectionChanged += (_, _) => Refresh();
        Refresh();
        Content = new ScrollViewer { Content = root, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    private static void OpenFolder(string dir)
    {
        try { Process.Start(new ProcessStartInfo("explorer.exe", $"\"{dir}\"") { UseShellExecute = true }); } catch { }
    }

    private static DataTemplate BuildTemplate()
    {
        // Built in code to keep it next to the actions it wires up.
        var t = new DataTemplate(typeof(DownloadItem));
        var border = new FrameworkElementFactory(typeof(Border));
        border.SetValue(Border.BackgroundProperty, Ui.Res<System.Windows.Media.Brush>("SurfaceBrush"));
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(12));
        border.SetValue(Border.PaddingProperty, new Thickness(12));
        border.SetValue(Border.MarginProperty, new Thickness(8, 0, 8, 10));
        border.SetValue(FrameworkElement.TagProperty, new Binding());
        border.AddHandler(UIElement.MouseRightButtonUpEvent, new System.Windows.Input.MouseButtonEventHandler((s, _) =>
        {
            if ((s as FrameworkElement)?.Tag is not DownloadItem d) return;
            var menu = new ContextMenu();
            void Add(string h, Action a) { var mi = new MenuItem { Header = h }; mi.Click += (_, _) => a(); menu.Items.Add(mi); }
            if (d.IsDone && d.FilePath != null)
            {
                Add("Mở tệp", () => Ui.OpenUrl(d.FilePath));
                Add("Hiện trong thư mục", () => { try { Process.Start("explorer.exe", $"/select,\"{d.FilePath}\""); } catch { } });
            }
            if (d.IsActive) Add("Huỷ tải", () => DownloadManager.Shared.Cancel(d));
            Add("Xoá khỏi danh sách", () => DownloadManager.Shared.Remove(d));
            Add("Phát video gốc", () => MainWindow.Instance.OpenVideo(d.Video));
            menu.IsOpen = true;
        }));

        var stack = new FrameworkElementFactory(typeof(StackPanel));
        var title = new FrameworkElementFactory(typeof(TextBlock));
        title.SetBinding(TextBlock.TextProperty, new Binding("Video.Title"));
        title.SetValue(TextBlock.FontWeightProperty, FontWeights.SemiBold);
        title.SetValue(TextBlock.TextTrimmingProperty, TextTrimming.CharacterEllipsis);
        stack.AppendChild(title);
        var kind = new FrameworkElementFactory(typeof(TextBlock));
        kind.SetBinding(TextBlock.TextProperty, new MultiBinding { StringFormat = "{0} • {1}", Bindings = { new Binding("Kind"), new Binding("Status") } });
        kind.SetValue(TextBlock.StyleProperty, Ui.Res<Style>("SubText"));
        kind.SetValue(FrameworkElement.MarginProperty, new Thickness(0, 4, 0, 6));
        stack.AppendChild(kind);
        var bar = new FrameworkElementFactory(typeof(ProgressBar));
        bar.SetValue(RangeBase.MaximumProperty, 1.0);
        bar.SetBinding(RangeBase.ValueProperty, new Binding("Progress"));
        bar.SetValue(FrameworkElement.HeightProperty, 4.0);
        bar.SetValue(Control.ForegroundProperty, Ui.Res<System.Windows.Media.Brush>("AccentBrush"));
        bar.SetValue(Control.BackgroundProperty, Ui.Res<System.Windows.Media.Brush>("Surface2Brush"));
        bar.SetValue(Control.BorderThicknessProperty, new Thickness(0));
        stack.AppendChild(bar);
        border.AppendChild(stack);
        t.VisualTree = border;
        return t;
    }
}

/// <summary>Pick MP4 quality or MP3 and start a download.</summary>
public sealed class DownloadDialog : Window
{
    public static void Show(Video v, List<int>? heights = null)
    {
        var d = new DownloadDialog(v, heights) { Owner = MainWindow.Instance };
        d.ShowDialog();
    }

    private DownloadDialog(Video v, List<int>? heights)
    {
        Title = "Tải xuống";
        Width = 420;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = Ui.Res<System.Windows.Media.Brush>("BgBrush");
        var root = new StackPanel { Margin = new Thickness(20) };
        root.Children.Add(new TextBlock { Text = v.Title, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 12) });
        var hasFf = DownloadManager.FfmpegDir() != null;
        var options = (heights is { Count: > 0 } ? heights : new List<int> { 2160, 1440, 1080, 720, 480, 360 })
            .Where(h => h >= 360).Distinct().OrderByDescending(h => h).ToList();
        var wrap = new WrapPanel();
        foreach (var h in options)
        {
            wrap.Children.Add(Ui.Pill($"MP4 {h}p", (_, _) => Start(v, false, h.ToString()), accent: h.ToString() == AppStore.Shared.Settings.DownloadQuality));
            ((FrameworkElement)wrap.Children[^1]).Margin = new Thickness(0, 0, 8, 8);
        }
        root.Children.Add(wrap);
        var audio = Ui.Pill(hasFf ? "Âm thanh MP3" : "Âm thanh M4A", (_, _) => Start(v, true, "audio"));
        audio.HorizontalAlignment = HorizontalAlignment.Left;
        root.Children.Add(audio);
        if (!hasFf)
            root.Children.Add(new TextBlock
            {
                Text = "Máy chưa có ffmpeg nên video sẽ tải dạng MP4 một luồng (chất lượng có thể thấp hơn) và âm thanh dạng M4A.",
                Style = Ui.Res<Style>("SubText"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 0)
            });
        root.Children.Add(new TextBlock { Text = "Lưu vào: " + AppStore.Shared.Settings.DownloadFolder, Style = Ui.Res<Style>("SubText"), Margin = new Thickness(0, 12, 0, 0) });
        Content = root;
    }

    private void Start(Video v, bool audio, string q)
    {
        DownloadManager.Shared.Start(v, audio, q);
        MainWindow.Instance.ShowToast("Đã bắt đầu tải: " + v.Title);
        Close();
    }
}
