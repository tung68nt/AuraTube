using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.RegularExpressions;
using AuraTube.Models;

namespace AuraTube.Services;

public sealed class DownloadItem : INotifyPropertyChanged
{
    public string Id { get; } = Guid.NewGuid().ToString("N");
    public required Video Video { get; init; }
    public bool IsAudioOnly { get; init; }
    public string Quality { get; init; } = "1080";

    private double _progress;
    private string _status = "Đang chờ…";
    private bool _isDone, _isError;
    private string? _filePath;

    public double Progress { get => _progress; set => Set(ref _progress, value); }
    public string Status { get => _status; set => Set(ref _status, value); }
    public bool IsDone { get => _isDone; set { Set(ref _isDone, value); OnChanged(nameof(IsActive)); } }
    public bool IsError { get => _isError; set { Set(ref _isError, value); OnChanged(nameof(IsActive)); } }
    public string? FilePath { get => _filePath; set => Set(ref _filePath, value); }
    public bool IsActive => !IsDone && !IsError;
    public string Kind => IsAudioOnly ? "Âm thanh" : $"Video {Quality}p";
    internal Process? Process { get; set; }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return;
        field = value;
        OnChanged(name);
    }
    private void OnChanged(string? name) =>
        System.Windows.Application.Current?.Dispatcher.BeginInvoke(() => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name)));
}

/// <summary>MP4/MP3 downloads via yt-dlp with no-ffmpeg fallbacks. Port of DownloadManager.swift.</summary>
public sealed class DownloadManager
{
    public static DownloadManager Shared { get; } = new();
    public ObservableCollection<DownloadItem> Downloads { get; } = new();

    private static readonly Regex ProgressRx = new(@"\[download\]\s+([\d.]+)%", RegexOptions.Compiled);
    private static readonly Regex DestRx = new(@"(?:Destination:|Merging formats into ""|has already been downloaded)\s*""?(.+?)""?\s*$", RegexOptions.Compiled);

    public string DownloadDir
    {
        get
        {
            var d = AppStore.Shared.Settings.DownloadFolder;
            Directory.CreateDirectory(d);
            return d;
        }
    }

    /// <summary>ffmpeg folder if one exists (bundled bin/, managed bin/, or PATH).</summary>
    public static string? FfmpegDir()
    {
        var dirs = new[] { Path.Combine(AppContext.BaseDirectory, "bin"), YtDlpBinary.BinDir }
            .Concat((Environment.GetEnvironmentVariable("PATH") ?? "").Split(';', StringSplitOptions.RemoveEmptyEntries));
        foreach (var d in dirs)
        {
            try { if (File.Exists(Path.Combine(d.Trim('"'), "ffmpeg.exe"))) return d.Trim('"'); } catch { }
        }
        return null;
    }

    public DownloadItem Start(Video video, bool audioOnly, string quality)
    {
        var item = new DownloadItem { Video = video, IsAudioOnly = audioOnly, Quality = quality };
        Downloads.Insert(0, item);
        _ = RunAsync(item);
        return item;
    }

    public void Cancel(DownloadItem item)
    {
        try { item.Process?.Kill(true); } catch { }
        item.IsError = true;
        item.Status = "Đã huỷ";
    }

    public void Remove(DownloadItem item)
    {
        if (item.IsActive) Cancel(item);
        Downloads.Remove(item);
    }

    private async Task RunAsync(DownloadItem item)
    {
        string ytdlp;
        string[] js;
        try
        {
            item.Status = "Đang chuẩn bị yt-dlp…";
            ytdlp = await YtDlpBinary.Shared.ResolveAsync();
            js = await YtDlpBinary.Shared.JsRuntimeArgsAsync();
        }
        catch (Exception e)
        {
            item.IsError = true;
            item.Status = "Không cài được yt-dlp: " + e.Message;
            return;
        }
        if (!YtDlpService.IsValidId(item.Video.Id))
        {
            item.IsError = true;
            item.Status = "ID video không hợp lệ";
            return;
        }

        var q = item.Quality;
        var args = new List<string> { "-o", Path.Combine(DownloadDir, "%(title)s.%(ext)s"), "--no-playlist", "--newline", "--progress", "--windows-filenames" };
        var ff = FfmpegDir();
        if (ff != null) args.AddRange(new[] { "--ffmpeg-location", ff });
        args.AddRange(js);
        if (item.IsAudioOnly && ff == null)
            args.AddRange(new[] { "-f", "bestaudio[ext=m4a]/bestaudio/b" }); // no ffmpeg → keep original M4A
        else if (ff == null)
            args.AddRange(new[] { "-f", $"best[ext=mp4][height<={q}]/best[ext=mp4]/b/bv*" }); // no ffmpeg → single-file MP4
        else if (item.IsAudioOnly)
            args.AddRange(new[] { "-x", "--audio-format", "mp3", "--audio-quality", "0", "--embed-metadata" });
        else
            args.AddRange(new[]
            {
                "-f", $"bestvideo[vcodec^=avc1][height<={q}]+bestaudio[ext=m4a]/bestvideo[ext=mp4][height<={q}]+bestaudio[ext=m4a]/bestvideo[height<={q}]+bestaudio/best[height<={q}]/bv*+ba/b",
                "--merge-output-format", "mp4", "--postprocessor-args", "Merger:-movflags +faststart"
            });
        args.AddRange(new[] { "--", item.Video.WatchUrl });

        var psi = new ProcessStartInfo(ytdlp)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };
        psi.Environment["PYTHONIOENCODING"] = "utf-8";
        foreach (var a in args) psi.ArgumentList.Add(a);

        var errors = new StringBuilder();
        try
        {
            using var p = new Process { StartInfo = psi, EnableRaisingEvents = true };
            item.Process = p;
            p.OutputDataReceived += (_, e) =>
            {
                if (e.Data == null) return;
                var m = ProgressRx.Match(e.Data);
                if (m.Success && double.TryParse(m.Groups[1].Value, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var pct))
                {
                    item.Progress = pct / 100;
                    item.Status = $"Đang tải {pct:0.0}%";
                }
                var d = DestRx.Match(e.Data);
                if (d.Success) item.FilePath = d.Groups[1].Value.Trim();
                if (e.Data.Contains("[ExtractAudio]") || e.Data.Contains("[Merger]")) item.Status = "Đang xử lý…";
            };
            p.ErrorDataReceived += (_, e) => { if (e.Data != null) errors.AppendLine(e.Data); };
            item.Status = "Đang tải…";
            p.Start();
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
            await p.WaitForExitAsync();
            if (item.IsError) return;
            if (p.ExitCode == 0)
            {
                item.Progress = 1;
                item.IsDone = true;
                item.Status = "Hoàn tất";
            }
            else
            {
                item.IsError = true;
                var line = errors.ToString().Split('\n').LastOrDefault(l => l.Contains("ERROR")) ?? errors.ToString();
                item.Status = "Lỗi: " + line.Trim();
            }
        }
        catch (Exception e)
        {
            item.IsError = true;
            item.Status = "Lỗi: " + e.Message;
        }
    }
}
