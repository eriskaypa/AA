// Spec: 10 VESSEL-101 (Shippalm import: off-main parse, upsert, Save(), status hint, Import failed box, no log),
//       VESSEL-103 (export: empty → Export info, save panel, all jobs in collection order, Export failed, hint, open),
//       VESSEL-201/202/204 (ports import: different-vessel prompt, Apply, activity log, Save(), hint), VESSEL-205
//       (ports export), VESSEL-021…025 (quick-card add / edit / duplicate / delete / open), §1.4 persistence triggers,
//       §3.5 (save failures → the app's standard error UI), VESSEL-318 (Mac-only formula hint), VESSEL-331,
//       X.7.3 (open panel with an Excel / All files pop-up); DECISIONS 10 Q4/Q6; ARCHITECTURE.md §9.1, §9.4.
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

/// The vessel flows shared by the panels and the Tools ▸ Vessel menu (VesselActions).
@MainActor enum VesselFlows {
    // MARK: Persistence (§1.4)

    /// `MarkDirty()` + `FlushIfDirty()` — an immediate synchronous save (quick cards, master switch).
    static func saveNow(_ env: AppEnvironment) {
        env.store.markDirty()
        do { try env.store.flushIfDirty() } catch { env.reportError(error, context: "Saving the data file") }
    }

    /// `Save()` — always writes (bulk work-order actions, deletions, imports).
    static func save(_ env: AppEnvironment) {
        do { try env.store.save() } catch { env.reportError(error, context: "Saving the data file") }
    }

    // MARK: Work orders (VESSEL-101, VESSEL-103)

