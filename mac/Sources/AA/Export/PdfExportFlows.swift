// Spec: 11 §2.1 PDF-001…007 (item export flow: lock refusal, flush, save panel, busy state, error, auto-open,
//       nothing persisted), §2.2 PDF-010…012 (checklist PDF / Excel), §2.3 PDF-020…027 (saved lists: selection,
//       group, all, list-style prompt every time, save panel, "Open it now?", failure), §6.2 (snapshot on the main
//       actor, render off-main, progress after ~300 ms, NSSavePanel as a sheet, optional Print ⌘P), DEV-09 (flush
//       every editor), DEV-10 (Export All without a selection), DEV-12 (open failures ignored); 06 BUILD-039/040,
//       BUILD-091…096; 04 HIER-092; ARCHITECTURE.md §7.7 (contract), §9.1.
import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

enum SavedListsExportScope { case list(UUID), group(ofList: UUID), all }

@MainActor enum PdfExportFlows {
    // MARK: Item PDF (product A) and Print

    static func exportItem(itemID: UUID, env: AppEnvironment, dialogs: DialogPresenter) async {
        guard let item = env.store.item(id: itemID) else { return }
        guard await prepareItemExport(item, env: env, dialogs: dialogs) else { return }
        let config = SavePanelConfig(title: PdfExport.itemSaveTitle,
                                     defaultName: PdfExport.itemFileName(kind: item.kind, name: item.name),
                                     allowedTypes: [.pdf])
        guard let url = await dialogs.savePanel(config) else { return }                 // cancel → silent
        guard let live = env.store.item(id: itemID) else { return }                        // re-resolve (§2.4)
        let snapshot = PdfSnapshotBuilder.item(live, store: env.store, isGated: env.locks.isGated)
        let stamp = PdfScaffold.stamp(env.clock.now())
        let result = await runBusy(dialogs, text: PdfExport.busyText) {
            try PdfExport.write(PdfExport.itemPDF(snapshot, stamp: stamp), to: url)
        }
        switch result {
        case .failure(let error):
            await dialogs.error(PdfExport.exportErrorTitle, PdfExport.itemFailurePrefix + error.localizedDescription)
        case .success:
            NSWorkspace.shared.open(url)                                                    // PDF-006: errors ignored
        }
    }

