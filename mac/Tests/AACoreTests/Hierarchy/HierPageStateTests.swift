// Tests for 04 HIER-025 (typing after Return keeps re-labelling in place — no rebuild per keystroke), HIER-125 / Q-07
// (structural changes still rebuild), HIER-056 + 05 CONT-007/CONT-062 + DEVIATIONS 05 D-4 (which app-password
// session changes re-load a hosted editor).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite struct HierPageStateTests {
    static let clock = FixedClock(local: "2026-09-29T11:15:30", zone: TZ.athens)

    // TV: HIER-025 — the item being typed is left out of the signature; other items' names are in it
    @Test func signatureExcludesTheEditedName() {
        let made = StoreFactory.make(clock: Self.clock); let store = made.store
        let a = store.createItem(kind: .equipment, name: "Alpha"), b = store.createItem(kind: .equipment, name: "Beta")
        let before = HierStructureSignature(store: store, kind: .equipment, editingNameID: a.id, includeTags: false)
        _ = HierPageOps.setName(a, "Alphabet")
        #expect(HierStructureSignature(store: store, kind: .equipment, editingNameID: a.id, includeTags: false) == before)
        _ = HierPageOps.setName(b, "Bravo")                                  // e.g. typed in another window (HIER-117)
        #expect(HierStructureSignature(store: store, kind: .equipment, editingNameID: a.id, includeTags: false) != before)
    }

    // TV: HIER-025 — Return keeps the box focused: the item stays excluded, so the next keystrokes do not rebuild
    @Test func returnKeepsTheNameExcluded() {
        let made = StoreFactory.make(clock: Self.clock); let store = made.store
        let a = store.createItem(kind: .task, name: "Pump")
        let id = HierRenameState.editingAfterCommit(stillEditing: a.id, primary: a.id)
        #expect(id == a.id)
        let afterCommit = HierStructureSignature(store: store, kind: .task, editingNameID: id, includeTags: false)
        for text in ["Pump ", "Pump 2", "Pump 2 overhaul"] {
            _ = HierPageOps.setName(a, text)
            #expect(HierStructureSignature(store: store, kind: .task, editingNameID: id, includeTags: false) == afterCommit)
        }
        // Focus loss (or the item no longer the details item) ends the exclusion.
        #expect(HierRenameState.editingAfterCommit(stillEditing: nil, primary: a.id) == nil)
        #expect(HierRenameState.editingAfterCommit(stillEditing: a.id, primary: UUID()) == nil)
        #expect(HierRenameState.editingAfterCommit(stillEditing: a.id, primary: nil) == nil)
    }

    // TV: HIER-056 / CONT-062 / D-4 — relock always re-loads; an unlock only when a legacy body waits for it
    @Test func editorReloadRule() {
        #expect(HierEditorReload.onSessionChange(wasUnlocked: true, isUnlocked: false, bodyIsLegacyEncrypted: false))
        #expect(HierEditorReload.onSessionChange(wasUnlocked: true, isUnlocked: false, bodyIsLegacyEncrypted: true))
        #expect(!HierEditorReload.onSessionChange(wasUnlocked: false, isUnlocked: true, bodyIsLegacyEncrypted: false))
        #expect(HierEditorReload.onSessionChange(wasUnlocked: false, isUnlocked: true, bodyIsLegacyEncrypted: true))
        #expect(!HierEditorReload.onSessionChange(wasUnlocked: false, isUnlocked: false, bodyIsLegacyEncrypted: true))
        #expect(!HierEditorReload.onSessionChange(wasUnlocked: true, isUnlocked: true, bodyIsLegacyEncrypted: true))
    }
}
