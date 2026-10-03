// Spec: 11 PDF-023 (ListStylePromptWindow: title "List style", 430 wide, prompt, "• Bulleted" preselected every
//       time, "1. Numbered", muted captions, Cancel (Esc) / bold Continue (Return), never remembered), 05 CONT-049,
//       06 BUILD-094; 11 §6.5 (Mac: a sheet with a radio group and secondary captions).
import SwiftUI
import AACore

/// "Bulleted or numbered?" — `finish(true)` = numbered, `finish(false)` = bulleted, `finish(nil)` = cancelled.
struct PdfListStyleSheet: View {
    let prompt: String
    let finish: (Bool?) -> Void
    @State private var numbered = false                    // bullets preselected, every time
    @State private var done = false

    init(prompt: String = PdfExport.listStyleDefaultPrompt, finish: @escaping (Bool?) -> Void) {
        self.prompt = prompt
        self.finish = finish
    }

    private func complete(_ r: Bool?) {
        guard !done else { return }
        done = true
        finish(r)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.m) {
            HStack(spacing: AASpacing.s) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AAColor.tint)
                Text(PdfExport.listStyleWindowTitle).font(.system(size: 14, weight: .bold))
            }
            Text(prompt)
                .fixedSize(horizontal: false, vertical: true)
            Picker(selection: $numbered) {
                option(PdfExport.bulletedTitle, PdfExport.bulletedCaption).tag(false)
                option(PdfExport.numberedTitle, PdfExport.numberedCaption).tag(true)
            } label: {
                EmptyView()
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .padding(.leading, AASpacing.xs)
            HStack {
                Spacer()
                Button("Cancel") { complete(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Continue") { complete(numbered) }
                    .keyboardShortcut(.defaultAction)
                    .aaProminent()
            }
            .padding(.top, AASpacing.xs)
        }
        .padding(AASpacing.l)
        .frame(width: 430)
        .fixedSize(horizontal: false, vertical: true)
        .onDisappear { complete(nil) }                     // any other dismissal = Cancel
        .accessibilityLabel(PdfExport.listStyleWindowTitle)
        .aaSheet(.decision)
    }

    private func option(_ title: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: AAType.body, weight: .bold))
            Text(caption)
                .font(.system(size: AAType.small))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Both captions wrap at the same measure (the radio group otherwise sizes each label to its own ideal width).
        .frame(width: 350, alignment: .leading)
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
