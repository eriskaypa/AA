// W-FILES — resolution state machine over a stand-in for W-PERSIST's primitives (01 OC-12 / TV-OWN-06, ARCH §9.4
// unmapped Windows paths), the SHELL-543 Quick Look enable rule and the Mac footer strings. The same checks against
// W-PERSIST's real store run post-merge (`missingCopyNamesTheResolvedPath`, `unmappedWindowsPaths`).
import Foundation
import Testing
@testable import AACore

@MainActor @Suite struct FileBankResolveStateTests {
    /// Behaves like the 05 §3.6 / ARCH §9.4 contract: URLs and rooted paths unchanged, relative paths under the app
    /// folder, `Z:\` mapped to `mapped` when given, every other drive letter / UNC path unmapped.
    private func resolver(mapped: URL? = nil) -> FileBankResolver {
        func isWindows(_ s: String) -> Bool {
            if s.hasPrefix("\\\\") { return true }
            let u = Array(s.unicodeScalars)
            return u.count >= 3 && CharacterSet.letters.contains(u[0]) && u[1] == ":" && (u[2] == "\\" || u[2] == "/")
        }
        return FileBankResolver(
            urlForStored: { _, _ in nil },
            resolveFilePath: { ds, stored in
                if stored.isEmpty { return "" }
                let lower = stored.lowercased()
                if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:") { return stored }
                if stored.hasPrefix("/") || isWindows(stored) { return stored }
                return ds.appFolder.appending(path: stored.replacingOccurrences(of: "\\", with: "/")).path
            },
            isWindowsPath: isWindows,
            macURL: { p in
                guard let mapped, p.uppercased().hasPrefix("Z:\\") else { return nil }
                return mapped.appending(path: String(p.dropFirst(3)).replacingOccurrences(of: "\\", with: "/"))
            },
            normalizeWebLink: { s in s.hasPrefix("www.") ? URL(string: "https://" + s) : nil })
    }

