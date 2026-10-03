// Spec: 11 PDF-071…073, §3.5.11 (NormalizeLinkUri, ToUri, AddRunAutoLinked), §3.5.12 (ScanLinks + the exact
//       regex), DEV-11 (formal targets: trimmed NavigateUri, www. → https://), §7.1, §7.2.
import Foundation

public enum PdfLinkScanner {
    /// One segment of a scanned run: `uri == nil` = plain text.
    public struct Segment: Sendable, Hashable, CustomStringConvertible {
        public var text: String
        public var uri: String?
        public init(_ text: String, _ uri: String?) { self.text = text; self.uri = uri }
        public var description: String { "(\(text.debugDescription), \(uri?.debugDescription ?? "nil"))" }
    }

    /// The .NET pattern verbatim (options IgnoreCase); ICU supports the bounded lookbehind, the atomic group and
    /// the named groups (11 §3.5.12 Swift note).
    public static let pattern =
        #"(?<=^|[\s(\[<"'])(?:(?<url>(?:https?://|www\.)[^\s<>()]+)|(?<mail>(?>[A-Za-z0-9._%+\-]+)@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}))"#

    // The pattern is a compile-time constant (verified by the §7.1 tests).
    private static let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])

    /// Trailing sentence punctuation excluded from a link: `. , ; : ! ? ) ] } ' "`.
    private static let trailing: Set<UInt16> = Set(".,;:!?)]}'\"".utf16)

    /// `ScanLinks(text)` (11 §3.5.12): alternating plain / link segments; trimmed punctuation flows into the next
    /// plain segment. Empty input → `[]`.
    public static func scan(_ text: String) -> [Segment] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        let units = Array(text.utf16)
        var out: [Segment] = []
        var last = 0
        func slice(_ a: Int, _ b: Int) -> String { String(decoding: units[a..<b], as: UTF16.self) }
        for m in regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
            var len = m.range.length
            while len > 0, trailing.contains(units[m.range.location + len - 1]) { len -= 1 }
            if len == 0 { continue }
            let start = m.range.location
            let linkText = slice(start, start + len)
            if start > last { out.append(Segment(slice(last, start), nil)) }
            let isMail = m.range(withName: "mail").location != NSNotFound
            out.append(Segment(linkText, toUri(linkText, isMail: isMail)))
            last = start + len
        }
        if last < units.count { out.append(Segment(slice(last, units.count), nil)) }
        return out
    }

    /// `ToUri` (11 §3.5.11).
    public static func toUri(_ linkText: String, isMail: Bool) -> String {
        if isMail { return "mailto:" + linkText }
        return hasWwwPrefix(linkText) ? "https://" + linkText : linkText
    }

    /// `NormalizeLinkUri` (PDF-071, DEV-11): blank → nil; trimmed; a `www.` target gets `https://`.
    public static func normalizeLinkUri(_ s: String?) -> String? {
        guard let s, !NetText.isBlank(s) else { return nil }
        let t = NetText.trim(s)
        return hasWwwPrefix(t) ? "https://" + t : t
    }

    private static func hasWwwPrefix(_ s: String) -> Bool {
        let u = Array(s.utf16.prefix(4))
        guard u.count == 4 else { return false }
        return (u[0] | 0x20) == 0x77 && (u[1] | 0x20) == 0x77 && (u[2] | 0x20) == 0x77 && u[3] == 0x2E
    }

    /// The `URL` written into the PDF annotation (DEV-11): the string as is when Foundation accepts it, else
    /// percent-encoded (spaces and other illegal characters) and retried; nil when still invalid.
    public static func annotationURL(_ s: String) -> URL? {
        if let u = URL(string: s), u.scheme != nil { return u }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(charactersIn: "#%/:?@[]!$&'()*+,;=")
        if let enc = s.addingPercentEncoding(withAllowedCharacters: allowed), let u = URL(string: enc), u.scheme != nil {
            return u
        }
        return nil
    }
}
