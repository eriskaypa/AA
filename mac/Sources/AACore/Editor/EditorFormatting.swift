// Spec: 05 CONT-020…030 (font family/size, B/I/U, strike, text colour, highlight, alignment, clear formatting, WPF
//       built-in size step and baseline variants), CONT-043 (whole-paragraph indent in 24 px steps, NaN/Auto = 0),
//       K-3 (independent underline and strike on the Mac), D-4 / CONT-066 (formatting allowed on locked text but the
//       sentinel survives Highlight and Clear formatting), XD.2.8 / XD.5 (`.aaFontFamilyName` is the stored family
//       token; display substitutes never leak into it; tokens dropped when the weight/style changes).
import AppKit

/// A character-format command applied to a range (or, with an empty selection, to the typing attributes).
public enum EditorCharCommand: Equatable {
    case bold, italic, underline, strikethrough
    case fontFamily(String)
    case fontSize(CGFloat)
    case step(bigger: Bool)
    case foreground(NSColor)
    case highlight(NSColor?)
    case clearFormatting
    /// +1 superscript, −1 subscript, 0 default (Format ▸ Font ▸ Baseline).
    case baseline(Int)
}

/// What the format bar shows for the current selection (CONT-022; the Mac also reflects B/I/U/S, alignment and lists).
public struct EditorSelectionSummary: Equatable {
    public enum ListKind: Equatable { case none, bullets, numbered }
    public var family: String?            // nil = mixed
    public var size: CGFloat?             // nil = mixed
    public var bold = false, italic = false, underline = false, strikethrough = false
    public var baseline = 0
    public var alignment: NSTextAlignment?  // nil = mixed
    public var list: ListKind = .none
    public var foreground: NSColor?
    public var highlight: NSColor?
    public var hasSelection = false
    public var touchesLock = false

    public init() {}
}

@MainActor public enum EditorFormatting {
    /// WPF `EditingCommands.IncreaseFontSize` / `DecreaseFontSize` step (`TextEditorCharacters.OneFontPoint` =
    /// 72/96 DIP) and its bounds; the Mac maps 1 DIP to 1 pt (XD.2.8).
    public static let fontStep: CGFloat = 0.75
    public static let maxFontSize: CGFloat = 1638
    /// CONT-043 / 05 §3.2 `IndentStep`.
    public static let indentStep: CGFloat = 24
    /// CONT-028: Clear formatting resets the ink to the paper colour `EditorFg #FF1A1A1A`, never the theme colour.
    public static let editorInk = NSColor(srgbRed: 0x1A / 255.0, green: 0x1A / 255.0, blue: 0x1A / 255.0, alpha: 1)
    /// CONT-021 sizes (WPF DIP, shown as points).
    public static let standardSizes: [CGFloat] = [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 72]

    // MARK: Fonts

    public static func isBold(_ f: NSFont?) -> Bool {
        guard let f else { return false }
        return NSFontManager.shared.traits(of: f).contains(.boldFontMask)
    }

    public static func isItalic(_ f: NSFont?) -> Bool {
        guard let f else { return false }
        return NSFontManager.shared.traits(of: f).contains(.italicFontMask)
    }

    /// `f` with the bold trait set or cleared (the editor default font when nil).
    public static func font(_ f: NSFont?, bold: Bool) -> NSFont {
        let base = f ?? defaultFont()
        let fm = NSFontManager.shared
        return bold ? fm.convert(base, toHaveTrait: .boldFontMask) : fm.convert(base, toNotHaveTrait: .boldFontMask)
    }

    public static func font(_ f: NSFont?, italic: Bool) -> NSFont {
        let base = f ?? defaultFont()
        let fm = NSFontManager.shared
        return italic ? fm.convert(base, toHaveTrait: .italicFontMask) : fm.convert(base, toNotHaveTrait: .italicFontMask)
    }

    public static func font(_ f: NSFont?, size: CGFloat) -> NSFont {
        let base = f ?? defaultFont()
        return NSFontManager.shared.convert(base, toSize: size)
    }

    /// `f` moved to `family`, keeping bold/italic where the family has them.
    public static func font(_ f: NSFont?, family: String) -> NSFont {
        let base = f ?? defaultFont()
        let fm = NSFontManager.shared
        let converted = fm.convert(base, toFamily: family)
        if converted.familyName == family { return converted }
        // The family has no face with these traits: take its regular face, then re-apply what it supports.
        if let plain = NSFont(name: family, size: base.pointSize) ?? fm.font(withFamily: family, traits: [], weight: 5,
                                                                              size: base.pointSize) {
            var out = plain
            if isBold(base) { out = fm.convert(out, toHaveTrait: .boldFontMask) }
            if isItalic(base) { out = fm.convert(out, toHaveTrait: .italicFontMask) }
            return out
        }
        return base
    }

