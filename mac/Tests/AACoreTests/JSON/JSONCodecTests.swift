// TV: 01 §7.4 (escaping, numbers, unknown keys), 01 App. A09a/A10/A15/A19 (parser edge cases), 01 §4.1.9 (depth),
//     13 CS-19 / §3.11.9–3.11.10 (ordinal strings, DeepEquals, JsonNode accessors).
import Foundation
import Testing
@testable import AACore

@Suite struct JSONEscapingTests {
    // TV: 01 §7.4 escaping golden (verbatim)
    @Test func escapingGolden() {
        #expect(JSONWriter.escape("Pump \u{2192} main <A&B> 'x' \"y\" +1")
                == #""Pump \u2192 main \u003CA\u0026B\u003E \u0027x\u0027 \u0022y\u0022 \u002B1""#)
    }

    @Test func escapingTable() {
        #expect(JSONWriter.escape("\u{2693}") == #""\u2693""#)
        #expect(JSONWriter.escape("😀") == #""\uD83D\uDE00""#)
        #expect(JSONWriter.escape("a\tb\nc") == #""a\tb\nc""#)
        #expect(JSONWriter.escape("C:\\x") == #""C:\\x""#)
        #expect(JSONWriter.escape("\u{0001}") == #""\u0001""#)
        #expect(JSONWriter.escape("\u{007F}") == #""\u007F""#)
        #expect(JSONWriter.escape("`") == #""\u0060""#)
        #expect(JSONWriter.escape("\u{0008}\u{000C}\r") == #""\b\f\r""#)
        #expect(JSONWriter.escape("\u{000B}\u{001F}") == #""\u000B\u001F""#)
        #expect(JSONWriter.escape("é") == #""\u00E9""#)
        #expect(JSONWriter.escape("e\u{301}") == #""e\u0301""#)      // NFD kept, no normalisation (A09a)
        #expect(JSONWriter.escape("\u{2028}\u{FEFF}") == #""\u2028\uFEFF""#)
    }

    // TV: 01 App. A09a — the 95 printable ASCII characters
    @Test func printableAsciiSet() {
        let all = String((0x20...0x7E).map { Character(Unicode.Scalar(UInt8($0))) })
        let expected = #"" !\u0022#$%\u0026\u0027()*\u002B,-./0123456789:;\u003C=\u003E?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_\u0060abcdefghijklmnopqrstuvwxyz{|}~""#
        #expect(JSONWriter.escape(all) == expected)
    }

    @Test func keysAreEscapedToo() throws {
        let v = JSONValue.object(JSONObject([("Task|Café", .bool(true))]))
        #expect(try JSONWriter.string(v) == #"{"Task|Caf\u00E9":true}"#)
    }

    @Test func rawStringIsWrittenVerbatim() throws {
        let o = JSONObject([("A", .rawString("2026-09-29T11:15:29.9876543+03:00")),
                            ("B", .string("2026-09-29T11:15:29.9876543+03:00"))])
        #expect(try JSONWriter.string(.object(o))
                == #"{"A":"2026-09-29T11:15:29.9876543+03:00","B":"2026-09-29T11:15:29.9876543\u002B03:00"}"#)
        #expect(JSONValue.rawString("x") == JSONValue.string("x"))
        #expect(JSONValue.rawString("x").hashValue == JSONValue.string("x").hashValue)
    }
}

@Suite struct JSONNumberTests {
    // TV: 01 §4.1.6, §7.4 numbers, App. A15, ARCHITECTURE.md §3.3 vectors
    @Test(arguments: [
        (24.0, "24"), (180.5, "180.5"), (0.1, "0.1"), (1e16, "1E+16"), (1e15, "1E+15"), (1e-4, "0.0001"),
        (1e-5, "1E-05"), (1.5e-7, "1.5E-07"), (5e-324, "5E-324"), (-0.0, "-0"), (24.5, "24.5"), (-24, "-24"),
        (1.7976931348623157e308, "1.7976931348623157E+308"), (0.30000000000000004, "0.30000000000000004"),
        (123456789.123, "123456789.123"), (123456789012345, "123456789012345"), (12.5, "12.5"), (0.25, "0.25"),
        (-1280.5, "-1280.5"), (900.25, "900.25"), (333.25, "333.25"), (1.2e20, "1.2E+20"), (0.00012, "0.00012"),
    ] as [(Double, String)])
    func shortest(_ value: Double, _ text: String) {
        #expect(NetNumberText.shortest(value) == text)
    }

