// Spec: 14 TOOLS-040 (multi-line, Return and Tab insert characters, no wrap, both scrollbars, Consolas), TOOLS-042
//       (every change re-parses), §6.7 (NSTextView, monospaced token font, horizontal scroller, Tab inserts \t, every
//       automatic substitution off, `\n` line endings, initial keyboard focus).
import AppKit
import SwiftUI

/// The Folder builder's bulk editor: a plain-text `NSTextView` that never wraps and never "corrects" folder names.
struct ToolBulkTextView: NSViewRepresentable {
    @Binding var text: String
    var focusOnAppear = true

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.isAutomaticTextCompletionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.font = AAFont.mono(AAType.body)
        tv.textColor = .textColor
        tv.backgroundColor = .textBackgroundColor
        tv.drawsBackground = true
        tv.textContainerInset = NSSize(width: 6, height: 6)
        // No wrapping: the container is as wide as the longest line.
        tv.isHorizontallyResizable = true
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.autoresizingMask = [.width, .height]
        tv.string = text
        tv.delegate = context.coordinator
        tv.setAccessibilityLabel("Folder list")
        if focusOnAppear {
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView, tv.string != text else { return }
        context.coordinator.isUpdating = true
        tv.string = text
        context.coordinator.isUpdating = false
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isUpdating = false

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let tv = notification.object as? NSTextView else { return }
            text.wrappedValue = tv.string
        }

        /// Tab inserts a tab character (never moves focus); Return inserts a newline (no default button).
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertTab(_:)) {
                textView.insertText("\t", replacementRange: textView.selectedRange())
                return true
            }
            return false
        }
    }
}
