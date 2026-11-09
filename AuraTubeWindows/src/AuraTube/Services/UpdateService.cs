using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text.Json;
using AuraTube.Models;

namespace AuraTube.Services;

/// <summary>
/// Reads version-windows.json (same shape as the Mac version.json, with windowsDownloadUrl) so the
/// Mac updater is untouched. Downloads the installer and runs it silently, then exits.
/// </summary>
public sealed class UpdateService
{
    public static UpdateService Shared { get; } = new();

    public const string ManifestUrl = "https://raw.githubusercontent.com/tung68nt/AuraTube/main/version-windows.json";
    public const string ReleasesPage = "https://github.com/tung68nt/AuraTube/releases";

    public static string CurrentVersion
    {
        get
        {
            var v = Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "0.0.0";
            var plus = v.IndexOf('+');
            return plus > 0 ? v[..plus] : v;
        }
    }

    public async Task<AppUpdateInfo?> FetchLatestAsync()
    {
        try
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10));
            var json = await InnerTubeService.Http.GetStringAsync(ManifestUrl + "?t=" + DateTime.UtcNow.Ticks, cts.Token);
            return JsonSerializer.Deserialize<AppUpdateInfo>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        }
        catch { return null; }
    }

    public static bool IsNewer(string candidate, string current)
    {
        static int[] Parts(string s) => s.TrimStart('v').Split('.').Select(p => int.TryParse(p, out var n) ? n : 0).Concat(new[] { 0, 0, 0 }).Take(3).ToArray();
        var a = Parts(candidate);
        var b = Parts(current);
        for (var i = 0; i < 3; i++) if (a[i] != b[i]) return a[i] > b[i];
        return false;
    }

    public async Task<AppUpdateInfo?> CheckAsync()
    {
        var info = await FetchLatestAsync();
        return info != null && IsNewer(info.Version, CurrentVersion) ? info : null;
    }

    /// <summary>Is this a portable copy (no installer uninstall entry next to it)?</summary>
    public static bool IsPortable => !File.Exists(Path.Combine(AppContext.BaseDirectory, "unins000.exe"));

    public async Task DownloadAndInstallAsync(AppUpdateInfo info, IProgress<double> progress, CancellationToken ct)
    {
        var url = info.WindowsDownloadUrl;
        if (string.IsNullOrEmpty(url) || IsPortable)
        {
            Process.Start(new ProcessStartInfo(ReleasesPage) { UseShellExecute = true });
            return;
        }
        var dest = Path.Combine(Path.GetTempPath(), $"AuraTube-Setup-{info.Version}.exe");
        await YtDlpBinary.DownloadToFileAsync(url, dest, TimeSpan.FromMinutes(15), progress, ct);
        Process.Start(new ProcessStartInfo(dest, "/SILENT /SUPPRESSMSGBOXES /NORESTART") { UseShellExecute = true });
        System.Windows.Application.Current.Shutdown();
    }
}
