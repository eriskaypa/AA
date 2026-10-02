// TV: 09 §7.13 round trip against the 09 §4.10 parts stored as fixtures (Fixtures/xlsxwriter/crew-4.10/, named
//     "<order>-<part path with '/' → '.'>").
import Foundation
import Testing
@testable import AACore

@Suite struct XlsxFixtureTests {
    @Test func crewPackageMatchesTheStoredParts() throws {
        let dir = Fixtures.url("xlsxwriter/crew-4.10")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(files.count == 6)
        let folder = TempFolder()
        let url = folder.file("crew.xlsx")
        try XlsxWriter.write(to: url, sheetName: "Crew", headers: ["Last Name", "CID"], rows: [["O'Neil & Co", "<1>"]])
        let r = try ZipReader(url: url)
        #expect(r.entries.map(\.name) == XlsxWriterTests.partNames)
        for (entry, file) in zip(r.entries, files) {
            let expected = try Data(contentsOf: dir.appending(path: file))
            #expect(try r.data(for: entry) == expected, "\(entry.name) vs \(file)")
        }
    }
}
