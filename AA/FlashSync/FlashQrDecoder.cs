using System;
using System.IO;
using System.Reflection;
using OpenCvSharp;

namespace AA.FlashSync;

/// <summary>Reads Flash Sync QR frames off camera images, using OpenCV's WeChat detector.
///
/// Why this one: our frames are dense (around QR version 22, 105 modules) because chunkSize is 900. On
/// synthetic camera conditions — blur, 10-15% perspective warp, glare, downscaling — the managed decoders
/// measured 42%, this one 82%, and it never once returned wrong text in ~5,000 trials. Speed is not the
/// constraint either: ~15 ms a frame against a protocol that flashes 8-15 a second.
///
/// The detector needs its four model files on disk (OpenCV loads them by path), so they ride inside the
/// exe as embedded resources and are unpacked once, on first use.</summary>
public sealed class FlashQrDecoder : IDisposable
{
    private const string ResourcePrefix = "AA.FlashSync.Models.";
    private static readonly string[] ModelFiles = { "detect.prototxt", "detect.caffemodel", "sr.prototxt", "sr.caffemodel" };

    private readonly WeChatQRCode _detector;
    private bool _disposed;

    public FlashQrDecoder()
    {
        var dir = EnsureModels();
        _detector = WeChatQRCode.Create(
            Path.Combine(dir, "detect.prototxt"), Path.Combine(dir, "detect.caffemodel"),
            Path.Combine(dir, "sr.prototxt"), Path.Combine(dir, "sr.caffemodel"));
    }

    /// <summary>Unpack the detector weights beside the app data (once) and return the folder.
    /// Re-extracts if a file is missing or truncated, so a half-written first run repairs itself.</summary>
    public static string EnsureModels()
    {
        var dir = Path.Combine(AA.Services.DataStore.AppFolder, "qrmodels");
        Directory.CreateDirectory(dir);
        var asm = Assembly.GetExecutingAssembly();
        foreach (var name in ModelFiles)
        {
            var target = Path.Combine(dir, name);
            using var src = asm.GetManifestResourceStream(ResourcePrefix + name)
                ?? throw new InvalidOperationException($"Embedded QR model '{name}' is missing from the build.");
            if (File.Exists(target) && new FileInfo(target).Length == src.Length) continue;
            using var dst = File.Create(target);
            src.CopyTo(dst);
        }
        return dir;
    }

    /// <summary>Decode every QR visible in a BGRA camera frame. Returns an empty array when there is none —
    /// which is the common case, and not an error. Never throws: this runs on the capture loop.</summary>
    public string[] Decode(byte[] bgra, int width, int height)
    {
        if (_disposed || width <= 0 || height <= 0) return Array.Empty<string>();
        try
        {
            using var mat = Mat.FromPixelData(height, width, MatType.CV_8UC4, bgra);
            using var gray = new Mat();
            Cv2.CvtColor(mat, gray, ColorConversionCodes.BGRA2GRAY);
            _detector.DetectAndDecode(gray, out _, out string[] texts);
            return texts ?? Array.Empty<string>();
        }
        catch { return Array.Empty<string>(); }
    }

    /// <summary>Decode from an existing grayscale/colour Mat (the camera path, avoiding a copy).</summary>
    public string[] Decode(Mat frame)
    {
        if (_disposed || frame.Empty()) return Array.Empty<string>();
        try
        {
            using var gray = new Mat();
            if (frame.Channels() == 1) frame.CopyTo(gray);
            else Cv2.CvtColor(frame, gray, frame.Channels() == 4 ? ColorConversionCodes.BGRA2GRAY : ColorConversionCodes.BGR2GRAY);
            _detector.DetectAndDecode(gray, out _, out string[] texts);
            return texts ?? Array.Empty<string>();
        }
        catch { return Array.Empty<string>(); }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        try { _detector.Dispose(); } catch { }
    }
}
