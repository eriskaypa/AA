// Spec: 05 §2.1–2.4 (CONT-001…066 except 035, 042, 049, 050, 065 — those are W-RICH / W-PDF / W-PLAN), §3.1, §6.2,
//       §6.5–6.8, §6.10, §6.12, §7.8; 06 BUILD-100, BUILD-145 B5; 03 SHELL-678, 680…682, 685, 689, SHELL-517/519/520,
//       §6.5.1 Format rows (behaviour); DECISIONS 05; ARCHITECTURE.md §2.4 (identity rebind on reload), §6.7 / §11
//       (never persist against the placeholder reader), §7.4 (`EditorFlushCenter`), §7.6 (`AARichTextResponder`).
import AppKit
import Observation
import SwiftUI
import AACore

/// A short inline notice above the paper (lock hint outside the main window, image moved to the file bank, …).
struct EditorNotice: Equatable, Identifiable {
    enum Style: Equatable { case info, warning, success }
    let id = UUID()
    var style: Style
    var text: String
}

/// Owns one container editor: the TextKit 1 text view, the AACore session (load / debounce / flush / withhold), the
/// lock gate, every Format command and the format-bar state.
@MainActor @Observable
final class EditorController: NSObject {
    // MARK: Observed state (format bar, banners)

    private(set) var summary = EditorSelectionSummary()
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var withheld: EditorWithheldReason?
    private(set) var parkedByOtherEditor = false
    private(set) var orphaned = false
    private(set) var hostEnabled = true
    private(set) var notice: EditorNotice?
    private(set) var zoom: CGFloat = EditorController.storedZoom()
    private(set) var hasContainer = false

    /// The text can be edited right now.
    var isEditable: Bool { hasContainer && hostEnabled && withheld == nil && !parkedByOtherEditor && !orphaned }

    // MARK: Plumbing

    @ObservationIgnored let session = EditorSession()
    @ObservationIgnored let undoManager = UndoManager()
    @ObservationIgnored private(set) weak var env: AppEnvironment?
    @ObservationIgnored var dialogs: DialogPresenter = .unbound
    @ObservationIgnored private(set) var host: EditorHost = .mainPane(.equipment)
    @ObservationIgnored private(set) weak var container: Container?
    @ObservationIgnored private var flushToken: EditorFlushCenter.Token?
    @ObservationIgnored private var dataReplacedSubscription: EventSubscription?
    @ObservationIgnored private var undoObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var hasAnyLock = false
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var bypassLockGate = false
    @ObservationIgnored private var hintThrottle = EditorHintThrottle()
    @ObservationIgnored private var colorTarget: ColorTarget = .text
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var observationGeneration = 0
    @ObservationIgnored private var previewMode = false
    /// Preview only (no environment): whether the legacy banners assume an app password.
    private var previewHasAppPassword: Bool?
    private enum ColorTarget { case text, highlight }

    @ObservationIgnored private var _scrollView: EditorScrollView?
    @ObservationIgnored private var _textView: AARichTextView?
    /// The text storage is the root of the TextKit 1 object graph; keep it alive explicitly.
    @ObservationIgnored private var _textStorage: NSTextStorage?

    @ObservationIgnored private weak var flushCenter: EditorFlushCenter?

    override init() { super.init() }

