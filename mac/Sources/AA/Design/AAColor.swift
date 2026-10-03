// Spec: 03 §6.6.1 (tokens), §6.6.3 (semantic colours), SHELL-150/153/159, DECISIONS 03 Q-1 (light muted/border →
//       secondaryLabel/separator), DECISIONS 07 Q-10 (per-kind colours); ARCHITECTURE.md §8.2.
import AppKit
import SwiftUI
import AACore

/// Asset-free dynamic colour tokens that follow the effective appearance (`NSApp.appearance`).
enum AAColor {
    // MARK: Helpers

    /// A dynamic `NSColor` resolved on the effective appearance.
    static func dynamicNS(_ name: String, light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: NSColor.Name("aa." + name)) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    static func hex(_ s: String) -> NSColor {
        let c = WpfColor.parse(s) ?? ARGB(r: 0, g: 0, b: 0)
        return ns(c)
    }

    static func ns(_ c: ARGB) -> NSColor {
        NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: CGFloat(c.a) / 255)
    }

    static func color(_ c: ARGB) -> Color { Color(nsColor: ns(c)) }

    static func dyn(_ name: String, _ light: String, _ dark: String) -> Color {
        Color(nsColor: dynamicNS(name, light: hex(light), dark: hex(dark)))
    }

    // MARK: Tokens (§8.2)

    enum NS {
        static let bg = AAColor.dynamicNS("bg", light: AAColor.hex("#FFFFFF"), dark: AAColor.hex("#1E1E1E"))
        static let panel = AAColor.dynamicNS("panel", light: AAColor.hex("#FFFFFF"), dark: AAColor.hex("#252526"))
        static let panelAlt = AAColor.dynamicNS("panelAlt", light: AAColor.hex("#FFFFFF"), dark: AAColor.hex("#2D2D30"))
        static let accent = AAColor.dynamicNS("accent", light: AAColor.hex("#000000"), dark: AAColor.hex("#FFFFFF"))
        static let fg = AAColor.dynamicNS("fg", light: AAColor.hex("#000000"), dark: AAColor.hex("#F0F0F0"))
        static let muted = AAColor.dynamicNS("muted", light: .secondaryLabelColor, dark: AAColor.hex("#B0B0B0"))
        static let border = AAColor.dynamicNS("border", light: .separatorColor, dark: AAColor.hex("#3F3F46"))
        static let hover = AAColor.dynamicNS("hover", light: AAColor.hex("#EFEFEF"), dark: AAColor.hex("#3A3A3D"))
        static let selectionBg = AAColor.dynamicNS("selBg", light: AAColor.hex("#CCE8FF"), dark: AAColor.hex("#094771"))
        static let selectionFg = AAColor.dynamicNS("selFg", light: AAColor.hex("#000000"), dark: AAColor.hex("#FFFFFF"))
        static let editorPaper = AAColor.hex("#FCFCFC")
        static let editorInk = AAColor.hex("#1A1A1A")
        static let tint = AAColor.dynamicNS("tint", light: AAColor.hex("#1E88E5"), dark: AAColor.hex("#4AA3F0"))
    }

    static let bg = Color(nsColor: NS.bg)
    static let panel = Color(nsColor: NS.panel)
    static let panelAlt = Color(nsColor: NS.panelAlt)
    static let accent = Color(nsColor: NS.accent)
    static let accentHover = dyn("accentHover", "#000000", "#CCCCCC")
    static let fg = Color(nsColor: NS.fg)
    static let muted = Color(nsColor: NS.muted)
    static let border = Color(nsColor: NS.border)
    static let hover = Color(nsColor: NS.hover)
    static let selectionBg = Color(nsColor: NS.selectionBg)
    static let selectionFg = Color(nsColor: NS.selectionFg)
    static let editorPaper = Color(nsColor: NS.editorPaper)
    static let editorInk = Color(nsColor: NS.editorInk)
    static let tint = Color(nsColor: NS.tint)

    /// Semantic fixed colours (§8.2, 03 §6.6.3).
    enum Status {
        static let danger = Color(nsColor: AAColor.hex("#D45050"))
        static let sharedOK = Color(nsColor: AAColor.hex("#3CA05A"))
        static let ok = Color(nsColor: AAColor.hex("#2E9E5B"))
        static let dueSoon = Color(nsColor: AAColor.hex("#E8890C"))
        static let warning = Color(nsColor: AAColor.hex("#C9A227"))
        static let neutral = Color(nsColor: AAColor.hex("#8A8A8A"))
        static let overdue = Color(nsColor: AAColor.hex("#E53935"))
        static let overdueMeta = AAColor.dyn("overdueMeta", "#D32F2F", "#EF5350")
        static let diffAdded = AAColor.dyn("diffAdded", "#2E7D32", "#66BB6A")
        static let diffChanged = AAColor.dyn("diffChanged", "#EF6C00", "#FFA726")
        static let diffRemoved = AAColor.dyn("diffRemoved", "#C62828", "#EF5350")
        static let boardMuted = Color(nsColor: AAColor.hex("#6B6B6B"))
        static let searchHighlight = Color(nsColor: AAColor.hex("#FFE066"))
        /// DATA value (rich-text lock sentinel) — used only by the editor.
        static let lockSentinel = Color(nsColor: AAColor.hex("#FFE699"))
        static let crewAccent = Color(nsColor: AAColor.hex("#9C6ADE"))
        static let floatingOverdue = Color(nsColor: AAColor.hex("#E05252"))
        static let floatingHeaderStart = Color(nsColor: AAColor.hex("#3A7BD5"))
        static let floatingHeaderEnd = Color(nsColor: AAColor.hex("#00A88E"))
        static let floatingTint = Color(nsColor: AAColor.hex("#EAF6FF"))
        static let sireAmber = Color(nsColor: AAColor.hex("#F0A030"))
        static let hyperlinkGrey = Color(nsColor: AAColor.hex("#9AA0A6"))
        static let plannerMuted = Color(nsColor: AAColor.hex("#6B7785"))
        static let plannerGrid = Color(nsColor: AAColor.hex("#22808080"))
        static let plannerBlock = Color(nsColor: AAColor.hex("#1E88E5"))
        static let defaultCard = Color(nsColor: AAColor.hex("#1E88E5"))
        static let splashBorder = Color(nsColor: AAColor.hex("#DDDDDD"))
    }

    // MARK: Per-kind colours (DECISIONS 07 Q-10)

    /// Pastel fill, identical in both appearances (black text on top, `border` stroke).
    static func kind(_ kind: ItemKind) -> Color {
        switch kind {
        case .task: return Color(nsColor: hex("#FFB74D"))
        case .procedure: return Color(nsColor: hex("#A5D6A7"))
        case .vessel: return Color(nsColor: hex("#CE93D8"))
        default: return Color(nsColor: hex("#4FC3F7"))
        }
    }

    /// Crew item colour.
    static let crewKind = Color(nsColor: hex("#9C6ADE"))

    /// A darker glyph variant on light backgrounds; the fill itself on dark.
    static func kindGlyph(_ kind: ItemKind) -> Color {
        let pair: (String, String)
        switch kind {
        case .task: pair = ("#EF6C00", "#FFB74D")
        case .procedure: pair = ("#388E3C", "#A5D6A7")
        case .vessel: pair = ("#8E24AA", "#CE93D8")
        default: pair = ("#0288D1", "#4FC3F7")
        }
        return dyn("kindGlyph.\(kind.rawValue)", pair.0, pair.1)
    }

    /// A tab's custom colour (theme-independent) and its contrast text colour (SHELL-029).
    static func tabFill(_ hexText: String?) -> (fill: Color, text: Color)? {
        guard let c = ShellTabColor.parse(hexText) else { return nil }
        let opaque = ARGB(a: 255, r: c.r, g: c.g, b: c.b)
        let alpha = Double(c.a) / 255
        return (color(opaque).opacity(alpha), ShellTabColor.textIsBlack(c) ? .black : .white)
    }
}