    @Test func nonFinite() {
        #expect(NetNumberText.shortest(.nan) == nil)
        #expect(NetNumberText.shortest(.infinity) == nil)
        #expect(JSONNumber(Double.nan) == nil)
        #expect(JSONNumber(60).lexeme == "60")
    }

    @Test func lexemeSemantics() {
        #expect(JSONNumber(lexeme: "1") != JSONNumber(lexeme: "1.0"))
        #expect(JSONNumber(lexeme: "-0") != JSONNumber(lexeme: "0"))
        #expect(JSONNumber(lexeme: "60.0").intValue == nil)                // A07.7
        #expect(JSONNumber(lexeme: "6E1").intValue == nil)                 // A07.8
        #expect(JSONNumber(lexeme: "2147483648").intValue == nil)          // A07.12
        #expect(JSONNumber(lexeme: "2147483647").intValue == 2_147_483_647)
        #expect(JSONNumber(lexeme: "-2147483648").intValue == -2_147_483_648)
        #expect(JSONNumber(lexeme: "2147483648").int64Value == 2_147_483_648)
        #expect(JSONNumber(lexeme: "1.50").doubleValue == 1.5)
    }

    @Test func net0_4() {
        #expect(NetNumberText.net0_4(1.23456) == "1.2346")
        #expect(NetNumberText.net0_4(0.00005) == "0.0001")
        #expect(NetNumberText.net0_4(0.00004) == "0")
        #expect(NetNumberText.net0_4(-0.00001) == "0")
        #expect(NetNumberText.net0_4(12) == "12")
        #expect(NetNumberText.net0_4(-2.5) == "-2.5")
        #expect(NetNumberText.net0_4(0.1 + 0.2) == "0.3")
        #expect(NetNumberText.net0_4(9.99995) == "10")
        #expect(NetNumberText.net0_4(1234567.891) == "1234567.891")
        #expect(NetNumberText.net0_4(0) == "0")
    }

    @Test func int64Saturating() {
        #expect(NetNumberText.int64Saturating(1e19) == Int64.max)
        #expect(NetNumberText.int64Saturating(-1e19) == Int64.min)
        #expect(NetNumberText.int64Saturating(-2.9) == -2)
        #expect(NetNumberText.int64Saturating(.nan) == 0)
    }
}

@Suite struct JSONParserTests {
    @Test func roundTripKeepsLexemesAndOrder() throws {
        // TV: 01 App. A10 raw number text kept
        let text = #"{"b":1.50,"a":-0,"e":1e2,"n":null,"s":"\u00e9\/","arr":[true,false,{}],"o":{}}"#
        let v = try JSONParser.parse(text)
        #expect(try JSONWriter.string(v) == #"{"b":1.50,"a":-0,"e":1e2,"n":null,"s":"\u00E9/","arr":[true,false,{}],"o":{}}"#)
    }

