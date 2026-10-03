// Spec: 11 PDF-076 (ResolveFontName: split, trim, aliases, first installed), §6.4 / DEV-06 (Mac substitution
//       table), DEV-07 (CoreText cascade fallback), DECISIONS 11 Q2 (no bundled font: the system sans), §7.10.
import CoreText
import Foundation

/// Font-name resolution for the PDF (pure apart from the installed-family list, which is injectable for tests).
public struct PdfFontResolver: Sendable {
    /// The family name CoreText reports for the system UI font; `font(…)` maps it to
    /// `CTFontCreateUIFontForLanguage(.system, …)`.
    public static let systemUIFamily = ".AppleSystemUIFont"

    /// Installed family names keyed by their invariant lower-case form.
    private let installed: [String: String]

    /// `families` = the installed family names (default: `CTFontManagerCopyAvailableFontFamilyNames()`).
    public init(installedFamilies families: [String]) {
        var map: [String: String] = [:]
        for f in families { let k = NetText.toLowerInvariant(f); if map[k] == nil { map[k] = f } }
        installed = map
    }

    /// The resolver over this Mac's installed fonts (computed once).
    public static let system: PdfFontResolver = {
        let names = (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []
        return PdfFontResolver(installedFamilies: names)
    }()

    /// Windows `ResolveFontName` aliases (PDF-076), keyed lower-case.
    static let aliases: [String: String] = [
        "sans serif": "Arial", "sans-serif": "Arial", "sansserif": "Arial", "serif": "Times New Roman",
        "monospace": "Consolas", "cursive": "Comic Sans MS", "fantasy": "Impact", "system-ui": "Segoe UI",
    ]

    /// 11 §6.4 Mac substitution table (step 3), keyed lower-case, each candidate with its metric scale: the size
    /// factor that makes the substitute's advance widths match the Windows font (DECISIONS 11 Q2 "metrics tuned to
    /// match page breaks"; e.g. Calibri's em is ~9 % narrower than Helvetica Neue's, Consolas' 0.55 em cell vs
    /// Menlo's 0.602 em). `systemUIFamily` = the system UI font.
    static let substitutes: [String: [(family: String, scale: Double)]] = [
        "calibri": [("Carlito", 1.0), ("Helvetica Neue", 0.91), ("Helvetica", 0.92)],
        "consolas": [("Menlo", 0.914), ("SF Mono", 0.917), ("Monaco", 0.917), ("Courier New", 0.917)],
        "segoe ui": [(systemUIFamily, 1.0), ("Helvetica Neue", 0.95)],
        "segoe ui semibold": [(systemUIFamily, 1.0), ("Helvetica Neue", 0.95)],
        "cambria": [("Charter", 1.0), ("Georgia", 0.95), ("Times New Roman", 1.0)],
        "candara": [("Helvetica Neue", 0.92)], "corbel": [("Helvetica Neue", 0.92)],
        "tahoma": [("Verdana", 0.9), ("Helvetica Neue", 0.97)], "microsoft sans serif": [("Helvetica Neue", 0.95)],
    ]

    public func isInstalled(_ family: String) -> Bool { installed[NetText.toLowerInvariant(family)] != nil }

    /// The parts of a WPF family source after splitting on `,`, trimming whitespace then `'`/`"`, and applying
    /// the Windows alias map (PDF-076 step 2).
    public static func parts(_ source: String) -> [String] {
        source.split(separator: ",", omittingEmptySubsequences: false).compactMap { raw -> String? in
            var p = NetText.trim(String(raw))
            p = NetText.trim(p, characters: [0x27, 0x22])
            guard !p.isEmpty else { return nil }
            return aliases[NetText.toLowerInvariant(p)] ?? p
        }
    }

    /// The Mac family for a WPF `FontFamily` source (11 §6.4): first installed part; else the first installed
    /// substitute of any part; else the Normal font (= resolve("Calibri")). Never empty.
    public func resolve(_ source: String?) -> String { resolveFont(source).family }

    /// `resolve` plus the metric scale of a substitution (1 when the requested font itself is installed).
    public func resolveFont(_ source: String?) -> PdfResolvedFont {
        let src = NetText.isBlank(source) ? "Calibri" : source!
        let ps = Self.parts(src)
        for p in ps { if let actual = installed[NetText.toLowerInvariant(p)] { return PdfResolvedFont(family: actual, scale: 1) } }
        for p in ps { if let s = substitute(p) { return s } }
        return normalFontResolved
    }

    /// The resolved Normal font: resolve("Calibri") through the table (Helvetica Neue on a stock Mac).
    public var normalFont: String { normalFontResolved.family }

    var normalFontResolved: PdfResolvedFont {
        if let actual = installed["calibri"] { return PdfResolvedFont(family: actual, scale: 1) }
        return substitute("Calibri") ?? PdfResolvedFont(family: Self.systemUIFamily, scale: 1)
    }

    private func substitute(_ part: String) -> PdfResolvedFont? {
        guard let cands = Self.substitutes[NetText.toLowerInvariant(part)] else { return nil }
        for c in cands {
            if c.family == Self.systemUIFamily { return PdfResolvedFont(family: c.family, scale: c.scale) }
            if let actual = installed[NetText.toLowerInvariant(c.family)] { return PdfResolvedFont(family: actual, scale: c.scale) }
        }
        return nil
    }
}

public struct PdfResolvedFont: Sendable, Hashable {
    public var family: String
    /// Size factor applied when drawing (metric tuning of a substitute).
    public var scale: Double
    public init(family: String, scale: Double) { self.family = family; self.scale = scale }
}

/// A concrete CoreText font for one (family, size, bold, italic) request, with synthesis flags when the family
/// lacks the face (PDFsharp synthesises too, 11 §6.4).
final class PdfFontFace {
    let font: CTFont
    let syntheticBold: Bool
    init(font: CTFont, syntheticBold: Bool) { self.font = font; self.syntheticBold = syntheticBold }
}

/// Per-export cache of CoreText fonts (used only inside one layout/render pass).
final class PdfFontCache {
    private struct Key: Hashable { let family: String; let size: Double; let bold: Bool; let italic: Bool }
    private var faces: [Key: PdfFontFace] = [:]
    let resolver: PdfFontResolver