    /// Mac addition (11 §6.2): the same PDF built in memory and printed at 100 %.
    static func printItem(itemID: UUID, env: AppEnvironment, dialogs: DialogPresenter) async {
        guard let item = env.store.item(id: itemID) else { return }
        guard await prepareItemExport(item, env: env, dialogs: dialogs) else { return }
        let snapshot = PdfSnapshotBuilder.item(item, store: env.store, isGated: env.locks.isGated)
        let stamp = PdfScaffold.stamp(env.clock.now())
        let title = "\(item.kind.name) - \(item.name)"
        let rendered = await Task.detached(priority: .userInitiated) { PdfExport.itemPDF(snapshot, stamp: stamp) }.value
        guard let pdf = PDFDocument(data: rendered),
              let op = pdf.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleNone, autoRotate: false) else {
            await dialogs.error(PdfExport.exportErrorTitle, PdfExport.itemFailurePrefix + "The document could not be prepared for printing.")
            return
        }
        op.jobTitle = title
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        if let window = dialogs.window ?? NSApp.keyWindow, window.isVisible, window.attachedSheet == nil {
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            op.run()
        }
    }

    /// PDF-002 lock refusal, then PDF-003 / DEV-09: flush every editor and save if dirty.
    private static func prepareItemExport(_ item: HierarchyItem, env: AppEnvironment, dialogs: DialogPresenter) async -> Bool {
        if env.locks.isGated(item) {
            await dialogs.info(PdfExport.lockedTitle, PdfExport.lockedMessage)
            return false
        }
        env.flushAllEditors()
        return await flushIfDirty(env: env)
    }

    /// `_repo.FlushIfDirty()`; a failing disk is reported like any unexpected error (SHELL-001) and stops the export.
    private static func flushIfDirty(env: AppEnvironment) async -> Bool {
        guard env.store.isDirty else { return true }
        do {
            try env.store.save()
            return true
        } catch {
            env.reportError(error, context: "Saving before export")
            return false
        }
    }

    // MARK: Checklist-only exports (products C and D)

    static func exportChecklistPDF(procedureID: UUID, env: AppEnvironment, dialogs: DialogPresenter) async {
        await exportChecklist(procedureID: procedureID, excel: false, env: env, dialogs: dialogs)
    }

    static func exportChecklistXLSX(procedureID: UUID, env: AppEnvironment, dialogs: DialogPresenter) async {
        await exportChecklist(procedureID: procedureID, excel: true, env: env, dialogs: dialogs)
    }

    private static func exportChecklist(procedureID: UUID, excel: Bool, env: AppEnvironment, dialogs: DialogPresenter) async {
        guard let p = env.store.item(id: procedureID) as? Procedure else { return }
        guard await flushIfDirty(env: env) else { return }                                 // PDF-011 (no editor flush)
        let xlsx = UTType(filenameExtension: "xlsx") ?? UTType(importedAs: "org.openxmlformats.spreadsheetml.sheet")
        let config = SavePanelConfig(title: excel ? PdfExport.checklistXlsxSaveTitle : PdfExport.checklistPdfSaveTitle,
                                     defaultName: PdfExport.checklistFileName(procedureName: p.name, excel: excel),
                                     allowedTypes: [excel ? xlsx : .pdf])
        guard let url = await dialogs.savePanel(config) else { return }
        guard let live = env.store.item(id: procedureID) as? Procedure else { return }
        let snapshot = PdfSnapshotBuilder.checklist(live, store: env.store)
        let result = await runBusy(dialogs, text: excel ? PdfExport.busyTextWorkbook : PdfExport.busyText) {
            if excel { try PdfChecklistXlsx.write(snapshot, to: url) }
            else { try PdfExport.write(PdfExport.checklistPDF(snapshot), to: url) }
        }
        switch result {
        case .failure(let error):
            await dialogs.error(PdfExport.exportErrorTitle, PdfExport.checklistFailurePrefix + error.localizedDescription)
        case .success:
            NSWorkspace.shared.open(url)                                                    // PDF-012: errors ignored
        }
    }

    // MARK: Saved lists (product B)

    static func exportSavedLists(_ scope: SavedListsExportScope, env: AppEnvironment, dialogs: DialogPresenter) async {
        env.flushAllEditors()                                       // the latest typing in any open list-item note
        let request: PdfExport.SavedListsScopeRequest
        switch scope {
        case .list(let id): request = .list(id)
        case .group(let id): request = .group(ofList: id)
        case .all: request = .all
        }
        switch PdfExport.savedListsSelection(request, data: env.store.data) {
        case .needSelection:
            await dialogs.info(PdfExport.needSelectionTitle, PdfExport.needSelectionMessage)
        case .noSavedLists:
            await dialogs.info(PdfExport.infoTitle, PdfExport.noSavedListsMessage)
        case .entries(let title, let entries):
            await exportSavedLists(title: title, entries: entries, env: env, dialogs: dialogs)
        }
    }

    private static func exportSavedLists(title: String, entries: [PdfSavedListEntry], env: AppEnvironment,
                                         dialogs: DialogPresenter) async {
        if entries.isEmpty {                                                               // PDF-026
            await dialogs.info(PdfExport.infoTitle, PdfExport.nothingToExportMessage)
            return
        }
        guard let numbered = await askListStyle(entryCount: entries.count, dialogs: dialogs) else { return }
        let config = SavePanelConfig(title: PdfExport.savedListsSaveTitle,
                                     defaultName: PdfExport.savedListsFileName(title: title), allowedTypes: [.pdf])
        guard let url = await dialogs.savePanel(config) else { return }
        let stamp = PdfScaffold.stamp(env.clock.now())
        let result = await runBusy(dialogs, text: PdfExport.busyText) {
            try PdfExport.write(PdfExport.savedListsPDF(title: title, entries: entries, numbered: numbered, stamp: stamp),
                                to: url)
        }
        switch result {
        case .failure(let error):
            await dialogs.error(PdfExport.failedTitle, PdfExport.failedMessage(error.localizedDescription))
        case .success:
            let choice = await dialogs.alert(AlertSpec(
                title: PdfExport.completeTitle, message: PdfExport.completeMessage(path: url.path), style: .informational,
                buttons: [AlertButton(title: "Open", role: .default), AlertButton(title: "Not Now", role: .cancel),
                          AlertButton(title: "Show in Finder")]))
            switch choice {
            case 0: NSWorkspace.shared.open(url)                                          // DEV-12: failures ignored
            case 2: NSWorkspace.shared.activateFileViewerSelecting([url])
            default: break
            }
        }
    }

    /// PDF-023: asked every time, bullets preselected, never remembered; nil = cancelled (before the save panel).
    static func askListStyle(entryCount: Int, dialogs: DialogPresenter) async -> Bool? {
        var result: Bool?
        await dialogs.presentSheet(.decision) { dismiss in
            PdfListStyleSheet(prompt: PdfExport.listStylePrompt(entryCount: entryCount)) { numbered in
                result = numbered
                dismiss()
            }
        }
        return result
    }

    // MARK: Busy state (PDF-005: replaces the wait cursor; shown only after ~300 ms)

    private static func runBusy(_ dialogs: DialogPresenter, text: String,
                                _ work: @escaping @Sendable () throws -> Void) async -> Result<Void, Error> {
        let state = PdfBusyState()
        Task { @MainActor in
            defer { state.indicatorClosed = true }
            try? await Task.sleep(for: .milliseconds(300))
            guard !state.finished else { return }
            await dialogs.presentSheet(.decision) { dismiss in PdfBusySheet(text: text, state: state, dismiss: dismiss) }
        }
        let result: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
            do { try work(); return .success(()) } catch { return .failure(error) }
        }.value
        state.finished = true
        // Let the busy sheet close before the result alert attaches (bounded, so a vanished window never hangs).
        for _ in 0..<60 where !state.indicatorClosed { try? await Task.sleep(for: .milliseconds(50)) }
        return result
    }
}

/// Completion flag the busy sheet observes.
@MainActor @Observable final class PdfBusyState {
    var finished = false
    /// The indicator task has ended (never shown, or shown and dismissed).
    var indicatorClosed = false
}

/// The indeterminate progress sheet of a running export.
struct PdfBusySheet: View {
    let text: String
    let state: PdfBusyState
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: AASpacing.m) {
            ProgressView().controlSize(.small)
            Text(text).font(.system(size: AAType.body))
        }
        .padding(.horizontal, AASpacing.xl)
        .padding(.vertical, AASpacing.l)
        .frame(minWidth: 260)
        .onAppear { if state.finished { dismiss() } }
        .onChange(of: state.finished) { _, done in if done { dismiss() } }
        .accessibilityLabel(text)
        .aaSheet(.decision)
    }
}
