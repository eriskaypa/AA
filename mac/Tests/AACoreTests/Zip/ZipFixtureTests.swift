// TV: 01 §6.7 — archives the writer never produces: a system `ditto` archive (Deflate + data descriptors, a
//     directory entry) and a legacy archive with CP437 names and no UTF-8 flag (Fixtures/zip/).
import Foundation
import Testing
@testable import AACore

@Suite struct ZipFixtureTests {
    @Test func dittoArchiveWithDataDescriptors() throws {
        let r = try ZipReader(url: Fixtures.url("zip/ditto-descriptors.zip"))
        #expect(r.entries.map(\.name) == ["sample-data.json", "files/", "files/a.txt"])
        #expect(r.entries.map(\.isDirectory) == [false, true, false])
        let json = try #require(r.entry(named: "sample-data.json"))
        #expect(json.method == 8)
        #expect(try r.data(for: json) == (try Fixtures.data("json/A01.appdata.golden.json")))
        #expect(try r.data(for: #require(r.entry(named: "files/a.txt"))) == Data("hello from ditto\n".utf8))
        let folder = TempFolder()
        try r.extractAll(to: folder.url)
        #expect(try folder.readText("files/a.txt") == "hello from ditto\n")
    }

    @Test func cp437Names() throws {
        let r = try ZipReader(url: Fixtures.url("zip/cp437-names.zip"))
        #expect(r.entries.map(\.name) == ["caf\u{E9}.txt", "\u{3A9}.txt"])
        #expect(r.entries.allSatisfy { !$0.isUTF8 })
        #expect(try r.data(for: r.entries[0]) == Data("cafe".utf8))
        #expect(try r.data(for: r.entries[1]) == Data("omega".utf8))
        #expect(r.entries[0].modified != nil)
    }
}
