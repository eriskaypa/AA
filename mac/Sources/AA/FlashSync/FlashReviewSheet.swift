// Spec: 13 FLASH-044 (never apply silently; the exact review text; safe default = don't apply), FLASH-045/046,
//       FLASH-132 (no-settings note), FLASH-135 (rich review sheet: per-collection breakdown, removals in red),
//       §6.6 (Apply — destructive for a snapshot — / Don't Apply, the safe button is the default for Return and Esc),
//       ARCH §7.5 (a …Sheet is a content view; `.aaSheet(.decision)`).
import SwiftUI
import AACore

struct FlashReviewSheet: View {
    let change: FlashIncomingChange
    let finish: (Bool) -> Void

    private var rows: [FlashReviewRow] { FlashReviewBreakdown.rows(for: change) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: AASpacing.m) {
                Image(systemName: change.isSnapshot ? "exclamationmark.triangle.fill" : "square.and.arrow.down.on.square.fill")
                    .font(.system(size: 30, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(change.isSnapshot ? AAColor.Status.danger : AAColor.tint)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: AASpacing.s) {
                    Text(FlashSyncTexts.applyTitle)
                        .font(.system(size: 15, weight: .semibold))
                    Text(FlashSyncTexts.applyQuestion(change))
                        .font(.system(size: AAType.body))
                        .foregroundStyle(AAColor.fg)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .padding(AASpacing.l)

            ScrollView {
              VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    HStack(spacing: AASpacing.s) {
                        Image(systemName: row.symbol)
                            .foregroundStyle(color(row.tone))
                            .frame(width: 20)
                        Text(row.title)
                            .font(.aaMono(AAType.small, weight: .semibold))
                            .foregroundStyle(row.tone == .removed ? AAColor.Status.diffRemoved : AAColor.fg)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: AASpacing.s)
                        Text(row.detail)
                            .font(.system(size: AAType.small))
                            .foregroundStyle(row.tone == .removed ? AAColor.Status.diffRemoved : AAColor.muted)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, AASpacing.m)
                    if row.id != rows.last?.id { Divider().padding(.leading, AASpacing.m + 28) }
                }
              }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(CGFloat(rows.count) * 29.5 + 2, 310))
            .background(AAColor.panel, in: RoundedRectangle(cornerRadius: AARadius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AARadius.tile, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
            .padding(.horizontal, AASpacing.l)

            HStack(spacing: AASpacing.s) {
                Spacer()
                if change.isSnapshot {
                    Button(FlashSyncTexts.applyButton, role: .destructive) { finish(true) }
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
            .padding(AASpacing.l)
        }
        .frame(width: 520)
        .aaSheet(.decision)
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
