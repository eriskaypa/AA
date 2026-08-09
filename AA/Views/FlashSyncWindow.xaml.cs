using System;
using System.Linq;
using System.Windows;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using AA.FlashSync;
using AA.Models;
using AA.Services;
// Aliased, not imported: OpenCvSharp also defines a `Window`, which would collide with WPF's.
using Mat = OpenCvSharp.Mat;
using Cv2 = OpenCvSharp.Cv2;
using ColorConversionCodes = OpenCvSharp.ColorConversionCodes;

namespace AA.Views;

/// <summary>The Flash Sync screen: flash a QR fountain for the iPhone to film (Send), or film the
/// iPhone's and rebuild what it sent (Receive).</summary>
public partial class FlashSyncWindow : Window
{
    private readonly DispatcherTimer _flashTimer = new();
    private FlashEncoder? _encoder;
    private int _framesShown;
    private int _chunkCount;
    private string _sendLabel = "";
    private JsonSnapshotForBaseline? _pendingBaseline;

    private FlashCamera? _camera;
    private FlashQrDecoder? _decoder;
    private FlashDecoder _receiver = new();
    private volatile bool _applying;
    private DateTime _lastPreviewPush = DateTime.MinValue;

    /// <summary>The tree that was sent, held until the user confirms the phone received it.</summary>
    private sealed class JsonSnapshotForBaseline
    {
        public System.Text.Json.Nodes.JsonObject Data { get; init; } = new();
        public System.Text.Json.Nodes.JsonObject Settings { get; init; } = new();
    }

    /// <summary>Raised after an incoming transfer is applied, so the main window can reload.</summary>
    public event Action<AppData>? DataApplied;

    public FlashSyncWindow()
    {
        InitializeComponent();
        _flashTimer.Tick += (_, __) => ShowNextFrame();
        SetFps(12);
        Loaded += (_, __) => { PrepareSend(); PopulateCameras(); };
    }

    // ================= SEND =================

    private void PrepareSend()
    {
        var outgoing = FlashSyncStore.BuildOutgoing(DataStore.AppIdentity);
        if (outgoing == null)
        {
            SendSummary.Text = "Nothing to send — the iPhone already has everything, as of the last transfer it confirmed.";
            SendStartBtn.IsEnabled = false;
            return;
        }

        var (payload, kind, label) = outgoing.Value;
        _sendLabel = label;
        _encoder = new FlashEncoder(payload, kind, label, FlashEncoder.NewSession());
        _chunkCount = _encoder.ChunkCount;
        _pendingBaseline = new JsonSnapshotForBaseline
        {
            Data = FlashSyncStore.ReadDataTree(),
            Settings = FlashSyncStore.ReadSettingsTree()
        };

        SendSummary.Text = kind == FrameKind.FullSnapshot
            ? $"First transfer to this iPhone, so the whole database goes across: {_chunkCount} pieces, about {EstimateSeconds(_chunkCount)}."
            : $"Sending your changes since the last confirmed transfer — {label}. {_chunkCount} piece{(_chunkCount == 1 ? "" : "s")}, about {EstimateSeconds(_chunkCount)}.";
        SendStartBtn.IsEnabled = true;
    }

    private string EstimateSeconds(int chunks)
    {
        // Systematic prefix means a clean capture needs ~1 pass; allow a little slack for missed frames.
        double fps = FpsSlider.Value <= 0 ? 12 : FpsSlider.Value;
        int secs = (int)Math.Ceiling(chunks * 1.35 / fps) + 1;
        return secs < 60 ? $"{secs} seconds" : $"{secs / 60} min {secs % 60} s";
    }

    private void SendStart_Click(object sender, RoutedEventArgs e)
    {
        if (_encoder == null) return;
        _flashTimer.Start();
        SendStartBtn.IsEnabled = false;
        SendStopBtn.IsEnabled = true;
        ConfirmedBtn.IsEnabled = true;
        // A transfer can take a while and must not be interrupted by the screen blanking.
        try { SystemSleep.KeepAwake(true); } catch { }
    }

    private void SendStop_Click(object sender, RoutedEventArgs e) => StopFlashing();

    private void StopFlashing()
    {
        _flashTimer.Stop();
        SendStartBtn.IsEnabled = _encoder != null;
        SendStopBtn.IsEnabled = false;
        try { SystemSleep.KeepAwake(false); } catch { }
    }

