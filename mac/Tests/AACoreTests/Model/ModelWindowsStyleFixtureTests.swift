// TV: 01 §4 (data compatibility), §4.1.3 (emission order), §4.1.5 (dates, three kinds), §3.20 / A11 (legacy
//     BucketId), DATA-024 / OC-02 (unknown members on every object), §4.10 (Trash payload), ARCHITECTURE.md §10.3
//     (parse → decode → encode → write is byte-identical).
//
// Fixtures (hand-authored in the exact System.Text.Json shape a Windows build writes — compact, PascalCase,
// default JavaScriptEncoder escaping, typed dates with a literal '+', WhenWritingNull, extension data last):
//   model/WIN.windows-style.input.json — every model type populated; Unspecified, Utc ("Z") and Local ("+08:00",
//       "+04:00") dates incl. 1–7 fraction digits; unknown members on 20+ objects at every nesting level (null,
//       1.50, -0, 1e2, 1e-7, nested arrays/objects); four items from an older build carrying the legacy single
//       `BucketId` and no `BucketIds`; an in-place UNC link, a drive-letter folder card, a web link; a Trash entry
//       whose PayloadJson holds a whole task (literal '+' inside, `\u002B` outside); an `enc:` saved-list body;
//       SIRE statuses incl. the numeric form "2"; Ui with an unknown tab name and ordinal dictionary keys.
//   model/WIN.mac-expected.golden.json — the same document with each `BucketId` folded into `BucketIds` (the only
//       normalisation the Mac applies to it).
import Foundation
import Testing
@testable import AACore

@MainActor @Suite struct ModelWindowsStyleFixtureTests {
    static let input = "model/WIN.windows-style.input.json"
    static let expected = "model/WIN.mac-expected.golden.json"
    static let zones = [TZ.athens, TZ.newYork, TZ.kolkata, TZ.utc, TimeZone(identifier: "Asia/Singapore")!]

    func decode(_ bytes: Data, zone: TimeZone) throws -> AppData {
        let ctx = JSONDecodeContext(zone: zone, clock: FixedClock(local: "2026-09-29T14:05:00", zone: zone))
        return try ModelCodec.decodeAppData(try JSONParser.parse(bytes), context: ctx)
    }

    func encode(_ data: AppData, zone: TimeZone) throws -> Data {
        try JSONWriter.data(ModelCodec.encodeAppData(data, options: JSONEncodeOptions(zone: zone)))
    }

    // parse → model → write: the Mac-expected document reproduces itself byte for byte in every zone,
    // through the model codec and through the save pipeline's serializer.
    @Test func roundTripIsByteIdentical() throws {
        let golden = try Fixtures.data(Self.expected)
        for zone in Self.zones {
            #expect(try encode(decode(golden, zone: zone), zone: zone) == golden, "\(zone.identifier)")
        }
        let ds = DataStore(appFolder: TempFolder().url, secrets: InMemorySecretStore(),
                           clock: FixedClock(local: "2026-09-29T14:05:00", zone: TZ.athens))
        let folder = TempFolder()
        try folder.write("data.json", golden)
        #expect(try ds.serializeForSave(ds.loadFrom(folder.file("data.json"))) == golden)
    }

    // The legacy-bucket input converges on the expected document, and a second pass is a fixed point.
    @Test func legacyInputConverges() throws {
        let input = try Fixtures.data(Self.input)
        let golden = try Fixtures.data(Self.expected)
        #expect(input != golden)
        for zone in Self.zones {
            let once = try encode(decode(input, zone: zone), zone: zone)
            #expect(once == golden, "\(zone.identifier)")
            #expect(try encode(decode(once, zone: zone), zone: zone) == once)
        }
        let text = String(decoding: input, as: UTF8.self)
        #expect(text.components(separatedBy: #""BucketId":"#).count - 1 == 4)
        #expect(!String(decoding: golden, as: UTF8.self).contains(#""BucketId":"#))
    }

