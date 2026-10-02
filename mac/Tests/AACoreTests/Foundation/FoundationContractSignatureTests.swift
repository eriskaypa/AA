// TV: ARCHITECTURE.md §3–§4, §5.2, §6.1–§6.4 — compile-time conformance of every public F1 signature.
// Each closure below calls the contract exactly as ARCHITECTURE.md declares it (labels, parameter types, defaults
// that callers may omit, typed throws, return types, settable vs read-only properties). A drift between the code
// and the contract breaks the BUILD of this file, not just a test. The closures are never invoked.
import CryptoKit
import Foundation
import Testing
import UniformTypeIdentifiers
import os
import AACore

@MainActor @Suite struct FoundationContractSignatureTests {
    // MARK: §3.1 JSONValue / JSONObject / JSONNumber / Ordinal
    @Test func jsonTree() {
        var sigs: [Any] = []
        sigs.append({ (a: String, b: String) -> Bool in Ordinal.equals(a, b) })
        sigs.append({ (s: String, h: inout Hasher) in Ordinal.hash(s, into: &h) })
        sigs.append({ (s: String) -> String in Ordinal.Key(s).string })
        let _: any (Hashable & Sendable).Type = Ordinal.Key.self

        sigs.append({ (s: String) -> JSONNumber in JSONNumber(lexeme: s) })
        sigs.append({ (i: Int) -> JSONNumber in JSONNumber(i) })
        sigs.append({ (i: Int64) -> JSONNumber in JSONNumber(i) })
        sigs.append({ (d: Double) -> JSONNumber? in JSONNumber(d) })
        let _: KeyPath<JSONNumber, String> = \.lexeme
        let _: KeyPath<JSONNumber, Double?> = \.doubleValue
        let _: KeyPath<JSONNumber, Int64?> = \.int64Value
        let _: KeyPath<JSONNumber, Int32?> = \.int32Value
        let _: KeyPath<JSONNumber, Int?> = \.intValue
        let _: any (Sendable & Hashable).Type = JSONNumber.self

        let values: [JSONValue] = [.null, .bool(true), .number(JSONNumber(1)), .string(""), .array([]),
                                   .object(JSONObject()), .rawString("")]
        sigs.append(values)
        let _: KeyPath<JSONValue, JSONObject?> = \.objectValue
        let _: KeyPath<JSONValue, [JSONValue]?> = \.arrayValue
        let _: KeyPath<JSONValue, String?> = \.stringValue
        let _: KeyPath<JSONValue, Bool?> = \.boolValue
        let _: KeyPath<JSONValue, Bool> = \.isNull
        let _: KeyPath<JSONValue, String?> = \.idText
        sigs.append({ (a: JSONValue?, b: JSONValue?) -> Bool in JSONValue.deepEquals(a, b) })
        let _: any (Sendable & Hashable).Type = JSONValue.self

        sigs.append({ () -> JSONObject in JSONObject() })
        sigs.append({ (p: [(String, JSONValue)]) -> JSONObject in JSONObject(p) })
        let _: KeyPath<JSONObject, [(key: String, value: JSONValue)]> = \.pairs
        let _: KeyPath<JSONObject, [String]> = \.keys
        let _: KeyPath<JSONObject, Int> = \.count
        sigs.append({ (o: JSONObject, k: String) -> JSONValue? in o[k] })
        sigs.append({ (o: JSONObject, k: String) -> Bool in o.containsKey(k) })
        sigs.append({ (o: JSONObject, k: String) -> JSONValue? in o.rawValue(forKey: k) })
        sigs.append({ (o: inout JSONObject, k: String, v: JSONValue) in o.set(k, v) })
        sigs.append({ (o: inout JSONObject, k: String) -> JSONValue? in o.removeValue(forKey: k) })
        sigs.append({ (o: inout JSONObject, x: JSONObject) in o.append(contentsOf: x) })
        sigs.append({ (o: JSONObject, k: Set<Ordinal.Key>) -> JSONObject in o.filtering(excluding: k) })
        sigs.append({ (o: JSONObject) -> [(key: String, value: JSONValue)] in o.map { $0 } })   // Sequence
        let _: any (Sendable & Hashable).Type = JSONObject.self
        #expect(sigs.count > 0)
    }

    // MARK: §3.2 parser / writer, §3.3 NetNumberText
    @Test func parserWriterNumbers() {
        var sigs: [Any] = []
        let errors: [JSONParseError] = [.invalid(offset: 0, reason: ""), .tooDeep(limit: 64), .invalidUTF8(offset: 0)]
        sigs.append(errors)
        let _: [InvalidUTF8Policy] = [.replace, .reject]
        #expect(JSONParser.maxDepth == 64)
        sigs.append({ (d: Data) throws(JSONParseError) -> JSONValue in try JSONParser.parse(d) })
        sigs.append({ (d: Data, m: Int, p: InvalidUTF8Policy) throws(JSONParseError) -> JSONValue in
            try JSONParser.parse(d, maxDepth: m, invalidUTF8: p) })
        sigs.append({ (s: String) throws(JSONParseError) -> JSONValue in try JSONParser.parse(s) })
        sigs.append({ (s: String, m: Int) throws(JSONParseError) -> JSONValue in try JSONParser.parse(s, maxDepth: m) })

        var o = JSONWriteOptions()
        o.indented = true; o.indent = "  "; o.newline = "\n"; o.maxDepth = 64
        #expect(o == JSONWriteOptions(indented: true, indent: "  ", newline: "\n", maxDepth: 64))
        #expect(JSONWriteOptions.compact == JSONWriteOptions())
        #expect(JSONWriteOptions.aaschedIndented.indented && JSONWriteOptions.aaschedIndented.newline == "\r\n")
        let _: [JSONWriteError] = [.tooDeep(limit: 64)]
        sigs.append({ (v: JSONValue) throws(JSONWriteError) -> Data in try JSONWriter.data(v) })
        sigs.append({ (v: JSONValue, o: JSONWriteOptions) throws(JSONWriteError) -> Data in try JSONWriter.data(v, options: o) })
        sigs.append({ (v: JSONValue) throws(JSONWriteError) -> String in try JSONWriter.string(v) })
        sigs.append({ (v: JSONValue, o: JSONWriteOptions) throws(JSONWriteError) -> String in try JSONWriter.string(v, options: o) })
        sigs.append({ (s: String) -> String in JSONWriter.escape(s) })

        sigs.append({ (x: Double) -> String? in NetNumberText.shortest(x) })
        sigs.append({ (x: Double) -> Int64 in NetNumberText.int64Saturating(x) })
        sigs.append({ (x: Double) -> String in NetNumberText.net0_4(x) })
        #expect(sigs.count > 0)
    }