    private void ShowNextFrame()
    {
        if (_encoder == null) return;
        try
        {
            QrImage.Source = FlashQr.ToBitmapSource(_encoder.Next());
            _framesShown++;
            int passes = _chunkCount > 0 ? _framesShown / Math.Max(1, _chunkCount) : 0;
            SendProgress.Text = $"Flashing — {_framesShown} frames shown, {passes} full pass{(passes == 1 ? "" : "es")}. Keep going until the iPhone says it is done.";
        }
        catch (Exception ex)
        {
            StopFlashing();
            MessageBox.Show(this, "Could not draw the QR code: " + ex.Message, "Flash Sync",
                MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void Fps_Changed(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (!IsLoaded) return;
        SetFps((int)e.NewValue);
    }

    private void SetFps(int fps)
    {
        if (fps < 1) fps = 12;
        _flashTimer.Interval = TimeSpan.FromMilliseconds(1000.0 / fps);
        if (FpsText != null) FpsText.Text = $"{fps} / sec";
    }

    private void Confirmed_Click(object sender, RoutedEventArgs e)
    {
        if (_pendingBaseline == null) return;
        var ok = MessageBox.Show(this,
            "Has the iPhone actually reported that the transfer finished?\n\n" +
            "Only confirm if it has. This records what the phone now holds, so future syncs send just your newer changes. " +
            "Confirming too early would skip the changes it never received, and they would not be sent again.",
            "Confirm the iPhone received it", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No);
        if (ok != MessageBoxResult.Yes) return;

        FlashSyncStore.WriteBaseline(_pendingBaseline.Data, _pendingBaseline.Settings);
        StopFlashing();
        ConfirmedBtn.IsEnabled = false;
        _encoder = null;
        SendProgress.Text = "";
        PrepareSend();
        MessageBox.Show(this, "Recorded. Next time only your newer changes need to go across.", "Flash Sync",
            MessageBoxButton.OK, MessageBoxImage.Information);
    }

    // ================= RECEIVE =================

    private void PopulateCameras()
    {
        CameraCombo.Items.Clear();
        foreach (var (index, name) in FlashCamera.Enumerate())
            CameraCombo.Items.Add(new CameraChoice(index, name));
        if (CameraCombo.Items.Count > 0) CameraCombo.SelectedIndex = 0;
        else
        {
            RecvStatus.Text = "No camera found. Plug one in and press Rescan — or use the Send tab, which needs no camera at all.";
            RecvStartBtn.IsEnabled = false;
        }
    }

    private sealed record CameraChoice(int Index, string Name)
    {
        public override string ToString() => Name;
    }

    private void Rescan_Click(object sender, RoutedEventArgs e)
    {
        RecvStartBtn.IsEnabled = true;
        PopulateCameras();
    }

    private void RecvStart_Click(object sender, RoutedEventArgs e)
    {
        if (CameraCombo.SelectedItem is not CameraChoice choice) return;
        try
        {
            _decoder ??= new FlashQrDecoder();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, "The QR reader could not start: " + ex.Message, "Flash Sync",
                MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }

        _receiver = new FlashDecoder();
        _camera = new FlashCamera();
        RecvStatus.Text = "Looking for the iPhone's screen...";
        RecvBar.Value = 0;
        RecvLabel.Text = "";

        if (!_camera.Start(choice.Index, OnCameraFrame, OnCameraError))
        {
            _camera = null;
            return;
        }
        RecvStartBtn.IsEnabled = false;
        RecvStopBtn.IsEnabled = true;
        CameraCombo.IsEnabled = false;
    }

    private void RecvStop_Click(object sender, RoutedEventArgs e) => StopCamera();

    private void StopCamera()
    {
        try { _camera?.Stop(); } catch { }
        _camera = null;
        RecvStartBtn.IsEnabled = CameraCombo.Items.Count > 0;
        RecvStopBtn.IsEnabled = false;
        CameraCombo.IsEnabled = true;
    }

    /// <summary>Capture thread. Decode here (it is far too slow for the UI thread), then marshal only
    /// the cheap updates across.</summary>
    private void OnCameraFrame(Mat frame)
    {
        if (_applying) return;

        string[] texts;
        BitmapSource? preview = null;
        try
        {
            texts = _decoder?.Decode(frame) ?? Array.Empty<string>();

            // The preview is a comfort feature, not the decode path — throttle it so it never competes.
            if ((DateTime.UtcNow - _lastPreviewPush).TotalMilliseconds > 100)
            {
                _lastPreviewPush = DateTime.UtcNow;
                preview = ToBitmap(frame);
            }
        }
        catch { return; }

        foreach (var t in texts) _receiver.Ingest(t);

        bool complete = _receiver.IsComplete;
        int solved = _receiver.SolvedCount, total = _receiver.ChunkCount;
        string label = _receiver.Label;

        Dispatcher.BeginInvoke(() =>
        {
            if (preview != null) CamImage.Source = preview;
            if (total > 0)
            {
                RecvBar.Maximum = total;
                RecvBar.Value = solved;
                RecvStatus.Text = $"Receiving — {solved} of {total} pieces. Hold steady.";
                if (!string.IsNullOrWhiteSpace(label)) RecvLabel.Text = "Incoming: " + label;
            }
            else RecvStatus.Text = "Looking for the iPhone's screen...";

            if (complete && !_applying) { _applying = true; FinishReceive(); }
        });
    }

    private static BitmapSource? ToBitmap(Mat frame)
    {
        try
        {
            using var rgba = new Mat();
            if (frame.Channels() == 4) frame.CopyTo(rgba);
            else Cv2.CvtColor(frame, rgba, frame.Channels() == 1 ? ColorConversionCodes.GRAY2BGRA : ColorConversionCodes.BGR2BGRA);
            int w = rgba.Width, h = rgba.Height;
            var buf = new byte[(long)w * h * 4];
            System.Runtime.InteropServices.Marshal.Copy(rgba.Data, buf, 0, buf.Length);
            var bmp = BitmapSource.Create(w, h, 96, 96, System.Windows.Media.PixelFormats.Bgra32, null, buf, w * 4);
            bmp.Freeze();
            return bmp;
        }
        catch { return null; }
    }

    private void OnCameraError(string message) =>
        Dispatcher.BeginInvoke(() =>
        {
            StopCamera();
            RecvStatus.Text = message;
        });

    /// <summary>Everything arrived. Verify, show the user exactly what it would do, and only then apply.</summary>
    private void FinishReceive()
    {
        StopCamera();
        var payload = _receiver.Finish();
        if (payload == null)
        {
            RecvStatus.Text = "The transfer arrived damaged, so nothing was changed. Start the iPhone sending again.";
            _applying = false;
            return;
        }

        var kind = _receiver.Manifest?.Kind ?? FrameKind.ChangeSet;
        var change = FlashSyncStore.Preview(payload, kind);
        if (change == null)
        {
            RecvStatus.Text = "That transfer was not readable as Flash Sync data. Nothing was changed.";
            _applying = false;
            return;
        }

        var warning = change.IsSnapshot
            ? "\n\nThis REPLACES your current database with the iPhone's copy. Anything on this PC that is not on the phone will be lost."
            : "";
        var answer = MessageBox.Show(this,
            $"Received from the iPhone:\n\n    {change.Summary}{warning}\n\nApply it now?",
            "Apply the received changes?", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No);

        if (answer != MessageBoxResult.Yes)
        {
            RecvStatus.Text = "Discarded — nothing was changed.";
            _applying = false;
            return;
        }

        try
        {
            var data = FlashSyncStore.Apply(change);
            RecvStatus.Text = "Applied. " + change.Summary;
            DataApplied?.Invoke(data);
            PrepareSend();   // the baseline moved, so what is left to send has changed too
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, "Could not apply the transfer: " + ex.Message, "Flash Sync",
                MessageBoxButton.OK, MessageBoxImage.Error);
            RecvStatus.Text = "Failed to apply — your data was not changed.";
        }
        finally { _applying = false; }
    }

    private void Window_Closing(object sender, System.ComponentModel.CancelEventArgs e)
    {
        StopFlashing();
        StopCamera();
        try { _decoder?.Dispose(); } catch { }
        _decoder = null;
    }
}

/// <summary>Keeps the screen awake while a transfer is flashing — a blanked screen is a failed transfer.</summary>
internal static class SystemSleep
{
    [System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint SetThreadExecutionState(uint esFlags);

    private const uint ES_CONTINUOUS = 0x80000000, ES_DISPLAY_REQUIRED = 0x00000002, ES_SYSTEM_REQUIRED = 0x00000001;

    public static void KeepAwake(bool on) =>
        SetThreadExecutionState(on ? ES_CONTINUOUS | ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED : ES_CONTINUOUS);
}
