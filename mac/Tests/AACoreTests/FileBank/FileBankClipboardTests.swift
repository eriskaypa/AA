// W-FILES — CONT-087 Cut / Copy / Paste with the Mac's true move (05 §8 D-5, DECISIONS 05).
import Foundation
import Testing
@testable import AACore

@MainActor @Suite struct FileBankClipboardTests {
    let now = NetDateTime(year: 2026, month: 10, day: 2, hour: 9, minute: 0, kind: .local)

    private func entry(_ name: String, linked: [UUID] = []) -> FileItem {
        FileItem(name: name, path: "files/0123456789abcdef0123456789abcdef_\(name)", kind: .document,
                 added: NetDateTime(year: 2026, month: 9, day: 29, kind: .local), linkedItemIds: linked)
    }

    @Test func copyPasteMakesNewEntries() {
        // TV: 05 §7.5 paste semantics — copy A (LinkedItemIds [x]) → paste into B → new Id, same Path, [] , Added now
        let x = UUID()
        let a = Container(files: [entry("A.pdf", linked: [x])]), b = Container()
        let clip = FileBankClipboard()
        clip.copy(a.files, from: a, generation: 3)
        let r = clip.paste(into: b, generation: 3, now: now)
        #expect(r.addedCount == 1 && r.removedFromSource == 0 && !r.wasStale)
        #expect(b.files.count == 1 && a.files.count == 1)
        let p = b.files[0]
        #expect(p.id != a.files[0].id && p.path == a.files[0].path && p.linkedItemIds.isEmpty && p.added == now)
        // Copy mode stays: a second paste makes another copy, even into the source container.
        _ = clip.paste(into: a, generation: 3, now: now)
        #expect(a.files.count == 2 && a.files[1].id != a.files[0].id)
    }

    @Test func cutPasteIsATrueMove() {
        // TV: 05 §7.5 cut A → paste into B → B contains the same entry (same Id); Mac D-5: A no longer does
        let a = Container(files: [entry("A.pdf"), entry("B.pdf")]), b = Container()
        let moving = a.files[0]
        let clip = FileBankClipboard()
        clip.cut([moving], from: a, generation: 1)
        let r = clip.paste(into: b, generation: 1, now: now)
        #expect(r.addedCount == 1 && r.removedFromSource == 1)
        #expect(b.files.count == 1 && b.files[0] === moving && b.files[0].id == moving.id)
        #expect(a.files.map(\.name) == ["B.pdf"])
        #expect(!clip.isCut)
        // Second paste of the same clipboard → a copy (Windows: cut mode switches off after one paste).
        let c = Container()
        let r2 = clip.paste(into: c, generation: 1, now: now)
        #expect(r2.addedCount == 1 && c.files[0] !== moving && c.files[0].id != moving.id)
        #expect(b.files.count == 1)
    }

    @Test func cutPasteIntoTheSameContainerChangesNothing() {
        let a = Container(files: [entry("A.pdf")])
        let clip = FileBankClipboard()
        clip.cut(a.files, from: a, generation: 1)
        let r = clip.paste(into: a, generation: 1, now: now)
        #expect(r.addedCount == 0 && r.removedFromSource == 0 && !r.changedTarget)
        #expect(a.files.count == 1)
    }

    @Test func emptySelectionEmptiesTheClipboard() {
        // TV: 05 CONT-087 "With nothing selected either button empties the clipboard."
        let a = Container(files: [entry("A.pdf")])
        let clip = FileBankClipboard()
        clip.copy(a.files, from: a, generation: 1)
        #expect(!clip.isEmpty)
        clip.cut([], from: a, generation: 1)
        #expect(clip.isEmpty && !clip.isCut)
        #expect(clip.paste(into: Container(), generation: 1, now: now) == FileBankPasteResult())
    }

    @Test func staleClipboardAfterReloadPastesNothing() {
        // ARCH §2.4: a clipboard filled before `store.replaceData` refers to a detached graph.
        let a = Container(files: [entry("A.pdf")]), b = Container()
        let clip = FileBankClipboard()
        clip.cut(a.files, from: a, generation: 4)
        let r = clip.paste(into: b, generation: 5, now: now)
        #expect(r.wasStale && b.files.isEmpty && a.files.count == 1 && clip.isEmpty)
    }

    @Test func duplicatesInTheSelectionAreTakenOnce() {
        let a = Container(files: [entry("A.pdf")])
        let clip = FileBankClipboard()
        clip.copy([a.files[0], a.files[0]], from: a, generation: 1)
        #expect(clip.entries.count == 1)
    }

    @Test func toleratesDuplicateIdsAcrossContainers() {
        // TV: 05 §4.1 / D-5 "the Mac MUST tolerate duplicate FileItem Ids in data"
        let shared = UUID()
        let a = Container(files: [FileItem(id: shared, name: "x")]), b = Container(files: [FileItem(id: shared, name: "x")])
        let clip = FileBankClipboard()
        clip.cut(a.files, from: a, generation: 1)
        let r = clip.paste(into: b, generation: 1, now: now)
        #expect(r.addedCount == 1 && b.files.count == 2 && b.files.allSatisfy { $0.id == shared } && a.files.isEmpty)
    }
}
