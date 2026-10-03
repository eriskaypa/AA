// Spec: 10 §4.6 (50 icons, exact order and code points), §4.7 (20-colour palette, readable foreground), §3.1.3
//       (ParseColor / ReadableForeground), VESSEL-013/014/048/049; 03 SHELL-157, Appendix C; ARCHITECTURE.md §6.8
//       (OC-51).
import Foundation

/// The Quick Card icon set, colour palette and colour helpers (C# `MaritimeIcons`).
public enum MaritimeIcons {
    public struct Icon: Sendable, Hashable {
        public let glyph: String
        public let name: String

        public init(glyph: String, name: String) {
            self.glyph = glyph; self.name = name
        }
    }

    /// `MaritimeIcons.DefaultIcon` — U+2693 ⚓.
    public static let defaultIcon = "\u{2693}"

    /// `#FF1E88E5` — the fallback for a blank or unparseable card colour.
    public static let defaultColor = "#FF1E88E5"

    /// 10 §4.6, in picker order. Glyphs are exact scalar sequences (VS16 and ZWJ kept); #48 deliberately repeats #8.
    public static let all: [Icon] = [
        Icon(glyph: "\u{2693}", name: "Anchor"),
        Icon(glyph: "\u{1F6A2}", name: "Ship"),
        Icon(glyph: "\u{26F4}\u{FE0F}", name: "Ferry"),
        Icon(glyph: "\u{26F5}", name: "Sailboat"),
        Icon(glyph: "\u{1F6E5}\u{FE0F}", name: "Motorboat"),
        Icon(glyph: "\u{1F6DF}", name: "Lifebuoy"),
        Icon(glyph: "\u{26D1}\u{FE0F}", name: "Rescue"),
        Icon(glyph: "\u{1F9ED}", name: "Compass"),
        Icon(glyph: "\u{1F5FA}\u{FE0F}", name: "Chart"),
        Icon(glyph: "\u{1F6DE}", name: "Helm/Wheel"),
        Icon(glyph: "\u{2699}\u{FE0F}", name: "Engine"),
        Icon(glyph: "\u{1F527}", name: "Wrench"),
        Icon(glyph: "\u{1F6E0}\u{FE0F}", name: "Tools"),
        Icon(glyph: "\u{1F9F0}", name: "Toolbox"),
        Icon(glyph: "\u{1F529}", name: "Fasteners"),
        Icon(glyph: "\u{26A1}", name: "Electrical"),
        Icon(glyph: "\u{1F4A1}", name: "Lights"),
        Icon(glyph: "\u{1F526}", name: "Torch"),
        Icon(glyph: "\u{1F4E1}", name: "Radar"),
        Icon(glyph: "\u{1F4FB}", name: "Radio"),
        Icon(glyph: "\u{1F4DE}", name: "Phone"),
        Icon(glyph: "\u{1F525}", name: "Fire"),
        Icon(glyph: "\u{1F9EF}", name: "Extinguisher"),
        Icon(glyph: "\u{1F6A8}", name: "Alarm"),
        Icon(glyph: "\u{26A0}\u{FE0F}", name: "Warning"),
        Icon(glyph: "\u{26FD}", name: "Fuel"),
        Icon(glyph: "\u{1F6E2}\u{FE0F}", name: "Oil/Bunker"),
        Icon(glyph: "\u{1F4A7}", name: "Fresh water"),
        Icon(glyph: "\u{1F30A}", name: "Sea/Ballast"),
        Icon(glyph: "\u{2744}\u{FE0F}", name: "Reefer"),
        Icon(glyph: "\u{1F321}\u{FE0F}", name: "Temperature"),
        Icon(glyph: "\u{1F4E6}", name: "Cargo"),
        Icon(glyph: "\u{1F5C3}\u{FE0F}", name: "Stores"),
        Icon(glyph: "\u{1F5C2}\u{FE0F}", name: "Files"),
        Icon(glyph: "\u{1F4C1}", name: "Folder"),
        Icon(glyph: "\u{1F4C4}", name: "Document"),
        Icon(glyph: "\u{1F4CB}", name: "Checklist"),
        Icon(glyph: "\u{1F4C5}", name: "Schedule"),
        Icon(glyph: "\u{1FA7A}", name: "Medical"),
        Icon(glyph: "\u{1F9EA}", name: "Lab/Test"),
        Icon(glyph: "\u{1FA9D}", name: "Hook/Crane"),
        Icon(glyph: "\u{1F517}", name: "Link"),
        Icon(glyph: "\u{1F6AA}", name: "Door/Hatch"),
        Icon(glyph: "\u{1FA9F}", name: "Bridge"),
        Icon(glyph: "\u{1F9D1}\u{200D}\u{2708}\u{FE0F}", name: "Crew"),
        Icon(glyph: "\u{1F310}", name: "Network"),
        Icon(glyph: "\u{260E}\u{FE0F}", name: "Comms"),
        Icon(glyph: "\u{1F9ED}", name: "Navigation"),
        Icon(glyph: "\u{1F514}", name: "Bell"),
        Icon(glyph: "\u{2B50}", name: "Favourite"),
    ]

    /// 10 §4.7 — exact `#AARRGGBB` strings in swatch order.
    public static let palette: [String] = [
        "#FF1E88E5", "#FF3949AB", "#FF00897B", "#FF43A047", "#FF7CB342",
        "#FFFDD835", "#FFFB8C00", "#FFF4511E", "#FFE53935", "#FFD81B60",
        "#FF8E24AA", "#FF5E35B1", "#FF546E7A", "#FF6D4C41", "#FF26A69A",
        "#FF455A64", "#FF263238", "#FF9E9E9E", "#FFEEEEEE", "#FFFFFFFF",
    ]

    /// §3.1.3 `ParseColor`: blank → `#FF1E88E5`; else WPF `ColorConverter` (`#RGB`, `#ARGB`, `#RRGGBB`, `#AARRGGBB`,
    /// the 141 named colours, `sc#`); anything unparseable → `#FF1E88E5`. Alpha is kept.
    public static func parseColor(_ s: String?) -> ARGB {
        let fallback = ARGB(a: 0xFF, r: 0x1E, g: 0x88, b: 0xE5)
        guard let s, !NetText.isBlank(s) else { return fallback }
        return WpfColor.parse(s) ?? fallback
    }

    /// §3.1.3 `ReadableForeground`: `(0.299·R + 0.587·G + 0.114·B) / 255 > 0.6` → dark text `#1A1A1A`, else white.
    /// Alpha is ignored.
    public static func readableForegroundIsDark(_ c: ARGB) -> Bool {
        (0.299 * Double(c.r) + 0.587 * Double(c.g) + 0.114 * Double(c.b)) / 255.0 > 0.6
    }

    /// The readable foreground as a colour value: `#FF1A1A1A` or `#FFFFFFFF`.
    public static func readableForeground(_ c: ARGB) -> ARGB {
        readableForegroundIsDark(c) ? ARGB(a: 0xFF, r: 0x1A, g: 0x1A, b: 0x1A) : ARGB(a: 0xFF, r: 0xFF, g: 0xFF, b: 0xFF)
    }

    /// The friendly name of a glyph (first match in picker order), or nil for a glyph outside the set.
    public static func name(of glyph: String) -> String? {
        all.first { Ordinal.equals($0.glyph, glyph) }?.name
    }
}
