// Spec: 14 §6.3 (Mac addition: "Waiting for Google sign-in in your browser…" sheet with Cancel; Cancel stops the
//       listener and fails the operation quietly with "Google sign-in cancelled."; 5-minute timeout), Q-7.
import AppKit
import SwiftUI
import AACore

/// State of one interactive sign-in round, shared by the coordinator (which finishes it) and the sheet.
@MainActor @Observable
final class DriveSignInModel {
    private(set) var finished = false
    let startedAt = Date()
    @ObservationIgnored private let cancelAction: @Sendable () -> Void
    /// The consent URL, so the user can reopen the browser if they closed the tab.
    var consentURL: URL?

    init(cancel: @escaping @Sendable () -> Void) { cancelAction = cancel }

    func cancel() {
        cancelAction()
        finished = true
    }

    func finish() { finished = true }
}

/// The waiting sheet (a decision sheet: ⌘W/⌘Q do not close it; Esc = Cancel).
struct DriveSignInSheet: View {
    let model: DriveSignInModel
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.l) {
            HStack(alignment: .top, spacing: AASpacing.m) {
                ZStack {
                    Circle().fill(AAColor.tint.opacity(0.14)).frame(width: 52, height: 52)
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(AAColor.tint)
                        .symbolEffect(.pulse, options: .repeating)
                }
                VStack(alignment: .leading, spacing: AASpacing.xs) {
                    Text(DriveText.waitingTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(DriveText.waitingMessage)
                        .font(.system(size: AAType.small))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: AASpacing.s) {
                ProgressView().controlSize(.small)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(DriveSignInSheet.remainingText(since: model.startedAt, now: ctx.date))
                        .font(.system(size: AAType.caption).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                if let url = model.consentURL {
                    Button("Open Browser Again") { NSWorkspace.shared.open(url) }
                        .help("Reopen Google's sign-in page in your default browser.")
                }
                Spacer()
                Button("Cancel", role: .cancel) { model.cancel() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(AASpacing.xl)
        .frame(width: 440)
        .aaSheet(.decision)
        .onAppear { if model.finished { dismiss() } }
        .onChange(of: model.finished) { _, done in if done { dismiss() } }
    }

    /// "Times out in m:ss" (the 5-minute limit of 14 §6.3).
    static func remainingText(since start: Date, now: Date, limit: TimeInterval = 300) -> String {
        let left = max(0, Int((limit - now.timeIntervalSince(start)).rounded(.up)))
        return String(format: "Times out in %d:%02d", left / 60, left % 60)
    }
}
