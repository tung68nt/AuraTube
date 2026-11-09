using System.IO;
using System.Windows;
using System.Windows.Threading;
using AuraTube.Services;

namespace AuraTube;

public partial class App : Application
{
    private static Mutex? _singleInstance;

    public static void Log(string msg)
    {
        try { File.AppendAllText(Path.Combine(AppStore.DataDir, "app.log"), $"[{DateTime.Now:HH:mm:ss.fff}] {msg}\n"); } catch { }
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        _singleInstance = new Mutex(true, "AuraTube.Windows.SingleInstance", out var isNew);
        if (!isNew)
        {
            NativeMethods.ActivateExisting("AuraTube");
            Shutdown();
            return;
        }

        DispatcherUnhandledException += OnUnhandled;
        AppDomain.CurrentDomain.UnhandledException += (_, a) => Log("FATAL " + a.ExceptionObject);
        TaskScheduler.UnobservedTaskException += (_, a) => { Log("task " + a.Exception); a.SetObserved(); };
        Log("startup");
        base.OnStartup(e);

        YtDlpBinary.Shared.PrepareInBackground();
        _ = NetworkSpeedService.Shared.MeasureAsync();

        Log("creating window");
        var main = new MainWindow();
        MainWindow = main;
        main.Show();
        Log("shown");

        var link = e.Args.Select(InnerTubeService.ParseVideoId).FirstOrDefault(id => id != null);
        if (link != null) main.OpenVideoById(link);
    }

    private void OnUnhandled(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        try
        {
            File.AppendAllText(Path.Combine(AppStore.DataDir, "error.log"), $"[{DateTime.Now:u}] {e.Exception}\n\n");
        }
        catch { }
        e.Handled = true;
    }

    protected override void OnExit(ExitEventArgs e)
    {
        AppStore.Shared.SaveSettings();
        base.OnExit(e);
    }
}

internal static class NativeMethods
{
    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    private static extern IntPtr FindWindow(string? lpClassName, string lpWindowName);
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public static void ActivateExisting(string title)
    {
        var h = FindWindow(null, title);
        if (h == IntPtr.Zero) return;
        ShowWindow(h, 9);
        SetForegroundWindow(h);
    }
}
