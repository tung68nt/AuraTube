using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using AuraTube.Models;
using AuraTube.Services;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace AuraTube.Views;

/// <summary>
/// Google sign-in inside WebView2, then reads youtube.com/feed/channels to import the account's
/// subscriptions into the local subscription list. Cookies stay in the app's WebView2 profile only.
/// </summary>
public sealed class SignInWindow : Window
{
    private const string ChannelsUrl = "https://www.youtube.com/feed/channels";
    private readonly WebView2 _web = new();
    private readonly TextBlock _status = new() { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 0, 0) };
    private readonly Button _sync;
    private bool _syncing;
    public int ImportedCount { get; private set; }

    public static string ProfileDir => Path.Combine(AppStore.DataDir, "WebView2");

    public SignInWindow()
    {
        Title = "Đăng nhập Google — đồng bộ kênh đăng ký";
        Width = 980;
        Height = 760;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = Ui.Res<System.Windows.Media.Brush>("BgBrush");

        _sync = Ui.Pill("Đồng bộ kênh đăng ký", async (_, _) => await SyncAsync(), accent: true);
        var signOut = Ui.Pill("Đăng xuất", async (_, _) => await SignOutAsync());
        var bar = new DockPanel { Margin = new Thickness(12), LastChildFill = true };
        var left = new StackPanel { Orientation = Orientation.Horizontal };
        left.Children.Add(_sync);
        left.Children.Add(signOut);
        DockPanel.SetDock(left, Dock.Left);
        bar.Children.Add(left);
        bar.Children.Add(_status);

        var root = new DockPanel();
        DockPanel.SetDock(bar, Dock.Top);
        root.Children.Add(bar);
        root.Children.Add(_web);
        Content = root;
        Loaded += async (_, _) => await InitAsync();
    }

    private async Task InitAsync()
    {
        try
        {
            var env = await CoreWebView2Environment.CreateAsync(null, ProfileDir);
            await _web.EnsureCoreWebView2Async(env);
            _web.CoreWebView2.NavigationCompleted += async (_, _) =>
            {
                var url = _web.Source?.ToString() ?? "";
                if (url.StartsWith(ChannelsUrl) && !_syncing) await SyncAsync();
            };
            _status.Text = "Đăng nhập tài khoản Google của bạn. Ứng dụng chỉ đọc danh sách kênh đăng ký.";
            _web.Source = new Uri("https://accounts.google.com/ServiceLogin?service=youtube&continue=" + Uri.EscapeDataString(ChannelsUrl));
        }
        catch (Exception e)
        {
            _status.Text = "Không khởi động được WebView2: " + e.Message + ". Hãy cài Microsoft Edge WebView2 Runtime.";
            _sync.IsEnabled = false;
        }
    }

    private async Task SignOutAsync()
    {
        if (_web.CoreWebView2 == null) return;
        _web.CoreWebView2.CookieManager.DeleteAllCookies();
        _status.Text = "Đã đăng xuất.";
        _web.Source = new Uri("https://accounts.google.com/ServiceLogin?service=youtube&continue=" + Uri.EscapeDataString(ChannelsUrl));
        await Task.CompletedTask;
    }

    private const string ScrapeScript = """
        (async () => {
          const sleep = ms => new Promise(r => setTimeout(r, ms));
          let last = -1;
          for (let i = 0; i < 25; i++) {
            const n = document.querySelectorAll('ytd-channel-renderer').length;
            if (n === last && i > 2) break;
            last = n;
            window.scrollTo(0, document.documentElement.scrollHeight);
            await sleep(900);
          }
          const out = [];
          document.querySelectorAll('ytd-channel-renderer').forEach(el => {
            const a = el.querySelector('a#main-link') || el.querySelector('a');
            const href = a ? a.getAttribute('href') || '' : '';
            const title = (el.querySelector('#channel-title #text, #text.ytd-channel-name') || {}).textContent || '';
            const img = el.querySelector('img');
            const handle = (el.querySelector('#subscribers') || {}).textContent || '';
            out.push({ href, title: title.trim(), avatar: img ? img.src : '', handle: handle.trim() });
          });
          const signedIn = !!document.querySelector('ytd-topbar-menu-button-renderer img#img, #avatar-btn');
          return JSON.stringify({ signedIn, items: out, initial: out.length ? null : JSON.stringify(window.ytInitialData || {}) });
        })()
        """;

    private async Task SyncAsync()
    {
        if (_web.CoreWebView2 == null || _syncing) return;
        _syncing = true;
        _sync.IsEnabled = false;
        try
        {
            if (!(_web.Source?.ToString() ?? "").StartsWith(ChannelsUrl))
            {
                _web.Source = new Uri(ChannelsUrl);
                return; // NavigationCompleted calls back in once the page is there
            }
            _status.Text = "Đang đọc danh sách kênh đăng ký…";
            await Task.Delay(1500);
            // ExecuteScriptAsync does not await promises; poll a global the script fills in.
            await _web.CoreWebView2.ExecuteScriptAsync("window.__auraSync = null; (" + ScrapeScript + ").then(r => window.__auraSync = r);");
            string? payload = null;
            for (var i = 0; i < 60 && payload == null; i++)
            {
                await Task.Delay(1000);
                var r = await _web.CoreWebView2.ExecuteScriptAsync("window.__auraSync");
                if (r != "null") payload = JsonSerializer.Deserialize<string>(r);
            }
            if (payload == null) { _status.Text = "Hết thời gian chờ. Thử lại."; return; }

            var root = JsonNode.Parse(payload)!;
            var channels = new List<SubscribedChannel>();
            foreach (var it in (root["items"] as JsonArray) ?? new JsonArray())
            {
                var href = InnerTubeService.Str(it?["href"]);
                var title = InnerTubeService.Str(it?["title"]);
                if (title.Length == 0) continue;
                string? id = null, handle = null;
                if (href.StartsWith("/channel/")) id = href["/channel/".Length..];
                else if (href.StartsWith("/@")) handle = href[1..];
                var hText = InnerTubeService.Str(it?["handle"]);
                if (handle == null && hText.StartsWith('@')) handle = hText;
                channels.Add(new SubscribedChannel { Title = title, Id = id ?? handle, Handle = handle, AvatarUrl = InnerTubeService.Str(it?["avatar"]) });
            }
            if (channels.Count == 0 && InnerTubeService.Str(root["initial"]) is { Length: > 2 } initial && JsonNode.Parse(initial) is JsonNode data)
            {
                InnerTubeService.Walk(data, o =>
                {
                    if (o["channelRenderer"] is JsonObject cr)
                    {
                        var sub = InnerTubeService.Text(cr["subscriberCountText"]);
                        channels.Add(new SubscribedChannel
                        {
                            Id = InnerTubeService.Str(cr["channelId"]),
                            Title = InnerTubeService.Text(cr["title"]),
                            Handle = sub.StartsWith('@') ? sub : null,
                            AvatarUrl = InnerTubeService.FixUrl(InnerTubeService.Str((cr["thumbnail"]?["thumbnails"] as JsonArray)?.LastOrDefault()?["url"]))
                        });
                        return false;
                    }
                    return true;
                });
            }
            if (channels.Count == 0)
            {
                _status.Text = root["signedIn"]?.GetValue<bool>() == true
                    ? "Tài khoản chưa đăng ký kênh nào."
                    : "Bạn chưa đăng nhập. Hãy đăng nhập rồi bấm \"Đồng bộ kênh đăng ký\".";
                return;
            }
            var added = 0;
            foreach (var c in channels)
            {
                if (AppStore.Shared.IsSubscribed(c.Id ?? c.Title) || AppStore.Shared.IsSubscribed(c.Title)) continue;
                AppStore.Shared.Subscriptions.Add(c);
                added++;
            }
            AppStore.Shared.SaveSubscriptions();
            AppStore.Shared.Settings.LastGoogleSync = DateTime.Now;
            AppStore.Shared.SaveSettings();
            ImportedCount = channels.Count;
            _status.Text = $"Đã đồng bộ {channels.Count} kênh ({added} kênh mới). Có thể đóng cửa sổ này.";
        }
        catch (Exception e) { _status.Text = "Lỗi đồng bộ: " + e.Message; }
        finally
        {
            _syncing = false;
            _sync.IsEnabled = true;
        }
    }
}