    // MARK: §3.4 NetDateTime / NetDateFormat, §3.5 CivilDate / clocks, §3.6 GUIDs
    @Test func datesAndGuids() {
        var sigs: [Any] = []
        let _: [NetDateTime.Kind] = [.unspecified, .utc, .local]
        #expect(NetDateTime.Kind.local.rawValue == 2)
        let _: KeyPath<NetDateTime, Int64> = \.ticks
        let _: KeyPath<NetDateTime, NetDateTime.Kind> = \.kind
        let _: KeyPath<NetDateTime, String?> = \.originalText
        let _: KeyPath<NetDateTime, Int32?> = \.offsetHint
        sigs.append({ (t: Int64, k: NetDateTime.Kind) -> NetDateTime in NetDateTime(ticks: t, kind: k) })
        sigs.append({ (k: NetDateTime.Kind) -> NetDateTime in NetDateTime(year: 2026, month: 1, day: 1, kind: k) })
        sigs.append({ (y: Int, m: Int, d: Int, h: Int, mi: Int, s: Int, f: Int64, k: NetDateTime.Kind) -> NetDateTime in
            NetDateTime(year: y, month: m, day: d, hour: h, minute: mi, second: s, fractionTicks: f, kind: k) })
        sigs.append({ (s: String) -> NetDateTime? in NetDateTime(parsing: s) })
        sigs.append({ (s: String, z: TimeZone) -> NetDateTime? in NetDateTime(parsing: s, zone: z) })
        sigs.append({ (d: NetDateTime) -> String in d.jsonString() })
        sigs.append({ (d: NetDateTime, z: TimeZone) -> String in d.jsonString(zone: z) })
        sigs.append({ (d: NetDateTime, z: TimeZone) -> String in d.formattedISO(zone: z) })
        sigs.append({ (d: NetDateTime) -> String in d.formattedISO() })
        sigs.append({ (a: NetDateTime, b: NetDateTime) -> Bool in a == b && a < b })
        sigs.append({ (d: NetDateTime) -> String in d.description })
        sigs.append({ () -> NetDateTime in NetDateTime.now() })
        sigs.append({ (c: AppClock) -> NetDateTime in NetDateTime.now(clock: c) })
        sigs.append({ () -> NetDateTime in NetDateTime.utcNow() })
        sigs.append({ (c: AppClock) -> NetDateTime in NetDateTime.utcNow(clock: c) })
        sigs.append({ (d: CivilDate) -> NetDateTime in NetDateTime.calendarDate(d) })
        sigs.append({ (d: CivilDate, m: Int) -> NetDateTime in NetDateTime.calendarDateTime(d, minutes: m) })
        let _: KeyPath<NetDateTime, NetDateTime> = \.asCalendarDate
        let _: KeyPath<NetDateTime, NetDateTime> = \.date
        let _: KeyPath<NetDateTime, CivilDate> = \.civilDate
        let _: KeyPath<NetDateTime, Int> = \.minutesOfDay
        sigs.append({ (d: NetDateTime, n: Int) -> [NetDateTime] in
            [d.addingDays(n), d.addingMonths(n), d.addingYears(n), d.addingTicks(Int64(n))] })
        sigs.append({ (d: NetDateTime) -> NetDateTime in d.toLocalTime() })
        sigs.append({ (d: NetDateTime, z: TimeZone) -> NetDateTime in d.toLocalTime(zone: z) })
        sigs.append({ (d: NetDateTime, z: TimeZone) -> Date in d.foundationDate(zone: z) })
        sigs.append({ (d: NetDateTime) -> Date in d.foundationDate() })
        sigs.append({ (d: Date, k: NetDateTime.Kind, z: TimeZone) -> NetDateTime in NetDateTime(date: d, kind: k, zone: z) })
        sigs.append({ (d: Date, k: NetDateTime.Kind) -> NetDateTime in NetDateTime(date: d, kind: k) })
        sigs.append({ (d: NetDateTime, f: NetDateFormat, z: TimeZone) -> String in d.format(f, zone: z) })
        sigs.append({ (d: NetDateTime, f: NetDateFormat) -> String in d.format(f) })
        #expect(NetDateTime.unixEpochTicks == 621_355_968_000_000_000)
        let _: [NetDateFormat] = [.isoDate, .isoMinute, .isoSecond, .time, .stampMinute, .stampSecond,
                                  .isoLocalSeconds, .isoLocal7, .roundTripO]
        let _: any (Sendable & Hashable & Comparable & CustomStringConvertible).Type = NetDateTime.self

        let _: KeyPath<CivilDate, Int> = \.year
        let _: KeyPath<CivilDate, Int> = \.month
        let _: KeyPath<CivilDate, Int> = \.day
        sigs.append({ (y: Int, m: Int, d: Int) -> CivilDate? in CivilDate(year: y, month: m, day: d) })
        sigs.append({ (s: String) -> CivilDate? in CivilDate(iso: s) })
        let _: KeyPath<CivilDate, String> = \.iso
        let _: KeyPath<CivilDate, Int> = \.daysFromCivil
        let _: KeyPath<CivilDate, Int> = \.weekday
        sigs.append({ (n: Int) -> CivilDate in CivilDate(daysFromCivil: n) })
        sigs.append({ (d: CivilDate, n: Int) -> [CivilDate] in [d.addingDays(n), d.addingMonths(n), d.addingYears(n)] })
        sigs.append({ (a: CivilDate, b: CivilDate) -> Int in a.days(to: b) })
        let _: any (Sendable & Hashable & Comparable & CustomStringConvertible).Type = CivilDate.self

        sigs.append({ (c: AppClock) -> (NetDateTime, NetDateTime, CivilDate, TimeZone, Date) in
            (c.now(), c.utcNow(), c.today(), c.timeZone, c.instant()) })
        let _: AppClock = SystemClock()
        let _: AppClock = FixedClock(local: "2026-09-29T14:05:00", zone: TZ.athens)

        let _: KeyPath<UUID, String> = \.netString
        sigs.append({ (s: String) -> UUID? in UUID(netString: s) })
        #expect(UUID.netEmpty.netString == "00000000-0000-0000-0000-000000000000")
        #expect(sigs.count > 0)
    }

