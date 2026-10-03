// Spec: 05 CONT-060 (lock = sentinel background #FFFFE699 on the selection), CONT-061 (unlock clears the whole locked
//       stretch the selection touches), CONT-063 (edit geometry; boundaries never count), CONT-064 (1.5 s hint
//       throttle and text), CONT-065 (the sentinel is data on any element), XD.3 (`.aaLockSource`: a sentinel
//       `.backgroundColor` alone already means `inlineRun`; `inlineAncestor` / `block` are stored), §6.8, D-4.
import AppKit

@MainActor public enum EditorLocking {
    /// The sentinel as a display colour (A=255, R=255, G=230, B=153).
    public static let sentinelColor = NSColor(srgbRed: 1, green: 230 / 255.0, blue: 153 / 255.0, alpha: 1)

    /// CONT-064 hint text (status line of the main window).
    public static let hintText = "🔒 Highlighted/touched text is locked. Select it and click 🔓 to unlock."
    /// CONT-060 / CONT-061 empty-selection messages (title, text).
    public static let lockNeedsSelection = (title: "Lock highlighted text",
                                            text: "Highlight the text you want to protect from editing, then click 🔒.")
    public static let unlockNeedsSelection = (title: "Unlock highlighted text",
                                              text: "Highlight the locked text you want to unlock, then click 🔓.")

    /// True when `c` is exactly the sentinel (8-bit sRGB compare, alpha 255).
    public static func isSentinel(_ c: NSColor?) -> Bool {
        guard let c, let s = c.usingColorSpace(.sRGB) else { return false }
        func b(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }
        return b(s.alphaComponent) == 255 && b(s.redComponent) == 255 && b(s.greenComponent) == 230
            && b(s.blueComponent) == 153
    }

    /// A character is locked when its run carries the sentinel background or a stored lock source (CONT-065).
    public static func isLocked(_ a: [NSAttributedString.Key: Any]) -> Bool {
        if (a[.aaLocked] as? Bool) == true { return true }
        if a[.aaLockSource] != nil { return true }
        return isSentinel(a[.backgroundColor] as? NSColor)
    }

    public static func isLocked(_ s: NSAttributedString, at i: Int) -> Bool {
        guard i >= 0, i < s.length else { return false }
        if s.attribute(.aaListMarker, at: i, effectiveRange: nil) != nil { return false }   // markers never count
        return isLocked(s.attributes(at: i, effectiveRange: nil))
    }

    /// Whether the document holds any locked character (the CONT-065 fast-path flag).
    public static func hasAnyLock(_ s: NSAttributedString) -> Bool {
        var found = false
        s.enumerateAttributes(in: NSRange(location: 0, length: s.length), options: []) { a, _, stop in
            if a[.aaListMarker] == nil, isLocked(a) { found = true; stop.pointee = true }
        }
        return found
    }

    /// 05 §3.1 lock geometry over the character model: a replacement of a non-empty range is blocked iff any
    /// character in it is locked; a pure insertion at `a` is blocked iff `L(a-1) && L(a)`.
    public static func blocksEdit(_ s: NSAttributedString, range: NSRange) -> Bool {
        let len = s.length
        let start = max(0, min(range.location, len))
        let end = max(start, min(NSMaxRange(range), len))
        if end > start {
            var blocked = false
            s.enumerateAttributes(in: NSRange(location: start, length: end - start), options: []) { a, _, stop in
                if a[.aaListMarker] == nil, isLocked(a) { blocked = true; stop.pointee = true }
            }
            return blocked
        }
        return isLocked(s, at: start - 1) && isLocked(s, at: start)
    }

    /// The editor's combined gate: the W-RICH contract (`LockRules.blocksEdit`) and the character model above.
    public static func editBlocked(_ s: NSAttributedString, range: NSRange, replacementLength: Int) -> Bool {
        LockRules.blocksEdit(s, range: range, replacementLength: replacementLength) || blocksEdit(s, range: range)
    }

