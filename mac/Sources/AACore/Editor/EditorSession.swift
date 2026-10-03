// Spec: 05 CONT-003 (load order), CONT-004 (400 ms debounce → persist → MarkDirty), CONT-005 (FlushPending only
//       when an edit is pending; immediate-persist actions), CONT-006 (content-withheld guard), CONT-007 + §6.10 + D-1
//       (legacy `enc:` migration; a failed decrypt keeps the ciphertext), CONT-009 (orphaned / disabled editor),
//       CONT-011 + D-2 (undo cleared on load — done by the view), §6.7 (persist only when the string changed; untouched
//       notes are never rewritten), §6.12 (external changes reload when nothing is pending); ARCHITECTURE.md §6.7 /
//       §11 (never persist against the placeholder reader: `ContractStatus.isImplemented(.wRich)` false or
//       `metadata.isPlaceholderResult` true).
import AppKit

/// Why the editor shows a stand-in that must never be written back.
public enum EditorWithheldReason: Equatable, Sendable {
    /// Legacy `enc:` body and the session is locked.
    case legacyLocked
    /// Legacy `enc:` body, session unlocked, but decryption failed (wrong key / other machine) — D-1.
    case legacyUndecryptable
    /// The XAML could not be read; the raw markup is shown.
    case unparseable
    /// The rich-text engine is not available in this build (placeholder reader) — nothing may be written.
    case engineUnavailable

    /// The banner shown above a withheld note (Mac addition, §6.7 "inline banner").
    public var bannerText: String {
        switch self {
        case .legacyLocked:
            return "This note is encrypted. Unlock it first (Tools ▸ Set / change password, then reopen) — nothing typed here would be saved."
        case .legacyUndecryptable:
            return "This note is encrypted with a different password or on another computer and can't be opened here. It is kept unchanged."
        case .unparseable:
            return "This note's saved text could not be read, so it is shown as raw markup and can't be edited here. Nothing is changed."
        case .engineUnavailable:
            return "Rich-text editing is not available in this build. The note is shown read-only and is never changed."
        }
    }
}

/// What the view should display after a load.
public struct EditorLoadedDocument {
    public var text: NSAttributedString
    public var editable: Bool
    public var withheld: EditorWithheldReason?
    public var hasAnyLock: Bool

    public init(text: NSAttributedString, editable: Bool, withheld: EditorWithheldReason?, hasAnyLock: Bool) {
        self.text = text; self.editable = editable; self.withheld = withheld; self.hasAnyLock = hasAnyLock
    }
}

/// The load / debounce / flush / withhold state machine of one container editor (no AppKit view inside, so it is
/// testable with a stub reader and writer).
@MainActor public final class EditorSession {
    public typealias Reader = @MainActor (_ xaml: String, _ context: XamlContext) -> XamlReadOutcome
    public typealias Writer = @MainActor (_ text: NSAttributedString, _ metadata: RichTextMetadata, _ context: XamlContext) -> String

    public let context: XamlContext
    public var debounce: Duration
    private let reader: Reader
    private let writer: Writer
    private let engineAvailable: @MainActor () -> Bool
    /// Supplies the current document (the text view's storage).
    public var textProvider: (@MainActor () -> NSAttributedString)?
    /// Called after every successful write (tests, status).
    public var didPersist: (@MainActor () -> Void)?

    public private(set) weak var container: Container?
    public private(set) weak var store: AppStore?
    public private(set) var passwords: PasswordService?
    public private(set) var metadata: RichTextMetadata
    public private(set) var withheld: EditorWithheldReason?
    /// The document exactly as loaded (an edit that returns to it is not a change, §6.7).
    public private(set) var loadedText = NSAttributedString()
    /// The `RichTextXaml` this session last loaded or wrote (external-change detection, §6.12).
    public private(set) var knownXaml: String = ""
    public private(set) var hasPendingEdit = false
    public private(set) var writeCount = 0
    private var debounceTask: Task<Void, Never>?
    private var generation = 0

    public init(context: XamlContext = .containerEditor, debounce: Duration = .milliseconds(400),
                reader: Reader? = nil, writer: Writer? = nil,
                engineAvailable: (@MainActor () -> Bool)? = nil) {
        self.context = context
        self.debounce = debounce
        self.reader = reader ?? { XamlReader.read($0, context: $1) }
        self.writer = writer ?? { XamlWriter.write($0, metadata: $1, context: $2) }
        self.engineAvailable = engineAvailable ?? { ContractStatus.isImplemented(.wRich) }
        self.metadata = RichTextMetadata(context: context)
    }

    /// Writes are allowed only with the real engine, a non-placeholder parse and no stand-in on screen.
    public var canPersist: Bool {
        container != nil && withheld == nil && engineAvailable() && !metadata.isPlaceholderResult
    }

    // MARK: Load (CONT-003)

