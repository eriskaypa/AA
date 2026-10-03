// TV: CONT-162 (tolerant display of recoverable issues; the writer never re-emits an invalid recognised attribute),
//     CONT-006 (anything that is not well-formed is `.unparseable`, never a crash), 05 §4.3.7 (every Mac output is
//     well-formed and loadable), 01 §4.11 invariant 1 (a Mac-written body is a fixed point of read → write).
// Seeded, deterministic mutation fuzzing of the *stored input* (hand-edited, truncated or foreign XAML): random cuts,
// duplicated slices and injected attributes / elements / property elements / entities over every sample. For each
// mutant: read never traps; a readable mutant written after an edit parses, is loadable, and is a fixed point.
// Bounded (`FUZZ_MUTANTS`, default 60 per sample) so the gate stays fast.
import AppKit
import Testing
@testable import AACore

@MainActor
@Suite struct RichInputFuzzTests {
    static let mutants = Int(ProcessInfo.processInfo.environment["FUZZ_MUTANTS"] ?? "") ?? 60
    static let seed = UInt64(ProcessInfo.processInfo.environment["FUZZ_SEED"] ?? "") ?? 11

    /// Fragments injected at random offsets — every recognised-attribute grammar with valid and invalid values,
    /// markup extensions, duplicate properties, foreign elements, opaque containers, entities and newlines.
    static let injections = [
        ##" FontSize="abc""##, ##" FontSize="12pt""##, ##" FontWeight="SemiBold""##, ##" FontWeight="950""##,
        ##" Foreground="{x:Null}""##, ##" Foreground="{StaticResource X}""##, ##" Foreground="#80FF0000""##,
        ##" Background="#FFFFE699""##, ##" Background="sc#1,1,0.5,0.2""##, ##" TextDecorations="Underline, OverLine""##,
        ##" TextDecorations="Bogus""##, ##" Margin="1,2""##, ##" Margin="Auto""##, ##" LineHeight="-3""##,
        ##" xml:lang="EL-gr""##, ##" Typography.Kerning="maybe""##, ##" Foo="1""##, ##" p:Bar="2""##,
        ##" Text="t""##, ##" ColumnSpan="0""##, ##" MarkerStyle="Hexagon""##, ##" StartIndex="-4""##,
        ##" NavigateUri="https://x.y/?a=1&amp;b=2""##, ##" BaselineAlignment="Subscript""##,
        "<Run>ins</Run>", "<LineBreak />", "<Foo>chip</Foo>", "<InlineUIContainer><Button /></InlineUIContainer>",
        "<Run.Foreground><SolidColorBrush Color=\"Red\" Opacity=\"0.4\"/></Run.Foreground>",
        "<Paragraph.Background><LinearGradientBrush /></Paragraph.Background>", "&#xD;", "&#xD;&#xA;", "\n", "&amp;",
        "<Bold>b</Bold>", "<Hyperlink><Run>h</Run></Hyperlink>", "<Span Background=\"#FFFFE699\"><Run>l</Run></Span>",
        "<Paragraph>p</Paragraph>", "<List><ListItem><Paragraph>li</Paragraph></ListItem></List>", "<!-- c -->",
    ]

    static func mutate(_ src: String, _ rng: inout RichEditFuzzTests.Rng) -> String {
        var u = Array(src.utf16)
        for _ in 0..<(1 + rng.int(3)) {
            let at = rng.int(u.count + 1)
            switch rng.int(5) {
            case 0:                                                     // cut a slice
                let len = min(u.count - at, rng.int(24))
                u.removeSubrange(at..<(at + len))
            case 1:                                                     // duplicate a slice
                let len = min(u.count - at, rng.int(60))
                u.insert(contentsOf: u[at..<(at + len)], at: at)
            default:                                                    // inject a fragment (often just after a tag name)
                let frag = Array(Self.injections[rng.int(Self.injections.count)].utf16)
                var pos = at
                if frag.first == 0x20, let gt = u[at...].firstIndex(where: { $0 == 0x3E || $0 == 0x20 }) { pos = gt }
                u.insert(contentsOf: frag, at: pos)
            }
        }
        return String(decoding: u, as: UTF16.self)
    }

