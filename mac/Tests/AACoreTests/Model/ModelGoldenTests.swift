// TV: 01 §4.2.1 fresh-database golden, 01 §7.4 (Task vector, unknown keys, Status sync, legacy BucketId, missing keys,
//     GUID case), 01 App. A04/A05/A07/A08/A10/A11/A16, 01 §3.8 rule 8 (literal '+' in typed dates: source.json B07,
//     a Local date in data.json, the Trash payload case), B08, 06 §7.14 (JSON round trip), 13 CS-19 (ordinal keys),
//     ARCHITECTURE.md §10.3 (round trip of every sample byte-identical).
import Foundation
import Testing
@testable import AACore

@MainActor @Suite struct ModelGoldenTests {
    static let freshDB = Goldens.freshDB

    func context(_ guids: SequentialGuids = SequentialGuids(), zone: TimeZone = TZ.athens) -> JSONDecodeContext {
        JSONDecodeContext(zone: zone, clock: FixedClock(local: "2026-09-29T14:05:00", zone: zone), newGuid: { guids.next() })
    }

    func encode(_ m: some JSONModel, zone: TimeZone = TZ.athens) throws -> String {
        try JSONWriter.string(.object(m.toJSON(options: JSONEncodeOptions(zone: zone))))
    }

    func object(_ text: String) throws -> JSONObject { try #require(try JSONParser.parse(text).objectValue) }

    // TV: 01 §4.2.1 / §7.4 / App. A01
    @Test func freshDatabaseGolden() throws {
        let data = AppData()
        data.schemaVersion = 1
        #expect(try encode(data) == Self.freshDB)
        #expect(try Fixtures.string("json/A01.appdata.golden.json") == Self.freshDB)
        let folder = TempFolder()
        let ds = DataStore(appFolder: folder.url, secrets: InMemorySecretStore())
        let bytes = try ds.serializeForSave(AppData())
        #expect(String(decoding: bytes, as: UTF8.self) == Self.freshDB)
    }

    // TV: 01 §7.4 Task vector (normative values)
    @Test func taskVector() throws {
        let t = TaskItem(id: UUID(netString: "3f2504e0-4f89-11d3-9a0c-0305e82c3301")!, name: "Fire drill")
        t.deadline = NetDateTime.calendarDate(CivilDate(year: 2026, month: 10, day: 1)!)
        t.recurrence = .monthly
        t.status = .inProgress
        t.tags = ["safety"]
        t.container = Container(id: UUID(netString: "11111111-2222-3333-4444-555555555555")!)
        #expect(try encode(t) == #"{"Deadline":"2026-10-01T00:00:00","IsJob":false,"DurationMinutes":60,"Recurrence":3,"RecurrenceSpawned":false,"IsComplete":false,"Status":1,"Subtasks":[],"Id":"3f2504e0-4f89-11d3-9a0c-0305e82c3301","Name":"Fire drill","Description":"","Container":{"Id":"11111111-2222-3333-4444-555555555555","RichTextXaml":"","Files":[],"SharedWithContainerIds":[],"IsLocked":false},"RelatedIds":[],"Tags":["safety"],"BucketIds":[]}"#)
    }

    // TV: ARCHITECTURE.md §10.3 — parse → decode → encode → write is byte-identical for the kitchen sink
    @Test func kitchenSinkRoundTripIsByteIdentical() throws {
        let input = try Fixtures.data("model/KS.sample-data.json")
        for zone in [TZ.athens, TZ.newYork, TZ.kolkata, TZ.utc] {
            let root = try JSONParser.parse(input)
            let data = try ModelCodec.decodeAppData(root, context: context(zone: zone))
            let out = try JSONWriter.data(ModelCodec.encodeAppData(data, options: JSONEncodeOptions(zone: zone)))
            #expect(out == input, "zone \(zone.identifier)")
        }
        // …and through the save serializer (SchemaVersion already 1, paths already relative).
        let folder = TempFolder()
        let ds = DataStore(appFolder: folder.url, secrets: InMemorySecretStore(), clock: FixedClock(local: "2026-09-29T14:05:00", zone: TZ.athens))
        let data = try ModelCodec.decodeAppData(try JSONParser.parse(input), context: context())
        #expect(try ds.serializeForSave(data) == input)
    }

    @Test func kitchenSinkValues() throws {
        let data = try ModelCodec.decodeAppData(try JSONParser.parse(Fixtures.data("model/KS.sample-data.json")), context: context())
        let e = try #require(data.equipment.first)
        #expect(e.name == "Main Engine \u{2192} \u{2693} <ME>")
        #expect(e.isLockProtected && e.lockHint == "the usual")
        #expect(e.components.first?.container.files.first?.kind == .image)
        #expect(e.container.files.map(\.sourceLabel) == ["Copy", "Live", "Live", "Web link", "Copy"])
        #expect(e.container.extra.keys == ["ContainerFuture"])
        #expect(e.container.files[0].extra["FileFuture"] != nil)
        let t = try #require(data.tasks.first)
        #expect(t.isComplete && t.status == .done && t.recurrence == .monthly)
        #expect(t.subtasks.first?.status == .blocked)
        #expect(t.subtasks.first?.subtasks.first?.recurrence == .yearly)
        #expect(t.extra.keys == ["TaskFuture", "FutureNull"])
        #expect(t.rangeStart?.kind == .local && t.deadline?.kind == .unspecified)
        #expect(data.vessels.first?.notificationsEnabled == false)
        #expect(data.vessels.first?.quickCards.first?.x == 12.5)
        #expect(data.vessels.first?.jobs.first?.overdueDays == -3)
        #expect(data.crew.first?.fullName == "Jos\u{E9} Mar\u{ED}a \u{3A9}mega")
        #expect(data.crew.first?.flags.map(\.severity) == [.info, .warning, .error])
        #expect(data.crew.first?.schedule.compactMap(\.refId).count == 3)
        #expect(data.ports.first?.visits.count == 2 && data.ports.first?.visits[1].vesselId == nil)
        #expect(data.trash.first?.batchId == G(27))
        #expect(data.sire.status(for: "2.1.1") == .checked)
        #expect(data.sire.extra.keys == ["SireFuture"])
        #expect(data.ui.tabOrder == ["TabTasks", "TabFuture", "TabEquipment"])
        #expect(data.ui.groupExpanded.count == 3)                                  // Café NFC and NFD both kept
        #expect(data.ui.extra.keys == ["NewPref"])
        #expect(data.extra.keys == ["FutureThing", "FutureNull"])
        #expect(data.lastModified?.jsonString(zone: TZ.newYork) == "2026-09-29T11:15:29.9876543+03:00")
        #expect(data.checklistTemplates.map(\.name) == ["Pre-arrival", "Orphan"])  // array order kept (06 §7.14)
        #expect(data.checklistTemplates[1].groupId == G(99))                        // dangling id kept
        #expect(data.checklistTemplates[0].items[0].container.richTextXaml.hasPrefix("enc:"))
    }

    // TV: 01 §3.8 rule 8 / App. B07 — source.json literal byte-exact
    @Test func bundleSourceGolden() throws {
        let literal = #"{"Identity":"Vessel-Alpha","Machine":"BRIDGE-PC","WrittenUtc":"2026-09-29T08:15:30.1234567Z","LastModified":"2026-09-29T11:15:29.9876543+03:00","DataOnly":false}"#
        let s = try BundleSource(json: try object(literal), context: context())
        #expect(try JSONWriter.string(.object(s.toJSON())) == literal)
        // Built from values (no original text) in Athens:
        let built = BundleSource(identity: "Vessel-Alpha", machine: "BRIDGE-PC",
                                 writtenUtc: NetDateTime(year: 2026, month: 9, day: 29, hour: 8, minute: 15, second: 30,
                                                         fractionTicks: 1_234_567, kind: .utc),
                                 lastModified: NetDateTime(year: 2026, month: 9, day: 29, hour: 11, minute: 15, second: 29,
                                                           fractionTicks: 9_876_543, kind: .local))
        #expect(try JSONWriter.string(.object(built.toJSON(options: JSONEncodeOptions(zone: TZ.athens)))) == literal)
    }

    // TV: 01 App. B08 — defaults
    @Test func bundleSourceDefaults() throws {
        let s = BundleSource()
        #expect(try JSONWriter.string(.object(s.toJSON())) == #"{"Identity":"","Machine":"","WrittenUtc":"0001-01-01T00:00:00","DataOnly":false}"#)
        #expect(s.writtenLocal == "")
        let decoded = try BundleSource(json: try object("{}"), context: context())
        #expect(decoded == s)
        #expect(throws: JSONModelError.self) { try BundleSource(json: try object(#"{"DataOnly":"true"}"#), context: context()) }
        let stamped = BundleSource(writtenUtc: NetDateTime(year: 2026, month: 9, day: 29, hour: 8, minute: 15, kind: .utc))
        #expect(stamped.writtenLocal.count == 16)
    }

    // TV: 01 §3.8 rule 8 — a Local date inside a data.json object keeps a literal '+'
    @Test func localDateLiteralPlus() throws {
        let f = FileItem(id: G(1), name: "a", path: "files/x_a", added: NetDateTime(year: 2026, month: 9, day: 29, hour: 11, kind: .local))
        let s = try encode(f)
        #expect(s.contains(#""Added":"2026-09-29T11:00:00+03:00""#))
        #expect(!s.contains("\\u002B"))
    }

    // TV: 01 §3.8 rule 8 — the Trash payload case: inner literal '+', outer escaped form
    @Test func trashPayloadEscaping() throws {
        let v = Vessel(id: G(26), name: "Beta")
        v.container = Container(id: G(126))
        v.container.files = [FileItem(id: G(2), name: "f", added: NetDateTime(year: 2026, month: 9, day: 29, hour: 11, kind: .local))]
        let payload = TrashPayload.encode(v)
        // The payload is written in the machine zone (TrashPayload has no zone parameter): build the expected text.
        let stamp = NetDateTime(year: 2026, month: 9, day: 29, hour: 11, kind: .local).jsonString()
        #expect(stamp.count == 25)                                               // always "+hh:mm" or "-hh:mm"
        #expect(payload.contains(#""Added":"\#(stamp)""#))                       // literal sign inside the payload
        let entry = TrashedItem(id: G(25), itemType: "Vessel", itemId: G(26), name: "Beta", kindLabel: "Vessel",
                                deletedUtc: NetDateTime(year: 2026, month: 9, day: 29, hour: 8, kind: .utc), payloadJson: payload)
        let outer = try encode(entry)
        // …and the outer PayloadJson string is an ordinary escaped string, so '"' and '+' are \uXXXX escapes there.
        #expect(outer.contains(JSONWriter.escape(#""Added":"\#(stamp)""#).dropFirst().dropLast()))   // escape() adds the quotes
        #expect(!stamp.contains("+") || outer.contains("\\u002B"))
        let back = try TrashedItem(json: try object(outer), context: context())
        #expect(back.payloadJson == payload)
        let restored = try #require(TrashPayload.decode(itemType: back.itemType, payload: back.payloadJson, context: context()) as? Vessel)
        #expect(restored.id == G(26) && restored.container.files.count == 1)
    }

    // TV: 01 §7.4 unknown keys (top level + Ui) and App. A10 (nested, null / 1.50 / -0 / 1e2 kept verbatim)
    @Test func unknownMembersRoundTrip() throws {
        let input = #"{"Tasks":[],"FutureThing":{"a":[1,2]},"Ui":{"NewPref":true}}"#
        let data = try ModelCodec.decodeAppData(try JSONParser.parse(input), context: context())
        data.schemaVersion = 1
        let out = try encode(data)
        #expect(out.hasSuffix(#""SchemaVersion":1,"FutureThing":{"a":[1,2]}}"#))
        #expect(out.contains(#""CrewTableShownColumns":[],"NewPref":true}"#))
        let nested = #"{"Id":"00000000-0000-0000-0000-000000000001","Name":"","Path":"","Kind":0,"Added":"2026-01-01T00:00:00","IsLink":false,"LinkInPlace":false,"LinkedItemIds":[],"x":null,"n":1.50,"z":-0,"e":1e2,"id":"lower-case is unknown"}"#
        let f = try FileItem(json: try object(nested), context: context())
        #expect(try encode(f) == nested)
        #expect(f.extra.keys == ["x", "n", "z", "e", "id"])
    }

    // TV: 01 §7.4 Status sync on read / App. A16 (order-independent Mac rule)
    @Test(arguments: [
        (#"{"IsComplete":true}"#, 3, true), (#"{"Status":3}"#, 3, true), (#"{"IsComplete":true,"Status":0}"#, 0, false),
        (#"{"Status":0,"IsComplete":true}"#, 0, false), (#"{"IsComplete":false}"#, 0, false), (#"{"Status":2}"#, 2, false),
        (#"{"IsComplete":true,"Status":1}"#, 1, false), (#"{"IsComplete":false,"Status":3}"#, 3, true), ("{}", 0, false),
    ] as [(String, Int, Bool)])
    func statusLoadRule(_ json: String, _ status: Int, _ complete: Bool) throws {
        let t = try TaskItem(json: try object(json), context: context())
        #expect(t.status.rawValue == status)
        #expect(t.isComplete == complete)
    }

    // TV: 01 §7.4 legacy bucket, App. A11
    @Test func legacyBucketId() throws {
        let g = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", h = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        let a = try TaskItem(json: try object(#"{"BucketId":"\#(g)"}"#), context: context())
        #expect(a.bucketIds == [UUID(netString: g)!])
        #expect(!(try encode(a)).contains("BucketId\""))
        #expect(a.extra.isEmpty)
        let b = try TaskItem(json: try object(#"{"BucketIds":["\#(g)"],"BucketId":"\#(g)"}"#), context: context())
        #expect(b.bucketIds.count == 1)
        let c = try TaskItem(json: try object(#"{"BucketId":"\#(g)","BucketIds":["\#(h)"]}"#), context: context())
        #expect(c.bucketIds == [UUID(netString: h)!, UUID(netString: g)!])       // Mac: legacy appended regardless of order
        let d = try TaskItem(json: try object(#"{"BucketId":null}"#), context: context())
        #expect(d.bucketIds.isEmpty)
        for type in [Equipment.self, Procedure.self, Vessel.self] as [HierarchyItem.Type] {
            let item = try type.init(json: try object(#"{"BucketId":"\#(g)"}"#), context: context())
            #expect(item.bucketIds == [UUID(netString: g)!])
        }
        #expect(throws: JSONModelError.self) { try TaskItem(json: try object(#"{"BucketId":"not-a-guid"}"#), context: context()) }
        #expect(throws: JSONModelError.self) { try TaskItem(json: try object(#"{"BucketId":5}"#), context: context()) }
        let step = try ChecklistStep(json: try object(#"{"BucketId":"\#(g)"}"#), context: context())
        #expect(step.bucketIds.isEmpty && step.extra.keys == ["BucketId"])      // no such property: kept as unknown
    }

    // TV: 01 App. A07 — value-type null and type mismatches
    @Test func typeRules() throws {
        let ok = try TaskItem(json: try object(#"{"IsJob":null,"DurationMinutes":null,"Id":null,"Recurrence":7}"#), context: context())
        #expect(!ok.isJob && ok.durationMinutes == 60 && ok.recurrence.rawValue == 7)
        #expect(try encode(ok).contains(#""Recurrence":7"#))
        let f = try FileItem(json: try object(#"{"Added":null}"#), context: context())
        #expect(f.added.jsonString(zone: TZ.athens) == "2026-09-29T14:05:00+03:00")
        for bad in [#"{"Status":"Done"}"#, #"{"DurationMinutes":"60"}"#, #"{"DurationMinutes":60.0}"#,
                    #"{"DurationMinutes":6E1}"#, #"{"Name":5}"#, #"{"IsJob":1}"#, #"{"DurationMinutes":2147483648}"#,
                    #"{"Deadline":"2026-10-01 00:00:00"}"#, #"{"Subtasks":{}}"#, #"{"Container":[]}"#, #"{"Tags":"x"}"#] {
            #expect(throws: JSONModelError.self, "\(bad)") { try TaskItem(json: try object(bad), context: context()) }
        }
        #expect(throws: JSONModelError.self) {
            try UiState(json: try object(#"{"SelectedMainTabIndex":2147483648}"#), context: context())
        }
        let nullRefs = try TaskItem(json: try object(#"{"Name":null,"Tags":null,"Container":null,"Subtasks":[null]}"#), context: context())
        #expect(nullRefs.name == "" && nullRefs.tags.isEmpty && nullRefs.subtasks.isEmpty)
    }

    // TV: 01 §7.4 GUID read / App. A08
    @Test func guidForms() throws {
        let upper = try FileItem(json: try object(#"{"Id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301"}"#), context: context())
        #expect(try encode(upper).hasPrefix(#"{"Id":"3f2504e0-4f89-11d3-9a0c-0305e82c3301""#))
        for bad in ["{3f2504e0-4f89-11d3-9a0c-0305e82c3301}", "3f2504e04f8911d39a0c0305e82c3301",
                    "(3f2504e0-4f89-11d3-9a0c-0305e82c3301)", "3f2504e0-4f89-11d3-9a0c-0305e82c330"] {
            #expect(throws: JSONModelError.self) { try FileItem(json: try self.object(#"{"Id":"\#(bad)"}"#), context: self.context()) }
        }
        let empty = try TrashedItem(json: try object(#"{"ItemId":"00000000-0000-0000-0000-000000000000"}"#), context: context())
        #expect(empty.itemId == .netEmpty)
        #expect(UUID.netEmpty.netString == "00000000-0000-0000-0000-000000000000")
        #expect(G(255).netN == "000000000000000000000000000000ff")
    }

    // TV: 01 §7.4 missing keys / App. A04–A05 defaults
    @Test func missingKeyDefaults() throws {
        let guids = SequentialGuids()
        let t = try TaskItem(json: try object("{}"), context: context(guids))
        #expect(try encode(t) == #"{"IsJob":false,"DurationMinutes":60,"Recurrence":0,"RecurrenceSpawned":false,"IsComplete":false,"Status":0,"Subtasks":[],"Id":"00000000-0000-0000-0000-000000000001","Name":"","Description":"","Container":{"Id":"00000000-0000-0000-0000-000000000002","RichTextXaml":"","Files":[],"SharedWithContainerIds":[],"IsLocked":false},"RelatedIds":[],"Tags":[],"BucketIds":[]}"#)
        let q = try QuickCard(json: try object("{}"), context: context(SequentialGuids()))
        #expect(q.icon == "\u{2693}" && q.color == "#FF1E88E5" && q.x == 24 && q.y == 24 && q.width == 180 && q.height == 120)
        #expect(try encode(q) == ##"{"Id":"00000000-0000-0000-0000-000000000001","Title":"","Target":"","IsLink":false,"LinkInPlace":false,"IsFolder":false,"Icon":"\u2693","Color":"#FF1E88E5","X":24,"Y":24,"Width":180,"Height":120}"##)
        #expect(try Vessel(json: try object("{}"), context: context()).notificationsEnabled)
        let crew = try CrewMember(json: try object("{}"), context: context())
        #expect(crew.userType == "Crew" && crew.signedOnOff == "On")
        #expect(try UiState(json: try object("{}"), context: context()).showShortcutBar)
        #expect(try ItemGroup(json: try object("{}"), context: context()).expanded)
        #expect(try ChecklistTemplateItem(json: try object("{}"), context: context()).durationMinutes == 60)
        let tpl = try ChecklistTemplate(json: try object("{}"), context: context())
        #expect(tpl.createdUtc.jsonString() == "2026-09-29T11:05:00Z")
        let trash = try TrashedItem(json: try object("{}"), context: context(SequentialGuids()))
        #expect(try encode(trash) == #"{"Id":"00000000-0000-0000-0000-000000000001","ItemType":"","ItemId":"00000000-0000-0000-0000-000000000000","BatchId":"00000000-0000-0000-0000-000000000000","Name":"","KindLabel":"","DeletedUtc":"2026-09-29T11:05:00Z","PayloadJson":""}"#)
        let log = try LogEntry(json: try object("{}"), context: context())
        #expect(try encode(log) == #"{"TimestampUtc":"2026-09-29T11:05:00Z","Action":"","Kind":"","Name":"","Detail":""}"#)
        let sireTask = try SireTask(json: try object("{}"), context: context())
        #expect(sireTask.createdAt.jsonString(zone: TZ.athens) == "2026-09-29T14:05:00+03:00")
        #expect(try encode(SireState()) == #"{"QuestionStatuses":{},"Bookmarks":[],"ForExport":[],"Tasks":[],"QuestionBodies":{}}"#)
        let entry = try ScheduleEntry(json: try object("{}"), context: context(SequentialGuids()))
        #expect(try encode(entry) == #"{"Id":"00000000-0000-0000-0000-000000000001","Title":"","Kind":0,"Date":"","Time":"","EndDate":"","EndTime":"","Done":false,"Notes":""}"#)
        #expect(try JSONWriter.string(.object(entry.toJSON(options: .aasched))) == #"{"Id":"00000000-0000-0000-0000-000000000001","Title":"","Kind":0,"RefId":null,"Date":"","Time":"","EndDate":"","EndTime":"","Done":false,"Notes":""}"#)
    }

    // Emission order = jsonKeys for fully populated instances of every type (01 §4.1.3).
    @Test func emissionOrderMatchesKeyLists() throws {
        let data = try ModelCodec.decodeAppData(try JSONParser.parse(Fixtures.data("model/KS.sample-data.json")), context: context())
        func keys(_ m: some JSONModel) -> [String] { m.toJSON(options: .dataFile).keys }
        func known(_ k: [String], _ list: [String]) -> [String] { k.filter { list.contains($0) } }
        #expect(known(keys(data), AppData.jsonKeys) == AppData.jsonKeys)
        #expect(keys(data.equipment[0]).prefix(Equipment.jsonKeys.count).elementsEqual(Equipment.jsonKeys))
        // Omit-nil keys absent from the sample keep the relative order of the rest.
        #expect(known(keys(data.tasks[0]), TaskItem.jsonKeys) == TaskItem.jsonKeys.filter { keys(data.tasks[0]).contains($0) })
        #expect(TaskItem.jsonKeys == ["Deadline", "RangeStart", "IsJob", "DurationMinutes", "ScheduledStart", "Recurrence",
                                      "RecurrenceSpawned", "IsComplete", "Status", "Subtasks", "Id", "Name", "Description",
                                      "Container", "RelatedIds", "Tags", "GroupId", "BucketIds", "LockHash", "LockSalt",
                                      "LockHint"])
        #expect(keys(data.procedures[0]) == Procedure.jsonKeys.filter { $0 != "LockHash" && $0 != "LockSalt" && $0 != "LockHint" })
        #expect(keys(data.vessels[0]) == Vessel.jsonKeys.filter { !["GroupId", "LockHash", "LockSalt", "LockHint"].contains($0) })
        #expect(keys(data.vessels[0].quickCards[0]) == QuickCard.jsonKeys)
        #expect(keys(data.vessels[0].jobs[0]) == ShipJob.jsonKeys)
        #expect(keys(data.vessels[0].portCalls[0]) == PortCall.jsonKeys)
        #expect(keys(data.ports[0]) == PortRecord.jsonKeys)
        #expect(keys(data.ports[0].visits[0]) == PortVisit.jsonKeys)
        #expect(keys(data.crew[0]) == CrewMember.jsonKeys)
        #expect(keys(data.crew[0].flags[0]) == CrewReviewFlag.jsonKeys)
        #expect(keys(data.procedures[0].steps[0]) == ChecklistStep.jsonKeys)
        #expect(keys(data.checklistTemplates[0]) == ChecklistTemplate.jsonKeys)
        #expect(keys(data.checklistTemplates[0].items[0]) == ChecklistTemplateItem.jsonKeys)
        #expect(keys(data.listGroups[0]) == ListGroup.jsonKeys)
        #expect(keys(data.quickBuckets[0]) == QuickBucket.jsonKeys)
        #expect(keys(data.scheduleTemplates[0]) == ScheduleTemplate.jsonKeys)
        #expect(keys(data.trash[0]) == TrashedItem.jsonKeys)
        #expect(keys(data.log[0]) == LogEntry.jsonKeys)
        #expect(known(keys(data.sire), SireState.jsonKeys) == SireState.jsonKeys)
        #expect(keys(data.sire.tasks[0]) == SireTask.jsonKeys)
        #expect(known(keys(data.ui), UiState.jsonKeys) == UiState.jsonKeys)
        #expect(keys(data.groups[0]) == ItemGroup.jsonKeys)
        #expect(keys(data.equipment[0].components[0]) == Component.jsonKeys)
        #expect(known(keys(data.equipment[0].container), Container.jsonKeys) == Container.jsonKeys)
        #expect(known(keys(data.equipment[0].container.files[0]), FileItem.jsonKeys) == FileItem.jsonKeys)
        #expect(CrewMember.jsonKeys.count == 44)                     // FullName/Key are [JsonIgnore]
        #expect(UiState.jsonKeys.count == 28 && UiState.perDeviceKeyNames.count == 16)
    }

    // TV: 13 CS-19 — ordinal dictionary keys survive a model round trip
    @Test func ordinalGroupExpandedKeys() throws {
        let ui = try UiState(json: try object(#"{"GroupExpanded":{"Task|Café":true,"Task|Café":false}}"#), context: context())
        #expect(ui.groupExpanded.count == 2)
        #expect(try encode(ui).contains(#""GroupExpanded":{"Task|Caf\u00E9":true,"Task|Cafe\u0301":false}"#))
    }

    // TV: 06 §7.14 — templates keep order, dangling group ids, SortAZ.savedlists and a literal +02:00 step deadline;
    //     GroupId null is never written; an enc: body round-trips byte-identical
    @Test func savedListsRoundTrip() throws {
        let input = #"{"Procedures":[{"Steps":[{"Id":"00000000-0000-0000-0000-000000000007","Title":"s","BucketIds":[],"Done":false,"Deadline":"2026-09-28T00:00:00+02:00","IsJob":false,"DurationMinutes":60,"TaskIds":[],"EquipmentIds":[],"Container":{"Id":"00000000-0000-0000-0000-000000000008","RichTextXaml":"","Files":[],"SharedWithContainerIds":[],"IsLocked":false}}],"Recurrence":0,"RecurrenceSpawned":false,"Status":0,"IsJob":false,"DurationMinutes":60,"Id":"00000000-0000-0000-0000-000000000004","Name":"p","Description":"","Container":{"Id":"00000000-0000-0000-0000-000000000009","RichTextXaml":"","Files":[],"SharedWithContainerIds":[],"IsLocked":false},"RelatedIds":[],"Tags":[],"BucketIds":[]}],"ChecklistTemplates":[{"Id":"00000000-0000-0000-0000-000000000002","Name":"Zeta","Items":[{"Title":"a","DurationMinutes":60,"IsJob":false,"Container":{"Id":"00000000-0000-0000-0000-000000000003","RichTextXaml":"enc:EBESExQVFhcYGRobHB0eHxJkbpvR5sxlvHs4LU1Zlc/8FgD7jQznyIZndaufj6DG8Ti6ErBbvtnRWs5/oiOkMApZpCT7lzAUZnjCNe73CmY=","Files":[],"SharedWithContainerIds":[],"IsLocked":true}}],"CreatedUtc":"2026-09-29T08:15:30Z","GroupId":"00000000-0000-0000-0000-000000000063"},{"Id":"00000000-0000-0000-0000-000000000001","Name":"Alpha","Items":[],"CreatedUtc":"2026-09-29T08:15:30Z","GroupId":null}],"Ui":{"SortAZ":{"savedlists":true}}}"#
        let data = try ModelCodec.decodeAppData(try JSONParser.parse(input), context: context(zone: TZ.newYork))
        let out = try encode(data, zone: TZ.newYork)
        #expect(out.contains(#""Deadline":"2026-09-28T00:00:00+02:00""#))
        #expect(data.checklistTemplates.map(\.name) == ["Zeta", "Alpha"])
        #expect(out.contains(#""GroupId":"00000000-0000-0000-0000-000000000063""#))
        #expect(!out.contains(#""GroupId":null"#))
        #expect(out.contains(#""SortAZ":{"savedlists":true}"#))
        #expect(out.contains(#""RichTextXaml":"enc:EBESExQVFhcYGRobHB0eHxJkbpvR5sxlvHs4LU1Zlc/8FgD7jQznyIZndaufj6DG8Ti6ErBbvtnRWs5/oiOkMApZpCT7lzAUZnjCNe73CmY=""#))
    }

    // TV: 01 §4.1.9 / §7.4 depth: 7 + 2n for n subtask levels with a file's LinkedItemIds; n = 28 ok, n = 29 refused
    @Test func depthLimitOnSave() throws {
        func chain(_ n: Int) -> AppData {
            let data = AppData()
            let top = TaskItem(name: "0")
            data.tasks = [top]
            var cur = top
            for i in 1...n { let s = TaskItem(name: "\(i)"); cur.subtasks = [s]; cur = s }
            cur.container.files = [FileItem(name: "f", linkedItemIds: [G(1)])]
            return data
        }
        let ds = DataStore(appFolder: TempFolder().url, secrets: InMemorySecretStore())
        #expect(throws: Never.self) { _ = try ds.serializeForSave(chain(28)) }
        #expect(throws: AppStoreError.serialization("The structure is too deep to save.")) { _ = try ds.serializeForSave(chain(29)) }
    }

    // TV: ARCHITECTURE.md §3.8 rule 2 — an Int32 overflow is clamped, recorded, and fails the save
    @Test func int32OverflowFailsTheSave() throws {
        let data = AppData()
        let t = TaskItem(name: "x")
        t.durationMinutes = Int(Int32.max) + 1
        data.tasks = [t]
        let log = JSONEncodeIssueLog()
        let obj = t.toJSON(options: JSONEncodeOptions(issueLog: log))
        #expect(obj["DurationMinutes"] == .number(JSONNumber(2_147_483_647)))
        #expect(log.issues == ["DurationMinutes: 2147483648 is outside Int32"])
        let ds = DataStore(appFolder: TempFolder().url, secrets: InMemorySecretStore())
        #expect(throws: AppStoreError.self) { _ = try ds.serializeForSave(data) }
    }

    // TV: ARCHITECTURE.md §3.10 — decoder root rules (01 A19)
    @Test func rootRules() throws {
        #expect(try ModelCodec.decodeAppData(.null, context: context()).tasks.isEmpty)
        #expect(throws: JSONModelError.notAnObject(path: "")) { try ModelCodec.decodeAppData(.array([]), context: context()) }
        #expect(throws: JSONModelError.self) { try ModelCodec.decodeAppData(.string("x"), context: context()) }
    }
}
