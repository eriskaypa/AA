// TV: 01 §7.6 (paths), 05 §7 Mac sanitiser / classification / ResolveFilePath vectors, CONT-081, DATA-060…068,
//     DECISIONS 05 (package → one zip entry; pasted bytes).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite("W-PERSIST attachments store")
struct PersistAttachmentStoreTests {
    /// A container holding one file item per stored path.
    private func model(_ paths: [String], isLink: Bool = false, live: Bool = false) -> (AppData, [FileItem]) {
        let d = AppData()
        let e = Equipment(name: "Pump")
        var items: [FileItem] = []
        for p in paths {
            let f = FileItem(name: "x", path: p, kind: .document)
            f.isLink = isLink
            f.linkInPlace = live
            items.append(f)
        }
        e.container.files = items
        d.equipment.append(e)
        return (d, items)
    }

    @Test("01 §7.6 NormalizeFilePaths and MigrateLegacyAbsolutePaths table")
    func pathTable() throws {
        let made = StoreFactory.make()
        let ds = made.dataStore
        try FileManager.default.createDirectory(at: ds.filesFolder, withIntermediateDirectories: true)
        try Data("0123456789".utf8).write(to: ds.filesFolder.appending(path: "ab12_x.pdf"))
        let app = ds.appFolder.standardizedFileURL.path
        let rows: [(String, String, String)] = [
            ("files/ab12_x.pdf", "files/ab12_x.pdf", "files/ab12_x.pdf"),
            (app + "/files/ab12_x.pdf", "files/ab12_x.pdf", "files/ab12_x.pdf"),
            (app.uppercased() + "/FILES/ab12_x.pdf", "FILES/ab12_x.pdf", "FILES/ab12_x.pdf"),
            (#"C:\Users\bob\AppData\Local\AA\files\ab12_x.pdf"#, "files/ab12_x.pdf", "files/ab12_x.pdf"),
            (#"C:\Users\bob\AppData\Local\AA\files\zz_missing.pdf"#, #"C:\Users\bob\AppData\Local\AA\files\zz_missing.pdf"#, "files/zz_missing.pdf"),
            (#"D:\Projects\Files\ab12_x.pdf"#, "Files/ab12_x.pdf", "Files/ab12_x.pdf"),
            (#"\\srv\share\docs\a.xlsx"#, #"\\srv\share\docs\a.xlsx"#, #"\\srv\share\docs\a.xlsx"#),
            (#"C:\docs\a.xlsx"#, #"C:\docs\a.xlsx"#, #"C:\docs\a.xlsx"#),
        ]
        for (stored, normalized, migrated) in rows {
            let (d1, f1) = model([stored])
            AttachmentStore.normalizeFilePaths(ds, data: d1)
            #expect(f1[0].path == normalized, "normalize \(stored)")
            let (d2, f2) = model([stored])
            AttachmentStore.migrateLegacyAbsolutePaths(ds, data: d2)
            #expect(f2[0].path == migrated, "migrate \(stored)")
            for (link, live) in [(true, false), (false, true)] {
                let (d3, f3) = model([stored], isLink: link, live: live)
                AttachmentStore.normalizeFilePaths(ds, data: d3)
                AttachmentStore.migrateLegacyAbsolutePaths(ds, data: d3)
                #expect(f3[0].path == stored)
            }
        }
    }

    @Test("Case 1 is case-insensitive against the Mac AppFolder (01 §7.6 row 3)")
    func caseInsensitiveAppFolder() throws {
        let made = StoreFactory.make()
        let ds = made.dataStore
        let lower = ds.appFolder.standardizedFileURL.path.lowercased() + "/files/ab12_x.pdf"
        let (d, f) = model([lower])
        AttachmentStore.normalizeFilePaths(ds, data: d)
        #expect(f[0].path == "files/ab12_x.pdf")
    }

    @Test("ResolveFilePath vectors (01 §7.6, 05 §7)")
    func resolve() {
        let made = StoreFactory.make()
        let ds = made.dataStore
        let app = ds.appFolder.standardizedFileURL.path
        #expect(AttachmentStore.resolveFilePath(ds, stored: nil) == "")
        #expect(AttachmentStore.resolveFilePath(ds, stored: "") == "")
        #expect(AttachmentStore.resolveFilePath(ds, stored: "https://x.y") == "https://x.y")
        #expect(AttachmentStore.resolveFilePath(ds, stored: "MAILTO:a@b") == "MAILTO:a@b")
        #expect(AttachmentStore.resolveFilePath(ds, stored: "HTTP://X") == "HTTP://X")
        #expect(AttachmentStore.resolveFilePath(ds, stored: "files/ab12_x.pdf") == app + "/files/ab12_x.pdf")
        #expect(AttachmentStore.resolveFilePath(ds, stored: #"files\a.pdf"#) == app + "/files/a.pdf")
        #expect(AttachmentStore.resolveFilePath(ds, stored: "/Volumes/share/a.pdf") == "/Volumes/share/a.pdf")
        #expect(AttachmentStore.resolveFilePath(ds, stored: #"C:\a.pdf"#) == #"C:\a.pdf"#)
        #expect(AttachmentStore.resolveFilePath(ds, stored: #"\\srv\s\a.pdf"#) == #"\\srv\s\a.pdf"#)
    }

    @Test("ImportFile copies to files/<32hex>_<name> with a Windows-safe leaf (01 §7.6, 05 §7)")
    func importFile() throws {
        let made = StoreFactory.make()
        let ds = made.dataStore
        let src = TempFolder("persist-src")
        let pump = try src.write("Pump manual.pdf", "PDF bytes")
        let stored = try AttachmentStore.importFile(ds, from: pump)
        #expect(stored.range(of: #"^files/[0-9a-f]{32}_Pump manual\.pdf$"#, options: .regularExpression) != nil)
        #expect(try Data(contentsOf: ds.appFolder.appending(path: stored)) == Data("PDF bytes".utf8))
        let odd = try src.write("a:b?.pdf", "x")
        let stored2 = try AttachmentStore.importFile(ds, from: odd)
        #expect(stored2.range(of: #"^files/[0-9a-f]{32}_a_b_\.pdf$"#, options: .regularExpression) != nil)
        let con = try src.write("CON.txt", "x")
        let stored3 = try AttachmentStore.importFile(ds, from: con)
        #expect(stored3.range(of: #"^files/[0-9a-f]{32}_CON\.txt$"#, options: .regularExpression) != nil)
        let dots = try src.write("report. ", "x")
        let stored4 = try AttachmentStore.importFile(ds, from: dots)
        #expect(stored4.range(of: #"^files/[0-9a-f]{32}_report$"#, options: .regularExpression) != nil)
        // 05 §4.2: the ORIGINAL part is capped at 150 UTF-16 units (the GUID prefix is not counted).
        let longName = String(repeating: "m", count: 180) + ".pdf"
        let long = try src.write(longName, "x")
        let stored5 = try AttachmentStore.importFile(ds, from: long)
        let original5 = String(stored5.dropFirst("files/".count + 33))
        #expect(original5.utf16.count == 150)
        #expect(original5.hasSuffix(".pdf"))
        #expect(original5 == AttachmentStore.windowsSafeLeaf(longName))
    }

    @Test("ImportFile keeps the link's own name and copies its target (File.Copy semantics)")
    func importSymlink() throws {
        let made = StoreFactory.make()
        let ds = made.dataStore
        let src = TempFolder("persist-link")
        let target = try src.write("Target.pdf", "real bytes")
        let link = src.file("Shortcut name.pdf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let stored = try AttachmentStore.importFile(ds, from: link)
        #expect(stored.range(of: #"^files/[0-9a-f]{32}_Shortcut name\.pdf$"#, options: .regularExpression) != nil)
        let dest = ds.appFolder.appending(path: stored)
        #expect(try Data(contentsOf: dest) == Data("real bytes".utf8))
        let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
        #expect(attrs[.type] as? FileAttributeType == .typeRegular)
    }

    @Test("DATA-067: trashing, purging and emptying the Trash never delete attachment files")
    func itemDeletionKeepsFiles() throws {
        let made = StoreFactory.make()
        let ds = made.dataStore
        let store = made.store
        let src = TempFolder("persist-067")
        let stored1 = try AttachmentStore.importFile(ds, from: try src.write("Manual.pdf", "manual"))
        let stored2 = try AttachmentStore.importFile(ds, from: try src.write("Photo.jpg", "photo"))
        let d = AppData()
        let e1 = Equipment(name: "Pump"), e2 = Equipment(name: "Valve")
        e1.container.files = [FileItem(name: "Manual.pdf", path: stored1, kind: .document)]
        e2.container.files = [FileItem(name: "Photo.jpg", path: stored2, kind: .image)]
        d.equipment = [e1, e2]
        store.replaceData(d, reason: .initialLoad)
        try store.save()
        let entry = try #require(store.trash(e1))
        store.purge(entry)
        _ = store.trash(e2)
        store.emptyTrash()
        try store.save()
        #expect(store.data.equipment.isEmpty)
        #expect(FileManager.default.fileExists(atPath: ds.appFolder.appending(path: stored1).path))
        #expect(FileManager.default.fileExists(atPath: ds.appFolder.appending(path: stored2).path))
    }

    @Test("A closed write gate (read-only copy, Stop Editing Here) refuses every attachment write (DATA-174)")
    func writeGate() throws {
        let made = StoreFactory.make()
        let ds = made.dataStore
        let src = TempFolder("persist-gate")
        let pump = try src.write("Pump.pdf", "x")
        ds.settings.isWriteGated = true
        defer { ds.settings.isWriteGated = false }
        #expect(throws: PersistWriteGateError.readOnly) { try AttachmentStore.importFile(ds, from: pump) }
        #expect(throws: PersistWriteGateError.readOnly) {
            try AttachmentStore.importData(ds, Data([1, 2, 3]), suggestedName: "Pasted.png")
        }
        #expect(PersistWriteGateError.readOnly.localizedDescription == "Not available in a read-only copy of AA.")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: ds.filesFolder.path)) ?? []
        #expect(files.isEmpty)
    }

    @Test("Windows-safe leaf rules (01 §6.6)")
    func windowsSafeLeaf() {
        #expect(AttachmentStore.windowsSafeLeaf("a:b?.pdf") == "a_b_.pdf")
        #expect(AttachmentStore.windowsSafeLeaf("<x>|\"y\"*.txt") == "_x___y__.txt")
        #expect(AttachmentStore.windowsSafeLeaf("tab\tname.txt") == "tab_name.txt")
        #expect(AttachmentStore.windowsSafeLeaf("CON.txt") == "_CON.txt")
        #expect(AttachmentStore.windowsSafeLeaf("lpt9") == "_lpt9")
        #expect(AttachmentStore.windowsSafeLeaf("COM10.txt") == "COM10.txt")
        #expect(AttachmentStore.windowsSafeLeaf("report. ") == "report")
        #expect(AttachmentStore.windowsSafeLeaf("...") == "_")
        let nfd = "Cafe\u{301}.pdf"
        #expect(AttachmentStore.windowsSafeLeaf(nfd) == "Caf\u{E9}.pdf")
        let long = String(repeating: "x", count: 200) + ".docx"
        let cut = AttachmentStore.windowsSafeLeaf(long)
        #expect(cut.utf16.count == 150)
        #expect(cut.hasSuffix(".docx"))
        let emoji = String(repeating: "🚢", count: 100) + ".png"
        let cutEmoji = AttachmentStore.windowsSafeLeaf(emoji)
        #expect(cutEmoji.utf16.count <= 150)
        #expect(cutEmoji.hasSuffix(".png"))
        #expect(!cutEmoji.unicodeScalars.contains { $0.value == 0xFFFD })
    }

    @Test("ClassifyFile table (DATA-066, CONT-081)")
    func classify() {
        #expect(AttachmentStore.classify(path: "X.PDF") == .document)
        #expect(AttachmentStore.classify(path: "a.heic") == .image)
        #expect(AttachmentStore.classify(path: "x.JPEG") == .image)
        #expect(AttachmentStore.classify(path: "b.webm") == .video)
        #expect(AttachmentStore.classify(path: "c.csv") == .other)
        #expect(AttachmentStore.classify(path: "noext") == .other)
        #expect(AttachmentStore.classify(path: "deck.key") == .other)
        #expect(AttachmentStore.classify(path: #"C:\dir.v2\file"#) == .other)
        #expect(AttachmentStore.classify(path: "files/3f25_Pump manual.pdf") == .document)
        for ext in ["pdf", "docx", "doc", "xlsx", "xls", "pptx", "ppt", "txt", "rtf"] {
            #expect(AttachmentStore.classify(path: "a.\(ext)") == .document)
        }
        for ext in ["jpg", "jpeg", "png", "tif", "tiff", "bmp", "heic", "gif"] {
            #expect(AttachmentStore.classify(path: "a.\(ext)") == .image)
        }
        for ext in ["mov", "mp4", "wmv", "avi", "mkv", "m4v", "webm"] {
            #expect(AttachmentStore.classify(path: "a.\(ext)") == .video)
        }
    }

    @Test("EnumerateContainers visits exactly the DATA-068 containers in order")
    func enumerate() {
        let d = AppData()
        let eq = Equipment(name: "E"); let comp = Component(name: "C"); eq.components = [comp]
        let t = TaskItem(name: "T"); let st = TaskItem(name: "S"); let sst = TaskItem(name: "SS")
        st.subtasks = [sst]; t.subtasks = [st]
        let p = Procedure(name: "P"); let step = ChecklistStep(title: "step"); p.steps = [step]
        let v = Vessel(name: "V")
        let cm = CrewMember(); let cstep = ChecklistStep(title: "crew"); cm.checklist = [cstep]
        let tpl = ChecklistTemplate(name: "L", items: [ChecklistTemplateItem(title: "i")])
        d.equipment = [eq]; d.tasks = [t]; d.procedures = [p]; d.vessels = [v]; d.crew = [cm]; d.checklistTemplates = [tpl]
        let got = AttachmentStore.enumerateContainers(d).map(ObjectIdentifier.init)
        let want = [eq.container, comp.container, t.container, st.container, sst.container, p.container, step.container,
                    v.container, cstep.container, tpl.items[0].container].map(ObjectIdentifier.init)
        #expect(got == want)
    }

    @Test("A folder or package is zipped into ONE files/ entry; Finder metadata skipped (DECISIONS 05)")
    func packageImport() throws {
        let made = StoreFactory.make()
        let ds = made.dataStore
        let src = TempFolder("persist-pkg")
        try src.write("Deck.pages/Index.zip", "index")
        try src.write("Deck.pages/Data/image1.png", "png")
        try src.write("Deck.pages/.DS_Store", "junk")
        try FileManager.default.createDirectory(at: src.file("Deck.pages/Empty"), withIntermediateDirectories: true)
        let stored = try AttachmentStore.importFile(ds, from: src.file("Deck.pages"))
        #expect(stored.range(of: #"^files/[0-9a-f]{32}_Deck\.pages\.zip$"#, options: .regularExpression) != nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: ds.filesFolder.path)
        #expect(files.count == 1)
        let names = try PersistZip.names(ds.appFolder.appending(path: stored)).sorted()
        #expect(names == ["Deck.pages/Data/image1.png", "Deck.pages/Empty/", "Deck.pages/Index.zip"])
        #expect(try PersistZip.entry(ds.appFolder.appending(path: stored), "Deck.pages/Index.zip") == Data("index".utf8))
    }

    @Test("Pasted bytes go to files/<32hex>_<safe name> atomically (DECISIONS 05)")
    func importData() throws {
        let made = StoreFactory.make()
        let ds = made.dataStore
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let stored = try AttachmentStore.importData(ds, png, suggestedName: "Pasted image 14:05.png")
        #expect(stored.range(of: #"^files/[0-9a-f]{32}_Pasted image 14_05\.png$"#, options: .regularExpression) != nil)
        #expect(try Data(contentsOf: ds.appFolder.appending(path: stored)) == png)
        let blank = try AttachmentStore.importData(ds, png, suggestedName: "  ")
        #expect(blank.hasSuffix("_attachment"))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: ds.filesFolder.path).filter { $0.hasSuffix(".tmp") }
        #expect(leftovers.isEmpty)
    }

    @Test("Load and save normalise through DataStore (DATA-064 wiring)")
    func normaliseOnSave() throws {
        let made = StoreFactory.make()
        let ds = made.dataStore
        try FileManager.default.createDirectory(at: ds.filesFolder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: ds.filesFolder.appending(path: "ab12_x.pdf"))
        let (d, f) = model([#"C:\Users\w\AppData\Local\AA\files\ab12_x.pdf"#])
        _ = try ds.serializeForSave(d)
        #expect(f[0].path == "files/ab12_x.pdf")
    }
}
