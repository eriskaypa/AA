// TV: 13 §7.8 CS-1…CS-19 (exact compact outputs, created/now fixed at 2026-09-27 12:00:00), CS-16/CS-17 (per-device
//     and excluded-settings isolation on apply), DECISIONS 13 Q-1/Q-2/Q-3 (receiver hardening), QR_SYNC_PROTOCOL.md §10
//     (FLASH-080…095, FLASH-107; VESSEL-284 Ports/Vessels travel whole with Order honoured).
import Foundation
import Testing
@testable import AACore

@Suite struct FlashChangeSetTests {
    static let cs: JSONObject = FlashTestKit.vectors["changeSets"]?.objectValue ?? JSONObject()
    static let now = FlashTestKit.created

    static func vector(_ id: String) -> JSONObject { cs[id]?.objectValue ?? JSONObject() }
    static func obj(_ v: JSONObject, _ key: String) -> JSONObject? { v[key]?.stringValue.map(FlashTestKit.object) }

    static func build(_ v: JSONObject) -> JSONObject? {
        FlashChangeSet.buildChangeSet(current: obj(v, "current") ?? JSONObject(), baselineData: obj(v, "baseline"),
                                      currentSettings: obj(v, "currentSettings"), baselineSettings: obj(v, "baselineSettings"),
                                      from: "Windows", created: now)
    }

