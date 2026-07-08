using System;
using System.Windows;
using System.Windows.Threading;
using AA.Services;
using AA.Views;

namespace AA;

/// <summary>
/// Interaction logic for App.xaml
/// </summary>
public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Never fail silently: log any unhandled exception (and show it) so a startup crash is
        // diagnosable instead of the app just "not starting".
        DispatcherUnhandledException += (_, ev) => { ReportCrash(ev.Exception); ev.Handled = true; };
        AppDomain.CurrentDomain.UnhandledException += (_, ev) => ReportCrash(ev.ExceptionObject as Exception);
        System.Threading.Tasks.TaskScheduler.UnobservedTaskException += (_, ev) => ev.SetObserved();

        // Apply the saved theme before any window renders (incl. the login screen).
        DataStore.LoadSettings();
        ThemeManager.Apply(DataStore.DarkMode);

        // Keep the app alive while only the modal login dialog is open — otherwise closing it
        // (with the default OnLastWindowClose) would shut the app down before MainWindow appears.
        ShutdownMode = ShutdownMode.OnExplicitShutdown;

        // Loading screen: show the splash photo, then continue to login → main window.
        var splash = new SplashWindow();
        splash.Show();

        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2.4) };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            splash.Close();
            ContinueToMain();
        };
        timer.Start();
    }

    /// <summary>Write an unhandled exception to a crash log next to the data folder and show it, so a
    /// failure to start is never silent. Best-effort — swallows any error while reporting.</summary>
    private static void ReportCrash(Exception? ex)
    {
        if (ex == null) return;
        var text = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {ex}\r\n\r\n";
        try
        {
            var path = System.IO.Path.Combine(DataStore.AppFolder, "crash.log");
            System.IO.Directory.CreateDirectory(DataStore.AppFolder);
            System.IO.File.AppendAllText(path, text);
            MessageBox.Show(
                $"AA hit an unexpected error and had to stop:\n\n{ex.Message}\n\n" +
                $"The full details were written to:\n{path}",
                "AA — error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        catch { /* last-resort: nothing more we can safely do */ }
    }

    private void ContinueToMain()
    {
        var login = new LoginWindow();
        if (login.ShowDialog() != true) { Shutdown(); return; }

        var main = new MainWindow();
        MainWindow = main;
        ShutdownMode = ShutdownMode.OnMainWindowClose;
        main.Show();
    }
}
