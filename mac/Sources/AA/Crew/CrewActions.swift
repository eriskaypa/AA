// Spec: 09 CREW-003/004 (Tools menu rows → select Crew first; F3's router does that), §D CREW-030…040 (pick → read
//       off-main → learn → ask (DECISIONS 09 Q1/Q2) → convert → upsert (Q3) → log → Save → refresh → status → dates log →
//       post-import expiry report; any failure → "Import failed"), CREW-050 (contract expiries report), §6.4 (busy
//       overlay instead of the wait cursor, three explicit buttons for the date-order question); 03 SHELL-097/098;
//       ARCHITECTURE.md §2.2 (XLSX parse off the main actor over Sendable values), §7.7.
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

@MainActor enum CrewActions {
    /// CREW-030…040.
    static func importCompas(env: AppEnvironment, dialogs: DialogPresenter) async {
        let model = CrewRosterModel.shared
        guard !model.importing else { return }
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
                                           AlertButton(title: CrewImportSession.cancelButton, role: .cancel)])
            switch await dialogs.alert(spec) {
            case 0: session.answer(.dayFirst)
            case 1: session.answer(.monthFirst)
            default: return                                           // Cancel → import nothing, no log
            }
            model.importing = true
        }

        session.convertAll()
        let result = CrewImport.apply(session, to: env.store)
        do {
            try env.store.save()
        } catch {
            await dialogs.error(CrewImport.failedTitle, CrewImport.failureMessage(error.localizedDescription))
            return
        }
        if let first = result.memberIDs.first, let m = env.store.crewMember(id: first),
           model.selectedID == nil || env.store.crewMember(id: model.selectedID!) == nil {
            model.select(memberID: m.id, key: m.key, clearFilters: false)
        }
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
