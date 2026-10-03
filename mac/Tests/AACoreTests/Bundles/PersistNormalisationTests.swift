// TV: 01 §6.6 / DATA-044 (AttachmentsMatch, copy, orphan sweep) — Stage V round 2, V2-COMPAT NFC/NFD (defence in
//     depth, F1 request): an attachment stored on disk with a decomposed (NFD) name and the composed (NFC) name a
//     bundle carries are the same attachment.
import Foundation
import Testing
@testable import AACore

@Suite struct PersistNormalisationTests {
    static let nfc = "Caf\u{00E9} menu.pdf"
    static let nfd = "Cafe\u{0301} menu.pdf"

    @Test func keysIgnoreNormalisationAndCase() {
        #expect(Array(Self.nfc.unicodeScalars) != Array(Self.nfd.unicodeScalars))   // different bytes on disk
        #expect(PersistBundleIO.key(Self.nfc) == PersistBundleIO.key(Self.nfd))
        #expect(PersistBundleIO.key("café MENU.pdf") == PersistBundleIO.key(Self.nfd))
    }

    @Test func nfdLocalCopyMatchesAndSurvivesTheSweep() throws {
        let bundle = TempFolder("aa-nfc-bundle"), local = TempFolder("aa-nfd-local")
        try bundle.write(Self.nfc, Data("pdf".utf8))
        try local.write(Self.nfd, Data("pdf".utf8))
        try local.write("orphan.txt", Data("x".utf8))
        // Same set apart from the orphan: not a match yet; without it, a match.
        #expect(!PersistBundleIO.attachmentsMatch(bundleDir: bundle.url, localDir: local.url))
        try FileManager.default.removeItem(at: local.file("orphan.txt"))
        #expect(PersistBundleIO.attachmentsMatch(bundleDir: bundle.url, localDir: local.url))
        // A full import: copy, then sweep — exactly one copy of the attachment remains.
        try local.write("orphan.txt", Data("x".utf8))
        let kept = try PersistBundleIO.copyTopLevelFiles(from: bundle.url, to: local.url)
        PersistBundleIO.sweepOrphans(local.url, keeping: kept)
        let leaves = PersistBundleIO.topLevelFiles(local.url).map(\.leaf)
        #expect(leaves.count == 1)
        #expect(leaves.first.map { Array($0.precomposedStringWithCanonicalMapping.unicodeScalars) }
                == Array(Self.nfc.unicodeScalars))
    }

    @Test func sweepKeepsAnNfdLeafNamedInNfc() throws {
        let local = TempFolder("aa-nfd-sweep")
        try local.write(Self.nfd, Data("pdf".utf8))
        PersistBundleIO.sweepOrphans(local.url, keeping: [PersistBundleIO.key(Self.nfc)])
        #expect(PersistBundleIO.topLevelFiles(local.url).count == 1)
    }
}
