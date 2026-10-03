// TV: 01 §6.6 (Windows-safe names MUST: a bundle made on the Mac is extracted on Windows), DATA-043…045 (smart import),
//     DATA-058 (shared import), DATA-041 (export). Round-2 finding V2-COMPAT (foreign bundle names re-exported as is).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite("W-PERSIST bundles: names Windows cannot create are renamed on import", .serialized)
struct PersistWindowsSafeImportTests {
    private let stamp = NetDateTime(parsing: "2026-09-29T11:15:29.9876543+03:00")!

    /// The V2-COMPAT bundle: data.json referencing each attachment, plus a safe file whose name the colon rename
    /// would otherwise take.
    private func foreignBundle(_ ds: DataStore) throws -> (TempFolder, URL) {
        let t = TempFolder("persist-winreserved")
        let url = t.file("winreserved.zip")
        let d = AppData()
        let e = Equipment(name: "Foreign")
        e.container.files = [
            FileItem(name: "colon", path: "files/abc_a:b.pdf"),
            FileItem(name: "trail", path: #"files\abc_trail. "#),
            FileItem(name: "device", path: "files/CON.txt"),
            FileItem(name: "plain", path: "files/abc_CON"),
            FileItem(name: "taken", path: "files/abc_a_b.pdf"),
            FileItem(name: "web", path: "https://example.com/a:b.pdf", isLink: true),
        ]
        d.equipment = [e]
        d.lastModified = stamp
        try PersistZip.make(url, [
            ("data.json", try ds.serializeForSave(d)),
            ("files/abc_a:b.pdf", Data("colon".utf8)),
            ("files/abc_trail. ", Data("trail".utf8)),
            ("files/CON.txt", Data("device".utf8)),
            ("files/abc_CON", Data("plain".utf8)),
            ("files/abc_a_b.pdf", Data("taken".utf8)),
        ])
        return (t, url)
    }

    private let expectedListing = ["abc_a_b_2.pdf": 5, "abc_trail": 5, "_CON.txt": 6, "abc_CON": 5, "abc_a_b.pdf": 5]
    private let expectedPaths = ["files/abc_a_b_2.pdf", "files/abc_trail", "files/_CON.txt", "files/abc_CON",
                                 "files/abc_a_b.pdf", "https://example.com/a:b.pdf"]

    @Test("Smart import renames illegal leaves, repoints the data, and the re-export is Windows-legal")
    func smartImportThenExport() throws {
        let made = StoreFactory.make()
        let ds = made.dataStore
        let (t, url) = try foreignBundle(ds); _ = t
        #expect(try BundleService.importBundleSmart(ds, from: url) == .withAttachments)
        #expect(persistListing(ds.filesFolder) == expectedListing)
        let files = ds.load().equipment[0].container.files
        #expect(files.map(\.path) == expectedPaths)
        #expect(try Data(contentsOf: ds.filesFolder.appending(path: "abc_a_b_2.pdf")) == Data("colon".utf8))
        #expect(try Data(contentsOf: ds.filesFolder.appending(path: "abc_a_b.pdf")) == Data("taken".utf8))
        // Every attachment resolves to a file that exists.
        for f in files where !f.isLink {
            #expect(FileManager.default.fileExists(atPath: AttachmentStore.resolveFilePath(ds, stored: f.path)), "\(f.path)")
        }
        // Importing the same bundle again sees matching attachments (names compared after the rename).
        #expect(try BundleService.importBundleSmart(ds, from: url) == .dataOnly)
        #expect(ds.load().equipment[0].container.files.map(\.path) == expectedPaths)
        // The re-export carries no name Windows cannot create.
        let out = t.file("re-export.zip")
        try BundleService.exportFolderToZipSync(ds, to: out, includeAttachments: true)
        let leaves = try PersistZip.names(out).filter { $0.hasPrefix("files/") }.map { String($0.dropFirst(6)) }
        #expect(Set(leaves) == Set(expectedListing.keys))
        #expect(!leaves.contains(where: PersistBundleIO.isWindowsIllegalLeaf))
    }

    @Test("Shared import applies the same renames")
    func sharedImport() throws {
        let made = StoreFactory.make()
        let ds = made.dataStore
        let (t, url) = try foreignBundle(ds); _ = t
        try BundleService.importSharedBundle(ds, from: url)
        #expect(persistListing(ds.filesFolder) == expectedListing)
        #expect(ds.load().equipment[0].container.files.map(\.path) == expectedPaths)
    }

    @Test("Windows-illegal leaf predicate (01 §6.6)")
    func predicate() {
        for bad in ["a:b.pdf", "a?.txt", "x\u{1}y", "trail.", "trail ", "CON", "con.txt", "LPT9.log", "a|b", "a*b", "a\"b", "a<b>"] {
            #expect(PersistBundleIO.isWindowsIllegalLeaf(bad), "\(bad)")
        }
        for ok in ["abc_CON", "COM10.txt", "3f25_manual.pdf", "é.pdf", ".hidden", "a b.pdf"] {
            #expect(!PersistBundleIO.isWindowsIllegalLeaf(ok), "\(ok)")
        }
    }
}
