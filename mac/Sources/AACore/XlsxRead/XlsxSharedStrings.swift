// Spec: 10 VESSEL-312…314, §X.4.6 (rich runs → joined + newline fix-up, no `_xHHHH_`; plain `<t>` → `_xHHHH_`
//       decoded, no fix-up; `<rPh>` / `<phoneticPr>` never part of the text), X.8.6.
import Foundation

enum SvcXlsxText {
    /// The shared-string table, in `<si>` order.
    static func sharedStrings(_ data: Data) throws(XlsxReadError) -> [String] {
        let scanner = try SvcXmlScanner(data)
        var out: [String] = []
        var path: [String] = []
        var plain: String?
        var runs: [String] = []
        var hasRuns = false
        var capture: Int = 0                 // 0 none, 1 plain <si><t>, 2 run <si><r><t>
        var buffer = ""
        while let ev = try scanner.next() {
            switch ev {
            case .start(let name, _):
                if name == "si" { plain = nil; runs = []; hasRuns = false }
                if name == "r", path.last == "si" { hasRuns = true; runs.append("") }
                if name == "t" {
                    if path.last == "si" { capture = 1; buffer = "" }
                    else if path.last == "r", path.count >= 2, path[path.count - 2] == "si" { capture = 2; buffer = "" }
                }
                path.append(name)
            case .text(let s):
                if capture != 0 { buffer += s }
            case .end(let name):
                path.removeLast()
                if name == "t", capture != 0 {
                    if capture == 1 { plain = (plain ?? "") + buffer } else if !runs.isEmpty { runs[runs.count - 1] += buffer }
                    capture = 0
                }
                if name == "si" {
                    out.append(hasRuns ? fixNewLines(runs.joined()) : decodeEscapes(plain ?? ""))
                }
            }
        }
        return out
    }

    /// `StringExtensions.FixNewLines` on Windows: when the text contains `\n`, every `\n` not preceded by `\r`
    /// becomes `\r\n` (the Windows `Environment.NewLine`); a lone `\r` is untouched.
    static func fixNewLines(_ s: String) -> String {
        let u = Array(s.utf16)
        guard u.contains(0x0A) else { return s }
        var out: [UInt16] = []
        out.reserveCapacity(u.count + 8)
        for (k, c) in u.enumerated() {
            if c == 0x0A && (k == 0 || u[k - 1] != 0x0D) { out.append(0x0D) }
            out.append(c)
        }
        return String(decoding: out, as: UTF16.self)
    }

    /// `XmlConvert.DecodeName` after ClosedXML's pre-pass: `_xHHHH_` (lower-case x, 4 hex digits) → that UTF-16 unit,
    /// `_xHHHHHHHH_` → that code point, consecutive escapes forming a surrogate pair combine, a lone surrogate or an
    /// invalid code point → U+FFFD; upper-case `_XHHHH_` is never decoded; `_x005F_` → `_`.
    static func decodeEscapes(_ s: String) -> String {
        guard s.contains("_x") else { return s }
        let u = Array(s.utf16)
        var out: [UInt16] = []
        out.reserveCapacity(u.count)
        func hex(_ from: Int, _ n: Int) -> UInt32? {
            guard from + n < u.count, u[from + n] == 0x5F else { return nil }
            var v: UInt32 = 0
            for k in from..<(from + n) {
                let c = u[k]
                let d: UInt32
                switch c {
                case 0x30...0x39: d = UInt32(c - 0x30)
                case 0x41...0x46: d = UInt32(c - 0x41 + 10)
                case 0x61...0x66: d = UInt32(c - 0x61 + 10)
                default: return nil
                }
                v = v << 4 | d
            }
            return v
        }
        var i = 0
        while i < u.count {
            if u[i] == 0x5F, i + 1 < u.count, u[i + 1] == 0x78 {
                if let v = hex(i + 2, 8) {
                    if let sc = Unicode.Scalar(v) { out.append(contentsOf: Array(String(Character(sc)).utf16)) }
                    else { out.append(0xFFFD) }
                    i += 11
                    continue
                }
                if let v = hex(i + 2, 4) {
                    out.append(UInt16(v))
                    i += 7
                    continue
                }
            }
            out.append(u[i])
            i += 1
        }
        // Lone surrogates cannot live in a Swift String: replace them explicitly (pairs decode normally).
        var cleaned: [UInt16] = []
        cleaned.reserveCapacity(out.count)
        var k = 0
        while k < out.count {
            let c = out[k]
            if UTF16.isLeadSurrogate(c), k + 1 < out.count, UTF16.isTrailSurrogate(out[k + 1]) {
                cleaned.append(c); cleaned.append(out[k + 1]); k += 2; continue
            }
            cleaned.append(UTF16.isLeadSurrogate(c) || UTF16.isTrailSurrogate(c) ? 0xFFFD : c)
            k += 1
        }
        return String(decoding: cleaned, as: UTF16.self)
    }
}
