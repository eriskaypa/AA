// Spec: 05 CONT-020 (every installed family, enumerated once per process, sorted case-insensitively, initial
//       "Consolas"), CONT-021 (size list, `double.TryParse` > 0), CONT-022 (the bar reflects family and size), K-16
//       (the Mac applies a typed size on commit), XD.5 (the family control shows the stored token, not the display
//       substitute).
import AppKit

@MainActor public enum EditorFontCatalog {
    /// Installed family names, sorted like `OrdinalIgnoreCase` (computed once per process).
    public static let families: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted {
            let c = NetText.compareIgnoreCase($0, $1)
            return c == .orderedSame ? $0 < $1 : c == .orderedAscending
        }
    }()

    private static let familySet: Set<String> = Set(families.map { NetText.toLowerInvariant($0) })

    public static func isInstalled(_ family: String) -> Bool { familySet.contains(NetText.toLowerInvariant(family)) }

    /// CONT-021: a typed size applies when it parses as a number > 0 (current culture, invariant fallback).
    public static func parseSize(_ text: String) -> CGFloat? {
        let t = NetText.trim(text)
        guard !t.isEmpty else { return nil }
        let f = NumberFormatter()
        f.locale = Locale.current
        f.numberStyle = .decimal
        var value: Double?
        if let n = f.number(from: t) { value = n.doubleValue } else if let d = Double(t) { value = d }
        guard let v = value, v.isFinite, v > 0 else { return nil }
        return CGFloat(min(v, Double(EditorFormatting.maxFontSize)))
    }

    /// The size shown in the bar: whole numbers plain, fractions to at most two decimals (display only).
    public static func displaySize(_ size: CGFloat?) -> String {
        guard let size else { return "" }
        if size == size.rounded() { return String(Int(size)) }
        let f = NumberFormatter()
        f.locale = Locale.current
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: Double(size))) ?? String(Double(size))
    }
}
