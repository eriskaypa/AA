// Spec: 14 TOOLS-086 / §3.5.4 (unit converter `Format(double)`: .NET `"G6"` and `"0.######"` with the invariant
//       culture, .NET Core 3.0+ digit generation), vectors 7.5.1–7.5.3. No `String(format:)` shortcut: the custom
//       format first takes 15 correctly rounded significant digits, then rounds half away from zero at the 6th
//       decimal, which C's `%.6f` does not do.
import Foundation

public enum ToolNetDoubleFormat {
    /// The unit converter's `Format`: NaN/±∞ → `""`; 0 → `"0"`; |v| < 1e-4 or ≥ 1e12 → `G6`; else `0.######`.
    public static func unitConverterText(_ v: Double) -> String {
        if v.isNaN || v.isInfinite { return "" }
        if v == 0 { return "0" }
        let a = abs(v)
        if a < 1e-4 || a >= 1e12 { return g6(v) }
        return fixed6(v)
    }

    /// Correctly rounded significant digits of a positive finite double from the C library (exact binary value,
    /// IEEE ties-to-even), as ASCII digit values and the decimal exponent of the first digit.
    static func significantDigits(_ x: Double, count: Int) -> (digits: [UInt8], exponent: Int) {
        var buf = [CChar](repeating: 0, count: 128)
        let format = "%.\(count - 1)e"
        _ = withVaList([x]) { vsnprintf(&buf, buf.count, format, $0) }
        let text = Array(String(cString: buf).utf8)
        var digits: [UInt8] = []
        var i = 0
        while i < text.count, text[i] != 0x65, text[i] != 0x45 {          // up to 'e' / 'E'
            if text[i] >= 0x30, text[i] <= 0x39 { digits.append(text[i] - 0x30) }
            i += 1
        }
        var exponent = 0
        if i < text.count {
            i += 1
            var negative = false
            if i < text.count, text[i] == 0x2D { negative = true; i += 1 } else if i < text.count, text[i] == 0x2B { i += 1 }
            while i < text.count, text[i] >= 0x30, text[i] <= 0x39 { exponent = exponent * 10 + Int(text[i] - 0x30); i += 1 }
            if negative { exponent = -exponent }
        }
        return (digits, exponent)
    }

    /// .NET `v.ToString("0.######", CultureInfo.InvariantCulture)` for finite non-zero `v`.
    public static func fixed6(_ v: Double) -> String {
        guard v.isFinite else { return "" }
        if v == 0 { return "0" }
        var (digits, exponent) = significantDigits(abs(v), count: 15)
        var pointPos = exponent + 1                                  // digits before the decimal point
        let cut = pointPos + 6                                       // index of the first dropped digit
        if cut < 0 {
            digits = []
        } else if cut < digits.count {
            let roundUp = digits[cut] >= 5
            digits = Array(digits[0..<cut])
            if roundUp {
                var k = digits.count - 1
                while k >= 0 {
                    if digits[k] == 9 { digits[k] = 0; k -= 1 } else { digits[k] += 1; break }
                }
                if k < 0 { digits.insert(1, at: 0); pointPos += 1 }
            }
        }
        while let last = digits.last, last == 0, digits.count > max(pointPos, 0) { digits.removeLast() }
        var intPart = ""
        var fracPart = ""
        if pointPos <= 0 {
            if !digits.isEmpty { fracPart = String(repeating: "0", count: -pointPos) + digits.map(String.init).joined() }
        } else {
            for i in 0..<pointPos { intPart += i < digits.count ? String(digits[i]) : "0" }
            if digits.count > pointPos { fracPart = digits[pointPos...].map(String.init).joined() }
        }
        if intPart.isEmpty { intPart = "0" }
        if intPart == "0" && fracPart.isEmpty && digits.allSatisfy({ $0 == 0 }) {
            return v < 0 ? "-0" : "0"
        }
        return (v < 0 ? "-" : "") + intPart + (fracPart.isEmpty ? "" : "." + fracPart)
    }

    /// .NET `v.ToString("G6", CultureInfo.InvariantCulture)` for finite `v`.
    public static func g6(_ v: Double) -> String {
        guard v.isFinite else { return v.isNaN ? "NaN" : (v < 0 ? "-Infinity" : "Infinity") }
        if v == 0 { return v.sign == .minus ? "-0" : "0" }
        var (digits, exponent) = significantDigits(abs(v), count: 6)
        while digits.count > 1, digits.last == 0 { digits.removeLast() }
        let sign = v < 0 ? "-" : ""
        if exponent > -5 && exponent < 6 {
            let pointPos = exponent + 1
            var intPart = "", fracPart = ""
            if pointPos <= 0 {
                intPart = "0"
                fracPart = String(repeating: "0", count: -pointPos) + digits.map(String.init).joined()
            } else {
                for i in 0..<pointPos { intPart += i < digits.count ? String(digits[i]) : "0" }
                if digits.count > pointPos { fracPart = digits[pointPos...].map(String.init).joined() }
            }
            return sign + intPart + (fracPart.isEmpty ? "" : "." + fracPart)
        }
        let mantissa = String(digits[0]) + (digits.count > 1 ? "." + digits[1...].map(String.init).joined() : "")
        let e = abs(exponent)
        return sign + mantissa + "E" + (exponent < 0 ? "-" : "+") + (e < 10 ? "0" : "") + String(e)
    }
}