    @Test func duplicateKeysFirstPositionLastValue() throws {
        let v = try JSONParser.parse(#"{"X":1,"Y":0,"X":2}"#)
        #expect(try JSONWriter.string(v) == #"{"X":2,"Y":0}"#)
    }

    // TV: 01 App. A19.1–A19.9 (parser side; the decoders own null / non-object roots)
    @Test func framing() throws {
        let body = #"{"Tasks":[]}"#
        #expect(try JSONParser.parse(Data([0xEF, 0xBB, 0xBF]) + Data(body.utf8)).objectValue?.count == 1)
        #expect(try JSONParser.parse(body + "\n  \r\n\t").objectValue != nil)
        #expect(throws: JSONParseError.self) { try JSONParser.parse("// c\n" + body) }
        #expect(throws: JSONParseError.self) { try JSONParser.parse(#"{"Tasks":[],}"#) }
        #expect(throws: JSONParseError.self) { try JSONParser.parse(#"{"Tasks":[1,]}"#) }
        #expect(try JSONParser.parse("null") == .null)
        #expect(try JSONParser.parse("[]") == .array([]))
        #expect(throws: JSONParseError.self) { try JSONParser.parse("") }
        #expect(throws: JSONParseError.self) { try JSONParser.parse("   ") }
        #expect(throws: JSONParseError.self) { try JSONParser.parse(body + body) }
        #expect(throws: JSONParseError.self) { try JSONParser.parse("NaN") }
        #expect(throws: JSONParseError.self) { try JSONParser.parse("{'a':1}") }
        #expect(throws: JSONParseError.self) { try JSONParser.parse("[01]") }
        #expect(throws: JSONParseError.self) { try JSONParser.parse("[1.]") }
        #expect(throws: JSONParseError.self) { try JSONParser.parse("\"a\u{0001}b\"") }
        #expect(throws: JSONParseError.self) { try JSONParser.parse("[tru]") }
    }

    @Test func utf16LEBomIsNotJSON() {
        // A19.2 — a UTF-16 LE file is not valid UTF-8 JSON.
        let data = Data([0xFF, 0xFE]) + "{}".data(using: .utf16LittleEndian)!
        #expect(throws: JSONParseError.self) { try JSONParser.parse(data) }
    }

    @Test func invalidUTF8Policies() throws {
        let bytes = Data([0x22, 0x61, 0xFF, 0x62, 0x22])                   // "a<FF>b"
        #expect(try JSONParser.parse(bytes) == .string("a\u{FFFD}b"))
        #expect(throws: JSONParseError.invalidUTF8(offset: 2)) {
            try JSONParser.parse(bytes, invalidUTF8: .reject)
        }
    }

    @Test func surrogates() throws {
        #expect(try JSONParser.parse(#""\uD83D\uDE00""#) == .string("😀"))
        #expect(try JSONParser.parse(#""\uD800""#) == .string("\u{FFFD}"))           // A09b divergence
        #expect(try JSONParser.parse(#""\uD800x""#) == .string("\u{FFFD}x"))
        #expect(try JSONParser.parse(#""\uDE00""#) == .string("\u{FFFD}"))
        #expect(try JSONParser.parse(#""\uD83D\u0041""#) == .string("\u{FFFD}A"))
    }

    // TV: 01 §4.1.9 depth 64 read and write
    @Test func depthLimit() throws {
        let ok = String(repeating: "[", count: 64) + String(repeating: "]", count: 64)
        let deep = String(repeating: "[", count: 65) + String(repeating: "]", count: 65)
        let v = try JSONParser.parse(ok)
        #expect(throws: JSONParseError.tooDeep(limit: 64)) { try JSONParser.parse(deep) }
        #expect(try JSONWriter.string(v) == ok)
        let tooDeep: JSONValue = .array([v])
        #expect(throws: JSONWriteError.self) { try JSONWriter.string(tooDeep) }
    }

    @Test func indentedOutput() throws {
        let v = try JSONParser.parse(#"{"A":1,"B":[1,{"C":null}],"E":[],"F":{}}"#)
        let s = try JSONWriter.string(v, options: .aaschedIndented)
        #expect(s == "{\r\n  \"A\": 1,\r\n  \"B\": [\r\n    1,\r\n    {\r\n      \"C\": null\r\n    }\r\n  ],\r\n  \"E\": [],\r\n  \"F\": {}\r\n}")
    }
}

@Suite struct JSONTreeSemanticsTests {
    // TV: 13 §3.11.10 accessor semantics
    @Test func objectAccessors() {
        var o = JSONObject([("a", .number(JSONNumber(1))), ("n", .null), ("b", .string("x"))])
        #expect(o["n"] == nil)
        #expect(o.containsKey("n"))
        #expect(o.rawValue(forKey: "n") == .null)
        #expect(o["missing"] == nil && !o.containsKey("missing"))
        o.set("a", .bool(true))
        #expect(o.keys == ["a", "n", "b"])                                   // replaced in place
        o.removeValue(forKey: "a")
        o.set("a", .bool(false))
        #expect(o.keys == ["n", "b", "a"])                                   // re-add appends at the end
        #expect(o["b"] == .string("x"))
        #expect(JSONValue.number(JSONNumber(lexeme: "1.0")).idText == "1.0")
        #expect(JSONValue.bool(true).idText == "true")
        #expect(JSONValue.string("k").idText == "k")
        #expect(JSONValue.null.idText == nil)
    }

