// TV: OWNERSHIP W-SHELL post-merge acceptance — "export→import ZIP through the real BundleService" (03 SHELL-070,
//     SHELL-071, SHELL-185; 01 DATA-040, DATA-042, DATA-043) and "shared save set/stop against the real coordinator"
//     (SHELL-066, SHELL-067; DATA-050, DATA-051), exactly the calls `ShellFlows` makes. Gated on W-PERSIST's
//     contract flag (ARCHITECTURE.md §10.5): skipped in the W-SHELL worktree, run in Stage V.
import Foundation
import Testing
@testable import AACore

/// A minimal `SharedSaveHost` (F3's AppEnvironment in the app).
@MainActor private final class ShellXTestSharedHost: SharedSaveHost {
    var statuses: [String] = []
    var reloads = 0
    func flushAllEditors() {}
    func captureUiState() {}
    func confirmReloadDiscardingChanges() async -> Bool { true }
    func reloadAfterSharedImport(identity: String?) { reloads += 1 }
    func postStatus(_ text: String) { statuses.append(text) }
}

@MainActor @Suite struct ShellXPersistIntegrationTests {
    private func sourceStore() throws -> StoreFactory.Made {
        let data = AppData()
        let item = Equipment(name: "Main engine")
        data.equipment.append(item)
        let m = StoreFactory.make(data: data)
        let stored = try AttachmentStore.importData(m.dataStore, Data("Bunker plan".utf8), suggestedName: "bunker plan.txt")
        item.container.files.append(FileItem(name: "bunker plan.txt", path: stored))
        try m.store.save()
        return m
    }

    @Test(.enabled(if: ContractStatus.isImplemented(.wPersist)))
    func exportThenImportDataFolderZip() async throws {
        let src = try sourceStore()
        let out = TempFolder("aa-export")
        let zip = out.file(ShellXText.exportDefaultName(src.store.clock.now()))
        #expect(ShellXDataFlows.exportDestinationAllowed(zip, dataStore: src.dataStore))
        try await BundleService.exportFolderToZip(src.dataStore, to: zip, includeAttachments: true)

        let dst = StoreFactory.make()
        let incoming = try #require(BundleService.peekZipData(zip, dataStore: dst.dataStore))
        #expect(incoming.equipment.map(\.name) == ["Main engine"])
        let kind = try BundleService.importBundleSmart(dst.dataStore, from: zip)
        #expect(kind == .withAttachments)
        #expect(ShellXText.importedBundle(fileName: zip.lastPathComponent, dataOnly: kind == .dataOnly)
                == "Imported \(zip.lastPathComponent) (with attachments)")
        let loaded = dst.dataStore.load()
        #expect(loaded.equipment.map(\.name) == ["Main engine"])
        let stored = try #require(loaded.equipment.first?.container.files.first?.path)
        let resolved = AttachmentStore.resolveFilePath(dst.dataStore, stored: stored)
        #expect(try String(contentsOfFile: resolved, encoding: .utf8) == "Bunker plan")
        #expect(dst.dataStore.currentDataFile == dst.dataStore.defaultDataFile)
    }

    @Test(.enabled(if: ContractStatus.isImplemented(.wPersist)))
    func textOnlyExportImportsAsDataOnly() async throws {
        let src = try sourceStore()
        _ = ShellXDataFlows.setTextOnlyExport(true, settings: src.dataStore.settings)
        let zip = TempFolder("aa-export-text").file("aa-data-text.zip")
        try await BundleService.exportFolderToZip(src.dataStore,
                                                  to: zip, includeAttachments: !src.dataStore.settings.values.textOnlyExport)
        #expect(BundleService.peekBundleSource(zip)?.dataOnly == true)
        let dst = StoreFactory.make()
        let kind = try BundleService.importBundleSmart(dst.dataStore, from: zip)
        #expect(kind == .dataOnly)
        #expect(ShellXText.importedBundle(fileName: "aa-data-text.zip", dataOnly: true)
                == "Imported aa-data-text.zip (text only — your attachments are untouched)")
    }

    @Test(.enabled(if: ContractStatus.isImplemented(.wPersist)))
    func exportIntoTheDataFolderIsRefused() async throws {
        let src = try sourceStore()
        let inside = src.folder.file("backup.zip")
        #expect(!ShellXDataFlows.exportDestinationAllowed(inside, dataStore: src.dataStore))
        await #expect(throws: (any Error).self) {
            try await BundleService.exportFolderToZip(src.dataStore, to: inside, includeAttachments: true)
        }
    }

    @Test(.enabled(if: ContractStatus.isImplemented(.wPersist)))
    func sharedSaveCreateJoinAndStop() async throws {
        let src = try sourceStore()
        let host = ShellXTestSharedHost()
        let coordinator = SharedSaveCoordinator(store: src.store)
        coordinator.host = host
        let shared = TempFolder("aa-shared").file(ShellXText.sharedDefaultName)

        // Create (file absent → push our data + attachments).
        try await coordinator.adoptSharedFile(shared, useItsContents: false)
        #expect(FileManager.default.fileExists(atPath: shared.path))
        #expect(src.dataStore.settings.values.sharedSaveFile == shared.path)
        #expect(BundleService.peekZipData(shared, dataStore: src.dataStore)?.equipment.map(\.name) == ["Main engine"])

        // Join from another copy (file exists → "Use Its Contents").
        let other = StoreFactory.make()
        let otherCoordinator = SharedSaveCoordinator(store: other.store)
        let otherHost = ShellXTestSharedHost()
        otherCoordinator.host = otherHost
        try await otherCoordinator.adoptSharedFile(shared, useItsContents: true)
        #expect(other.dataStore.load().equipment.map(\.name) == ["Main engine"])

        // Stop: the setting is cleared, local data kept.
        coordinator.stopUsing()
        #expect(NetText.isBlank(src.dataStore.settings.values.sharedSaveFile))
        #expect(coordinator.health == .off)
        #expect(src.dataStore.load().equipment.map(\.name) == ["Main engine"])
        otherCoordinator.stopUsing()
    }
}
