// Spec: 13 FLASH-044 (never apply silently; the exact review text; safe default = don't apply), FLASH-045/046,
//       FLASH-132 (no-settings note), FLASH-135 (rich review sheet: per-collection breakdown, removals in red),
//       §6.6 (Apply — destructive for a snapshot — / Don't Apply, the safe button is the default for Return and Esc),
//       DEV-FLASH-29 (the snapshot Apply is visibly destructive: red label, like NSAlert's destructive button),
//       ARCH §7.5 (a …Sheet is a content view; `.aaSheet(.decision)`).
import SwiftUI
import AACore

struct FlashReviewSheet: View {
    let change: FlashIncomingChange
    let finish: (Bool) -> Void

    private var rows: [FlashReviewRow] { FlashReviewBreakdown.rows(for: change) }
    @State private var listHeight: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: AASpacing.m) {
                Image(systemName: change.isSnapshot ? "exclamationmark.triangle.fill" : "square.and.arrow.down.on.square.fill")
                    .font(.system(size: 30, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(change.isSnapshot ? AAColor.Status.danger : AAColor.tint)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: AASpacing.s) {
                    Text(FlashSyncTexts.applyTitle)                      // NSAlert layout: 13 bold title
                        .font(.system(size: AAType.body, weight: .bold))
                    Text(FlashSyncTexts.applyQuestion(change))           // 11-pt informative text
                        .font(.system(size: AAType.caption))
                        .foregroundStyle(AAColor.fg)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .padding(AASpacing.l)

            // Sized to its measured rows (never a clipped last row); scrolls only past 380 pt.
            ScrollView {
                breakdown.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(listHeight ?? CGFloat(rows.count) * 29.5, 380))
            .background(AAColor.panel, in: RoundedRectangle(cornerRadius: AARadius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AARadius.tile, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
            .padding(.horizontal, AASpacing.l)
            .padding(.bottom, AASpacing.l)

            Divider()
            HStack(spacing: AASpacing.s) {
                Spacer()
                if change.isSnapshot {
                    // DEV-FLASH-29: a bordered `.destructive` button is not coloured on macOS — the red label is.
                    Button(role: .destructive) { finish(true) } label: {
                        Text(FlashSyncTexts.applyButton).foregroundStyle(AAColor.Status.danger)
                    }
                    .help(FlashSyncTexts.applySnapshotHelp)
                } else {
                    Button(FlashSyncTexts.applyButton) { finish(true) }
                }
                Button(FlashSyncTexts.dontApplyButton) { finish(false) }
                    .keyboardShortcut(.defaultAction)
                    .background {
                        Button("") { finish(false) }.keyboardShortcut(.cancelAction).opacity(0).allowsHitTesting(false)
                    }
            }
            .controlSize(.large)
            .padding(.horizontal, AASpacing.l)
            .padding(.vertical, AASpacing.s)
            .frame(minHeight: 44)
        }
        .frame(width: 520)
        .aaSheet(.decision)
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                HStack(spacing: AASpacing.s) {
                    Image(systemName: row.symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.aaMono(AAType.body))
                        .foregroundStyle(color(row.tone))
                        .frame(width: 20)
                    Text(row.title)
                        .font(.aaMono(AAType.body))
                        .foregroundStyle(row.tone == .removed ? AAColor.Status.diffRemoved : AAColor.fg)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer(minLength: AASpacing.s)
                    Text(row.detail)
                        .font(.aaMono(AAType.caption).monospacedDigit())
                        .foregroundStyle(row.tone == .removed ? AAColor.Status.diffRemoved : AAColor.muted)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, AASpacing.m)
                .frame(minHeight: 22)
                if row.id != rows.last?.id { Divider().padding(.leading, AASpacing.m + 28) }
            }
        }
    }

    private func color(_ tone: FlashReviewRow.Tone) -> Color {
        switch tone {
        case .added: return AAColor.Status.diffAdded
        case .changed: return AAColor.Status.diffChanged
        case .removed: return AAColor.Status.diffRemoved
        case .neutral: return AAColor.muted
        }
    }
}