    /// Every maximal locked stretch that intersects or touches `range` (CONT-061 "whole element").
    public static func lockedStretches(_ s: NSAttributedString, touching range: NSRange) -> [NSRange] {
        let len = s.length
        guard len > 0 else { return [] }
        let start = max(0, min(range.location, len))
        let end = max(start, min(NSMaxRange(range), len))
        var out: [NSRange] = []
        var i = max(0, start - (range.length == 0 ? 1 : 0))
        let limit = range.length == 0 ? min(len, start + 1) : end
        while i < limit {
            if isLocked(s, at: i) {
                var a = i, b = i + 1
                while a > 0, isLocked(s, at: a - 1) { a -= 1 }
                while b < len, isLocked(s, at: b) { b += 1 }
                out.append(NSRange(location: a, length: b - a))
                i = b
            } else {
                i += 1
            }
        }
        // Merge with the contract's stretches (W-RICH may know block-level locks beyond the run attributes).
        for r in LockRules.lockedRanges(s, touching: range) where !out.contains(where: { NSIntersectionRange($0, r).length == r.length }) {
            out.append(r)
        }
        return out.sorted { $0.location < $1.location }
    }

    /// CONT-060: the sentinel background on every non-marker run of `range`. Returns false when nothing changed.
    @discardableResult
    public static func lock(_ s: NSMutableAttributedString, range: NSRange) -> Bool {
        guard range.length > 0, NSMaxRange(range) <= s.length else { return false }
        var runs: [NSRange] = []
        s.enumerateAttributes(in: range, options: []) { a, r, _ in
            if a[.aaListMarker] == nil, !isSentinel(a[.backgroundColor] as? NSColor) { runs.append(r) }
        }
        guard !runs.isEmpty else { return false }
        s.beginEditing()
        for r in runs {
            s.addAttribute(.backgroundColor, value: sentinelColor, range: r)
            s.removeAttribute(.aaBackgroundBrushXml, range: r)
        }
        s.endEditing()
        return true
    }

    /// CONT-061: clears the lock from every stretch (sentinel background, stored lock source, and a block's carried
    /// sentinel `Background` in `.aaParagraphAttrs`). Other backgrounds are untouched. Returns false when nothing
    /// changed.
    @discardableResult
    public static func unlock(_ s: NSMutableAttributedString, stretches: [NSRange]) -> Bool {
        var changed = false
        s.beginEditing()
        defer { s.endEditing() }
        let text = s.string as NSString
        for stretch in stretches where stretch.length > 0 && NSMaxRange(stretch) <= s.length {
            var target = stretch
            var hasBlock = false
            s.enumerateAttribute(.aaLockSource, in: stretch, options: []) { v, _, stop in
                if (v as? String) == "block" { hasBlock = true; stop.pointee = true }
            }
            if hasBlock { target = text.paragraphRange(for: stretch) }   // the whole element unlocks
            var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
            s.enumerateAttributes(in: target, options: []) { a, r, _ in runs.append((r, a)) }
            for (r, a) in runs {
                if a[.aaLockSource] != nil { s.removeAttribute(.aaLockSource, range: r); changed = true }
                if a[.aaLocked] != nil { s.removeAttribute(.aaLocked, range: r); changed = true }
                if isSentinel(a[.backgroundColor] as? NSColor) { s.removeAttribute(.backgroundColor, range: r); changed = true }
                if let attrs = a[.aaParagraphAttrs] as? [[String]] {
                    let kept = attrs.filter { !isSentinelBackgroundAttribute($0) }
                    if kept.count != attrs.count {
                        s.addAttribute(.aaParagraphAttrs, value: kept, range: r)
                        changed = true
                    }
                }
            }
        }
        return changed
    }

    /// A carried raw attribute `[name, namespace, value]` that is `Background="#FFFFE699"` (or an equivalent token).
    static func isSentinelBackgroundAttribute(_ raw: [String]) -> Bool {
        guard raw.count >= 3, raw[0] == "Background" else { return false }
        return WpfColor.parse(raw[2]) == LockRules.sentinel
    }

    /// Typing next to locked text must not extend the lock (boundaries are editable, 05 §7.4): the sentinel and the
    /// stored lock source are dropped from the typing attributes.
    public static func unlockedTypingAttributes(_ a: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        guard isLocked(a) else { return a }
        var a = a
        a[.aaLockSource] = nil
        a[.aaLocked] = nil
        if isSentinel(a[.backgroundColor] as? NSColor) { a[.backgroundColor] = nil }
        return a
    }
}

/// CONT-064: at most one hint every 1.5 s.
public struct EditorHintThrottle {
    public static let interval: TimeInterval = 1.5
    private var last: Date?

    public init() {}

    /// True when a hint may be shown at `now` (and records it).
    public mutating func shouldShow(at now: Date) -> Bool {
        if let last, now.timeIntervalSince(last) < Self.interval, now >= last { return false }
        last = now
        return true
    }
}
