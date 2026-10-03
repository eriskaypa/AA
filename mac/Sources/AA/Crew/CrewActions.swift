// Spec: 09 CREW-003/004 (Tools menu rows → select Crew first; F3's router does that), §D CREW-030…040 (pick → read
//       off-main → learn → ask (DECISIONS 09 Q1/Q2) → convert → upsert (Q3) → log → Save → refresh → status → dates log →
//       post-import expiry report; any failure → "Import failed"), CREW-017 (selection after the import = the
//       roster's own reconcile), CREW-050 (contract expiries report), §6.4 (busy
//       overlay instead of the wait cursor, three explicit buttons for the date-order question); 03 SHELL-097/098;
//       01 DATA-174 (disabled in a read-only copy / while editing is
//       stopped); ARCHITECTURE.md §2.2 (XLSX parse off the main actor over Sendable values), §7.7.
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

@MainActor enum CrewActions {
    /// 01 DATA-174: the crew import is disabled in a read-only copy of AA and while editing is stopped (DATA-180) —
    /// the same predicate as the Tools-menu row (`CommandRouterCore.readOnlyDisabled` ∋ `.importCompasCrew`).
    static func importGated(_ env: AppEnvironment) -> Bool {
        env.isReadOnlyInstance || env.dataFileGuard?.state.mode == .stoppedEditing
    }

    /// The tooltip of the in-window Import COMPAS… buttons (the DATA-174 text while gated).
    static func importHelp(_ env: AppEnvironment) -> String {
        importGated(env) ? PersistReadOnlyText.disabledHelp : importTooltip
    }

    static let importTooltip = "Import a COMPAS crew report (.xlsx) and keep each member as an info card."

    /// CREW-030…040.
    static func importCompas(env: AppEnvironment, dialogs: DialogPresenter) async {
        let model = CrewRosterModel.shared
        guard !model.importing else { return }
        guard !importGated(env) else {                                  // DATA-174 (buttons are disabled too)
            env.status.post(PersistReadOnlyText.disabledHelp)
            return
        }
        let urls = await dialogs.openPanel(OpenPanelConfig(message: CrewImport.openPanelTitle, allowedTypes: [.xlsx],
                                                           allFilesAccessory: true))
        guard let url = urls.first else { return }                       // Cancel → nothing
        let fileName = url.lastPathComponent
        let now = env.clock.now()
        let today = env.clock.today()
        let zone = env.clock.timeZone
        model.importing = true
        defer { model.importing = false }

        // Read + learn off the main actor (Windows blocked the UI thread).
        let read: Result<CrewImportSession, CrewImportError> = await Task.detached(priority: .userInitiated) {
            do throws(CrewImportError) {
                let sheet = try CrewCompasReader.read(url: url)
                return .success(CrewImportSession(sheet: sheet, fileName: fileName, now: now, today: today, zone: zone))
            } catch {
                return .failure(error)
            }
        }.value

        var session: CrewImportSession
        switch read {
        case .success(let s): session = s
        case .failure(let e):
            await dialogs.error(CrewImport.failedTitle, CrewImport.failureMessage(e.localizedDescription))
            return
        }

        // CREW-033 (DECISIONS 09 Q1: only when a value actually depends on the convention).
        if let q = session.question {
            model.importing = false
            let spec = AlertSpec(title: CrewImportSession.questionTitle,
                                 message: CrewImportSession.questionMessage(q, fileName: fileName),
                                 style: .informational,
                                 buttons: [AlertButton(title: CrewImportSession.dayFirstButton),
                                           AlertButton(title: CrewImportSession.monthFirstButton),
                                           AlertButton(title: CrewImportSession.cancelButton, role: .cancel)],
                                 defaultIndex: 2)                    // CREW-033: default = Cancel (Return and ⎋)
            switch await dialogs.alert(spec) {
            case 0: session.answer(.dayFirst)
            case 1: session.answer(.monthFirst)
            default: return                                           // Cancel → import nothing, no log
            }
            model.importing = true
        }

        session.convertAll()
        let result = CrewImport.apply(session, to: env.store)
        // CREW-036 `Save()`: the roster is already updated, so a failed write is reported like every other save
        // failure (the data stays dirty and is retried) instead of claiming the import itself failed.
        CrewPersist.save(env)
        // CREW-017: the roster's Refresh keeps the selected Key, else selects the FIRST ROW in the roster's current
        // sort order — `CrewRosterModel.reconcile` does that when the rows change (never the first file row).
        model.statusOverride = result.statusText                       // CREW-038
        CrewImport.logDates(result, to: env.store)                     // CREW-037 (autosaved)
        model.importing = false
        await checkExpiries(env: env, dialogs: dialogs, showWhenNone: false)   // CREW-039
    }

    /// CREW-050: the warning list, or (interactive only) the "nothing due" info.
    static func checkExpiries(env: AppEnvironment, dialogs: DialogPresenter, showWhenNone: Bool) async {
        let today = env.clock.today()
        CrewRosterModel.shared.today = today
        let due = CrewExpiry.due(env.store.data.crew, today: today)
        if due.isEmpty {
            if showWhenNone { await dialogs.info(CrewExpiry.reportTitle, CrewExpiry.noneMessage) }
            return
        }
        await dialogs.warning(CrewExpiry.reportTitle, CrewExpiry.reportMessage(due))
    }
}
