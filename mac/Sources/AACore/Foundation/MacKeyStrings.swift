// Spec: 03 §6.5.1.9 (user-visible strings that name keys — the full 20-row table), SHELL registry "Strings" check.
import Foundation

/// Renders a Windows user-visible string that names a key into its Mac form. Everything else in the string stays
/// verbatim; strings that name no key come back unchanged.
public enum MacKeyStrings {
    /// Whole strings that change completely (menu titles, header buttons, gestures).
    static let wholeStrings: [(windows: String, mac: String)] = [
        ("Quick _work window (Ctrl+N)", "Quick Work Window"),
        ("Quick s_witcher (Ctrl+O)", "Quick Switcher…"),
        ("Search (Ctrl+F)", "Search"),
        ("Go to (Ctrl+O)", "Go to"),
        ("Save (Ctrl+S)", "Save"),
        ("Paste text only", "Paste Text Only"),
        ("Ctrl+Shift+V", "⌥⇧⌘V"),
    ]

    /// The shortcut strip (03 §6.2), compared with whitespace runs collapsed.
    static let windowsShortcutStrip = "⌨ Ctrl+S Save · Ctrl+F Search · Ctrl+N Quick work · Ctrl+O Go to (quick switcher) · Ctrl+R Due-dates window · Ctrl+1…9 Switch tab · F2 Rename · Ctrl+Z Undo delete"
    static let macShortcutStrip = "⌨  ⌘S Save · ⌘F Search · ⌘N Quick work · ⌘O Go to (quick switcher) · ⌘R Due-dates window · ⌘1…9 Switch tab · F2 Rename · ⌘Z Undo delete"

    /// Substring replacements, applied in order (longest / most specific first).
    static let replacements: [(windows: String, mac: String)] = [
        ("— Ctrl+Z undoes the last one.", "— ⌘Z undoes the last one."),
        ("When on, Ctrl+S also pushes your data", "When on, ⌘S also pushes your data"),
        ("Obsidian-style. Type, then Enter.", "Obsidian-style. Type, then Return."),
        ("or undo with Ctrl+Z.", "or undo with ⌘Z."),
        ("the quick switcher (Ctrl+O).", "the quick switcher (⌘O)."),
        ("or Ctrl+N for the quick-work window.", "or ⌘N for the quick-work window."),
        ("— Ctrl+Z to undo them all.", "— ⌘Z to undo them all."),
        ("— Ctrl+Z to undo.", "— ⌘Z to undo."),
        ("(in the Ctrl+N quick-work window)", "(in the ⌘N quick-work window)"),
        ("one Ctrl+Z removes", "one ⌘Z removes"),
        ("Bold (Ctrl+B)", "Bold (⌘B)"),
        ("Italic (Ctrl+I)", "Italic (⌘I)"),
        ("Underline (Ctrl+U)", "Underline (⌘U)"),
        ("Undo (Ctrl+Z)", "Undo (⌘Z)"),
        ("Redo (Ctrl+Y)", "Redo (⇧⌘Z)"),
        ("— Ctrl+Alt+Up.", "— ⌃⌘↑."),
        ("— Ctrl+Alt+Down.", "— ⌃⌘↓."),
        ("Outdent (Shift+Tab at the start of a list item)", "Outdent (⇧Tab at the start of a list item)"),
        ("Enter to open  ·", "Return to open  ·"),
        ("Add a task and press Enter…", "Add a task and press Return…"),
        ("(Enter = new line)", "(Return = new line)"),
        ("(View ▸ Shortcut bar to bring it back).", "(View ▸ Shortcut Bar to bring it back)."),
        ("(Ctrl+Z).", "(⌘Z)."),
    ]

    public static func render(_ windowsText: String) -> String {
        for row in wholeStrings where Ordinal.equals(row.windows, windowsText) { return row.mac }
        if collapseWhitespace(windowsText) == windowsShortcutStrip { return macShortcutStrip }
        var s = windowsText
        for row in replacements where s.contains(row.windows) {
            s = s.replacingOccurrences(of: row.windows, with: row.mac)
        }
        return s
    }

    static func collapseWhitespace(_ s: String) -> String {
        s.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }).joined(separator: " ")
    }
}
