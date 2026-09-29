// Spec: 01 §4.1.2–4.1.9 (STJ writer: compact, escaping via the default JavaScriptEncoder, number lexemes,
//       depth 64), OC-01, OC-41 (.aasched indented CRLF); ARCHITECTURE.md §3.2.
import Foundation

public struct JSONWriteOptions: Sendable, Equatable {
    public var indented: Bool = false              // compact by default (data.json, settings.json, source.json…)
    public var indent: String = "  "               // 2 spaces (System.Text.Json WriteIndented)
    public var newline: String = "\n"              // .aasched.json uses "\r\n" (OC-41)
    public var maxDepth: Int = 64

    public init(indented: Bool = false, indent: String = "  ", newline: String = "\n", maxDepth: Int = 64) {
        self.indented = indented; self.indent = indent; self.newline = newline; self.maxDepth = maxDepth
    }

    public static let compact = JSONWriteOptions()
    /// Indented, `"\r\n"`, `"Key": value` (06 §4.5, OC-41).
    public static let aaschedIndented = JSONWriteOptions(indented: true, indent: "  ", newline: "\r\n")
}

public enum JSONWriteError: Error, Sendable, CustomStringConvertible {
    case tooDeep(limit: Int)
    public var description: String {
        switch self { case .tooDeep: return "The structure is too deep to save." }
    }
}

public enum JSONWriter {
    public static func data(_ value: JSONValue, options: JSONWriteOptions = .compact) throws(JSONWriteError) -> Data {
        var w = Impl(options: options)
        try w.write(value, depth: 0)
        return Data(w.out)
    }

    public static func string(_ value: JSONValue, options: JSONWriteOptions = .compact) throws(JSONWriteError) -> String {
        var w = Impl(options: options)
        try w.write(value, depth: 0)
        return String(decoding: w.out, as: UTF8.self)
    }

    /// The complete JSON string token for `s` (surrounding quotes included), escaped exactly like the .NET
    /// default `JavaScriptEncoder` (01 §4.1.7): pure-ASCII output.
    public static func escape(_ s: String) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(s.utf8.count + 2)
        appendEscaped(s, to: &out)
        return String(decoding: out, as: UTF8.self)
    }

    private static let hexDigits: [UInt8] = Array("0123456789ABCDEF".utf8)

    /// Literal ASCII: letters, digits, space and `! # $ % ( ) * , - . / : ; = ? @ [ ] ^ _ { | } ~`.
    private static let literalTable: [Bool] = {
        var t = [Bool](repeating: false, count: 128)
        for c in 0x30...0x39 { t[c] = true }
        for c in 0x41...0x5A { t[c] = true }
        for c in 0x61...0x7A { t[c] = true }
        for c in " !#$%()*,-./:;=?@[]^_{|}~".utf8 { t[Int(c)] = true }
        return t
    }()

    static func appendEscaped(_ s: String, to out: inout [UInt8]) {
        out.append(0x22)
        for unit in s.utf16 {
            if unit < 0x80 {
                let c = UInt8(unit)
                if literalTable[Int(c)] { out.append(c); continue }
                switch c {
                case 0x5C: out.append(0x5C); out.append(0x5C)
                case 0x08: out.append(0x5C); out.append(0x62)
                case 0x09: out.append(0x5C); out.append(0x74)
                case 0x0A: out.append(0x5C); out.append(0x6E)
                case 0x0C: out.append(0x5C); out.append(0x66)
                case 0x0D: out.append(0x5C); out.append(0x72)
                default: appendUEscape(unit, to: &out)          // " & ' + < > ` controls U+007F
                }
            } else {
                appendUEscape(unit, to: &out)                     // non-ASCII (surrogate pairs come as two units)
            }
        }
        out.append(0x22)
    }

    private static func appendUEscape(_ unit: UInt16, to out: inout [UInt8]) {
        out.append(0x5C); out.append(0x75)
        out.append(hexDigits[Int(unit >> 12) & 0xF])
        out.append(hexDigits[Int(unit >> 8) & 0xF])
        out.append(hexDigits[Int(unit >> 4) & 0xF])
        out.append(hexDigits[Int(unit) & 0xF])
    }

    struct Impl {
        let options: JSONWriteOptions
        var out: [UInt8] = []
        let indentBytes: [UInt8]
        let newlineBytes: [UInt8]

        init(options: JSONWriteOptions) {
            self.options = options
            indentBytes = Array(options.indent.utf8)
            newlineBytes = Array(options.newline.utf8)
            out.reserveCapacity(4096)
        }

        mutating func newline(level: Int) {
            out.append(contentsOf: newlineBytes)
            for _ in 0..<level { out.append(contentsOf: indentBytes) }
        }

        mutating func write(_ v: JSONValue, depth: Int) throws(JSONWriteError) {
            switch v {
            case .null: out.append(contentsOf: [0x6E, 0x75, 0x6C, 0x6C])
            case .bool(let b): out.append(contentsOf: b ? Array("true".utf8) : Array("false".utf8))
            case .number(let n): out.append(contentsOf: n.lexeme.utf8)
            case .string(let s): JSONWriter.appendEscaped(s, to: &out)
            case .rawString(let s): out.append(0x22); out.append(contentsOf: s.utf8); out.append(0x22)
            case .array(let items):
                guard depth + 1 <= options.maxDepth else { throw .tooDeep(limit: options.maxDepth) }
                out.append(0x5B)
                if !items.isEmpty {
                    for (k, item) in items.enumerated() {
                        if k > 0 { out.append(0x2C) }
                        if options.indented { newline(level: depth + 1) }
                        try write(item, depth: depth + 1)
                    }
                    if options.indented { newline(level: depth) }
                }
                out.append(0x5D)
            case .object(let obj):
                guard depth + 1 <= options.maxDepth else { throw .tooDeep(limit: options.maxDepth) }
                out.append(0x7B)
                if !obj.isEmpty {
                    var first = true
                    for (key, item) in obj {
                        if !first { out.append(0x2C) }
                        first = false
                        if options.indented { newline(level: depth + 1) }
                        JSONWriter.appendEscaped(key, to: &out)
                        out.append(0x3A)
                        if options.indented { out.append(0x20) }
                        try write(item, depth: depth + 1)
                    }
                    if options.indented { newline(level: depth) }
                }
                out.append(0x7D)
            }
        }
    }
}
