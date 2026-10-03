// TV: 05 CONT-003…007 (load order, debounce, FlushPending, withheld guard, legacy migration), §7.6 (legacy crypto
//     blob — D-1: a failed decrypt keeps the ciphertext), §7.7 item 8 (unparseable → raw text, withheld, no write),
//     §7.8 (switch within 400 ms lands on the previous item; untouched notes are never rewritten), §6.12 (external
//     change detection); ARCHITECTURE.md §6.7 / §11 (no persistence against the placeholder reader).
import AppKit
import Foundation
import Testing
@testable import AACore

/// A stub reader / writer pair: "DOC:<text>" is a document, "BAD" is unparseable, "" is empty; the writer emits
/// "DOC:<plain text>".
@MainActor private enum EditorStubEngine {
    static func reader(_ x: String, _ c: XamlContext) -> XamlReadOutcome {
        if x.isEmpty { return .empty(RichTextMetadata(context: c)) }
        if x.hasPrefix("DOC:") {
            var m = RichTextMetadata(context: c)
            m.sourceHash = x.hashValue
            return .document(NSAttributedString(string: String(x.dropFirst(4))), m)
        }
        return .unparseable(raw: x)
    }

    static func writer(_ s: NSAttributedString, _ m: RichTextMetadata, _ c: XamlContext) -> String { "DOC:" + s.string }

    static func session(available: Bool = true, debounce: Duration = .milliseconds(400)) -> EditorSession {
        EditorSession(debounce: debounce, reader: reader, writer: writer, engineAvailable: { available })
    }
}

@MainActor private final class EditorTestDoc {
    let storage = NSTextStorage()
    func show(_ d: EditorLoadedDocument) { storage.setAttributedString(d.text) }
    func type(_ s: String) { storage.append(NSAttributedString(string: s)) }
}

@MainActor @Suite struct EditorSessionTests {
    private func bind(_ session: EditorSession, _ doc: EditorTestDoc) {
        session.textProvider = { NSAttributedString(attributedString: doc.storage) }
    }

    // TV: 05 CONT-003 — nothing is persisted by a load; untouched notes are never rewritten
    @Test func loadThenFlushWritesNothing() {
        let made = StoreFactory.make()
        let c = Container(richTextXaml: "DOC:hello")
        let s = EditorStubEngine.session(), doc = EditorTestDoc()
        bind(s, doc)
        let d = s.load(c, store: made.store, passwords: nil)
        doc.show(d)
        #expect(d.editable && d.withheld == nil)
        #expect(doc.storage.string == "hello")
        s.flushPending()
        #expect(c.richTextXaml == "DOC:hello")
        #expect(!made.store.isDirty)
        #expect(s.writeCount == 0)
    }

    // TV: 05 CONT-004/005 — an edit is persisted on flush, the store is marked dirty
    @Test func editThenFlushPersists() {
        let made = StoreFactory.make()
        let c = Container(richTextXaml: "DOC:hello")
        let s = EditorStubEngine.session(), doc = EditorTestDoc()
        bind(s, doc)
        doc.show(s.load(c, store: made.store, passwords: nil))
        doc.type(" world")
        s.noteEdited()
        #expect(s.hasPendingEdit)
        s.flushPending()
        #expect(c.richTextXaml == "DOC:hello world")
        #expect(made.store.isDirty)
        #expect(!s.hasPendingEdit)
        // A second flush without an edit does nothing (CONT-005).
        c.richTextXaml = "DOC:changed elsewhere"
        s.flushPending()
        #expect(c.richTextXaml == "DOC:changed elsewhere")
    }

    // TV: 05 §6.7 — an edit that returns to the loaded text is not a change
    @Test func revertedEditIsNotWritten() {
        let made = StoreFactory.make()
        let c = Container(richTextXaml: "DOC:abc")
        let s = EditorStubEngine.session(), doc = EditorTestDoc()
        bind(s, doc)
        doc.show(s.load(c, store: made.store, passwords: nil))
        doc.type("d")
        s.noteEdited()
        doc.storage.deleteCharacters(in: NSRange(location: 3, length: 1))
        s.noteEdited()
        s.flushPending()
        #expect(c.richTextXaml == "DOC:abc")
        #expect(!made.store.isDirty)
    }

    // TV: 05 §7.8 — switching items within 400 ms lands the text on the previous item
    @Test func switchingFlushesPreviousContainer() {
        let made = StoreFactory.make()
        let a = Container(richTextXaml: "DOC:A"), b = Container(richTextXaml: "DOC:B")
        let s = EditorStubEngine.session(), doc = EditorTestDoc()
        bind(s, doc)
        doc.show(s.load(a, store: made.store, passwords: nil))
        doc.type("1")
        s.noteEdited()
        doc.show(s.load(b, store: made.store, passwords: nil))
        #expect(a.richTextXaml == "DOC:A1")
        #expect(b.richTextXaml == "DOC:B")
        #expect(doc.storage.string == "B")
    }

