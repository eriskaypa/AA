// Spec: 11 PDF-001…007, PDF-010…012, PDF-020…027 (UI flows: exact strings, default file names with the Windows
//       invalid-character set, prompts, messages), §6.2 (render off-main), §7.15; 06 BUILD-039/040, 091…096;
//       04 HIER-092, §3.8 (safe names), §7.9; 05 CONT-049. The AA target's `PdfExportFlows` presents panels and
//       alerts and calls these helpers; everything testable lives here.
import Foundation

public enum PdfExport {
    // MARK: Strings (verbatim Windows texts; Mac captions use the typographic ellipsis, 11 §2)

    public static let exportButtonTitle = "Export PDF\u{2026}"
    public static let exportButtonHelp = "Export this item, its hierarchy and relationships to an A4 PDF."
    public static let lockedTitle = "Locked"
    public static let lockedMessage = "Unlock this entry before exporting it to PDF."
    public static let itemSaveTitle = "Export to PDF"
    public static let exportErrorTitle = "Export error"
    public static let itemFailurePrefix = "Failed to export PDF:\n"
    public static let checklistFailurePrefix = "Failed to export checklist:\n"
    public static let checklistPdfButton = "Export checklist (PDF)"
    public static let checklistPdfHelp = "Export ONLY the checklist (no notes, no relationships) as a printable A4 PDF."
    public static let checklistXlsxButton = "Export checklist (Excel)"
    public static let checklistXlsxHelp = "Export ONLY the checklist as an Excel workbook (.xlsx)."
    public static let checklistPdfSaveTitle = "Export checklist to PDF"
    public static let checklistXlsxSaveTitle = "Export checklist to Excel"
    public static let exportListButton = "\u{1F4C4} Export this list (PDF)\u{2026}"
    public static let exportListMenu = "Export this list (PDF)\u{2026}"
    public static let exportGroupButton = "\u{1F4C4} Export group (PDF)\u{2026}"
    public static let exportAllButton = "\u{1F4C4} Export ALL (PDF)\u{2026}"
    public static let needSelectionTitle = "Saved Lists"
    public static let needSelectionMessage = "Select a saved list first."
    public static let infoTitle = "Export"
    public static let noSavedListsMessage = "No saved lists to export."
    public static let nothingToExportMessage = "Nothing to export."
    public static let savedListsSaveTitle = "Export saved lists to PDF"
    public static let completeTitle = "Export complete"
    public static let failedTitle = "Export failed"
    public static let ungroupedListsTitle = "Ungrouped lists"
    public static let allSavedListsTitle = "All saved lists"
    public static let singleListFallbackTitle = "Saved list"
    public static let busyText = "Exporting PDF\u{2026}"
    public static let busyTextWorkbook = "Exporting workbook\u{2026}"

    /// `Exported to:\n{path}\n\nOpen it now?` (PDF-025).
    public static func completeMessage(path: String) -> String { "Exported to:\n\(path)\n\nOpen it now?" }
    /// `Could not export the PDF:\n\n{message}` (PDF-025, note the blank line).
    public static func failedMessage(_ message: String) -> String { "Could not export the PDF:\n\n\(message)" }

    // MARK: List-style prompt (PDF-023, CONT-049)

    public static let listStyleWindowTitle = "List style"
    public static let listStyleDefaultPrompt = "How should the items be listed?"
    public static let bulletedTitle = "\u{2022} Bulleted"
    public static let bulletedCaption = "Every item marked with a bullet. Best when the order does not matter."
    public static let numberedTitle = "1. Numbered"
    public static let numberedCaption = "Items numbered in order. Best for steps that run in sequence."

    public static func listStylePrompt(entryCount n: Int) -> String {
        n == 1 ? "How should the items in this list be shown in the PDF?"
               : "How should the items in these \(n) lists be shown in the PDF?"
    }

    // MARK: File names (PDF-004, PDF-011, PDF-024; Windows `Path.GetInvalidFileNameChars()` set)