    @Test func ordinalKeys() {
        var o = JSONObject()
        o.set("Task|Caf\u{E9}", .bool(true))
        o.set("Task|Cafe\u{301}", .bool(false))
        #expect(o.count == 2)                                                // canonical equivalence NOT merged
        #expect(o["Task|Caf\u{E9}"] == .bool(true))
        #expect(o["task|caf\u{E9}"] == nil)                                  // case-sensitive
    }

    // TV: 13 CS-19 deep-equals vectors
    @Test func deepEqualsVectors() throws {
        func p(_ s: String) throws -> JSONValue { try JSONParser.parse(s) }
        #expect(JSONValue.deepEquals(try p(#"{"a":1,"b":2}"#), try p(#"{"b":2,"a":1}"#)))
        #expect(!JSONValue.deepEquals(try p("[1,2]"), try p("[2,1]")))
        #expect(!JSONValue.deepEquals(try p(#"{"a":null}"#), try p("{}")))
        #expect(JSONValue.deepEquals(try p(#"{"a":null}"#), try p(#"{"a":null}"#)))
        #expect(!JSONValue.deepEquals(.string("\u{E9}"), .string("e\u{301}")))
        #expect(JSONValue.deepEquals(try p(#""\u00e9""#), .string("\u{E9}")))
        #expect(!JSONValue.deepEquals(try p("1"), try p("1.0")))
        #expect(!JSONValue.deepEquals(try p("-0"), try p("0")))
        #expect(!JSONValue.deepEquals(try p(#""1""#), try p("1")))
        #expect(JSONValue.deepEquals(nil, .null))
        #expect(!JSONValue.deepEquals(nil, try p("{}")))
        #expect(!JSONValue.deepEquals(try p("[]"), try p("{}")))
        #expect(JSONValue.deepEquals(.rawString("x"), .string("x")))
    }

    @Test func structuralEqualityIsOrdered() throws {
        #expect(try JSONParser.parse(#"{"a":1,"b":2}"#) != JSONParser.parse(#"{"b":2,"a":1}"#))
    }
}

@Suite struct OrderedMapTests {
    // TV: ARCHITECTURE.md §3.8 — .NET Dictionary slot reuse (remove b, add d → a, d, c)
    @Test func slotReuse() {
        var m = OrderedMap<Bool>()
        m["a"] = true; m["b"] = true; m["c"] = true
        m["b"] = nil
        m["d"] = false
        #expect(m.keys == ["a", "d", "c"])
        m["a"] = false                                                       // existing key keeps its position
        #expect(m.keys == ["a", "d", "c"])
    }

    @Test func lifoFreeList() {
        var m = OrderedMap<String>()
        m["a"] = "1"; m["b"] = "2"; m["c"] = "3"
        m["a"] = nil; m["c"] = nil                                            // freed: slot 0 then slot 2
        m["x"] = "4"                                                          // most recently freed → slot 2
        m["y"] = "5"                                                          // then slot 0
        #expect(m.keys == ["y", "b", "x"])
        var n = OrderedMap<String>()
        n["a"] = "1"; n["b"] = "2"
        n["a"] = nil; n["b"] = nil
        n["x"] = "3"; n["y"] = "4"
        #expect(n.keys == ["y", "x"])                                         // no reset when the count hits 0
    }

    @Test func ordinalIdentity() {
        var m = OrderedMap<Bool>()
        m["Task|Caf\u{E9}"] = true
        m["Task|Cafe\u{301}"] = false
        #expect(m.count == 2)
    }
}