    // TV: 05 CONT-004 — the 400 ms debounce persists by itself
    @Test func debouncePersists() async throws {
        let made = StoreFactory.make()
        let c = Container(richTextXaml: "DOC:x")
        let s = EditorStubEngine.session(debounce: .milliseconds(30)), doc = EditorTestDoc()
        bind(s, doc)
        doc.show(s.load(c, store: made.store, passwords: nil))
        doc.type("y")
        s.noteEdited()
        #expect(c.richTextXaml == "DOC:x")
        try await Task.sleep(for: .milliseconds(250))
        #expect(c.richTextXaml == "DOC:xy")
        #expect(s.writeCount == 1)
    }

    @Test func defaultDebounceIs400ms() {
        #expect(EditorSession().debounce == .milliseconds(400))
    }

    // TV: 05 §7.7 item 8 — unparseable → raw text shown, withheld, never written
    @Test func unparseableIsWithheld() {
        let made = StoreFactory.make()
        let c = Container(richTextXaml: "BAD")
        let s = EditorStubEngine.session(), doc = EditorTestDoc()
        bind(s, doc)
        let d = s.load(c, store: made.store, passwords: nil)
        doc.show(d)
        #expect(d.withheld == .unparseable)
        #expect(!d.editable)
        #expect(doc.storage.string == "BAD")
        doc.type("typed")
        s.noteEdited()
        s.flushPending()
        #expect(!s.persistNow())
        #expect(c.richTextXaml == "BAD")
        #expect(!made.store.isDirty)
    }

    // TV: ARCH §6.7 / §11 — the placeholder reader never leads to a write (this worktree's real XamlReader)
    @Test func placeholderEngineNeverPersists() {
        let made = StoreFactory.make()
        let c = Container(richTextXaml: "<Section><Paragraph><Run>x</Run></Paragraph></Section>")
        let s = EditorSession(engineAvailable: { false }), doc = EditorTestDoc()
        bind(s, doc)
        let d = s.load(c, store: made.store, passwords: nil)
        doc.show(d)
        #expect(d.withheld == .engineUnavailable || d.withheld == .unparseable || ContractStatus.isImplemented(.wRich))
        doc.type("!")
        s.noteEdited()
        s.flushPending()
        #expect(c.richTextXaml == "<Section><Paragraph><Run>x</Run></Paragraph></Section>")
        #expect(!made.store.isDirty)
    }

    // TV: ARCH §11 / CONT-006 — an empty note under an unavailable engine is read-only (withheld) and stays empty
    @Test func emptyNoteUnderUnavailableEngine() {
        let made = StoreFactory.make()
        let c = Container(richTextXaml: "")
        let s = EditorStubEngine.session(available: false), doc = EditorTestDoc()
        bind(s, doc)
        let d = s.load(c, store: made.store, passwords: nil)
        doc.show(d)
        #expect(!d.editable)
        #expect(d.withheld == .engineUnavailable && s.withheld == .engineUnavailable)
        #expect(!s.canPersist)
        doc.type("new text")
        s.noteEdited()
        s.flushPending()
        #expect(c.richTextXaml == "")
        #expect(!made.store.isDirty)
    }

    // TV: ARCH §6.7 — metadata.isPlaceholderResult blocks persistence even with the flag on
    @Test func placeholderMetadataBlocksPersistence() {
        let made = StoreFactory.make()
        let c = Container(richTextXaml: "")
        let s = EditorSession(reader: { _, ctx in
            var m = RichTextMetadata(context: ctx)
            m.isPlaceholderResult = true
            return .empty(m)
        }, writer: { _, _, _ in "WRITTEN" }, engineAvailable: { true })
        let doc = EditorTestDoc()
        bind(s, doc)
        let d = s.load(c, store: made.store, passwords: nil)
        doc.show(d)
        #expect(!d.editable && s.withheld == .engineUnavailable)    // never typeable (CONT-006)
        doc.type("x")
        s.noteEdited()
        s.flushPending()
        #expect(c.richTextXaml == "")
    }

