using System.Windows;
using System.Windows.Controls;
using AuraTube.Models;
using AuraTube.Services;

namespace AuraTube.Views;

public sealed class InputDialog : Window
{
    private readonly TextBox _box;
    public string Value => _box.Text;

    public InputDialog(string title, string prompt)
    {
        Title = title;
        Width = 520;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = Ui.Res<System.Windows.Media.Brush>("BgBrush");
        var root = new StackPanel { Margin = new Thickness(20) };
        root.Children.Add(new TextBlock { Text = prompt, Margin = new Thickness(0, 0, 0, 8) });
        _box = new TextBox { FontSize = 14, Padding = new Thickness(6), Background = Ui.Res<System.Windows.Media.Brush>("SurfaceBrush"), Foreground = Ui.Res<System.Windows.Media.Brush>("TextBrush"), CaretBrush = Ui.Res<System.Windows.Media.Brush>("TextBrush") };
        try { if (Clipboard.ContainsText() && Clipboard.GetText().Contains("youtu")) _box.Text = Clipboard.GetText().Trim(); } catch { }
        root.Children.Add(_box);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 14, 0, 0) };
        var ok = Ui.Pill("Mở", (_, _) => { DialogResult = true; }, accent: true);
        ok.IsDefault = true;
        var cancel = Ui.Pill("Huỷ", (_, _) => { DialogResult = false; });
        cancel.IsCancel = true;
        buttons.Children.Add(cancel);
        buttons.Children.Add(ok);
        root.Children.Add(buttons);
        Content = root;
        Loaded += (_, _) => { _box.Focus(); _box.SelectAll(); };
    }
}

/// <summary>Shows release notes and downloads/installs the Windows build.</summary>
public sealed class UpdateWindow : Window
{
    public UpdateWindow(AppUpdateInfo info)
    {
        Title = "Cập nhật AuraTube";
        Width = 520;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = Ui.Res<System.Windows.Media.Brush>("BgBrush");

        var root = new StackPanel { Margin = new Thickness(24) };
        root.Children.Add(new TextBlock { Text = info.Title.Length > 0 ? info.Title : $"AuraTube v{info.Version}", FontSize = 20, FontWeight = FontWeights.Bold, TextWrapping = TextWrapping.Wrap });
        root.Children.Add(Ui.Sub($"Phiên bản hiện tại: {UpdateService.CurrentVersion} → mới: {info.Version}" + (info.FileSize != null ? $" • {info.FileSize}" : "")));
        root.Children.Add(new Border
        {
            Background = Ui.Res<System.Windows.Media.Brush>("SurfaceBrush"), CornerRadius = new CornerRadius(12), Padding = new Thickness(14), Margin = new Thickness(0, 14, 0, 14),
            Child = new ScrollViewer { MaxHeight = 260, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = new TextBlock { Text = info.ReleaseNotes, TextWrapping = TextWrapping.Wrap } }
        });
        var progress = new ProgressBar { Height = 6, Maximum = 1, Visibility = Visibility.Collapsed, Margin = new Thickness(0, 0, 0, 12), Foreground = Ui.Res<System.Windows.Media.Brush>("AccentBrush") };
        root.Children.Add(progress);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var cts = new CancellationTokenSource();
        var skip = Ui.Pill("Bỏ qua bản này", (_, _) =>
        {
            AppStore.Shared.Settings.SkippedUpdateVersion = info.Version;
            AppStore.Shared.SaveSettings();
            Close();
        });
        var later = Ui.Pill("Để sau", (_, _) => { cts.Cancel(); Close(); });
        Button install = null!;
        install = Ui.Pill(UpdateService.IsPortable || string.IsNullOrEmpty(info.WindowsDownloadUrl) ? "Mở trang tải về" : "Cập nhật ngay", async (_, _) =>
        {
            install.IsEnabled = skip.IsEnabled = false;
            progress.Visibility = Visibility.Visible;
            try
            {
                await UpdateService.Shared.DownloadAndInstallAsync(info, new Progress<double>(v => progress.Value = v), cts.Token);
                Close();
            }
            catch (Exception e)
            {
                if (!cts.IsCancellationRequested) MessageBox.Show(this, "Tải bản cập nhật thất bại: " + e.Message, "AuraTube");
                install.IsEnabled = skip.IsEnabled = true;
            }
        }, accent: true);
        buttons.Children.Add(skip);
        buttons.Children.Add(later);
        buttons.Children.Add(install);
        root.Children.Add(buttons);
        Content = root;
        Closed += (_, _) => cts.Cancel();
    }
}
