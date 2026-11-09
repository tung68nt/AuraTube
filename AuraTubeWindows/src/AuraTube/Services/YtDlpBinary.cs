using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net.Http;

namespace AuraTube.Services;

/// <summary>
/// Finds yt-dlp.exe and keeps an app-managed copy in %LOCALAPPDATA%\AuraTube\bin, refreshed every
/// 3 days. Also resolves a JavaScript runtime for yt-dlp (deno or node, installing deno if neither
/// exists) — without one YouTube exposes few formats and yt-dlp fails with
/// "Requested format is not available". Port of YTDLPBinary.swift.
/// </summary>
public sealed class YtDlpBinary
{
    public static YtDlpBinary Shared { get; } = new();

    private const string DownloadUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe";
    private const string DenoUrl = "https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip";
    private static readonly TimeSpan UpdateInterval = TimeSpan.FromDays(3);

    private readonly SemaphoreSlim _installLock = new(1, 1);
    private readonly SemaphoreSlim _denoLock = new(1, 1);
    private Task<string?>? _denoTask;

    public static string BinDir { get; } = Path.Combine(AppStore.DataDir, "bin");
    public string ManagedPath => Path.Combine(BinDir, "yt-dlp.exe");
    private string ManagedDenoPath => Path.Combine(BinDir, "deno.exe");
    private static string BundledDir => Path.Combine(AppContext.BaseDirectory, "bin");

    public event Action<string>? StatusChanged;

    private IEnumerable<string> Candidates()
    {
        yield return ManagedPath;
        yield return Path.Combine(BundledDir, "yt-dlp.exe");
        foreach (var p in FindOnPath("yt-dlp.exe")) yield return p;
    }

    public string? ExistingPath => Candidates().FirstOrDefault(IsValidExe);

    public async Task<string> ResolveAsync()
    {
        var p = ExistingPath;
        return p ?? await InstallAsync();
    }

    /// <summary>Called at launch: installs if missing, refreshes the managed copy when it is old.</summary>
    public void PrepareInBackground()
    {
        _ = Task.Run(async () =>
        {
            _ = await JsRuntimeArgsAsync();
            try
            {
                if (!IsValidExe(ManagedPath))
                {
                    // Seed the managed copy from the bundled one so it can self-update in a writable dir.
                    var bundled = Path.Combine(BundledDir, "yt-dlp.exe");
                    if (IsValidExe(bundled))
                    {
                        Directory.CreateDirectory(BinDir);
                        File.Copy(bundled, ManagedPath, true);
                        File.SetLastWriteTimeUtc(ManagedPath, File.GetLastWriteTimeUtc(bundled));
                    }
                }
                if (!IsValidExe(ManagedPath) && ExistingPath == null) { await InstallAsync(); return; }
                if (IsValidExe(ManagedPath) && DateTime.UtcNow - File.GetLastWriteTimeUtc(ManagedPath) > UpdateInterval)
                    await InstallAsync(force: true);
            }
            catch { /* keep the working copy */ }
        });
    }

    public async Task<string> InstallAsync(bool force = false)
    {
        await _installLock.WaitAsync();
        try
        {
            if (!force && IsValidExe(ManagedPath)) return ManagedPath;
            Directory.CreateDirectory(BinDir);
            StatusChanged?.Invoke("Đang tải yt-dlp…");
            Exception? last = null;
            for (var attempt = 0; attempt < 3; attempt++)
            {
                try
                {
                    var staged = ManagedPath + ".new";
                    await DownloadToFileAsync(DownloadUrl, staged, TimeSpan.FromMinutes(2));
                    if (!IsValidExe(staged)) throw new InvalidOperationException("File yt-dlp tải về không hợp lệ");
                    File.Move(staged, ManagedPath, true);
                    File.SetLastWriteTimeUtc(ManagedPath, DateTime.UtcNow);
                    StatusChanged?.Invoke("Đã cập nhật yt-dlp");
                    return ManagedPath;
                }
                catch (Exception e)
                {
                    last = e;
                    await Task.Delay(1500 * (attempt + 1));
                }
            }
            // A failed refresh should not hide a still-working older copy.
            var existing = ExistingPath;
            if (existing != null) return existing;
            throw new InvalidOperationException("Không thể tải yt-dlp. Vui lòng kiểm tra kết nối mạng.", last);
        }
        finally { _installLock.Release(); }
    }