    @Test func tvOwn06MissingCopyNamesTheResolvedPath() {
        // TV: 01 TV-OWN-06 (OC-12) — the missing-file text shows the RESOLVED path, never files/…; a web link never
        // shows the missing alert.
        let made = StoreFactory.make()
        let ds = made.dataStore
        let r = resolver()
        let f = FileItem(name: "manual.pdf", path: "files/0123456789abcdef0123456789abcdef_manual.pdf")
        let expected = ds.appFolder.appending(path: "files/0123456789abcdef0123456789abcdef_manual.pdf").path
        #expect(FileBankResolve.target(of: f, dataStore: ds, using: r) == expected)
        #expect(FileBankResolve.state(of: f, dataStore: ds, using: r) == .missing(expected))
        #expect(FileBankText.viewerMissing(FileBankResolve.target(of: f, dataStore: ds, using: r)) ==
                "That file is missing:\n\n\(expected)")
        #expect(FileBankText.notFound(FileBankResolve.target(of: f, dataStore: ds, using: r)) == "Not found:\n\(expected)")
        let web = FileItem(name: "www.imo.org", path: "www.imo.org", kind: .link, isLink: true)
        #expect(FileBankResolve.state(of: web, dataStore: ds, using: r) == .web(URL(string: "https://www.imo.org")))
        #expect(FileBankResolve.target(of: web, dataStore: ds, using: r) == "www.imo.org")
    }

    @Test func presentCopiesAndBackslashedPaths() throws {
        // 05 §7.5 ResolveFilePath: `files\a.pdf` resolves like `files/a.pdf`
        let made = StoreFactory.make()
        let ds = made.dataStore
        try FileManager.default.createDirectory(at: ds.filesFolder, withIntermediateDirectories: true)
        let leaf = "0123456789abcdef0123456789abcdef_a.pdf"
        try Data("x".utf8).write(to: ds.filesFolder.appending(path: leaf))
        let expected = URL(fileURLWithPath: ds.appFolder.appending(path: "files/" + leaf).path)
        for stored in ["files/" + leaf, "files\\" + leaf] {
            #expect(FileBankResolve.state(of: FileItem(path: stored), dataStore: ds, using: resolver()) == .present(expected))
        }
        #expect(FileBankResolve.previewURLs([FileItem(path: "files/" + leaf), FileItem(path: "files/gone.pdf")],
                                            dataStore: ds, using: resolver()) == [expected])
    }

    @Test func windowsPathsMappedOrUnmapped() throws {
        // ARCH §9.4: a drive-letter / UNC path without a mapping is "unmapped" (Settings ▸ File Links), never
        // "missing"; with a mapping it resolves to the Mac folder (present or missing there).
        let made = StoreFactory.make()
        let ds = made.dataStore
        let t = TempFolder("fb-map")
        try t.write("Routine/a.pdf", "a")
        let folder = FileItem(name: "Routine  (folder)", path: "Q:\\Routine", kind: .other, linkInPlace: true)
        #expect(FileBankResolve.state(of: folder, dataStore: ds, using: resolver()) == .windowsUnmapped("Q:\\Routine"))
        let unc = FileItem(name: "Daily log.xlsx", path: "\\\\shipserver\\ops\\Daily log.xlsx", linkInPlace: true)
        #expect(FileBankResolve.state(of: unc, dataStore: ds, using: resolver()) == .windowsUnmapped(unc.path))
        #expect(FileBankResolve.fileURL(of: unc, dataStore: ds, using: resolver()) == nil)

        let mapped = resolver(mapped: t.url)
        let z = FileItem(name: "a.pdf", path: "Z:\\Routine\\a.pdf", linkInPlace: true)
        #expect(FileBankResolve.state(of: z, dataStore: ds, using: mapped) == .present(t.file("Routine/a.pdf")))
        #expect(FileBankResolve.target(of: z, dataStore: ds, using: mapped) == t.file("Routine/a.pdf").path)
        let zGone = FileItem(name: "b.pdf", path: "Z:\\Routine\\b.pdf", linkInPlace: true)
        #expect(FileBankResolve.state(of: zGone, dataStore: ds, using: mapped) == .missing(t.file("Routine/b.pdf").path))
    }

    @Test func emptyPathIsMissingNotACrash() {
        let made = StoreFactory.make()
        let f = FileItem(name: "x", path: "")
        #expect(FileBankResolve.state(of: f, dataStore: made.dataStore, using: resolver()) == .missing(""))
    }
}

@Suite struct FileBankQuickLookPolicyTests {
    @Test func shell543NeedsALocalFileInTheSelection() {
        // TV: 03 SHELL-543 — ⌘Y is enabled for LIST(fileBank | viewerFiles) "with a selection that has a local file"
        typealias R = CommandRouterCore
        var c = CommandContext()
        c.section = .equipment
        c.keyWin = .main
        c.list = FileBankListPolicy.state(selectionCount: 1, canRemove: true, selectionHasLocalFile: false)
        #expect(!R.state(.quickLook, c).enabled)
        c.list = FileBankListPolicy.state(selectionCount: 1, canRemove: true, selectionHasLocalFile: true)
        #expect(R.state(.quickLook, c).enabled)
        c.keyWin = .viewer
        c.list = FileBankListPolicy.viewerState(selectionCount: 2, selectionHasLocalFile: false)
        #expect(!R.state(.quickLook, c).enabled)
        #expect(FileBankListPolicy.removeAvailable(editable: true, isShared: false))
        #expect(!FileBankListPolicy.removeAvailable(editable: true, isShared: true))
        #expect(!FileBankListPolicy.removeAvailable(editable: false, isShared: false))
    }

    @Test func footerAndDropTexts() {
        #expect(FileBankText.footerCount(shown: 1, selected: 0) == "1 item")
        #expect(FileBankText.footerCount(shown: 9, selected: 0) == "9 items")
        #expect(FileBankText.footerCount(shown: 9, selected: 2) == "2 of 9 items selected")
        #expect(FileBankText.footerCount(shown: 1, selected: 1) == "1 of 1 item selected")
        #expect(FileBankText.lockedSharersCount(1) == "1 locked")
        #expect(FileBankText.yes == "Yes" && FileBankText.no == "No")
    }
}