    // Generic tree check: the typed model writes exactly the members the file has, in the same order, at every
    // level — nothing dropped, nothing added, nothing reordered (stronger diagnostics than a byte compare).
    @Test func treeIsPreservedMemberByMember() throws {
        let golden = try Fixtures.data(Self.expected)
        let original = try JSONParser.parse(golden)
        let written = ModelCodec.encodeAppData(try decode(golden, zone: TZ.newYork), options: JSONEncodeOptions(zone: TZ.newYork))
        var diffs: [String] = []
        func walk(_ a: JSONValue, _ b: JSONValue, _ path: String) {
            switch (a, b) {
            case (.object(let x), .object(let y)):
                if x.keys != y.keys { diffs.append("\(path): keys \(x.keys) ≠ \(y.keys)"); return }
                for k in x.keys { walk(x.rawValue(forKey: k)!, y.rawValue(forKey: k)!, "\(path).\(k)") }
            case (.array(let x), .array(let y)):
                if x.count != y.count { diffs.append("\(path): count \(x.count) ≠ \(y.count)"); return }
                for i in x.indices { walk(x[i], y[i], "\(path)[\(i)]") }
            default:
                if a != b { diffs.append("\(path): \(a) ≠ \(b)") }
            }
        }
        walk(original, written, "$")
        #expect(diffs.isEmpty, "\(diffs.prefix(10))")
    }

