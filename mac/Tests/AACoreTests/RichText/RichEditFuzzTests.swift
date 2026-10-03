// TV: 05 §4.3.7 (every Mac output is well-formed, loadable XAML; round-trip goal), 01 §4.11 invariant 1 (a Mac-written
//     body read and written again is byte-identical, so a later untouched save never drifts), CONT-163…166, §6.4.
// Seeded, deterministic edit fuzzing over every sample: random insertions (plain, formatted, linked, locked, line
// breaks, paragraph breaks), deletions across structure, list commands, fragment pastes and lock/unlock — after each
// step the written XAML must parse, be loadable, be a fixed point of read → write, and keep every visible character.
import AppKit
import Testing
@testable import AACore

@MainActor
@Suite struct RichEditFuzzTests {
    /// SplitMix64 — deterministic across runs and platforms.
    struct Rng {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
    }

    /// 30 steps per sample in the gate (a few seconds in a debug build); `FUZZ_STEPS` / `FUZZ_SEED` run deeper or
    /// different sequences by hand (audits ran 400 steps × seeds 1–5 and 300 steps × seeds 1–3 green).
    static let steps = Int(ProcessInfo.processInfo.environment["FUZZ_STEPS"] ?? "") ?? 30
    static let seed = Int(ProcessInfo.processInfo.environment["FUZZ_SEED"] ?? "") ?? 7

    nonisolated static let samples = ["S-01-editor-save", "S-02-nested-bullets", "S-03-numbered-insert", "S-04-table-2x2",
                          "S-05-hyperlink", "S-05b-hyperlink-styled", "S-06-lock-linebreak-tab-lang", "S-07-hr",
                          "S-08-sire-body", "S-09-subscript", "S-10-empty-note"]

    static func check(_ xaml: String, _ ctx: XamlContext, _ label: String) -> Bool {
        guard !xaml.isEmpty else { return true }
        guard case .success(let doc) = XamlDOM.parse(xaml) else {
            Issue.record("\(label): output does not parse: \(xaml.prefix(300))")
            return false
        }
        if case .notLoadable(let issues) = doc.loadability {
            Issue.record("\(label): output not loadable \(issues): \(xaml.prefix(300))")
            return false
        }
        guard case .document(let s, let m) = XamlReader.read(xaml, context: ctx) else {
            Issue.record("\(label): output not readable")
            return false
        }
        let again = XamlWriter.write(s, metadata: m, context: ctx)
        if again != xaml {
            let a = Array(xaml.utf16), b = Array(again.utf16)
            var k = 0
            while k < min(a.count, b.count), a[k] == b[k] { k += 1 }
            let lo = max(0, k - 160)
            func cut(_ u: [UInt16]) -> String { String(decoding: u[lo..<min(u.count, k + 160)], as: UTF16.self) }
            Issue.record("\(label): not a fixed point at \(k)\n first: …\(cut(a))…\nsecond: …\(cut(b))…")
            return false
        }
        return true
    }

    @Test(arguments: samples) func randomEditsKeepTheOutputLoadableAndStable(_ name: String) throws {
        let ctx: XamlContext = name.contains("sire") ? .sirePane : .containerEditor
        let (s0, meta) = RichTest.read(try RichTest.sample(name + ".xaml"), ctx)
        var rng = Rng(state: UInt64(bitPattern: Int64(name.utf8.reduce(Self.seed) { $0 &* 31 &+ Int($1) })))
        let storage = NSTextStorage(attributedString: s0)
        let frags = [RichTest.doc(##"<Paragraph><Run FontWeight="Bold">frag</Run></Paragraph><Paragraph><Run>two</Run></Paragraph>"##),
                     HTMLToXAML.convert("<b>web</b> <i>it</i><ul><li>u</li></ul>"),
                     HTMLToXAML.convert("<table><tr><td>c1</td><td>c2</td></tr></table>")]
        for step in 0..<Self.steps {
            let n = storage.length
            let loc = rng.int(n + 1)
            let len = min(n - loc, rng.int(6))
            let typing: [NSAttributedString.Key: Any] = n > 0
                ? storage.attributes(at: max(0, min(loc, n - 1)), effectiveRange: nil)
                : XamlReader.typingAttributes(for: meta)
            switch rng.int(10) {
            case 0, 1:
                storage.replaceCharacters(in: NSRange(location: loc, length: len),
                                          with: NSAttributedString(string: ["x", "word ", "\t", "Ω", "&<>\""][rng.int(5)], attributes: typing))
            case 2:
                storage.replaceCharacters(in: NSRange(location: loc, length: len),
                                          with: NSAttributedString(string: ["\n", "\u{2028}"][rng.int(2)], attributes: typing))
            case 3:
                if len > 0 { storage.deleteCharacters(in: NSRange(location: loc, length: len)) }
            case 4:
                if len > 0 {
                    let r = NSRange(location: loc, length: len)
                    switch rng.int(4) {
                    case 0:
                        if let f = storage.attribute(.font, at: loc, effectiveRange: nil) as? NSFont {
                            storage.addAttribute(.font, value: NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask), range: r)
                        }
                    case 1: storage.addAttribute(.foregroundColor, value: NSColor(srgbRed: 0.8, green: 0.1, blue: 0.1, alpha: 1), range: r)
                    case 2: storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
                    default: storage.addAttribute(.link, value: URL(string: "https://example.com/\(step)")!, range: r)
                    }
                }
            case 5:
                _ = RichListFormatter.toggleList(rng.int(2) == 0 ? .bullets : .numbered, in: storage,
                                                 selection: NSRange(location: loc, length: len))
            case 6:
                _ = rng.int(2) == 0 ? RichListFormatter.indent(storage, selection: NSRange(location: loc, length: len))
                    : RichListFormatter.outdent(storage, selection: NSRange(location: loc, length: len))
            case 7:
                _ = XamlReader.insertFragment(frags[rng.int(frags.count)], into: storage,
                                              replacing: NSRange(location: loc, length: len), base: ctx)
            case 8:
                if len > 0 { LockRules.lock(storage, range: NSRange(location: loc, length: len)) } else {
                    LockRules.unlock(storage, range: NSRange(location: loc, length: 0))
                }
            default:
                _ = RichListFormatter.moveItem(storage, selection: NSRange(location: loc, length: 0), up: rng.int(2) == 0)
            }
            let out = XamlWriter.write(storage, metadata: meta, context: ctx)
            guard Self.check(out, ctx, "\(name) step \(step)") else { return }
            // No visible text is lost or invented by the save (empty paragraphs aside: the synthetic one after a final
            // table is never written).
            let back: NSAttributedString
            if case .document(let b, _) = XamlReader.read(out, context: ctx) { back = b } else { back = NSAttributedString() }
            let before = RichTest.paragraphs(storage).filter { !$0.isEmpty }
            let after = RichTest.paragraphs(back).filter { !$0.isEmpty }
            if before != after {
                Issue.record("\(name) step \(step): text changed\n before: \(before)\n  after: \(after)")
                return
            }
        }
    }
}
