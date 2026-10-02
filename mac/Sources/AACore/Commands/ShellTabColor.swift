// Spec: 03 SHELL-029 (tab colours: WPF ColorConverter parsing, contrast rule luma > 150, alpha ignored, "#RRGGBB"
//       upper-case from the picker), §6.7 (sRGB bytes rounded with Swift's default rounding). Vectors: 03 §7.1 "Tab contrast", "TryBrush for tabs", "Colour picker output".
import Foundation

public enum ShellTabColor {
    /// The parsed custom colour of a tab (nil = theme default: unparseable or absent).
    public static func parse(_ text: String?) -> ARGB? { WpfColor.parse(text) }

    /// Header text is black when `0.299R + 0.587G + 0.114B > 150` (alpha ignored), else white.
    public static func textIsBlack(_ c: ARGB) -> Bool { WpfColor.luma(c) > 150 }

    /// Picker components (sRGB, 0…1) → `#RRGGBB` upper-case; byte = `Int((component * 255).rounded())`.
    public static func hex(red: Double, green: Double, blue: Double) -> String {
        func byte(_ v: Double) -> UInt8 { UInt8(max(0, min(255, Int((v * 255).rounded())))) }
        return WpfColor.hexRRGGBB(ARGB(r: byte(red), g: byte(green), b: byte(blue)))
    }
}
