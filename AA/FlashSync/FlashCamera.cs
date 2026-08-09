using System;
using System.Collections.Generic;
using System.Threading;
using OpenCvSharp;

namespace AA.FlashSync;

/// <summary>Webcam capture for the Flash Sync receiver.
///
/// Uses the DirectShow backend deliberately: it needs no FFmpeg, which lets the build drop a 26 MB DLL
/// that only matters for reading video *files*. We only ever read live frames.
///
/// Capture runs on its own thread and hands frames to a callback. Decoding a dense QR takes ~15 ms, so a
/// single thread comfortably keeps up with a protocol that flashes 8-15 codes a second — but the UI thread
/// must never do it, or the preview stutters and frames are missed.</summary>
public sealed class FlashCamera : IDisposable
{
    private VideoCapture? _capture;
    private Thread? _thread;
    private volatile bool _running;

    /// <summary>Camera indices that opened successfully, with a friendly label. DirectShow gives no
    /// reliable device names without extra native interop, so probe indices and label them by position —
    /// enough for a "which camera?" picker, and honest about what we actually know.</summary>
    public static List<(int Index, string Name)> Enumerate(int maxProbe = 5)
    {
        var found = new List<(int, string)>();
        for (int i = 0; i < maxProbe; i++)
        {
            VideoCapture? probe = null;
            try
            {
                probe = new VideoCapture(i, VideoCaptureAPIs.DSHOW);
                if (probe.IsOpened())
                    found.Add((i, i == 0 ? "Default camera" : $"Camera {i + 1}"));
            }
            catch { }
            finally { try { probe?.Release(); probe?.Dispose(); } catch { } }
        }
        return found;
    }

    public bool IsRunning => _running;

    /// <summary>Open a camera and start delivering frames. <paramref name="onFrame"/> is called on the
    /// capture thread — marshal to the UI yourself. Returns false if the camera could not be opened
    /// (in use by another app, no device, driver refusal).</summary>
    public bool Start(int index, Action<Mat> onFrame, Action<string>? onError = null)
    {
        Stop();
        try
        {
            _capture = new VideoCapture(index, VideoCaptureAPIs.DSHOW);
            if (!_capture.IsOpened()) { onError?.Invoke("That camera could not be opened. Another app may be using it."); return false; }

            // A screen is a close, flat, bright target: ask for the most pixels the device will give us,
            // because module size in the captured image is what decides whether a dense code resolves.
            try
            {
                _capture.Set(VideoCaptureProperties.FrameWidth, 1920);
                _capture.Set(VideoCaptureProperties.FrameHeight, 1080);
                _capture.Set(VideoCaptureProperties.Fps, 30);
                _capture.Set(VideoCaptureProperties.BufferSize, 1);   // freshest frame, not a backlog
            }
            catch { }   // any of these may be unsupported; the defaults still work

            _running = true;
            _thread = new Thread(() => Loop(onFrame, onError)) { IsBackground = true, Name = "FlashSync capture" };
            _thread.Start();
            return true;
        }
        catch (Exception ex)
        {
            onError?.Invoke("Could not start the camera: " + ex.Message);
            Stop();
            return false;
        }
    }

    private void Loop(Action<Mat> onFrame, Action<string>? onError)
    {
        using var frame = new Mat();
        int emptyRun = 0;
        while (_running)
        {
            try
            {
                if (_capture == null || !_capture.Read(frame) || frame.Empty())
                {
                    // A few empty reads are normal at startup; a sustained run means the device went away.
                    if (++emptyRun > 120) { onError?.Invoke("The camera stopped sending frames."); return; }
                    Thread.Sleep(10);
                    continue;
                }
                emptyRun = 0;
                onFrame(frame);
            }
            catch (Exception ex) { onError?.Invoke("Camera error: " + ex.Message); return; }
        }
    }

    public void Stop()
    {
        _running = false;
        try { _thread?.Join(500); } catch { }
        _thread = null;
        try { _capture?.Release(); } catch { }
        try { _capture?.Dispose(); } catch { }
        _capture = null;
    }

    public void Dispose() => Stop();
}