    /// As `RichEditFuzzTests.check`, except that opaque content is written back verbatim by design (§4.3.7 rule 10):
    /// an unknown element, or a recognised element the input already misplaced (a block inside an inline or a Run,
    /// shown as a chip), may remain. Invalid recognised *attributes* never may (CONT-162).
    static func check(_ out: String, input: XamlLoadability, _ ctx: XamlContext, _ label: String) -> Bool {
        guard case .success(let doc) = XamlDOM.parse(out) else {
            Issue.record("\(label)\n→ output does not parse: \(out)")
            return false
        }
        if case .notLoadable(let issues) = doc.loadability {
            var had: [XamlIssue] = []
            if case .notLoadable(let i) = input { had = i }
            let unexpected = issues.filter { issue in
                switch issue {
                case .unknownElement, .invalidNesting: return !had.contains(where: Self.isOpaqueIssue)
                default: return true
                }
            }
            if !unexpected.isEmpty {
                Issue.record("\(label)\n→ output not loadable \(unexpected): \(out)")
                return false
            }
        }
        guard case .document(let s, let m) = XamlReader.read(out, context: ctx) else {
            Issue.record("\(label)\n→ output not readable: \(out)")
            return false
        }
        let again = XamlWriter.write(s, metadata: m, context: ctx)
        if again != out {
            let a = Array(out.utf16), b = Array(again.utf16)
            var k = 0
            while k < min(a.count, b.count), a[k] == b[k] { k += 1 }
            let lo = max(0, k - 200)
            func cut(_ u: [UInt16]) -> String { String(decoding: u[lo..<min(u.count, k + 160)], as: UTF16.self) }
            Issue.record("\(label)\n→ not a fixed point at \(k)\n first: …\(cut(a))…\nsecond: …\(cut(b))…")
            return false
        }
        return true
    }

    /// The mutant without its (long) root start tag, for readable failure messages.
    static func afterRootTag(_ s: String) -> String {
        guard let gt = s.firstIndex(of: ">") else { return s }
        return String(s[s.index(after: gt)...])
    }

    static func isOpaqueIssue(_ i: XamlIssue) -> Bool {
        switch i {
        case .unknownElement, .invalidNesting: return true
        default: return false
        }
    }

    @Test(arguments: RichEditFuzzTests.samples) func mutatedInputsNeverTrapAndRewriteLoadably(_ name: String) throws {
        let ctx: XamlContext = name.contains("sire") ? .sirePane : .containerEditor
        let base = try RichTest.sample(name + ".xaml")
        var rng = RichEditFuzzTests.Rng(state: name.utf8.reduce(Self.seed) { $0 &* 131 &+ UInt64($1) })
        for k in 0..<Self.mutants {
            let src = Self.mutate(base, &rng)
            _ = LockRules.quickHasAnyLock(src)
            guard case .document(let s, let m) = XamlReader.read(src, context: ctx) else { continue }
            // Edit so the writer cannot take the untouched-source shortcut.
            let e = NSMutableAttributedString(attributedString: s)
            let at = rng.int(e.length + 1)
            let attrs: [NSAttributedString.Key: Any] = e.length > 0 ? e.attributes(at: min(at, e.length - 1), effectiveRange: nil)
                : XamlReader.typingAttributes(for: m)
            e.insert(NSAttributedString(string: "q", attributes: attrs), at: at)
            let out = XamlWriter.write(e, metadata: m, context: ctx)
            guard Self.check(out, input: m.loadability, ctx, "\(name) mutant \(k): \(Self.afterRootTag(src))") else { return }
        }
    }
}

