// Spec: 05 CONT-031 (Insert hyperlink: `Uri.TryCreate(value, Absolute)`, display text = normalised
//       `uri.ToString()`, e.g. `https://example.com` → `https://example.com/`; bare `https://` does nothing), K-14 (the
//       Mac inserts at the caret and validates in the sheet), XD.2.8 / XD.5 (`.link`, link colour baked into
//       `.foregroundColor` with `.aaLinkStyled`), 03 SHELL-678 (⌘-click opens), 06 Add. row 32.
import AppKit

/// .NET `Uri.TryCreate(s, UriKind.Absolute)` + `Uri.ToString()` for the shapes a user types into the link sheet.
public enum EditorLinkRules {
    public static let sheetTitle = "Insert hyperlink"
    public static let sheetLabel = "URL:"
    public static let sheetInitial = "https://"

    /// Schemes .NET treats as hierarchical with an authority (`scheme://host…`); a missing host fails.
    static let authoritySchemes: Set<String> = ["http", "https", "ftp", "ftps", "ws", "wss", "file", "gopher", "nntp",
                                                "net.tcp", "net.pipe", "telnet", "ldap", "sftp", "smb", "afp"]
    static let defaultPorts: [String: String] = ["http": "80", "https": "443", "ftp": "21", "ws": "80", "wss": "443",
                                                 "gopher": "70", "nntp": "119", "telnet": "23", "ldap": "389"]

    /// The normalised absolute URI text, or nil when .NET would reject it (relative, blank, `https://`, …).
    public static func normalise(_ raw: String) -> String? {
        let t = NetText.trim(raw)
        guard !t.isEmpty else { return nil }
        let u = Array(t.utf16)
        // Windows drive path "C:\…" / "C:/…" → file URI (Uri accepts implicit file paths).
        if u.count >= 3, isLetter(u[0]), u[1] == 0x3A, u[2] == 0x5C || u[2] == 0x2F {
            let rest = String(t.dropFirst(3)).replacingOccurrences(of: "\\", with: "/")
            return "file:///\(String(t.prefix(1)).uppercased()):/\(rest)"
        }
        // UNC "\\server\share\…" → file://server/share/…
        if t.hasPrefix("\\\\") {
            let rest = String(t.dropFirst(2)).replacingOccurrences(of: "\\", with: "/")
            guard let host = rest.split(separator: "/", omittingEmptySubsequences: false).first, !host.isEmpty else { return nil }
            let path = rest.dropFirst(host.count)
            return "file://\(host.lowercased())\(path.isEmpty ? "/" : String(path))"
        }
        guard let colon = t.firstIndex(of: ":") else { return nil }
        let scheme = String(t[t.startIndex..<colon])
        guard isValidScheme(scheme) else { return nil }
        let lowerScheme = scheme.lowercased()
        let afterColon = String(t[t.index(after: colon)...])
        if authoritySchemes.contains(lowerScheme) {
            guard afterColon.hasPrefix("//") else {
                // "http:example.com" is not absolute for .NET's hierarchical schemes.
                return nil
            }
            let afterSlashes = String(afterColon.dropFirst(2))
            let endOfAuthority = afterSlashes.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" || $0 == "\\" })
                ?? afterSlashes.endIndex
            var authority = String(afterSlashes[afterSlashes.startIndex..<endOfAuthority])
            var tail = String(afterSlashes[endOfAuthority...]).replacingOccurrences(of: "\\", with: "/")
            if lowerScheme == "file", authority.isEmpty {
                return "file://" + (tail.isEmpty ? "/" : tail)
            }
            // user-info stays as typed; host and port normalised.
            var userInfo = ""
            if let at = authority.lastIndex(of: "@") {
                userInfo = String(authority[...at])
                authority = String(authority[authority.index(after: at)...])
            }
            var host = authority
            var port = ""
            if !host.hasPrefix("["), let pc = host.lastIndex(of: ":") {
                port = String(host[host.index(after: pc)...])
                host = String(host[..<pc])
                guard port.allSatisfy(\.isASCII), port.allSatisfy(\.isNumber) else { return nil }
                if let p = Int(port), p > 65535 { return nil }
            }
            guard !host.isEmpty, !host.contains(" ") else { return nil }
            host = host.lowercased()
            if let d = defaultPorts[lowerScheme], d == port || (port.isEmpty == false && Int(port) == Int(d)) { port = "" }
            if tail.isEmpty || tail.hasPrefix("?") || tail.hasPrefix("#") { tail = "/" + tail }
            return "\(lowerScheme)://\(userInfo)\(host)\(port.isEmpty ? "" : ":" + port)\(tail)"
        }
        // Non-hierarchical (mailto:, tel:, news:, urn:, custom): needs something after the colon.
        guard !afterColon.isEmpty else { return nil }
        if lowerScheme == "mailto" {
            guard afterColon.contains("@") || afterColon.hasPrefix("?") else { return nil }
        }
        return "\(lowerScheme):\(afterColon)"
    }

