// Contract: ARCHITECTURE.md §6.7.
// Spec: 05 §3.1 "Lock geometry (normative for the Mac)" (deletion/replacement blocked iff any L(i), a ≤ i < b; pure
//       insertion blocked iff L(a−1) && L(a); out-of-range indices unlocked; element tags — paragraph terminators and
//       list markers here — are never locked), §4.4 (the sentinel #FFFFE699 is data), CONT-059…065 (lock / unlock
//       granularity: the whole locked stretch; `DocumentContainsLock` scan; the old substring test false-positived on
//       gold colours), CONT-159 (lock sources), §XD.3 `aa.lockSource` row (unlocking an inlineAncestor stretch clears
//       the key; unlocking a block stretch removes the sentinel from that block), §6.8, D-4.
import AppKit

public enum LockRules {
    public static let sentinel = ARGB(a: 0xFF, r: 0xFF, g: 0xE6, b: 0x99)

    /// L(i) of §3.1 (false outside the string, for terminators and for list-marker characters).
    public static func isLocked(_ s: NSAttributedString, at i: Int) -> Bool {
        guard i >= 0, i < s.length else { return false }
        let c = (s.string as NSString).character(at: i)
        if c == 0x0A || c == 0x0D || c == 0x2029 { return false }
        let a = s.attributes(at: i, effectiveRange: nil)
        if a[.aaListMarker] != nil { return false }
        if a[.aaLocked] as? Bool == true { return true }
        if let src = a[.aaLockSource] as? String, XamlLockSource(rawValue: src) != nil { return true }
        if let bg = a[.backgroundColor] as? NSColor, RichColor.argb(bg) == XamlValues.sentinelARGB { return true }
        return false
    }

    /// §3.1: may the edit replacing `range` with `replacementLength` characters go ahead?
    public static func blocksEdit(_ s: NSAttributedString, range: NSRange, replacementLength: Int) -> Bool {
        let a = max(0, range.location), b = min(s.length, NSMaxRange(range))
        if b > a {
            for i in a..<b where isLocked(s, at: i) { return true }
            return false
        }
        if replacementLength == 0 { return false }                     // a no-op edit
        return isLocked(s, at: a - 1) && isLocked(s, at: a)
    }

    /// The maximal locked stretches that intersect `range` or (for an empty range) contain the caret position or
    /// touch it from either side — the unit CONT-061 unlocks.
    public static func lockedRanges(_ s: NSAttributedString, touching range: NSRange) -> [NSRange] {
        guard s.length > 0 else { return [] }
        var lo = max(0, range.location), hi = min(s.length, NSMaxRange(range))
        if hi <= lo {
            if isLocked(s, at: lo) { hi = lo + 1 } else if isLocked(s, at: lo - 1) { lo -= 1; hi = lo + 1 } else { return [] }
        }
        var out: [NSRange] = []
        var i = lo
        while i < hi {
            guard isLocked(s, at: i) else { i += 1; continue }
            var a = i
            while isLocked(s, at: a - 1) { a -= 1 }
            var b = i + 1
            while isLocked(s, at: b) { b += 1 }
            out.append(NSRange(location: a, length: b - a))
            i = b
        }
        return out
    }

    /// Raw-string fast path (CONT-065): no `FFE699` anywhere → no lock; otherwise an exact scan of the parsed
    /// document (the sentinel on the root wrapper, on a TableColumn or inside opaque content never counts).
    public static func quickHasAnyLock(_ xaml: String) -> Bool {
        guard xaml.range(of: "FFE699", options: .caseInsensitive) != nil else { return false }
        guard case .success(let doc) = XamlDOM.parse(xaml) else { return false }
        for (i, n) in doc.nodes.enumerated() where Int32(i) != doc.root.index {
            switch n.kind {
            case .tableColumn, .unknown, .text: continue
            default:
                if XamlValues.isSentinel(n.local.background) { return true }
            }
        }
        return false
    }

    /// `DocumentContainsLock` over attributed text.
    public static func hasAnyLock(_ s: NSAttributedString) -> Bool {
        var found = false
        s.enumerateAttributes(in: NSRange(location: 0, length: s.length)) { a, _, stop in
            if a[.aaLocked] as? Bool == true || a[.aaLockSource] != nil {
                found = true; stop.pointee = true; return
            }
            if let bg = a[.backgroundColor] as? NSColor, RichColor.argb(bg) == XamlValues.sentinelARGB {
                found = true; stop.pointee = true
            }
        }
        return found
    }

    /// CONT-060 data effect: the sentinel highlight on every non-marker, non-terminator character of `range`.
    public static func lock(_ s: NSMutableAttributedString, range: NSRange) {
        let r = NSIntersectionRange(range, NSRange(location: 0, length: s.length))
        guard r.length > 0 else { return }
        let ns = s.string as NSString
        s.beginEditing()
        for i in r.location..<NSMaxRange(r) {
            let c = ns.character(at: i)
            if c == 0x0A || c == 0x0D || c == 0x2029 { continue }
            if s.attribute(.aaListMarker, at: i, effectiveRange: nil) != nil { continue }
            let one = NSRange(location: i, length: 1)
            s.addAttribute(.backgroundColor, value: RichColor.color(XamlValues.sentinelARGB), range: one)
            s.addAttribute(.aaLockSource, value: XamlLockSource.inlineRun.rawValue, range: one)
            s.addAttribute(.aaLocked, value: true, range: one)
            s.removeAttribute(.aaBackgroundBrushXml, range: one)
        }
        s.endEditing()
    }

