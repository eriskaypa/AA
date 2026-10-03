// Spec: ARCHITECTURE.md §7.5 (shared alerts: button 0 is the default unless another is marked; a cancel button answers
//       ⎋), 09 CREW-033 (the date-order Yes/No/Cancel box defaults to Cancel: Return and Esc both cancel the import),
//       03 SHELL-161 / DECISIONS 03 Q-5 (destructive confirmations may default to Cancel).
import Foundation

/// Pure key-equivalent layout of an AA alert (the presenter is F3's `DialogPresenter.alert`).
public enum ShellAlertKeys {
    public static let returnKey = "\r"
    public static let escapeKey = "\u{1b}"

    public struct Layout: Sendable, Equatable {
        /// Per button, in order: `"\r"`, `"\u{1b}"` or `""`.
        public var keys: [String]
        /// The button Return answers.
        public var defaultIndex: Int
        /// The button ⎋ answers (the first cancel button), nil when none.
        public var escapeIndex: Int?
        /// True when one button answers both Return and ⎋ (a button carries one key equivalent, so the presenter
        /// routes ⎋ to it itself).
        public var escapeNeedsRouting: Bool { escapeIndex != nil && escapeIndex == defaultIndex }
    }

    /// `explicitDefault` (an `AlertSpec.defaultIndex`) wins; else the first button with the default role; else 0.
    public static func layout(count: Int, cancel: [Bool], defaultRole: [Bool], explicitDefault: Int? = nil) -> Layout {
        guard count > 0 else { return Layout(keys: [], defaultIndex: 0, escapeIndex: nil) }
        let def: Int
        if let e = explicitDefault, (0..<count).contains(e) {
            def = e
        } else {
            def = (0..<count).first { $0 < defaultRole.count && defaultRole[$0] } ?? 0
        }
        let esc = (0..<count).first { $0 < cancel.count && cancel[$0] }
        var keys = Array(repeating: "", count: count)
        for i in 0..<count {
            if i == def { keys[i] = returnKey } else if i == esc { keys[i] = escapeKey }
        }
        return Layout(keys: keys, defaultIndex: def, escapeIndex: esc)
    }
}
