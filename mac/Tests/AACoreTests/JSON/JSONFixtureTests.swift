// TV: ARCHITECTURE.md §10.3 (round trip of every Fixtures/json sample byte-identical), 01 App. A01 (fresh database),
//     A04 (which defaults are written), A10 (unknown members incl. raw number lexemes, duplicate keys, nested
//     unknowns — Mac superset expectation), DATA-024, OC-02.
import Foundation
import Testing
@testable import AACore

@MainActor @Suite struct JSONFixtureTests {
    static let zone = TZ.athens
    func context() -> JSONDecodeContext {
        let guids = SequentialGuids()
        return JSONDecodeContext(zone: Self.zone, clock: FixedClock(local: "2026-09-29T14:05:00", zone: Self.zone),
                                 newGuid: { guids.next() })
    }

    /// Every `json/*.golden.json` is an AppData document whose values need no normalisation.
    nonisolated static var goldenNames: [String] {
        let dir = Fixtures.url("json")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasSuffix(".golden.json") }.sorted()
    }

    @Test func goldensExist() {
        #expect(Self.goldenNames == ["A01.appdata.golden.json", "A04.defaults.golden.json", "A10.mac-expected.golden.json"])
    }

    // TV: ARCHITECTURE.md §10.3 — parse → decode → encode → write is byte-identical (also via serializeForSave)
    @Test(arguments: JSONFixtureTests.goldenNames)
    func roundTrip(_ name: String) throws {
        let bytes = try Fixtures.data("json/\(name)")
        for zone in [TZ.athens, TZ.newYork, TZ.kolkata, TZ.utc] {
            let ctx = JSONDecodeContext(zone: zone, clock: FixedClock(local: "2026-09-29T14:05:00", zone: zone))
            let data = try ModelCodec.decodeAppData(try JSONParser.parse(bytes), context: ctx)
            #expect(try JSONWriter.data(ModelCodec.encodeAppData(data, options: JSONEncodeOptions(zone: zone))) == bytes,
                    "\(name) in \(zone.identifier)")
        }
        let ds = DataStore(appFolder: TempFolder().url, secrets: InMemorySecretStore(), clock: FixedClock(local: "2026-09-29T14:05:00", zone: Self.zone))
        let folder = TempFolder()
        try folder.write("data.json", bytes)
        let loaded = try ds.loadFrom(folder.file("data.json"))
        #expect(try ds.serializeForSave(loaded) == bytes, "\(name) via DataStore")
    }

    // TV: 01 App. A10 — Mac superset: top-level, Ui, nested (Tasks[0], Container, Files[0], Sire) unknowns kept
    // verbatim (null / 1.50 / -0 / 1e2 / 1.0), duplicate keys → first position with the last value, string escapes
    // normalised, insignificant white space dropped, lower-case "tasks" and "id" are unknown keys.
    @Test func a10UnknownMembers() throws {
        let input = try Fixtures.data("json/A10.input.json")
        let data = try ModelCodec.decodeAppData(try JSONParser.parse(input), context: context())
        #expect(data.extra.keys == ["FutureThing", "FutureNull", "X", "tasks"])
        #expect(data.tasks.first?.extra.keys == ["TaskFuture", "id"])
        let ds = DataStore(appFolder: TempFolder().url, secrets: InMemorySecretStore(), clock: FixedClock(local: "2026-09-29T14:05:00", zone: Self.zone))
        let out = try ds.serializeForSave(data)
        #expect(String(decoding: out, as: UTF8.self) == (try Fixtures.string("json/A10.mac-expected.golden.json")))
    }

    // TV: 01 App. A04 — one instance of every type with only ids/dates fixed → the defaults that are written
    @Test func a04Defaults() throws {
        let data = Self.a04()
        let ds = DataStore(appFolder: TempFolder().url, secrets: InMemorySecretStore(), clock: FixedClock(local: "2026-09-29T14:05:00", zone: Self.zone))
        let text = String(decoding: try ds.serializeForSave(data), as: UTF8.self)
        #expect(text == (try Fixtures.string("json/A04.defaults.golden.json")))
        for needle in [#""DurationMinutes":60"#, #""NotificationsEnabled":true"#, #""Icon":"\u2693""#, ##""Color":"#FF1E88E5""##,
                       #""X":24,"Y":24,"Width":180,"Height":120"#, #""Expanded":true"#, #""UserType":"Crew""#,
                       #""SignedOnOff":"On""#, #""ItemId":"00000000-0000-0000-0000-000000000000""#,
                       #""BatchId":"00000000-0000-0000-0000-000000000000""#] {
            #expect(text.contains(needle), "\(needle)")
        }
        for absent in ["BucketId\"", "\"GroupId\"", "LockHash", "\"Deadline\"", "\"RefId\"", "\"VesselId\"",
                       "\"LastModified\"", "null"] {
            #expect(!text.contains(absent), "\(absent)")
        }
    }

    static func a04() -> AppData {
        let d = AppData()
        let stampU = NetDateTime(year: 2026, month: 9, day: 29, hour: 8, minute: 15, second: 30, kind: .utc)
        let stampL = NetDateTime(year: 2026, month: 9, day: 29, hour: 11, minute: 15, second: 30, kind: .local)
        let e = Equipment(id: G(1)); e.container = Container(id: G(101))
        let comp = Component(id: G(2), container: Container(id: G(102)))
        e.components = [comp]
        let f = FileItem(id: G(30), added: stampL); e.container.files = [f]
        let t = TaskItem(id: G(3)); t.container = Container(id: G(103))
        let p = Procedure(id: G(4)); p.container = Container(id: G(104))
        let step = ChecklistStep(id: G(7)); step.container = Container(id: G(107)); p.steps = [step]
        let v = Vessel(id: G(8)); v.container = Container(id: G(108))
        v.quickCards = [QuickCard(id: G(9))]
        v.jobs = [ShipJob()]
        v.portCalls = [PortCall(id: G(10))]
        let crew = CrewMember(id: G(11))
        let cstep = ChecklistStep(id: G(12)); cstep.container = Container(id: G(112)); crew.checklist = [cstep]
        crew.schedule = [ScheduleEntry(id: G(13))]
        crew.flags = [CrewReviewFlag()]
        let item = ChecklistTemplateItem(container: Container(id: G(120)))
        let tpl = ChecklistTemplate(id: G(20), items: [item]); tpl.createdUtc = stampU
        let port = PortRecord(id: G(22)); port.visits = [PortVisit()]
        let sched = ScheduleTemplate(id: G(23), entries: [ScheduleEntry(id: G(24))]); sched.createdUtc = stampU
        let sire = SireState(); sire.tasks = [SireTask(id: G(28), createdAt: stampL)]
        d.equipment = [e]; d.tasks = [t]; d.procedures = [p]; d.vessels = [v]; d.groups = [ItemGroup(id: G(40))]
        d.crew = [crew]; d.log = [LogEntry(timestampUtc: stampU)]; d.checklistTemplates = [tpl]
        d.listGroups = [ListGroup(id: G(21), createdUtc: stampU)]
        d.quickBuckets = [QuickBucket(id: G(50), createdUtc: stampU)]; d.ports = [port]; d.scheduleTemplates = [sched]
        d.trash = [TrashedItem(id: G(25), deletedUtc: stampU)]; d.sire = sire
        return d
    }
}