    // TV: DECISIONS 05 — emptying a note writes "" (the empty document)
    @Test func emptiedNoteWritesEmptyString() {
        let made = StoreFactory.make()
        let c = Container(richTextXaml: "DOC:abc")
        let s = EditorStubEngine.session(), doc = EditorTestDoc()
        bind(s, doc)
        doc.show(s.load(c, store: made.store, passwords: nil))
        doc.storage.deleteCharacters(in: NSRange(location: 0, length: 3))
        s.noteEdited()
        s.flushPending()
        #expect(c.richTextXaml == XamlWriter.emptyDocument())
    }

    // TV: 05 CONT-003 step 4 — IsLocked cleared in memory without marking dirty
    @Test func isLockedClearedInMemory() {
        let made = StoreFactory.make()
        let c = Container(richTextXaml: "DOC:x", isLocked: true)
        let s = EditorStubEngine.session()
        _ = s.load(c, store: made.store, passwords: nil)
        #expect(!c.isLocked)
        #expect(!made.store.isDirty)
    }

    // TV: 05 §6.12 — external changes are detected; own writes are not
    @Test func externalChangeDetection() {
        let made = StoreFactory.make()
        let c = Container(richTextXaml: "DOC:x")
        let s = EditorStubEngine.session(), doc = EditorTestDoc()
        bind(s, doc)
        doc.show(s.load(c, store: made.store, passwords: nil))
        #expect(!s.externallyChanged)
        doc.type("y")
        s.noteEdited()
        s.flushPending()
        #expect(!s.externallyChanged)
        c.richTextXaml = "DOC:other"
        #expect(s.externallyChanged)
    }

    // TV: CONT-009 — after unbind nothing is written
    @Test func unbindWithoutFlushDiscards() {
        let made = StoreFactory.make()
        let c = Container(richTextXaml: "DOC:x")
        let s = EditorStubEngine.session(), doc = EditorTestDoc()
        bind(s, doc)
        doc.show(s.load(c, store: made.store, passwords: nil))
        doc.type("y")
        s.noteEdited()
        s.unbind(flush: false)
        #expect(c.richTextXaml == "DOC:x")
        #expect(s.container == nil)
    }

    @Test func unbindWithFlushPersists() {
        let made = StoreFactory.make()
        let c = Container(richTextXaml: "DOC:x")
        let s = EditorStubEngine.session(), doc = EditorTestDoc()
        bind(s, doc)
        doc.show(s.load(c, store: made.store, passwords: nil))
        doc.type("y")
        s.noteEdited()
        s.unbind(flush: true)
        #expect(c.richTextXaml == "DOC:xy")
    }
}

/// TV: 05 §7.6 — legacy `enc:` bodies (CONT-007, D-1).
@MainActor @Suite struct EditorLegacyBodyTests {
    static let hash = "r8aEvRy/8yh5is2gkdnAZp/hnmK1R108BLIM6VbhOyI="
    static let salt = "AAECAwQFBgcICQoLDA0ODw=="
    static let blob = "enc:EBESExQVFhcYGRobHB0eH7yh0+cZnnHk+wt1LaJhOt37Vp1TfN1upIjugsLMCx8A+1BO/lOwe048ZDbt09pbLyzc0beZRySCCCdKYiLMU5PdZE5PJzh+Mh/dB0qGRrpyynpDMaDlxhjSkurNzory7yVyLf5MXDJksvDN6MZQ6xq0cW8h2FEuYihYTqxvmhwrVt1py4SETHUppvsjlMHfskgrHLivepYL5vBOq4Iy1MYzL9/UXBU8F/ZSwuzCLFPP"
    static let plain = "<Section xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\"><Paragraph><Run>Secret</Run></Paragraph></Section>"

    private func setup() -> (StoreFactory.Made, PasswordService) {
        let made = StoreFactory.make()
        made.dataStore.settings.setPassword(hash: Self.hash, salt: Self.salt)
        return (made, PasswordService(settings: made.dataStore.settings))
    }

    @Test func lockedSessionWithholdsAndKeepsCiphertext() {
        let (made, pw) = setup()
        let c = Container(richTextXaml: Self.blob, isLocked: true)
        let s = EditorStubEngine.session()
        let doc = EditorTestDoc()
        s.textProvider = { NSAttributedString(attributedString: doc.storage) }
        let d = s.load(c, store: made.store, passwords: pw)
        doc.show(d)
        #expect(d.withheld == .legacyLocked)
        #expect(d.text.length == 0)
        doc.type("oops")
        s.noteEdited()
        s.flushPending()
        #expect(c.richTextXaml == Self.blob)
        #expect(!made.store.isDirty)
    }

