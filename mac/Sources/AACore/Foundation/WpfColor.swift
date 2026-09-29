// Spec: 03 §6.7 (WPF colour strings: tab colours, Quick Card colours, XAML brushes), 01 §4.2.9 (#AARRGGBB);
//       ARCHITECTURE.md §6.1.
import Foundation

public struct ARGB: Sendable, Hashable, CustomStringConvertible {
    public var a, r, g, b: UInt8
    public init(a: UInt8 = 0xFF, r: UInt8, g: UInt8, b: UInt8) { self.a = a; self.r = r; self.g = g; self.b = b }
    public var description: String { WpfColor.hexAARRGGBB(self) }
}

/// WPF `ColorConverter` parsing: `#RGB`, `#ARGB`, `#RRGGBB`, `#AARRGGBB`, the 141 known colour names
/// (case-insensitive) and `sc#[a,]r,g,b` scRGB floats.
public enum WpfColor {
    public static func parse(_ text: String?) -> ARGB? {
        guard let text else { return nil }
        let t = NetText.trim(text)
        if t.hasPrefix("#") { return parseHex(t) }
        if t.lowercased().hasPrefix("sc#") { return parseScRgb(String(t.dropFirst(3))) }
        guard let v = knownColors[t.lowercased()] else { return nil }
        return ARGB(a: UInt8((v >> 24) & 0xFF), r: UInt8((v >> 16) & 0xFF), g: UInt8((v >> 8) & 0xFF), b: UInt8(v & 0xFF))
    }

    static func hexValue(_ c: UInt8) -> UInt8? {
        switch c {
        case 0x30...0x39: return c - 0x30
        case 0x41...0x46: return c - 0x41 + 10
        case 0x61...0x66: return c - 0x61 + 10
        default: return nil
        }
    }

    static func parseHex(_ t: String) -> ARGB? {
        let u = Array(t.utf8)
        guard [4, 5, 7, 9].contains(u.count) else { return nil }
        var h: [UInt8] = []
        for c in u.dropFirst() { guard let v = hexValue(c) else { return nil }; h.append(v) }
        switch u.count {
        case 9: return ARGB(a: h[0] * 16 + h[1], r: h[2] * 16 + h[3], g: h[4] * 16 + h[5], b: h[6] * 16 + h[7])
        case 7: return ARGB(r: h[0] * 16 + h[1], g: h[2] * 16 + h[3], b: h[4] * 16 + h[5])
        case 5: return ARGB(a: h[0] * 17, r: h[1] * 17, g: h[2] * 17, b: h[3] * 17)
        default: return ARGB(r: h[0] * 17, g: h[1] * 17, b: h[2] * 17)
        }
    }

    static func parseScRgb(_ body: String) -> ARGB? {
        let parts = body.split(separator: ",", omittingEmptySubsequences: false)
            .map { Float(NetText.trim(String($0))) }
        guard parts.count == 3 || parts.count == 4, parts.allSatisfy({ $0 != nil }) else { return nil }
        let v = parts.map { $0! }
        let a: Float = v.count == 4 ? v[0] : 1
        let rgb = v.count == 4 ? Array(v[1...]) : v
        let alpha: UInt8 = a < 0 ? 0 : (a > 1 ? 255 : UInt8((a * 255) + 0.5))
        return ARGB(a: alpha, r: scToS(rgb[0]), g: scToS(rgb[1]), b: scToS(rgb[2]))
    }

    /// WPF `Color.ScRgbTosRgb`.
    static func scToS(_ val: Float) -> UInt8 {
        if !(val > 0) { return 0 }
        if val <= 0.0031308 { return UInt8((255 * val * 12.92) + 0.5) }
        if val < 1 { return UInt8((255 * ((1.055 * Float(pow(Double(val), 1.0 / 2.4))) - 0.055)) + 0.5) }
        return 255
    }

    /// `"#RRGGBB"` upper case.
    public static func hexRRGGBB(_ c: ARGB) -> String { "#" + hex2(c.r) + hex2(c.g) + hex2(c.b) }
    /// `"#AARRGGBB"` upper case.
    public static func hexAARRGGBB(_ c: ARGB) -> String { "#" + hex2(c.a) + hex2(c.r) + hex2(c.g) + hex2(c.b) }

    static func hex2(_ v: UInt8) -> String {
        let s = String(v, radix: 16, uppercase: true)
        return s.count == 1 ? "0" + s : s
    }

    /// 0.299R + 0.587G + 0.114B (0…255).
    public static func luma(_ c: ARGB) -> Double { 0.299 * Double(c.r) + 0.587 * Double(c.g) + 0.114 * Double(c.b) }

