// Spec: 11 PDF-001 (Export PDF… caption + tooltip), PDF-010 (Export checklist (PDF) / (Excel) captions + tooltips),
//       PDF-020…022 (Saved Lists buttons + list context-menu item), §6.2 (SF Symbols: item `arrow.up.doc`,
//       checklist PDF `list.bullet.rectangle.portrait`, Excel `tablecells`, saved lists `doc.on.doc`), §6.6
//       (accessibility label = caption); ARCHITECTURE.md §8.5 (a Windows caption emoji becomes the SF Symbol).
// The single source of truth for every export control's caption, tooltip and symbol. The hosting views (W-HIER
// header, W-BUILD Procedure Specifics / Saved Lists tab) own the layout, enablement and action wiring and read
// their labels from here, so no export caption or symbol is hard-coded twice.
import Foundation

public enum PdfExportCommand: String, CaseIterable, Sendable {
    /// Item header button "Export PDF…" (PDF-001).
    case item
    /// Procedure ▸ Specifics "Export checklist (PDF)" (PDF-010).
    case checklistPDF
    /// Procedure ▸ Specifics "Export checklist (Excel)" (PDF-010).
    case checklistXLSX
    /// Saved Lists detail button "Export this list (PDF)…" (PDF-020).
    case savedList
    /// Saved Lists row context-menu item "Export this list (PDF)…" (PDF-020; the Windows menu text has no emoji).
    case savedListMenu
    /// Saved Lists detail button "Export group (PDF)…" (PDF-021).
    case savedGroup
    /// Saved Lists "Export ALL (PDF)…" (PDF-022; DEV-10: available without a selection).
    case savedAll

    /// The visible caption. The 📄 of the Windows Saved Lists captions is carried by the SF Symbol instead.
    public var title: String {
        switch self {
        case .item: PdfExport.exportButtonTitle
        case .checklistPDF: PdfExport.checklistPdfButton
        case .checklistXLSX: PdfExport.checklistXlsxButton
        case .savedList: Self.stripEmoji(PdfExport.exportListButton)
        case .savedListMenu: PdfExport.exportListMenu
        case .savedGroup: Self.stripEmoji(PdfExport.exportGroupButton)
        case .savedAll: Self.stripEmoji(PdfExport.exportAllButton)
        }
    }

    /// The Windows tooltip, where the control has one (the Saved Lists buttons have none).
    public var help: String? {
        switch self {
        case .item: PdfExport.exportButtonHelp
        case .checklistPDF: PdfExport.checklistPdfHelp
        case .checklistXLSX: PdfExport.checklistXlsxHelp
        case .savedList, .savedListMenu, .savedGroup, .savedAll: nil
        }
    }

    /// The §6.2 SF Symbol.
    public var symbol: String {
        switch self {
        case .item: "arrow.up.doc"
        case .checklistPDF: "list.bullet.rectangle.portrait"
        case .checklistXLSX: "tablecells"
        case .savedList, .savedListMenu, .savedGroup, .savedAll: "doc.on.doc"
        }
    }

    /// The VoiceOver label (§6.6: the caption).
    public var accessibilityLabel: String { title }

    static func stripEmoji(_ caption: String) -> String {
        caption.hasPrefix("\u{1F4C4} ") ? String(caption.dropFirst(2)) : caption
    }
}
