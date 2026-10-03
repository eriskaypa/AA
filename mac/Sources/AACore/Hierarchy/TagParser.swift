// Spec: 04 §3.4 (main-pane ParseTags; item-window comma-only parse kept for the vector only), HIER-027, REPO-106,
//       04 §7.1 (vectors); DECISIONS 04 Q-A (one unified parser everywhere: multi-delimiter, `#` strip,
//       case-insensitive de-dup), Q-E (`#tag` sidebar search); ARCHITECTURE.md §6.8.
import Foundation

public enum TagParser {
    /// The delimiters of the main-pane parser: `,` `;` `\n` `\r` `\t` and U+0020 SPACE only.
    static let delimiters: Set<UInt16> = [0x2C, 0x3B, 0x0A, 0x0D, 0x09, 0x20]

    /// 04 §3.4 `ParseTags`: split on the delimiters, trim each part (Unicode white space, `TrimEntries`), drop
    /// empties, strip **all** leading `#`, drop parts that became empty, de-duplicate ordinal-ignore-case keeping the
    /// first spelling, preserve order.
    public static func parse(_ text: String) -> [String] {
        var out: [String] = []
        for part in splitUTF16(text, on: delimiters) {
            var t = NetText.trim(part)
            if t.isEmpty { continue }
            t = stripLeadingHashes(t)
            if t.isEmpty { continue }
            if out.contains(where: { NetText.equalsIgnoreCase($0, t) }) { continue }
            out.append(t)
        }
        return out
    }

    /// The Windows item-window parser (`ItemWindow.xaml.cs:118`): split on `,` only, trim, drop empties — no `#`
    /// strip, no de-duplication. DECISIONS 04 Q-A replaces it with `parse` in the Mac item window; kept so the
    /// 04 §7.1 vector documents the Windows behaviour.
    public static func parseCommaOnly(_ text: String) -> [String] {
        splitUTF16(text, on: [0x2C]).map { NetText.trim($0) }.filter { !$0.isEmpty }
    }

    /// ", " joined (HIER-027 display and the on-blur normalisation).
    public static func display(_ tags: [String]) -> String { tags.joined(separator: ", ") }

    /// "#tag" sidebar search (DECISIONS 04 Q-E). `hashQuery` is the trimmed query that starts with `#`; it may hold
    /// several space-separated tokens (`#pump #engine`). Every token (leading `#`s stripped) must be contained,
    /// ordinal-ignore-case, in at least one tag. A query with no token left (`"#"`) matches every item.
    public static func matches(_ tags: [String], hashQuery: String) -> Bool {
        let tokens = splitUTF16(hashQuery, on: [0x20, 0x09, 0x2C, 0x3B])
            .map { stripLeadingHashes(NetText.trim($0)) }
            .filter { !$0.isEmpty }
        if tokens.isEmpty { return true }
        return tokens.allSatisfy { token in tags.contains { NetText.containsIgnoreCase($0, token) } }
    }

    /// True when a (trimmed) sidebar query is a tag query.
    public static func isHashQuery(_ trimmedQuery: String) -> Bool { trimmedQuery.hasPrefix("#") }

    static func stripLeadingHashes(_ s: String) -> String {
        let u = Array(s.utf16)
        var a = 0
        while a < u.count, u[a] == 0x23 { a += 1 }
        return a == 0 ? s : String(decoding: u[a...], as: UTF16.self)
    }

    /// `string.Split(char[])` over UTF-16 code units (empty parts kept; callers drop them).
    static func splitUTF16(_ s: String, on separators: Set<UInt16>) -> [String] {
        var parts: [String] = []
        var current: [UInt16] = []
        for u in s.utf16 {
            if separators.contains(u) {
                parts.append(String(decoding: current, as: UTF16.self))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(u)
            }
        }
        parts.append(String(decoding: current, as: UTF16.self))
        return parts
    }
}
