// TV: ARCHITECTURE.md §5.3, §6.5–§6.8, §11 — compile-time conformance of every placeholder F1 created for F2 and
// the wave owners. The owners replace the bodies in place with the same public signatures (§11), so this file must
// keep compiling after every merge; a drift breaks the build of the test target. Closures are never invoked.
import AppKit
import CryptoKit
import Foundation
import Testing
import AACore

@MainActor @Suite struct FoundationPlaceholderSignatureTests {
    // MARK: §5.3 AppStore domain operations (F2)
    @Test func appStoreDomainOperations() {
        var sigs: [Any] = []
        sigs.append({ (s: AppStore, id: UUID, k: ItemKind, j: any SchedulableJob) in
            let _: [HierarchyItem] = s.allItems()
            let _: [HierarchyItem] = s.items(of: k)
            let _: HierarchyItem? = s.item(id: id)
            let _: TaskItem? = s.task(id: id)
            let _: TaskItem? = s.parentTask(of: id)
            let _: TaskItem? = s.topLevelTask(containing: id)
            let _: (step: ChecklistStep, owner: StepOwner)? = s.step(id: id)
            let _: (component: Component, equipment: Equipment)? = s.component(id: id)
            let _: CrewMember? = s.crewMember(id: id)
            let _: ChecklistTemplate? = s.template(id: id)
            let _: QuickBucket? = s.bucket(id: id)
            let _: Vessel? = s.vessel(id: id)
            let _: (owner: HierarchyItem, childID: UUID?)? = s.topLevelOwner(ofAnyID: id)
            let _: [Container] = s.allContainers()
            let _: [any SchedulableJob] = s.allJobs()
            let _: String = s.jobOwnerLabel(j)
            let _: String = s.label(for: id)
        })
        sigs.append({ (k: ItemKind) -> String in AppStore.kindLabel(k) })
        let _: [StepOwner] = [.procedure(UUID()), .crew(UUID())]
        let _: any (Sendable & Hashable).Type = StepOwner.self

        sigs.append({ (s: AppStore, a: HierarchyItem, e: Equipment, st: ChecklistStep, ids: [UUID]) in
            s.addRelation(a, a); s.removeRelation(a, a)
            let _: [HierarchyItem] = s.relatedItems(of: a)
            let _: [HierarchyItem] = s.referencedBy(a)
            s.purgeReferences(to: a.id)
            s.linkProcedures(ids, to: e); s.linkTasks(ids, to: e); s.linkTasks(ids, to: st); s.linkEquipment(ids, to: st)
        })
        sigs.append({ (s: AppStore, n: String, e: Equipment, st: ChecklistStep, t: TaskItem, p: Procedure, c: Component) in
            let _: HierarchyItem = s.createItem(kind: .task)
            let _: HierarchyItem = s.createItem(kind: .task, name: n)
            let _: Procedure = s.createLinkedProcedure(named: n, for: e)
            let _: TaskItem = s.createLinkedTask(named: n, for: e)
            let _: TaskItem = s.createLinkedTask(named: n, for: st)
            let _: TaskItem = s.addSubtask(named: n, to: t)
            let _: TaskItem = s.addSubtask(named: n, to: t, log: false)
            let _: ChecklistStep = s.addStep(titled: n, to: p)
            let _: ChecklistStep = s.addStep(titled: n, to: p, log: false)
            let _: Component = s.addComponent(named: n, to: e)
            let _: TaskItem = s.createTopLevelTask(named: n)
            let _: TaskItem = s.createTopLevelTask(named: n, logKind: nil)
            let _: Procedure = s.createTopLevelProcedure(named: n)
            s.removeSubtask(t, from: t); s.removeSubtask(t, from: t, log: false)
            s.removeStep(st, from: p); s.removeStep(st, from: p, log: false)
            s.removeComponent(c, from: e)
            s.createItem(kind: .vessel); s.addComponent(named: n, to: e)            // @discardableResult
        })
        #expect(AppStore.maxLogEntries == 10_000)
        sigs.append({ (s: AppStore, n: String?) in
            s.logAdded(kind: "", name: n); s.logAdded(kind: "", name: n, detail: nil)
            s.logRemoved(kind: "", name: n); s.logRemoved(kind: "", name: n, detail: "")
            s.clearLog()
        })
        #expect(AppStore.maxTrashItems == 200 && AppStore.trashRetentionDays == 90)
        sigs.append({ (s: AppStore, i: HierarchyItem, t: TaskItem, m: CrewMember, e: TrashedItem, b: UUID?, n: NetDateTime?) in
            let _: TrashedItem? = s.trash(i)
            let _: TrashedItem? = s.trash(i, batchID: b)
            let _: TrashedItem? = s.trashSubtask(t)
            let _: TrashedItem? = s.trashSubtask(t, batchID: b)
            let _: Int = s.trashItems([i])
            let _: TrashedItem = s.trash(m)
            let _: TrashedItem = s.trash(m, batchID: b)
            let _: Int = s.trashAllCrew()
            let _: TrashItemType? = s.restore(e)
            s.purge(e); s.emptyTrash()
            let _: Bool = s.pruneTrash()
            let _: Bool = s.pruneTrash(now: n)
            let _: Int = s.pendingUndoCount()
            let _: [TrashItemType] = s.undoLastDelete()
            s.hardDeleteTask(t); s.hardDelete(i)
            s.trash(i); s.trashItems([i]); s.trash(m); s.trashAllCrew(); s.pruneTrash()   // @discardableResult
        })
        sigs.append({ (d: NetDateTime, r: RecurrenceKind) -> NetDateTime in AppStore.nextOccurrence(from: d, r) })
        sigs.append({ (s: AppStore, t: CivilDate?) -> Bool in s.reconcileRecurrences(); return s.reconcileRecurrences(today: t) })
        sigs.append({ (s: AppStore, k: ItemKind, n: String, g: ItemGroup, i: [HierarchyItem], id: UUID?) in
            let _: [ItemGroup] = s.groups(for: k)
            let _: ItemGroup = s.createGroup(kind: k, name: n)
            s.createGroup(kind: k, name: n)
            s.renameGroup(g, to: n); s.deleteGroup(g); s.assign(i, toGroup: id)
        })
        #expect(sigs.count > 0)
    }

