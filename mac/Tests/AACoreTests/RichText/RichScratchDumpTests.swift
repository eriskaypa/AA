import AppKit
import Testing
@testable import AACore

@MainActor
@Suite struct RichScratchDumpTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RICH_DUMP"] != nil)) func dump() throws {
        var body = ""
        var k = 0
        while body.utf8.count < 1_000_000 {
            body += ##"<Paragraph><Run>Line \##(k) — check the main engine </Run><Run FontWeight="Bold" Foreground="#FFC00000">oil level</Run><Span Background="#FFFFFF00"><Run> and log it.</Run></Span></Paragraph>"##
            k += 1
        }
        let xaml = RichTest.doc(body)
        for _ in 0..<(ProcessInfo.processInfo.environment["RICH_LOOP"] != nil ? 200 : 3) {
            var t = Date()
            guard case .success(let tree) = XamlXMLScanner.scan(xaml) else { return }
            print("scan \(Int(Date().timeIntervalSince(t) * 1000))"); t = Date()
            guard case .success(let d) = XamlDOMBuilder.build(source: xaml, tree: tree) else { return }
            print("build \(Int(Date().timeIntervalSince(t) * 1000))"); t = Date()
            let r = XamlStyleResolver(d, context: .containerEditor)
            print("resolve \(Int(Date().timeIntervalSince(t) * 1000)) \(r.computed(d.root).fontSize)")
        }
    }
}
