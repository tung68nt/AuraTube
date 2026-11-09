using AuraTube.Player;
using WinForms = System.Windows.Forms;

namespace AuraTube.Views;

/// <summary>Notification-area icon with media controls (play/pause, next, mini player) and quit.</summary>
public sealed class TrayIcon : IDisposable
{
    private readonly WinForms.NotifyIcon _icon;
    private readonly WinForms.ToolStripMenuItem _now = new() { Enabled = false };
    private readonly WinForms.ToolStripMenuItem _play;
    private bool _hinted;

    public TrayIcon(MainWindow main)
    {
        var iconStream = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/Assets/AuraTube.ico"))?.Stream;
        _icon = new WinForms.NotifyIcon
        {
            Icon = iconStream != null ? new System.Drawing.Icon(iconStream) : System.Drawing.SystemIcons.Application,
            Text = "AuraTube",
            Visible = true
        };
        var menu = new WinForms.ContextMenuStrip();
        menu.Items.Add(_now);
        menu.Items.Add(new WinForms.ToolStripSeparator());
        _play = new WinForms.ToolStripMenuItem("Phát / Tạm dừng", null, (_, _) => PlayerService.Shared.TogglePlay());
        menu.Items.Add(_play);
        menu.Items.Add(new WinForms.ToolStripMenuItem("Tua lại 10 giây", null, (_, _) => PlayerService.Shared.SeekBy(-10)));
        menu.Items.Add(new WinForms.ToolStripMenuItem("Tua tới 10 giây", null, (_, _) => PlayerService.Shared.SeekBy(10)));
        menu.Items.Add(new WinForms.ToolStripMenuItem("Video tiếp theo", null, (_, _) => main.PlayNext()));
        menu.Items.Add(new WinForms.ToolStripMenuItem("Trình phát mini", null, (_, _) => main.OpenMiniPlayer()));
        menu.Items.Add(new WinForms.ToolStripSeparator());
        menu.Items.Add(new WinForms.ToolStripMenuItem("Mở AuraTube", null, (_, _) => main.ShowAndActivate()));
        menu.Items.Add(new WinForms.ToolStripMenuItem("Thoát", null, (_, _) => main.ExitApp()));
        menu.Opening += (_, _) =>
        {
            var cur = PlayerService.Shared.Current;
            _now.Text = cur == null ? "Không có video đang phát" : Trim(cur.Title, 60);
            _play.Text = PlayerService.Shared.IsPlaying ? "Tạm dừng" : "Phát";
        };
        _icon.ContextMenuStrip = menu;
        _icon.MouseClick += (_, e) => { if (e.Button == WinForms.MouseButtons.Left) main.ShowAndActivate(); };

        PlayerService.Shared.StateChanged += () =>
        {
            var cur = PlayerService.Shared.Current;
            _icon.Text = Trim(cur == null ? "AuraTube" : "AuraTube — " + cur.Title, 63);
        };
    }

    private static string Trim(string s, int n) => s.Length <= n ? s : s[..(n - 1)] + "…";

    public void ShowHint()
    {
        if (_hinted) return;
        _hinted = true;
        _icon.ShowBalloonTip(3000, "AuraTube vẫn đang chạy", "Nhấp vào biểu tượng để mở lại. Chọn \"Thoát\" trong menu để đóng hẳn.", WinForms.ToolTipIcon.Info);
    }

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
    }
}