    /// Binds `container` and returns what to show. The previous container's pending edit is persisted first.
    /// Nothing is written by a load except the legacy-body migration (CONT-007).
    public func load(_ container: Container?, store: AppStore?, passwords: PasswordService?) -> EditorLoadedDocument {
        flushPending()
        generation += 1
        self.container = container
        self.store = store
        self.passwords = passwords
        withheld = nil
        hasPendingEdit = false
        metadata = RichTextMetadata(context: context)
        guard let container else {
            loadedText = NSAttributedString()
            knownXaml = ""
            return EditorLoadedDocument(text: loadedText, editable: false, withheld: nil, hasAnyLock: false)
        }
        var toShow = container.richTextXaml
        if LegacyBodyCrypto.isEncrypted(toShow) {
            if let pw = passwords, pw.isUnlocked {
                if let plain = pw.decryptLegacyBody(toShow) {
                    container.richTextXaml = plain          // migrate in place (CONT-007)
                    if container.isLocked { container.isLocked = false }
                    store?.markDirty()
                    toShow = plain
                } else {
                    withheld = .legacyUndecryptable         // D-1: keep the ciphertext
                }
            } else {
                withheld = .legacyLocked
            }
        }
        if container.isLocked { container.isLocked = false }   // in memory, unconditionally (CONT-003 step 4)
        knownXaml = container.richTextXaml

        if withheld != nil {
            loadedText = NSAttributedString()
            return EditorLoadedDocument(text: loadedText, editable: false, withheld: withheld, hasAnyLock: false)
        }
        let doc: EditorLoadedDocument
        if NetText.isBlank(toShow) {
            switch reader("", context) {
            case .empty(let m), .document(_, let m): metadata = m
            case .unparseable: break
            }
            loadedText = NSAttributedString()
            doc = EditorLoadedDocument(text: loadedText, editable: true, withheld: nil, hasAnyLock: false)
        } else {
            switch reader(toShow, context) {
            case .empty(let m):
                metadata = m
                loadedText = NSAttributedString()
                doc = EditorLoadedDocument(text: loadedText, editable: true, withheld: nil, hasAnyLock: false)
            case .document(let s, let m):
                metadata = m
                loadedText = NSAttributedString(attributedString: s)
                doc = EditorLoadedDocument(text: loadedText, editable: true, withheld: nil,
                                           hasAnyLock: m.hasAnyLock || EditorLocking.hasAnyLock(s))
            case .unparseable(let raw):
                withheld = engineAvailable() ? .unparseable : .engineUnavailable
                loadedText = NSAttributedString(string: raw, attributes: EditorFormatting.defaultTypingAttributes())
                doc = EditorLoadedDocument(text: loadedText, editable: false, withheld: withheld, hasAnyLock: false)
            }
        }
        return doc
    }

    // MARK: Edits, debounce, persist (CONT-004/005)

    /// Every text or attribute change (not during a load) restarts the 400 ms debounce.
    public func noteEdited() {
        guard container != nil else { return }
        hasPendingEdit = true
        debounceTask?.cancel()
        let gen = generation
        let delay = debounce
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, gen == self.generation else { return }
            self.debounceTask = nil
            self.persistNow()
        }
    }

    /// CONT-005: persists only when an edit is pending, then stops the debounce.
    public func flushPending() {
        guard hasPendingEdit else { return }
        debounceTask?.cancel()
        debounceTask = nil
        persistNow()
    }

    /// Drops a pending edit without writing (orphaned binding, data replaced).
    public func discardPending() {
        debounceTask?.cancel()
        debounceTask = nil
        hasPendingEdit = false
    }

    /// Serialises the current document into the bound container (immediately). Refused while withheld, without the
    /// real engine, or when the text equals what was loaded. Marks the store dirty only when the stored string changed.
    @discardableResult
    public func persistNow() -> Bool {
        debounceTask?.cancel()
        debounceTask = nil
        hasPendingEdit = false
        guard let container, canPersist, let current = textProvider?() else { return false }
        if current.isEqual(to: loadedText) { return false }       // back to what was loaded: not an edit
        let xaml = current.length == 0 ? XamlWriter.emptyDocument() : writer(current, metadata, context)
        guard xaml != container.richTextXaml else { return false }
        container.richTextXaml = xaml
        knownXaml = xaml
        loadedText = NSAttributedString(attributedString: current)
        writeCount += 1
        store?.markDirty()
        didPersist?()
        return true
    }

    /// Whether `container.richTextXaml` was changed by someone else since this session loaded or wrote it.
    public var externallyChanged: Bool {
        guard let container else { return false }
        return container.richTextXaml != knownXaml
    }

    /// Detaches from the container (orphaned item, view going away) after flushing.
    public func unbind(flush: Bool) {
        if flush { flushPending() } else { discardPending() }
        generation += 1
        container = nil
    }

    /// The view normalises attributes when it displays a document (font fixing); that displayed form is the
    /// baseline "unchanged" compares against.
    public func rebaseLoadedText(_ displayed: NSAttributedString) {
        loadedText = NSAttributedString(attributedString: displayed)
    }

    /// Re-reads the lock flag of the current document (after lock/unlock).
    public func setHasAnyLock(_ v: Bool) { metadata.hasAnyLock = v }
}