    // MARK: §3.7 enums, §3.8 mapping pattern, §3.10 codec / trash payload
    @Test func enumsAndMapping() {
        var sigs: [Any] = []
        func netEnum<E: NetIntEnum>(_: E.Type, _ cases: [E], _ n: Int) {
            #expect(cases.map(\.rawValue) == Array(0..<n))
            #expect(E(rawValue: 77).rawValue == 77 && E(rawValue: 77).name == "77")
            #expect(E.names.count == n)
        }
        netEnum(FileKind.self, [.document, .image, .video, .link, .other], 5)
        netEnum(ItemKind.self, [.equipment, .task, .procedure, .vessel], 4)
        netEnum(RecurrenceKind.self, [.none, .daily, .weekly, .monthly, .yearly], 5)
        netEnum(WorkStatus.self, [.todo, .inProgress, .blocked, .done], 4)
        netEnum(ScheduleKind.self, [.note, .task, .procedure, .equipment], 4)
        netEnum(CrewFlagSeverity.self, [.info, .warning, .error], 3)
        let _: KeyPath<WorkStatus, String> = \.friendlyLabel
        let _: KeyPath<RecurrenceKind, String> = \.friendlyLabel

        var c = JSONDecodeContext()
        c.zone = .current; c.clock = SystemClock(); c.newGuid = { UUID() }; c.path = []
        sigs.append({ (z: TimeZone, k: AppClock, g: @escaping @Sendable () -> UUID, p: [String]) -> JSONDecodeContext in
            JSONDecodeContext(zone: z, clock: k, newGuid: g, path: p) })
        let _: JSONDecodeContext = .standard
        let _: [JSONModelError] = [.typeMismatch(path: "", expected: ""), .invalidGuid(path: "", text: ""),
                                   .invalidDate(path: "", text: ""), .notAnObject(path: "")]
        let _: any (Error & Sendable & CustomStringConvertible).Type = JSONModelError.self
        let log = JSONEncodeIssueLog()
        log.record("x")
        #expect(log.issues == ["x"])
        var e = JSONEncodeOptions()
        e.writeNulls = false; e.includeExtra = true; e.zone = .current; e.issueLog = nil
        sigs.append({ (n: Bool, x: Bool, z: TimeZone, l: JSONEncodeIssueLog?) -> JSONEncodeOptions in
            JSONEncodeOptions(writeNulls: n, includeExtra: x, zone: z, issueLog: l) })
        #expect(JSONEncodeOptions.aasched.writeNulls && !JSONEncodeOptions.aasched.includeExtra)
        #expect(!JSONEncodeOptions.dataFile.writeNulls && JSONEncodeOptions.dataFile.includeExtra)

        sigs.append({ (o: JSONObject, c: JSONDecodeContext, t: String) -> JSONFieldReader in JSONFieldReader(o, context: c, type: t) })
        sigs.append({ (r: JSONFieldReader, k: String) throws(JSONModelError) in
            let _: String? = try r.string(k); let _: Bool? = try r.bool(k); let _: Int? = try r.int(k)
            let _: Double? = try r.double(k); let _: UUID? = try r.guid(k); let _: NetDateTime? = try r.date(k)
            let _: WorkStatus? = try r.netEnum(k, WorkStatus.self); let _: [UUID]? = try r.guidArray(k)
            let _: [String]? = try r.stringArray(k); let _: OrderedMap<String>? = try r.stringMap(k)
            let _: OrderedMap<Bool>? = try r.boolMap(k)
            let _: Container? = try r.model(k, Container.self); let _: [FileItem]? = try r.modelArray(k, FileItem.self)
            let _: JSONObject = r.unknownMembers(knownKeys: [k]); let _: JSONObject = r.unknownMembers(knownKeys: [k], legacyKeys: [k])
        })
        sigs.append({ (o: JSONEncodeOptions) -> JSONObjectBuilder in JSONObjectBuilder(o) })
        sigs.append({ (w: inout JSONObjectBuilder, k: String, d: NetDateTime) -> JSONObject in
            w.string(k, ""); w.optionalString(k, nil); w.bool(k, true); w.int(k, 1); w.double(k, 1)
            w.optionalDouble(k, nil); w.guid(k, UUID()); w.optionalGuid(k, nil); w.date(k, d); w.optionalDate(k, nil)
            w.netEnum(k, WorkStatus.done); w.guidArray(k, []); w.stringArray(k, []); w.stringMap(k, OrderedMap<String>())
            w.boolMap(k, OrderedMap<Bool>()); w.model(k, Container()); w.modelArray(k, [FileItem]())
            return w.build(appending: JSONObject())
        })
        var m = OrderedMap<String>()
        m["a"] = "b"
        let _: [String] = m.keys
        let _: Int = m.count
        let _: [(key: String, value: String)] = m.pairs
        let _: [(key: String, value: String)] = m.map { $0 }                                // Sequence
        let _: any (Sendable & Hashable).Type = OrderedMap<Bool>.self

        sigs.append({ (v: JSONValue, c: JSONDecodeContext) throws(JSONModelError) -> AppData in try ModelCodec.decodeAppData(v, context: c) })
        sigs.append({ (d: AppData) -> JSONValue in ModelCodec.encodeAppData(d) })
        sigs.append({ (d: AppData, o: JSONEncodeOptions) -> JSONValue in ModelCodec.encodeAppData(d, options: o) })
        sigs.append({ (t: TaskItem) -> TaskItem in ModelCodec.deepClone(t) })
        sigs.append({ (t: HierarchyItem, c: JSONDecodeContext) -> HierarchyItem in ModelCodec.deepClone(t, context: c) })
        sigs.append({ (i: HierarchyItem) -> String in TrashPayload.encode(i) })
        sigs.append({ (m: CrewMember) -> String in TrashPayload.encode(m) })
        sigs.append({ (t: String, p: String, c: JSONDecodeContext) -> AnyObject? in TrashPayload.decode(itemType: t, payload: p, context: c) })
        #expect(sigs.count > 0)
    }

