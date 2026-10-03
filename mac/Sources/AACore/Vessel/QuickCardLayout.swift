// Spec: 10 §B (VESSEL-011…028), §C (VESSEL-040…055), §3.1 (QuickCardsPanel / QuickCardEditorWindow algorithms),
//       §3.1.11 (editor flag table, size parsing, custom colour), §4.2 (target kinds), §7.14 (vectors).
import Foundation

/// What a Quick Card points at (precedence everywhere: `IsLink` → web, else `IsFolder` → folder, else `LinkInPlace`
/// → live file, else imported copy — 10 §4.2).
public enum QuickCardTargetKind: Sendable, Hashable, CaseIterable {
    case webLink, folder, liveFile, importedCopy

    public init(isLink: Bool, isFolder: Bool, linkInPlace: Bool) {
        if isLink { self = .webLink } else if isFolder { self = .folder } else if linkInPlace { self = .liveFile } else {
            self = .importedCopy
        }
    }

    /// VESSEL-015 / VESSEL-042 label.
    public var label: String {
        switch self {
        case .webLink: return "Web link"
        case .folder: return "Folder (live)"
        case .liveFile: return "File (live)"
        case .importedCopy: return "Imported copy"
        }
    }

    /// The exact flag combination each editor action writes (10 §3.1.11 table).
    public var flags: (isLink: Bool, linkInPlace: Bool, isFolder: Bool) {
        switch self {
        case .webLink: return (true, false, false)
        case .folder: return (false, true, true)
        case .liveFile: return (false, true, false)
        case .importedCopy: return (false, false, false)
        }
    }
}

/// Pure geometry and text rules of the Quick Cards canvas and editor (no UI).
public enum QuickCardLayout {
    // MARK: Canvas (VESSEL-011, §3.1.2)

    public static let minCanvasWidth: Double = 1000
    public static let minCanvasHeight: Double = 640
    public static let canvasSlack: Double = 40

    /// `SizeCanvas`: `max(1000, max(X+W+40))` × `max(640, max(Y+H+40))`.
    public static func canvasSize(_ frames: [(x: Double, y: Double, width: Double, height: Double)]) -> (width: Double, height: Double) {
        var w = minCanvasWidth, h = minCanvasHeight
        for f in frames {
            w = max(w, f.x + f.width + canvasSlack)
            h = max(h, f.y + f.height + canvasSlack)
        }
        return (w, h)
    }

    @MainActor public static func canvasSize(cards: [QuickCard]) -> (width: Double, height: Double) {
        canvasSize(cards.map { (x: $0.x, y: $0.y, width: $0.width, height: $0.height) })
    }

    // MARK: Card (VESSEL-013, §3.1.4)

    /// `max(18, min(W, H) × 0.36)`.
    public static func iconSize(width: Double, height: Double) -> Double { max(18, min(width, height) * 0.36) }

    public static let cardCornerRadius: Double = 10
    public static let gripSize: Double = 16

    // MARK: Add / duplicate (VESSEL-021, VESSEL-023)

    /// Cascade position for a new card: `24 + (n mod 6) × 28` on both axes.
    public static func cascadePosition(existingCount n: Int) -> (x: Double, y: Double) {
        let v = 24 + Double(((n % 6) + 6) % 6) * 28
        return (v, v)
    }

    public static let duplicateOffset: Double = 24

    // MARK: Drag and resize (VESSEL-017, VESSEL-018, §3.1.5)

    /// `X = max(0, originX + dx)`, `Y = max(0, originY + dy)` — no upper clamp, no snapping.
    public static func dragged(originX: Double, originY: Double, dx: Double, dy: Double) -> (x: Double, y: Double) {
        (max(0, originX + dx), max(0, originY + dy))
    }

    public static let minDragWidth: Double = 90
    public static let minDragHeight: Double = 64

    /// Grip drag: `W = max(90, W + dx)`, `H = max(64, H + dy)` — no maximum.
    public static func resized(width: Double, height: Double, dx: Double, dy: Double) -> (width: Double, height: Double) {
        (max(minDragWidth, width + dx), max(minDragHeight, height + dy))
    }

    // MARK: Editor size fields (VESSEL-051, §3.1.11)