    /// Consolas when installed, else the monospaced system font (05 §6.2), at the editor's 14 pt.
    public static func defaultFont(size: CGFloat = 14) -> NSFont {
        NSFont(name: "Consolas", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// The stored family token of a run: `.aaFontFamilyName`, else the display font's family.
    public static func familyToken(_ attrs: [NSAttributedString.Key: Any]) -> String? {
        if let t = attrs[.aaFontFamilyName] as? String, !t.isEmpty { return t }
        return (attrs[.font] as? NSFont)?.familyName
    }

    // MARK: Attribute dictionaries

    /// The default typing attributes of an empty container note (root context: Consolas 14, #FF1A1A1A, en-us).
    public static func defaultTypingAttributes(paragraphStyle: NSParagraphStyle? = nil) -> [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [
            .font: defaultFont(),
            .foregroundColor: editorInk,
            .aaFontFamilyName: "Consolas",
            .aaXmlLang: "en-us",
        ]
        if let paragraphStyle { a[.paragraphStyle] = paragraphStyle }
        return a
    }

    /// Character attributes worth carrying into new structure (table cells, inserted lists, plain paste): font,
    /// family token, ink and language — never links, locks, highlights, list markers or carried raw attributes.
    public static func plainBaseAttributes(from a: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var out: [NSAttributedString.Key: Any] = [:]
        let f = (a[.font] as? NSFont) ?? defaultFont()
        out[.font] = font(font(f, bold: false), italic: false)
        out[.aaFontFamilyName] = familyToken(a) ?? "Consolas"
        if a[.aaLinkStyled] as? Bool == true, let under = a[.aaUnderlyingForeground] as? NSColor {
            out[.foregroundColor] = under
        } else {
            out[.foregroundColor] = (a[.foregroundColor] as? NSColor) ?? editorInk
        }
        if let lang = a[.aaXmlLang] { out[.aaXmlLang] = lang }
        if let lang = a[NSAttributedString.Key("NSLanguage")] { out[NSAttributedString.Key("NSLanguage")] = lang }
        if let p = a[.paragraphStyle] { out[.paragraphStyle] = p }
        return out
    }

    /// Attributes that describe one stored piece of text and must never spread to newly typed or pasted text:
    /// a list marker (the writer drops marker text, so typed text carrying it would vanish on save), an in-run
    /// newline's original sequence and an opaque preserved fragment (the writer would repeat them), and attachments.
    public static let nonInheritableKeys: [NSAttributedString.Key] = [.aaListMarker, .aaInRunNewline, .aaPreservedXaml,
                                                                     .attachment]

    /// Typing attributes safe to type with at `caret` (05 §6.4, §7.4, XD.2.8): never a list marker, in-run newline,
    /// preserved fragment, attachment or lock. Right after a list marker (the start of an item's text) the item's
    /// first character supplies the attributes, so typed text matches the item and not the marker glyph.
    public static func cleanTypingAttributes(_ typing: [NSAttributedString.Key: Any], in s: NSAttributedString,
                                             caret: Int) -> [NSAttributedString.Key: Any] {
        var a = typing
        if a[.aaListMarker] != nil, caret >= 0, caret < s.length {
            let next = s.attributes(at: caret, effectiveRange: nil)
            let ch = (s.string as NSString).character(at: caret)
            if next[.aaListMarker] == nil, ch != 0x0A, ch != 0x2029, ch != 0x0D {
                a = next
            }
        }
        for k in nonInheritableKeys { a[k] = nil }
        return EditorLocking.unlockedTypingAttributes(a)
    }

    /// Whether `typing` carries anything `cleanTypingAttributes` would remove.
    public static func needsCleaning(_ typing: [NSAttributedString.Key: Any]) -> Bool {
        nonInheritableKeys.contains { typing[$0] != nil } || EditorLocking.isLocked(typing)
    }

    // MARK: Decisions (WPF toggle semantics)

    /// Runs that count for "is the selection uniformly X": no list markers and not newline-only (unless the range
    /// holds nothing else).
    static func contentRuns(_ s: NSAttributedString, _ range: NSRange) -> [(NSRange, [NSAttributedString.Key: Any])] {
        var all: [(NSRange, [NSAttributedString.Key: Any])] = []
        var content: [(NSRange, [NSAttributedString.Key: Any])] = []
        let text = s.string as NSString
        s.enumerateAttributes(in: range, options: []) { attrs, r, _ in
            if attrs[.aaListMarker] != nil { return }
            all.append((r, attrs))
            let sub = text.substring(with: r)
            if sub.contains(where: { $0 != "\n" && $0 != "\u{2029}" && $0 != "\r" }) { content.append((r, attrs)) }
        }
        return content.isEmpty ? all : content
    }

    /// The WPF toggle decision for B/I/U/S: uniformly on → turn off; anything else (mixed, off) → turn on.
    public static func toggleTarget(_ cmd: EditorCharCommand, in s: NSAttributedString, range: NSRange,
                                    typing: [NSAttributedString.Key: Any]) -> Bool {
        let runs = range.length > 0 ? contentRuns(s, range).map(\.1) : [typing]
        guard !runs.isEmpty else { return true }
        let allOn: Bool
        switch cmd {
        case .bold: allOn = runs.allSatisfy { isBold($0[.font] as? NSFont) }
        case .italic: allOn = runs.allSatisfy { isItalic($0[.font] as? NSFont) }
        case .underline: allOn = runs.allSatisfy { (($0[.underlineStyle] as? Int) ?? 0) != 0 }
        case .strikethrough: allOn = runs.allSatisfy { (($0[.strikethroughStyle] as? Int) ?? 0) != 0 }
        default: return true
        }
        return !allOn
    }

    // MARK: Applying character commands

    /// Applies `cmd` to every run of `range` (list markers are skipped). Returns false when nothing changed.
    @discardableResult
    public static func apply(_ cmd: EditorCharCommand, to s: NSMutableAttributedString, range: NSRange,
                             typing: [NSAttributedString.Key: Any] = [:]) -> Bool {
        guard range.length > 0, NSMaxRange(range) <= s.length else { return false }
        let on = toggleTarget(cmd, in: s, range: range, typing: typing)
        var changes: [(NSRange, [NSAttributedString.Key: Any])] = []
        s.enumerateAttributes(in: range, options: []) { attrs, r, _ in
            if attrs[.aaListMarker] != nil { return }
            let updated = transform(attrs, cmd, on: on)
            if !NSDictionary(dictionary: updated).isEqual(to: attrs) { changes.append((r, updated)) }
        }
        guard !changes.isEmpty else { return false }
        s.beginEditing()
        for (r, a) in changes { s.setAttributes(a, range: r) }
        s.endEditing()
        return true
    }

    /// `cmd` applied to the typing attributes (empty selection — "springloaded" formatting, CONT-020/023).
    public static func applyToTyping(_ cmd: EditorCharCommand, typing: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        let on = toggleTarget(cmd, in: NSAttributedString(), range: NSRange(location: 0, length: 0), typing: typing)
        return transform(typing, cmd, on: on)
    }

    /// One run's attributes after `cmd` (`on` = the toggle direction decided for the whole range).
    public static func transform(_ a: [NSAttributedString.Key: Any], _ cmd: EditorCharCommand,
                                 on: Bool) -> [NSAttributedString.Key: Any] {
        var a = a
        let f = a[.font] as? NSFont
        switch cmd {
        case .bold:
            a[.font] = font(f, bold: on)
            a[.aaFontWeightToken] = nil
        case .italic:
            a[.font] = font(f, italic: on)
            a[.aaFontStyleToken] = nil
        case .underline:
            a[.underlineStyle] = on ? NSUnderlineStyle.single.rawValue : nil
        case .strikethrough:
            a[.strikethroughStyle] = on ? NSUnderlineStyle.single.rawValue : nil
        case .fontFamily(let family):
            a[.font] = font(f, family: family)
            a[.aaFontFamilyName] = family
        case .fontSize(let size):
            guard size > 0, size.isFinite else { return a }
            a[.font] = font(f, size: size)
        case .step(let bigger):
            let cur = f?.pointSize ?? 14
            let next = bigger ? min(cur + fontStep, maxFontSize) : max(cur - fontStep, fontStep)
            a[.font] = font(f, size: next)
        case .foreground(let c):
            a[.foregroundColor] = c.usingColorSpace(.sRGB) ?? c
            a[.aaLinkStyled] = nil
            a[.aaUnderlyingForeground] = nil
            a[.aaForegroundBrushXml] = nil
        case .highlight(let c):
            // D-4: never overwrite the lock sentinel through Highlight.
            if EditorLocking.isLocked(a) { return a }
            if let c { a[.backgroundColor] = c.usingColorSpace(.sRGB) ?? c } else { a[.backgroundColor] = nil }
            a[.aaBackgroundBrushXml] = nil
        case .clearFormatting:
            a[.font] = font(font(f, bold: false), italic: false)
            a[.aaFontWeightToken] = nil
            a[.aaFontStyleToken] = nil
            a[.underlineStyle] = nil
            a[.strikethroughStyle] = nil
            a[.aaExtraDecorations] = nil
            a[.foregroundColor] = editorInk
            a[.aaLinkStyled] = nil
            a[.aaUnderlyingForeground] = nil
            a[.aaForegroundBrushXml] = nil
            if !EditorLocking.isLocked(a) {          // D-4: Clear formatting keeps a lock
                a[.backgroundColor] = nil
                a[.aaBackgroundBrushXml] = nil
            }
        case .baseline(let v):
            a[.superscript] = v == 0 ? nil : v
            a[.baselineOffset] = nil
            a[.aaBaselineAlignment] = nil
            var extras = (a[.aaInheritedExtras] as? [String: String]) ?? [:]
            if v == 0 { extras["Typography.Variants"] = nil } else {
                extras["Typography.Variants"] = v > 0 ? "Superscript" : "Subscript"
            }
            a[.aaInheritedExtras] = extras.isEmpty ? nil : extras
        }
        return a
    }

    // MARK: Paragraph commands

    /// Sets `alignment` on every paragraph the range touches (CONT-027). Returns the changed paragraph ranges.
    @discardableResult
    public static func setAlignment(_ alignment: NSTextAlignment, in s: NSMutableAttributedString,
                                    range: NSRange) -> [NSRange] {
        updateParagraphs(in: s, range: range) { p in
            guard p.alignment != alignment else { return false }
            p.alignment = alignment
            return true
        }
    }

    /// CONT-043 Indent / Outdent on a non-empty document (05 §3.1 `ChangeIndent`). Caret in a list → nest / un-nest
    /// (WPF Increase/DecreaseIndentation) + normalise. Caret in ordinary text → every touched paragraph's
    /// `Margin.Left = max(0, Left ± 24)` (NaN/Auto = 0) and `TextIndent = 0`, written into the paragraph model the
    /// XAML writer persists (the AppKit indents alone are not persisted for modelled paragraphs — V-05). The block
    /// tree is re-rendered as one replacement; the caller wraps the call in one undo step. Returns the new selection.
    @discardableResult
    public static func changeIndent(_ s: NSTextStorage, selection: NSRange, increase: Bool) -> NSRange {
        guard s.length > 0 else { return selection }
        let inList = isInList(s, at: selection.location)
        let out = increase ? RichListFormatter.indent(s, selection: selection)
                           : RichListFormatter.outdent(s, selection: selection)
        if inList { RichListFormatter.normalise(s) }
        return out
    }

    /// CONT-043 in an empty document: the typing attributes move ±24 (head and first-line together, clamped at 0,
    /// NaN = 0). A paragraph model carried in the typing attributes (left over from deleted text) is shifted too, so
    /// the first paragraph typed with them is written with the same `Margin.Left` it shows.
    public static func indentTypingAttributes(_ a: [NSAttributedString.Key: Any],
                                              increase: Bool) -> [NSAttributedString.Key: Any] {
        var cur: CGFloat = 0
        var out = paragraphStyle(a) { p in
            cur = p.headIndent.isFinite ? p.headIndent : 0
            let next = max(0, cur + (increase ? indentStep : -indentStep))
            guard next != cur || p.firstLineHeadIndent != next else { return false }
            p.headIndent = next
            p.firstLineHeadIndent = next
            return true
        }
        if var model = out[.richParagraphModel] as? [String: String] {
            let m = model["Margin"].flatMap(XamlValues.parseThickness)
                ?? XamlThickness(left: .nan, top: .nan, right: .nan, bottom: .nan)
            let left = m.left.isFinite ? m.left : 0
            let next = max(0, left + Double(increase ? indentStep : -indentStep))
            model["Margin"] = XamlValues.formatThickness(XamlThickness(left: next, top: m.top, right: m.right,
                                                                       bottom: m.bottom))
            model["TextIndent"] = nil
            out[.richParagraphModel] = model
        }
        return out
    }

    /// The new paragraph style of a typing-attributes dictionary for an empty document.
    public static func paragraphStyle(_ a: [NSAttributedString.Key: Any],
                                      _ body: (NSMutableParagraphStyle) -> Bool) -> [NSAttributedString.Key: Any] {
        let p = ((a[.paragraphStyle] as? NSParagraphStyle) ?? NSParagraphStyle.default).mutableCopy() as! NSMutableParagraphStyle
        var a = a
        if body(p) { a[.paragraphStyle] = p.copy() }
        return a
    }

    static func updateParagraphs(in s: NSMutableAttributedString, range: NSRange,
                                 _ body: (NSMutableParagraphStyle) -> Bool) -> [NSRange] {
        guard s.length > 0 else { return [] }
        var changed: [NSRange] = []
        s.beginEditing()
        for pr in EditorBlocks.paragraphRanges(s, touching: range) where pr.length > 0 {
            // A paragraph may carry several styles (e.g. after a paste); update each run's style.
            var runs: [(NSRange, NSParagraphStyle)] = []
            s.enumerateAttribute(.paragraphStyle, in: pr, options: []) { v, r, _ in
                runs.append((r, (v as? NSParagraphStyle) ?? NSParagraphStyle.default))
            }
            var any = false
            for (r, style) in runs {
                let m = style.mutableCopy() as! NSMutableParagraphStyle
                if body(m) {
                    s.addAttribute(.paragraphStyle, value: m.copy(), range: r)
                    any = true
                }
            }
            if any { changed.append(pr) }
        }
        s.endEditing()
        return changed
    }

    // MARK: Summary (format bar state)

    /// The summary looks at most this many characters of a selection (display only; a select-all on a very
    /// large note stays instant).
    public static let summaryScanLimit = 100_000

    public static func summary(_ s: NSAttributedString, selection fullSelection: NSRange,
                               typing: [NSAttributedString.Key: Any]) -> EditorSelectionSummary {
        var out = EditorSelectionSummary()
        out.hasSelection = fullSelection.length > 0
        let selection = NSRange(location: fullSelection.location, length: min(fullSelection.length, summaryScanLimit))
        let len = s.length
        let runs: [[NSAttributedString.Key: Any]]
        if selection.length > 0, NSMaxRange(selection) <= len {
            runs = contentRuns(s, selection).map(\.1)
        } else {
            runs = [typing]
        }
        guard let first = runs.first else { return out }
        let fam = familyToken(first)
        out.family = runs.allSatisfy { familyToken($0) == fam } ? fam : nil
        let size = (first[.font] as? NSFont)?.pointSize
        out.size = runs.allSatisfy { ($0[.font] as? NSFont)?.pointSize == size } ? size : nil
        out.bold = runs.allSatisfy { isBold($0[.font] as? NSFont) }
        out.italic = runs.allSatisfy { isItalic($0[.font] as? NSFont) }
        out.underline = runs.allSatisfy { (($0[.underlineStyle] as? Int) ?? 0) != 0 }
        out.strikethrough = runs.allSatisfy { (($0[.strikethroughStyle] as? Int) ?? 0) != 0 }
        out.baseline = (first[.superscript] as? Int) ?? 0
        out.foreground = first[.foregroundColor] as? NSColor
        out.highlight = EditorLocking.isLocked(first) ? nil : first[.backgroundColor] as? NSColor
        // Paragraph state from the paragraphs the selection touches.
        var styles: [NSParagraphStyle] = []
        if len > 0 {
            for pr in EditorBlocks.paragraphRanges(s, touching: selection).prefix(200) {
                let at = min(pr.location, len - 1)
                styles.append((s.attribute(.paragraphStyle, at: at, effectiveRange: nil) as? NSParagraphStyle) ?? .default)
            }
        } else if let p = typing[.paragraphStyle] as? NSParagraphStyle {
            styles = [p]
        }
        if styles.isEmpty { styles = [(typing[.paragraphStyle] as? NSParagraphStyle) ?? .default] }
        let a0 = styles[0].alignment
        out.alignment = styles.allSatisfy { $0.alignment == a0 } ? a0 : nil
        if let list = styles[0].textLists.last {
            out.list = isNumbered(list) ? .numbered : .bullets
        }
        return out
    }

    /// Numbered marker formats (05 §3.2 `IsNumbered`: Decimal, Lower/UpperLatin, Lower/UpperRoman).
    public static func isNumbered(_ list: NSTextList) -> Bool {
        let f = list.markerFormat.rawValue.lowercased()
        return f.contains("decimal") || f.contains("alpha") || f.contains("roman") || f.contains("latin")
    }

    /// Whether the paragraph at `location` belongs to a list.
    public static func isInList(_ s: NSAttributedString, at location: Int) -> Bool {
        guard s.length > 0 else { return false }
        let st = s.attribute(.paragraphStyle, at: min(max(0, location), s.length - 1), effectiveRange: nil) as? NSParagraphStyle
        return !(st?.textLists.isEmpty ?? true)
    }
}
