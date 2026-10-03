// Spec: 06 Addendum BUILD-136…150, A22, A28 (one shared prompt: OK always enabled, raw value, line-break cut, select-all,
//       no substitutions, Esc / ⌘. cancel, prompt wraps, secure variant with reveal toggle, optional help line), 03
//       SHELL-162, 04 HIER-130, 07 VIEW-204; ARCHITECTURE.md §7.5.
import AppKit
import SwiftUI
import AACore

struct TextPromptSheet: View {
    let request: TextPromptRequest
    let finish: (TextPromptResult) -> Void
    @State private var text: String
    @State private var reveal = false
    @State private var done = false

    init(request: TextPromptRequest, finish: @escaping (TextPromptResult) -> Void) {
        self.request = request
        self.finish = finish
        _text = State(initialValue: ShellPromptText.singleLine(request.initial))
    }

    private func complete(_ r: TextPromptResult) {
        guard !done else { return }                          // BUILD-139: fire exactly once
        done = true
        finish(r)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(request.title).font(.system(size: 14, weight: .bold))
            Text(request.prompt)
                .fixedSize(horizontal: false, vertical: true)    // wraps (BUILD-141)
            ShellRawSingleLineField(text: $text, secure: request.isSecure && !reveal,
                                    onSubmit: { complete(.ok(text)) }, onCancel: { complete(.cancelled) })
                .frame(height: 24)
                .accessibilityLabel(request.prompt)
            if let help = request.helpText {
                Text(help).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if request.isSecure {
                    Toggle(isOn: $reveal) { Image(systemName: reveal ? "eye.slash" : "eye") }
                        .toggleStyle(.button)
                        .help(reveal ? "Hide the key" : "Show the key")
                }
                Spacer()
                Button("Cancel") { complete(.cancelled) }.keyboardShortcut(.cancelAction)
                Button("OK") { complete(.ok(text)) }
                    .keyboardShortcut(.defaultAction)                 // never .disabled — BUILD-137
                    .aaProminent()
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(minWidth: 440, idealWidth: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onDisappear { complete(.cancelled) }                     // any other dismissal = Cancel
        .accessibilityLabel(request.title)
        .aaSheet(.decision)
    }
}

/// BUILD-A28 single-line filtering.
enum ShellPromptText {
    /// `\n`, `\r`, `\v`, `\f`, U+0085, U+2028, U+2029 — the WPF `TextEditor._FilterText` set.
    static let lineBreaks: Set<Character> = ["\n", "\r", "\r\n", "\u{0B}", "\u{0C}", "\u{85}", "\u{2028}", "\u{2029}"]

    /// Text cut at the first line break.
    static func singleLine(_ s: String) -> String {
        if let i = s.firstIndex(where: { lineBreaks.contains($0) }) { return String(s[..<i]) }
        return s
    }
}

/// An `NSTextField` / `NSSecureTextField` that returns raw text: no smart quotes/dashes, replacement, autocorrect or
/// capitalisation; pasted multi-line text is cut at the first line break; the initial text is fully selected.
struct ShellRawSingleLineField: NSViewRepresentable {
    @Binding var text: String
    var secure: Bool
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        install(in: container, context: context, focus: true)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.isSecure != secure {
            container.subviews.forEach { $0.removeFromSuperview() }
            install(in: container, context: context, focus: true)
        } else if let f = context.coordinator.field, f.stringValue != text {
            f.stringValue = text
        }
    }

    private func install(in container: NSView, context: Context, focus: Bool) {
        let field: NSTextField = secure ? NSSecureTextField() : NSTextField()
        field.stringValue = text
        field.delegate = context.coordinator
        field.bezelStyle = .roundedBezel
        field.isBordered = true
        field.lineBreakMode = .byClipping
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            field.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        context.coordinator.field = field
        context.coordinator.isSecure = secure
        if focus {
            DispatchQueue.main.async { [weak field] in
                guard let field, let w = field.window else { return }
                w.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)                  // BUILD-140
                Coordinator.configure(field.currentEditor())
            }
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ShellRawSingleLineField
        weak var field: NSTextField?
        var isSecure = false

        init(_ p: ShellRawSingleLineField) { parent = p }

        static func configure(_ editor: NSText?) {
            guard let tv = editor as? NSTextView else { return }
            tv.isAutomaticQuoteSubstitutionEnabled = false
            tv.isAutomaticDashSubstitutionEnabled = false
            tv.isAutomaticTextReplacementEnabled = false
            tv.isAutomaticSpellingCorrectionEnabled = false
            tv.isAutomaticLinkDetectionEnabled = false
            tv.isAutomaticDataDetectionEnabled = false
            tv.smartInsertDeleteEnabled = false
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            Coordinator.configure(obj.userInfo?["NSFieldEditor"] as? NSText)
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let f = field else { return }
            let cut = ShellPromptText.singleLine(f.stringValue)
            if cut != f.stringValue { f.stringValue = cut }
            if parent.text != cut { parent.text = cut }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) || sel == #selector(NSResponder.insertLineBreak(_:))
                || sel == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                parent.text = ShellPromptText.singleLine(control.stringValue)
                parent.onSubmit()
                return true
            }
            if sel == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}
