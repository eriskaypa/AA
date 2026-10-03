// Spec: 14 TOOLS-067 (date-calculator amount: .NET `int.TryParse(NumberStyles.Integer, Invariant)`),
//       TOOLS-084 / §3.5.2 (unit converter: .NET `double.TryParse(NumberStyles.Any, Invariant)`), vectors 7.4, 7.5.2.
//       A dedicated parser — Swift's `Double(String)` / `Int32(String)` accept different grammars.
import Foundation

/// .NET invariant-culture number parsing emulations used by the tools.
public enum ToolNetNumber {
    /// The white space .NET's number parser skips: U+0009–U+000D and U+0020.
    static func isNumberWhite(_ c: UInt16) -> Bool { c == 0x20 || (c >= 0x09 && c <= 0x0D) }

    static func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }

    /// `true` when everything from `p` to the end is NUL (.NET `TrailingZeros`).
    static func onlyTrailingNULs(_ u: [UInt16], from p: Int) -> Bool {
        var i = p
        while i < u.count { if u[i] != 0 { return false }; i += 1 }
        return true
    }

    // MARK: Int32 (NumberStyles.Integer)

    /// `int.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out v)`: optional leading/trailing white
    /// space, one optional leading `+`/`-`, ASCII digits only; overflow fails.
    public static func parseInt32(_ s: String) -> Int32? {
        let u = Array(s.utf16)
        var p = 0
        while p < u.count, isNumberWhite(u[p]) { p += 1 }
        var negative = false
        if p < u.count, u[p] == 0x2B { p += 1 } else if p < u.count, u[p] == 0x2D { negative = true; p += 1 }
        let digitsStart = p
        var value: Int64 = 0
        while p < u.count, isDigit(u[p]) {
            value = value * 10 + Int64(u[p] - 0x30)
            if value > 2_147_483_648 { return nil }               // overflow, whatever follows
            p += 1
        }
        guard p > digitsStart else { return nil }
        while p < u.count, isNumberWhite(u[p]) { p += 1 }
        guard onlyTrailingNULs(u, from: p) else { return nil }
        let signed = negative ? -value : value
        guard signed >= Int64(Int32.min), signed <= Int64(Int32.max) else { return nil }
        return Int32(signed)
    }

    // MARK: Double (NumberStyles.Any)

    private struct State: OptionSet {
        let rawValue: Int
        static let sign = State(rawValue: 0x01), parens = State(rawValue: 0x02), digits = State(rawValue: 0x04)
        static let nonZero = State(rawValue: 0x08), decimal = State(rawValue: 0x10), currency = State(rawValue: 0x20)
    }

    private static let currencySymbol: UInt16 = 0x00A4      // invariant "¤"

    /// `double.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, out v)` (.NET Core 3.0+ semantics):
    /// white space, leading or trailing sign or parentheses, `¤`, `,` group separators (only after a digit and
    /// before the decimal point), `.`, exponent, and the `Infinity` / `-Infinity` / `NaN` symbols. Values beyond
    /// the double range become ±∞.
    public static func parseDouble(_ s: String) -> Double? {
        if let v = parseNumber(Array(s.utf16)) { return v }
        return parseSymbols(s)
    }

    private static func parseNumber(_ u: [UInt16]) -> Double? {
        var p = 0
        func ch(_ i: Int) -> UInt16 { i < u.count ? u[i] : 0 }
        var state: State = []
        var negative = false
        var currencyAvailable = true

        // Leading part: white space, sign, '(' and the currency symbol.
        while true {
            let c = ch(p)
            let eatWhite = isNumberWhite(c) && !(state.contains(.sign) && !state.contains(.currency))
            if !eatWhite {
                if !state.contains(.sign) && (c == 0x2B || c == 0x2D) {
                    state.insert(.sign)
                    if c == 0x2D { negative = true }
                } else if c == 0x28 && !state.contains(.sign) {          // '('
                    state.formUnion([.sign, .parens])
                    negative = true
                } else if currencyAvailable && c == currencySymbol {
                    state.insert(.currency)
                    currencyAvailable = false
                } else {
                    break
                }
            }
            p += 1
        }

        // Digits, one decimal point, group separators.
        var digits: [UInt16] = []
        var scale = 0
        while true {
            let c = ch(p)
            if isDigit(c) {
                state.insert(.digits)
                if c != 0x30 || state.contains(.nonZero) {
                    digits.append(c)
                    if !state.contains(.decimal) { scale += 1 }
                    state.insert(.nonZero)
                } else if state.contains(.decimal) {
                    scale -= 1
                }
            } else if c == 0x2E && !state.contains(.decimal) {           // '.'
                state.insert(.decimal)
            } else if c == 0x2C && state.contains(.digits) && !state.contains(.decimal) {   // ','
                // group separator: ignored
            } else {
                break
            }
            p += 1
        }

        guard state.contains(.digits) else { return nil }

        // Exponent.
        if ch(p) == 0x65 || ch(p) == 0x45 {
            let save = p
            p += 1
            var negExp = false
            if ch(p) == 0x2B { p += 1 } else if ch(p) == 0x2D { p += 1; negExp = true }
            if isDigit(ch(p)) {
                var exp = 0
                repeat {
                    exp = exp * 10 + Int(ch(p) - 0x30)
                    p += 1
                    if exp > 1000 {
                        exp = 9999
                        while isDigit(ch(p)) { p += 1 }
                    }
                } while isDigit(ch(p))
                scale += negExp ? -exp : exp
            } else {
                p = save
            }
        }

        // Trailing part: white space, sign, ')' and the currency symbol.
        while true {
            let c = ch(p)
            if !isNumberWhite(c) {
                if !state.contains(.sign) && (c == 0x2B || c == 0x2D) {
                    state.insert(.sign)
                    if c == 0x2D { negative = true }
                } else if c == 0x29 && state.contains(.parens) {         // ')'
                    state.remove(.parens)
                } else if currencyAvailable && c == currencySymbol {
                    currencyAvailable = false
                } else {
                    break
                }
            }
            if p >= u.count { break }
            p += 1
        }
        guard !state.contains(.parens), onlyTrailingNULs(u, from: p) else { return nil }

        // Value = 0.<digits> × 10^scale, correctly rounded (strtod); overflow → ±∞, underflow → ±0.
        var magnitude = 0.0
        if !digits.isEmpty {
            let text = "0." + String(decoding: digits, as: UTF16.self) + "e" + String(scale)
            magnitude = Double(text) ?? .infinity
        }
        return negative ? -magnitude : magnitude
    }

    /// The fallback after a failed numeric parse: the trimmed text against the invariant symbols.
    private static func parseSymbols(_ s: String) -> Double? {
        let t = NetText.trim(s)
        if NetText.equalsIgnoreCase(t, "Infinity") { return .infinity }
        if NetText.equalsIgnoreCase(t, "-Infinity") { return -.infinity }
        if NetText.equalsIgnoreCase(t, "NaN") { return .nan }
        if t.hasPrefix("+") {
            let rest = String(t.dropFirst())
            if NetText.equalsIgnoreCase(rest, "Infinity") { return .infinity }
            if NetText.equalsIgnoreCase(rest, "NaN") { return .nan }
            return nil
        }
        if t.hasPrefix("-"), NetText.equalsIgnoreCase(String(t.dropFirst()), "NaN") { return .nan }
        return nil
    }
}
