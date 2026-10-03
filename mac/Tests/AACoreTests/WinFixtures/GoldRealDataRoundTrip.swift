// DATA-314: the optional local-only round trip of a REAL data.json (crew passports, dates of birth, next of kin).
// `AA_REAL_DATA_JSON=<path> swift test --filter GoldRealDataRoundTrip` (Scripts/fixtures.sh real-data <path>).
// The file is copied into a temporary folder and never written; nothing is committed, attached or printed except
// pass/fail, the byte counts and the first differing byte offset — never content.
import Foundation
import Testing
@testable import AACore

enum GoldRealData {
    struct Outcome: Equatable {
        var loaded: Bool
        var originalBytes: Int
        var resavedBytes: Int
        /// nil when byte-identical.
        var firstDifference: Int?
        var failure: String?

        /// The only text this test ever reports: no names, values or content.
        var summary: String {
            if let failure { return "real data.json: FAIL (\(failure)); \(originalBytes) bytes" }
            guard let at = firstDifference else { return "real data.json: PASS — \(originalBytes) bytes re-saved byte-identically" }
            return "real data.json: FAIL — first differing byte at offset \(at) (original \(originalBytes) bytes, re-saved \(resavedBytes) bytes)"
        }
    }

    static func firstDifference(_ a: Data, _ b: Data) -> Int? {
        let x = [UInt8](a), y = [UInt8](b)
        let n = min(x.count, y.count)
        for i in 0..<n where x[i] != y[i] { return i }
        return x.count == y.count ? nil : n
    }

    /// Load + SerializeForSave of a copy. Errors are reduced to their type name (a message could quote content).
    @MainActor
    static func roundTrip(_ original: Data) -> Outcome {
        let folder = TempFolder("gold-real-data")
        let ds = DataStore(appFolder: folder.url, secrets: InMemorySecretStore(), clock: SystemClock())
        ds.loadSettings()
        let copy = folder.file("data.json")
        do { try original.write(to: copy) } catch {
            return Outcome(loaded: false, originalBytes: original.count, resavedBytes: 0, firstDifference: 0, failure: "scratch copy failed")
        }
        let model: AppData
        do { model = try ds.loadFrom(copy) } catch {
            return Outcome(loaded: false, originalBytes: original.count, resavedBytes: 0, firstDifference: 0,
                           failure: "load threw \(type(of: error))")
        }
        do {
            let resaved = try ds.serializeForSave(model)
            return Outcome(loaded: true, originalBytes: original.count, resavedBytes: resaved.count,
                           firstDifference: firstDifference(original, resaved), failure: nil)
        } catch {
            return Outcome(loaded: true, originalBytes: original.count, resavedBytes: 0, firstDifference: 0,
                           failure: "save threw \(type(of: error))")
        }
    }
}

@Suite("WinFixtures — real data.json round trip (DATA-314, local only)", .tags(.goldWinFixtures))
struct GoldRealDataRoundTrip {
    @MainActor
    @Test("a real Windows data.json re-saves byte-identically",
          .enabled(if: GoldEnv.realDataJSON != nil, "set AA_REAL_DATA_JSON=<path to a real data.json> to run (local only, nothing is committed)"))
    func realFile() throws {
        let path = try #require(GoldEnv.realDataJSON)
        let original = try Data(contentsOf: URL(fileURLWithPath: path))
        let outcome = GoldRealData.roundTrip(original)
        print(outcome.summary)
        if outcome.failure != nil || outcome.firstDifference != nil { Issue.record(Comment(rawValue: outcome.summary)) }
    }

    @MainActor
    @Test("the report carries offsets and counts only (synthetic)")
    func reportShape() throws {
        #expect(GoldRealData.firstDifference(Data("abc".utf8), Data("abc".utf8)) == nil)
        #expect(GoldRealData.firstDifference(Data("abc".utf8), Data("abd".utf8)) == 2)
        #expect(GoldRealData.firstDifference(Data("abc".utf8), Data("ab".utf8)) == 2)
        let folder = TempFolder("gold-real-synthetic")
        let ds = DataStore(appFolder: folder.url, secrets: InMemorySecretStore(), clock: SystemClock())
        let ks = try ds.serializeForSave(GoldKitchenSink.build())
        let pass = GoldRealData.roundTrip(ks)
        #expect(pass.loaded && pass.firstDifference == nil && pass.failure == nil, "\(pass.summary)")
        let broken = GoldRealData.roundTrip(Data("{\"Equipment\":[{\"Name\":\"SECRET-PASSPORT-123\"".utf8))
        #expect(broken.failure != nil)
        #expect(!broken.summary.contains("SECRET"))
        var spaced = ks
        spaced.append(contentsOf: Array(" ".utf8))
        let diff = GoldRealData.roundTrip(spaced)
        #expect(diff.firstDifference == ks.count)
        #expect(diff.summary.contains("offset \(ks.count)"))
    }
}