    init(resolver: PdfFontResolver) { self.resolver = resolver }

    /// `family` must already be resolved (`PdfFontResolver.resolve`).
    func face(family: String, size: Double, bold: Bool, italic: Bool) -> PdfFontFace {
        let key = Key(family: family, size: size, bold: bold, italic: italic)
        if let f = faces[key] { return f }
        let made = Self.make(family: family, size: CGFloat(size), bold: bold, italic: italic)
        faces[key] = made
        return made
    }

    private static func base(family: String, size: CGFloat) -> CTFont {
        if family == PdfFontResolver.systemUIFamily {
            return CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        }
        let desc = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family] as CFDictionary)
        return CTFontCreateWithFontDescriptor(desc, size, nil)
    }

    private static func make(family: String, size: CGFloat, bold: Bool, italic: Bool) -> PdfFontFace {
        let plain = base(family: family, size: size)
        var wanted = CTFontSymbolicTraits()
        if bold { wanted.insert(.traitBold) }
        if italic { wanted.insert(.traitItalic) }
        let mask: CTFontSymbolicTraits = [.traitBold, .traitItalic]
        func has(_ f: CTFont, _ t: CTFontSymbolicTraits) -> Bool { CTFontGetSymbolicTraits(f).contains(t) }
        var font = plain
        if !wanted.isEmpty {
            if let both = CTFontCreateCopyWithSymbolicTraits(plain, size, nil, wanted, mask), has(both, wanted) {
                font = both
            } else if bold, let b = CTFontCreateCopyWithSymbolicTraits(plain, size, nil, .traitBold, mask), has(b, .traitBold) {
                font = b
            } else if italic, let i = CTFontCreateCopyWithSymbolicTraits(plain, size, nil, .traitItalic, mask), has(i, .traitItalic) {
                font = i
            }
        }
        let synthBold = bold && !has(font, .traitBold)
        if italic && !has(font, .traitItalic) {
            var skew = CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0)     // ~11° oblique
            font = CTFontCreateCopyWithAttributes(font, size, &skew, nil)
        }
        return PdfFontFace(font: font, syntheticBold: synthBold)
    }
}
