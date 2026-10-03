// Spec: 11 PDF-001 (Export PDF… button: caption, tooltip, SF Symbol), PDF-010 (Export checklist (PDF) / (Excel)
//       buttons with captions kept as text), PDF-020…022 (Saved Lists buttons + context-menu item; DEV-10 Export ALL
//       always available), §6.2 SF Symbols, §6.6 (accessibility labels = captions). Ready-made controls the hosting
//       views (W-HIER header, W-BUILD Specifics / Saved Lists) may embed; each calls `PdfExportFlows`.
import SwiftUI
import AACore

/// "Export PDF…" for one item (PDF-001).
struct PdfExportItemButton: View {
    let itemID: UUID
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs

    var body: some View {
        Button {
            Task { @MainActor in await PdfExportFlows.exportItem(itemID: itemID, env: env, dialogs: dialogs) }
        } label: {
            Label(PdfExport.exportButtonTitle, systemImage: "arrow.up.doc")
        }
        .help(PdfExport.exportButtonHelp)
        .accessibilityLabel(PdfExport.exportButtonTitle)
    }
}

/// "Export checklist (PDF)" and "Export checklist (Excel)" (PDF-010).
struct PdfChecklistExportButtons: View {
    let procedureID: UUID
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs

    var body: some View {
        HStack(spacing: AASpacing.s) {
            Button {
                Task { @MainActor in await PdfExportFlows.exportChecklistPDF(procedureID: procedureID, env: env, dialogs: dialogs) }
            } label: {
                Label(PdfExport.checklistPdfButton, systemImage: "list.bullet.rectangle.portrait")
            }
            .help(PdfExport.checklistPdfHelp)
            .accessibilityLabel(PdfExport.checklistPdfButton)
            Button {
                Task { @MainActor in await PdfExportFlows.exportChecklistXLSX(procedureID: procedureID, env: env, dialogs: dialogs) }
            } label: {
                Label(PdfExport.checklistXlsxButton, systemImage: "tablecells")
            }
            .help(PdfExport.checklistXlsxHelp)
            .accessibilityLabel(PdfExport.checklistXlsxButton)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

/// The three Saved Lists export buttons (PDF-020…022). `selectedListID` = the primary selection.
struct PdfSavedListsExportButtons: View {
    let selectedListID: UUID?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs

    var body: some View {
        HStack(spacing: AASpacing.s) {
            button(PdfExport.exportListButton, .list(selectedListID ?? UUID()))
                .disabled(selectedListID == nil)
            button(PdfExport.exportGroupButton, .group(ofList: selectedListID ?? UUID()))
                .disabled(selectedListID == nil)
            button(PdfExport.exportAllButton, .all)                                        // DEV-10: always available
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private func button(_ title: String, _ scope: SavedListsExportScope) -> some View {
        // The 📄 of the Windows caption becomes the SF Symbol (ARCHITECTURE.md §8.5).
        let caption = title.replacingOccurrences(of: "\u{1F4C4} ", with: "")
        return Button {
            Task { @MainActor in await PdfExportFlows.exportSavedLists(scope, env: env, dialogs: dialogs) }
        } label: {
            Label(caption, systemImage: "doc.on.doc")
        }
        .accessibilityLabel(caption)
    }
}

/// The list context-menu entry "Export this list (PDF)…" (PDF-020).
struct PdfSavedListContextMenuItem: View {
    let listID: UUID
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs

    var body: some View {
        Button(PdfExport.exportListMenu) {
            Task { @MainActor in await PdfExportFlows.exportSavedLists(.list(listID), env: env, dialogs: dialogs) }
        }
    }
}