    /// `System.Windows.Media.Colors` (lower-cased name → 0xAARRGGBB).
    static let knownColors: [String: UInt32] = [
        "aliceblue": 0xFFF0F8FF, "antiquewhite": 0xFFFAEBD7, "aqua": 0xFF00FFFF, "aquamarine": 0xFF7FFFD4,
        "azure": 0xFFF0FFFF, "beige": 0xFFF5F5DC, "bisque": 0xFFFFE4C4, "black": 0xFF000000,
        "blanchedalmond": 0xFFFFEBCD, "blue": 0xFF0000FF, "blueviolet": 0xFF8A2BE2, "brown": 0xFFA52A2A,
        "burlywood": 0xFFDEB887, "cadetblue": 0xFF5F9EA0, "chartreuse": 0xFF7FFF00, "chocolate": 0xFFD2691E,
        "coral": 0xFFFF7F50, "cornflowerblue": 0xFF6495ED, "cornsilk": 0xFFFFF8DC, "crimson": 0xFFDC143C,
        "cyan": 0xFF00FFFF, "darkblue": 0xFF00008B, "darkcyan": 0xFF008B8B, "darkgoldenrod": 0xFFB8860B,
        "darkgray": 0xFFA9A9A9, "darkgreen": 0xFF006400, "darkkhaki": 0xFFBDB76B, "darkmagenta": 0xFF8B008B,
        "darkolivegreen": 0xFF556B2F, "darkorange": 0xFFFF8C00, "darkorchid": 0xFF9932CC, "darkred": 0xFF8B0000,
        "darksalmon": 0xFFE9967A, "darkseagreen": 0xFF8FBC8F, "darkslateblue": 0xFF483D8B,
        "darkslategray": 0xFF2F4F4F, "darkturquoise": 0xFF00CED1, "darkviolet": 0xFF9400D3,
        "deeppink": 0xFFFF1493, "deepskyblue": 0xFF00BFFF, "dimgray": 0xFF696969, "dodgerblue": 0xFF1E90FF,
        "firebrick": 0xFFB22222, "floralwhite": 0xFFFFFAF0, "forestgreen": 0xFF228B22, "fuchsia": 0xFFFF00FF,
        "gainsboro": 0xFFDCDCDC, "ghostwhite": 0xFFF8F8FF, "gold": 0xFFFFD700, "goldenrod": 0xFFDAA520,
        "gray": 0xFF808080, "green": 0xFF008000, "greenyellow": 0xFFADFF2F, "honeydew": 0xFFF0FFF0,
        "hotpink": 0xFFFF69B4, "indianred": 0xFFCD5C5C, "indigo": 0xFF4B0082, "ivory": 0xFFFFFFF0,
        "khaki": 0xFFF0E68C, "lavender": 0xFFE6E6FA, "lavenderblush": 0xFFFFF0F5, "lawngreen": 0xFF7CFC00,
        "lemonchiffon": 0xFFFFFACD, "lightblue": 0xFFADD8E6, "lightcoral": 0xFFF08080, "lightcyan": 0xFFE0FFFF,
        "lightgoldenrodyellow": 0xFFFAFAD2, "lightgray": 0xFFD3D3D3, "lightgreen": 0xFF90EE90,
        "lightpink": 0xFFFFB6C1, "lightsalmon": 0xFFFFA07A, "lightseagreen": 0xFF20B2AA,
        "lightskyblue": 0xFF87CEFA, "lightslategray": 0xFF778899, "lightsteelblue": 0xFFB0C4DE,
        "lightyellow": 0xFFFFFFE0, "lime": 0xFF00FF00, "limegreen": 0xFF32CD32, "linen": 0xFFFAF0E6,
        "magenta": 0xFFFF00FF, "maroon": 0xFF800000, "mediumaquamarine": 0xFF66CDAA, "mediumblue": 0xFF0000CD,
        "mediumorchid": 0xFFBA55D3, "mediumpurple": 0xFF9370DB, "mediumseagreen": 0xFF3CB371,
        "mediumslateblue": 0xFF7B68EE, "mediumspringgreen": 0xFF00FA9A, "mediumturquoise": 0xFF48D1CC,
        "mediumvioletred": 0xFFC71585, "midnightblue": 0xFF191970, "mintcream": 0xFFF5FFFA,
        "mistyrose": 0xFFFFE4E1, "moccasin": 0xFFFFE4B5, "navajowhite": 0xFFFFDEAD, "navy": 0xFF000080,
        "oldlace": 0xFFFDF5E6, "olive": 0xFF808000, "olivedrab": 0xFF6B8E23, "orange": 0xFFFFA500,
        "orangered": 0xFFFF4500, "orchid": 0xFFDA70D6, "palegoldenrod": 0xFFEEE8AA, "palegreen": 0xFF98FB98,
        "paleturquoise": 0xFFAFEEEE, "palevioletred": 0xFFDB7093, "papayawhip": 0xFFFFEFD5,
        "peachpuff": 0xFFFFDAB9, "peru": 0xFFCD853F, "pink": 0xFFFFC0CB, "plum": 0xFFDDA0DD,
        "powderblue": 0xFFB0E0E6, "purple": 0xFF800080, "red": 0xFFFF0000, "rosybrown": 0xFFBC8F8F,
        "royalblue": 0xFF4169E1, "saddlebrown": 0xFF8B4513, "salmon": 0xFFFA8072, "sandybrown": 0xFFF4A460,
        "seagreen": 0xFF2E8B57, "seashell": 0xFFFFF5EE, "sienna": 0xFFA0522D, "silver": 0xFFC0C0C0,
        "skyblue": 0xFF87CEEB, "slateblue": 0xFF6A5ACD, "slategray": 0xFF708090, "snow": 0xFFFFFAFA,
        "springgreen": 0xFF00FF7F, "steelblue": 0xFF4682B4, "tan": 0xFFD2B48C, "teal": 0xFF008080,
        "thistle": 0xFFD8BFD8, "tomato": 0xFFFF6347, "transparent": 0x00FFFFFF, "turquoise": 0xFF40E0D0,
        "violet": 0xFFEE82EE, "wheat": 0xFFF5DEB3, "white": 0xFFFFFFFF, "whitesmoke": 0xFFF5F5F5,
        "yellow": 0xFFFFFF00, "yellowgreen": 0xFF9ACD32,
    ]
}