    // MARK: §4 models — conformances, key lists, defaults and helper signatures
    @Test func modelShapes() {
        var sigs: [Any] = []
        let models: [any JSONModel.Type] = [FileItem.self, Container.self, HierarchyItem.self, Equipment.self,
            Component.self, TaskItem.self, Procedure.self, Vessel.self, ChecklistStep.self, ItemGroup.self,
            QuickCard.self, ShipJob.self, PortCall.self, PortRecord.self, PortVisit.self, CrewMember.self,
            CrewReviewFlag.self, ChecklistTemplateItem.self, ChecklistTemplate.self, ListGroup.self,
            ScheduleEntry.self, ScheduleTemplate.self, QuickBucket.self, TrashedItem.self, LogEntry.self,
            SireState.self, SireTask.self, UiState.self, AppData.self]
        #expect(models.count == 29)
        // §4.1 protocols
        let _: [any SchedulableJob.Type] = [TaskItem.self, Procedure.self, ChecklistStep.self]
        let _: [any Bucketable.Type] = [HierarchyItem.self, ChecklistStep.self]
        sigs.append({ (j: any SchedulableJob) -> (UUID, Bool, Int, NetDateTime?, String) in
            j.isJob = j.isJob; j.durationMinutes = j.durationMinutes; j.scheduledStart = j.scheduledStart
            return (j.id, j.isJob, j.durationMinutes, j.scheduledStart, j.jobName) })
        sigs.append({ (b: any Bucketable) in b.bucketIds = b.bucketIds })
        // Value records are Sendable + Hashable (§3.8, §4)
        let _: [any (Sendable & Hashable).Type] = [PortVisit.self, CrewReviewFlag.self, TrashedItem.self, LogEntry.self]
        // Identifiable
        let _: [any Identifiable.Type] = [FileItem.self, Container.self, HierarchyItem.self, Component.self,
            ChecklistStep.self, ItemGroup.self, QuickCard.self, ShipJob.self, PortCall.self, PortRecord.self,
            CrewMember.self, ChecklistTemplateItem.self, ChecklistTemplate.self, ListGroup.self, ScheduleEntry.self,
            ScheduleTemplate.self, QuickBucket.self, TrashedItem.self, SireTask.self]

        // §4.2
        let _: ReferenceWritableKeyPath<FileItem, [UUID]> = \.linkedItemIds
        let _: KeyPath<FileItem, String> = \.sourceLabel
        let _: ReferenceWritableKeyPath<Container, String> = \.richTextXaml
        let _: ReferenceWritableKeyPath<Container, [UUID]> = \.sharedWithContainerIds
        // §4.3
        let _: KeyPath<HierarchyItem, ItemKind> = \.kind
        let _: KeyPath<HierarchyItem, Bool> = \.isLockProtected
        let _: ReferenceWritableKeyPath<HierarchyItem, UUID?> = \.groupId
        let _: ReferenceWritableKeyPath<HierarchyItem, String?> = \.lockHint
        let _: [String] = HierarchyItem.baseJSONKeys
        sigs.append({ (h: HierarchyItem, r: JSONFieldReader) throws(JSONModelError) in try h.decodeBase(r) })
        sigs.append({ (h: HierarchyItem, w: inout JSONObjectBuilder) in h.encodeBase(into: &w) })
        sigs.append({ (o: JSONObject, c: JSONDecodeContext, t: HierarchyItem.Type) throws(JSONModelError) -> HierarchyItem in
            try t.init(json: o, context: c) })                                            // required init
        let _: ReferenceWritableKeyPath<Equipment, [Component]> = \.components
        let _: ReferenceWritableKeyPath<TaskItem, Bool> = \.isComplete
        let _: ReferenceWritableKeyPath<TaskItem, WorkStatus> = \.status
        let _: KeyPath<TaskItem, Bool> = \.hasRange
        let _: KeyPath<TaskItem, NetDateTime?> = \.rangeFirst
        let _: KeyPath<TaskItem, String> = \.whenText
        sigs.append({ (t: TaskItem, d: CivilDate) -> Bool in t.coversDay(d) })
        sigs.append({ (t: TaskItem) -> [TaskItem] in t.allSubtasksDepthFirst() })
        let _: ReferenceWritableKeyPath<Procedure, [ChecklistStep]> = \.steps
        let _: ReferenceWritableKeyPath<Vessel, Bool> = \.notificationsEnabled
        let _: ReferenceWritableKeyPath<ItemGroup, Bool> = \.expanded
        // §4.4
        sigs.append({ (q: QuickCard) -> QuickCard in q.copy(from: q); return q.clone() })
        let _: KeyPath<ShipJob, NetDateTime?> = \.dueDateValue
        let _: KeyPath<ShipJob, String> = \.id
        sigs.append({ (j: ShipJob, d: CivilDate) -> Int? in j.copy(from: j); return j.daysUntilDue(today: d) })
        let _: [KeyPath<PortCall, String>] = [\.key, \.displayName, \.arrivalDisplay, \.departureDisplay]
        let _: KeyPath<PortCall, NetDateTime?> = \.arrivalValue
        let _: [KeyPath<PortRecord, String>] = [\.key, \.display]
        let _: [KeyPath<PortVisit, String>] = [\.visitKey, \.arrivalDisplay, \.departureDisplay]
        let _: KeyPath<PortVisit, NetDateTime?> = \.arrivalValue
        let _: WritableKeyPath<PortVisit, UUID?> = \.vesselId
        // §4.5
        let _: [KeyPath<CrewMember, String>] = [\.fullName, \.key]
        let _: [KeyPath<CrewMember, Bool>] = [\.hasFlags, \.hasErrors]
        let _: KeyPath<CrewMember, NetDateTime?> = \.signOffDateValue
        sigs.append({ (m: CrewMember, d: CivilDate) -> (Int?, ContractStatus, ContractStatus) in
            (m.daysUntilSignOff(today: d), m.contractStatus(on: d), m.contractStatus(on: d, criticalDays: 30, soonDays: 60)) })
        sigs.append({ (s: String?) -> NetDateTime? in CrewMember.parseDate(s) })
        let _: [ContractStatus] = [.unknown, .ok, .dueSoon, .critical, .expired]
        #expect(ContractStatus.expired.rawValue == 4)
        let _: WritableKeyPath<CrewReviewFlag, CrewFlagSeverity> = \.severity
        // §4.6
        let _: KeyPath<ChecklistTemplateItem, UUID> = \.rowID
        let _: KeyPath<ChecklistTemplate, String> = \.display
        let _: ReferenceWritableKeyPath<ChecklistTemplate, UUID?> = \.groupId
        let _: ReferenceWritableKeyPath<ChecklistTemplate, NetDateTime> = \.createdUtc
        let _: KeyPath<ScheduleEntry, NetDateTime?> = \.when
        let _: [KeyPath<ScheduleEntry, String>] = [\.kindIcon, \.whenDisplay]
        let _: KeyPath<ScheduleTemplate, String> = \.display
        let _: KeyPath<QuickBucket, String> = \.display
        // §4.7
        let _: [KeyPath<TrashedItem, String>] = [\.deletedLocal, \.display]
        let _: [TrashItemType] = [.equipment, .task, .procedure, .vessel, .crew]
        #expect(TrashItemType.crew.rawValue == "Crew")
        let _: [KeyPath<LogEntry, String>] = [\.timeUtc, \.timeLocal]
        // §4.8
        let _: ReferenceWritableKeyPath<SireState, OrderedMap<String>> = \.questionStatuses
        let _: ReferenceWritableKeyPath<SireState, OrderedMap<String>> = \.questionBodies
        sigs.append({ (s: SireState, q: String) -> (SireQuestionStatus, Int, Bool, Bool, [SireTask], Int, Int) in
            s.setStatus(.checked, for: q); s.toggleBookmark(q); s.toggleForExport(q)
            return (s.status(for: q), s.count(of: .none), s.isBookmarked(q), s.isForExport(q), s.tasks(for: q),
                    s.totalTaskCount, s.completedTaskCount) })
        let _: [SireQuestionStatus] = [.none, .inProgress, .checked, .notApplicable]
        #expect(SireQuestionStatus.notApplicable.rawValue == "NotApplicable")
        let _: ReferenceWritableKeyPath<SireTask, NetDateTime> = \.createdAt
        // §4.9
        #expect(UiState.perDeviceKeyNames.count == 16)
        sigs.append({ (u: UiState) in u.copyPerDeviceValues(from: u) })
        let _: ReferenceWritableKeyPath<UiState, OrderedMap<String>> = \.tabColors
        let _: ReferenceWritableKeyPath<UiState, OrderedMap<Bool>> = \.sortAZ
        let _: ReferenceWritableKeyPath<UiState, NetDateTime?> = \.calendarSelectedDate
        // §4.10
        let _: ReferenceWritableKeyPath<AppData, [PortRecord]> = \.ports
        let _: ReferenceWritableKeyPath<AppData, NetDateTime?> = \.lastModified
        let _: ReferenceWritableKeyPath<AppData, Int> = \.schemaVersion
        // §4.11
        let s = AppSettings(json: JSONObject())
        let _: [KeyPath<AppSettings, String?>] = [\.currentDataFile, \.passwordHash, \.passwordSalt, \.googleDriveFolder,
                                                  \.folderBuilderBase, \.sharedSaveFile, \.geminiApiKey, \.appIdentity]
        let _: [KeyPath<AppSettings, Bool>] = [\.syncOnSave, \.darkMode, \.encryptLocalData, \.textOnlyExport]
        let _: KeyPath<AppSettings, JSONObject> = \.extra
        #expect(s == AppSettings(json: JSONObject()))
        let _: any (Sendable & Equatable).Type = AppSettings.self
        // §4.12
        sigs.append({ (o: JSONObject, c: JSONDecodeContext) throws(JSONModelError) -> BundleSource in try BundleSource(json: o, context: c) })
        sigs.append({ (b: BundleSource) -> (JSONObject, String) in (b.toJSON(), b.writtenLocal) })
        let _: WritableKeyPath<BundleSource, Bool> = \.dataOnly
        let _: any (Sendable & Equatable).Type = BundleSource.self
        #expect(sigs.count > 0)
    }