    @Test func valuesLandInTheModel() throws {
        let data = try decode(try Fixtures.data(Self.input), zone: TZ.newYork)
        // Every collection populated.
        #expect(data.equipment.count == 1 && data.tasks.count == 2 && data.procedures.count == 1 && data.vessels.count == 1)
        #expect(data.groups.count == 3 && data.crew.count == 1 && data.log.count == 2 && data.checklistTemplates.count == 2)
        #expect(data.listGroups.count == 1 && data.quickBuckets.count == 3 && data.ports.count == 1)
        #expect(data.scheduleTemplates.count == 1 && data.trash.count == 1 && data.sire.tasks.count == 1)

        // Legacy BucketId folded in (not kept as an unknown member).
        let bucket80 = data.quickBuckets[0].id, bucket82 = data.quickBuckets[2].id
        #expect(data.equipment[0].bucketIds == [bucket80] && data.tasks[0].bucketIds == [bucket80])
        #expect(data.procedures[0].bucketIds == [bucket80] && data.vessels[0].bucketIds == [bucket82])
        for item in data.equipment as [HierarchyItem] + data.tasks + data.procedures + data.vessels {
            #expect(!item.extra.containsKey("BucketId"), "\(item.name)")
        }

        // Three date kinds; Local values convert to the reading zone's wall clock, keep their text.
        let t = data.tasks[0]
        #expect(t.deadline?.kind == .unspecified && t.rangeStart?.kind == .local && data.tasks[1].deadline?.kind == .utc)
        #expect(t.rangeStart?.format(.isoMinute) == "2026-10-07 12:00")                 // 00:00+08:00 in New York
        #expect(t.rangeStart?.jsonString(zone: TZ.newYork) == "2026-10-08T00:00:00+08:00")
        #expect(data.lastModified?.originalText == "2026-09-29T14:03:27.1234567+08:00")
        #expect(data.equipment[0].container.files[1].added.jsonString(zone: TZ.utc) == "2026-01-07T08:00:00+04:00")
        #expect(data.trash[0].deletedUtc.ticks % 10_000_000 == 9_999_999)
        #expect(data.sire.tasks[0].createdAt.originalText == "2026-09-27T15:45:12.004+08:00")

        // Status / IsComplete, recursion, enums.
        #expect(t.status == .inProgress && !t.isComplete && t.recurrence == .monthly && t.recurrenceSpawned)
        #expect(data.tasks[1].isComplete && data.tasks[1].status == .done)
        #expect(t.subtasks[0].status == .blocked && t.subtasks[0].subtasks[0].recurrence == .yearly)
        #expect(t.allSubtasksDepthFirst().map(\.name) == ["Drain and clean bowl", "Order spare O-rings"])

        // Unknown members at several levels.
        #expect(data.extra.keys == ["FutureThing", "FutureNull"] && data.ui.extra.keys == ["NewPref"])
        #expect(data.equipment[0].extra.keys == ["EquipmentFuture"])
        #expect(data.equipment[0].components[0].extra.keys == ["ComponentFuture"])
        #expect(data.equipment[0].container.extra.keys == ["ContainerFuture"])
        #expect(data.equipment[0].container.files[2].extra.keys == ["FileFuture"])
        #expect(t.extra.keys == ["TaskFuture", "FutureNull"] && t.subtasks[0].subtasks[0].extra.keys == ["SubtaskFuture"])
        #expect(data.tasks[1].container.extra.keys == ["Rev"])
        #expect(data.procedures[0].steps[1].extra.keys == ["StepFuture"])
        #expect(data.vessels[0].quickCards[1].extra.keys == ["CardFuture"])
        #expect(data.groups[1].extra.keys == ["GroupFuture"])
        #expect(data.crew[0].extra.keys == ["CrewFuture"] && data.crew[0].flags[1].extra.keys == ["FlagFuture"])
        #expect(data.crew[0].schedule[1].extra.keys == ["EntryFuture"])
        #expect(data.log[1].extra.keys == ["LogFuture"] && data.checklistTemplates[0].items[0].extra.keys == ["ItemFuture"])
        #expect(data.listGroups[0].extra.keys == ["ListGroupFuture"] && data.quickBuckets[2].extra.keys == ["BucketFuture"])
        #expect(data.ports[0].visits[1].extra.keys == ["VisitFuture"] && data.trash[0].extra.keys == ["TrashFuture"])
        #expect(data.sire.extra.keys == ["SireFuture"] && data.sire.tasks[0].extra.keys == ["SireTaskFuture"])

        // Paths and links are kept verbatim; locks, crew, SIRE and Ui values.
        let files = data.equipment[0].container.files
        #expect(files.map(\.sourceLabel) == ["Copy", "Live", "Web link"])
        #expect(files[1].path == #"\\BW-SRV01\Engine\PMS\PMS export.xlsx"#)
        #expect(data.vessels[0].quickCards[0].target == #"Z:\Bridge\Passage plans"#)
        #expect(data.vessels[0].isLockProtected && data.vessels[0].lockHint == "ship\u{2019}s usual")
        #expect(!data.vessels[0].notificationsEnabled && data.vessels[0].jobs[0].overdueDays == -12)
        #expect(data.vessels[0].quickCards[1].y == -12.75 && data.vessels[0].quickCards[0].icon == "\u{1F9ED}")
        #expect(data.crew[0].fullName == "Jos\u{E9} Mar\u{ED}a O'Neill" && data.crew[0].scheduleVesselId == data.vessels[0].id)
        #expect(data.crew[0].flags.map(\.severity) == [.warning, .error])
        #expect(data.ports[0].visits[0].vesselId == data.vessels[0].id && data.ports[0].visits[1].vesselId == nil)
        #expect(data.sire.status(for: "3.4.5") == .checked && data.sire.status(for: "4.1.1") == .notApplicable)
        #expect(data.ui.tabOrder.contains("TabFutureThing") && data.ui.groupExpanded.keys.count == 3)
        #expect(data.ui.windowLeft == -1280 && data.ui.calendarFontScale == 13.5 && data.ui.selectedMainTabIndex == 3)
        #expect(data.checklistTemplates[0].items[0].container.richTextXaml.hasPrefix("enc:"))
        #expect(data.checklistTemplates[1].groupId == nil)

        // The Trash payload is an ordinary JSON string; decoded it restores the task with its literal-'+' date.
        let entry = data.trash[0]
        #expect(entry.payloadJson.contains(#""Deadline":"2026-09-01T00:00:00+08:00""#))
        let restored = try #require(TrashPayload.decode(itemType: entry.itemType, payload: entry.payloadJson,
                                                        context: JSONDecodeContext(zone: TZ.newYork)) as? TaskItem)
        #expect(restored.id == entry.itemId && restored.deadline?.originalText == "2026-09-01T00:00:00+08:00")
        #expect(TrashPayload.encode(restored) == entry.payloadJson)
    }
}
