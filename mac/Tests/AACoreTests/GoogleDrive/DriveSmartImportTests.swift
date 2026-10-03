// Tests for 14 §7.7 (smart import of a Drive bundle in a temp AppFolder; TOOLS-028/029/032). The vector is W-DRIVE's
// (OWNERSHIP §4 "Vector homes"); the importer is W-PERSIST's `BundleService.importBundleSmart`, so the test is gated
// on `.wPersist` and runs after the merge (ARCHITECTURE.md §10.5).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct DriveSmartImportTests {
    enum FilesEntry { case none, emptyDir, files([String: Int]) }

    private func bundle(_ folder: TempFolder, files: FilesEntry, dataOnlyFlag: Bool = false, withData: Bool = true) throws -> URL {
        let url = folder.url.appending(path: "bundle-\(UUID().uuidString).zip")
        let w = try ZipWriter(url: url)
        if withData {
            let json = Goldens.freshDB.replacingOccurrences(of: #""SchemaVersion":1"#,
                                                            with: #""LastModified":"2026-09-30T11:00:00","SchemaVersion":1"#)
            try w.addData(Data(json.utf8), named: "data.json", modified: nil)
        }
        switch files {
        case .none: break
        case .emptyDir: try w.addDirectory(named: "files/")
        case .files(let m):
            for (name, size) in m.sorted(by: { $0.key < $1.key }) {
                try w.addData(Data(repeating: 1, count: size), named: "files/\(name)", modified: nil)
            }
        }
        let source = #"{"Identity":"Vessel-Alpha","Machine":"BRIDGE-PC","WrittenUtc":"2026-09-30T08:15:30Z","DataOnly":\#(dataOnlyFlag)}"#
        try w.addData(Data(source.utf8), named: "source.json", modified: nil)
        try w.finish()
        return url
    }

    private func local(_ ds: DataStore, _ files: [String: Int]) throws {
        try FileManager.default.createDirectory(at: ds.filesFolder, withIntermediateDirectories: true)
        for (n, s) in files { try Data(repeating: 2, count: s).write(to: ds.filesFolder.appending(path: n)) }
    }

    private func localFiles(_ ds: DataStore) -> [String: Int] {
        var out: [String: Int] = [:]
        for n in (try? FileManager.default.contentsOfDirectory(atPath: ds.filesFolder.path)) ?? [] {
            out[n] = ((try? FileManager.default.attributesOfItem(atPath: ds.filesFolder.appending(path: n).path)[.size]) as? NSNumber)?.intValue
        }
        return out
    }

    // TV: 14 §7.7 table
    @Test(.enabled(if: ContractStatus.isImplemented(.wPersist)))
    func smartImportTable() throws {
        let cases: [(local: [String: Int], bundle: FilesEntry, flag: Bool, kind: ImportKind, after: [String: Int])] = [
            (["a.pdf": 10, "b.png": 20], .files(["a.pdf": 10, "b.png": 20]), false, .dataOnly, ["a.pdf": 10, "b.png": 20]),
            (["a.pdf": 10, "b.png": 20], .files(["a.pdf": 11, "b.png": 20]), false, .withAttachments, ["a.pdf": 11, "b.png": 20]),
            (["a.pdf": 10, "b.png": 20], .files(["a.pdf": 10]), false, .withAttachments, ["a.pdf": 10]),
            (["a.pdf": 10, "b.png": 20], .none, false, .dataOnly, ["a.pdf": 10, "b.png": 20]),
            (["a.pdf": 10, "b.png": 20], .none, true, .dataOnly, ["a.pdf": 10, "b.png": 20]),
            (["a.pdf": 10, "b.png": 20], .emptyDir, false, .withAttachments, [:]),
            (["A.PDF": 10], .files(["a.pdf": 10]), false, .dataOnly, ["A.PDF": 10]),
        ]
        for c in cases {
            let made = StoreFactory.make()
            let ds = made.dataStore
            ds.settings.setAppIdentity("Mac-Bridge")
            ds.settings.setGoogleDriveFolder("/Users/op/My Drive")
            ds.settings.setPassword(hash: "H", salt: "S")
            try local(ds, c.local)
            try Data("{}".utf8).write(to: ds.googleClientSecretFile)
            let work = TempFolder("aa-smart")
            let kind = try BundleService.importBundleSmart(ds, from: try bundle(work, files: c.bundle, dataOnlyFlag: c.flag))
            #expect(kind == c.kind)
            #expect(localFiles(ds) == c.after)
            #expect(ds.currentDataFile.standardizedFileURL == ds.defaultDataFile.standardizedFileURL)
            let settings = String(decoding: try Data(contentsOf: ds.settingsFile), as: UTF8.self)
            #expect(settings.contains(#""PasswordHash":"H""#) && settings.contains(#""AppIdentity":"Mac-Bridge""#))
            #expect(FileManager.default.fileExists(atPath: ds.googleClientSecretFile.path))
            #expect(ds.load().lastModified?.ticks == NetDateTime(parsing: "2026-09-30T11:00:00")!.ticks)
        }
    }

    // TV: 14 §7.7 failure rows (nothing local changes)
    @Test(.enabled(if: ContractStatus.isImplemented(.wPersist)))
    func smartImportFailures() throws {
        let made = StoreFactory.make()
        let ds = made.dataStore
        try local(ds, ["a.pdf": 10])
        let work = TempFolder("aa-smart")
        do {
            _ = try BundleService.importBundleSmart(ds, from: try bundle(work, files: .none, withData: false))
            Issue.record("expected a missing data.json error")
        } catch {
            #expect(error.localizedDescription == "The bundle has no data.json.")
        }
        let corrupt = try work.write("corrupt.zip", "PK\u{3}\u{4} not a zip")
        #expect(throws: (any Error).self) { try BundleService.importBundleSmart(ds, from: corrupt) }
        #expect(localFiles(ds) == ["a.pdf": 10])
    }
}
