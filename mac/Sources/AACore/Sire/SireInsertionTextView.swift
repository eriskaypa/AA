// Spec: 12 SIRE-022 (insertion-only editing), SIRE-025 (context menu: Copy / Paste (insert) / Select All), §6.3,
//       §6.4 rules 1–8 (the single gate `shouldChangeText`, collapse-before-insert, blocked delete/transpose/case
//       commands, no drag and drop, nothing that rewrites existing text — autocorrect, substitutions, Writing Tools,
//       find-and-replace —, sanitised paste without attachments, light paper), 03 SHELL-688 (SIRE body keys).
//       Lives in AACore so the gate is unit-testable; the AA target subclasses it to adopt AARichTextResponder.
import AppKit

/// A TextKit 1 `NSTextView` that only ever inserts: the original text can never be deleted or replaced.
open class SireInsertionTextView: NSTextView {
    /// True while the owner replaces the whole document (load / reset); the gate lets those changes through.
    public var isLoadingContent = false
    /// Called when the view stops being first responder (flush trigger, §6.4 rule 9b).
    public var onResignFirstResponder: (() -> Void)?

    /// The TextKit 1 storage this view owns (a text view does not retain its storage itself).
    private var sireOwnedStorage: NSTextStorage?

    /// A view on its own TextKit 1 stack (NSTextBlock chips and NSTextList markers need TextKit 1), already
    /// configured insertion-only.
    public convenience init(textKit1Frame frame: NSRect) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: frame.width, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        self.init(frame: frame, textContainer: container)
        sireOwnedStorage = storage
        configureInsertionOnly()
    }

    public override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// §6.4 rules 4, 5, 8.
    public func configureInsertionOnly() {
        isRichText = true
        importsGraphics = false
        allowsImageEditing = false
        allowsUndo = true
        usesFontPanel = false
        usesInspectorBar = false
        usesRuler = false
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticTextCompletionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        smartInsertDeleteEnabled = false
        writingToolsBehavior = .none
        inlinePredictionType = .no
        displaysLinkToolTips = true
        unregisterDraggedTypes()
    }

    // MARK: Rule 1 — the gate

    /// Whether a change of `range` may happen: undo/redo, loads, and changes inside IME marked text pass; any
    /// change that touches existing characters (replacement or attribute change) is refused.
    public func sireAllowsChange(in range: NSRange) -> Bool {
        if isLoadingContent { return true }
        if let um = undoManager, um.isUndoing || um.isRedoing { return true }
        if range.length == 0 { return true }
        if hasMarkedText() {
            let m = markedRange()
            if m.location != NSNotFound, NSIntersectionRange(m, range) == range { return true }
        }
        return false
    }

    open override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard sireAllowsChange(in: affectedCharRange) else { return false }
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    open override func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        for v in affectedRanges where !sireAllowsChange(in: v.rangeValue) { return false }
        return super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings)
    }

    // MARK: Rule 2 — collapse the selection to its start before inserting

    /// Collapses a non-empty selection to its start (never while composing marked text).
    public func sireCollapseSelection() {
        guard !hasMarkedText() else { return }
        let sel = selectedRange()
        if sel.length > 0 { setSelectedRange(NSRange(location: sel.location, length: 0)) }
    }

    open override func insertText(_ string: Any, replacementRange: NSRange) {
        var r = replacementRange
        if !hasMarkedText() {
            sireCollapseSelection()
            if r.location != NSNotFound, r.length > 0 { r = NSRange(location: r.location, length: 0) }
        }
        super.insertText(string, replacementRange: r)
    }

    open override func insertNewline(_ sender: Any?) { sireCollapseSelection(); super.insertNewline(sender) }
    open override func insertParagraphSeparator(_ sender: Any?) { sireCollapseSelection(); super.insertParagraphSeparator(sender) }
    open override func insertLineBreak(_ sender: Any?) { sireCollapseSelection(); super.insertLineBreak(sender) }
    open override func insertTab(_ sender: Any?) { sireCollapseSelection(); super.insertTab(sender) }
    open override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
        sireCollapseSelection(); super.insertNewlineIgnoringFieldEditor(sender)
    }
    open override func insertTabIgnoringFieldEditor(_ sender: Any?) {
        sireCollapseSelection(); super.insertTabIgnoringFieldEditor(sender)
    }
    open override func insertContainerBreak(_ sender: Any?) { sireCollapseSelection(); super.insertContainerBreak(sender) }
    open override func insertSingleQuoteIgnoringSubstitution(_ sender: Any?) {
        sireCollapseSelection(); super.insertSingleQuoteIgnoringSubstitution(sender)
    }
    open override func insertDoubleQuoteIgnoringSubstitution(_ sender: Any?) {
        sireCollapseSelection(); super.insertDoubleQuoteIgnoringSubstitution(sender)
    }

    // MARK: Paste (rule 2 + rule 6)

    open override func paste(_ sender: Any?) { sireCollapseSelection(); sirePaste(rich: true) }
    open override func pasteAsRichText(_ sender: Any?) { sireCollapseSelection(); sirePaste(rich: true) }
    open override func pasteAsPlainText(_ sender: Any?) { sireCollapseSelection(); sirePaste(rich: false) }
    open override func pasteFont(_ sender: Any?) {}
    open override func pasteRuler(_ sender: Any?) {}

    /// The pasteboard content to insert: AA XAML fragment → RTFD / RTF (attachments stripped) → plain text.
    public func sirePasteContent(from pb: NSPasteboard, rich: Bool) -> NSAttributedString? {
        if rich {
            if let x = pb.string(forType: NSPasteboard.PasteboardType(Identifiers.utXaml)),
               let frag = XamlReader.readFragment(x, destinationContext: .sirePane) {
                return Self.strippingAttachments(frag)
            }
            if let d = pb.data(forType: .rtfd), let a = NSAttributedString(rtfd: d, documentAttributes: nil) {
                return Self.strippingAttachments(a)
            }
            if let d = pb.data(forType: .rtf), let a = NSAttributedString(rtf: d, documentAttributes: nil) {
                return Self.strippingAttachments(a)
            }
        }
        if let s = pb.string(forType: .string) {
            return NSAttributedString(string: s, attributes: typingAttributes)
        }
        return nil
    }

    func sirePaste(rich: Bool) {
        guard let content = sirePasteContent(from: .general, rich: rich), content.length > 0 else { return }
        super.insertText(content, replacementRange: selectedRange())
    }

    /// Removes attachment characters (images are not representable in the stored XAML).
    public static func strippingAttachments(_ a: NSAttributedString) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: a)
        var ranges: [NSRange] = []
        m.enumerateAttribute(.attachment, in: NSRange(location: 0, length: m.length)) { v, r, _ in
            if v != nil { ranges.append(r) }
        }
        for r in ranges.reversed() { m.deleteCharacters(in: r) }
        return m
    }

    // MARK: Rule 3 — blocked commands

    open override func deleteBackward(_ sender: Any?) {}
    open override func deleteForward(_ sender: Any?) {}
    open override func deleteWordBackward(_ sender: Any?) {}
    open override func deleteWordForward(_ sender: Any?) {}
    open override func deleteToBeginningOfLine(_ sender: Any?) {}
    open override func deleteToEndOfLine(_ sender: Any?) {}
    open override func deleteToBeginningOfParagraph(_ sender: Any?) {}
    open override func deleteToEndOfParagraph(_ sender: Any?) {}
    open override func deleteBackwardByDecomposingPreviousCharacter(_ sender: Any?) {}
    open override func deleteToMark(_ sender: Any?) {}
    open override func cut(_ sender: Any?) {}
    open override func delete(_ sender: Any?) {}
    open override func transpose(_ sender: Any?) {}
    open override func transposeWords(_ sender: Any?) {}
    open override func capitalizeWord(_ sender: Any?) {}
    open override func lowercaseWord(_ sender: Any?) {}
    open override func uppercaseWord(_ sender: Any?) {}
    open override func changeCaseOfLetter(_ sender: Any?) {}
    open override func yank(_ sender: Any?) {}
    open override func complete(_ sender: Any?) {}

    static let blockedActions: Set<Selector> = [
        #selector(NSText.cut(_:)), #selector(NSText.delete(_:)), #selector(NSResponder.transpose(_:)),
        #selector(NSResponder.transposeWords(_:)), #selector(NSResponder.capitalizeWord(_:)),
        #selector(NSResponder.lowercaseWord(_:)), #selector(NSResponder.uppercaseWord(_:)),
        #selector(NSResponder.yank(_:)), #selector(NSTextView.complete(_:)), #selector(NSText.pasteFont(_:)),
        #selector(NSText.pasteRuler(_:)), #selector(NSResponder.changeCaseOfLetter(_:)),
    ]

    /// Find-bar actions that would replace text.
    static let replaceActions: Set<Int> = [
        NSTextFinder.Action.replace.rawValue, NSTextFinder.Action.replaceAll.rawValue,
        NSTextFinder.Action.replaceAndFind.rawValue, NSTextFinder.Action.replaceAllInSelection.rawValue,
    ]

    open override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if let action = item.action {
            if Self.blockedActions.contains(action) { return false }
            if action == #selector(NSTextView.performTextFinderAction(_:)), Self.replaceActions.contains(item.tag) { return false }
        }
        return super.validateUserInterfaceItem(item)
    }

    open override func performTextFinderAction(_ sender: Any?) {
        if let item = sender as? NSValidatedUserInterfaceItem, Self.replaceActions.contains(item.tag) { return }
        super.performTextFinderAction(sender)
    }

    // MARK: Rule 4 — no drag and drop

    open override func dragSelection(with event: NSEvent, offset mouseOffset: NSSize, slideBack: Bool) -> Bool { false }
    open override var acceptableDragTypes: [NSPasteboard.PasteboardType] { [] }

    // MARK: Services may read the selection but never write back

    open override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?,
                                      returnType: NSPasteboard.PasteboardType?) -> Any? {
        if returnType != nil { return nil }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    // MARK: Rule 7 — context menu

    open override func menu(for event: NSEvent) -> NSMenu? { Self.contextMenu() }

    /// Exactly `Copy`, `Paste (insert)`, `Select All` (SIRE-025).
    public static func contextMenu() -> NSMenu {
        let m = NSMenu(title: "")
        m.autoenablesItems = true
        m.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: ""))
        m.addItem(NSMenuItem(title: "Paste (insert)", action: #selector(NSText.paste(_:)), keyEquivalent: ""))
        m.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: ""))
        return m
    }

    // MARK: Focus

    open override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onResignFirstResponder?() }
        return ok
    }

    // MARK: Loading

    /// Replaces the whole document (gate bypassed) and clears the undo stack — loading never becomes undoable.
    public func sireLoad(_ text: NSAttributedString) {
        isLoadingContent = true
        defer { isLoadingContent = false }
        textStorage?.setAttributedString(text)
        undoManager?.removeAllActions(withTarget: self)
        if let ts = textStorage { undoManager?.removeAllActions(withTarget: ts) }
        setSelectedRange(NSRange(location: 0, length: 0))
    }
}
