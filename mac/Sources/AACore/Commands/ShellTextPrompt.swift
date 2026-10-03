// Spec: 06 Addendum BUILD-136…150, BUILD-A22 (TextPromptRequest / TextPromptResult / TextPrompting), A28 (line-break
//       cut), §Add.6 (raw field: no substitutions; async presenter; ScriptedPrompter records every request), §Add.7
//       (TV-PR-01…11); ARCHITECTURE.md §7.5. The SwiftUI sheet (`TextPromptSheet`) and the presenter live in the AA
//       target; the request/result types, the fire-once session and the field-editor rules live here so they are
//       unit-testable.
import AppKit
import Observation

/// One prompt: heading, label (verbatim), pre-filled text (fully selected), secure display, optional muted help line.
/// There is deliberately no validate / canSubmit / trim parameter (BUILD-146).
public struct TextPromptRequest: Equatable, Sendable {
    public var title: String
    public var prompt: String
    public var initial: String
    public var isSecure: Bool
    public var helpText: String?

    public init(title: String, prompt: String, initial: String = "", isSecure: Bool = false, helpText: String? = nil) {
        self.title = title
        self.prompt = prompt
        self.initial = initial
        self.isSecure = isSecure
        self.helpText = helpText
    }
}

/// `.ok` carries the RAW text (BUILD-A22).
public enum TextPromptResult: Equatable, Sendable { case ok(String), cancelled }

/// The injectable prompter (BUILD-A22), so the 35 caller handlers can be unit-tested with `ScriptedPrompter`.
@MainActor public protocol TextPrompting: AnyObject {
    func prompt(_ request: TextPromptRequest) async -> TextPromptResult
}

/// Returns pre-set results in order (`.cancelled` once they run out) and records every request (§Add.6, TV-PR-40).
@MainActor public final class ScriptedPrompter: TextPrompting {
    public private(set) var requests: [TextPromptRequest] = []
    private var results: [TextPromptResult]

    public init(results: [TextPromptResult]) { self.results = results }

    public func prompt(_ request: TextPromptRequest) async -> TextPromptResult {
        requests.append(request)
        return results.isEmpty ? .cancelled : results.removeFirst()
    }
}

/// BUILD-A28 single-line filtering.
public enum ShellPromptText {
    /// `\n`, `\r`, `\v`, `\f`, U+0085, U+2028, U+2029 — the WPF `TextEditor._FilterText` set.
    public static let lineBreaks: Set<Character> = ["\n", "\r", "\r\n", "\u{0B}", "\u{0C}", "\u{85}", "\u{2028}", "\u{2029}"]

    /// Text cut at the first line break.
    public static func singleLine(_ s: String) -> String {
        if let i = s.firstIndex(where: { lineBreaks.contains($0) }) { return String(s[..<i]) }
        return s
    }
}

/// Sheet geometry the spec fixes (TV-PR-11: the label wraps; width ≥ 440).
public enum TextPromptLayout {
    public static let minWidth: CGFloat = 440
}

/// The prompt's state: raw single-line text, OK always enabled (BUILD-137), and a completion that fires exactly once
/// (BUILD-139) whichever of OK / Return / Cancel / Esc / ⌘. / parent-window close comes first.
@MainActor @Observable
public final class TextPromptSession {
    public let request: TextPromptRequest
    public private(set) var text: String
    public private(set) var result: TextPromptResult?
    @ObservationIgnored private let onFinish: (TextPromptResult) -> Void

    public init(request: TextPromptRequest, onFinish: @escaping (TextPromptResult) -> Void) {
        self.request = request
        self.text = ShellPromptText.singleLine(request.initial)
        self.onFinish = onFinish
    }

    /// OK is never disabled — blank, whitespace-only and NBSP values are returned as typed.
    public var canSubmit: Bool { true }

    /// Applies an edit (typing or paste); the value is cut at the first line break. Returns the stored text.
    @discardableResult
    public func setText(_ s: String) -> String {
        let cut = ShellPromptText.singleLine(s)
        if cut != text { text = cut }
        return cut
    }

    public func ok() { complete(.ok(text)) }
    public func cancel() { complete(.cancelled) }

    private func complete(_ r: TextPromptResult) {
        guard result == nil else { return }
        result = r
        onFinish(r)
    }
}

/// The field-editor rules of the raw prompt field (§Add.6): no smart quotes/dashes, replacement, autocorrect, link or
/// data detection; Return / Enter submits, Esc / ⌘. cancels.
@MainActor public enum ShellRawFieldEditing {
    public enum Command: Equatable { case submit, cancel, none }

    public static func configure(_ editor: NSText?) {
        guard let tv = editor as? NSTextView else { return }
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.smartInsertDeleteEnabled = false
    }

    public static func command(for selector: Selector) -> Command {
        if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.insertLineBreak(_:))
            || selector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
            return .submit
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) { return .cancel }
        return .none
    }
}

/// The `NSTextFieldDelegate` behind the raw prompt field: cuts pasted multi-line text at the first line break and maps
/// Return / Esc to submit / cancel.
@MainActor public final class ShellRawFieldDelegate: NSObject, NSTextFieldDelegate {
    public var onChange: (String) -> Void
    public var onSubmit: (String) -> Void
    public var onCancel: () -> Void

    public init(onChange: @escaping (String) -> Void, onSubmit: @escaping (String) -> Void,
                onCancel: @escaping () -> Void) {
        self.onChange = onChange
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    public func controlTextDidBeginEditing(_ obj: Notification) {
        ShellRawFieldEditing.configure(obj.userInfo?["NSFieldEditor"] as? NSText)
    }

    public func controlTextDidChange(_ obj: Notification) {
        guard let f = obj.object as? NSTextField else { return }
        let cut = ShellPromptText.singleLine(f.stringValue)
        if cut != f.stringValue { f.stringValue = cut }
        onChange(cut)
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch ShellRawFieldEditing.command(for: sel) {
        case .submit:
            onSubmit(ShellPromptText.singleLine(control.stringValue))
            return true
        case .cancel:
            onCancel()
            return true
        case .none:
            return false
        }
    }
}