    /// `file` = a workbook dropped from Finder (X.7.3); nil shows the open panel. Both go through the same gate.
    static func importWorkOrders(vesselID: UUID, env: AppEnvironment, dialogs: DialogPresenter, file: URL? = nil) async {
        guard let vessel = env.store.vessel(id: vesselID) else { return }
        let session = VesselSessionState.shared
        guard !session.busyWorkOrders.contains(vesselID) else { return }
        var picked = file
        if picked == nil {
            picked = await dialogs.openPanel(OpenPanelConfig(message: WorkOrderAnalysis.importDialogTitle(vessel.name),
                                                             allowedTypes: [.xlsx], allFilesAccessory: true)).first
        }
        guard let url = picked else { return }
        session.setBusy(workOrders: vesselID, true)
        defer {
            session.setBusy(workOrders: vesselID, false)
            session.bump()
        }
        let now = env.clock.now(), today = env.clock.today(), zone = env.clock.timeZone
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try WorkOrderShippalmReader.read(url: url, now: now, today: today, zone: zone)
            }.value
            guard let live = env.store.vessel(id: vesselID) else {
                await dialogs.warning("Import failed", "The vessel was removed while the file was being read.")
                return
            }
            let up = WorkOrderAnalysis.upsert(into: live, parsed: result.jobs.map { $0.makeJob() })
            try env.store.save()
            var hint = WorkOrderAnalysis.importedHint(count: result.jobs.count, vessel: live.name, added: up.added,
                                                      updated: up.updated)
            if result.uncachedFormulaCount > 0 { hint += " " + XlsxRender.uncachedFormulaHint(count: result.uncachedFormulaCount) }
            env.status.post(hint)
        } catch {
            await dialogs.error("Import failed", "Could not import the Shippalm file:\n\n\(error.localizedDescription)")
        }
    }

    static func exportWorkOrders(vesselID: UUID, env: AppEnvironment, dialogs: DialogPresenter) async {
        guard let vessel = env.store.vessel(id: vesselID) else { return }
        if vessel.jobs.isEmpty {
            await dialogs.info("Export", WorkOrderAnalysis.exportEmptyMessage)
            return
        }
        guard let url = await dialogs.savePanel(SavePanelConfig(title: WorkOrderAnalysis.exportDialogTitle(vessel.name),
                                                                message: WorkOrderAnalysis.exportDialogTitle(vessel.name),
                                                                defaultName: VesselText.workOrdersExportName(vessel.name),
                                                                allowedTypes: [.xlsx])) else { return }
        let jobs = vessel.jobs
        do {
            try WorkOrderShippalmReader.write(jobs, to: url)
        } catch {
            await dialogs.error("Export failed", "Could not export:\n\n\(error.localizedDescription)")
            return
        }
        env.status.post(WorkOrderAnalysis.exportedHint(count: jobs.count, vessel: vessel.name))
        NSWorkspace.shared.open(url)                                  // a failure to open is ignored (VESSEL-103)
    }

    // MARK: Ports (VESSEL-201…205, VESSEL-209)

    /// `file` = a workbook dropped from Finder (X.7.3); nil shows the open panel. Both go through the same gate and
    /// the same different-vessel confirmation.
    static func importPorts(vesselID: UUID, env: AppEnvironment, dialogs: DialogPresenter, file: URL? = nil) async {
        guard let vessel = env.store.vessel(id: vesselID) else { return }
        let session = VesselSessionState.shared
        guard !session.busyPorts.contains(vesselID) else { return }
        var picked = file
        if picked == nil {
            picked = await dialogs.openPanel(OpenPanelConfig(message: PortsAnalysis.importDialogTitle(vessel.name),
                                                             allowedTypes: [.xlsx], allFilesAccessory: true)).first
        }
        guard let url = picked else { return }
        session.setBusy(ports: vesselID, true)
        defer {
            session.setBusy(ports: vesselID, false)
            session.bump()
        }
        let now = env.clock.now(), today = env.clock.today(), zone = env.clock.timeZone
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try PortCallReader.read(url: url, now: now, today: today, zone: zone)
            }.value
            session.setBusy(ports: vesselID, false)
            guard let live = env.store.vessel(id: vesselID) else {
                await dialogs.warning("Import failed", "The vessel was removed while the file was being read.")
                return
            }
            if PortsAnalysis.needsDifferentVesselConfirmation(fileVessel: result.vesselName, vessel: live.name) {
                let ok = await dialogs.alert(AlertSpec(
                    title: "Different vessel",
                    message: PortsAnalysis.differentVesselMessage(fileVessel: result.vesselName, vessel: live.name,
                                                                  count: result.calls.count),
                    style: .informational,
                    buttons: [AlertButton(title: "Import Anyway", role: .default), AlertButton(title: "Cancel", role: .cancel)]))
                guard ok == 0, let still = env.store.vessel(id: vesselID), still === live else { return }
            }
            let r = PortsService.apply(data: env.store.data, vessel: live, calls: result.calls.map { $0.makePortCall() })
            env.store.logAdded(kind: "Ports import", name: PortsAnalysis.logName(added: r.added, updated: r.updated),
                               detail: PortsAnalysis.logDetail(vessel: live.name, format: result.format))
            try env.store.save()
            var hint = PortsAnalysis.importedHint(count: result.calls.count, vessel: live.name, added: r.added,
                                                  updated: r.updated, format: result.format, newVisits: r.newVisits)
            if result.uncachedFormulaCount > 0 { hint += " " + XlsxRender.uncachedFormulaHint(count: result.uncachedFormulaCount) }
            env.status.post(hint)
        } catch {
            await dialogs.error("Import failed", "Could not import the ports file:\n\n\(error.localizedDescription)")
        }
    }

    static func exportPorts(vesselID: UUID, env: AppEnvironment, dialogs: DialogPresenter) async {
        guard let vessel = env.store.vessel(id: vesselID) else { return }
        if vessel.portCalls.isEmpty {
            await dialogs.info("Export", PortsAnalysis.exportEmptyMessage)
            return
        }
        guard let url = await dialogs.savePanel(SavePanelConfig(title: PortsAnalysis.exportDialogTitle,
                                                                message: PortsAnalysis.exportDialogTitle,
                                                                defaultName: VesselText.portsExportName(vessel.name),
                                                                allowedTypes: [.xlsx])) else { return }
        do {
            try PortsService.export(vessel, to: url)
        } catch {
            await dialogs.error("Export failed", "Could not export:\n\n\(error.localizedDescription)")
            return
        }
        env.status.post(PortsAnalysis.exportedHint(count: vessel.portCalls.count, vessel: vessel.name))
        NSWorkspace.shared.open(url)
    }

    /// VESSEL-209: selected rows only; confirmation; RemoveCall each; Save(); hint.
    static func deletePortCalls(_ calls: [PortCall], vesselID: UUID, env: AppEnvironment, dialogs: DialogPresenter) async {
        guard let vessel = env.store.vessel(id: vesselID) else { return }
        if calls.isEmpty {
            env.status.post(PortsAnalysis.selectToDeleteHint)
            return
        }
        let ok = await dialogs.confirm("Delete ports", PortsAnalysis.deleteConfirmMessage(count: calls.count, vessel: vessel.name),
                                       confirm: "Delete", destructive: true, defaultIsCancel: true)
        guard ok else { return }
        for c in calls { PortsService.removeCall(data: env.store.data, vessel: vessel, call: c) }
        save(env)
        VesselSessionState.shared.bump()
        env.status.post(PortsAnalysis.deletedHint(count: calls.count))
    }

    // MARK: Quick cards (VESSEL-021…025)

    /// `+ Quick card`: a new card in the editor; only OK appends it and saves.
    static func addQuickCard(vesselID: UUID, env: AppEnvironment, dialogs: DialogPresenter) async {
        guard let vessel = env.store.vessel(id: vesselID) else { return }
        let card = QuickCardLayout.newCard(existingCount: vessel.quickCards.count)
        guard await presentEditor(card, env: env, dialogs: dialogs) else { return }
        guard let live = env.store.vessel(id: vesselID) else {
            await dialogs.warning("Quick card", "The vessel was removed while the card was being edited.")
            return
        }
        live.quickCards.append(card)
        saveNow(env)
        VesselSessionState.shared.bump()
    }

    /// `Edit…`: edits the live card; Cancel restores every field from the snapshot (nothing saved).
    static func editQuickCard(_ card: QuickCard, vesselID: UUID, env: AppEnvironment, dialogs: DialogPresenter) async {
        let snapshot = card.clone()
        let ok = await presentEditor(card, env: env, dialogs: dialogs)
        if ok {
            if env.store.vessel(id: vesselID)?.quickCards.contains(where: { $0 === card }) == true {
                saveNow(env)
            } else {
                await dialogs.warning("Quick card", "This quick card no longer exists (the data was reloaded).")
            }
        } else {
            card.copy(from: snapshot)
        }
        VesselSessionState.shared.bump()
    }

    static func presentEditor(_ card: QuickCard, env: AppEnvironment, dialogs: DialogPresenter) async -> Bool {
        var result = false
        await dialogs.presentSheet(.decision) { dismiss in
            QuickCardEditorSheet(card: card) { ok in
                result = ok
                dismiss()
            }
            .environment(env)
        }
        return result
    }

    /// VESSEL-023: new Id, +24/+24, appended (drawn on top), saved.
    static func duplicateQuickCard(_ card: QuickCard, vesselID: UUID, env: AppEnvironment) {
        guard let vessel = env.store.vessel(id: vesselID) else { return }
        vessel.quickCards.append(QuickCardLayout.duplicate(card))
        saveNow(env)
        VesselSessionState.shared.bump()
    }

    /// VESSEL-024: confirmation; the imported file is deliberately left in `files/`.
    static func deleteQuickCard(_ card: QuickCard, vesselID: UUID, env: AppEnvironment, dialogs: DialogPresenter) async {
        let ok = await dialogs.confirm("Confirm", QuickCardLayout.deletePrompt(title: card.title, icon: card.icon),
                                       confirm: "Delete", destructive: true, defaultIsCancel: true)
        guard ok, let vessel = env.store.vessel(id: vesselID) else { return }
        vessel.quickCards.removeAll { $0 === card }
        saveNow(env)
        VesselSessionState.shared.bump()
    }

    /// VESSEL-025 through `AttachmentOpener` (path mapping for Windows paths, `smb://` for UNC, ARCH §9.4).
    static func openQuickCard(_ card: QuickCard, env: AppEnvironment, dialogs: DialogPresenter) async {
        if NetText.isBlank(card.target) {
            await dialogs.info(QuickCardLayout.noTargetTitle, QuickCardLayout.noTargetMessage)
            return
        }
        switch AttachmentOpener.open(stored: card.target, isLink: card.isLink, dataStore: env.dataStore) {
        case .opened:
            break
        case .notFound(let path):
            await dialogs.warning(QuickCardLayout.openFailedTitle, "Not found:\n\(path)")
        case .windowsPathUnmapped(let path):
            let choice = await dialogs.alert(AlertSpec(
                title: QuickCardLayout.openFailedTitle,
                message: "Not found:\n\(path)\n\nThis is a Windows path. Map its drive or server share to a folder on this Mac in Settings ▸ File Links.",
                style: .warning,
                buttons: [AlertButton(title: "OK", role: .default), AlertButton(title: "Open File Links Settings…")]))
            if choice == 1 { env.open(.settings(tab: .fileLinks)) }
        case .failed(let message):
            await dialogs.error(QuickCardLayout.openFailedTitle, message)
        }
    }

    /// Quick Look of a file card (Mac enhancement, 10 §6.2) — web links have nothing to preview.
    static func quickLook(_ card: QuickCard, env: AppEnvironment) {
        guard !card.isLink, !NetText.isBlank(card.target),
              let url = AttachmentOpener.url(forStored: card.target, isLink: false, dataStore: env.dataStore) else { return }
        QuickLookCoordinator.shared.preview([url])
    }
}

/// Finder drops of a workbook onto the Work Orders / Ports panels (10 X.7.3, additive): the first file URL starts the
/// same import as the toolbar button (the VESSEL-301 extension gate decides what is accepted).
@MainActor enum VesselWorkbookDrop {
    static func handle(_ providers: [NSItemProvider], perform: @escaping @MainActor (URL) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) })
        else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in perform(url) }
        }
        return true
    }
}

/// The drop highlight of a panel accepting a workbook (system accent, X.7.3).
struct VesselDropHighlight: View {
    let active: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: AARadius.control, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: 2)
            .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
            .opacity(active ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: active)
            .allowsHitTesting(false)
    }
}