    /// A destroyed editor gives up its container (the next editor of it un-parks) and its flush registration.
    isolated deinit {
        if let c = container { EditorBindingRegistry.release(self, container: c) }
        if let token = flushToken { flushCenter?.unregister(token) }
        for o in undoObservers { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: Views (created lazily — SwiftUI may construct controllers it never uses)

    var scrollView: EditorScrollView {
        if let s = _scrollView { return s }
        makeViews()
        return _scrollView!
    }

    var textView: AARichTextView {
        if let t = _textView { return t }
        makeViews()
        return _textView!
    }

    private var storage: NSTextStorage { textView.textStorage! }

    static let paperColor = NSColor(srgbRed: 0xFC / 255.0, green: 0xFC / 255.0, blue: 0xFC / 255.0, alpha: 1)

    /// XD.2.8: the typing attributes of an empty (or cleared) note — W-RICH's projection of the root context,
    /// including the paragraph style the reader gives an `Auto`-margin paragraph, so new text looks exactly like
    /// loaded text and the writer emits no `Margin` for it (CONT-003, 05 §6.2, §4.3.7 rule 5; REQ-W-CONT-02).
    static func emptyTypingAttributes(_ metadata: RichTextMetadata = RichTextMetadata(context: .containerEditor))
        -> [NSAttributedString.Key: Any] {
        XamlReader.typingAttributes(for: metadata)
    }

    private func makeViews() {
        let textStorage = NSTextStorage()
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = true            // large notes (ARCH §9.7)
        layout.backgroundLayoutEnabled = true
        textStorage.addLayoutManager(layout)
        let tc = NSTextContainer(containerSize: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        tc.widthTracksTextView = true
        layout.addTextContainer(tc)
        let tv = AARichTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: tc)
        tv.editor = self
        configure(tv)
        textStorage.delegate = self

        let sv = EditorScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.borderType = .noBorder
        sv.automaticallyAdjustsContentInsets = false      // never inset for a title bar / toolbar above the pane
        sv.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        sv.drawsBackground = true
        sv.backgroundColor = Self.paperColor
        sv.allowsMagnification = true
        sv.minMagnification = 0.5
        sv.maxMagnification = 3
        sv.findBarPosition = .aboveContent
        sv.appearance = NSAppearance(named: .aqua)
        sv.documentView = tv
        sv.magnification = zoom
        sv.onMagnificationChanged = { [weak self] m in self?.magnificationChanged(m) }
        _scrollView = sv
        _textView = tv
        _textStorage = textStorage
        observeUndo()
    }

    private func configure(_ tv: AARichTextView) {
        tv.isRichText = true
        tv.importsGraphics = false
        tv.allowsImageEditing = false
        tv.allowsUndo = true
        tv.usesFontPanel = true
        tv.usesRuler = false
        tv.usesInspectorBar = false
        tv.allowsDocumentBackgroundColorChange = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.isGrammarCheckingEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.isAutomaticTextCompletionEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.appearance = NSAppearance(named: .aqua)          // the paper stays light in both appearances
        tv.drawsBackground = true
        tv.backgroundColor = Self.paperColor
        tv.insertionPointColor = EditorFormatting.editorInk
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        // XD.5: the link colour is baked into the text; the view only adds the underline.
        tv.linkTextAttributes = [.underlineStyle: NSUnderlineStyle.single.rawValue]
        let empty = Self.emptyTypingAttributes()
        if let p = empty[.paragraphStyle] as? NSParagraphStyle { tv.defaultParagraphStyle = p }
        tv.typingAttributes = empty
        tv.selectedTextAttributes = [.backgroundColor: NSColor(srgbRed: 0.71, green: 0.84, blue: 1.0, alpha: 1)]
        tv.delegate = self
        tv.setAccessibilityLabel("Notes")
    }

    private func observeUndo() {
        let nc = NotificationCenter.default
        let names: [Notification.Name] = [.NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange,
                                          .NSUndoManagerDidRedoChange, .NSUndoManagerCheckpoint]
        for n in names {
            undoObservers.append(nc.addObserver(forName: n, object: undoManager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshUndoState() }
            })
        }
    }

    private func refreshUndoState() {
        let u = undoManager.canUndo, r = undoManager.canRedo
        if canUndo != u { canUndo = u }
        if canRedo != r { canRedo = r }
    }

    // MARK: Binding (CONT-002/003, §6.12, ARCH §2.4)

    /// Binds (or re-binds) the editor to `container` for `host`. Persists the previous container's pending edit first.
    func bind(container: Container, host: EditorHost, isEnabled: Bool, env: AppEnvironment, dialogs: DialogPresenter) {
        self.dialogs = dialogs
        hostEnabled = isEnabled
        if self.env !== env || dataReplacedSubscription == nil {
            self.env = env
            dataReplacedSubscription = env.store.dataReplaced.subscribe { [weak self] _ in self?.dataReplaced() }
        }
        self.host = host
        if self.container === container, hasContainer { applyEditability(); return }
        if let old = self.container, old !== container {
            session.flushPending()                              // the previous container keeps its edit
            EditorBindingRegistry.release(self, container: old)
        }
        self.container = container
        hasContainer = true
        orphaned = false
        parkedByOtherEditor = false                             // parked was about the previous container
        // Claim first: an older editor of the same container flushes before this one reads it (§6.12).
        EditorBindingRegistry.claim(self, container: container)
        load()
        if let token = flushToken {
            env.flush.rebind(token, to: container)
        } else {
            flushToken = env.flush.register(container: container, host: hostDescription) { [weak self] in self?.flush() }
            flushCenter = env.flush
        }
        observeContainerText()
    }

    /// The host changed only its enabled state (e.g. an orphaned item window, CONT-009).
    func setHostEnabled(_ enabled: Bool) {
        guard hostEnabled != enabled else { return }
        hostEnabled = enabled
        applyEditability()
    }

    /// Flushes, unregisters and forgets the container (view going away).
    func unbind() {
        session.unbind(flush: !orphaned)
        if let c = container { EditorBindingRegistry.release(self, container: c) }
        if let token = flushToken, let env { env.flush.unregister(token) }
        flushToken = nil
        container = nil
        hasContainer = false
        observationGeneration += 1
        dataReplacedSubscription = nil
        noticeTask?.cancel()
    }

    /// The view left the screen (tab switch, window closing): persist now, keep the binding (and undo) so coming
    /// back is instant; `deinit` releases everything when the view is destroyed.
    func viewDisappeared() {
        flush()
    }

    /// CONT-005: persist now if an edit is pending (hosts, ⌘S, quit, sync, export).
    func flush() {
        guard !orphaned, !previewMode else { return }
        session.flushPending()
    }

    private var hostDescription: String {
        switch host {
        case .mainPane(let k): return "main-pane:\(k)"
        case .itemWindow(let id): return "item-window:\(id.uuidString)"
        case .component(let id): return "component:\(id.uuidString)"
        case .subtask(let id): return "subtask:\(id.uuidString)"
        case .step(let id): return "step:\(id.uuidString)"
        case .savedListItem(let id): return "saved-list-item:\(id.uuidString)"
        }
    }

    /// CONT-003 + §6.7: show the container, clear undo, caret to the start, scroll to the top.
    private func load() {
        loading = true
        defer { loading = false }
        session.textProvider = { [weak self] in
            guard let self else { return NSAttributedString() }
            return NSAttributedString(attributedString: self.storage)
        }
        let doc = session.load(container, store: env?.store, passwords: env?.passwords)
        withheld = doc.withheld
        hasAnyLock = doc.hasAnyLock
        let tv = textView
        storage.beginEditing()
        storage.setAttributedString(doc.text)
        storage.endEditing()
        session.rebaseLoadedText(NSAttributedString(attributedString: storage))
        tv.typingAttributes = typingAttributesForEmptyOrStart()
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        scrollToTop()
        undoManager.removeAllActions()                         // D-2
        refreshUndoState()
        applyEditability()
        refreshSummary()
    }

    /// Caret to the start, view to the very top (inset included).
    private func scrollToTop() {
        func top() {
            let clip = scrollView.contentView
            clip.scroll(to: NSPoint(x: 0, y: 0))
            scrollView.reflectScrolledClipView(clip)
        }
        top()
        // Again after SwiftUI's first layout pass sized the scroll view (a fresh view starts at a placeholder size).
        Task { @MainActor [weak self] in
            guard let self, self.textView.selectedRange().location == 0 else { return }
            top()
        }
    }

    private func typingAttributesForEmptyOrStart() -> [NSAttributedString.Key: Any] {
        if storage.length == 0 {
            let empty = Self.emptyTypingAttributes(session.metadata)
            if let p = empty[.paragraphStyle] as? NSParagraphStyle { textView.defaultParagraphStyle = p }
            return empty
        }
        return EditorFormatting.cleanTypingAttributes(storage.attributes(at: 0, effectiveRange: nil), in: storage, caret: 0)
    }

    private func applyEditability() {
        let editable = isEditable
        if textView.isEditable != editable { textView.isEditable = editable }
        textView.isSelectable = true
    }

    /// §6.12: another editor took this container — flush, then show it read-only until that editor closes.
    func park() {
        guard !parkedByOtherEditor else { return }
        session.flushPending()
        parkedByOtherEditor = true
        // `EditorFlushCenter.holder(of:)` must name the editor that holds the container now (CONT-008).
        if let token = flushToken { flushCenter?.rebind(token, to: nil) }
        applyEditability()
    }

    /// The other editor closed: reload what it wrote and become editable again.
    func unpark() {
        guard parkedByOtherEditor else { return }
        parkedByOtherEditor = false
        if let token = flushToken, let c = container { flushCenter?.rebind(token, to: c) }
        if container != nil, !orphaned { load() } else { applyEditability() }
    }

    /// ARCH §2.4: after a reload the bound object may be detached → orphaned (CONT-009) until the host rebinds.
    private func dataReplaced() {
        guard let c = container, let env else { return }
        session.discardPending()
        let reachable = env.store.allContainers().contains { $0 === c }
        if !reachable {
            orphaned = true
            applyEditability()
        } else if session.externallyChanged {
            load()
        }
    }

    /// §6.12: reload when the container's text is changed elsewhere and nothing is pending here.
    private func observeContainerText() {
        observationGeneration += 1
        let gen = observationGeneration
        guard let c = container else { return }
        withObservationTracking {
            _ = c.richTextXaml
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, gen == self.observationGeneration else { return }
                if self.session.externallyChanged, !self.session.hasPendingEdit, !self.parkedByOtherEditor, !self.orphaned {
                    self.load()
                }
                self.observeContainerText()
            }
        }
    }

    // MARK: Debug preview (snapshot hook only — never bound to data)

    /// Shows `text` without a container (DEBUG snapshots of the format bar and paper).
    func showPreview(_ text: NSAttributedString, selection: NSRange, withheld: EditorWithheldReason? = nil,
                     notice: EditorNotice? = nil, hasAppPassword: Bool = true) {
        previewMode = true
        previewHasAppPassword = hasAppPassword
        loading = true
        storage.setAttributedString(text)
        loading = false
        undoManager.removeAllActions()                         // a new document never undoes into the old one (D-2)
        hasContainer = true
        self.withheld = withheld
        hasAnyLock = EditorLocking.hasAnyLock(text)
        textView.setSelectedRange(selection)
        scrollToTop()
        self.notice = notice
        applyEditability()
        refreshSummary()
    }

    // MARK: Zoom (Mac addition)

    private static let zoomKey = MacPreferences.Key("aa.editor.zoom")
    static let zoomLevels: [CGFloat] = [0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]

    static func storedZoom() -> CGFloat {
        guard let s = MacPreferences.shared.string(zoomKey), let v = Double(s), v >= 0.5, v <= 3 else { return 1 }
        return CGFloat(v)
    }

    func setZoom(_ z: CGFloat) {
        let v = min(max(z, 0.5), 3)
        scrollView.magnification = v
        magnificationChanged(v)
    }

