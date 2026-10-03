// TV: 11 §7.1 (LinkScanner L1…L26), §7.2 (NormalizeLinkUri / formal links), DEV-11 (annotation URLs).
import Foundation
import Testing
@testable import AACore

@Suite("W-PDF link scanner (11 §7.1, §7.2)")
struct PdfLinkScannerTests {
    typealias S = PdfLinkScanner.Segment
    func scan(_ s: String) -> [S] { PdfLinkScanner.scan(s) }

    // TV: 11 §7.1 L1…L23, L26
    static let vectors: [(String, [S])] = {
        var v: [(String, [S])] = []
        v.append(("Visit https://example.com.", [S("Visit ", nil), S("https://example.com", "https://example.com"), S(".", nil)]))
        v.append(("www.imo.org/en", [S("www.imo.org/en", "https://www.imo.org/en")]))
        v.append(("Mail ops@ship.co.uk, thanks", [S("Mail ", nil), S("ops@ship.co.uk", "mailto:ops@ship.co.uk"), S(", thanks", nil)]))
        v.append(("backup_www.tar.gz", [S("backup_www.tar.gz", nil)]))
        v.append(("C:\\svc\\www.cache\\x", [S("C:\\svc\\www.cache\\x", nil)]))
        v.append(("(see http://a.b/c)", [S("(see ", nil), S("http://a.b/c", "http://a.b/c"), S(")", nil)]))
        v.append(("\"https://x.y/z\"", [S("\"", nil), S("https://x.y/z", "https://x.y/z"), S("\"", nil)]))
        v.append(("HTTPS://EXAMPLE.COM", [S("HTTPS://EXAMPLE.COM", "HTTPS://EXAMPLE.COM")]))
        v.append(("WWW.Example.com", [S("WWW.Example.com", "https://WWW.Example.com")]))
        v.append(("mailto:joe@x.com", [S("mailto:joe@x.com", nil)]))
        v.append(("a,https://x.y", [S("a,https://x.y", nil)]))
        v.append(("https://en.wikipedia.org/wiki/Foo_(bar)", [S("https://en.wikipedia.org/wiki/Foo_", "https://en.wikipedia.org/wiki/Foo_"), S("(bar)", nil)]))
        v.append(("user@host", [S("user@host", nil)]))
        v.append(("x@y.c", [S("x@y.c", nil)]))
        v.append(("first.last+tag@sub.example.org!", [S("first.last+tag@sub.example.org", "mailto:first.last+tag@sub.example.org"), S("!", nil)]))
        v.append(("www..", [S("www", "www"), S("..", nil)]))
        v.append(("Go to https://a.com/x?y=1;", [S("Go to ", nil), S("https://a.com/x?y=1", "https://a.com/x?y=1"), S(";", nil)]))
        v.append(("\thttps://a.b", [S("\t", nil), S("https://a.b", "https://a.b")]))
        v.append(("https://", [S("https://", nil)]))
        v.append(("<https://a.b>", [S("<", nil), S("https://a.b", "https://a.b"), S(">", nil)]))
        v.append(("[www.a.io]", [S("[", nil), S("www.a.io", "https://www.a.io"), S("]", nil)]))
        v.append(("a@b.co and c@d.io", [S("a@b.co", "mailto:a@b.co"), S(" and ", nil), S("c@d.io", "mailto:c@d.io")]))
        v.append(("\u{00A0}https://a.b", [S("\u{00A0}", nil), S("https://a.b", "https://a.b")]))
        return v
    }()

    @Test(arguments: PdfLinkScannerTests.vectors)
    func vectors(_ input: String, _ expected: [S]) {
        #expect(scan(input) == expected)
    }

    // TV: 11 §7.1 L19
    @Test func emptyInput() { #expect(scan("").isEmpty) }

    // TV: 11 §7.1 L24, L25 — linear on pathological tokens (< 1 s; target < 100 ms)
    @Test func pathologicalTokensStayLinear() {
        let a = String(repeating: "a", count: 40_000) + "@"
        let b = "x" + String(repeating: "www.a.b", count: 10_000)
        let t0 = Date()
        #expect(scan(a) == [S(a, nil)])
        #expect(scan(b) == [S(b, nil)])
        #expect(Date().timeIntervalSince(t0) < 1.0)
    }

    // TV: 11 §7.2
    @Test func normalizeLinkUri() {
        #expect(PdfLinkScanner.normalizeLinkUri(nil) == nil)
        #expect(PdfLinkScanner.normalizeLinkUri("") == nil)
        #expect(PdfLinkScanner.normalizeLinkUri("   ") == nil)
        #expect(PdfLinkScanner.normalizeLinkUri(" www.x.com ") == "https://www.x.com")
        #expect(PdfLinkScanner.normalizeLinkUri("WWW.X.COM") == "https://WWW.X.COM")
        #expect(PdfLinkScanner.normalizeLinkUri("mailto:a@b.co") == "mailto:a@b.co")
        #expect(PdfLinkScanner.normalizeLinkUri("https://example.com") == "https://example.com")     // DEV-11
    }

    @Test func toUri() {
        #expect(PdfLinkScanner.toUri("a@b.co", isMail: true) == "mailto:a@b.co")
        #expect(PdfLinkScanner.toUri("www.a.io", isMail: false) == "https://www.a.io")
        #expect(PdfLinkScanner.toUri("http://a", isMail: false) == "http://a")
    }

    // DEV-11: strings Foundation rejects are percent-encoded before the annotation is written.
    @Test func annotationURLs() {
        #expect(PdfLinkScanner.annotationURL("https://a.b/c d")?.absoluteString == "https://a.b/c%20d")
        #expect(PdfLinkScanner.annotationURL("mailto:a@b.co")?.absoluteString == "mailto:a@b.co")
        #expect(PdfLinkScanner.annotationURL("https://example.com")?.absoluteString == "https://example.com")
        #expect(PdfLinkScanner.annotationURL("www") == nil)                // no scheme → no annotation
    }
}