    // MARK: §5.2 AppStore core, PersistenceWriter, events, write guard
    @Test func appStoreCore() {
        var sigs: [Any] = []
        let _: [DataReplaceReason] = [.initialLoad, .reloadFromDisk, .importFile, .importBundle, .sharedSavePull,
                                      .driveImport, .flashSyncApply, .other("")]
        let _: [AppStoreError] = [.timeout(path: ""), .serialization(""), .write(""), .pausedByGuard, .writesPaused]
        let _: any (Error & LocalizedError & Sendable).Type = AppStoreError.self
        sigs.append({ (g: DataFileWriteGuard, u: URL, d: Data) -> Bool in
            g.didWrite(to: u, bytes: d); g.didLoad(from: u, bytes: d); return g.shouldWrite(to: u) })
        let _: [WritePauseReason] = [.externalChange, .readOnly, .other("")]
        sigs.append({ () -> EventHub<Int> in
            let h = EventHub<Int>()
            let sub: EventSubscription = h.subscribe { (_: Int) in }
            h.send(1); sub.cancel(); h.removeAll(); return h })
        sigs.append({ (d: DataStore, a: AppData, c: AppClock) -> AppStore in AppStore(dataStore: d, data: a, clock: c) })
        sigs.append({ (d: DataStore, a: AppData) -> AppStore in AppStore(dataStore: d, data: a) })
        let _: KeyPath<AppStore, DataStore> = \.dataStore
        let _: KeyPath<AppStore, AppClock> = \.clock
        let _: KeyPath<AppStore, AppData> = \.data
        let _: KeyPath<AppStore, Int> = \.generation
        let _: KeyPath<AppStore, Bool> = \.isDirty
        let _: ReferenceWritableKeyPath<AppStore, Bool> = \.suspendSaving
        let _: KeyPath<AppStore, Bool> = \.writesPaused
        let _: KeyPath<AppStore, WritePauseReason?> = \.writePauseReason
        let _: KeyPath<AppStore, String?> = \.lastSaveError
        let _: KeyPath<AppStore, PersistenceWriter> = \.writer
        let _: ReferenceWritableKeyPath<AppStore, Set<UUID>> = \.detachedItemIDs
        let _: ReferenceWritableKeyPath<AppStore, Duration> = \.debounceInterval
        #expect(AppStore.saveTimeout == 15)
        let _: KeyPath<AppStore, EventHub<Void>> = \.saved
        let _: KeyPath<AppStore, EventHub<DataReplaceReason>> = \.dataReplaced
        let _: KeyPath<AppStore, EventHub<Void>> = \.trashChanged
        sigs.append({ (s: AppStore, a: AppData) throws(AppStoreError) -> (Bool, Data) in
            s.pauseWrites(reason: .readOnly); s.resumeWrites(); s.markDirty(); try s.save(); try s.flushIfDirty()
            s.replaceData(a, reason: .other("x")); s.cancelPendingAutosave()
            return (s.waitForQueuedWrites(timeout: 1), try s.encodedSnapshot()) })

        sigs.append({ (w: PersistenceWriter, j: WriteJob) -> DispatchWorkItem in
            w.runOnWriterQueue {}
            return w.enqueue(j) { (_: Result<Void, Error>) in } })
        let _: ReferenceWritableKeyPath<PersistenceWriter, DataFileWriteGuard?> = \.writeGuard
        sigs.append({ (b: Data, u: URL, k: SymmetricKey?) -> WriteJob in
            var j = WriteJob(bytes: b, url: u, encryptionKey: k); j.bytes = b; j.url = u; j.encryptionKey = k; return j })
        let _: any Sendable.Type = PersistenceWriter.self
        let _: any Sendable.Type = WriteJob.self
        #expect(sigs.count > 0)
    }