    static func isLetter(_ c: UInt16) -> Bool { (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) }

    /// RFC 3986 scheme: ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ), at least 2 chars (1 char = a drive letter).
    static func isValidScheme(_ s: String) -> Bool {
        let u = Array(s.utf16)
        guard u.count >= 2, isLetter(u[0]) else { return false }
        return u.dropFirst().allSatisfy { isLetter($0) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2B || $0 == 0x2D || $0 == 0x2E }
    }

    /// The `.link` value for a normalised string (a URL when Foundation can represent it, else the string).
    public static func linkValue(_ normalised: String) -> Any {
        URL(string: normalised) ?? normalised
    }

    /// The URL to open for a `.link` value (⌘-click, context menu).
    public static func url(from link: Any?) -> URL? {
        if let u = link as? URL { return u }
        if let s = link as? String {
            if let u = URL(string: s) { return u }
            return s.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init(string:))
        }
        return nil
    }

    /// K-14: the edit that inserts a link. Empty selection → the normalised URL as new linked text at the caret;
    /// a selection → the selected text becomes the link (selection kept).
    @MainActor public static func insertion(url normalised: String, in s: NSAttributedString, selection: NSRange,
                                            typing: [NSAttributedString.Key: Any],
                                            linkColor: NSColor) -> EditorTextEdit {
        if selection.length == 0 {
            var attrs = EditorLocking.unlockedTypingAttributes(typing)
            attrs = linkAttributes(attrs, url: normalised, linkColor: linkColor)
            let str = NSAttributedString(string: normalised, attributes: attrs)
            return EditorTextEdit(range: selection, replacement: str,
                                  selectionAfter: NSRange(location: selection.location + str.length, length: 0))
        }
        let sub = NSMutableAttributedString(attributedString: s.attributedSubstring(from: selection))
        var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
        sub.enumerateAttributes(in: NSRange(location: 0, length: sub.length), options: []) { a, r, _ in runs.append((r, a)) }
        for (r, a) in runs where a[.aaListMarker] == nil {
            sub.setAttributes(linkAttributes(a, url: normalised, linkColor: linkColor), range: r)
        }
        return EditorTextEdit(range: selection, replacement: sub, selectionAfter: selection)
    }

    /// A run's attributes as a fresh hyperlink (the default link look is display-only: colour baked in with
    /// `.aaLinkStyled`, the original ink kept in `.aaUnderlyingForeground`).
    @MainActor public static func linkAttributes(_ a: [NSAttributedString.Key: Any], url: String,
                                      linkColor: NSColor) -> [NSAttributedString.Key: Any] {
        var a = a
        a[.link] = linkValue(url)
        a[.aaHyperlink] = nil                    // a new Hyperlink element (no carried attributes)
        if (a[.aaLinkStyled] as? Bool) != true {
            a[.aaUnderlyingForeground] = (a[.foregroundColor] as? NSColor) ?? EditorFormatting.editorInk
            a[.foregroundColor] = linkColor
            a[.aaLinkStyled] = true
        }
        return a
    }

    /// Removes the link from `range`, restoring the ink the link colour replaced.
    @MainActor public static func removingLink(_ a: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var a = a
        a[.link] = nil
        a[.aaHyperlink] = nil
        if (a[.aaLinkStyled] as? Bool) == true {
            a[.foregroundColor] = (a[.aaUnderlyingForeground] as? NSColor) ?? EditorFormatting.editorInk
            a[.aaLinkStyled] = nil
            a[.aaUnderlyingForeground] = nil
        }
        return a
    }

    /// The full range of the link at `index` (same `.link` value, contiguous).
    public static func linkRange(_ s: NSAttributedString, at index: Int) -> NSRange? {
        guard index >= 0, index < s.length else { return nil }
        var r = NSRange(location: 0, length: 0)
        guard s.attribute(.link, at: index, longestEffectiveRange: &r, in: NSRange(location: 0, length: s.length)) != nil
        else { return nil }
        return r
    }

    /// The editor's display link colour (`XamlContext.containerEditor.linkDisplayColor`).
    public static var editorLinkColor: NSColor {
        let v = XamlContext.containerEditor.linkDisplayColor
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: CGFloat((v >> 24) & 0xFF) / 255)
    }
}
