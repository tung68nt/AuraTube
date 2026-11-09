using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;
using AuraTube.Models;

namespace AuraTube.Services;

public sealed class AppSettings
{
    /// <summary>"auto", "2160", "1440", "1080", "720", "480", "360".</summary>
    public string PreferredQuality { get; set; } = "auto";
    public bool PreferMaxQuality { get; set; }
    public bool SponsorBlockEnabled { get; set; } = true;
    public bool AutoplayNext { get; set; } = true;
    public bool MinimizeToTray { get; set; } = true;
    public bool AutoCheckUpdates { get; set; } = true;
    public string DownloadFolder { get; set; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads", "AuraTube");
    public string DownloadQuality { get; set; } = "1080";
    public double Volume { get; set; } = 80;
    public string? SkippedUpdateVersion { get; set; }
    public DateTime? LastGoogleSync { get; set; }
}

/// <summary>JSON persistence for settings, history, bookmarks and subscriptions under %LOCALAPPDATA%\AuraTube.</summary>
public sealed class AppStore
{
    public static string DataDir { get; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AuraTube");

    public static AppStore Shared { get; } = new();

    private static readonly JsonSerializerOptions JsonOpts = new() { WriteIndented = true };

    public AppSettings Settings { get; private set; } = new();
    public ObservableCollection<Video> History { get; } = new();
    public ObservableCollection<Video> Bookmarks { get; } = new();
    public ObservableCollection<SubscribedChannel> Subscriptions { get; } = new();
    public List<string> RecentSearches { get; } = new();

    public event Action? SubscriptionsChanged;

    private AppStore()
    {
        Directory.CreateDirectory(DataDir);
        Settings = Load<AppSettings>("settings.json") ?? new AppSettings();
        foreach (var v in Load<List<Video>>("history.json") ?? new()) History.Add(v);
        foreach (var v in Load<List<Video>>("bookmarks.json") ?? new()) Bookmarks.Add(v);
        foreach (var c in Load<List<SubscribedChannel>>("subscriptions.json") ?? new()) Subscriptions.Add(c);
        RecentSearches.AddRange(Load<List<string>>("searches.json") ?? new());
    }

    private static T? Load<T>(string name)
    {
        try
        {
            var p = Path.Combine(DataDir, name);
            return File.Exists(p) ? JsonSerializer.Deserialize<T>(File.ReadAllText(p)) : default;
        }
        catch { return default; }
    }

    private static void Save<T>(string name, T value)
    {
        try
        {
            var p = Path.Combine(DataDir, name);
            File.WriteAllText(p + ".tmp", JsonSerializer.Serialize(value, JsonOpts));
            File.Move(p + ".tmp", p, true);
        }
        catch { /* best effort */ }
    }

    public void SaveSettings() => Save("settings.json", Settings);

    public void AddHistory(Video v)
    {
        var existing = History.FirstOrDefault(x => x.Id == v.Id);
        if (existing != null) History.Remove(existing);
        History.Insert(0, v);
        while (History.Count > 300) History.RemoveAt(History.Count - 1);
        Save("history.json", History.ToList());
    }

    public void ClearHistory() { History.Clear(); Save("history.json", History.ToList()); }

    public bool IsBookmarked(string id) => Bookmarks.Any(b => b.Id == id);

    public bool ToggleBookmark(Video v)
    {
        var existing = Bookmarks.FirstOrDefault(x => x.Id == v.Id);
        if (existing != null) Bookmarks.Remove(existing); else Bookmarks.Insert(0, v);
        Save("bookmarks.json", Bookmarks.ToList());
        return existing == null;
    }

    public bool IsSubscribed(string titleOrId) =>
        Subscriptions.Any(c => string.Equals(c.Id, titleOrId, StringComparison.OrdinalIgnoreCase)
                            || string.Equals(c.Title, titleOrId, StringComparison.OrdinalIgnoreCase));

    public void Subscribe(SubscribedChannel ch)
    {
        if (IsSubscribed(ch.Id ?? ch.Title) || IsSubscribed(ch.Title)) return;
        Subscriptions.Add(ch);
        SaveSubscriptions();
    }

    public void Unsubscribe(string titleOrId)
    {
        foreach (var c in Subscriptions.Where(c => string.Equals(c.Id, titleOrId, StringComparison.OrdinalIgnoreCase)
                     || string.Equals(c.Title, titleOrId, StringComparison.OrdinalIgnoreCase)).ToList())
            Subscriptions.Remove(c);
        SaveSubscriptions();
    }

    public void SaveSubscriptions()
    {
        Save("subscriptions.json", Subscriptions.ToList());
        SubscriptionsChanged?.Invoke();
    }

    public void RecordSearch(string q)
    {
        q = q.Trim();
        if (q.Length == 0) return;
        RecentSearches.RemoveAll(s => string.Equals(s, q, StringComparison.OrdinalIgnoreCase));
        RecentSearches.Insert(0, q);
        if (RecentSearches.Count > 20) RecentSearches.RemoveRange(20, RecentSearches.Count - 20);
        Save("searches.json", RecentSearches);
    }
}