    // MARK: §6.1 Foundation
    @Test func foundation() {
        var sigs: [Any] = []
        #expect(Identifiers.bundleID == "com.eriskay.aa" && Identifiers.logSubsystem == "com.eriskay.aa")
        #expect([Identifiers.utBundle, Identifiers.utSchedule, Identifiers.utXaml, Identifiers.utTaskRef,
                 Identifiers.utJobRef, Identifiers.utItemRef]
                == ["com.eriskay.aa.bundle", "com.eriskay.aa.schedule", "com.eriskay.aa.xaml", "com.eriskay.aa.task-ref",
                    "com.eriskay.aa.job-ref", "com.eriskay.aa.item-ref"])
        #expect(Identifiers.instanceRequestNotification == "com.eriskay.aa.InstanceRequest")
        #expect(Identifiers.reminderNotificationID == "aa.reminder")
        let k: [(service: String, account: String)] = [Identifiers.Keychain.localDataKey, Identifiers.Keychain.googleTokenKey,
                                                       Identifiers.Keychain.gemini]
        #expect(k.map(\.service) == ["AA.LocalDataKey", "AA", "com.eriskay.aa.gemini"])
        #expect(k.map(\.account) == ["v1", "google-token-key", "GeminiApiKey"])
        let scenes: [SceneID] = [.main, .splash, .login, .item, .quickWork, .search, .activityLog, .unitConverter,
                                 .folderBuilder, .dateCalculator, .flashSync, .crewTable, .shortcuts, .settings, .about,
                                 .bootstrap, .due, .switcher]
        #expect(scenes.map(\.rawValue) == ["main", "splash", "login", "item", "quick-work", "search", "activity-log",
                                           "unit-converter", "folder-builder", "date-calculator", "flash-sync",
                                           "crew-table", "shortcuts", "settings", "about", "bootstrap", "due", "switcher"])
        let _: [UTType] = [.aaBundle, .aaXaml, .aaTaskRef, .aaJobRef, .aaItemRef, .xlsx]
        sigs.append({ (n: String, e: String) -> (URL?, Data?) in (AAResources.url(name: n, ext: e), AAResources.data(name: n, ext: e)) })
        sigs.append({ (s: String?, a: String, b: String) -> (Bool, String, Bool, Bool, ComparisonResult, ComparisonResult, String) in
            (NetText.isBlank(s), NetText.trim(a), NetText.equalsIgnoreCase(a, b), NetText.containsIgnoreCase(a, b),
             NetText.compareIgnoreCase(a, b), NetText.compareCulture(a, b), NetText.toLowerInvariant(a)) })
        let _: Set<Character> = WindowsFileName.invalidCharacters
        sigs.append({ (n: String, r: Character, f: String) -> (String, String, String) in
            (WindowsFileName.sanitize(n, replacement: r, fallback: f), WindowsFileName.sanitize(n, fallback: f),
             WindowsFileName.safeIdentity(n)) })
        var c = ARGB(r: 1, g: 2, b: 3)
        c.a = 0xFF; c.r = 1; c.g = 2; c.b = 3
        #expect(c == ARGB(a: 0xFF, r: 1, g: 2, b: 3))
        sigs.append({ (s: String?, c: ARGB) -> (ARGB?, String, String, Double) in
            (WpfColor.parse(s), WpfColor.hexRRGGBB(c), WpfColor.hexAARRGGBB(c), WpfColor.luma(c)) })
        let _: MacPreferences = MacPreferences.shared
        sigs.append({ (d: UserDefaults) -> MacPreferences in MacPreferences(defaults: d) })
        sigs.append({ (p: MacPreferences, raw: String) -> (Bool, String?, Data?, [String]?) in
            let k = MacPreferences.Key(raw)
            let _: String = k.rawValue
            p.set(true, k); p.set(nil as String?, k); p.set(nil as Data?, k); p.setCodable([raw], k)
            return (p.bool(k, default: false), p.string(k), p.data(k), p.codable(k, as: [String].self)) })
        let _: any (Hashable & Sendable).Type = MacPreferences.Key.self
        sigs.append({ (c: String) -> Logger in AALog.logger(c) })
        sigs.append({ (d: Data, s: UInt32) -> (UInt32, UInt32) in (CRC32.checksum(d), CRC32.checksum(d, seed: s)) })
        sigs.append({ (b: [UInt8], n: Int?) throws -> ([UInt8], [UInt8]) in
            (try RawDeflate.compress(b), try RawDeflate.inflate(b, expectedLength: n)) })
        sigs.append({ (s: String) -> String in MacKeyStrings.render(s) })
        #expect(ContractOwner.allCases.map(\.rawValue) == ["wShell", "wPersist", "wRich", "wCont", "wFiles", "wHier",
            "wBuild", "wPlan", "wQuick", "wCrew", "wVessel", "wPdf", "wSire", "wFlash", "wDrive"])
        sigs.append({ (o: ContractOwner) -> Bool in ContractStatus.isImplemented(o) })
        #expect(sigs.count > 0)
    }

    // MARK: §6.2 Persistence
    @Test func persistence() {
        var sigs: [Any] = []
        let _: [DataLoadError] = [.unreadable(""), .windowsEncrypted, .macKeyUnavailable,
                                  .parse(.tooDeep(limit: 64)), .model(.notAnObject(path: ""))]
        let _: any (Error & LocalizedError & Sendable).Type = DataLoadError.self
        sigs.append({ (u: URL, s: SecretStore, c: AppClock) -> DataStore in DataStore(appFolder: u, secrets: s, clock: c) })
        sigs.append({ (u: URL) -> DataStore in DataStore(appFolder: u) })
        let urls: [KeyPath<DataStore, URL>] = [\.appFolder, \.filesFolder, \.defaultDataFile, \.settingsFile,
            \.googleClientSecretFile, \.googleTokenFolder, \.crashLogFile, \.flashBaselineFile, \.instanceLockFile,
            \.currentDataFile]
        #expect(urls.count == 10)
        let _: KeyPath<DataStore, SettingsStore> = \.settings
        let _: KeyPath<DataStore, SecretStore> = \.secrets
        let _: KeyPath<DataStore, AppClock> = \.clock
        let _: KeyPath<DataStore, Bool> = \.lastLoadFailed
        let _: KeyPath<DataStore, DataLoadError?> = \.lastLoadError
        let _: KeyPath<DataStore, Int?> = \.loadedNewerSchema
        #expect(DataStore.currentSchemaVersion == 1)
        let _: ReferenceWritableKeyPath<DataStore, DataFileWriteGuard?> = \.writeGuard
        sigs.append({ (d: DataStore, u: URL, a: AppData, b: Data) throws -> (AppData, Data, URL, Bool, SymmetricKey?) in
            d.loadSettings()
            let loaded: AppData = d.load()
            _ = loaded
            let imported = try d.loadFrom(u)
            let bytes = try d.serializeForSave(a)
            try d.saveTo(a, url: u)
            try d.writeLocalDataFile(b, to: u)
            d.setCurrentDataFile(u)
            let adopted = try d.adoptExternalDataFile(u, copyIntoAppFolder: true)
            return (imported, bytes, adopted, d.isUnderAppFolder(u), d.localEncryptionKeyIfEnabled(for: u)) })
        sigs.append({ (d: DataStore, u: URL) throws(DataLoadError) -> AppData in try d.loadFrom(u) })
        sigs.append({ (d: DataStore, a: AppData) throws(AppStoreError) -> Data in try d.serializeForSave(a) })
        sigs.append({ (d: DataStore) async -> AppData in await d.loadInBackground() })
        sigs.append({ (u: URL, k: SymmetricKey?) throws(DataLoadError) -> Data in try DataStore.readDataBytes(u, key: k) })

        sigs.append({ (u: URL, s: SecretStore) -> SettingsStore in SettingsStore(fileURL: u, secrets: s) })
        let _: KeyPath<SettingsStore, AppSettings> = \.values
        let _: KeyPath<SettingsStore, String> = \.appIdentity
        let _: KeyPath<SettingsStore, [String]> = \.foreignPathKeys
        let _: ReferenceWritableKeyPath<SettingsStore, Bool> = \.isWriteGated
        let _: KeyPath<SettingsStore, Bool> = \.lastWriteRefused
        sigs.append({ (s: SettingsStore, t: String, b: Bool) in
            s.reload(); s.setCurrentDataFile(nil); s.setCurrentDataFile(t); s.setPassword(hash: t, salt: t)
            s.setGoogleDriveFolder(t); s.setSyncOnSave(b); s.setTextOnlyExport(b); s.setDarkMode(b)
            s.setEncryptLocalData(b); s.setAppIdentity(nil); s.setFolderBuilderBase(t); s.setSharedSaveFile(nil) })
        sigs.append({ (s: SettingsStore, o: JSONObject) throws(DataLoadError) -> JSONObject in
            try s.writeRawTree(o); return try s.readRawTree() })
        #expect(SettingsStore.unreadableStatus
                == "Couldn't update settings.json (it is unreadable) \u{2014} this change applies until AA quits.")
        sigs.append({ () -> String in SettingsStore.defaultIdentity() })

        sigs.append({ (d: Data, u: URL) throws -> URL in try AtomicWrite.write(d, to: u); return AtomicWrite.tempURL(for: u) })
        let _: [LocalEncryption.FileClass] = [.plain, .mac, .windowsDPAPI]
        #expect(LocalEncryption.macMagic == Data("AAENCM1\n".utf8))
        #expect(LocalEncryption.windowsMagic == Data("AAENC1\n".utf8))
        sigs.append({ (d: Data, k: SymmetricKey, s: SecretStore) throws -> (LocalEncryption.FileClass, Data, Data, SymmetricKey?) in
            (LocalEncryption.classify(d), try LocalEncryption.encrypt(d, key: k), try LocalEncryption.decrypt(d, key: k),
             try LocalEncryption.key(secrets: s, create: false)) })
        sigs.append({ (a: AppData) in SchemaMigration.migrate(a) })
        #expect(sigs.count > 0)
    }

    // MARK: §6.3 Crypto
    @Test func crypto() {
        var sigs: [Any] = []
        sigs.append({ (p: String, s: Data, i: Int, l: Int) -> Data in PBKDF2.sha256(password: p, salt: s, iterations: i, length: l) })
        sigs.append({ (d: Data, k: Data, iv: Data) throws -> (Data, Data) in
            (try AESCBC.encrypt(d, key: k, iv: iv), try AESCBC.decrypt(d, key: k, iv: iv)) })
        sigs.append({ (d: Data, k: Data) -> Data in HMACSHA256.mac(d, key: k) })
        sigs.append({ (a: Data, b: Data) -> Bool in ConstantTime.equals(a, b) })
        sigs.append({ (n: Int) -> Data in SecureRandom.bytes(n) })
        sigs.append({ (d: Data, s: String) -> (String, Data?) in (NetBase64.encode(d), NetBase64.decode(s)) })
        #expect(PasswordHashing.iterations == 100_000 && PasswordHashing.saltSize == 16 && PasswordHashing.keySize == 32)
        #expect(PasswordHashing.masterPassword == "redemption")
        sigs.append({ (p: String, s: Data) -> (Data, Data) in (PasswordHashing.newSalt(), PasswordHashing.hash(password: p, salt: s)) })
        #expect(LegacyBodyCrypto.prefix == "enc:")
        sigs.append({ (t: String, p: String, s: String, iv: Data?) -> (Bool, String?, String, String) in
            (LegacyBodyCrypto.isEncrypted(t), LegacyBodyCrypto.decrypt(t, password: p, saltBase64: s),
             LegacyBodyCrypto.encrypt(t, password: p, saltBase64: s), LegacyBodyCrypto.encrypt(t, password: p, saltBase64: s, iv: iv)) })
        sigs.append({ (s: SecretStore, d: Data, a: String) throws -> Data? in
            try s.write(d, service: a, account: a); try s.delete(service: a, account: a)
            return try s.read(service: a, account: a) })
        let _: SecretStore = KeychainSecretStore()
        let _: SecretStore = InMemorySecretStore()
        let _: [PasswordError] = [.tooShort, .mismatch, .wrongCurrentPassword]
        sigs.append({ (s: SettingsStore) -> PasswordService in PasswordService(settings: s) })
        let _: KeyPath<PasswordService, Bool> = \.hasPassword
        let _: KeyPath<PasswordService, Bool> = \.isUnlocked
        sigs.append({ (p: PasswordService, t: String) throws(PasswordError) -> (Bool, Bool, String?) in
            p.lock(); try p.setPassword(t, current: nil)
            return (p.verify(t), p.unlock(t), p.decryptLegacyBody(t)) })
        sigs.append({ () -> ItemLockService in ItemLockService() })
        let _: KeyPath<ItemLockService, Set<UUID>> = \.unlockedIDs
        sigs.append({ (l: ItemLockService, i: HierarchyItem, p: String) async -> Bool in
            l.protect(i, password: p, hint: nil); l.removeProtection(i); l.relock(i.id); l.relockAll()
            _ = l.isGated(i)
            return await l.tryUnlock(i, password: p) })
        sigs.append({ (p: String, h: String, s: String) -> Bool in ItemLockService.verify(password: p, hashBase64: h, saltBase64: s) })
        #expect(sigs.count > 0)
    }

    // MARK: §6.4 ZIP and XLSX writer
    @Test func zipAndXlsx() {
        var sigs: [Any] = []
        let _: [ZipError] = [.notAZip, .corrupt(""), .unsafePath(""), .crcMismatch(""), .unsupported(""), .io("")]
        sigs.append({ (e: ZipEntryInfo) -> (String, Bool, UInt16, UInt64, UInt64, UInt32, Date?, Bool) in
            (e.name, e.isDirectory, e.method, e.compressedSize, e.uncompressedSize, e.crc32, e.modified, e.isUTF8) })
        let _: any (Sendable & Hashable).Type = ZipEntryInfo.self
        sigs.append({ (u: URL) throws(ZipError) -> ZipReader in try ZipReader(url: u) })
        sigs.append({ (d: Data) throws(ZipError) -> ZipReader in try ZipReader(data: d) })
        sigs.append({ (r: ZipReader, n: String, u: URL) throws(ZipError) -> ([ZipEntryInfo], ZipEntryInfo?, Data) in
            let e = r.entries[0]
            try r.extract(e, to: u); try r.extractAll(to: u); try r.extractAll(to: u, skip: { _ in false })
            return (r.entries, r.entry(named: n), try r.data(for: e)) })
        sigs.append({ (n: String) -> Bool in ZipReader.isFinderMetadata(n) })
        sigs.append({ (u: URL, d: Data, n: String, m: Date?) throws(ZipError) -> ZipWriter in
            let w = try ZipWriter(url: u)
            try w.addFile(named: n, from: u, modified: m); try w.addData(d, named: n, modified: m)
            try w.addData(d, named: n, modified: m, compress: false); try w.addDirectory(named: n); try w.finish()
            return w })

        let _: [XlsxCellValue] = [.text(""), .number(1), .empty]
        var col = XlsxColumnSpec()
        col.width = nil; col.textFormat = false
        #expect(XlsxColumnSpec(width: 1, textFormat: true).textFormat)
        var sheet = XlsxSheetSpec(name: "", columns: [col], boldHeader: true, header: [], rows: [])
        sheet.name = "s"; sheet.columns = []; sheet.boldHeader = false; sheet.header = []; sheet.rows = [[.empty]]
        sigs.append({ (u: URL, s: XlsxSheetSpec, p: [(path: String, data: Data)]) throws in
            try XlsxWriter.write(to: u, sheetName: "", headers: [], rows: [[""]])
            try XlsxWriter.write(to: u, sheet: s)
            try XlsxWriter.writePackage(to: u, parts: p) })
        sigs.append({ (n: String) -> (String, String) in (XlsxWriter.sanitizeSheetName(n, fallback: n), XlsxWriter.xmlEscape(n)) })
        #expect(sigs.count > 0 && sheet.rows.count == 1)
    }
}