    // TV: CS-1, CS-4…CS-10 — build vectors (exact text + summary)
    @Test(arguments: ["CS-1", "CS-4", "CS-5", "CS-6", "CS-7", "CS-8", "CS-9", "CS-10"])
    func buildVectors(_ id: String) {
        let v = Self.vector(id)
        let got = Self.build(v)
        if let want = v["out"]?.stringValue {
            #expect(got.map(FlashTestKit.text) == want, "\(id)")
            if let summary = v["summary"]?.stringValue, let got { #expect(FlashChangeSet.summarize(got) == summary, "\(id)") }
        } else {
            #expect(got == nil, "\(id) must be 'nothing to send'")
        }
    }

    // TV: CS-2, CS-3, CS-15 — apply vectors (exact data + settings)
    @Test(arguments: ["CS-2", "CS-3", "CS-15"])
    func applyVectors(_ id: String) {
        let v = Self.vector(id)
        var data = Self.obj(v, "data")!
        var settings = Self.obj(v, "settings")!
        let change = Self.obj(v, "changeSet")!
        FlashChangeSet.applyChangeSet(change, data: &data, settings: &settings, now: Self.now)
        #expect(FlashTestKit.text(data) == v["outData"]!.stringValue!, "\(id)")
        #expect(FlashTestKit.text(settings) == v["outSettings"]!.stringValue!, "\(id)")
        if let s = v["summary"]?.stringValue { #expect(FlashChangeSet.summarize(change) == s) }
    }

    // TV: CS-11 snapshot build
    @Test func snapshotBuild() {
        let v = Self.vector("CS-11")
        let snap = FlashChangeSet.buildSnapshot(data: Self.obj(v, "data")!, settings: Self.obj(v, "settings"))
        #expect(FlashTestKit.text(snap) == v["out"]!.stringValue!)
        #expect(FlashChangeSet.isSnapshotEnvelope(.object(snap)))
        #expect(FlashTestKit.text(FlashChangeSet.buildSnapshot(data: JSONObject(), settings: nil)) == #"{"V":1,"Data":{},"Settings":null}"#)
    }

    // TV: CS-12, CS-13 snapshot apply (envelope and bare data.json)
    @Test(arguments: ["CS-12", "CS-13"])
    func snapshotApply(_ id: String) {
        let v = Self.vector(id)
        var settings = Self.obj(v, "settings")!
        let r = FlashChangeSet.applySnapshot(Self.obj(v, "payload")!, settings: &settings, now: Self.now,
                                             existingData: Self.obj(v, "existing"))
        #expect(FlashTestKit.text(r.data) == v["outData"]!.stringValue!, "\(id)")
        #expect(FlashTestKit.text(settings) == v["outSettings"]!.stringValue!, "\(id)")
        #expect(r.hadSettings == v["hadSettings"]!.boolValue!, "\(id)")
    }

    // TV: CS-14 Reorder edge
    @Test func reorderEdge() throws {
        let v = Self.vector("CS-14")
        guard case .array(let target) = try JSONParser.parse(v["target"]!.stringValue!) else { Issue.record("fixture"); return }
        let order = (v["order"]?.arrayValue ?? []).compactMap(\.stringValue)
        let out = FlashChangeSet.reorder(target, order)
        #expect(try JSONWriter.string(.array(out)) == v["out"]!.stringValue!)
    }

    // TV: CS-16 per-device isolation on apply
    @MainActor @Test func perDeviceKeysAreNeverTouchedOnApply() {
        var data = FlashTestKit.object(#"{"Ui":{"WindowLeft":5,"WindowTop":6,"SelectedTaskId":"x","GroupExpanded":{"a":true},"LastDigestDate":"2026-01-01"}}"#)
        var settings = JSONObject()
        let change = FlashTestKit.object(#"{"UiChanges":{"WindowLeft":999,"SelectedTaskId":"y","GroupExpanded":{},"LastDigestDate":"2027-01-01","TabOrder":["A"]},"UiDeletes":["WindowTop","SortAZ"]}"#)
        FlashChangeSet.applyChangeSet(change, data: &data, settings: &settings, now: Self.now)
        #expect(FlashTestKit.text(data) == #"{"Ui":{"WindowLeft":5,"WindowTop":6,"SelectedTaskId":"x","GroupExpanded":{"a":true},"LastDigestDate":"2026-01-01","TabOrder":["A"]},"LastModified":"2026-09-27T12:00:00.0000000"}"#)
        #expect(FlashChangeSet.perDeviceUiKeys.count == 16)
        let modelKeys = UiState.perDeviceKeyNames
        #expect(FlashChangeSet.perDeviceUiKeys == modelKeys)
    }

    // TV: CS-17 excluded settings on apply (and DECISIONS Q-2: SettingsDeletes filtered too)
    @Test func excludedSettingsAreNeverWrittenOrRemoved() {
        var data = JSONObject()
        var settings = FlashTestKit.object(#"{"PasswordHash":"mine","PasswordSalt":"salt","AppIdentity":"MAC1","CurrentDataFile":"/x","OnlyHere":1,"Foo":2}"#)
        let change = FlashTestKit.object(#"{"Settings":{"PasswordHash":"theirs","AppIdentity":"PC","CurrentDataFile":"C:\\d.json","DarkMode":true,"GeminiApiKey":"k"},"SettingsDeletes":["PasswordHash","PasswordSalt","Foo","EncryptLocalData"]}"#)
        FlashChangeSet.applyChangeSet(change, data: &data, settings: &settings, now: Self.now)
        #expect(FlashTestKit.text(settings) == #"{"PasswordHash":"mine","PasswordSalt":"salt","AppIdentity":"MAC1","CurrentDataFile":"/x","OnlyHere":1,"DarkMode":true}"#)
        #expect(FlashChangeSet.excludedSettingsKeys.count == 11)
    }

    // TV: CS-18 envelope detection
    @Test func envelopeDetection() throws {
        #expect(FlashChangeSet.isSnapshotEnvelope(try JSONParser.parse(#"{"V":1,"Data":{}}"#)))
        #expect(!FlashChangeSet.isSnapshotEnvelope(try JSONParser.parse(#"{"V":null,"Data":{}}"#)))
        #expect(!FlashChangeSet.isSnapshotEnvelope(try JSONParser.parse(#"{"V":1,"Data":[]}"#)))
        #expect(!FlashChangeSet.isSnapshotEnvelope(try JSONParser.parse(#"{"Tasks":[]}"#)))
        #expect(!FlashChangeSet.isSnapshotEnvelope(try JSONParser.parse(#"[1]"#)))
        #expect(!FlashChangeSet.isSnapshotEnvelope(nil))
    }

    // TV: CS-19 deep equality (the change-set decisions use JSONValue.deepEquals — F1's, exercised here)
    @Test func deepEqualsDrivesChangeDetection() throws {
        func eq(_ a: String, _ b: String) throws -> Bool { JSONValue.deepEquals(try JSONParser.parse(a), try JSONParser.parse(b)) }
        #expect(try eq(#"{"a":1,"b":2}"#, #"{"b":2,"a":1}"#))
        #expect(try !eq("[1,2]", "[2,1]"))
        #expect(try !eq(#"{"a":null}"#, "{}"))
        #expect(try eq("\"é\"", #""\u00e9""#))
        #expect(try !eq("\"é\"", #""e\u0301""#))
        #expect(try !eq("1", "1.0"))
        #expect(try !eq(#""1""#, "1"))
        // Key order alone is not a change.
        let base = FlashTestKit.object(#"{"Tasks":[{"Id":"a","N":1,"M":2}]}"#)
        let cur = FlashTestKit.object(#"{"Tasks":[{"M":2,"Id":"a","N":1}]}"#)
        #expect(FlashChangeSet.buildChangeSet(current: cur, baselineData: base, currentSettings: nil, baselineSettings: nil,
                                              from: "Mac", created: Self.now) == nil)
    }

    // TV: Q-1 — a malformed/legacy sender cannot wipe Ui or LastModified through BlockDeletes/Sets/Deletes/Order
    @Test func excludedDataKeysAreSkippedEverywhereOnApply() {
        var data = FlashTestKit.object(#"{"Ui":{"WindowLeft":1,"TabOrder":["X"]},"LastModified":"2026-01-01T00:00:00","Tasks":[]}"#)
        var settings = JSONObject()
        let change = FlashTestKit.object(#"{"Sets":{"Ui":[{"Id":"u"}]},"Deletes":{"Ui":["u"]},"Order":{"Ui":["u"]},"Blocks":{"LastModified":"1999"},"BlockDeletes":["Ui","LastModified","Gone"]}"#)
        FlashChangeSet.applyChangeSet(change, data: &data, settings: &settings, now: Self.now)
        #expect(FlashTestKit.text(data) == #"{"Ui":{"WindowLeft":1,"TabOrder":["X"]},"LastModified":"2026-09-27T12:00:00.0000000","Tasks":[]}"#)
    }

    // TV: Q-3 — a root-level legacy Ui is folded into the merge with the lowest precedence
    @Test func rootLevelLegacyUiIsMerged() {
        var data = FlashTestKit.object(#"{"Ui":{"WindowLeft":7,"SortAZ":{}}}"#)
        var settings = JSONObject()
        let change = FlashTestKit.object(#"{"V":1,"Ui":{"WindowLeft":1,"TabOrder":["Root"],"ShowShortcutBar":false,"CrewSortMode":"Root"},"Blocks":{"Ui":{"TabOrder":["Blocks"],"CrewSortMode":"Blocks"}},"UiChanges":{"CrewSortMode":"Changes"}}"#)
        FlashChangeSet.applyChangeSet(change, data: &data, settings: &settings, now: Self.now)
        #expect(FlashTestKit.text(data) == #"{"Ui":{"WindowLeft":7,"SortAZ":{},"TabOrder":["Blocks"],"ShowShortcutBar":false,"CrewSortMode":"Changes"},"LastModified":"2026-09-27T12:00:00.0000000"}"#)
        #expect(FlashChangeSet.summarize(change) == "Ui, layout")
    }

    // TV: protocol §10 "Diff EVERY key" — unknown collections, Trash, Sire, scalars; Sets+Deletes conflict → deleted
    @Test func structuralDiffOfUnknownKeysAndConflicts() {
        let base = FlashTestKit.object(#"{"Trash":[{"Id":"t1","Payload":{"x":1}}],"Future":[{"Id":"f1","v":1}],"Sire":{"Bookmarks":[]},"SchemaVersion":1}"#)
        let cur = FlashTestKit.object(#"{"Trash":[],"Future":[{"Id":"f1","v":2},{"Id":"f2","Nested":{"WinOnly":true}}],"Sire":{"Bookmarks":["2.1"]},"SchemaVersion":3,"Brand":"new"}"#)
        let cs = FlashChangeSet.buildChangeSet(current: cur, baselineData: base, currentSettings: nil, baselineSettings: nil,
                                               from: "Mac", created: Self.now)!
        #expect(FlashTestKit.text(cs) == #"{"V":1,"From":"Mac","Created":"2026-09-27T12:00:00","Sets":{"Future":[{"Id":"f1","v":2},{"Id":"f2","Nested":{"WinOnly":true}}]},"Deletes":{"Trash":["t1"]},"Blocks":{"Sire":{"Bookmarks":["2.1"]},"SchemaVersion":3,"Brand":"new"}}"#)
        // Applying it to the baseline reproduces the current tree exactly (zero-data-loss transport).
        var data = base
        var settings = JSONObject()
        FlashChangeSet.applyChangeSet(cs, data: &data, settings: &settings, now: Self.now)
        data.removeValue(forKey: "LastModified")
        #expect(JSONValue.deepEquals(.object(data), .object(cur)))
        // An item both set and deleted by a malformed sender ends up deleted.
        var d2 = FlashTestKit.object(#"{"Tasks":[{"Id":"a"},{"Id":"a","dup":true}]}"#)
        FlashChangeSet.applyChangeSet(FlashTestKit.object(#"{"Sets":{"Tasks":[{"Id":"a","v":2}]},"Deletes":{"Tasks":["a"]}}"#),
                                      data: &d2, settings: &settings, now: Self.now)
        #expect(FlashTestKit.text(d2) == #"{"Tasks":[],"LastModified":"2026-09-27T12:00:00.0000000"}"#)
    }

    // TV: VESSEL-284 — Vessels/Ports travel whole per item, and a port reorder sends Order which apply honours
    @Test func vesselsAndPortsTravelWholeWithOrder() {
        let base = FlashTestKit.object(#"{"Vessels":[{"Id":"v1","Name":"ARANDA","QuickCards":[]}],"Ports":[{"Id":"p1","Name":"Bonny"},{"Id":"p2","Name":"Ras Laffan"}]}"#)
        let cur = FlashTestKit.object(#"{"Vessels":[{"Id":"v1","Name":"ARANDA","QuickCards":[{"Id":"q","Title":"Bunkers"}]}],"Ports":[{"Id":"p2","Name":"Ras Laffan"},{"Id":"p1","Name":"Bonny","Visits":[{"Date":"2026-09-01"}]}]}"#)
        let cs = FlashChangeSet.buildChangeSet(current: cur, baselineData: base, currentSettings: nil, baselineSettings: nil,
                                               from: "Mac", created: Self.now)!
        #expect(FlashTestKit.text(cs) == #"{"V":1,"From":"Mac","Created":"2026-09-27T12:00:00","Sets":{"Vessels":[{"Id":"v1","Name":"ARANDA","QuickCards":[{"Id":"q","Title":"Bunkers"}]}],"Ports":[{"Id":"p1","Name":"Bonny","Visits":[{"Date":"2026-09-01"}]}]},"Order":{"Ports":["p2","p1"]}}"#)
        var data = base
        var settings = JSONObject()
        FlashChangeSet.applyChangeSet(cs, data: &data, settings: &settings, now: Self.now)
        data.removeValue(forKey: "LastModified")
        #expect(FlashTestKit.text(data) == FlashTestKit.text(cur))
    }

    // TV: FLASH-093 — summary parts and pluralisation; null BlockDeletes entry shows "?"
    @Test func summaryParts() {
        let cs = FlashTestKit.object(#"{"Sets":{"Tasks":[{"Id":"a"},{"Id":"b"}],"Equipment":[],"Crew":[{"Id":"c"}]},"Deletes":{"Tasks":["x"],"Crew":["y","z"]},"Blocks":{"Log":[],"Sire":{}},"UiDeletes":["TabOrder"],"BlockDeletes":["Old",null],"Settings":{},"SettingsDeletes":["A","B"]}"#)
        #expect(FlashChangeSet.summarize(cs) == "2 Tasks, 1 Crew, 3 deleted, Log, Sire, layout, REMOVES Old, ?, settings, clears 2 settings")
        #expect(FlashChangeSet.summarize(JSONObject()) == "other changes")
    }

    // TV: FLASH-086/087/091 — Ui null values, settings null ≡ removed, snapshot Ui moved to the end
    @Test func uiAndSettingsEdgeCases() {
        // A current Ui key present with null vs a non-null baseline → UiChanges carries null; current-null vs absent → unchanged.
        let cs = FlashChangeSet.buildChangeSet(current: FlashTestKit.object(#"{"Ui":{"CalendarViewMode":null,"X":null}}"#),
                                               baselineData: FlashTestKit.object(#"{"Ui":{"CalendarViewMode":"Month","Gone":1,"WindowTop":3}}"#),
                                               currentSettings: FlashTestKit.object(#"{"DarkMode":true,"Foo":null}"#),
                                               baselineSettings: FlashTestKit.object(#"{"DarkMode":true,"Foo":1}"#),
                                               from: "Mac", created: Self.now)!
        #expect(FlashTestKit.text(cs) == #"{"V":1,"From":"Mac","Created":"2026-09-27T12:00:00","Settings":{"DarkMode":true,"Foo":null},"SettingsDeletes":["Foo"],"UiChanges":{"CalendarViewMode":null},"UiDeletes":["Gone"]}"#)
        // Ui not an object now → no UiChanges, baseline shared keys → UiDeletes.
        let cs2 = FlashChangeSet.buildChangeSet(current: FlashTestKit.object(#"{"Ui":[1]}"#),
                                                baselineData: FlashTestKit.object(#"{"Ui":{"TabOrder":[],"WindowLeft":1}}"#),
                                                currentSettings: nil, baselineSettings: nil, from: "Mac", created: Self.now)!
        #expect(FlashTestKit.text(cs2) == #"{"V":1,"From":"Mac","Created":"2026-09-27T12:00:00","UiDeletes":["TabOrder"]}"#)
    }

    // TV: FLASH-082 — duplicate ids: first occurrence participates; numbers as ids compare by lexeme
    @Test func duplicateAndNumericIds() {
        let base = FlashTestKit.object(#"{"L":[{"Id":1,"v":"a"},{"Id":1,"v":"dup"}]}"#)
        let cur = FlashTestKit.object(#"{"L":[{"Id":1,"v":"b"},{"Id":"1","v":"string id"}]}"#)
        let cs = FlashChangeSet.buildChangeSet(current: cur, baselineData: base, currentSettings: nil, baselineSettings: nil,
                                               from: "Mac", created: Self.now)!
        #expect(FlashTestKit.text(cs) == #"{"V":1,"From":"Mac","Created":"2026-09-27T12:00:00","Sets":{"L":[{"Id":1,"v":"b"}]}}"#)
    }
}
