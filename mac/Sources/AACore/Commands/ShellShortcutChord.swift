// Spec: 03 §6.5.1.0 (glyph notation, ⌘− / ⌘+), SHELL-500 (US-layout shift normalisation), SHELL-501 (reserved keys),
//       SHELL-511 (layouts), §6.5.1.14 (registry integrity tests).
import Foundation

/// A key equivalent parsed from the registry's glyph notation (`⌥⇧⌘V`, `⌃⌘↑`, `F2`, `⌘+`).
public struct ShellShortcutChord: Sendable, Hashable, CustomStringConvertible {
    /// Canonical modifier names, always in ⌃ ⌥ ⇧ ⌘ order.
    public static let modifierOrder = ["control", "option", "shift", "command"]
    static let glyphs: [Character: String] = ["⌃": "control", "⌥": "option", "⇧": "shift", "⌘": "command"]
    static let glyphOf: [String: String] = ["control": "⌃", "option": "⌥", "shift": "⇧", "command": "⌘"]

    /// Lower-case letter/digit/punctuation, or a named key: `delete` (⌫), `forwardDelete` (⌦), `return` (↩),
    /// `enter` (⌅), `escape` (⎋), `tab` (⇥), `space`, `left`, `right`, `up`, `down`, `F1`…`F20`.
    public let key: String
    public let modifiers: [String]

    public init(key: String, modifiers: [String]) {
        self.key = key
        self.modifiers = ShellShortcutChord.modifierOrder.filter { modifiers.contains($0) }
    }

    /// Parses `⌥⇧⌘V`, `⌘⌫`, `⌃⌘↑`, `⇧⌘7`, `F2`, `⌘−`, `⌘.`; nil for an empty or unknown key.
    public init?(_ glyphText: String) {
        var mods: [String] = []
        var rest = Substring(glyphText)
        while let c = rest.first, let m = ShellShortcutChord.glyphs[c] {
            mods.append(m)
            rest = rest.dropFirst()
        }
        let k = String(rest)
        let named: [String: String] = ["⌫": "delete", "⌦": "forwardDelete", "↩": "return", "⌅": "enter", "⎋": "escape",
                                       "⇥": "tab", "←": "left", "→": "right", "↑": "up", "↓": "down", "Space": "space",
                                       "−": "-"]
        let key: String
        if let n = named[k] {
            key = n
        } else if k.count >= 2, k.hasPrefix("F"), Int(k.dropFirst()) != nil {
            key = k
        } else if k.count == 1 {
            let ch = k.first!
            if ch.isUppercase && ch.isLetter {
                key = k.lowercased()                // ⌥⇧⌘V: the letter is written upper-case; shift is explicit
            } else {
                key = k
            }
        } else {
            return nil
        }
        self.init(key: key, modifiers: mods)
    }

    /// The registry's glyph rendering (`⌥⇧⌘V`, `⌘⌫`, `F2`).
    public var description: String {
        let names: [String: String] = ["delete": "⌫", "forwardDelete": "⌦", "return": "↩", "enter": "⌅", "escape": "⎋",
                                       "tab": "⇥", "left": "←", "right": "→", "up": "↑", "down": "↓", "space": "Space",
                                       "-": "−"]
        let k = names[key] ?? (key.count == 1 ? key.uppercased() : key)
        return modifiers.compactMap { ShellShortcutChord.glyphOf[$0] }.joined() + k
    }

    /// SHELL-500 US-layout shift normalisation: `{`≡⇧`[`, `}`≡⇧`]`, `|`≡⇧`\`, `+`≡⇧`=`, `:`≡⇧`;`, `?`≡⇧`/`,
    /// `<`≡⇧`,`, `>`≡⇧`.`, `_`≡⇧`-`, `&`≡⇧`7`, `(`≡⇧`9`.
    public var normalized: ShellShortcutChord {
        let shifted: [String: String] = ["{": "[", "}": "]", "|": "\\", "+": "=", ":": ";", "?": "/", "<": ",",
                                         ">": ".", "_": "-", "&": "7", "(": "9", "*": "8", ")": "0", "^": "6",
                                         "%": "5", "$": "4", "#": "3", "@": "2", "!": "1", "~": "`", "\"": "'"]
        if let base = shifted[key] { return ShellShortcutChord(key: base, modifiers: modifiers + ["shift"]) }
        return self
    }

    // MARK: SHELL-501 reserved keys

    /// System, accessibility, Services and reserved-unused chords that AA never assigns (normalised).
    public static let reserved: Set<ShellShortcutChord> = {
        var s: [String] = [
            // system
            "⌘Space", "⌥⌘Space", "⌃Space", "⌃⌥Space", "⌘⇥", "⌘`", "⌘Q", "⌘H", "⌥⌘H", "⌘M", "⌥⌘M", "⌘,", "⌃⌘F",
            "⌃⌘Q", "⌃⌘Space", "⇧⌘3", "⇧⌘4", "⇧⌘5", "⇧⌘6", "⇧⌘/", "⌥⌘D", "⌥⌘⎋", "⌃↑", "⌃↓", "⌃←", "⌃→",
            // accessibility
            "⌥⌘8", "⌥⌘=", "⌥⌘-", "⌥⌘\\", "⌃⌥⌘8", "⌘F5",
            // default Services (⇧⌘M deliberately allowed, SHELL-501)
            "⇧⌘L", "⇧⌘Y", "⇧⌘A",
            // reserved but unused
            "⌘D", "⌥⌘C", "⌥⌘V", "⌃⌘C", "⌃⌘V", "⌥⌘I",
        ]
        for n in 1...8 { s.append("⌃F\(n)") }
        return Set(s.compactMap { ShellShortcutChord($0)?.normalized })
    }()

    /// Every ⌃⌥ chord is VoiceOver's (SHELL-501).
    public var isVoiceOverChord: Bool { modifiers.contains("control") && modifiers.contains("option") }

    /// Keys the macOS text system binds (§6.5.1.14 text-safety set).
    public var isTextSystemKey: Bool {
        let m = Set(modifiers)
        if key == "F2" && m.isEmpty { return true }
        if key == "escape" && m.isEmpty { return true }
        if key == "tab" && m == ["control"] { return true }
        if m == ["command"] && ["delete", "left", "right", "up", "down"].contains(key) { return true }
        if m == ["option"] && ["left", "right", "up", "down", "delete"].contains(key) { return true }
        return false
    }
}
