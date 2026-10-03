// Spec: 12 SIRE-020…025, SIRE-041 (light paper in both appearances), §6.4 rules 8–10 (paper #FCFCFC, 12 pt inset,
//       vertical scroller; dirty tracking; flush on selection change, focus loss, the app-wide flush hook and after
//       750 ms of idle typing — Q-8 fix; unreadable saved edits are shown read-only with a banner — Q-9 fix), §6.5,
//       03 SHELL-688 (SIRE body keys: ⌘B/⌘I/⌘U typing attributes only), ARCHITECTURE.md §6.7 (W-RICH reader/writer
//       with the `.sirePane` context; never persist through the placeholder), §7.6 (AARichTextResponder).
import AppKit
import Observation
import SwiftUI
import AACore

/// Owns the body document of the selected question: load, dirty tracking, flush, reset.
@MainActor @Observable
final class SireBodyController {
    enum Mode: Equatable {
        /// No question selected.
        case empty
        /// Insertion-only editing; flushed to `SireState.QuestionBodies`.
        case editable
        /// The generated original, read-only (the rich-text engine is not available in this build).
        case readOnly
        /// Saved edits that cannot be displayed: the original is shown read-only and the stored XAML is kept (Q-9).
        case withheld
    }

    private(set) var mode: Mode = .empty
    private(set) var questionNumber: String?

    @ObservationIgnored private weak var env: AppEnvironment?
    @ObservationIgnored private(set) weak var textView: SireBodyTextView?
    @ObservationIgnored private var content = NSAttributedString()
    @ObservationIgnored private var metadata: RichTextMetadata?
    @ObservationIgnored private var question: SireQuestion?
    @ObservationIgnored private(set) var isDirty = false
    @ObservationIgnored private var loadedState: ObjectIdentifier?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private lazy var delegate = SireBodyTextDelegate(owner: self)

    /// 750 ms idle debounce (§6.4 rule 9d).
    static let idleFlush: Duration = .milliseconds(750)

    /// Whether the W-RICH converter is real (no persisting through the placeholder, ARCH §6.7).
    var richEngineAvailable: Bool { ContractStatus.isImplemented(.wRich) }

    func attach(_ env: AppEnvironment) { self.env = env }

    func attachView(_ tv: SireBodyTextView) {
        textView = tv
        tv.delegate = delegate
        tv.onResignFirstResponder = { [weak self] in self?.flush() }
        push()
    }

    // MARK: Load (SIRE-023)

    /// Shows `q`'s saved body when present and readable, else the freshly generated original.
    func load(question q: SireQuestion?) {
        debounce?.cancel()
        isDirty = false
        question = q
        questionNumber = q?.questionNumber
        metadata = nil
        guard let q, let env else {
            mode = .empty
            content = NSAttributedString()
            push()
            return
        }
        let state = env.store.data.sire
        loadedState = ObjectIdentifier(state)
        if let stored = state.questionBodies[q.questionNumber], !stored.isEmpty {
            switch XamlReader.read(stored, context: .sirePane) {
            case .document(let text, let meta) where !meta.isPlaceholderResult && !Self.notLoadable(meta):
                mode = .editable; content = text; metadata = meta
            case .empty(let meta) where !meta.isPlaceholderResult:
                mode = .editable; content = NSAttributedString(); metadata = meta
            default:
                mode = .withheld
                content = SireFlowRenderer.render(SireFlow.buildQuestion(q, body: SireFlow.black))
            }
        } else {
            loadOriginal(q)
        }
        push()
    }

    static func notLoadable(_ m: RichTextMetadata) -> Bool {
        if case .notLoadable = m.loadability { return true }
        return false
    }

    /// The generated original: editable through the W-RICH reader, else rendered read-only.
    private func loadOriginal(_ q: SireQuestion) {
        let original = SireFlow.buildQuestion(q, body: SireFlow.black)
        if richEngineAvailable,
           case .document(let text, let meta) = XamlReader.read(SireFlowXaml.write(original), context: .sirePane),
           !meta.isPlaceholderResult {
            mode = .editable; content = text; metadata = meta
        } else {
            mode = .readOnly
            content = SireFlowRenderer.render(original)
        }
    }

    private func push() {
        guard let tv = textView else { return }
        tv.isEditable = mode == .editable
        tv.isSelectable = true
        tv.sireLoad(content)
        tv.scroll(.zero)
    }

    // MARK: Flush (§6.4 rule 9)

    /// Serialises the document into `QuestionBodies[q]` when edited (Windows: stored even after typing + undo).
    func flush() {
        debounce?.cancel()
        guard isDirty else { return }
        isDirty = false
        guard mode == .editable, let env, let q = questionNumber, let meta = metadata, let tv = textView,
              let storage = tv.textStorage, richEngineAvailable else { return }
        let state = env.store.data.sire
        guard ObjectIdentifier(state) == loadedState else { return }      // never write into a replaced model
        let xaml = XamlWriter.write(storage, metadata: meta, context: .sirePane)
        guard !xaml.isEmpty else { return }
        state.questionBodies[q] = xaml
        env.store.markDirty()
    }

