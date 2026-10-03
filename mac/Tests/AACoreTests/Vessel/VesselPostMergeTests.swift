// TV: 10 §7.14 ImportFile / ResolveFilePath (Mac) — quick-card imported copies and target resolution go through
//     W-PERSIST's AttachmentStore / AttachmentOpener (ARCHITECTURE.md §6.6, §9.4). Gated on W-PERSIST (§10.5): they
//     are skipped in the W-VESSEL worktree and run in Stage V (OWNERSHIP W-VESSEL post-merge acceptance).
import Foundation
import Testing
@testable import AACore

@Suite("W-VESSEL — quick-card targets through W-PERSIST (post-merge)")
@MainActor struct VesselPostMergeTests {
    // TV: 10 §7.14 ImportFile("/Users/x/Manual v2.pdf") → files/[0-9a-f]{32}_Manual v2.pdf, file present.
    @Test(.enabled(if: ContractStatus.isImplemented(.wPersist)))
    func importCopyLandsInFiles() throws {
        let made = StoreFactory.make()
        let src = TempFolder("aa-vessel-src")
        let url = try src.write("Manual v2.pdf", "%PDF-1.4 test")
        let stored = try AttachmentStore.importFile(made.dataStore, from: url)
        #expect(stored.hasPrefix("files/"))
        let leaf = String(stored.dropFirst("files/".count))
        let hex = leaf.prefix(32)
        #expect(hex.count == 32 && hex.allSatisfy { "0123456789abcdef".contains($0) })
        #expect(leaf.dropFirst(32) == "_Manual v2.pdf")
        #expect(FileManager.default.fileExists(atPath: made.folder.url.appending(path: stored).path))
        let card = QuickCard()
        QuickCardLayout.setTarget(card, stored, kind: .importedCopy)
        #expect(!card.isLink && !card.linkInPlace && !card.isFolder)
    }

    // TV: 10 §7.14 ResolveFilePath (Mac): relative → AppFolder; rooted Windows / UNC / POSIX paths and URLs unchanged.
    @Test(.enabled(if: ContractStatus.isImplemented(.wPersist)))
    func resolveFilePathVectors() {
        let made = StoreFactory.make()
        let ds = made.dataStore
        let resolved = AttachmentStore.resolveFilePath(ds, stored: "files/abc_x.pdf")
        #expect(URL(fileURLWithPath: resolved).standardizedFileURL.path
                == made.folder.url.appending(path: "files/abc_x.pdf").standardizedFileURL.path)
        for s in [#"C:\Docs\x.pdf"#, #"\\srv\sh\x.pdf"#, "/Volumes/sh/x.pdf", "https://a.b", "mailto:a@b.c"] {
            #expect(AttachmentStore.resolveFilePath(ds, stored: s) == s, "\(s)")
        }
    }

    // TV: 10 VESSEL-025 step 3 — a missing imported copy reports "Not found" (never opens anything).
    @Test(.enabled(if: ContractStatus.isImplemented(.wPersist)))
    func missingImportedCopyIsNotFound() {
        let made = StoreFactory.make()
        let outcome = AttachmentOpener.open(stored: "files/00000000000000000000000000000000_gone.pdf", isLink: false,
                                            dataStore: made.dataStore)
        if case .notFound = outcome {} else { Issue.record("expected .notFound, got \(outcome)") }
    }
}