    @Test func unlockedSessionMigratesToPlaintext() {
        let (made, pw) = setup()
        #expect(pw.unlock("test1234"))
        let c = Container(richTextXaml: Self.blob, isLocked: true)
        let s = EditorSession(reader: { x, ctx in
            x == Self.plain ? .document(NSAttributedString(string: "Secret"), RichTextMetadata(context: ctx)) : .unparseable(raw: x)
        }, writer: { _, _, _ in "" }, engineAvailable: { true })
        let d = s.load(c, store: made.store, passwords: pw)
        #expect(c.richTextXaml == Self.plain)
        #expect(!c.isLocked)
        #expect(made.store.isDirty)
        #expect(d.withheld == nil)
        #expect(d.text.string == "Secret")
    }

    // D-1: the master password unlocks the session but cannot decrypt → keep the blob, withhold
    @Test func failedDecryptKeepsBlob() {
        let (made, pw) = setup()
        #expect(pw.unlock("redemption"))
        let c = Container(richTextXaml: Self.blob)
        let s = EditorStubEngine.session()
        let d = s.load(c, store: made.store, passwords: pw)
        #expect(d.withheld == .legacyUndecryptable)
        #expect(c.richTextXaml == Self.blob)
        #expect(!made.store.isDirty)
        #expect(!s.canPersist)
    }

    @Test func bannerTexts() {
        for r in [EditorWithheldReason.legacyLocked, .legacyUndecryptable, .unparseable, .engineUnavailable] {
            #expect(!r.bannerText.isEmpty)
            #expect(!r.bannerText(hasAppPassword: false).isEmpty)
        }
    }

    // FIX2 (V2-J3): the legacy banners name the button beside them and never offer to set a password.
    @Test func legacyBannerActions() {
        #expect(EditorWithheldReason.legacyLocked.bannerAction(hasAppPassword: true) == .unlock)
        #expect(EditorWithheldReason.legacyUndecryptable.bannerAction(hasAppPassword: true) == .unlockWithAppPassword)
        #expect(EditorWithheldReason.legacyLocked.bannerAction(hasAppPassword: false) == nil)
        #expect(EditorWithheldReason.legacyUndecryptable.bannerAction(hasAppPassword: false) == nil)
        #expect(EditorWithheldReason.unparseable.bannerAction(hasAppPassword: true) == nil)
        #expect(EditorWithheldReason.engineUnavailable.bannerAction(hasAppPassword: true) == nil)
        let locked = EditorWithheldReason.legacyLocked.bannerText(hasAppPassword: true)
        #expect(locked.contains(EditorWithheldAction.unlock.title))
        #expect(!locked.contains("Tools"))
        let undecryptable = EditorWithheldReason.legacyUndecryptable.bannerText(hasAppPassword: true)
        #expect(undecryptable.contains(EditorWithheldAction.unlockWithAppPassword.title))
        #expect(undecryptable.contains("master password"))
        for r in [EditorWithheldReason.legacyLocked, .legacyUndecryptable] {
            let t = r.bannerText(hasAppPassword: false)
            #expect(t.contains("no app password is set on this Mac"))
            #expect(!t.contains("Unlock"))
        }
    }

    // FIX2 journey (V2-J3 lockAndLegacyBodies, §7.6 vector): master-password session → undecryptable, blob kept →
    // "Unlock with App Password…" with test1234 → the session is re-keyed → reload migrates the body.
    @Test func lockAndLegacyBodiesJourney() {
        let (made, pw) = setup()
        #expect(pw.unlock(PasswordHashing.masterPassword))
        let c = Container(richTextXaml: Self.blob, isLocked: true)
        let s = EditorSession(reader: { x, ctx in
            x == Self.plain ? .document(NSAttributedString(string: "Secret"), RichTextMetadata(context: ctx)) : .unparseable(raw: x)
        }, writer: { _, _, _ in "" }, engineAvailable: { true })
        let first = s.load(c, store: made.store, passwords: pw)
        #expect(first.withheld == .legacyUndecryptable)
        #expect(first.withheld?.bannerAction(hasAppPassword: pw.hasPassword) == .unlockWithAppPassword)
        #expect(c.richTextXaml == Self.blob)

        // Failures leave the session (and the blob) exactly as they were.
        #expect(EditorLegacyUnlock.tryAppPassword("redemption", blob: c.richTextXaml, passwords: pw) == .masterPassword)
        #expect(EditorLegacyUnlock.tryAppPassword("nope", blob: c.richTextXaml, passwords: pw) == .wrongPassword)
        #expect(pw.isUnlocked)
        #expect(pw.decryptLegacyBody(Self.blob) == nil)          // still the master-password session
        #expect(c.richTextXaml == Self.blob)
        #expect(!made.store.isDirty)

        #expect(EditorLegacyUnlock.tryAppPassword("test1234", blob: c.richTextXaml, passwords: pw) == .unlocked)
        #expect(pw.isUnlocked)
        let second = s.load(c, store: made.store, passwords: pw)
        #expect(second.withheld == nil)
        #expect(second.text.string == "Secret")
        #expect(c.richTextXaml == Self.plain)
        #expect(!c.isLocked)
        #expect(made.store.isDirty)
    }