    // MARK: §6.5 Services and XLSX reader (F2)
    @Test func services() {
        var sigs: [Any] = []
        sigs.append({ (t: String?) -> NetDateTime? in NetDateParser.parse(t) })
        sigs.append({ (t: String?, z: TimeZone, d: CivilDate?) -> NetDateTime? in NetDateParser.parse(t, zone: z, today: d) })
        sigs.append({ (s: String) -> String in CrewText.norm(s) })
        sigs.append({ (c: XlsxCell, w: XlsxWorkbook, d: CivilDate) throws(XlsxReadError) -> [String] in
            [try XlsxRender.compasCellString(c, workbook: w), try XlsxRender.shippalmCell(c, workbook: w),
             try XlsxRender.portsCell(c, workbook: w), XlsxRender.getString(c), XlsxRender.shippalmExcelDate("", today: d)] })
        let _: [XlsxReadError] = [.gate(""), .message(""), .corrupt(detail: "")]
        let _: any (Error & LocalizedError & Sendable).Type = XlsxReadError.self
        let _: [any Sendable.Type] = [XlsxWorkbook.self, XlsxWorksheet.self, XlsxCell.self, XlsxValue.self,
                                      XlsxStyles.self, NumberKind.self]

        sigs.append({ (a: NetDateTime?, b: NetDateTime?, e: Bool) -> (start: NetDateTime?, deadline: NetDateTime?) in
            WorkRange.coerce(start: a, deadline: b, editedStart: e) })
        sigs.append({ (o: AnyObject?, os: [AnyObject], d: NetDateTime?) -> (Bool, Int, Bool, Int, NetDateTime??) in
            (BatchDone.setDone(o, done: true), BatchDone.setDoneAll(os, done: false),
             BatchDeadline.setDeadline(o, date: d), BatchDeadline.setDeadlineAll(os, date: d), BatchDeadline.sharedDeadline(of: os)) })
        sigs.append({ (d: BatchDelete.Description) -> (Int, Bool, String) in
            var x = d
            x.equipment = 0; x.tasks = 0; x.procedures = 0; x.vessels = 0; x.descendants = 0; x.withAttachments = 0
            x.linkedFromElsewhere = 0; x.locked = 0
            return (x.total, x.isEmpty, x.kindBreakdown()) })
        let _: any (Sendable & Equatable).Type = BatchDelete.Description.self
        sigs.append({ (sel: [AnyObject], s: AppStore, g: @escaping (HierarchyItem) -> Bool, d: BatchDelete.Description) in
            let _: [HierarchyItem] = BatchDelete.topLevel(sel)
            let _: BatchDelete.Description = BatchDelete.describe(sel, store: s, isGated: g)
            let _: String = BatchDelete.confirmationMessage(d, trashCount: 1)
            let _: (title: String, message: String)? = BatchDelete.nothingToDeleteMessage(d)
            let _: Int = BatchDelete.trashAll(sel, store: s, isGated: g)
            BatchDelete.trashAll(sel, store: s, isGated: g)
            let _: String = BatchDelete.statusAfterDelete(count: 1, firstName: "")
        })
        sigs.append({ (f: SearchField) -> (SearchHitKind, String, String, UUID?) in (f.kind, f.whereLabel, f.text, f.childID) })
        let _: [SearchHitKind] = [.item, .component, .subtask, .step, .file]
        #expect([SearchHitKind.item, .component, .subtask, .step, .file].map(\.rawValue)
                == ["Item", "Component", "Subtask", "Step", "File"])
        sigs.append({ (d: SearchDocument) -> (UUID, ItemKind, String, [SearchField]) in (d.ownerID, d.ownerKind, d.ownerHeader, d.fields) })
        sigs.append({ (h: SearchHit) -> (Int, UUID, ItemKind, String, SearchHitKind, String, String, Int, Int, UUID?) in
            (h.id, h.ownerID, h.ownerKind, h.ownerHeader, h.kind, h.whereLabel, h.snippet, h.matchStart, h.matchLength, h.childID) })
        let _: [any (Sendable & Hashable).Type] = [SearchField.self, SearchHit.self]
        let _: any Sendable.Type = SearchDocument.self
        #expect(SearchService.maxHits == 500)
        sigs.append({ (s: AppStore, g: @escaping (HierarchyItem) -> Bool, docs: [SearchDocument], q: String) in
            let _: [SearchDocument] = SearchService.makeDocuments(store: s, isGated: g)
            let _: [SearchHit] = SearchService.search(docs, query: q)
            let _: [SearchHit] = SearchService.search(docs, query: q, isCancelled: { false })
            let _: (snippet: String, start: Int) = SearchService.makeSnippet(text: q, matchIndex: 0, matchLength: 1)
        })
        sigs.append({ (r: QuickSwitcherScoring.Row) -> (UUID, String, ItemKind, String, [String], String) in
            (r.id, r.name, r.kind, r.kindLabel, r.tags, r.description) })
        sigs.append({ (s: AppStore, rows: [QuickSwitcherScoring.Row], q: String) in
            let _: [QuickSwitcherScoring.Row] = QuickSwitcherScoring.rows(store: s)
            let _: String = QuickSwitcherScoring.normalizeQuery(q)
            let _: Int = QuickSwitcherScoring.score(rows[0], query: q)
            let _: [QuickSwitcherScoring.Row] = QuickSwitcherScoring.rank(rows, query: q)
            let _: [QuickSwitcherScoring.Row] = QuickSwitcherScoring.rank(rows, query: q, limit: 5)
        })
        sigs.append({ (r: ReminderSummary) -> (Int, Int, Int, Int, Bool, String) in
            (r.overdue, r.dueToday, r.dueWeek, r.total, r.any, r.headline()) })
        let _: any (Sendable & Equatable).Type = ReminderSummary.self
        sigs.append({ (s: AppStore, d: CivilDate, r: ReminderSummary) -> (ReminderSummary, String, String) in
            (ReminderService.compute(store: s, today: d), ReminderService.dedupKey(r, crewExpiring: 0, today: d),
             ReminderService.notificationBody(r, crewExpiring: 0)) })
        sigs.append({ (all: inout [ChecklistTemplate], picks: [ChecklistTemplate], d: AppData, g: UUID?) in
            let _: [Int] = SavedListOrder.groupSpan(all, groupID: g)
            let _: Bool = SavedListOrder.nudge(&all, picks: picks, up: true)
            let _: Bool = SavedListOrder.moveTo(&all, picks: picks, targetInGroup: 0)
            let _: [(template: ChecklistTemplate, group: String?)]? = SavedListOrder.groupEntries(d, groupID: g)
            let _: [(template: ChecklistTemplate, group: String?)] = SavedListOrder.allEntries(d)
        })
        sigs.append({ (n: String, steps: inout [ChecklistStep], subs: inout [TaskItem], t: ChecklistTemplate,
                       i: ChecklistTemplateItem, c: Container?, f: FileItem) in
            let _: ChecklistTemplate = ChecklistTemplateService.captureFromSteps(name: n, steps: steps)
            let _: ChecklistTemplate = ChecklistTemplateService.captureFromSubtasks(name: n, subtasks: subs)
            let _: Int = ChecklistTemplateService.applyToSteps(t, steps: &steps, replace: true)
            let _: Int = ChecklistTemplateService.applyToSubtasks(t, subtasks: &subs, replace: false)
            ChecklistTemplateService.applyToSteps(t, steps: &steps, replace: true)
            let _: ChecklistTemplate = ChecklistTemplateService.clone(t, newName: n)
            let _: TaskItem = ChecklistTemplateService.itemToTask(i)
            let _: [ChecklistStep] = ChecklistTemplateService.toSteps(t)
            ChecklistTemplateService.writeBackFromSteps(t, steps: steps)
            let _: Container = ChecklistTemplateService.cloneContainer(c)
            let _: FileItem = ChecklistTemplateService.cloneFile(f)
        })
        let _: [ScheduleImportError] = [.notASchedule, .parse("")]
        let _: any (Error & LocalizedError & Sendable).Type = ScheduleImportError.self
        sigs.append({ (e: ScheduleEntry, n: String, m: CrewMember, d: AppData, t: ScheduleTemplate, data: Data) throws in
            let _: ScheduleEntry = ScheduleService.cloneEntry(e)
            let _: ScheduleTemplate = ScheduleService.captureFromCrew(name: n, crew: m, data: d)
            let _: Int = ScheduleService.applyToCrew(t, crew: m, replace: true)
            ScheduleService.applyToCrew(t, crew: m, replace: true)
            let _: Data = try ScheduleService.exportJSON(t)
        })
        sigs.append({ (d: Data) throws(ScheduleImportError) -> ScheduleTemplate in try ScheduleService.importJSON(d) })
        let _: [DiffNode.Change] = [.added, .removed, .changed]
        sigs.append({ (n: DiffNode) -> (UUID, DiffNode.Change, String, [DiffNode]) in (n.id, n.change, n.text, n.children) })
        let _: any (Sendable & Identifiable & Hashable).Type = DiffNode.self
        let r = DiffResult()
        #expect(!r.hasChanges && r.roots.isEmpty && r.added == 0 && r.removed == 0 && r.changed == 0)
        #expect(DiffResult(roots: [], added: 1, removed: 0, changed: 0).hasChanges)
        sigs.append({ (a: AppData, b: AppData, s: String?) -> (DiffResult, DiffResult, String) in
            (DataDiff.compare(current: a, incoming: b), DataDiff.compareOtherData(current: a, incoming: b), DataDiff.snip(s)) })
        sigs.append({ (a: NetDateTime?, b: NetDateTime?) -> String in AgeVerdict.text(incoming: a, current: b) })
        sigs.append({ (x: String) -> (String, String) in (XamlPlainText.searchText(x), XamlPlainText.diffText(x)) })
        #expect(sigs.count > 0)
    }

    // MARK: §6.6 W-PERSIST
    @Test func persist() {
        var sigs: [Any] = []
        let _: [ImportKind] = [.withAttachments, .dataOnly]
        sigs.append({ (ds: DataStore, u: URL) async throws in
            try await BundleService.exportFolderToZip(ds, to: u, includeAttachments: true)
            let _: ImportKind = try BundleService.importBundleSmart(ds, from: u)
            try BundleService.importSharedBundle(ds, from: u)
            try BundleService.importFolderFromZipLegacy(ds, from: u)
            let _: AppData? = BundleService.peekZipData(u, dataStore: ds)
            let _: AppData = try ds.applySyncedData(Data())
        })
        sigs.append({ (u: URL, k: SymmetricKey?) -> (NetDateTime?, NetDateTime?, BundleSource?, String) in
            (BundleService.peekZipLastModified(u), BundleService.peekFileLastModified(u, key: k),
             BundleService.peekBundleSource(u), BundleService.machineName()) })
        let _: (NetDateTime) -> String = BundleService.exportDefaultName
        #expect(BundleService.sharedDefaultName == "aa-shared.zip")
        sigs.append({ (ds: DataStore, u: URL, d: Data, a: AppData) throws in
            let _: String = try AttachmentStore.importFile(ds, from: u)
            let _: String = try AttachmentStore.importData(ds, d, suggestedName: "")
            let _: String = AttachmentStore.resolveFilePath(ds, stored: nil)
            AttachmentStore.normalizeFilePaths(ds, data: a)
            AttachmentStore.migrateLegacyAbsolutePaths(ds, data: a)
            let _: [Container] = AttachmentStore.enumerateContainers(a)
        })
        sigs.append({ (p: String) -> (FileKind, String) in (AttachmentStore.classify(path: p), AttachmentStore.windowsSafeLeaf(p)) })
        var pm = PathMapping(windowsPrefix: "Z:\\", macPath: "/Volumes/Z")
        pm.windowsPrefix = "Z:\\"; pm.macPath = "/"
        let _: any (Codable & Sendable & Hashable).Type = PathMapping.self
        let _: PathMapper = PathMapper.shared
        let _: ReferenceWritableKeyPath<PathMapper, [PathMapping]> = \.mappings
        sigs.append({ (m: PathMapper, s: String) -> (Bool, URL?, URL?) in
            (PathMapper.isWindowsPath(s), m.macURL(for: s), PathMapper.smbURL(forUNC: s)) })
        let _: [OpenOutcome] = [.opened, .notFound(""), .windowsPathUnmapped(""), .failed("")]
        sigs.append({ (s: String, ds: DataStore) -> (URL?, OpenOutcome, OpenOutcome, URL?) in
            (AttachmentOpener.url(forStored: s, isLink: false, dataStore: ds),
             AttachmentOpener.open(stored: s, isLink: false, dataStore: ds),
             AttachmentOpener.revealInFinder(stored: s, dataStore: ds), AttachmentOpener.normalizeWebLink(s)) })
        sigs.append({ (h: any SharedSaveHost) async in
            h.flushAllEditors(); h.captureUiState(); _ = await h.confirmReloadDiscardingChanges()
            h.reloadAfterSharedImport(identity: nil); h.postStatus("") })
        let _: [SharedSaveCoordinator.Health] = [.off, .online(lastSync: nil), .offline(since: Date()), .notSaving(since: Date())]
        sigs.append({ (s: AppStore, u: URL) async throws -> SharedSaveCoordinator in
            let c = SharedSaveCoordinator(store: s)
            c.host = nil
            let _: SharedSaveCoordinator.Health = c.health
            let _: (String, String, NetDateTime?, NetDateTime?) = (c.indicatorText, c.indicatorHelp, c.lastSeen, c.lastSynced)
            c.start(); c.stop(); await c.checkForUpdate(); try c.push(label: ""); c.pushInBackground(label: "")
            c.pushOnCloseIfNeeded(); try await c.adoptSharedFile(u, useItsContents: true); c.stopUsing()
            return c })
        let _: [InstanceGuardResult] = [.editor, .unguarded(""), .runningHere(pid: 1), .otherUser(""),
                                        .remote(host: "", lastSeen: Date(), stale: false)]
        sigs.append({ (u: URL) in
            let _: InstanceGuardResult = InstanceGuard.acquire(appFolder: u)
            let _: Bool = InstanceGuard.forwardToRunningInstance(pid: 1, documents: [u])
            InstanceGuard.listenForForwardedDocuments { (_: [URL]) in }
            InstanceGuard.release()
            let _: InstanceGuardResult = InstanceGuard.acquireExternal(fileURL: u)
            InstanceGuard.releaseExternal()
        })
        sigs.append({ (s: AppStore, h: any DataFileConflictHost) -> DataFileWriteGuard in
            let f = DataFileFingerprint(store: s, host: h)
            f.start(); f.stop()
            return f })
        let _: [DataFileConflict.Kind] = [.changed, .deleted, .unreadable(reason: "")]
        var conflict = DataFileConflict(kind: .changed, fileName: "", ourTime: "", theirTime: "", theirBytes: nil)
        conflict.kind = .deleted; conflict.fileName = ""; conflict.ourTime = ""; conflict.theirTime = ""; conflict.theirBytes = nil
        let _: [DataFileConflictChoice] = [.keepMine, .useTheirs, .stopEditingHere]
        sigs.append({ (h: any DataFileConflictHost, c: DataFileConflict) async -> DataFileConflictChoice in await h.presentConflict(c) })
        let entry = ConflictCopies.Entry(fileName: "a", isTheirs: true, size: 1, lastModified: nil)
        #expect(entry.id == "a")
        sigs.append({ (ds: DataStore, e: ConflictCopies.Entry) -> ([ConflictCopies.Entry], URL) in
            (ConflictCopies.list(ds), ConflictCopies.url(of: e, ds)) })
        #expect(sigs.count > 0)
    }

    // MARK: §6.7 W-RICH
    @Test func richText() {
        var sigs: [Any] = []
        let _: XamlRootRole? = nil
        let _: [XamlFontStyle] = [.normal, .italic, .oblique]
        let _: [XamlTextAlignment] = [.left, .right, .center, .justify]
        let _: [XamlLineStacking] = [.maxHeight, .blockLineHeight]
        let _: [XamlFlowDirection] = [.leftToRight, .rightToLeft]
        let _: [XamlBaselineAlignment] = [.top, .center, .bottom, .baseline, .textTop, .textBottom, .subscript, .superscript]
        let _: XamlDecorations = [.underline, .strikethrough, .overLine, .baseline]
        let _: [XamlLockSource] = [.inlineRun, .inlineAncestor, .block]
        let ff = XamlFontFamily(raw: "Consolas")
        let _: (String, String) = (ff.raw, ff.canon)
        var th = XamlThickness(left: 0, top: 0, right: 0, bottom: 0)
        th.left = 1; th.top = 1; th.right = 1; th.bottom = 1
        #expect(XamlProperty.allCases.count == 14)
        var lv = XamlLocalValues()
        lv.fontFamily = ff; lv.fontSize = nil; lv.fontWeight = nil; lv.fontWeightToken = nil; lv.fontStyle = nil
        lv.fontStyleToken = nil; lv.fontStretch = nil; lv.foreground = nil; lv.textAlignment = nil; lv.lineHeight = nil
        lv.lineStackingStrategy = nil; lv.flowDirection = nil; lv.language = nil; lv.isHyphenationEnabled = nil
        lv.typography = [:]; lv.numberSubstitution = [:]; lv.background = nil; lv.textDecorations = nil
        lv.baselineAlignment = nil; lv.margin = th; lv.padding = nil; lv.borderThickness = nil; lv.borderBrush = nil
        lv.textIndent = nil; lv.keepTogether = nil; lv.markerStyle = nil; lv.startIndex = nil; lv.markerOffset = nil
        lv.cellSpacing = nil; lv.columnSpan = nil; lv.rowSpan = nil; lv.width = nil; lv.navigateUri = nil; lv.targetName = nil
        sigs.append({ (p: XamlPropertyElement) -> (String, String, String, XamlBrush?) in (p.ownerName, p.propertyName, p.rawXML, p.brush) })
        let _: [XamlIssue] = [.unknownElement(""), .invalidNesting(""), .textInBlockContainer, .invalidValue(property: "", value: ""),
                              .duplicateProperty(""), .runTextAndContent, .markupExtension(""), .unknownAttribute("")]
        let _: [XamlFatalError] = [.malformedXML(""), .dtdPresent, .wrongRootNamespace(nil)]
        sigs.append({ (c: XamlComputedStyle) -> [XamlProperty: XamlNodeID] in
            _ = (c.fontFamily, c.fontSize, c.fontWeight, c.fontStyle, c.fontStretch, c.foreground, c.textAlignment,
                 c.lineHeight, c.lineStackingStrategy, c.flowDirection, c.language, c.isHyphenationEnabled,
                 c.typography, c.numberSubstitution)
            return c.setter })
        let keys: [NSAttributedString.Key] = [.aaLocked, .aaLockSource, .aaListMarker, .aaListItemID, .aaListContinuation,
            .aaHyperlink, .aaXmlLang, .aaFontFamilyName, .aaFontWeightToken, .aaFontStyleToken, .aaInheritedExtras,
            .aaLinkStyled, .aaUnderlyingForeground, .aaForegroundBrushXml, .aaBackgroundBrushXml, .aaExtraDecorations,
            .aaBaselineAlignment, .aaParagraphAttrs, .aaExtraAttributes, .aaSectionPath, .aaTableRowGroup,
            .aaPreservedXaml, .aaInRunNewline]
        #expect(Set(keys).count == 23)
        let _: XamlElementID = ""
        let contexts: [XamlContext] = [.containerEditor, .containerViewer, .pdf, .sirePane]
        var md = RichTextMetadata(context: contexts[0])
        md.rootAttributes = []; md.rootRole = nil; md.elementAttributes = [:]; md.hyperlinkAttributes = [:]
        md.context = contexts[1]; md.hasAnyLock = false; md.sourceHash = 0; md.isPlaceholderResult = false
        let _: XamlLoadability = md.loadability
        sigs.append({ (o: XamlReadOutcome) -> Int in
            switch o { case .empty(let m): return m.sourceHash
                       case .document(let s, _): return s.length
                       case .unparseable(let raw): return raw.count } })
        sigs.append({ (x: String, c: XamlContext, s: NSAttributedString, m: RichTextMetadata) -> (XamlReadOutcome, NSAttributedString?, String, String) in
            (XamlReader.read(x, context: c), XamlReader.readFragment(x, destinationContext: c),
             XamlWriter.write(s, metadata: m, context: c), XamlWriter.emptyDocument()) })
        sigs.append({ (h: String) -> String in HTMLToXAML.convert(h) })
        let _: [RichListFormatter.ListKind] = [.bullets, .numbered]
        sigs.append({ (s: NSTextStorage, r: NSRange) in
            let _: NSRange = RichListFormatter.toggleList(.bullets, in: s, selection: r)
            RichListFormatter.normalise(s)
            let _: NSRange = RichListFormatter.indent(s, selection: r)
            let _: NSRange = RichListFormatter.outdent(s, selection: r)
            let _: NSRange? = RichListFormatter.handleTab(s, selection: r, shift: false)
            let _: NSRange? = RichListFormatter.handleReturn(s, selection: r)
            let _: NSRange? = RichListFormatter.handleBackspaceAtItemStart(s, selection: r)
            let _: NSRange? = RichListFormatter.moveItem(s, selection: r, up: true)
            let _: NSRange = RichListFormatter.insertList(lines: [], kind: .numbered, into: s, at: r)
            let _: Bool = RichListFormatter.isAtItemStart(s, location: 0)
        })
        #expect(LockRules.sentinel == ARGB(a: 0xFF, r: 0xFF, g: 0xE6, b: 0x99))
        sigs.append({ (s: NSAttributedString, r: NSRange, x: String) -> (Bool, [NSRange], Bool) in
            (LockRules.blocksEdit(s, range: r, replacementLength: 0), LockRules.lockedRanges(s, touching: r),
             LockRules.quickHasAnyLock(x)) })
        #expect(sigs.count > 0)
    }

    // MARK: §6.8 other wave-owned AACore contracts
    @Test func otherWaveContracts() {
        var sigs: [Any] = []
        #expect(CrewExpiry.warnDays == 60 && CrewExpiry.criticalDays == 30)
        sigs.append({ (c: [CrewMember], d: CivilDate, n: Int) -> (Int, String) in
            (CrewExpiry.expiringCount(c, today: d), CrewExpiry.badgeText(n)) })
        let icon = MaritimeIcons.all.first
        let _: (String, String)? = icon.map { ($0.glyph, $0.name) }
        let _: [String] = MaritimeIcons.palette
        let _: any (Sendable & Hashable).Type = MaritimeIcons.Icon.self
        sigs.append({ (s: String?, c: ARGB) -> (ARGB, Bool) in (MaritimeIcons.parseColor(s), MaritimeIcons.readableForegroundIsDark(c)) })
        sigs.append({ (t: String, tags: [String]) -> ([String], String, Bool) in
            (TagParser.parse(t), TagParser.display(tags), TagParser.matches(tags, hashQuery: t)) })
        sigs.append({ (s: SecretStore, st: SettingsStore) throws -> GeminiKeyStore in
            let g = GeminiKeyStore(secrets: s, settings: st)
            let _: (Bool, String?) = (g.hasKey, g.key())
            try g.setKey(nil); g.importFromSettingsOnce()
            return g })
        sigs.append({ (ds: DataStore) -> (Bool, Bool) in
            (GoogleTokenStore.hasToken(ds), GoogleTokenStore.needsReconsentForWholeDrive(ds)) })
        sigs.append({ (n: String, m: String?) -> Bool in BundleName.isRestorable(name: n, mimeType: m) })
        #expect(sigs.count > 0)
    }
}
