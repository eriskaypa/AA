// Spec: 01 §4.1.6 (double write format), 10 Addendum X.4.12 (NetShortest, Int64Saturating, Net0_4), App. A15;
//       ARCHITECTURE.md §3.3 — shared by JSON, XLSX and tools.
import Foundation

public enum NetNumberText {
    /// System.Text.Json / `double.ToString("R")` shortest round-trip text: integral |x| < 1e15 → integer text
    /// ("180", "-24", "-0" for -0.0); otherwise shortest round-trip digits with decimal exponent `e` of the first
    /// digit — fixed iff -5 < e < 15, scientific "1E+16" / "1E-05" otherwise. nil for NaN/Infinity.
    public static func shortest(_ x: Double) -> String? {
        guard x.isFinite else { return nil }
        if x == 0 { return x.sign == .minus ? "-0" : "0" }
        let (digits, exp) = shortestDigits(abs(x))
        let body: String
        if exp > -5 && exp < 15 {
            if exp >= 0 {
                if digits.count <= exp + 1 {
                    body = digits + String(repeating: "0", count: exp + 1 - digits.count)
                } else {
                    let cut = digits.index(digits.startIndex, offsetBy: exp + 1)
                    body = String(digits[..<cut]) + "." + String(digits[cut...])
                }
            } else {
                body = "0." + String(repeating: "0", count: -exp - 1) + digits
            }
        } else {
            let first = String(digits.prefix(1))
            let rest = String(digits.dropFirst())
            let e = abs(exp)
            body = first + (rest.isEmpty ? "" : "." + rest) + "E" + (exp < 0 ? "-" : "+") + (e < 10 ? "0" : "") + String(e)
        }
        return (x < 0 ? "-" : "") + body
    }

    /// Shortest round-trip significant digits (no leading/trailing zeros) of a positive finite double and the
    /// decimal exponent of the first digit, taken from Swift's shortest-round-trip `description`.
    static func shortestDigits(_ x: Double) -> (digits: String, exponent: Int) {
        let d = x.description                                  // e.g. "180.5", "1e-05", "1.5e-07", "5e-324"
        var mantissa = Substring(d)
        var exp10 = 0
        if let e = d.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            mantissa = d[..<e]
            exp10 = Int(d[d.index(after: e)...]) ?? 0
        }
        var intPart = mantissa, fracPart: Substring = ""
        if let dot = mantissa.firstIndex(of: ".") {
            intPart = mantissa[..<dot]
            fracPart = mantissa[mantissa.index(after: dot)...]
        }
        var all = String(intPart) + String(fracPart)
        var pointPos = intPart.count + exp10                    // digits before the decimal point
        while all.hasPrefix("0") && all.count > 1 { all.removeFirst(); pointPos -= 1 }
        while all.hasSuffix("0") && all.count > 1 { all.removeLast() }
        return (all, pointPos - 1)
    }

    /// 10 X.4.12 `Int64Saturating`: saturates at Int64.min/max; NaN → 0 (.NET 9 saturating conversion).
    public static func int64Saturating(_ x: Double) -> Int64 {
        if x.isNaN { return 0 }
        if x >= 9.223372036854775807e18 { return Int64.max }
        if x < -9.223372036854775808e18 { return Int64.min }
        return Int64(x)
    }

    /// .NET custom format `"0.####"` (10 X.4.12 `Net0_4`): 15 significant digits correctly rounded, then
    /// half-up rounding at the 4th decimal, trailing zeros trimmed, `-0` → `0`.
    public static func net0_4(_ x: Double) -> String {
        guard x.isFinite else { return x.isNaN ? "NaN" : (x < 0 ? "-∞" : "∞") }
        if x == 0 { return "0" }
        let sci = String(format: "%.14e", locale: Locale(identifier: "en_US_POSIX"), abs(x))  // d.dddddddddddddde±XX
        guard let eIdx = sci.firstIndex(where: { $0 == "e" || $0 == "E" }) else { return "0" }
        var digits = Array(sci[..<eIdx].replacingOccurrences(of: ".", with: ""))
        var exp = Int(sci[sci.index(after: eIdx)...]) ?? 0
        let keep = exp + 1 + 4
        if keep < 0 { return "0" }
        if keep < 15 {
            if digits[keep] >= "5" {
                if keep == 0 {
                    digits = ["1"]; exp += 1
                } else {
                    var d = Array(digits[0..<keep])
                    var k = keep - 1
                    while k >= 0 {
                        if d[k] == "9" { d[k] = "0"; k -= 1 } else { d[k] = Character(String(d[k].wholeNumberValue! + 1)); break }
                    }
                    if k < 0 { d = ["1"]; exp += 1 }
                    digits = d
                }
            } else {
                digits = Array(digits[0..<keep])
            }
        }
        while let last = digits.last, last == "0" { digits.removeLast() }
        if digits.isEmpty { return "0" }
        let intPart: String, fracPart: String
        if exp >= 0 {
            let head = digits.prefix(exp + 1)
            intPart = String(head) + String(repeating: "0", count: max(0, exp + 1 - head.count))
            fracPart = digits.count > exp + 1 ? String(digits[(exp + 1)...]) : ""
        } else {
            intPart = "0"
            fracPart = String(repeating: "0", count: -exp - 1) + String(digits)
        }
        let result = intPart + (fracPart.isEmpty ? "" : "." + fracPart)
        return (x < 0 && result != "0") ? "-" + result : result
    }
}