    private func magnificationChanged(_ m: CGFloat) {
        if abs(zoom - m) > 0.001 { zoom = m }
        MacPreferences.shared.set(String(Double(m)), Self.zoomKey)
    }

    // MARK: Summary

    func refreshSummary() {
        guard _textView != nil else { return }
        var s = EditorFormatting.summary(storage, selection: textView.selectedRange(), typing: textView.typingAttributes)
        s.touchesLock = hasAnyLock && EditorLocking.editBlocked(storage, range: textView.selectedRange(), replacementLength: 0)
        if s != summary { summary = s }
    }

    // MARK: Notices and the locked hint (CONT-064)

    func post(_ n: EditorNotice, seconds: Double = 4) {
        noticeTask?.cancel()
        withAnimation(.snappy) { notice = n }
        noticeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.notice = nil }
        }
    }

    func dismissNotice() {
        noticeTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { notice = nil }
    }

    /// Main window: the status line; elsewhere a beep plus a short inline notice (§6.8).
    func showLockedHint() {
        guard hintThrottle.shouldShow(at: Date()) else { return }
        if case .mainPane = host, let env {
            env.status.post(EditorLocking.hintText)
        } else {
            NSSound.beep()
            post(EditorNotice(style: .warning, text: EditorLocking.hintText), seconds: 3)
        }
    }

    /// CONT-063 for commands: the caret (inside) or the selection (overlap) touches locked text.
    private func selectionTouchesLock() -> Bool {
        guard hasAnyLock else { return false }
        return EditorLocking.editBlocked(storage, range: textView.selectedRange(), replacementLength: 0)
    }

    // MARK: Edits

    /// Applies a replacement through `shouldChangeText` (undoable, lock-gated unless `bypassLock`).
    @discardableResult
    func apply(_ edit: EditorTextEdit, actionName: String, bypassLock: Bool = false) -> Bool {
        let tv = textView
        bypassLockGate = bypassLock
        defer { bypassLockGate = false }
        tv.breakUndoCoalescing()
        guard tv.shouldChangeText(in: edit.range, replacementString: edit.replacement.string) else { return false }
        storage.beginEditing()
        storage.replaceCharacters(in: edit.range, with: edit.replacement)
        storage.endEditing()
        tv.didChangeText()
        undoManager.setActionName(actionName)
        let sel = NSRange(location: min(edit.selectionAfter.location, storage.length),
                          length: max(0, min(edit.selectionAfter.length, storage.length - min(edit.selectionAfter.location, storage.length))))
        tv.setSelectedRange(sel)
        tv.scrollRangeToVisible(sel)
        return true
    }

    /// Attribute-only change over `ranges` (formatting is allowed on locked text, D-4); undoable.
    private func applyAttributes(_ ranges: [NSRange], actionName: String, _ body: (NSTextStorage) -> Void) {
        let tv = textView
        let valid = ranges.filter { $0.length > 0 && NSMaxRange($0) <= storage.length }
        guard !valid.isEmpty else { return }
        tv.breakUndoCoalescing()
        guard tv.shouldChangeText(inRanges: valid.map { NSValue(range: $0) }, replacementStrings: nil) else { return }
        storage.beginEditing()
        body(storage)
        storage.endEditing()
        tv.didChangeText()
        undoManager.setActionName(actionName)
        refreshSummary()
    }

    /// A structural change by the list engine: the whole document before/after is one undo step (one Ctrl+Z
    /// removes the whole change, CONT-040…047). Returns false when nothing changed.
    @discardableResult
    private func structural(_ actionName: String, _ body: (NSTextStorage, NSRange) -> NSRange?) -> Bool {
        let tv = textView
        let before = NSAttributedString(attributedString: storage)
        let beforeSel = tv.selectedRange()
        tv.breakUndoCoalescing()
        bypassLockGate = true
        storage.beginEditing()
        let newSel = body(storage, beforeSel)
        storage.endEditing()
        bypassLockGate = false
        if storage.isEqual(to: before) {
            if let newSel { tv.setSelectedRange(clamp(newSel)) }
            return false
        }
        let after = NSAttributedString(attributedString: storage)
        let afterSel = clamp(newSel ?? tv.selectedRange())
        registerSwap(to: before, selection: beforeSel, from: after, fromSelection: afterSel, name: actionName)
        tv.didChangeText()
        tv.setSelectedRange(afterSel)
        tv.scrollRangeToVisible(afterSel)
        if !hasAnyLock { hasAnyLock = EditorLocking.hasAnyLock(storage) }
        refreshSummary()
        return true
    }

    private func registerSwap(to target: NSAttributedString, selection: NSRange, from current: NSAttributedString,
                              fromSelection: NSRange, name: String) {
        undoManager.registerUndo(withTarget: self) { me in
            MainActor.assumeIsolated {
                me.restoreDocument(target, selection: selection, redo: current, redoSelection: fromSelection, name: name)
            }
        }
        undoManager.setActionName(name)
    }

    private func restoreDocument(_ doc: NSAttributedString, selection: NSRange, redo: NSAttributedString,
                                 redoSelection: NSRange, name: String) {
        guard _textView != nil else { return }
        let tv = textView
        let previous = NSAttributedString(attributedString: storage)
        let previousSel = tv.selectedRange()
        bypassLockGate = true
        storage.beginEditing()
        storage.setAttributedString(doc)
        storage.endEditing()
        bypassLockGate = false
        registerSwap(to: previous, selection: previousSel, from: doc, fromSelection: selection, name: name)
        tv.didChangeText()
        tv.setSelectedRange(clamp(selection))
        tv.scrollRangeToVisible(clamp(selection))
        hasAnyLock = EditorLocking.hasAnyLock(storage)
        refreshSummary()
    }

    private func clamp(_ r: NSRange) -> NSRange {
        let len = storage.length
        let loc = min(max(0, r.location), len)
        return NSRange(location: loc, length: min(max(0, r.length), len - loc))
    }

    // MARK: Command validation (ARCH §7.6)

    func validate(_ c: FormatCommand) -> Bool {
        switch c {
        case .showFind, .findNext, .findPrevious, .jumpToSelection:
            return hasContainer
        case .useSelectionForFind:
            return hasContainer && textView.selectedRange().length > 0
        case .insertSavedList:
            return hasContainer && hostEnabled && !parkedByOtherEditor && !orphaned   // withheld → "Nothing inserted"
        case .moveItemUp, .moveItemDown:
            return isEditable
        case .pasteAndMatchStyle:
            return isEditable && NSPasteboard.general.availableType(from: [.string]) != nil
        default:
            return isEditable
        }
    }

    // MARK: Command dispatch (Format menu, format bar)

    func perform(_ c: FormatCommand) {
        guard validate(c) else { NSSound.beep(); return }
        switch c {
        case .showFonts:
            focusText()
            NSFontManager.shared.target = textView
            NSFontManager.shared.orderFrontFontPanel(nil)
        case .bold: applyChar(.bold, name: "Bold")
        case .italic: applyChar(.italic, name: "Italic")
        case .underline: applyChar(.underline, name: "Underline")
        case .strikethrough: applyChar(.strikethrough, name: "Strikethrough")
        case .bigger: applyChar(.step(bigger: true), name: "Bigger")
        case .smaller: applyChar(.step(bigger: false), name: "Smaller")
        case .baselineDefault: applyChar(.baseline(0), name: "Baseline")
        case .superscript: applyChar(.baseline(1), name: "Superscript")
        case .subscript: applyChar(.baseline(-1), name: "Subscript")
        case .showColors:
            colorTarget = .text
            focusText()
            NSColorPanel.shared.showsAlpha = false          // CONT-025: alpha is always 255
            NSApp.orderFrontColorPanel(nil)
        case .highlight(let argb):
            applyChar(.highlight(argb.map(Self.color(from:))), name: "Highlight")
        case .highlightOther:
            colorTarget = .highlight
            focusText()
            NSColorPanel.shared.showsAlpha = false          // CONT-025: alpha is always 255
            NSApp.orderFrontColorPanel(nil)
        case .alignLeft: setAlignment(.left)
        case .center: setAlignment(.center)
        case .justify: setAlignment(.justified)
        case .alignRight: setAlignment(.right)
        case .bulletedList: toggleList(.bullets)
        case .numberedList: toggleList(.numbered)
        case .indent: changeIndent(increase: true)
        case .outdent: changeIndent(increase: false)
        case .insertLink: Task { await self.insertLink() }
        case .insertTable: Task { await self.insertTablePrompt() }
        case .insertSavedList: Task { await self.insertSavedList() }
        case .clearFormatting: applyChar(.clearFormatting, name: "Clear Formatting")
        case .lockSelection: Task { await self.lockSelection() }
        case .unlockSelection: Task { await self.unlockSelection() }
        case .moveItemUp: moveCurrent(up: true)
        case .moveItemDown: moveCurrent(up: false)
        case .pasteAndMatchStyle: pasteTextOnly()
        case .showFind: finder(.showFindInterface)
        case .findNext: finder(.nextMatch)
        case .findPrevious: finder(.previousMatch)
        case .useSelectionForFind: finder(.setSearchString)
        case .jumpToSelection:
            textView.scrollRangeToVisible(textView.selectedRange())
            textView.showFindIndicator(for: textView.selectedRange())
        }
    }

    /// CONT-029 Undo / Redo buttons (text undo passes the lock gate, D-4).
    func undo() {
        textView.breakUndoCoalescing()
        if undoManager.canUndo { undoManager.undo() }
        focusText()
        refreshUndoState()
    }

    func redo() {
        if undoManager.canRedo { undoManager.redo() }
        focusText()
        refreshUndoState()
    }

    func focusText() {
        guard let w = textView.window else { return }
        if w.firstResponder !== textView { w.makeFirstResponder(textView) }
    }

    private func finder(_ action: NSTextFinder.Action) {
        focusText()
        let item = NSMenuItem()
        item.tag = action.rawValue
        textView.performTextFinderAction(item)
    }

    static func color(from argb: ARGB) -> NSColor {
        NSColor(srgbRed: CGFloat(argb.r) / 255, green: CGFloat(argb.g) / 255, blue: CGFloat(argb.b) / 255,
                alpha: CGFloat(argb.a) / 255)
    }

    // MARK: Character formatting (CONT-020…030)

    func applyChar(_ cmd: EditorCharCommand, name: String) {
        let tv = textView
        let ranges = tv.selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        if ranges.isEmpty {
            tv.typingAttributes = EditorFormatting.applyToTyping(cmd, typing: tv.typingAttributes)
            refreshSummary()
            return
        }
        // One toggle direction for the whole multi-range selection (WPF decides over the selection).
        let decisionRange = NSRange(location: ranges[0].location, length: NSMaxRange(ranges.last!) - ranges[0].location)
        let on = EditorFormatting.toggleTarget(cmd, in: storage, range: decisionRange, typing: tv.typingAttributes)
        applyAttributes(ranges, actionName: name) { s in
            for r in ranges {
                var changes: [(NSRange, [NSAttributedString.Key: Any])] = []
                s.enumerateAttributes(in: r, options: []) { a, rr, _ in
                    if a[.aaListMarker] != nil { return }
                    changes.append((rr, EditorFormatting.transform(a, cmd, on: on)))
                }
                for (rr, a) in changes { s.setAttributes(a, range: rr) }
            }
        }
        if case .highlight(let c) = cmd, EditorLocking.isSentinel(c) { hasAnyLock = true }
    }

    func applyFontFamily(_ family: String) {
        applyChar(.fontFamily(family), name: "Font")
        focusText()
    }

    func applyFontSize(_ size: CGFloat) {
        guard size > 0 else { return }
        applyChar(.fontSize(size), name: "Font Size")
        focusText()
    }

    /// The colour panel (Show Colors / Highlight ▸ Other…) — text colour or highlight per the last opener.
    func applyPanelColor(_ color: NSColor) {
        guard isEditable else { return }
        switch colorTarget {
        case .text: applyChar(.foreground(color), name: "Text Color")
        case .highlight: applyChar(.highlight(color), name: "Highlight")
        }
    }

    func applyTextColor(_ color: NSColor?) {
        applyChar(.foreground(color ?? EditorFormatting.editorInk), name: "Text Color")
        focusText()
    }

    func applyHighlight(_ color: NSColor?) {
        applyChar(.highlight(color), name: color == nil ? "Remove Highlight" : "Highlight")
        focusText()
    }

    /// Opens the system colour panel for text colour or highlight ("Other…").
    func openColorPanel(highlight: Bool) {
        colorTarget = highlight ? .highlight : .text
        focusText()
        NSColorPanel.shared.showsAlpha = false          // CONT-025: alpha is always 255
        NSApp.orderFrontColorPanel(nil)
    }

    // MARK: Font panel token reconciliation (XD.5)

    struct FontSnapshot {
        var ranges: [NSRange]
        var before: [NSAttributedString]
        var typing: [NSAttributedString.Key: Any]
    }

    func snapshotForFontChange() -> FontSnapshot {
        let ranges = textView.selectedRanges.map(\.rangeValue).filter { $0.length > 0 && NSMaxRange($0) <= storage.length }
        return FontSnapshot(ranges: ranges, before: ranges.map { storage.attributedSubstring(from: $0) },
                            typing: textView.typingAttributes)
    }

    /// After the font panel changed fonts: a new family replaces `.aaFontFamilyName`; a weight/style change drops the
    /// original tokens, so the writer never stores a stale family or weight.
    func reconcileFontTokens(before snap: FontSnapshot) {
        func fixed(_ old: [NSAttributedString.Key: Any], _ new: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
            var a = new
            let of = old[.font] as? NSFont, nf = new[.font] as? NSFont
            guard let nf else { return a }
            if of?.familyName != nf.familyName, let fam = nf.familyName { a[.aaFontFamilyName] = fam }
            if EditorFormatting.isBold(of) != EditorFormatting.isBold(nf) { a[.aaFontWeightToken] = nil }
            if EditorFormatting.isItalic(of) != EditorFormatting.isItalic(nf) { a[.aaFontStyleToken] = nil }
            return a
        }
        if snap.ranges.isEmpty {
            textView.typingAttributes = fixed(snap.typing, textView.typingAttributes)
            refreshSummary()
            return
        }
        storage.beginEditing()
        for (i, r) in snap.ranges.enumerated() where NSMaxRange(r) <= storage.length {
            let old = snap.before[i]
            guard old.length == r.length else { continue }
            var updates: [(NSRange, [NSAttributedString.Key: Any])] = []
            storage.enumerateAttributes(in: r, options: []) { a, rr, _ in
                let oldAttrs = old.attributes(at: rr.location - r.location, effectiveRange: nil)
                let f = fixed(oldAttrs, a)
                if !NSDictionary(dictionary: f).isEqual(to: a) { updates.append((rr, f)) }
            }
            for (rr, a) in updates { storage.setAttributes(a, range: rr) }
        }
        storage.endEditing()
        refreshSummary()
    }

    // MARK: Paragraph formatting (CONT-027, CONT-043)

    private func setAlignment(_ a: NSTextAlignment) {
        let tv = textView
        if storage.length == 0 {
            tv.typingAttributes = EditorFormatting.paragraphStyle(tv.typingAttributes) { p in
                guard p.alignment != a else { return false }
                p.alignment = a
                return true
            }
            if let p = tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle { tv.defaultParagraphStyle = p }
            refreshSummary()
            return
        }
        let paras = EditorBlocks.paragraphRanges(storage, touching: tv.selectedRange()).filter { $0.length > 0 }
        applyAttributes(paras, actionName: "Alignment") { s in
            EditorFormatting.setAlignment(a, in: s, range: tv.selectedRange())
        }
        tv.typingAttributes = EditorFormatting.paragraphStyle(tv.typingAttributes) { p in
            guard p.alignment != a else { return false }
            p.alignment = a
            return true
        }
        refreshSummary()
    }

    private func changeIndent(increase: Bool) {
        let tv = textView
        if storage.length > 0 {
            // Lists and ordinary paragraphs both go through the block model, so the indent is persisted (CONT-043).
            structural(increase ? "Indent" : "Outdent") { s, r in
                EditorFormatting.changeIndent(s, selection: r, increase: increase)
            }
            return
        }
        // Empty document: the indent goes into the typing attributes (CONT-043).
        tv.typingAttributes = EditorFormatting.indentTypingAttributes(tv.typingAttributes, increase: increase)
    }

    // MARK: Lists (CONT-040…046, §6.5)

    private func toggleList(_ kind: RichListFormatter.ListKind) {
        structural(kind == .bullets ? "Bullets" : "Numbering") { s, r in
            let out = RichListFormatter.toggleList(kind, in: s, selection: r)
            RichListFormatter.normalise(s)
            return out
        }
    }

    /// Tab / ⇧Tab at the start of a list item nests / un-nests (CONT-044); elsewhere the native key runs.
    func handleTab(shift: Bool) -> Bool {
        guard isEditable, storage.length > 0 else { return false }
        let sel = textView.selectedRange()
        guard sel.length == 0, RichListFormatter.isAtItemStart(storage, location: sel.location) else { return false }
        if selectionTouchesLock() { showLockedHint(); return true }
        var handled = false
        structural(shift ? "Outdent" : "Indent") { s, r in
            guard let out = RichListFormatter.handleTab(s, selection: r, shift: shift) else { return nil }
            handled = true
            RichListFormatter.normalise(s)
            return out
        }
        return handled
    }

    /// Return in a list item: new item at the same level; on an empty item leave the list / outdent (CONT-044).
    func handleReturn() -> Bool {
        guard isEditable, storage.length > 0 else { return false }
        let sel = textView.selectedRange()
        guard EditorFormatting.isInList(storage, at: sel.location) else { return false }
        if EditorLocking.editBlocked(storage, range: sel, replacementLength: 1), hasAnyLock { showLockedHint(); return true }
        let depthBefore = EditorBlocks.paragraphStyle(storage, at: sel.location)?.textLists.count ?? 0
        var handled = false
        structural("Typing") { s, r in
            guard let out = RichListFormatter.handleReturn(s, selection: r) else { return nil }
            handled = true
            let depthAfter = EditorBlocks.paragraphStyle(s, at: out.location)?.textLists.count ?? 0
            if depthAfter != depthBefore { RichListFormatter.normalise(s) }
            return out
        }
        return handled
    }

    /// CONT-045: Backspace at the start of an item outdents one level (top level → ordinary paragraph).
    func handleBackspaceAtItemStart() -> Bool {
        guard isEditable, storage.length > 0 else { return false }
        let sel = textView.selectedRange()
        guard sel.length == 0, RichListFormatter.isAtItemStart(storage, location: sel.location) else { return false }
        if hasAnyLock, EditorLocking.isLocked(storage, at: sel.location - 1) && EditorLocking.isLocked(storage, at: sel.location) {
            showLockedHint()
            return true
        }
        var handled = false
        structural("Outdent") { s, r in
            guard let out = RichListFormatter.handleBackspaceAtItemStart(s, selection: r) else { return nil }
            handled = true
            RichListFormatter.normalise(s)
            return out
        }
        return handled
    }

    /// CONT-046: move the list item(s) or the caret's block one place; persists immediately.
    private func moveCurrent(up: Bool) {
        guard container != nil, withheld == nil else { return }
        if selectionTouchesLock() { showLockedHint(); return }
        let moved = structural(up ? "Move Up" : "Move Down") { s, r in
            guard let out = RichListFormatter.moveItem(s, selection: r, up: up) else { return nil }
            RichListFormatter.normalise(s)
            return out
        }
        if moved {
            focusText()
            session.persistNow()
        }
    }

    // MARK: Insert hyperlink (CONT-031, K-14)

    private func insertLink() async {
        let tv = textView
        let sel = tv.selectedRange()
        var editRange: NSRange? = sel.length > 0 ? sel : nil
        var initial = EditorLinkRules.sheetInitial
        // Mac addition: the caret inside an existing link edits that link.
        if sel.length == 0, let r = EditorLinkRules.linkRange(storage, at: max(0, sel.location - 1)),
           sel.location > r.location, sel.location < NSMaxRange(r) {
            editRange = r
            if let u = EditorLinkRules.url(from: storage.attribute(.link, at: r.location, effectiveRange: nil)) {
                initial = u.absoluteString
            }
        } else if sel.length > 0, let u = EditorLinkRules.url(from: storage.attribute(.link, at: sel.location, effectiveRange: nil)) {
            initial = u.absoluteString
        }
        var chosen: String?
        await dialogs.presentSheet(.decision) { dismiss in
            EditorInsertLinkSheet(initial: initial, isEditing: initial != EditorLinkRules.sheetInitial) { result in
                chosen = result
                dismiss()
            }
        }
        guard let url = chosen, container != nil, isEditable else { return }
        if let r = editRange, NSMaxRange(r) <= storage.length {
            applyAttributes([r], actionName: "Insert Link") { s in
                var changes: [(NSRange, [NSAttributedString.Key: Any])] = []
                s.enumerateAttributes(in: r, options: []) { a, rr, _ in
                    if a[.aaListMarker] != nil { return }
                    changes.append((rr, EditorLinkRules.linkAttributes(a, url: url, linkColor: EditorLinkRules.editorLinkColor)))
                }
                for (rr, a) in changes { s.setAttributes(a, range: rr) }
            }
        } else {
            let edit = EditorLinkRules.insertion(url: url, in: storage, selection: tv.selectedRange(),
                                                 typing: tv.typingAttributes, linkColor: EditorLinkRules.editorLinkColor)
            guard apply(edit, actionName: "Insert Link") else { return }
            // Typing after the new link must not extend it.
            tv.typingAttributes = EditorLinkRules.removingLink(tv.typingAttributes)
        }
        focusText()
        session.persistNow()
    }

    /// Removes the link the caret / selection is in (context menu).
    func removeLink(at index: Int) {
        guard isEditable, let r = EditorLinkRules.linkRange(storage, at: index) else { return }
        applyAttributes([r], actionName: "Remove Link") { s in
            var changes: [(NSRange, [NSAttributedString.Key: Any])] = []
            s.enumerateAttributes(in: r, options: []) { a, rr, _ in changes.append((rr, EditorLinkRules.removingLink(a))) }
            for (rr, a) in changes { s.setAttributes(a, range: rr) }
        }
        session.persistNow()
    }

    /// SHELL-678: ⌘-click opens the link under the pointer.
    func openLink(at point: NSPoint) -> Bool {
        let tv = textView
        guard let lm = tv.layoutManager, let tc = tv.textContainer, storage.length > 0 else { return false }
        let p = NSPoint(x: point.x - tv.textContainerOrigin.x, y: point.y - tv.textContainerOrigin.y)
        var fraction: CGFloat = 0
        let idx = lm.characterIndex(for: p, in: tc, fractionOfDistanceBetweenInsertionPoints: &fraction)
        guard idx < storage.length, let link = storage.attribute(.link, at: idx, effectiveRange: nil),
              let url = EditorLinkRules.url(from: link) else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    // MARK: Insert table (CONT-032, B5, K-15)

    private func insertTablePrompt() async {
        let r = await dialogs.prompt(TextPromptRequest(title: EditorTablePlan.promptTitle, prompt: EditorTablePlan.promptLabel,
                                                       initial: EditorTablePlan.promptInitial))
        guard case .ok(let v) = r else { return }
        let size = EditorTablePlan.parse(v)
        insertTable(rows: size.rows, columns: size.columns)
    }

    /// Inserts a rows × columns table after the caret's block; caret in the first cell; persists immediately.
    func insertTable(rows: Int, columns: Int) {
        guard isEditable else { return }
        let tv = textView
        let base = EditorFormatting.plainBaseAttributes(from: EditorLocking.unlockedTypingAttributes(tv.typingAttributes))
        let edit = EditorTableBuilder.insertion(rows: rows, columns: columns, in: storage, selection: tv.selectedRange(),
                                                base: base)
        guard apply(edit, actionName: "Insert Table") else { return }
        focusText()
        session.persistNow()
    }

    // MARK: Insert saved list (CONT-047/048, BUILD-100)

    private func insertSavedList() async {
        guard container != nil, let env else { return }
        if withheld != nil {
            await dialogs.info(EditorSavedListInsert.withheldTitle, EditorSavedListInsert.withheldText)
            return
        }
        guard isEditable else { return }
        if selectionTouchesLock() { showLockedHint(); return }
        var result: EditorSavedListChoice?
        await dialogs.presentSheet(.decision) { dismiss in
            EditorInsertSavedListSheet(store: env.store) { choice in
                result = choice
                dismiss()
            }
        }
        guard let choice = result, !choice.lines.isEmpty, isEditable else { return }
        structural("Insert Saved List") { s, r in
            // A live selection is untouched: the list goes after its end.
            let at = NSRange(location: NSMaxRange(r), length: 0)
            let out = RichListFormatter.insertList(lines: choice.lines, kind: choice.numbered ? .numbered : .bullets,
                                                   into: s, at: at)
            RichListFormatter.normalise(s)
            return out
        }
        focusText()
        session.persistNow()
    }

    // MARK: Text lock (CONT-060…062)

    /// CONT-062: session unlocked → go; no password → set one; else the unlock sheet. Cancel aborts.
    private func ensureUnlocked() async -> Bool {
        guard let pw = env?.passwords else { return false }
        if pw.isUnlocked { return true }
        if !pw.hasPassword {
            guard case .ok(let password, _) = await dialogs.password(.setNew) else { return false }
            do {
                try pw.setPassword(password, current: nil)
                return true
            } catch {
                await dialogs.error("AA — error", error.message)
                return false
            }
        }
        guard case .ok(let password, _) = await dialogs.password(.unlock(prompt: ShellPasswordMode.unlock.prompt)) else {
            return false
        }
        return pw.unlock(password)
    }

    /// The withheld banner's "Unlock…" for legacy encrypted bodies (CONT-007): unlock the session, then reload. Only
    /// offered with an app password set (a password set now gets a fresh salt and could never decrypt the body).
    func unlockAndReload() async {
        guard hasAppPassword, await ensureUnlocked(), container != nil else { return }
        load()
    }

    /// The withheld banner's "Unlock with App Password…" (CONT-007, D-1): the session was unlocked with a password
    /// that can't decrypt the body (typically the master password). Asks for the app password, re-keys the session
    /// only when it decrypts this body, then reloads (which migrates it). Any failure says why and changes nothing.
    func unlockWithAppPasswordAndReload() async {
        guard let pw = env?.passwords, let c = container, withheld == .legacyUndecryptable else { return }
        guard case .ok(let typed, _) = await dialogs.password(.unlock(prompt: EditorLegacyUnlock.prompt)) else { return }
        guard self.container === c, withheld == .legacyUndecryptable else { return }   // rebound meanwhile
        let outcome = EditorLegacyUnlock.tryAppPassword(typed, blob: c.richTextXaml, passwords: pw)
        if let f = outcome.failure {
            await dialogs.info(f.title, f.text)
            return
        }
        load()
    }

    /// An app password (hash + salt) exists — the withheld legacy banners depend on it.
    var hasAppPassword: Bool { previewHasAppPassword ?? env?.passwords.hasPassword ?? false }

    /// The legacy banner's action, run from the view.
    func performWithheldAction(_ a: EditorWithheldAction) async {
        switch a {
        case .unlock: await unlockAndReload()
        case .unlockWithAppPassword: await unlockWithAppPasswordAndReload()
        }
    }

    private func lockSelection() async {
        let sel = textView.selectedRange()
        guard sel.length > 0 else {
            await dialogs.info(EditorLocking.lockNeedsSelection.title, EditorLocking.lockNeedsSelection.text)
            return
        }
        guard await ensureUnlocked(), isEditable else { return }
        let ranges = textView.selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        applyAttributes(ranges, actionName: "Lock") { s in
            for r in ranges { EditorLocking.lock(s, range: r) }
        }
        hasAnyLock = true
        session.setHasAnyLock(true)
        textView.typingAttributes = EditorLocking.unlockedTypingAttributes(textView.typingAttributes)
        refreshSummary()
        session.persistNow()
    }

    private func unlockSelection() async {
        let sel = textView.selectedRange()
        guard sel.length > 0 else {
            await dialogs.info(EditorLocking.unlockNeedsSelection.title, EditorLocking.unlockNeedsSelection.text)
            return
        }
        guard await ensureUnlocked(), isEditable else { return }
        let stretches = textView.selectedRanges.map(\.rangeValue).flatMap { EditorLocking.lockedStretches(storage, touching: $0) }
        if !stretches.isEmpty {
            let text = storage.string as NSString
            let ranges = stretches.map { text.paragraphRange(for: $0) }
            applyAttributes(ranges, actionName: "Unlock") { s in EditorLocking.unlock(s, stretches: stretches) }
        }
        hasAnyLock = EditorLocking.hasAnyLock(storage)
        session.setHasAnyLock(hasAnyLock)
        refreshSummary()
        session.persistNow()
    }

    // MARK: Paste (CONT-034…038, §6.6)

    /// Paste text only / Paste and Match Style.
    func pasteTextOnly() {
        guard isEditable, let s = NSPasteboard.general.string(forType: .string), !s.isEmpty else { return }
        let tv = textView
        let sel = tv.selectedRange()
        if hasAnyLock, EditorLocking.editBlocked(storage, range: sel, replacementLength: s.utf16.count) {
            showLockedHint()
            return
        }
        let text = EditorRichSanitiser.plain(s, typing: tv.typingAttributes)
        apply(EditorTextEdit(range: sel, replacement: text, selectionAfter: NSRange(location: sel.location + text.length, length: 0)),
              actionName: "Paste and Match Style")
        focusText()
    }

    /// Paste and drop (`readSelection(from:type:)`).
    func paste(from pb: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard isEditable else { NSSound.beep(); return false }
        let tv = textView
        let typing = tv.typingAttributes
        switch type {
        case EditorPaste.xamlType:
            // V2-J3: the WPF paste shape on the block tree (lists, tables, sections stay whole; CONT-161, §6.6).
            if let xaml = pb.string(forType: type),
               let ok = insertStructured(length: xaml.utf16.count, {
                   XamlReader.insertFragment(xaml, into: $0, replacing: $1, base: .containerEditor)
               }) {
                return ok
            }
            return pasteFallback(pb, typing: typing)
        case EditorPaste.fileURLType:
            let urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            guard !urls.isEmpty else { return pasteFallback(pb, typing: typing) }
            addFilesToBank(urls)
            return true
        case EditorPaste.rtfdType, EditorPaste.flatRtfdType, EditorPaste.rtfType:
            guard let data = pb.data(forType: type) else { return pasteFallback(pb, typing: typing) }
            let docType: NSAttributedString.DocumentType = type == EditorPaste.rtfType ? .rtf : .rtfd
            guard let a = try? NSAttributedString(data: data, options: [.documentType: docType], documentAttributes: nil)
            else { return pasteFallback(pb, typing: typing) }
            let (clean, images) = EditorRichSanitiser.sanitise(a, base: EditorFormatting.plainBaseAttributes(from: typing))
            let ok = clean.length == 0 ? true
                : (insertStructured(length: clean.length, {
                       XamlReader.insertFragment(attributed: clean, into: $0, replacing: $1, base: .containerEditor)
                   }) ?? insertRich(clean))
            importImages(images)
            return ok
        case EditorPaste.htmlType:
            if let html = pb.string(forType: type) {
                let xaml = HTMLToXAML.convert(html)
                if !NetText.isBlank(xaml),
                   let ok = insertStructured(length: xaml.utf16.count, {
                       XamlReader.insertFragment(xaml, into: $0, replacing: $1, base: .containerEditor)
                   }) {
                    return ok
                }
            }
            return pasteFallback(pb, typing: typing)
        case EditorPaste.stringType:
            return pasteFallback(pb, typing: typing)
        default:
            if EditorPaste.imageTypes.contains(type), let img = EditorPaste.imageData(from: pb) {
                importImages([EditorExtractedImage(data: img.data, name: EditorPaste.pastedImageName(at: Date(), ext: img.ext))])
                return true
            }
            return pasteFallback(pb, typing: typing)
        }
    }

    /// Any failure falls back to plain text (Windows: "any exception → default paste").
    private func pasteFallback(_ pb: NSPasteboard, typing: [NSAttributedString.Key: Any]) -> Bool {
        guard let s = pb.string(forType: .string), !s.isEmpty else { return false }
        return insertRich(EditorRichSanitiser.plain(s, typing: typing))
    }

    /// A rich paste through the W-RICH fragment insertion (V2-J3): the lock check comes first (`structural` bypasses
    /// the lock gate), then one undo swap for the whole insertion. Nil = nothing was inserted (blank or unparseable
    /// fragment) and the caller falls back; false = blocked by a lock.
    private func insertStructured(length: Int, _ body: (NSTextStorage, NSRange) -> NSRange?) -> Bool? {
        let sel = textView.selectedRange()
        if hasAnyLock, EditorLocking.editBlocked(storage, range: sel, replacementLength: max(1, length)) {
            showLockedHint()
            return false
        }
        var inserted = false
        _ = structural("Paste") { s, r in
            let out = body(s, r)
            inserted = out != nil
            return out
        }
        if inserted { session.persistNow() }
        return inserted ? true : nil
    }

    private func insertRich(_ text: NSAttributedString) -> Bool {
        let tv = textView
        let sel = tv.selectedRange()
        if hasAnyLock, EditorLocking.editBlocked(storage, range: sel, replacementLength: text.length) {
            showLockedHint()
            return false
        }
        return apply(EditorTextEdit(range: sel, replacement: text,
                                    selectionAfter: NSRange(location: sel.location + text.length, length: 0)),
                     actionName: "Paste")
    }

    /// DECISIONS 05: images go to the file bank (a copy) with a brief inline notice.
    private func importImages(_ images: [EditorExtractedImage]) {
        guard !images.isEmpty, let env, let c = container else { return }
        var added: [String] = []
        var failure: String?
        for img in images {
            do {
                let stored = try AttachmentStore.importData(env.dataStore, img.data, suggestedName: img.name)
                _ = FileBankOperations.addImported(storedPath: stored, displayName: img.name, to: c, env: env)
                added.append(img.name)
            } catch {
                failure = error.localizedDescription
            }
        }
        if !added.isEmpty {
            let text = added.count == 1 ? "Image added to the File Bank: \(added[0])"
                                        : "\(added.count) images added to the File Bank."
            post(EditorNotice(style: .success, text: text + " Notes can't hold pictures, so it was stored as a file."))
        } else if let failure {
            post(EditorNotice(style: .warning, text: "The image could not be added to the File Bank: \(failure)"))
        }
    }

    /// Files dropped or pasted onto the text go to the file bank: none = a copy; ⇧ or ⌥⌘ = link in place (SHELL-679).
    private func addFilesToBank(_ urls: [URL]) {
        guard let env, let c = container else { return }
        let flags = NSEvent.modifierFlags
        let linkInPlace = flags.contains(.shift) || flags.contains([.option, .command])
        do {
            let items = try FileBankOperations.addFiles(urls, linkInPlace: linkInPlace, to: c, env: env)
            let n = items.count
            if n > 0 {
                post(EditorNotice(style: .success,
                                  text: n == 1 ? "Added to the File Bank: \(items[0].name)" : "\(n) items added to the File Bank."))
            }
        } catch {
            post(EditorNotice(style: .warning, text: "Could not add to the File Bank: \(error.localizedDescription)"))
        }
    }

    // MARK: Copy (our own XAML type, §6.6)

    var canWriteXaml: Bool { ContractStatus.isImplemented(.wRich) }

    func selectedXaml() -> String? {
        guard canWriteXaml else { return nil }
        let r = textView.selectedRange()
        guard r.length > 0, NSMaxRange(r) <= storage.length else { return nil }
        let sub = storage.attributedSubstring(from: r)
        let xaml = XamlWriter.write(sub, metadata: RichTextMetadata(context: .containerEditor), context: .containerEditor)
        return xaml.isEmpty ? nil : xaml
    }

    // MARK: Context menu (CONT-033)

    func contextMenu(at index: Int) -> NSMenu {
        let menu = NSMenu()
        let tv = textView
        let sel = tv.selectedRange()
        // 1. Spelling (CONT-033): suggestions, or "(locked — can't correct)" on locked text.
        if let word = misspelledWord(at: sel.length == 0 ? sel.location : sel.location) {
            let locked = hasAnyLock && EditorLocking.blocksEdit(storage, range: word.range)
            if locked {
                let item = NSMenuItem(title: "(locked — can't correct)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            } else if word.guesses.isEmpty {
                let item = NSMenuItem(title: "(no spelling suggestions)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            } else {
                for g in word.guesses {                         // every suggestion, as WPF lists them
                    let item = EditorMenuItem(title: g) { [weak self] in self?.correctSpelling(word.range, with: g) }
                    item.attributedTitle = NSAttributedString(string: g, attributes: [.font: NSFont.boldSystemFont(ofSize: 0)])
                    menu.addItem(item)
                }
            }
            menu.addItem(EditorMenuItem(title: "Ignore Spelling") { [weak self] in self?.ignoreSpelling(word.word) })
            menu.addItem(.separator())
        }
        // Links (Mac additions).
        let linkIndex = sel.length > 0 ? sel.location : max(0, min(index, storage.length - 1))
        if storage.length > 0, let link = storage.attribute(.link, at: min(linkIndex, storage.length - 1), effectiveRange: nil),
           let url = EditorLinkRules.url(from: link) {
            menu.addItem(EditorMenuItem(title: "Open Link") { NSWorkspace.shared.open(url) })
            menu.addItem(EditorMenuItem(title: "Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            })
            if isEditable {
                menu.addItem(EditorMenuItem(title: "Edit Link…") { [weak self] in self?.perform(.insertLink) })
                menu.addItem(EditorMenuItem(title: "Remove Link") { [weak self] in self?.removeLink(at: linkIndex) })
            }
            menu.addItem(.separator())
        }
        // 2. Cut / Copy / Paste / Paste text only / Select All.
        menu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: ""))
        let plain = NSMenuItem(title: "Paste text only", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v")
        plain.keyEquivalentModifierMask = [.command, .option, .shift]
        plain.toolTip = "Paste the clipboard as plain text, dropping all formatting."
        menu.addItem(plain)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: ""))
        for item in menu.items where item.action != nil && item.target == nil { item.target = tv }
        return menu
    }

    private struct MisspelledWord { var range: NSRange; var word: String; var guesses: [String] }

    private func misspelledWord(at index: Int) -> MisspelledWord? {
        let tv = textView
        guard storage.length > 0, tv.isContinuousSpellCheckingEnabled else { return nil }
        let probe = min(max(0, index), storage.length - 1)
        let wordRange = tv.selectionRange(forProposedRange: NSRange(location: probe, length: 0), granularity: .selectByWord)
        guard wordRange.length > 0, NSMaxRange(wordRange) <= storage.length else { return nil }
        let word = (storage.string as NSString).substring(with: wordRange)
        let checker = NSSpellChecker.shared
        let miss = checker.checkSpelling(of: word, startingAt: 0, language: nil, wrap: false,
                                         inSpellDocumentWithTag: tv.spellCheckerDocumentTag, wordCount: nil)
        guard miss.location != NSNotFound, miss.length > 0 else { return nil }
        let guesses = checker.guesses(forWordRange: miss, in: word, language: nil,
                                      inSpellDocumentWithTag: tv.spellCheckerDocumentTag) ?? []
        return MisspelledWord(range: NSRange(location: wordRange.location + miss.location, length: miss.length),
                              word: (word as NSString).substring(with: miss), guesses: guesses)
    }

    private func correctSpelling(_ range: NSRange, with guess: String) {
        guard isEditable, NSMaxRange(range) <= storage.length else { return }
        // The lock is re-checked at click time (CONT-033).
        if hasAnyLock, EditorLocking.editBlocked(storage, range: range, replacementLength: guess.utf16.count) {
            showLockedHint()
            return
        }
        let attrs = storage.attributes(at: range.location, effectiveRange: nil)
        apply(EditorTextEdit(range: range, replacement: NSAttributedString(string: guess, attributes: attrs),
                             selectionAfter: NSRange(location: range.location + guess.utf16.count, length: 0)),
              actionName: "Correct Spelling")
    }

    private func ignoreSpelling(_ word: String) {
        let tv = textView
        NSSpellChecker.shared.ignoreWord(word, inSpellDocumentWithTag: tv.spellCheckerDocumentTag)
        tv.checkTextInDocument(nil)
    }
}

// MARK: - NSTextViewDelegate / NSTextStorageDelegate

extension EditorController: NSTextViewDelegate, NSTextStorageDelegate {
    /// The lock gate (§6.8): typing, IME, Backspace/Delete, cut, paste, drag-move, spelling, Services, dictation,
    /// find-and-replace and undo of text all pass here. Attribute-only changes are allowed (D-4).
    func textView(_ textView: NSTextView, shouldChangeTextInRanges affectedRanges: [NSValue],
                  replacementStrings: [String]?) -> Bool {
        if loading || bypassLockGate { return true }
        guard let strings = replacementStrings else { return true }
        guard isEditable else { return false }
        guard hasAnyLock else { return true }
        for (i, v) in affectedRanges.enumerated() {
            let r = v.rangeValue
            let len = i < strings.count ? strings[i].utf16.count : 0
            if EditorLocking.editBlocked(storage, range: r, replacementLength: len) {
                showLockedHint()
                return false
            }
        }
        return true
    }

    func textDidChange(_ notification: Notification) {
        guard !loading, !previewMode else { return }
        session.noteEdited()
        refreshSummary()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !loading, let tv = _textView else { return }
        var typing = tv.typingAttributes
        var changed = false
        let sel = tv.selectedRange()
        // Boundaries stay editable (§7.4) and typed text never inherits a list marker, an in-run newline or a
        // preserved fragment (the writer would drop or repeat it).
        if EditorFormatting.needsCleaning(typing) {
            typing = EditorFormatting.cleanTypingAttributes(typing, in: storage, caret: sel.location)
            changed = true
        }
        if sel.length == 0, typing[.link] != nil {
            // Typing at the end of a link does not extend it.
            let next = sel.location < storage.length ? storage.attribute(.link, at: sel.location, effectiveRange: nil) : nil
            if next == nil {
                typing = EditorLinkRules.removingLink(typing)
                changed = true
            }
        }
        if changed { tv.typingAttributes = typing }
        refreshSummary()
    }

    func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

    nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                                 range editedRange: NSRange, changeInLength delta: Int) {
        MainActor.assumeIsolated {
            // A paste or highlight may bring a lock in (CONT-065 fast-path flag).
            guard !hasAnyLock, editedRange.length > 0, NSMaxRange(editedRange) <= textStorage.length else { return }
            if EditorLocking.hasAnyLock(textStorage.attributedSubstring(from: editedRange)) {
                hasAnyLock = true
                session.setHasAnyLock(true)
            }
        }
    }
}

