// Lets the unmodified AA/Services/AppRepository.cs compile outside WPF (spec 01 GF.3.2 — the ONLY shim permitted).
// Provides only what AppRepository uses (object-initializer Interval, Tick, Start, Stop; AppRepository.cs:17,34-35,
// 264,296,305-306). It never ticks by itself: the generator persists explicitly (AppRepository.Save) so no background
// timing can reach a golden.
namespace System.Windows.Threading;

public sealed class DispatcherTimer
{
    public TimeSpan Interval { get; set; }
    public bool IsEnabled { get; private set; }
    public event EventHandler? Tick;
    public void Start() => IsEnabled = true;
    public void Stop() => IsEnabled = false;
    /// <summary>Generator-only: fire the 750 ms debounce (BackgroundSaveIfDirty) on demand.</summary>
    public void RaiseTick() => Tick?.Invoke(this, EventArgs.Empty);
}