    public static let editorMinWidth: Double = 80, editorMaxWidth: Double = 900
    public static let editorMinHeight: Double = 60, editorMaxHeight: Double = 700

    /// Width field: a number ≥ 80 → `min(900, value)`; anything else (blank, non-numeric, below 80) → nil (ignored).
    public static func editorWidth(from text: String, locale: Locale = .current) -> Double? {
        guard let v = parseNumber(text, locale: locale), v >= editorMinWidth else { return nil }
        return min(editorMaxWidth, v)
    }

    /// Height field: a number ≥ 60 → `min(700, value)`; anything else → nil (ignored).
    public static func editorHeight(from text: String, locale: Locale = .current) -> Double? {
        guard let v = parseNumber(text, locale: locale), v >= editorMinHeight else { return nil }
        return min(editorMaxHeight, v)
    }

    /// The editor's initial text: `(int)value` (truncated toward zero).
    public static func editorSizeText(_ v: Double) -> String {
        guard v.isFinite else { return "0" }
        return String(Int(v.rounded(.towardZero)))
    }

    /// `double.TryParse(text, Float | AllowThousands, CurrentCulture)`, also accepting `.` as the decimal separator
    /// (10 §3.1.11): surrounding white space, a leading sign, the locale's group separators, one decimal separator and
    /// an exponent.
    public static func parseNumber(_ text: String, locale: Locale = .current) -> Double? {
        let t = NetText.trim(text)
        guard !t.isEmpty else { return nil }
        let decimal = locale.decimalSeparator ?? "."
        let group = locale.groupingSeparator ?? ","
        func attempt(decimalSep: String, groupSep: String) -> Double? {
            var s = t
            if !groupSep.isEmpty, groupSep != decimalSep {
                s = s.replacingOccurrences(of: groupSep, with: "")
                if groupSep == "\u{00A0}" || groupSep == "\u{202F}" { s = s.replacingOccurrences(of: " ", with: "") }
            }
            if decimalSep != "." { s = s.replacingOccurrences(of: decimalSep, with: ".") }
            return strictDouble(s)
        }
        // A "." in a locale whose decimal separator is something else is read as the decimal point (10 §3.1.11).
        if decimal != ".", t.contains("."), !t.contains(decimal) { return attempt(decimalSep: ".", groupSep: "") }
        return attempt(decimalSep: decimal, groupSep: group)
    }

    /// `[sign] digits [. digits] [e|E [sign] digits]`, at least one digit in the mantissa, finite.
    static func strictDouble(_ s: String) -> Double? {
        let u = Array(s.utf8)
        var i = 0
        if i < u.count, u[i] == 0x2B || u[i] == 0x2D { i += 1 }
        var mantissaDigits = 0
        while i < u.count, (0x30...0x39).contains(u[i]) { i += 1; mantissaDigits += 1 }
        if i < u.count, u[i] == 0x2E {
            i += 1
            while i < u.count, (0x30...0x39).contains(u[i]) { i += 1; mantissaDigits += 1 }
        }
        guard mantissaDigits > 0 else { return nil }
        if i < u.count, u[i] == 0x65 || u[i] == 0x45 {
            i += 1
            if i < u.count, u[i] == 0x2B || u[i] == 0x2D { i += 1 }
            var expDigits = 0
            while i < u.count, (0x30...0x39).contains(u[i]) { i += 1; expDigits += 1 }
            guard expDigits > 0 else { return nil }
        }
        guard i == u.count, let v = Double(s), v.isFinite else { return nil }
        return v
    }

    // MARK: Colour (VESSEL-050)

    /// `$"#FF{R:X2}{G:X2}{B:X2}"` — alpha forced to FF, upper-case hex.
    public static func customColorHex(r: UInt8, g: UInt8, b: UInt8) -> String {
        WpfColor.hexAARRGGBB(ARGB(a: 0xFF, r: r, g: g, b: b))
    }

