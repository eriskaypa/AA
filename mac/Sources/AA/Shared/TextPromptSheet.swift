// Spec: 06 Addendum BUILD-136…150, A22, A28 (one shared prompt: OK always enabled, raw value, line-break cut, select-all,
//       no substitutions, Esc / ⌘. cancel, prompt wraps, secure variant with reveal toggle, optional help line), 03
//       SHELL-162, 04 HIER-130, 07 VIEW-204; ARCHITECTURE.md §7.5.
import AppKit
import SwiftUI
import AACore

struct TextPromptSheet: View {
    let request: TextPromptRequest
    @State private var session: TextPromptSession
    @State private var reveal = false

    init(request: TextPromptRequest, finish: @escaping (TextPromptResult) -> Void) {
        self.request = request
        _session = State(initialValue: TextPromptSession(request: request, onFinish: finish))  // fires once (BUILD-139)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.s) {
            // NSAlert layout: system 13 bold title, 11-pt body, field, then the buttons bottom-trailing.
            Text(request.title).font(.headline)
            Text(request.prompt)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)    // wraps (BUILD-141)
            ShellRawSingleLineField(text: Binding(get: { session.text }, set: { session.setText($0) }),
                                    secure: request.isSecure && !reveal,
                                    onSubmit: { session.ok() }, onCancel: { session.cancel() })
                .frame(height: 22)
                .accessibilityLabel(request.prompt)
            if let help = request.helpText {
                Text(help).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if request.isSecure {
                    Toggle(isOn: $reveal) { Image(systemName: reveal ? "eye.slash" : "eye") }
                        .toggleStyle(.button)
                        .help(reveal ? "Hide the key" : "Show the key")
                }
                Spacer()
                Button("Cancel") { session.cancel() }.keyboardShortcut(.cancelAction)
                Button("OK") { session.ok() }
                    .keyboardShortcut(.defaultAction)                 // never .disabled — BUILD-137
                    .aaProminent()
            }
            .padding(.top, AASpacing.xs)
        }
        .padding(AASpacing.l)
        .frame(minWidth: TextPromptLayout.minWidth, idealWidth: TextPromptLayout.minWidth)
        .fixedSize(horizontal: false, vertical: true)
        .onDisappear { session.cancel() }                         // any other dismissal = Cancel
        .accessibilityLabel(request.title)
        .aaSheet(.decision)
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
        field.delegate = context.coordinator.delegate
        field.isBezeled = true                                      // native rounded bezel (never isBordered)
        field.bezelStyle = .roundedBezel
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

    @MainActor final class Coordinator {
        var parent: ShellRawSingleLineField
        weak var field: NSTextField?
        var isSecure = false
        /// The field-editor rules and line-break cut (AACore, unit-tested by TV-PR-07…09).
        lazy var delegate = ShellRawFieldDelegate(
            onChange: { [weak self] cut in if self?.parent.text != cut { self?.parent.text = cut } },
            onSubmit: { [weak self] cut in self?.parent.text = cut; self?.parent.onSubmit() },
            onCancel: { [weak self] in self?.parent.onCancel() })

        init(_ p: ShellRawSingleLineField) { parent = p }

        static func configure(_ editor: NSText?) { ShellRawFieldEditing.configure(editor) }
    }
}
