using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using AuraTube.Player;

namespace AuraTube.Views;

/// <summary>Always-on-top, borderless picture-in-picture window sharing the main player.</summary>
public sealed class MiniPlayerWindow : Window
{
    private static MiniPlayerWindow? _shared;
    public static bool IsOpen => _shared != null;

    private readonly PlayerSurface _surface = new() { CompactControls = true };

    private MiniPlayerWindow()
    {
        Title = "AuraTube Mini";
        Width = 480;
        Height = 270 + 36;
        Topmost = true;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.CanResizeWithGrip;
        ShowInTaskbar = false;
        Background = System.Windows.Media.Brushes.Black;
        var area = SystemParameters.WorkArea;
        Left = area.Right - Width - 24;
        Top = area.Bottom - Height - 24;

        var bar = new DockPanel { Height = 36, Background = Ui.Res<System.Windows.Media.Brush>("SurfaceBrush"), LastChildFill = true };
        Button B(string glyph, string tip, Action a)
        {
            var b = new Button { Content = glyph, ToolTip = tip, Style = Ui.Res<Style>("IconButton"), Width = 32, Height = 32, FontSize = 13 };
            b.Click += (_, _) => a();
            return b;
        }
        var right = new StackPanel { Orientation = Orientation.Horizontal };
        right.Children.Add(B("", "Phát/Tạm dừng", () => PlayerService.Shared.TogglePlay()));
        right.Children.Add(B("", "Video tiếp theo", () => MainWindow.Instance.PlayNext()));
        right.Children.Add(B("", "Quay lại cửa sổ chính", () => MainWindow.Instance.ReturnToWatch()));
        right.Children.Add(B("", "Đóng", () => { PlayerService.Shared.Stop(); CloseIfOpen(); }));
        DockPanel.SetDock(right, Dock.Right);
        bar.Children.Add(right);
        var title = new TextBlock { Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center, FontSize = 12, TextTrimming = TextTrimming.CharacterEllipsis };
        bar.Children.Add(title);
        bar.MouseLeftButtonDown += (_, e) => { if (e.ButtonState == MouseButtonState.Pressed) DragMove(); };

        var root = new DockPanel();
        DockPanel.SetDock(bar, Dock.Top);
        root.Children.Add(bar);
        root.Children.Add(_surface);
        Content = root;

        void Refresh() => title.Text = PlayerService.Shared.Current?.Title ?? "";
        PlayerService.Shared.StateChanged += Refresh;
        Closed += (_, _) => PlayerService.Shared.StateChanged -= Refresh;
        Refresh();
        Loaded += (_, _) => _surface.Activate();
    }

    public static void ShowShared()
    {
        if (_shared != null) { _shared._surface.Activate(); _shared.Activate(); return; }
        _shared = new MiniPlayerWindow();
        _shared.Show();
    }

    public static void CloseIfOpen()
    {
        var w = _shared;
        if (w == null) return;
        _shared = null;
        w._surface.Deactivate();
        w.Close();
    }

    protected override void OnClosed(EventArgs e)
    {
        if (ReferenceEquals(_shared, this)) { _shared = null; _surface.Deactivate(); }
        base.OnClosed(e);
    }
}