    /// SIRE-040: the old edit belonged to the discarded model — drop it without flushing.
    func discardAfterSwap() {
        debounce?.cancel()
        isDirty = false
    }

    // MARK: Reset / edit anyway (SIRE-024, §6.4 rule 10)

    /// `↺ Reset`: removes the saved body (MarkDirty if one existed), discards unflushed edits, reloads the original.
    func reset() {
        guard let env, let q = question else { return }
        debounce?.cancel()
        isDirty = false
        if env.store.data.sire.questionBodies.removeValue(forKey: q.questionNumber) != nil { env.store.markDirty() }
        load(question: q)
    }

    /// `Edit anyway (replaces saved edits)`: the original becomes editable; the next edit replaces the stored body.
    func editAnyway() {
        guard let q = question, richEngineAvailable else { return }
        debounce?.cancel()
        isDirty = false
        loadOriginal(q)
        push()
    }

    // MARK: Text view callbacks

    fileprivate func textDidChange() {
        guard let tv = textView, !tv.isLoadingContent, mode == .editable else { return }
        isDirty = true
        debounce?.cancel()
        debounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: SireBodyController.idleFlush)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    fileprivate func textDidEndEditing() { flush() }
}

/// NSTextView delegate forwarding to the controller (kept separate so the controller stays a plain observable).
@MainActor final class SireBodyTextDelegate: NSObject, NSTextViewDelegate {
    weak var owner: SireBodyController?
    init(owner: SireBodyController) { self.owner = owner }

    func textDidChange(_ notification: Notification) { owner?.textDidChange() }
    func textDidEndEditing(_ notification: Notification) { owner?.textDidEndEditing() }

    /// Links in the body open in the browser (read-only behaviour; never edits text).
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let url = link as? URL { NSWorkspace.shared.open(url); return true }
        if let s = link as? String, let url = URL(string: s) { NSWorkspace.shared.open(url); return true }
        return false
    }
}

/// The SIRE body view: the AACore insertion-only gate plus the Format/Find subset the router may send (§7.6).
final class SireBodyTextView: SireInsertionTextView, AARichTextResponder {
    var aaRichKind: RichKind { .sireBody }

    static let findActions: [FormatCommand: NSTextFinder.Action] = [
        .showFind: .showFindInterface, .findNext: .nextMatch, .findPrevious: .previousMatch,
        .useSelectionForFind: .setSearchString,
    ]

    func aaValidate(_ c: FormatCommand) -> Bool {
        switch c {
        case .bold, .italic, .underline: return isEditable
        case .showFind, .findNext, .findPrevious, .useSelectionForFind, .jumpToSelection: return true
        default: return false
        }
    }

    func aaPerform(_ c: FormatCommand) {
        switch c {
        case .bold: toggleTypingTrait(.boldFontMask)
        case .italic: toggleTypingTrait(.italicFontMask)
        case .underline:
            guard isEditable else { return }
            sireCollapseSelection()
            var t = typingAttributes
            let on = (t[.underlineStyle] as? Int ?? 0) != 0
            t[.underlineStyle] = on ? nil : NSUnderlineStyle.single.rawValue
            typingAttributes = t
        case .jumpToSelection:
            scrollRangeToVisible(selectedRange())
        default:
            guard let action = Self.findActions[c] else { return }
            let item = NSMenuItem()
            item.tag = action.rawValue
            performTextFinderAction(item)
        }
    }

    /// ⌘B / ⌘I: the selection is collapsed first (WPF behaviour), so only text typed afterwards changes.
    private func toggleTypingTrait(_ trait: NSFontTraitMask) {
        guard isEditable else { return }
        sireCollapseSelection()
        var t = typingAttributes
        let font = (t[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 13)
        let fm = NSFontManager.shared
        let has = fm.traits(of: font).contains(trait)
        t[.font] = has ? fm.convert(font, toNotHaveTrait: trait) : fm.convert(font, toHaveTrait: trait)
        typingAttributes = t
    }
}

/// The paper-white editor (forced light appearance, SIRE-041).
struct SireBodyEditor: NSViewRepresentable {
    let controller: SireBodyController

    static let paper = NSColor(srgbRed: 0xFC / 255, green: 0xFC / 255, blue: 0xFC / 255, alpha: 1)

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.appearance = NSAppearance(named: .aqua)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = Self.paper
        let tv = SireBodyTextView(textKit1Frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        tv.appearance = NSAppearance(named: .aqua)
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainerInset = NSSize(width: 12, height: 12)
        tv.textContainer?.lineFragmentPadding = 0
        tv.drawsBackground = true
        tv.backgroundColor = Self.paper
        tv.insertionPointColor = .black
        tv.selectedTextAttributes = [.backgroundColor: NSColor(srgbRed: 0.80, green: 0.91, blue: 1, alpha: 1)]
        tv.typingAttributes = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black]
        tv.setAccessibilityLabel("SIRE question body")
        scroll.documentView = tv
        controller.attachView(tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {}
}
