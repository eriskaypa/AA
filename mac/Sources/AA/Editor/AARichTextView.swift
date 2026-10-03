// Spec: 05 §6.2 (TextKit 1 text view: spelling on, grammar and substitutions off, paper look, link attributes, find
//       bar), §6.3 (keys), §6.5 (list keys), §6.6 (paste / drop pipeline incl. our XAML type), §6.8 (lock gate,
//       spelling menu on locked words), CONT-033 (right-click menu), CONT-034 (Paste text only), 03 SHELL-514 / 685
//       (⎋ and ⌘. pass to the next responder; completion stays on ⌥⎋ / F5), SHELL-678 (⌘-click opens links), SHELL-679
//       (drop modifiers), SHELL-680…682, §6.5.1.13 (rich-text views validate every Format item, no app-key
//       performKeyEquivalent overrides); ARCHITECTURE.md §7.6 (`AARichTextResponder`).
import AppKit
import AACore

/// The container editor's text view. Commands are forwarded to its `EditorController`.
@MainActor final class AARichTextView: NSTextView, AARichTextResponder {
    weak var editor: EditorController?

    var aaRichKind: RichKind { .container }
    func aaValidate(_ c: FormatCommand) -> Bool { editor?.validate(c) ?? false }
    func aaPerform(_ c: FormatCommand) { editor?.perform(c) }

    // MARK: Keys (SHELL-680…682)

    override func insertTab(_ sender: Any?) {
        if editor?.handleTab(shift: false) == true { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if editor?.handleTab(shift: true) == true { return }
        super.insertBacktab(sender)
    }

    override func insertNewline(_ sender: Any?) {
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {   // ⇧↩ = line break (CONT-030)
            insertLineBreak(sender)
            return
        }
        if editor?.handleReturn() == true { return }
        super.insertNewline(sender)
    }

    /// ⌃↩ (and ⌥↩) insert a line break too (SHELL-681 optional alias).
    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) { insertLineBreak(sender) }

    override func deleteBackward(_ sender: Any?) {
        if editor?.handleBackspaceAtItemStart() == true { return }
        super.deleteBackward(sender)
    }

    /// SHELL-514: ⎋ / ⌘. close or cancel the surrounding sheet instead of opening word completion.
    override func cancelOperation(_ sender: Any?) {
        _ = nextResponder?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: sender)
    }

    // MARK: Paste text only (CONT-034)

    override func pasteAsPlainText(_ sender: Any?) { editor?.pasteTextOnly() }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(pasteAsPlainText(_:)) {
            return isEditable && NSPasteboard.general.availableType(from: [.string]) != nil
        }
        return super.validateUserInterfaceItem(item)
    }

    // MARK: Paste and drop (§6.6)

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { EditorPaste.readableTypes }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { EditorPaste.readableTypes }

    override func preferredPasteboardType(from availableTypes: [NSPasteboard.PasteboardType],
                                          restrictedToTypesFrom allowedTypes: [NSPasteboard.PasteboardType]?) -> NSPasteboard.PasteboardType? {
        let types = allowedTypes.map { allowed in availableTypes.filter { allowed.contains($0) } } ?? availableTypes
        switch EditorPaste.preferredKind(types) {
        case .aaXaml: return EditorPaste.xamlType
        case .fileURLs: return EditorPaste.fileURLType
        case .rtfd: return types.contains(EditorPaste.rtfdType) ? EditorPaste.rtfdType : EditorPaste.flatRtfdType
        case .rtf: return EditorPaste.rtfType
        case .html: return EditorPaste.htmlType
        case .string: return EditorPaste.stringType
        case .image: return EditorPaste.imageTypes.first { types.contains($0) }
        case nil: return super.preferredPasteboardType(from: availableTypes, restrictedToTypesFrom: allowedTypes)
        }
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if let editor { return editor.paste(from: pboard, type: type) }
        return super.readSelection(from: pboard, type: type)
    }

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        var t = super.writablePasteboardTypes
        if editor?.canWriteXaml == true, !t.contains(EditorPaste.xamlType) { t.insert(EditorPaste.xamlType, at: 0) }
        return t
    }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if type == EditorPaste.xamlType {
            guard let xaml = editor?.selectedXaml() else { return false }
            return pboard.setString(xaml, forType: type)
        }
        return super.writeSelection(to: pboard, type: type)
    }

    // MARK: Fonts and colours from the system panels (SHELL-600, SHELL-608)

    override func changeFont(_ sender: Any?) {
        guard let editor else { super.changeFont(sender); return }
        let before = editor.snapshotForFontChange()
        super.changeFont(sender)
        editor.reconcileFontTokens(before: before)
    }

    override func changeColor(_ sender: Any?) {
        guard let editor, let panel = sender as? NSColorPanel else { super.changeColor(sender); return }
        editor.applyPanelColor(panel.color)
    }

    // MARK: Links (SHELL-678: ⌘-click opens; a plain click only places the caret)

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let editor, editor.openLink(at: convert(event.locationInWindow, from: nil)) {
            return
        }
        super.mouseDown(with: event)
    }

    override func clicked(onLink link: Any, at charIndex: Int) {
        // Editable notes never open a link on a plain click (Windows parity); ⌘-click is handled in mouseDown.
    }

    // MARK: Context menu (CONT-033)

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let editor else { return super.menu(for: event) }
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        let sel = selectedRange()
        if !(sel.length > 0 && index >= sel.location && index <= NSMaxRange(sel)) {
            setSelectedRange(NSRange(location: index, length: 0))     // right-click moves the caret
        }
        return editor.contextMenu(at: index)
    }

    // MARK: Undo

    override var undoManager: UndoManager? { editor?.undoManager ?? super.undoManager }
}