    public string? Version()
    {
        var p = ExistingPath;
        if (p == null) return null;
        try
        {
            var psi = new ProcessStartInfo(p, "--version") { RedirectStandardOutput = true, UseShellExecute = false, CreateNoWindow = true };
            using var proc = Process.Start(psi)!;
            var v = proc.StandardOutput.ReadToEnd().Trim();
            proc.WaitForExit(5000);
            return v;
        }
        catch { return null; }
    }

    // MARK: - JS runtime

    private (string Name, string Path)? ExistingJsRuntime()
    {
        var denoCandidates = new[]
        {
            ManagedDenoPath,
            Path.Combine(BundledDir, "deno.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".deno", "bin", "deno.exe")
        }.Concat(FindOnPath("deno.exe"));
        foreach (var p in denoCandidates) if (IsValidExe(p)) return ("deno", p);
        foreach (var p in FindOnPath("node.exe").Append(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "nodejs", "node.exe")))
            if (IsValidExe(p)) return ("node", p);
        return null;
    }

    /// <summary>`--js-runtimes` arguments for yt-dlp; installs deno on first use if needed.</summary>
    public async Task<string[]> JsRuntimeArgsAsync()
    {
        var rt = ExistingJsRuntime();
        if (rt != null) return new[] { "--js-runtimes", $"{rt.Value.Name}:{rt.Value.Path}" };
        Task<string?> task;
        await _denoLock.WaitAsync();
        try { task = _denoTask ??= InstallDenoAsync(); }
        finally { _denoLock.Release(); }
        var path = await task;
        if (path == null) { _denoTask = null; return Array.Empty<string>(); }
        return new[] { "--js-runtimes", $"deno:{path}" };
    }

    private async Task<string?> InstallDenoAsync()
    {
        Directory.CreateDirectory(BinDir);
        StatusChanged?.Invoke("Đang tải trình chạy JavaScript (deno)…");
        for (var attempt = 0; attempt < 3; attempt++)
        {
            var zip = Path.Combine(BinDir, "deno.zip");
            var unzip = Path.Combine(BinDir, "deno-unzip");
            try
            {
                await DownloadToFileAsync(DenoUrl, zip, TimeSpan.FromMinutes(5));
                if (Directory.Exists(unzip)) Directory.Delete(unzip, true);
                ZipFile.ExtractToDirectory(zip, unzip);
                var exe = Path.Combine(unzip, "deno.exe");
                if (!IsValidExe(exe)) throw new InvalidDataException();
                File.Move(exe, ManagedDenoPath, true);
                return ManagedDenoPath;
            }
            catch { await Task.Delay(2000 * (attempt + 1)); }
            finally
            {
                try { File.Delete(zip); } catch { }
                try { if (Directory.Exists(unzip)) Directory.Delete(unzip, true); } catch { }
            }
        }
        return null;
    }

    // MARK: - Helpers

    internal static async Task DownloadToFileAsync(string url, string dest, TimeSpan timeout, IProgress<double>? progress = null, CancellationToken ct = default)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(timeout);
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        req.Headers.UserAgent.ParseAdd("AuraTube");
        using var resp = await InnerTubeService.Http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, cts.Token);
        resp.EnsureSuccessStatusCode();
        var total = resp.Content.Headers.ContentLength ?? -1;
        await using var src = await resp.Content.ReadAsStreamAsync(cts.Token);
        await using (var fs = File.Create(dest))
        {
            var buf = new byte[81920];
            long read = 0;
            int n;
            while ((n = await src.ReadAsync(buf, cts.Token)) > 0)
            {
                await fs.WriteAsync(buf.AsMemory(0, n), cts.Token);
                read += n;
                if (total > 0) progress?.Report((double)read / total);
            }
        }
    }

    private static IEnumerable<string> FindOnPath(string exe) =>
        (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';', StringSplitOptions.RemoveEmptyEntries)
            .Select(d => { try { return Path.Combine(d.Trim('"'), exe); } catch { return ""; } })
            .Where(p => p.Length > 0);

    /// <summary>PE executable ("MZ") of plausible size, not an HTML error page.</summary>
    internal static bool IsValidExe(string path)
    {
        try
        {
            if (!File.Exists(path)) return false;
            using var fs = File.OpenRead(path);
            if (fs.Length < 100_000) return false;
            return fs.ReadByte() == 'M' && fs.ReadByte() == 'Z';
        }
        catch { return false; }
    }
}
