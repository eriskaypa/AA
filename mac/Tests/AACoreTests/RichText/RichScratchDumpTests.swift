import AppKit
import Testing
@testable import AACore

@MainActor
@Suite struct RichScratchDumpTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RICH_DUMP"] != nil)) func dump() throws {
        for name in ["S-01-editor-save.xaml", "S-02-nested-bullets.xaml", "S-03-numbered-insert.xaml", "S-04-table-2x2.xaml",
                     "S-05-hyperlink.xaml", "S-05b-hyperlink-styled.xaml", "S-06-lock-linebreak-tab-lang.xaml",
                     "S-07-hr.xaml", "S-08-sire-body.xaml", "S-09-subscript.xaml", "S-10-empty-note.xaml"] {
            let x = try RichTest.sample(name)
            let (s, _) = RichTest.read(x)
            print("=== \(name)\n\(s.string.debugDescription)")
            print(RichTest.body(RichTest.roundTrip(x)))
        }
    }
}