/// Regression vectors for what the mutation fuzzing found (each was a colour change, a moved chip or a non-fixed-point
/// rewrite).
@MainActor
@Suite struct RichTolerantInputTests {
    static func write(_ xaml: String, _ ctx: XamlContext = .containerEditor) -> String {
        RichVectorRowTests.editedWrite(xaml, ctx)
    }

    @Test func elementsInsideARunAreShownWhereTheyStood() {
        let src = RichTest.doc(##"<Paragraph><Run Foreground="#FF0000FF">li<Bold>b</Bold>ne<Foo>chip</Foo>!</Run></Paragraph>"##)
        let (s, m) = RichTest.read(src)
        if case .notLoadable = m.loadability {} else { Issue.record("a Run with element content is not loadable") }
        #expect(s.string == "line\u{FFFC}!\n".replacingOccurrences(of: "line", with: "libne"))
        let b = RichTest.attrs(s, at: "b")
        #expect((b[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(RichTest.argb(b[.foregroundColor]) == 0xFF00_00FF)                  // inherits through the Run
        let out = RichTest.body(Self.write(src))
        #expect(out == ##"<Paragraph><Run Foreground="#FF0000FF">zli</Run><Run FontWeight="Bold" Foreground="#FF0000FF">b</Run><Run Foreground="#FF0000FF">ne</Run><Foo>chip</Foo><Run Foreground="#FF0000FF">!</Run></Paragraph>"##)
        #expect(RichTest.body(RichTest.roundTrip(RichTest.doc(out))) == out)            // fixed point
    }

    @Test func misplacedTableContentBecomesACell() {
        let src = RichTest.doc(##"<Table><TableRowGroup><Hyperlink><Run>h</Run></Hyperlink><TableRow><TableCell><Paragraph><Run>a</Run></Paragraph></TableCell></TableRow></TableRowGroup></Table><Paragraph><Run>after</Run></Paragraph>"##)
        let (s, _) = RichTest.read(src)
        #expect(RichTest.paragraphs(s).prefix(2) == ["h", "a"])
        let out = Self.write(src)
        if case .success(let d) = XamlDOM.parse(out) { #expect(d.loadability == .loadable) } else { Issue.record("unparseable") }
        #expect(RichTest.body(out).contains(##"<TableRow><TableCell><Paragraph><Hyperlink><Run>zh</Run></Hyperlink></Paragraph></TableCell></TableRow>"##))
        #expect(RichTest.roundTrip(out) == out)
    }

    @Test func aCarriedForegroundPropertyElementTakesPartInTheCascade() {
        for body in [##"<Paragraph><Paragraph.Foreground><SolidColorBrush Color="Red"/></Paragraph.Foreground><Run Foreground="#FF1A1A1A">x</Run><Run>y</Run></Paragraph>"##,
                     ##"<Section><Section.Foreground><SolidColorBrush Color="Red"/></Section.Foreground><Paragraph><Run Foreground="#FF1A1A1A">x</Run><Run>y</Run></Paragraph></Section>"##] {
            let out = Self.write(RichTest.doc(body))
            let (s, _) = RichTest.read(out)
            #expect(RichTest.argb(RichTest.attrs(s, at: "x")[.foregroundColor]) == 0xFF1A_1A1A, "\(out)")
            #expect(RichTest.argb(RichTest.attrs(s, at: "y")[.foregroundColor]) == 0xFFFF_0000, "\(out)")
            #expect(RichTest.body(out).contains(##"<Run Foreground="#FF1A1A1A">zx</Run><Run>y</Run>"##), "\(out)")
        }
        // An empty paragraph takes its colour from the terminator: the element is not doubled by an attribute.
        let empty = Self.write(RichTest.doc(##"<Paragraph><Paragraph.Foreground><SolidColorBrush Color="Red"/></Paragraph.Foreground></Paragraph><Paragraph><Run>t</Run></Paragraph>"##))
        if case .success(let d) = XamlDOM.parse(empty) { #expect(d.loadability == .loadable, "\(empty)") }
    }
}
