using System;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Net.Codecrete.QrCodeGenerator;

namespace AA.FlashSync;

/// <summary>QR generation for Flash Sync. Level L is deliberate (spec §11): the fountain handles frame
/// loss far better than QR's own redundancy would, so every module spent on ECC is payload wasted.
/// Base45 keeps every frame inside QR's alphanumeric charset, which packs ~5.5 bits/char.
///
/// Generation uses Net.Codecrete (Nayuki's reference algorithm), NOT QRCoder — see AA.csproj for why.
/// Decoding lives in the receiver, which owns the camera; this class only draws.</summary>
public static class FlashQr
{
    /// <summary>Encode a Base45 frame string as a QR symbol at ECC level L.</summary>
    public static QrCode Generate(string base45) => QrCode.EncodeText(base45, QrCode.Ecc.Low);

    /// <summary>Render at <paramref name="scale"/> pixels per module, nearest-neighbour, black on white,
    /// with a 4-module quiet zone. The quiet zone is not optional — a QR pressed to the edge of its
    /// background is unreadable however sharp it is.</summary>
    public static byte[] RenderBgra(QrCode qr, int scale, out int sizePx)
    {
        if (scale < 1) scale = 1;
        const int border = 4;
        int modules = qr.Size + border * 2;
        sizePx = modules * scale;
        var px = new byte[(long)sizePx * sizePx * 4];
        Array.Fill(px, (byte)0xFF);                       // white field (B,G,R,A)
        for (int my = 0; my < qr.Size; my++)
            for (int mx = 0; mx < qr.Size; mx++)
            {
                if (!qr.GetModule(mx, my)) continue;      // dark module
                for (int dy = 0; dy < scale; dy++)
                {
                    int rowStart = ((my + border) * scale + dy) * sizePx;
                    for (int dx = 0; dx < scale; dx++)
                    {
                        int p = (rowStart + (mx + border) * scale + dx) * 4;
                        px[p] = 0; px[p + 1] = 0; px[p + 2] = 0;   // black; alpha stays 0xFF
                    }
                }
            }
        return px;
    }

    /// <summary>A frozen BitmapSource for display, safe to hand to the UI thread.</summary>
    public static BitmapSource ToBitmapSource(byte[] bgra, int sizePx)
    {
        var bmp = BitmapSource.Create(sizePx, sizePx, 96, 96, PixelFormats.Bgra32, null, bgra, sizePx * 4);
        bmp.Freeze();
        return bmp;
    }

    /// <summary>Display-ready QR for a frame string. Rendered at 1 px/module and upscaled by the Image
    /// with NearestNeighbor, so modules stay square and crisp at any window size — smoothed edges cost
    /// far more decodes than a smaller code does.</summary>
    public static BitmapSource ToBitmapSource(string base45)
    {
        var bgra = RenderBgra(Generate(base45), 1, out int size);
        return ToBitmapSource(bgra, size);
    }
}
