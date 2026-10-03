// Spec: 05 CONT-031 (title "Insert hyperlink", label "URL:", initial "https://", `Uri.TryCreate(…, Absolute)`, the
//       normalised URI is stored and shown), K-14 (the Mac validates inline: Insert stays disabled until the URL
//       parses — every rejected input is a silent no-op on Windows, so nothing is lost, 06 BUILD-146), 06 Add. row 32;
//       ARCHITECTURE.md §7.5 (sheet contract).
import SwiftUI
import AACore

struct EditorInsertLinkSheet: View {
    let initial: String
    var isEditing = false
    let finish: (String?) -> Void
    @State private var text: String
    @State private var done = false

    init(initial: String, isEditing: Bool = false, finish: @escaping (String?) -> Void) {
        self.initial = initial
        self.isEditing = isEditing
        self.finish = finish
        _text = State(initialValue: initial)
    }

    private var normalised: String? { EditorLinkRules.normalise(text) }

    private func complete(_ r: String?) {
        guard !done else { return }
        done = true
        finish(r)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(EditorLinkRules.sheetTitle, systemImage: "link")
                .font(.system(size: 14, weight: .bold))
            Text(EditorLinkRules.sheetLabel)
            ShellRawSingleLineField(text: $text, secure: false,
                                    onSubmit: { if let n = normalised { complete(n) } else { NSSound.beep() } },
                                    onCancel: { complete(nil) })
                .frame(height: 24)
                .accessibilityLabel(EditorLinkRules.sheetLabel)
            Group {
                if let n = normalised {
                    Label {
                        Text(verbatim: n).font(.aaMono(AAType.caption)).lineLimit(1).truncationMode(.middle)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(AAColor.Status.ok)
                    }
                } else {
                    Label {
                        Text(verbatim: "Type a full address, e.g. https://www.example.com or mailto:name@example.com")
                    } icon: {
                        Image(systemName: "questionmark.circle").foregroundStyle(AAColor.muted)
                    }
                }
            }
            .font(.system(size: AAType.caption))
            .foregroundStyle(AAColor.muted)
            .frame(minHeight: 16, alignment: .leading)
            .animation(.snappy, value: normalised == nil)
            HStack {
                Spacer()
                Button("Cancel") { complete(nil) }.keyboardShortcut(.cancelAction)
                Button(isEditing ? "Update" : "Insert") { if let n = normalised { complete(n) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(normalised == nil)
                    .aaProminent()
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onDisappear { complete(nil) }
        .accessibilityLabel(EditorLinkRules.sheetTitle)
        .aaSheet(.decision)
    }
}
