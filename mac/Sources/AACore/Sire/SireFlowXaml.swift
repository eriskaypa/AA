// Spec: 12 §3.6 `ToContainerXaml`, §3.7 body XAML (BuildQuestionXaml / BuildOverviewXaml), §4.4 (the authoritative
//       element/attribute inventory: Section root with the WPF TextRange.Save defaults, Paragraph FontStyle/FontSize/
//       Margin/Padding/Background, Run Foreground, List MarkerStyle/Margin, ListItem, nested List; `Segoe UI`
//       preserved; intra-Run `\n` kept inside the Run; no whitespace between elements), 05 S-1/S-8; §6.1 ("build
//       the XAML for quick-add directly from the block model" — deterministic, byte-stable).
import Foundation

/// The byte-stable WPF `Section` writer for SireFlow documents.
public enum SireFlowXaml {
    static let namespaceURI = "http://schemas.microsoft.com/winfx/2006/xaml/presentation"

    /// The root attributes `TextRange.Save(DataFormats.Xaml)` emits for a SireFlow document (05 S-1 set).
    static func rootAttributes(foreground: ARGB) -> [(String, String)] {
        var a: [(String, String)] = [
            ("xmlns", namespaceURI), ("xml:space", "preserve"), ("TextAlignment", "Left"), ("LineHeight", "Auto"),
            ("IsHyphenationEnabled", "False"), ("xml:lang", "en-us"), ("FlowDirection", "LeftToRight"),
            ("NumberSubstitution.CultureSource", "User"), ("NumberSubstitution.Substitution", "AsCulture"),
            ("FontFamily", SireFlowDocument.fontFamily), ("FontStyle", "Normal"), ("FontWeight", "Normal"),
            ("FontStretch", "Normal"), ("FontSize", number(SireFlowDocument.fontSize)),
            ("Foreground", WpfColor.hexAARRGGBB(foreground)),
            ("Typography.StandardLigatures", "True"), ("Typography.ContextualLigatures", "True"),
            ("Typography.DiscretionaryLigatures", "False"), ("Typography.HistoricalLigatures", "False"),
            ("Typography.AnnotationAlternates", "0"), ("Typography.ContextualAlternates", "True"),
            ("Typography.HistoricalForms", "False"), ("Typography.Kerning", "True"),
            ("Typography.CapitalSpacing", "False"), ("Typography.CaseSensitiveForms", "False"),
        ]
        for i in 1...20 { a.append(("Typography.StylisticSet\(i)", "False")) }
        a += [("Typography.Fraction", "Normal"), ("Typography.SlashedZero", "False"),
              ("Typography.MathematicalGreek", "False"), ("Typography.EastAsianExpertForms", "False"),
              ("Typography.Variants", "Normal"), ("Typography.Capitals", "Normal"),
              ("Typography.NumeralStyle", "Normal"), ("Typography.NumeralAlignment", "Normal"),
              ("Typography.EastAsianWidths", "Normal"), ("Typography.EastAsianLanguage", "Normal"),
              ("Typography.StandardSwashes", "0"), ("Typography.ContextualSwashes", "0"),
              ("Typography.StylisticAlternates", "0")]
        return a
    }

    /// `ToContainerXaml(doc)`.
    public static func write(_ doc: SireFlowDocument) -> String {
        var out = "<Section"
        for (k, v) in rootAttributes(foreground: doc.foreground) { out += " \(k)=\"\(escapeAttribute(v))\"" }
        out += ">"
        for b in doc.blocks { writeBlock(b, into: &out) }
        out += "</Section>"
        return out
    }

    /// `BuildQuestionXaml(q)` — the quick-add container body (slate root).
    public static func questionXaml(_ q: SireQuestion) -> String { write(SireFlow.buildQuestion(q)) }

    /// `BuildOverviewXaml(title, qs)`.
    public static func overviewXaml(title: String, questions: [SireQuestion]) -> String {
        write(SireFlow.buildOverview(title: title, questions: questions))
    }

    static func writeBlock(_ b: SireFlowBlock, into out: inout String) {
        switch b {
        case .paragraph(let p): writeParagraph(p, into: &out)
        case .list(let l): writeList(l, into: &out)
        }
    }

    static func writeParagraph(_ p: SireFlowParagraph, into out: inout String) {
        out += "<Paragraph"
        if p.italic { out += " FontStyle=\"Italic\"" }
        if let s = p.fontSize { out += " FontSize=\"\(number(s))\"" }
        if let m = p.margin { out += " Margin=\"\(thickness(m))\"" }
        if let pd = p.padding { out += " Padding=\"\(thickness(pd))\"" }
        if let bg = p.background { out += " Background=\"\(WpfColor.hexAARRGGBB(bg))\"" }
        if p.runs.isEmpty { out += " />"; return }
        out += ">"
        for r in p.runs {
            out += "<Run"
            if let fg = r.foreground { out += " Foreground=\"\(WpfColor.hexAARRGGBB(fg))\"" }
            out += ">" + escapeText(r.text) + "</Run>"
        }
        out += "</Paragraph>"
    }

    static func writeList(_ l: SireFlowList, into out: inout String) {
        out += "<List MarkerStyle=\"\(l.marker.rawValue)\""
        if let m = l.margin { out += " Margin=\"\(thickness(m))\"" }
        out += ">"
        for item in l.items {
            out += "<ListItem>"
            writeParagraph(item.paragraph, into: &out)
            if let n = item.nested { writeList(n, into: &out) }
            out += "</ListItem>"
        }
        out += "</List>"
    }

    /// WPF numeric text: whole values without a fraction, otherwise the shortest round-trip form.
    static func number(_ d: Double) -> String {
        if d.rounded() == d, abs(d) < 1e15 { return String(Int64(d)) }
        return String(d)
    }

    static func thickness(_ t: SireThickness) -> String {
        "\(number(t.left)),\(number(t.top)),\(number(t.right)),\(number(t.bottom))"
    }

    /// Element content: `&`, `<`, `>` escaped; everything else (incl. LF) verbatim under `xml:space="preserve"`.
    static func escapeText(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for ch in s.unicodeScalars {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\r": out += "&#xD;"
            default: out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    static func escapeAttribute(_ s: String) -> String {
        var out = ""
        for ch in s.unicodeScalars {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "\n": out += "&#xA;"
            case "\r": out += "&#xD;"
            case "\t": out += "&#x9;"
            default: out.unicodeScalars.append(ch)
            }
        }
        return out
    }
}