    // The right app password that still can't decrypt (other computer / older salt) changes nothing.
    @Test func appPasswordThatCannotDecryptKeepsSession() {
        let made = StoreFactory.make()
        // test1234 again, but with a fresh salt (password re-set / another computer): it verifies, never decrypts.
        let salt = PasswordHashing.newSalt()
        made.dataStore.settings.setPassword(hash: NetBase64.encode(PasswordHashing.hash(password: "test1234", salt: salt)),
                                            salt: NetBase64.encode(salt))
        let pw = PasswordService(settings: made.dataStore.settings)
        #expect(pw.unlock("redemption"))
        #expect(EditorLegacyUnlock.tryAppPassword("test1234", blob: Self.blob, passwords: pw) == .cannotDecrypt)
        #expect(pw.isUnlocked)
        #expect(pw.verify("test1234"))
        #expect(!made.store.isDirty)
        for o in [EditorLegacyUnlock.Outcome.masterPassword, .wrongPassword, .cannotDecrypt] {
            #expect(o.failure?.text.contains("kept unchanged") == true)
        }
        #expect(EditorLegacyUnlock.Outcome.unlocked.failure == nil)
    }

    // No app password: the master password unlocks the session but nothing can decrypt — no action, no new password.
    @Test func noAppPasswordOffersNothing() {
        let made = StoreFactory.make()
        let pw = PasswordService(settings: made.dataStore.settings)
        #expect(!pw.hasPassword)
        let c = Container(richTextXaml: Self.blob)
        let s = EditorStubEngine.session()
        let locked = s.load(c, store: made.store, passwords: pw)
        #expect(locked.withheld == .legacyLocked)
        #expect(locked.withheld?.bannerAction(hasAppPassword: pw.hasPassword) == nil)
        #expect(EditorLegacyUnlock.tryAppPassword("test1234", blob: Self.blob, passwords: pw) == .wrongPassword)
        #expect(!pw.hasPassword)
        #expect(c.richTextXaml == Self.blob)
    }
}

/// Post-merge (Stage V): the real W-RICH reader/writer round trip through the session.
@MainActor @Suite struct EditorSessionRealEngineTests {
    static let s1 = "<Section xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\" xml:space=\"preserve\" FontFamily=\"Consolas\" FontSize=\"14\" Foreground=\"#FF1A1A1A\" xml:lang=\"en-us\"><Paragraph><Run>Check the </Run><Run FontWeight=\"Bold\">main engine</Run><Run> oil level.</Run></Paragraph></Section>"

    // TV: 05 §7.8 — open/close of an untouched note never rewrites it
    @Test(.enabled(if: ContractStatus.isImplemented(.wRich)))
    func untouchedRealNoteIsNotRewritten() {
        let made = StoreFactory.make()
        let c = Container(richTextXaml: Self.s1)
        let s = EditorSession()
        let storage = NSTextStorage()
        s.textProvider = { NSAttributedString(attributedString: storage) }
        let d = s.load(c, store: made.store, passwords: nil)
        storage.setAttributedString(d.text)
        s.rebaseLoadedText(storage)
        #expect(d.withheld == nil)
        s.flushPending()
        s.unbind(flush: true)
        #expect(c.richTextXaml == Self.s1)
        #expect(!made.store.isDirty)
    }

    // TV: 05 §7.8 — type, flush → richTextXaml updated and the store dirty
    @Test(.enabled(if: ContractStatus.isImplemented(.wRich)))
    func editedRealNoteIsWritten() {
        let made = StoreFactory.make()
        let c = Container(richTextXaml: Self.s1)
        let s = EditorSession()
        let storage = NSTextStorage()
        s.textProvider = { NSAttributedString(attributedString: storage) }
        storage.setAttributedString(s.load(c, store: made.store, passwords: nil).text)
        s.rebaseLoadedText(storage)
        storage.append(NSAttributedString(string: " Done.", attributes: storage.attributes(at: storage.length - 1, effectiveRange: nil)))
        s.noteEdited()
        s.flushPending()
        #expect(c.richTextXaml != Self.s1)
        #expect(XamlPlainText.searchText(c.richTextXaml).contains("Done."))
        #expect(made.store.isDirty)
    }
}