    /// Every Windows-invalid file-name character replaced with `_`; nothing trimmed (HierarchyPage).
    public static func safe(_ name: String) -> String {
        var out = String.UnicodeScalarView()
        for sc in name.unicodeScalars { if WindowsFileName.isInvalid(sc) { out.append("_") } else { out.append(sc) } }
        return String(out)
    }

    /// `{Kind}-{safe}.pdf` with the raw enum name (`Equipment`, not "Equipment/Area").
    public static func itemFileName(kind: ItemKind, name: String) -> String { "\(kind.name)-\(safe(name)).pdf" }

    /// `checklist-{safe}.pdf` / `.xlsx`.
    public static func checklistFileName(procedureName: String, excel: Bool) -> String {
        "checklist-\(safe(procedureName)).\(excel ? "xlsx" : "pdf")"
    }

    /// `Sanitize(title) + ".pdf"`: invalid characters → `_`, whitespace-only → `saved-lists`, else trimmed.
    public static func savedListsFileName(title: String) -> String {
        WindowsFileName.sanitize(title, fallback: "saved-lists") + ".pdf"
    }

    // MARK: Saved-list entry selection (PDF-020…022)

    public enum SavedListsSelection: Sendable, Equatable {
        case needSelection          // "Select a saved list first."
        case noSavedLists           // "No saved lists to export."
        case entries(title: String, [PdfSavedListEntry])
    }

    public enum SavedListsScopeRequest: Sendable, Equatable {
        case list(UUID?), group(ofList: UUID?), all
    }

    /// Resolves a scope to the document title and entries, in the user's arranged order (PDF-027).
    @MainActor
    public static func savedListsSelection(_ scope: SavedListsScopeRequest, data: AppData) -> SavedListsSelection {
        func template(_ id: UUID?) -> ChecklistTemplate? {
            guard let id else { return nil }
            return data.checklistTemplates.first { $0.id == id }
        }
        switch scope {
        case .list(let id):
            guard let t = template(id) else { return .needSelection }
            let title = t.name.isEmpty ? singleListFallbackTitle : t.name
            return .entries(title: title, PdfSnapshotBuilder.savedLists([(template: t, group: nil)]))
        case .group(let id):
            guard let t = template(id) else { return .needSelection }
            if let gid = t.groupId, let grp = data.listGroups.first(where: { $0.id == gid }) {
                let entries = SavedListOrder.groupEntries(data, groupID: gid) ?? []
                return .entries(title: grp.name, PdfSnapshotBuilder.savedLists(entries))
            }
            let entries = SavedListOrder.groupEntries(data, groupID: nil) ?? []
            return .entries(title: ungroupedListsTitle, PdfSnapshotBuilder.savedLists(entries))
        case .all:
            if data.checklistTemplates.isEmpty { return .noSavedLists }
            return .entries(title: allSavedListsTitle, PdfSnapshotBuilder.savedLists(SavedListOrder.allEntries(data)))
        }
    }

    // MARK: Rendering (off the main actor)

    public static func itemPDF(_ s: PdfItemSnapshot, stamp: String, resolver: PdfFontResolver = .system) -> Data {
        PdfRenderer.render(PdfItemBuilder.build(s, stamp: stamp), resolver: resolver)
    }

    public static func checklistPDF(_ s: PdfChecklistSnapshot, resolver: PdfFontResolver = .system) -> Data {
        PdfRenderer.render(PdfChecklistBuilder.build(s), resolver: resolver)
    }

    public static func savedListsPDF(title: String, entries: [PdfSavedListEntry], numbered: Bool, stamp: String,
                                     resolver: PdfFontResolver = .system) -> Data {
        PdfRenderer.render(PdfSavedListsBuilder.build(title: title, entries: entries, numbered: numbered, stamp: stamp),
                           resolver: resolver)
    }

    /// Writes finished bytes to the user's chosen URL (atomic replace; ARCHITECTURE.md §2.1).
    public static func write(_ data: Data, to url: URL) throws {
        try AtomicWrite.write(data, to: url)
    }
}
