// Spec: 05 §6.4 "Character" (display substitution: Consolas → SF Mono/Menlo, Segoe UI → system font, Calibri →
//       Helvetica Neue, Cambria → Georgia; the original name kept in `.aaFontFamilyName`), §XD.2.8 `.font` row (first
//       installed part of the family list, weight buckets, bold trait iff weight ≥ 600, italic iff FontStyle ≠
//       Normal), §XD.5 "Display fonts" (cache by canon family + size + traits; the substitute never leaks),
//       §XD.2.10 `wanted()` (token-consistency tests the writer runs against the displayed NSFont).
import AppKit

@MainActor public enum RichFontResolver {
    private struct Key: Hashable { let canon: String; let size: Double; let weight: Int; let italic: Bool }
    private static var cache: [Key: NSFont] = [:]
    private static var familyCache: [String: String?] = [:]
    private static var installed: [String: String]?

    /// Lower-cased installed family name → its real spelling.
    private static var installedFamilies: [String: String] {
        if let i = installed { return i }
        var m: [String: String] = [:]
        for f in NSFontManager.shared.availableFontFamilies { m[f.lowercased()] = f }
        installed = m
        return m
    }

    /// The marker the resolver uses for "the system UI font" / "the system monospaced font" substitutes.
    static let systemUI = "\u{1}system"
    static let systemMono = "\u{1}mono"

    /// XD.2.8: the installed family (or display substitute) used for a WPF family token.
    public static func displayFamily(for token: String) -> String {
        let canon = XamlFontFamily(raw: token).canon
        if let hit = familyCache[canon] { return hit ?? systemUI }
        var result: String?
        let parts = token.split(separator: ",").map { stripQuotes(NetText.trim(String($0))) }.filter { !$0.isEmpty }
        for p in parts {
            if let real = installedFamilies[p.lowercased()] { result = real; break }
        }
        if result == nil {
            for p in parts {
                if let s = substitute(p) { result = s; break }
            }
        }
        familyCache[canon] = .some(result ?? systemUI)
        return result ?? systemUI
    }

    private static func stripQuotes(_ s: String) -> String {
        var t = s
        if t.hasPrefix("./#") { t.removeFirst(3) }
        if let hash = t.lastIndex(of: "#"), t.contains("/") { t = String(t[t.index(after: hash)...]) }
        return NetText.trim(t, characters: [0x22, 0x27])
    }

    private static func substitute(_ name: String) -> String? {
        switch name.lowercased() {
        case "consolas", "lucida console", "cascadia mono", "cascadia code":
            return systemMono
        case "segoe ui", "segoe ui semibold", "segoe ui light", "system-ui", "tahoma", "microsoft sans serif":
            return systemUI
        case "calibri", "candara", "corbel":
            return installedFamilies["helvetica neue"] ?? installedFamilies["helvetica"]
        case "cambria":
            return installedFamilies["georgia"] ?? installedFamilies["times new roman"]
        default:
            return nil
        }
    }

    /// XD.2.8 weight buckets.
    public static func weight(for w: Int) -> NSFont.Weight {
        switch w {
        case ...150: return .ultraLight
        case ...250: return .thin
        case ...350: return .light
        case ...450: return .regular
        case ...550: return .medium
        case ...650: return .semibold
        case ...750: return .bold
        case ...850: return .heavy
        default: return .black
        }
    }

    /// The display font for a WPF family token, size (px = pt on screen), weight and italic flag.
    public static func font(family token: String, size: Double, weight w: Int, italic: Bool) -> NSFont {
        let key = Key(canon: XamlFontFamily(raw: token).canon, size: size, weight: w, italic: italic)
        if let f = cache[key] { return f }
        let fam = displayFamily(for: token)
        let size = CGFloat(max(size, 1))
        let nsWeight = weight(for: w)
        var font: NSFont
        switch fam {
        case systemUI: font = NSFont.systemFont(ofSize: size, weight: nsWeight)
        case systemMono: font = NSFont.monospacedSystemFont(ofSize: size, weight: nsWeight)
        default:
            let d = NSFontDescriptor(fontAttributes: [.family: fam, .traits: [NSFontDescriptor.TraitKey.weight: nsWeight]])
            font = NSFont(descriptor: d, size: size) ?? NSFont.systemFont(ofSize: size, weight: nsWeight)
        }
        if italic {
            let d = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.italic))
            if let f = NSFont(descriptor: d, size: size), f.fontDescriptor.symbolicTraits.contains(.italic) {
                font = f
            } else {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
        }
        let wantBold = w >= 600
        if wantBold, !isBoldish(font) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        } else if !wantBold, isBoldish(font) {
            font = NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
        }
        cache[key] = font
        return font
    }

    /// The weight trait of a font (−1…1).
    public static func weightTrait(_ font: NSFont) -> Double {
        if let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any],
           let w = traits[.weight] as? NSNumber {
            return w.doubleValue
        }
        let mw = NSFontManager.shared.weight(of: font)                   // 0…15, 5 = regular, 9 = bold
        return Double(mw - 5) / 10.0
    }

    /// "Bold trait" for the writer's consistency rule: the symbolic bold trait or a weight of semibold and above.
    public static func isBoldish(_ font: NSFont) -> Bool {
        font.fontDescriptor.symbolicTraits.contains(.bold) || weightTrait(font) >= NSFont.Weight.semibold.rawValue - 0.01
    }

    public static func isItalic(_ font: NSFont, attributes: [NSAttributedString.Key: Any] = [:]) -> Bool {
        if font.fontDescriptor.symbolicTraits.contains(.italic) { return true }
        if let o = attributes[.obliqueness] as? NSNumber, o.doubleValue > 0 { return true }
        return false
    }

    /// The family name the writer compares with `displayFamily(for:)` (system fonts map to the markers).
    public static func familyKey(of font: NSFont) -> String {
        let name = font.familyName ?? font.fontName
        if name == NSFont.systemFont(ofSize: font.pointSize).familyName { return systemUI }
        if name == NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular).familyName { return systemMono }
        return name
    }

    /// Is the font still what the reader would display for this token (family check, XD-W7)?
    public static func familyMatches(token: String, font: NSFont) -> Bool {
        displayFamily(for: token) == familyKey(of: font)
    }

    /// Is a preserved weight token still consistent with the displayed font (XD-W3)?
    public static func weightTokenMatches(_ w: Int, font: NSFont, token family: String, italic: Bool) -> Bool {
        guard (w >= 600) == isBoldish(font) else { return false }
        let expected = self.font(family: family, size: Double(font.pointSize), weight: w, italic: italic)
        return abs(weightTrait(expected) - weightTrait(font)) < 0.02
    }

    /// A family name to write for a font the user picked on the Mac (Mac-only names are written as is).
    public static func writableFamilyName(of font: NSFont) -> String {
        switch familyKey(of: font) {
        case systemMono: return "Consolas"
        case systemUI: return "Segoe UI"
        default: return font.familyName ?? font.fontName
        }
    }
}