    /// CONT-061 data effect: clears the lock from every whole locked stretch touching `range` (other backgrounds are
    /// untouched; a block-level sentinel is removed from its paragraph or container). Returns the stretches unlocked.
    @discardableResult
    public static func unlock(_ s: NSMutableAttributedString, range: NSRange) -> [NSRange] {
        let stretches = lockedRanges(s, touching: range)
        guard !stretches.isEmpty else { return [] }
        s.beginEditing()
        var blockParagraphs: [NSRange] = []
        let ns = s.string as NSString
        for r in stretches {
            for i in r.location..<NSMaxRange(r) {
                let a = s.attributes(at: i, effectiveRange: nil)
                let one = NSRange(location: i, length: 1)
                if let bg = a[.backgroundColor] as? NSColor, RichColor.argb(bg) == XamlValues.sentinelARGB {
                    s.removeAttribute(.backgroundColor, range: one)
                    s.removeAttribute(.aaBackgroundBrushXml, range: one)
                    s.removeAttribute(.richBackgroundBrushDisplay, range: one)
                }
                if (a[.aaLockSource] as? String) == XamlLockSource.block.rawValue {
                    blockParagraphs.append(ns.paragraphRange(for: one))
                }
                s.removeAttribute(.aaLockSource, range: one)
                s.removeAttribute(.aaLocked, range: one)
            }
        }
        // Block sentinel: drop it from the paragraph model and from the containers on the paragraph's path.
        for pr in blockParagraphs {
            clearBlockSentinel(s, paragraph: pr)
        }
        s.endEditing()
        return stretches
    }

    private static func clearBlockSentinel(_ s: NSMutableAttributedString, paragraph pr: NSRange) {
        guard pr.length > 0 else { return }
        let first = s.attributes(at: pr.location, effectiveRange: nil)
        let sentinelToken = XamlValues.formatColor(XamlValues.sentinelARGB)
        var model = (first[.richParagraphModel] as? [String: String]) ?? [:]
        var carried = RichAttributeCoding.decode(first[.aaParagraphAttrs])
        if model["Background"].flatMap(XamlValues.parseBrush).map({ XamlValues.isSentinel($0) }) == true {
            model["Background"] = nil
            model["Background.xml"] = nil
            model["Background.opacity"] = nil
        }
        carried.removeAll { $0.qualifiedName == "Background" && XamlValues.isSentinel(XamlValues.parseBrush($0.value)) }
        var path = RichAttributeCoding.decodePath(first[.richContainerPath])
        var changedIDs: [String: RichContainerInfo] = [:]
        for k in path.indices {
            var info = path[k]
            let before = info
            info.carried.removeAll { $0.qualifiedName == "Background" && XamlValues.isSentinel(XamlValues.parseBrush($0.value)) }
            if info.model["Background"] == sentinelToken { info.model["Background"] = nil }
            if info != before { changedIDs[info.id] = info }
            path[k] = info
        }
        // Apply to every character of every paragraph that shares the changed containers or this paragraph.
        let ns = s.string as NSString
        var replaced: [ObjectIdentifier: NSTextBlock] = [:]
        func dropSentinelBlocks(_ full: NSRange) {
            guard let ps = s.attribute(.paragraphStyle, at: full.location, effectiveRange: nil) as? NSParagraphStyle,
                  ps.textBlocks.contains(where: { b in
                      !(b is NSTextTableBlock) && b.backgroundColor.map(RichColor.argb) == XamlValues.sentinelARGB
                  }) else { return }
            let m = (ps.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            m.textBlocks = ps.textBlocks.map { b in
                guard !(b is NSTextTableBlock), b.backgroundColor.map(RichColor.argb) == XamlValues.sentinelARGB else { return b }
                if let r = replaced[ObjectIdentifier(b)] { return r }
                let c = (b.copy() as? NSTextBlock) ?? NSTextBlock()
                c.backgroundColor = nil
                replaced[ObjectIdentifier(b)] = c
                return c
            }
            s.addAttribute(.paragraphStyle, value: m.copy(), range: full)
        }
        for r in RichDoc.paragraphRanges(ns) {
            let full = NSRange(location: r.start, length: r.end - r.start)
            guard full.length > 0 else { continue }
            if NSEqualRanges(full, pr) || NSIntersectionRange(full, pr).length > 0 {
                s.addAttribute(.richParagraphModel, value: model, range: full)
                if carried.isEmpty { s.removeAttribute(.aaParagraphAttrs, range: full) } else {
                    s.addAttribute(.aaParagraphAttrs, value: RichAttributeCoding.encode(carried), range: full)
                }
                s.addAttribute(.richContainerPath, value: path.map(\.plist), range: full)
                dropSentinelBlocks(full)
                for i in full.location..<NSMaxRange(full) where
                    (s.attribute(.aaLockSource, at: i, effectiveRange: nil) as? String) == XamlLockSource.block.rawValue {
                    let one = NSRange(location: i, length: 1)
                    s.removeAttribute(.aaLockSource, range: one)
                    s.removeAttribute(.aaLocked, range: one)
                }
                continue
            }
            guard !changedIDs.isEmpty else { continue }
            let other = RichAttributeCoding.decodePath(s.attribute(.richContainerPath, at: r.start, effectiveRange: nil))
            guard other.contains(where: { changedIDs[$0.id] != nil }) else { continue }
            let updated = other.map { changedIDs[$0.id] ?? $0 }
            s.addAttribute(.richContainerPath, value: updated.map(\.plist), range: full)
            dropSentinelBlocks(full)
            for i in full.location..<NSMaxRange(full) where
                (s.attribute(.aaLockSource, at: i, effectiveRange: nil) as? String) == XamlLockSource.block.rawValue {
                let one = NSRange(location: i, length: 1)
                s.removeAttribute(.aaLockSource, range: one)
                s.removeAttribute(.aaLocked, range: one)
            }
        }
    }
}
