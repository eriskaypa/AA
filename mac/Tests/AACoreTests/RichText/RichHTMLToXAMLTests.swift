// TV: 05 §7.1 (H1–H20, NormaliseColor, ParseLengthPx, MapAlign, legacy `size`), §3.3 rules 1–13, CONT-035,
//     CONT-037, DECISIONS 05 (whitespace clean-up: H7 has no blank " " paragraph), §8 K-12 / K-13.
import Foundation
import Testing
@testable import AACore

@Suite struct RichHTMLToXAMLTests {
    static let R = "<Section xml:space=\"preserve\" xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\">"
    static let E = "</Section>"

    static func expectEqual(_ html: String, _ expectedBody: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let got = HTMLToXAML.convert(html)
        #expect(RichTest.semanticallyEqual(got, R + expectedBody + E),
                "\(html)\n got: \(got)", sourceLocation: sourceLocation)
    }

    @Test func h1Bold() {
        Self.expectEqual("<b>Hi</b>", ##"<Paragraph><Span FontWeight="Bold"><Run FontWeight="Bold">Hi</Run></Span></Paragraph>"##)
        // Exact bytes too (XmlWriter shape: attribute order and quoting).
        #expect(HTMLToXAML.convert("<b>Hi</b>") == Self.R
                + ##"<Paragraph><Span FontWeight="Bold"><Run FontWeight="Bold">Hi</Run></Span></Paragraph>"## + Self.E)
    }

    @Test func h2ParagraphAlignmentAndRgb() {
        Self.expectEqual(##"<p style="text-align:center;color:rgb(255,0,0)">Hello <i>world</i></p>"##,
                         ##"<Paragraph TextAlignment="Center"><Run Foreground="#FF0000">Hello </Run><Span FontStyle="Italic" Foreground="#FF0000"><Run FontStyle="Italic" Foreground="#FF0000">world</Run></Span></Paragraph>"##)
    }

    @Test func h3List() {
        Self.expectEqual("<ul><li>One</li><li>Two <b>bold</b></li></ul>",
                         ##"<List MarkerStyle="Disc"><ListItem><Paragraph><Run>One</Run></Paragraph></ListItem><ListItem><Paragraph><Run>Two </Run><Span FontWeight="Bold"><Run FontWeight="Bold">bold</Run></Span></Paragraph></ListItem></List>"##)
    }

    @Test func h4TableWithHeaderAndColspan() {
        Self.expectEqual(##"<table><tr><th>A</th><th>B</th></tr><tr><td colspan="2" style="text-align:right">C</td></tr></table>"##,
                         ##"<Table CellSpacing="0" Margin="0,4,0,4"><Table.Columns><TableColumn /><TableColumn /></Table.Columns><TableRowGroup><TableRow><TableCell BorderBrush="#FF9AA0A6" BorderThickness="0.6" Padding="3,1,3,1"><Paragraph><Run FontWeight="Bold">A</Run></Paragraph></TableCell><TableCell BorderBrush="#FF9AA0A6" BorderThickness="0.6" Padding="3,1,3,1"><Paragraph><Run FontWeight="Bold">B</Run></Paragraph></TableCell></TableRow><TableRow><TableCell BorderBrush="#FF9AA0A6" BorderThickness="0.6" Padding="3,1,3,1" ColumnSpan="2"><Paragraph TextAlignment="Right"><Run>C</Run></Paragraph></TableCell></TableRow></TableRowGroup></Table>"##)
    }

    @Test func h5LineBreak() {
        Self.expectEqual("a<br>b", "<Paragraph><Run>a</Run><LineBreak /><Run>b</Run></Paragraph>")
    }

    @Test func h6Heading() {
        Self.expectEqual("<h1>Title</h1>", ##"<Paragraph><Run FontWeight="Bold" FontSize="22">Title</Run></Paragraph>"##)
        Self.expectEqual("<h2>T</h2>", ##"<Paragraph><Run FontWeight="Bold" FontSize="18">T</Run></Paragraph>"##)
        Self.expectEqual("<h6>T</h6>", ##"<Paragraph><Run FontWeight="Bold" FontSize="12">T</Run></Paragraph>"##)
        Self.expectEqual(##"<h3 style="font-size:10px">T</h3>"##, ##"<Paragraph><Run FontWeight="Bold" FontSize="10">T</Run></Paragraph>"##)
    }

    @Test func h7WhitespaceBetweenBlocksIsCleanedUp() {
        // DECISIONS 05: the Windows quirk K-12 (a " " paragraph between the two) is cleaned up on the Mac.
        Self.expectEqual("<p>a</p>\n<p>b</p>", "<Paragraph><Run>a</Run></Paragraph><Paragraph><Run>b</Run></Paragraph>")
        // A div wrapping a p leaves no empty paragraph either.
        Self.expectEqual("<div><p>x</p></div>", "<Paragraph><Run>x</Run></Paragraph>")
        Self.expectEqual("<div>\n  <p>x</p>\n</div>", "<Paragraph><Run>x</Run></Paragraph>")
        // Content before the nested block keeps its paragraph; a truly empty <p></p> stays (a blank line).
        Self.expectEqual("<div>a<p>b</p>c</div>",
                         "<Paragraph><Run>a</Run></Paragraph><Paragraph><Run>b</Run></Paragraph><Paragraph><Run>c</Run></Paragraph>")
        Self.expectEqual("<p></p><p>x</p>", "<Paragraph /><Paragraph><Run>x</Run></Paragraph>")
        // Significant whitespace between inline elements stays.
        Self.expectEqual("<b>a</b> <i>b</i>",
                         ##"<Paragraph><Span FontWeight="Bold"><Run FontWeight="Bold">a</Run></Span><Run> </Run><Span FontStyle="Italic"><Run FontStyle="Italic">b</Run></Span></Paragraph>"##)
    }

    @Test func h8FontSizePointsAndQuotedFamily() {
        Self.expectEqual(##"<span style="font-size:12pt;font-family:'Times New Roman'">x</span>"##,
                         ##"<Paragraph><Span FontFamily="Times New Roman" FontSize="16"><Run FontFamily="Times New Roman" FontSize="16">x</Run></Span></Paragraph>"##)
    }

    @Test func h9HyperlinkSkipsForegroundOnTheLinkOnly() {
        Self.expectEqual(##"<a href="https://imo.org" style="color:red">IMO</a>"##,
                         ##"<Paragraph><Hyperlink NavigateUri="https://imo.org"><Run Foreground="red">IMO</Run></Hyperlink></Paragraph>"##)
        Self.expectEqual(##"<a>no href</a>"##, "<Paragraph><Hyperlink><Run>no href</Run></Hyperlink></Paragraph>")
    }

    @Test func h10LegacyFontAttributes() {
        Self.expectEqual(##"<font color="#12" size="5">t</font>"##,
                         ##"<Paragraph><Span FontSize="18"><Run FontSize="18">t</Run></Span></Paragraph>"##)
        Self.expectEqual(##"<font face="Arial" size="+1">t</font>"##,
                         ##"<Paragraph><Span FontFamily="Arial" FontSize="10"><Run FontFamily="Arial" FontSize="10">t</Run></Span></Paragraph>"##)
        // An invalid colour clears an inherited one.
        Self.expectEqual(##"<span style="color:#00ff00"><font color="nonsense">t</font></span>"##,
                         ##"<Paragraph><Span Foreground="#00ff00"><Span><Run>t</Run></Span></Span></Paragraph>"##)
    }

    @Test func h11NbspCollapses() {
        Self.expectEqual("<p>a&nbsp;&nbsp;b</p>", "<Paragraph><Run>a b</Run></Paragraph>")
    }

    @Test func h12NestedTableFlattenedNotDuplicated() {
        let got = HTMLToXAML.convert("<table><tr><td>x<table><tr><td>y</td></tr></table></td></tr></table>")
        #expect(got.components(separatedBy: "<TableRow>").count == 2)            // one row
        #expect(got.components(separatedBy: "<TableColumn />").count == 2)      // one column
        #expect(got.contains("<Run>x</Run><Span><Span><Span><Run>y</Run></Span></Span></Span>"))
        #expect(got.components(separatedBy: ">y<").count == 2)                    // y appears once
    }

    @Test func h13HorizontalRule() {
        #expect(HTMLToXAML.convert("<hr>") == Self.R
                + ##"<Paragraph BorderThickness="0,0,0,1" BorderBrush="#888" Padding="0" />"## + Self.E)
    }

    @Test func h14Blockquote() {
        Self.expectEqual("<blockquote>q</blockquote>", ##"<Paragraph Margin="20,0,0,0"><Run>q</Run></Paragraph>"##)
    }

    @Test func h15NonContentRemoved() {
        Self.expectEqual("<script>x()</script><style>p{}</style><p>ok</p>", "<Paragraph><Run>ok</Run></Paragraph>")
        Self.expectEqual("<html><head><title>T</title><meta charset=\"utf-8\"><link rel=\"x\"></head><body><p>ok</p></body></html>",
                         "<Paragraph><Run>ok</Run></Paragraph>")
    }

    @Test func h16ImagesDropped() {
        Self.expectEqual(##"<img src="a.png"><p>t</p>"##, "<Paragraph><Run>t</Run></Paragraph>")
    }

    @Test func h17EmptyTableGivesAnEmptySection() {
        #expect(HTMLToXAML.convert("<table></table>")
                == ##"<Section xml:space="preserve" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" />"##)
        #expect(HTMLToXAML.convert("<table><tr></tr></table>")
                == ##"<Section xml:space="preserve" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" />"##)
    }

    @Test func h18Blank() {
        #expect(HTMLToXAML.convert("") == "")
        #expect(HTMLToXAML.convert("   ") == "")
        #expect(HTMLToXAML.convert("\r\n\t") == "")
    }

    @Test func h19CfHtmlFragment() {
        let cf = "Version:0.9\r\nStartHTML:00000097\r\nEndHTML:00000174\r\nStartFragment:00000131\r\nEndFragment:00000140\r\n<html><body>\r\n<!--StartFragment--><b>Hi</b><!--EndFragment-->\r\n</body></html>"
        #expect(HTMLToXAML.extractFragment(cf) == "<b>Hi</b>")
        Self.expectEqual(cf, ##"<Paragraph><Span FontWeight="Bold"><Run FontWeight="Bold">Hi</Run></Span></Paragraph>"##)
        // No offsets → from "<html" on.
        #expect(HTMLToXAML.extractFragment("Version:0.9\r\n<HTML><body>x</body></HTML>") == "<HTML><body>x</body></HTML>")
        #expect(HTMLToXAML.extractFragment("<p>x</p>") == "<p>x</p>")
        // Offsets are UTF-8 bytes (non-ASCII before the fragment).
        let head = "Version:0.9\r\nStartFragment:00000000\r\nEndFragment:00000000\r\n<html><body>é<!--StartFragment-->"
        let frag = "<i>ü</i>"
        let s = head.utf8.count, e = s + frag.utf8.count
        let doc = head.replacingOccurrences(of: "StartFragment:00000000", with: String(format: "StartFragment:%08d", s))
            .replacingOccurrences(of: "EndFragment:00000000", with: String(format: "EndFragment:%08d", e)) + frag + "</body></html>"
        #expect(HTMLToXAML.extractFragment(doc) == frag)
    }

    @Test func h20PreKeepsWhitespace() {
        Self.expectEqual("<pre>a   b</pre>", "<Paragraph><Run>a   b</Run></Paragraph>")
        Self.expectEqual("<p>a   \n  b</p>", "<Paragraph><Run>a b</Run></Paragraph>")
    }

    @Test func listItemsAndStrays() {
        // Only direct li children; a stray li outside a list is a paragraph; ol → Decimal.
        Self.expectEqual("<ol><li>a</li>text<li>b</li></ol>",
                         ##"<List MarkerStyle="Decimal"><ListItem><Paragraph><Run>a</Run></Paragraph></ListItem><ListItem><Paragraph><Run>b</Run></Paragraph></ListItem></List>"##)
        Self.expectEqual(##"<li style="color:#123">x</li>"##, ##"<Paragraph><Run Foreground="#123">x</Run></Paragraph>"##)
        // Unclosed li items are fixed (HtmlAgilityPack OptionFixNestedTags).
        Self.expectEqual("<ul><li>a<li>b</ul>",
                         ##"<List MarkerStyle="Disc"><ListItem><Paragraph><Run>a</Run></Paragraph></ListItem><ListItem><Paragraph><Run>b</Run></Paragraph></ListItem></List>"##)
    }

    @Test func inlineDecorationsAndBackgroundFlowDown() {
        Self.expectEqual(##"<p style="background-color:yellow;font-weight:700"><u>a</u><s>b</s><del style="text-decoration:underline">c</del></p>"##,
                         ##"<Paragraph><Span FontWeight="Bold" TextDecorations="Underline" Background="yellow"><Run FontWeight="Bold" TextDecorations="Underline" Background="yellow">a</Run></Span><Span FontWeight="Bold" TextDecorations="Strikethrough" Background="yellow"><Run FontWeight="Bold" TextDecorations="Strikethrough" Background="yellow">b</Run></Span><Span FontWeight="Bold" TextDecorations="Underline,Strikethrough" Background="yellow"><Run FontWeight="Bold" TextDecorations="Underline,Strikethrough" Background="yellow">c</Run></Span></Paragraph>"##)
        // An inner font-weight:normal cannot cancel an outer bold (a false flag writes nothing).
        Self.expectEqual(##"<b>x<span style="font-weight:normal">y</span></b>"##,
                         ##"<Paragraph><Span FontWeight="Bold"><Run FontWeight="Bold">x</Run><Span><Run>y</Run></Span></Span></Paragraph>"##)
        Self.expectEqual(##"<span style="text-decoration:underline"><span style="text-decoration:none">n</span></span>"##,
                         ##"<Paragraph><Span TextDecorations="Underline"><Span><Run>n</Run></Span></Span></Paragraph>"##)
    }

    @Test func entitiesAndEscaping() {
        Self.expectEqual("<p>A &amp; B &lt;c&gt; &quot;q&quot; &euro;&#169;&#x263A; &bogus;</p>",
                         "<Paragraph><Run>A &amp; B &lt;c&gt; \"q\" €©☺ &amp;bogus;</Run></Paragraph>")
        #expect(HTMLToXAML.convert(##"<a href="x?a=1&amp;b=2">l</a>"##).contains(##"NavigateUri="x?a=1&amp;b=2""##))
        // A character XmlWriter refuses → no conversion (the caller pastes plain text).
        #expect(HTMLToXAML.convert("<p>a\u{1}b</p>") == "")
    }

    @Test func normaliseColorVectors() {
        let cases: [(String, String?)] = [
            ("#abc", "#abc"), ("#ABCD", "#ABCD"), ("#12", nil), ("#ggg", nil), ("rgb(300,20,0)", "#FF1400"),
            ("rgb(0, 128, 255)", "#0080FF"), ("rgb(-1,0,0)", nil), ("RED", "RED"), ("transparent", "transparent"),
            ("lightgrey", nil), ("rebeccapurple", nil), ("currentColor", nil), ("rgb(0 0 0 / 50%)", nil), ("", nil),
            ("  #FF0000  ", "#FF0000"), ("RGBA(1,2,3,0.5)", "#010203"), ("rgb(99999999999999999999,0,0)", "#FF0000"),
        ]
        for (input, expected) in cases { #expect(HTMLToXAML.normaliseColor(input) == expected, "\(input)") }
        // K-13 (Mac decision): alpha 0 → no colour (Windows: #000000).
        #expect(HTMLToXAML.normaliseColor("rgba(0,0,0,0)") == nil)
        #expect(HTMLToXAML.normaliseColor("rgba(0,0,0,0.0)") == nil)
    }

    @Test func parseLengthVectors() {
        let cases: [(String, Double?)] = [("16px", 16), ("16", 16), ("12pt", 15.996), ("1.5em", 21), ("2rem", 28),
                                          ("150%", 21), ("12 PX", 12), ("medium", nil), ("calc(1px)", nil), (".", nil),
                                          ("1.2.3", nil)]
        for (input, expected) in cases {
            let got = HTMLToXAML.parseLengthPx(input)
            if let e = expected { #expect(got.map { abs($0 - e) < 1e-9 } == true, "\(input) → \(String(describing: got))") }
            else { #expect(got == nil, "\(input)") }
        }
        #expect(HTMLToXAML.mapAlign("CENTER") == "Center" && HTMLToXAML.mapAlign("start") == "Left")
        #expect(HTMLToXAML.mapAlign(" justify ") == "Justify" && HTMLToXAML.mapAlign("right") == "Right")
        #expect(HTMLToXAML.formatSize(15.996) == "16" && HTMLToXAML.formatSize(14) == "14")
        #expect(HTMLToXAML.formatSize(13.333) == "13.33" && HTMLToXAML.formatSize(0.125) == "0.13")
        #expect(HTMLToXAML.formatSize(21.005) == "21.01")
    }

    @Test func legacySizeAttribute() {
        Self.expectEqual(##"<font size="3">a</font>"##, ##"<Paragraph><Span FontSize="14"><Run FontSize="14">a</Run></Span></Paragraph>"##)
        Self.expectEqual(##"<font size="+1">a</font>"##, ##"<Paragraph><Span FontSize="10"><Run FontSize="10">a</Run></Span></Paragraph>"##)
        Self.expectEqual(##"<font size="x">a</font>"##, "<Paragraph><Span><Run>a</Run></Span></Paragraph>")
    }

    @Test func tableDetails() {
        // thead/tbody rows in order; rowspan kept; invalid spans → 1; cell background becomes a run highlight.
        let html = ##"<table style="color:#111"><thead><tr><th rowspan="2">H</th><th colspan="x">I</th></tr></thead><tbody><tr bgcolor="red"><td style="background:#eee"><p>a</p><div>b</div></td></tr></tbody></table>"##
        let got = HTMLToXAML.convert(html)
        #expect(got.contains(##"RowSpan="2""##))
        #expect(!got.contains("ColumnSpan"))
        #expect(got.contains(##"<Run FontWeight="Bold" Foreground="#111">H</Run>"##))
        #expect(got.contains(##"<Span Foreground="#111" Background="#eee"><Run Foreground="#111" Background="#eee">a</Run></Span>"##))
        #expect(got.components(separatedBy: "<TableRow>").count == 3)
        // The result loads as a fragment (CONT-161) with a 2-column table.
        #expect(got.components(separatedBy: "<TableColumn />").count == 3)
    }

    @Test func fixtureFilesConvertAsDocumented() throws {
        // Fixtures/html/*.html with the expected XAML body beside them (*.xaml.txt).
        let dir = Fixtures.url("html")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".html") }.sorted()
        #expect(!files.isEmpty)
        for f in files {
            let html = try Fixtures.string("html/" + f)
            let expected = try Fixtures.string("html/" + f.replacingOccurrences(of: ".html", with: ".xaml.txt"))
            let got = HTMLToXAML.convert(html)
            #expect(RichTest.semanticallyEqual(got, NetText.trim(expected)), "\(f)\n got: \(got)")
            if case .failure(let e) = XamlDOM.parse(got) { Issue.record("\(f) output does not parse: \(e)") }
        }
    }
}