/// §2.2 / §3.8 / §4: value records and pure helpers are `nonisolated` — usable from a non-isolated context.
@Suite struct FoundationNonisolatedSignatureTests {
    @Test func valueRecordsAndStaticHelpers() throws {
        let c = JSONDecodeContext.standard
        let o = JSONObject()
        let v = try PortVisit(json: o, context: c)
        let f = try CrewReviewFlag(json: o, context: c)
        let t = try TrashedItem(json: o, context: c)
        let l = try LogEntry(json: o, context: c)
        let b = try BundleSource(json: o, context: c)
        #expect(v.toJSON().count == 6 && f.toJSON().count == 3 && t.toJSON().count == 8 && l.toJSON().count == 5)
        #expect(b.toJSON().count == 4)
        #expect(t.deletedLocal.count == 16 && l.timeUtc.hasSuffix(" UTC") && !v.visitKey.isEmpty)
        #expect(CrewMember.parseDate("2026-03-04") != nil)
        #expect(!ItemLockService.verify(password: "x", hashBase64: "", saltBase64: ""))
        #expect(!SettingsStore.defaultIdentity().isEmpty)
        let sigs: [Any] = [{ (u: URL) throws(DataLoadError) -> Data in try DataStore.readDataBytes(u, key: nil) }]
        #expect(sigs.count == 1)
    }
}
