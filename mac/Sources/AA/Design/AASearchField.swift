// Spec: 03 §6.5.1.5 (a search field clears on ⎋), SHELL-517 (⌥⌘F target via `.aaFilterField`); ARCHITECTURE.md §8.6.
import AppKit
import SwiftUI

/// An `NSSearchField`-backed filter field (clear button, ⎋ clears, Return submits). Combine with
/// `.aaFilterField(for:)` to make it the window's ⌥⌘F target.
struct AASearchField: View {
    @Binding var text: String
    var prompt: String = "Search"
    var onSubmit: (() -> Void)? = nil
    @FocusState private var focused: Bool
    @State private var holder = ShellSearchFieldHolder()

    init(text: Binding<String>, prompt: String = "Search", onSubmit: (() -> Void)? = nil) {
        _text = text
        self.prompt = prompt
        self.onSubmit = onSubmit
    }

    var body: some View {
        ShellSearchFieldRepresentable(text: $text, prompt: prompt, onSubmit: onSubmit, holder: holder)
            .frame(minWidth: 120, idealHeight: 24)
            .fixedSize(horizontal: false, vertical: true)
            .focusable()
            .focused($focused)
            .onChange(of: focused) { _, f in
                // SwiftUI focus (e.g. ⌥⌘F through `.aaFilterField`) → AppKit first responder.
                if f, let field = holder.field, let w = field.window { w.makeFirstResponder(field) }
            }
    }
}

struct ShellSearchFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    var prompt: String
    var onSubmit: (() -> Void)?
    let holder: ShellSearchFieldHolder

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let f = NSSearchField()
        f.placeholderString = prompt
        f.delegate = context.coordinator
        f.sendsSearchStringImmediately = true
        f.sendsWholeSearchString = false
        f.target = context.coordinator
        f.action = #selector(Coordinator.changed(_:))
        f.font = .systemFont(ofSize: NSFont.systemFontSize)
        holder.field = f
        return f
    }

    func updateNSView(_ f: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if f.stringValue != text { f.stringValue = text }
        f.placeholderString = prompt
        holder.field = f
    }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: ShellSearchFieldRepresentable
        init(_ p: ShellSearchFieldRepresentable) { parent = p }

        @objc func changed(_ sender: NSSearchField) {
            if parent.text != sender.stringValue { parent.text = sender.stringValue }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let f = obj.object as? NSSearchField else { return }
            if parent.text != f.stringValue { parent.text = f.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit?()
                return true
            }
            return false
        }
    }
}

/// The AppKit field behind one `AASearchField`.
@MainActor final class ShellSearchFieldHolder {
    weak var field: NSSearchField?
}