    /// sRGB components 0…1 → `#FFRRGGBB` (rounded, clamped).
    public static func customColorHex(red: Double, green: Double, blue: Double) -> String {
        func c(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        return customColorHex(r: c(red), g: c(green), b: c(blue))
    }

    // MARK: Texts (VESSEL-012, 015, 024, 025, 042, 053)

    public static let headerTitle = "Quick Cards"
    public static let headerHint = "Double-click a card to open it. Drag to move, drag the corner to resize, right-click to edit."
    /// The two-axis canvas pans with the trackpad / wheel; it shows no scrollers, so no legacy scroller corner square
    /// is drawn inside the rounded canvas (design rule 17).
    public static let canvasShowsScrollers = false
    public static let addButtonTitle = "+ Quick card"
    public static let emptyText = "No quick cards yet for this vessel.\nClick '+ Quick card' to add a shortcut to a file, folder, or web link."
    public static let noTargetTitle = "Quick card"
    public static let noTargetMessage = "This card has no target yet. Right-click ▸ Edit to point it at a file, folder, or web link."
    public static let openFailedTitle = "Open failed"
    public static let editorTip = "Tip: on the vessel screen, drag a card to move it and drag its bottom-right corner to resize."
    public static let noTargetDisplay = "(none — pick a file, folder, or web link)"

    /// VESSEL-015 three-line tooltip.
    public static func tooltip(title: String, target: String, kind: QuickCardTargetKind) -> String {
        let t = NetText.isBlank(target) ? "(no target — right-click ▸ Edit)" : target
        let name = NetText.isBlank(title) ? "(untitled)" : title
        return "\(name)\n\(kind.label): \(t)\nDouble-click to open • drag to move • drag corner to resize"
    }

    @MainActor public static func tooltip(_ card: QuickCard) -> String {
        tooltip(title: card.title, target: card.target, kind: kind(of: card))
    }

    @MainActor public static func kind(of card: QuickCard) -> QuickCardTargetKind {
        QuickCardTargetKind(isLink: card.isLink, isFolder: card.isFolder, linkInPlace: card.linkInPlace)
    }

    /// VESSEL-024 confirmation body: the title, or the icon when the title is blank.
    public static func deletePrompt(title: String, icon: String) -> String {
        "Delete quick card '\(NetText.isBlank(title) ? icon : title)'?"
    }

    /// VESSEL-042 type label: empty without a target, else the kind label.
    public static func targetTypeLabel(target: String, kind: QuickCardTargetKind) -> String {
        NetText.isBlank(target) ? "" : kind.label
    }

    /// VESSEL-042 read-only target text.
    public static func targetDisplay(_ target: String) -> String {
        NetText.isBlank(target) ? noTargetDisplay : target
    }

    /// VESSEL-052 preview title.
    public static func previewTitle(_ title: String) -> String { NetText.isBlank(title) ? "(untitled)" : title }

    /// VESSEL-047 title auto-fill for a picked file: the file name without its extension (`Path.GetFileNameWithoutExtension`).
    public static func titleForFile(_ url: URL) -> String {
        let leaf = url.lastPathComponent
        guard let dot = leaf.lastIndex(of: ".") else { return leaf }
        return String(leaf[..<dot])
    }

    /// VESSEL-047 title auto-fill for a picked folder: its own name (a volume root keeps the root itself).
    public static func titleForFolder(_ url: URL) -> String {
        let p = url.standardizedFileURL.path
        if p == "/" { return "/" }
        let leaf = url.standardizedFileURL.lastPathComponent
        return leaf.isEmpty ? p : leaf
    }

    /// The fields of a new card created by `+ Quick card` (VESSEL-021).
    @MainActor public static func newCard(existingCount: Int) -> QuickCard {
        let c = QuickCard()
        let p = cascadePosition(existingCount: existingCount)
        c.x = p.x; c.y = p.y
        return c
    }

    /// VESSEL-023: a clone with a new Id, offset by +24/+24 (the imported file is shared, not copied).
    @MainActor public static func duplicate(_ card: QuickCard) -> QuickCard {
        let copy = QuickCard()
        copy.copy(from: card)
        copy.extra = card.extra
        copy.x += duplicateOffset
        copy.y += duplicateOffset
        return copy
    }

    /// Sets the target and the exact flag combination of an editor action (10 §3.1.11).
    @MainActor public static func setTarget(_ card: QuickCard, _ target: String, kind: QuickCardTargetKind) {
        card.target = target
        let f = kind.flags
        card.isLink = f.isLink; card.linkInPlace = f.linkInPlace; card.isFolder = f.isFolder
    }
}
