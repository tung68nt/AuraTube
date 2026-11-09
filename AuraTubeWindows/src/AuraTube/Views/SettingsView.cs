using System.Windows;
using System.Windows.Controls;
using AuraTube.Services;

namespace AuraTube.Views;

public sealed class SettingsView : UserControl
{
    private readonly AppSettings _s = AppStore.Shared.Settings;

    public SettingsView()
    {
        var root = new StackPanel { Margin = new Thickness(24, 8, 24, 32), MaxWidth = 760, HorizontalAlignment = HorizontalAlignment.Left };
        root.Children.Add(Ui.Heading("Cài đặt"));

        // Playback
        root.Children.Add(Section("Phát video"));
        var quality = new ComboBox { Width = 260, HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 4, 0, 8) };
        var options = new (string Key, string Label)[]
        {
            ("auto", "Tự động theo tốc độ mạng"), ("2160", "2160p (4K)"), ("1440", "1440p (2K)"), ("1080", "1080p"), ("720", "720p"), ("480", "480p"), ("360", "360p")
        };
        foreach (var o in options) quality.Items.Add(new ComboBoxItem { Content = o.Label, Tag = o.Key, IsSelected = _s.PreferredQuality == o.Key });
        quality.SelectionChanged += (_, _) => { _s.PreferredQuality = (string)((ComboBoxItem)quality.SelectedItem).Tag; Save(); };
        root.Children.Add(Label("Chất lượng mặc định"));
        root.Children.Add(quality);
        root.Children.Add(Check("Cho phép 2K/4K khi mạng đủ nhanh (chế độ Tự động)", _s.PreferMaxQuality, v => _s.PreferMaxQuality = v));
        root.Children.Add(Check("Bỏ qua quảng cáo tài trợ trong video (SponsorBlock)", _s.SponsorBlockEnabled, v => _s.SponsorBlockEnabled = v));
        root.Children.Add(Check("Tự động phát video tiếp theo", _s.AutoplayNext, v => _s.AutoplayNext = v));

        var net = Ui.Sub("");
        void RenderNet() => net.Text = NetworkSpeedService.Shared.CurrentSpeedMbps > 0
            ? $"Tốc độ mạng: {NetworkSpeedService.Shared.CurrentSpeedMbps:0.0} Mbps ({NetworkSpeedService.Shared.TierLabel}), độ trễ {NetworkSpeedService.Shared.LatencyMs:0} ms → chất lượng tự động {NetworkSpeedService.Shared.RecommendedQuality(new(), _s.PreferMaxQuality)}p"
            : "Chưa đo tốc độ mạng.";
        RenderNet();
        NetworkSpeedService.Shared.Updated += RenderNet;
        Unloaded += (_, _) => NetworkSpeedService.Shared.Updated -= RenderNet;
        var netRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 6, 0, 0) };
        netRow.Children.Add(Ui.Pill("Đo lại tốc độ mạng", async (_, _) => { net.Text = "Đang đo…"; await NetworkSpeedService.Shared.MeasureAsync(true); RenderNet(); }));
        root.Children.Add(net);
        root.Children.Add(netRow);

        // Downloads
        root.Children.Add(Section("Tải xuống"));
        var folder = Ui.Sub(_s.DownloadFolder);
        root.Children.Add(Label("Thư mục lưu"));
        root.Children.Add(folder);
        var folderRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 6, 0, 0) };
        folderRow.Children.Add(Ui.Pill("Chọn thư mục…", (_, _) =>
        {
            var dlg = new Microsoft.Win32.OpenFolderDialog { InitialDirectory = _s.DownloadFolder, Title = "Chọn thư mục tải về" };
            if (dlg.ShowDialog() == true) { _s.DownloadFolder = dlg.FolderName; folder.Text = dlg.FolderName; Save(); }
        }));
        root.Children.Add(folderRow);
        root.Children.Add(Ui.Sub(DownloadManager.FfmpegDir() is { } ff ? $"ffmpeg: {ff}" : "Không tìm thấy ffmpeg (tải MP4 một luồng và M4A). Cài ffmpeg vào PATH để có MP3 và MP4 chất lượng cao."));

        // App
        root.Children.Add(Section("Ứng dụng"));
        root.Children.Add(Check("Thu nhỏ xuống khay hệ thống khi đóng cửa sổ", _s.MinimizeToTray, v => _s.MinimizeToTray = v));
        root.Children.Add(Check("Tự kiểm tra bản cập nhật khi mở ứng dụng", _s.AutoCheckUpdates, v => _s.AutoCheckUpdates = v));
        var appRow = new WrapPanel { Margin = new Thickness(0, 6, 0, 0) };
        appRow.Children.Add(Ui.Pill("Kiểm tra cập nhật", async (_, _) => await MainWindow.Instance.CheckUpdatesAsync(true)));
        appRow.Children.Add(Ui.Pill("Đồng bộ kênh từ Google", (_, _) => MainWindow.Instance.StartGoogleSync()));
        root.Children.Add(appRow);
        if (_s.LastGoogleSync is DateTime t) root.Children.Add(Ui.Sub($"Lần đồng bộ gần nhất: {t:dd/MM/yyyy HH:mm}"));

        // yt-dlp
        root.Children.Add(Section("yt-dlp"));
        var yt = Ui.Sub("Đang kiểm tra…");
        root.Children.Add(yt);
        _ = Task.Run(() => YtDlpBinary.Shared.Version()).ContinueWith(t =>
            Dispatcher.BeginInvoke(() => yt.Text = t.Result != null ? $"Phiên bản {t.Result} • {YtDlpBinary.Shared.ExistingPath}" : "Chưa cài yt-dlp (sẽ tự tải khi cần)."));
        var ytRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 6, 0, 0) };
        ytRow.Children.Add(Ui.Pill("Cập nhật yt-dlp ngay", async (_, _) =>
        {
            yt.Text = "Đang tải bản mới nhất…";
            try { await YtDlpBinary.Shared.InstallAsync(force: true); yt.Text = $"Phiên bản {await Task.Run(() => YtDlpBinary.Shared.Version())}"; }
            catch (Exception e) { yt.Text = "Lỗi: " + e.Message; }
        }));
        root.Children.Add(ytRow);

        // About
        root.Children.Add(Section("Giới thiệu"));
        root.Children.Add(Ui.Sub($"AuraTube cho Windows • phiên bản {UpdateService.CurrentVersion}\nXem YouTube không quảng cáo, phát bằng LibVLC và yt-dlp. Dữ liệu lưu tại {AppStore.DataDir}"));
        var about = new WrapPanel { Margin = new Thickness(0, 6, 0, 0) };
        about.Children.Add(Ui.Pill("Trang GitHub", (_, _) => Ui.OpenUrl("https://github.com/tung68nt/AuraTube")));
        about.Children.Add(Ui.Pill("Xoá lịch sử xem", (_, _) => AppStore.Shared.ClearHistory()));
        root.Children.Add(about);

        Content = new ScrollViewer { Content = root, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    private void Save() => AppStore.Shared.SaveSettings();

    private static TextBlock Section(string text) => new() { Text = text, FontSize = 17, FontWeight = FontWeights.Bold, Margin = new Thickness(0, 22, 0, 6) };
    private static TextBlock Label(string text) => new() { Text = text, FontSize = 13, Margin = new Thickness(0, 4, 0, 0) };

    private CheckBox Check(string text, bool value, Action<bool> set)
    {
        var c = new CheckBox { Content = text, IsChecked = value };
        c.Checked += (_, _) => { set(true); Save(); };
        c.Unchecked += (_, _) => { set(false); Save(); };
        return c;
    }
}
