// TV: 03 BD.7.3 — the resource byte copies match the pinned SHA-256 / sizes (Fixtures/foundation/resource-pins.json)
//     and the originals they were copied from (read-only, outside mac/).
import CryptoKit
import Foundation
import Testing
@testable import AACore

@Suite struct ResourcePinTests {
    static func sha256(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }
    static var macRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test func pinsMatch() throws {
        let pins = try #require(try JSONParser.parse(Fixtures.data("foundation/resource-pins.json")).objectValue)
        #expect(pins.count == 2)
        for (path, value) in pins {
            let d = try Data(contentsOf: Self.macRoot.appending(path: path))
            #expect(Self.sha256(d) == value.objectValue?["sha256"]?.stringValue, "\(path)")
            guard case .number(let size)? = value.objectValue?["size"] else { Issue.record("no size for \(path)"); continue }
            #expect(d.count == size.intValue, "\(path)")
        }
    }

    // The copies equal the originals byte for byte (skipped when the original tree is not next to mac/).
    @Test func copiesEqualTheOriginals() throws {
        let originals: [(String, String)] = [("Sources/AACore/Resources/sire2_question_bank.json", "../AA/Sire/Data/sire2_question_bank.json"),
                                             ("Sources/AA/Resources/Splash.png", "../AA/Assets/Splash.png")]
        for (copy, original) in originals {
            let o = Self.macRoot.appending(path: original)
            guard FileManager.default.fileExists(atPath: o.path) else { continue }
            #expect(try Data(contentsOf: Self.macRoot.appending(path: copy)) == (try Data(contentsOf: o)), "\(copy)")
        }
    }
}
