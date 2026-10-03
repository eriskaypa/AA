// Spec: 13 §3.10 (RenderBgra: 4-module white quiet zone, black modules on white), §6.3 "Rendering" (DeviceGray 8-bit,
//       an integer number of device pixels per module, no interpolation), FLASH-016, FLASH-071.
import CoreGraphics
import Foundation

/// Rasterises a `FlashQRCode`: 0 = dark, 255 = light, one square of `scale` pixels per module, quiet zone included.
public enum FlashQRRaster {
    /// The quiet zone the protocol requires (modules, each side).
    public static let quietZone = 4

    /// Pixels per side for a symbol at a scale (`scale < 1` → 1), quiet zone included.
    public static func pixelSize(of qr: FlashQRCode, scale: Int, border: Int = quietZone) -> Int {
        (qr.size + 2 * border) * max(1, scale)
    }

    /// The integer module scale that fits `side` device pixels (≥ 1).
    public static func fittingScale(for qr: FlashQRCode, side: Double, border: Int = quietZone) -> Int {
        guard side.isFinite, side > 0 else { return 1 }
        return max(1, Int((side / Double(qr.size + 2 * border)).rounded(.down)))
    }

    /// Row-major 8-bit grey pixels.
    public static func grayPixels(_ qr: FlashQRCode, scale: Int, border: Int = quietZone) -> (side: Int, pixels: [UInt8]) {
        let s = max(1, scale)
        let side = pixelSize(of: qr, scale: s, border: border)
        var px = [UInt8](repeating: 255, count: side * side)
        px.withUnsafeMutableBufferPointer { buf in
            for y in 0 ..< qr.size {
                for x in 0 ..< qr.size where qr.modules[y * qr.size + x] {
                    let ox = (x + border) * s, oy = (y + border) * s
                    for dy in 0 ..< s {
                        let row = (oy + dy) * side + ox
                        for dx in 0 ..< s { buf[row + dx] = 0 }
                    }
                }
            }
        }
        return (side, px)
    }

    /// The symbol as a DeviceGray `CGImage` (draw it with interpolation off).
    public static func cgImage(_ qr: FlashQRCode, scale: Int, border: Int = quietZone) -> CGImage? {
        let (side, px) = grayPixels(qr, scale: scale, border: border)
        guard let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Windows `RenderBgra` parity: BGRA bytes, white field, dark modules B=G=R=0, alpha 255.
    public static func bgraPixels(_ qr: FlashQRCode, scale: Int) -> (side: Int, pixels: [UInt8]) {
        let (side, gray) = grayPixels(qr, scale: scale)
        var out = [UInt8](repeating: 255, count: side * side * 4)
        for (i, g) in gray.enumerated() where g == 0 {
            out[i * 4] = 0; out[i * 4 + 1] = 0; out[i * 4 + 2] = 0
        }
        return (side, out)
    }
}