// MARK: - Helpers

/// A menu item that runs a closure.
@MainActor final class EditorMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}

/// Keeps the document as wide as the visible (magnified) clip view so zoomed text re-wraps instead of scrolling
/// sideways; reports magnification changes.
final class EditorScrollView: NSScrollView {
    var onMagnificationChanged: ((CGFloat) -> Void)?

    override var magnification: CGFloat {
        didSet {
            fitDocumentWidth()
            onMagnificationChanged?(magnification)
        }
    }

    override func endGesture(with event: NSEvent) {
        super.endGesture(with: event)
        onMagnificationChanged?(magnification)
    }

    override func tile() {
        super.tile()
        fitDocumentWidth()
    }

    override func reflectScrolledClipView(_ cView: NSClipView) {
        super.reflectScrolledClipView(cView)
        fitDocumentWidth()
    }

    private func fitDocumentWidth() {
        guard let doc = documentView else { return }
        let w = contentView.bounds.width
        if w > 0, abs(doc.frame.width - w) > 0.5 { doc.setFrameSize(NSSize(width: w, height: doc.frame.height)) }
    }
}

/// §6.12 — one editable editor per container: the newest binding wins; older ones park (read-only, flushed) and
/// reload when it goes away.
@MainActor enum EditorBindingRegistry {
    private struct Entry { weak var controller: EditorController?; let container: ObjectIdentifier }
    private static var entries: [Entry] = []

    static func claim(_ c: EditorController, container: Container) {
        let id = ObjectIdentifier(container)
        entries.removeAll { $0.controller == nil || $0.controller === c }
        for e in entries where e.container == id { e.controller?.park() }
        entries.append(Entry(controller: c, container: id))
    }

    static func release(_ c: EditorController, container: Container) {
        let id = ObjectIdentifier(container)
        let wasHolder = entries.last(where: { $0.container == id })?.controller === c
        entries.removeAll { $0.controller == nil || $0.controller === c }
        if wasHolder, let next = entries.last(where: { $0.container == id })?.controller { next.unpark() }
    }
}
