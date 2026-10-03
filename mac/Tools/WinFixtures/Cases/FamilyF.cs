// Family (f) extension families — X01–X06, SHOULD (spec 01 GF.5.f, DATA-320). X07 (Flash Sync) is NOT duplicated:
// Tests/FlashSync.Interop already produces the protocol vectors (13 §7).
using System.Globalization;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using AA.Models;
using AA.Services;
using AA.Sire;
using ClosedXML.Excel;
using static WinFixtures.Corpora;
using static WinFixtures.Fx;

namespace WinFixtures;

internal static class FamilyF
{
    private const string F = "ext";

    private static JsonArray Ids(IEnumerable<Guid> ids) => new(ids.Select(g => (JsonNode?)g.ToString("D")).ToArray());
    private static JsonArray Names(IEnumerable<HierarchyItem> items) => new(items.Select(i => (JsonNode?)i.Name).ToArray());
    private static JsonNode? DateNode(DateTime? d) =>
        d is DateTime v ? new JsonObject { ["ticks"] = v.Ticks, ["kind"] = v.Kind.ToString() } : null;

    public static IEnumerable<CaseDef> Cases()
    {
        // ---- X01 AppRepository -----------------------------------------------------------------------------------
        yield return new CaseDef
        {
            Id = "X01.rel", Family = F, Normative = "should", Compare = "json-semantic",
            Title = "AppRepository relations and lookups (02 T-REL-1…11)", Settles = new[] { "02 §7.1" },
            Run = r =>
            {
                var o = new JsonObject();
                { var d = new AppData(); var a = MkTask(3, "A"); var b = MkTask(5, "B"); d.Tasks.Add(a); d.Tasks.Add(b); var repo = new AppRepository(d);
                  repo.AddRelation(a, b); repo.AddRelation(a, b); o["T-REL-1"] = new JsonObject { ["A"] = Ids(a.RelatedIds), ["B"] = Ids(b.RelatedIds) };
                  repo.AddRelation(a, a); o["T-REL-2"] = Ids(a.RelatedIds);
                  repo.RemoveRelation(a, b); o["T-REL-3"] = new JsonObject { ["A"] = Ids(a.RelatedIds), ["B"] = Ids(b.RelatedIds) }; }
                { var d = new AppData(); var e = Equip(1, "E"); var v = Ship(8, "V"); var p = Proc(4, "P"); var t = MkTask(3, "T");
                  e.RelatedIds.Add(v.Id); e.ProcedureIds.Add(p.Id); e.TaskIds.Add(t.Id); e.TaskIds.Add(v.Id);
                  d.Equipment.Add(e); d.Vessels.Add(v); d.Procedures.Add(p); d.Tasks.Add(t);
                  o["T-REL-4"] = Names(new AppRepository(d).RelatedItems(e)); }
                { var d = new AppData(); var p = Proc(4, "P"); var s = Step(7, "s"); s.TaskIds.Add(G(3)); p.Steps.Add(s); d.Procedures.Add(p); d.Tasks.Add(MkTask(3, "T"));
                  o["T-REL-5"] = Names(new AppRepository(d).RelatedItems(p)); }
                { var d = new AppData(); var t = MkTask(3, "T"); var e = Equip(1, "E"); e.TaskIds.Add(t.Id); var p = Proc(4, "P"); var s = Step(7, "s"); s.TaskIds.Add(t.Id); p.Steps.Add(s);
                  var x = Ship(8, "X"); x.RelatedIds.Add(t.Id); d.Equipment.Add(e); d.Tasks.Add(t); d.Procedures.Add(p); d.Vessels.Add(x);
                  var repo = new AppRepository(d); o["T-REL-6"] = new JsonObject { ["referencedBy"] = Names(repo.ReferencedBy(t)), ["related"] = Names(repo.RelatedItems(t)) }; }
                { var d = new AppData(); var e = Equip(1, "E"); var p = Proc(4, "P"); e.ProcedureIds.Add(p.Id); d.Equipment.Add(e); d.Procedures.Add(p);
                  var repo = new AppRepository(d); repo.TrashHierarchyItem(p);
                  o["T-REL-7"] = new JsonObject { ["label"] = repo.Label(G(4)), ["related"] = Names(repo.RelatedItems(e)) }; }
                { var d = new AppData(); d.Tasks.Add(MkTask(3, "Pump")); o["T-REL-8"] = new AppRepository(d).Label(G(3)); }
                { var d = new AppData(); var dd = G(77);
                  var e = Equip(1, "E"); e.RelatedIds.Add(dd); e.ProcedureIds.Add(dd); d.Equipment.Add(e);
                  var p = Proc(4, "P"); var s = Step(7, "s"); s.EquipmentIds.Add(dd); p.Steps.Add(s); d.Procedures.Add(p);
                  var crew = new CrewMember { Id = G(11) }; var cs = Step(12, "cs"); var f = MkFile(201, "f", "files/f"); f.LinkedItemIds.Add(dd); cs.Container.Files.Add(f); crew.Checklist.Add(cs); d.Crew.Add(crew);
                  var t = MkTask(3, "T"); var sub = MkTask(5, "S"); sub.RelatedIds.Add(dd); t.Subtasks.Add(sub); d.Tasks.Add(t);
                  new AppRepository(d).PurgeReferences(dd);
                  o["T-REL-9"] = new JsonObject { ["E.RelatedIds"] = Ids(e.RelatedIds), ["E.ProcedureIds"] = Ids(e.ProcedureIds), ["step.EquipmentIds"] = Ids(s.EquipmentIds),
                                                  ["crewFile.LinkedItemIds"] = Ids(f.LinkedItemIds), ["subtask.RelatedIds"] = Ids(sub.RelatedIds) }; }
                { var d = new AppData(); d.Equipment.Add(Equip(3, "Equipment Z")); d.Tasks.Add(MkTask(3, "Task Z"));
                  o["T-REL-10"] = new AppRepository(d).FindById(G(3))?.Name; }
                { var d = new AppData(); var t = MkTask(3, "T"); t.IsJob = true; var s = MkTask(5, "S"); s.IsJob = true; s.Subtasks.Add(MkTask(6, "SS")); t.Subtasks.Add(s); d.Tasks.Add(t);
                  var p = Proc(4, "P"); var s1 = Step(71, "s1"); s1.IsJob = true; p.Steps.Add(s1); p.Steps.Add(Step(72, "s2")); d.Procedures.Add(p);
                  var crew = new CrewMember { Id = G(11) }; var cs = Step(12, "cs"); cs.IsJob = true; crew.Checklist.Add(cs); d.Crew.Add(crew);
                  o["T-REL-11"] = new JsonArray(new AppRepository(d).AllJobs().Select(j => (JsonNode?)j.JobName).ToArray()); }
                r.Json("result", "relations", o);
            },
        };

        yield return new CaseDef
        {
            Id = "X01.rec", Family = F, Normative = "should", Compare = "json-semantic",
            Title = "AppRepository recurrence (02 T-REC-1…6, 8…12; the undated T-REC-7 is X01.recToday)", Settles = new[] { "02 §7.4", "01 §7.11" },
            Run = r =>
            {
                var o = new JsonObject();
                DateTime Next(DateTime d, RecurrenceKind k) => Call<DateTime>(typeof(AppRepository), "NextOccurrence", d, k);
                o["T-REC-1"] = DateNode(Next(Day(2026, 1, 31), RecurrenceKind.Monthly));
                o["T-REC-2"] = DateNode(Next(Day(2024, 2, 29), RecurrenceKind.Yearly));
                o["T-REC-3"] = new JsonArray(DateNode(Next(Day(2026, 12, 31), RecurrenceKind.Daily)), DateNode(Next(Day(2026, 9, 29), RecurrenceKind.Weekly)),
                                             DateNode(Next(Day(2026, 9, 29), RecurrenceKind.None)));
                o["T-REC-4"] = DateNode(Next(new DateTime(2026, 3, 31, 9, 30, 0), RecurrenceKind.Monthly));

                var d = new AppData();
                var src = MkTask(3, "Fire drill"); src.Recurrence = RecurrenceKind.Monthly; src.Deadline = Day(2026, 1, 31); src.RangeStart = Day(2026, 1, 29);
                var s = MkTask(5, "S"); s.Deadline = Day(2026, 1, 30); s.RangeStart = Day(2026, 1, 28); s.IsComplete = true;
                var u = MkTask(6, "U"); u.Status = WorkStatus.InProgress;
                src.Subtasks.Add(s); src.Subtasks.Add(u); src.Container.Files.Add(MkFile(201, "f.pdf", "files/f.pdf"));
                src.IsComplete = true;
                var same = MkTask(13, "Same-day range"); same.Recurrence = RecurrenceKind.Weekly; same.RangeStart = Day(2026, 10, 5); same.Deadline = Day(2026, 10, 5); same.IsComplete = true;
                var spawned = MkTask(14, "Already spawned"); spawned.Recurrence = RecurrenceKind.Daily; spawned.IsComplete = true; spawned.RecurrenceSpawned = true;
                var open = MkTask(15, "Not complete"); open.Recurrence = RecurrenceKind.Daily;
                var parent = MkTask(16, "Parent"); var rsub = MkTask(17, "Recurring subtask"); rsub.Recurrence = RecurrenceKind.Daily; rsub.IsComplete = true; parent.Subtasks.Add(rsub);
                d.Tasks.Add(src); d.Tasks.Add(same); d.Tasks.Add(spawned); d.Tasks.Add(open); d.Tasks.Add(parent);
                var p = Proc(4, "Weekly checks"); p.Recurrence = RecurrenceKind.Weekly; p.Deadline = Day(2026, 9, 28); p.Status = WorkStatus.Done;
                var st1 = Step(71, "step1"); st1.Done = true; st1.Deadline = Day(2026, 9, 27); st1.TaskIds.Add(G(3)); var st2 = Step(72, "step2");
                p.Steps.Add(st1); p.Steps.Add(st2); d.Procedures.Add(p);
                var baseline = DataStore.SerializeForSave(JsonSerializer.Deserialize<AppData>(JsonSerializer.Serialize(d, Opts), Opts)!);
                r.InputFile($"{r.Id}.data.input.json", JsonSerializer.Serialize(d, Opts), "data");
                var repo = new AppRepository(d);
                o["first"] = repo.ReconcileRecurrences();
                o["second"] = repo.ReconcileRecurrences();
                r.Json("result", "recurrence", o);
                var bytes = DataStore.SerializeForSave(d);
                r.Mask.AutoMask(bytes, baseline);
                r.Text("bytes", "appdata", "json", bytes, "bytes-masked");
            },
        };

        yield return new CaseDef
        {
            Id = "X01.recToday", Family = F, Normative = "record-only", Compare = "json-semantic", DependsOnToday = true,
            Title = "AppRepository recurrence of an undated daily task (T-REC-7: Deadline = DateTime.Today, Local)",
            Settles = new[] { "02 §7.4", "01 §7.11" },
            Run = r =>
            {
                var d = new AppData();
                var daily = MkTask(9, "Daily undated"); daily.Recurrence = RecurrenceKind.Daily;
                var dsub = MkTask(12, "sub"); dsub.Deadline = Day(2026, 9, 1); daily.Subtasks.Add(dsub); daily.IsComplete = true;
                d.Tasks.Add(daily);
                var repo = new AppRepository(d);
                var spawned = repo.ReconcileRecurrences();
                var clone = d.Tasks.Last();
                r.Json("result", "recurrence-today", new JsonObject
                {
                    ["spawned"] = spawned, ["today"] = DateTime.Today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                    ["cloneDeadline"] = DateNode(clone.Deadline), ["cloneRangeStart"] = DateNode(clone.RangeStart),
                    ["cloneSubtaskDeadline"] = DateNode(clone.Subtasks.FirstOrDefault()?.Deadline),
                    ["log"] = d.Log.LastOrDefault()?.Detail,
                }, mac: false);
            },
        };

        yield return new CaseDef
        {
            Id = "X01.tr", Family = F, Normative = "should", Compare = "json-semantic",
            Title = "AppRepository trash and undo (02 T-TR-1…16)", Settles = new[] { "02 §7.5", "01 §7.11" },
            Run = r =>
            {
                var o = new JsonObject();
                // T-TR-1/2: trash + restore keeps the relation graph.
                { var d = new AppData(); var t = MkTask(3, "T"); var e = Equip(1, "E"); t.RelatedIds.Add(e.Id); e.RelatedIds.Add(t.Id); e.TaskIds.Add(t.Id);
                  d.Tasks.Add(t); d.Equipment.Add(e); var repo = new AppRepository(d);
                  var ti = repo.TrashHierarchyItem(t)!;
                  o["T-TR-1"] = new JsonObject { ["ItemType"] = ti.ItemType, ["ItemId"] = ti.ItemId.ToString("D"), ["KindLabel"] = ti.KindLabel,
                                                 ["BatchIdEmpty"] = ti.BatchId == Guid.Empty, ["E.RelatedIds"] = Ids(e.RelatedIds), ["E.TaskIds"] = Ids(e.TaskIds),
                                                 ["tasks"] = d.Tasks.Count, ["log"] = d.Log.Last().Action + " / " + d.Log.Last().Kind + " / " + d.Log.Last().Name + " / " + d.Log.Last().Detail };
                  var back = repo.RestoreTrash(ti);
                  o["T-TR-2"] = new JsonObject { ["returned"] = back, ["tasks"] = d.Tasks.Count, ["trash"] = d.Trash.Count, ["related"] = Names(repo.RelatedItems(e)),
                                                 ["log"] = d.Log.Last().Action + " / " + d.Log.Last().Kind + " / " + d.Log.Last().Name + " / " + d.Log.Last().Detail }; }
                // T-TR-4/5
                { var d = new AppData(); var repo = new AppRepository(d);
                  var bad = new TrashedItem { ItemType = "Task", ItemId = G(3), PayloadJson = "{", DeletedUtc = DateTime.UtcNow };
                  var widget = new TrashedItem { ItemType = "Widget", ItemId = G(5), PayloadJson = "{}", DeletedUtc = DateTime.UtcNow };
                  d.Trash.Add(bad); d.Trash.Add(widget);
                  o["T-TR-4"] = new JsonObject { ["returned"] = repo.RestoreTrash(bad), ["kept"] = d.Trash.Contains(bad) };
                  o["T-TR-5"] = repo.RestoreTrash(widget); }
                // T-TR-6/7/8: batches and undo.
                { var d = new AppData(); var a = MkTask(3, "A"); var b = MkTask(5, "B"); var c = MkTask(6, "C"); d.Tasks.Add(a); d.Tasks.Add(b); d.Tasks.Add(c);
                  var repo = new AppRepository(d);
                  var n = repo.TrashHierarchyItems(new HierarchyItem[] { a, b, c });
                  var batchIds = d.Trash.Select(t => t.BatchId).Distinct().ToList();
                  o["T-TR-6"] = new JsonObject { ["returned"] = n, ["entries"] = d.Trash.Count, ["sharedBatch"] = batchIds.Count == 1 && batchIds[0] != Guid.Empty };
                  o["T-TR-7.pending"] = repo.PendingUndoCount();
                  var types = repo.UndoLastDelete();
                  o["T-TR-7"] = new JsonObject { ["types"] = new JsonArray(types.Select(x => (JsonNode?)x).ToArray()), ["tasks"] = Names(d.Tasks), ["trash"] = d.Trash.Count };
                  o["T-TR-10"] = new JsonArray(repo.UndoLastDelete().Select(x => (JsonNode?)x).ToArray()); }
                // T-TR-11/13: prune by age.
                { var d = new AppData(); var e = Equip(1, "E"); e.RelatedIds.Add(G(90)); e.RelatedIds.Add(G(91)); d.Equipment.Add(e);
                  d.Trash.Add(new TrashedItem { ItemType = "Task", ItemId = G(90), DeletedUtc = DateTime.UtcNow.AddDays(-91), PayloadJson = "{}" });
                  d.Trash.Add(new TrashedItem { ItemType = "Task", ItemId = G(91), DeletedUtc = DateTime.UtcNow.AddDays(-89), PayloadJson = "{}" });
                  var repo = new AppRepository(d); repo.PruneTrash();
                  o["T-TR-11/13"] = new JsonObject { ["trash"] = d.Trash.Count, ["E.RelatedIds"] = Ids(e.RelatedIds), ["dirty"] = repo.IsDirty }; }
                // T-TR-12: the 200 cap.
                { var d = new AppData(); var repo = new AppRepository(d);
                  for (int i = 0; i < 200; i++) d.Trash.Add(new TrashedItem { ItemType = "Task", ItemId = G(2000 + i), DeletedUtc = DateTime.UtcNow.AddMinutes(-300 + i), PayloadJson = "{}" });
                  var t = MkTask(3, "new"); d.Tasks.Add(t); repo.TrashHierarchyItem(t);
                  o["T-TR-12"] = new JsonObject { ["trash"] = d.Trash.Count, ["oldestGone"] = d.Trash.All(x => x.ItemId != G(2000)) }; }
                // T-TR-14/15: crew.
                { var d = new AppData(); var m = new CrewMember { Id = G(11), FirstName = "Jan", LastName = "Kowalski" }; var blank = new CrewMember { Id = G(12) };
                  d.Crew.Add(m); d.Crew.Add(blank); var repo = new AppRepository(d);
                  var ti = repo.TrashCrew(m); var tb = repo.TrashCrew(blank);
                  o["T-TR-14"] = new JsonObject { ["Name"] = ti.Name, ["KindLabel"] = ti.KindLabel, ["ItemType"] = ti.ItemType, ["restored"] = repo.RestoreTrash(ti), ["crew"] = d.Crew.Count };
                  o["T-TR-15"] = new JsonObject { ["Name"] = tb.Name, ["Display"] = tb.Display.Split("   ·   ")[0] }; }
                // T-TR-16: purge / empty.
                { var d = new AppData(); var e = Equip(1, "E"); var t = MkTask(3, "T"); e.TaskIds.Add(t.Id); d.Equipment.Add(e); d.Tasks.Add(t);
                  var repo = new AppRepository(d); var ti = repo.TrashHierarchyItem(t)!;
                  repo.PurgeTrash(ti);
                  var empty = new AppRepository(new AppData()); empty.EmptyTrash();
                  o["T-TR-16"] = new JsonObject { ["E.TaskIds"] = Ids(e.TaskIds), ["trash"] = d.Trash.Count, ["emptyOnEmptyDirty"] = empty.IsDirty }; }
                r.Json("result", "trash", o);
            },
        };

        yield return new CaseDef
        {
            Id = "X01.log", Family = F, Normative = "should", Compare = "json-semantic",
            Title = "activity log and groups (02 T-LOG-1…3/5, T-GRP-1…3)", Settles = new[] { "02 §7.12", "02 §7.13" },
            Run = r =>
            {
                var d = new AppData(); var repo = new AppRepository(d);
                repo.LogAdded("Task", "  Pump  "); repo.LogRemoved("Task", "   ");
                var first = d.Log[0]; var second = d.Log[1];
                for (int i = 0; i < 10_000; i++) repo.LogAdded("Task", "n" + i);
                var grp = repo.CreateGroup(ItemKind.Task, "  ");
                repo.RenameGroup(grp, "");
                var e = Equip(1, "E"); var t = MkTask(3, "T"); e.GroupId = grp.Id; t.GroupId = grp.Id; d.Equipment.Add(e); d.Tasks.Add(t);
                repo.DeleteGroup(grp);
                r.Json("result", "log-groups", new JsonObject
                {
                    ["T-LOG-1"] = new JsonObject { ["Name"] = first.Name, ["Detail"] = first.Detail, ["Action"] = first.Action, ["Kind"] = first.TimestampUtc.Kind.ToString() },
                    ["T-LOG-2"] = second.Name,
                    ["T-LOG-3"] = new JsonObject { ["count"] = d.Log.Count, ["firstName"] = d.Log[0].Name },
                    ["T-LOG-5"] = new LogEntry { TimestampUtc = new DateTime(2026, 9, 29, 8, 15, 30, DateTimeKind.Utc) }.TimeUtc,
                    ["T-GRP-1"] = new JsonObject { ["Name"] = grp.Name, ["Kind"] = (int)grp.Kind },
                    ["T-GRP-3"] = new JsonObject { ["E.GroupId"] = e.GroupId?.ToString("D"), ["T.GroupId"] = t.GroupId?.ToString("D"), ["groups"] = d.Groups.Count },
                });
            },
        };

        // ---- X02 ChecklistTemplateService ----------------------------------------------------------------------------
        yield return new CaseDef
        {
            Id = "X02", Family = F, Normative = "should", Compare = "json-semantic",
            Title = "ChecklistTemplateService capture/apply/clone (02 T-TPL-1…9)", Settles = new[] { "02 §7.10", "06 §7.10" },
            Run = r =>
            {
                var step = Step(7, "Check oil"); step.DurationMinutes = 15; step.IsJob = true; step.Done = true; step.Deadline = Day(2026, 10, 5);
                step.TaskIds.Add(G(3)); step.Container.RichTextXaml = Xaml("X"); var f1 = MkFile(201, "f1.pdf", "files/f1.pdf"); f1.LinkedItemIds.Add(G(1)); step.Container.Files.Add(f1);
                var tpl = ChecklistTemplateService.CaptureFromSteps("  Daily rounds ", new[] { step });
                var s1 = MkTask(5, "S1"); s1.Description = "d"; s1.Subtasks.Add(MkTask(6, "S1a"));
                var tpl2 = ChecklistTemplateService.CaptureFromSubtasks("L", new[] { s1 });
                var target = new System.Collections.ObjectModel.ObservableCollection<ChecklistStep> { Step(70, "s0") };
                var two = ChecklistTemplateService.CaptureFromSteps("two", new[] { Step(71, "n1"), Step(72, "n2") });
                var applied = ChecklistTemplateService.ApplyToSteps(two, target, replace: false);
                var subs = new System.Collections.ObjectModel.ObservableCollection<TaskItem> { MkTask(80, "x"), MkTask(81, "y") };
                var appliedSubs = ChecklistTemplateService.ApplyToSubtasks(two, subs, replace: true);
                var locked = new Container { Id = G(150), IsLocked = true, RichTextXaml = "enc:QUJD" };
                var cloneLocked = ChecklistTemplateService.CloneContainer(locked);
                var cloneNull = ChecklistTemplateService.CloneContainer(null);
                var item = ChecklistTemplateService.ItemToTask(tpl.Items[0]);
                // Everything the service created is new by design (ids, CreatedUtc): mask what the sources lack.
                var baseline = string.Join("\n", JsonSerializer.Serialize(step, Opts), JsonSerializer.Serialize(s1, Opts), JsonSerializer.Serialize(locked, Opts));
                var probe = string.Join("\n", JsonSerializer.Serialize(tpl, Opts), JsonSerializer.Serialize(tpl2, Opts), JsonSerializer.Serialize(item, Opts),
                                        JsonSerializer.Serialize(cloneNull, Opts), JsonSerializer.Serialize(cloneLocked, Opts));
                r.Mask.AutoMask(probe, baseline);
                r.Json("result", "templates", new JsonObject
                {
                    ["T-TPL-1"] = JsonNode.Parse(JsonSerializer.Serialize(tpl, Opts)),
                    ["T-TPL-2"] = JsonNode.Parse(JsonSerializer.Serialize(tpl2, Opts)),
                    ["T-TPL-3"] = new JsonObject { ["returned"] = applied, ["titles"] = new JsonArray(target.Select(x => (JsonNode?)x.Title).ToArray()), ["done"] = new JsonArray(target.Select(x => (JsonNode?)x.Done).ToArray()) },
                    ["T-TPL-4"] = new JsonObject { ["returned"] = appliedSubs, ["names"] = new JsonArray(subs.Select(x => (JsonNode?)x.Name).ToArray()), ["status"] = new JsonArray(subs.Select(x => (JsonNode?)(int)x.Status).ToArray()) },
                    ["T-TPL-6"] = JsonNode.Parse(JsonSerializer.Serialize(item, Opts)),
                    ["T-TPL-8"] = JsonNode.Parse(JsonSerializer.Serialize(cloneNull, Opts)),
                    ["T-TPL-9"] = JsonNode.Parse(JsonSerializer.Serialize(cloneLocked, Opts)),
                });
            },
        };

        // ---- X03 ScheduleService export/import ---------------------------------------------------------------------------
        yield return new CaseDef
        {
            Id = "X03", Family = F, Runs = Runs.Both, Normative = "record-only", NormativeWindows = "should",
            Title = "ScheduleService.ExportJson (indented, Environment.NewLine) / ImportJson", Settles = new[] { "06 §7.11", "02 §7.11" },
            Run = r =>
            {
                var t = new ScheduleTemplate { Id = G(23), Name = "Café rota", VesselId = G(8), VesselName = "Alpha", CreatedUtc = D_Z };
                t.Entries.Add(new ScheduleEntry { Id = G(24), Title = "Watch", Kind = ScheduleKind.Task, RefId = G(3), Date = "2026-10-01", Time = "08:00", Notes = "é" });
                t.Entries.Add(new ScheduleEntry { Id = G(25), Title = "Free", Date = "2026-10-02" });
                var path = Path.Combine(r.DataDir, "rota.aasched.json");
                ScheduleService.ExportJson(t, path);
                r.Text("export", "export", "json", System.IO.File.ReadAllText(path), "bytes");
                var imported = ScheduleService.ImportJson(path);
                r.Mask.Guid(imported.Id); foreach (var e in imported.Entries) r.Mask.Guid(e.Id);
                r.Text("import", "import", "json", JsonSerializer.Serialize(imported, Opts), "bytes-masked");
                System.IO.File.WriteAllText(path, "null");
                try { ScheduleService.ImportJson(path); r.Json("null", "null-file", new JsonObject { ["threw"] = false }); }
                catch (Exception ex) { r.Json("null", "null-file", Shapes.ExceptionShape(ex, aaAuthored: true)); }
            },
        };

        // ---- X04 SireExport --------------------------------------------------------------------------------------------
        foreach (var mode in SireExport.Modes)
        {
            var slug = Slug(mode);
            yield return new CaseDef
            {
                Id = "X04." + slug, Family = F, Normative = "should", Compare = "text-lf",
                Title = "SireExport.Build(\"" + mode + "\") over the 12 §7.10 synthetic bank (now pinned 2026-09-29 14:05)",
                Settles = new[] { "12 §7.10" },
                Run = r =>
                {
                    var (bank, state, identified, filtered) = SireBankFixture();
                    var text = SireExport.Build(mode, bank, state, identified, filtered);
                    // The only clock read is the header line; 12 §7.10 pins now = 2026-09-29 14:05.
                    var generated = $"  Generated: {DateTime.Now:yyyy-MM-dd HH:mm}";
                    text = text.Replace(generated, "  Generated: 2026-09-29 14:05");
                    var prev = $"  Generated: {DateTime.Now.AddMinutes(-1):yyyy-MM-dd HH:mm}";
                    text = text.Replace(prev, "  Generated: 2026-09-29 14:05");
                    r.Input("mode", mode);
                    r.Input("now", "2026-09-29 14:05");
                    r.Text("result", "export", "txt", text, "text-lf");
                },
            };
        }

        // ---- X05 TaskIdentifierService / TagExtractor on the real bank --------------------------------------------------
        yield return new CaseDef
        {
            Id = "X05", Family = F, Normative = "should", Compare = "json-semantic",
            Title = "TaskIdentifierService, TagExtractor, ExtractRoviqLocations, DominantCategory on the real bank",
            Settles = new[] { "12 §7.3", "12 §7.4", "12 §7.5" },
            Run = r =>
            {
                var bankPath = Path.Combine(AppContext.BaseDirectory, "Data", "sire2_question_bank.json");
                var bank = JsonSerializer.Deserialize<QuestionBank>(System.IO.File.ReadAllText(bankPath))!;
                var tasks = TaskIdentifierService.IdentifyAllTasks(bank.Questions);
                var rows = new JsonArray();
                foreach (var q in bank.Questions)
                {
                    q.EvidenceTags = TagExtractor.ExtractTags(q);
                    q.RoviqLocations = TagExtractor.ExtractRoviqLocations(q.RoviqSequence);
                    rows.Add(new JsonObject
                    {
                        ["q"] = q.QuestionNumber,
                        ["tags"] = new JsonArray(q.EvidenceTags.Select(x => (JsonNode?)x).ToArray()),
                        ["roviq"] = new JsonArray(q.RoviqLocations.Select(x => (JsonNode?)x).ToArray()),
                        ["dominant"] = TagExtractor.DominantCategory(q),
                        ["tasks"] = tasks.TryGetValue(q.QuestionNumber, out var t) ? new JsonArray(t.Select(x => (JsonNode?)x).ToArray()) : null,
                    });
                }
                r.Input("bank", "Sources/AACore/Resources/sire2_question_bank.json (byte copy of AA/Sire/Data)");
                r.Json("result", "sire-identify", new JsonObject { ["questions"] = bank.Questions.Count, ["withTasks"] = tasks.Count, ["rows"] = rows });
            },
        };

        // ---- X06 CompasReader on synthetic workbooks ------------------------------------------------------------------
        yield return new CaseDef
        {
            Id = "X06", Family = F, Normative = "should", Compare = "json-semantic",
            Title = "CompasReader on synthetic workbooks generated with ClosedXML (09 §7.7)", Settles = new[] { "09 §7.7" },
            Run = r =>
            {
                var result = new JsonObject();
                foreach (var (name, build) in CompasBooks())
                {
                    var path = Path.Combine(r.DataDir, name + ".xlsx");
                    using (var wb = new XLWorkbook()) { build(wb); wb.SaveAs(path); }
                    r.Side($"{r.Id}.{name}.xlsx", System.IO.File.ReadAllBytes(path), mask: false);
                    try
                    {
                        var rows = CompasReader.Read(path);
                        var arr = new JsonArray();
                        foreach (var row in rows)
                        {
                            var o = new JsonObject();
                            foreach (var h in new[] { "First name", "Surname", "Rank", "Sign Off Date", "Code", "Weight", "Flag", "Note" })
                                o[h] = row.Get(h);
                            arr.Add(o);
                        }
                        result[name] = arr;
                    }
                    catch (Exception ex) { result[name] = Shapes.ExceptionShape(ex, aaAuthored: ex is InvalidDataException); }
                }
                r.Json("result", "compas", result);
            },
        };
    }

    private static (List<SireQuestion>, SireState, Dictionary<string, List<string>>, List<SireQuestion>) SireBankFixture()
    {
        var q1 = new SireQuestion { QuestionNumber = "1.1.1", Type = "data_field", Chapter = "1", ChapterName = "Particulars", Section = "1.1", FullQuestionText = "Name of the vessel" };
        var q2 = new SireQuestion { QuestionNumber = "2.1.2", Type = "inspection_question", Chapter = "2", ChapterName = "Certs", Section = "2.1", FullQuestionText = "Is alpha ok?", ShortQuestionText = "Alpha check", VesselTypes = new() { "Chemical" }, RoviqSequence = "Main Deck", Objective = "Obj A" };
        var q3 = new SireQuestion { QuestionNumber = "2.1.10", Type = "inspection_question", Chapter = "2", ChapterName = "Certs", Section = "2.1", FullQuestionText = "Is beta ok?", ShortQuestionText = "Beta check", VesselTypes = new() { "Oil", "LNG" }, RoviqSequence = "Bridge, Documentation", Objective = "Obj B", ExpectedEvidence = "Ev B", PotentialNegativeObservationGrounds = "Neg B" };
        foreach (var q in new[] { q1, q2, q3 }) q.RoviqLocations = TagExtractor.ExtractRoviqLocations(q.RoviqSequence);
        var state = new SireState();
        state.QuestionStatuses["2.1.10"] = "Checked"; state.QuestionStatuses["1.1.1"] = "InProgress";
        state.Bookmarks.Add("2.1.2"); state.ForExport.Add("2.1.10");
        state.Tasks.Add(new SireTask { Id = G(41), QuestionNumber = "2.1.10", Text = "Check log", IsCompleted = true, CreatedAt = new DateTime(2026, 9, 29, 10, 0, 0) });
        state.Tasks.Add(new SireTask { Id = G(42), QuestionNumber = "2.1.2", Text = "Sight cert", CreatedAt = new DateTime(2026, 9, 29, 9, 0, 0) });
        state.Tasks.Add(new SireTask { Id = G(43), QuestionNumber = "2.1.10", Text = "Review plan", CreatedAt = new DateTime(2026, 9, 29, 9, 30, 0) });
        var identified = new Dictionary<string, List<string>> { ["2.1.2"] = new() { "Verify Y", "Verify Z" }, ["2.1.10"] = new() { "Verify X" } };
        foreach (var q in new[] { q1, q2, q3 }) q.Status = state.GetStatus(q.QuestionNumber);
        q2.IsBookmarked = true; q3.IsForExport = true; q2.IsSelected = true; q3.IsSelected = true;
        return (new List<SireQuestion> { q1, q2, q3 }, state, identified, new List<SireQuestion> { q3, q1 });
    }

    private static IEnumerable<(string Name, Action<XLWorkbook> Build)> CompasBooks()
    {
        void Header(IXLWorksheet ws, int row, params string[] names)
        {
            for (int i = 0; i < names.Length; i++) ws.Cell(row, i + 1).Value = names[i];
        }
        yield return ("sheets-report", wb =>
        {
            wb.AddWorksheet("Summary").Cell(1, 1).Value = "summary";
            var ws = wb.AddWorksheet("REPORT");
            Header(ws, 1, "First Name", "SURNAME", "Rank");
            ws.Cell(2, 1).Value = "Juan"; ws.Cell(2, 2).Value = "Cruz"; ws.Cell(2, 3).Value = "MAST";
        });
        yield return ("sheets-first", wb =>
        {
            var a = wb.AddWorksheet("A"); Header(a, 1, "First name", "Surname"); a.Cell(2, 1).Value = "Ana"; a.Cell(2, 2).Value = "Lee";
            var b = wb.AddWorksheet("B"); Header(b, 1, "First name", "Surname"); b.Cell(2, 1).Value = "Bob"; b.Cell(2, 2).Value = "Ray";
        });
        yield return ("title-rows", wb =>
        {
            var ws = wb.AddWorksheet("report");
            ws.Cell(1, 1).Value = "COMPAS crew report"; ws.Cell(2, 1).Value = "Vessel: Alpha"; ws.Cell(3, 1).Value = "Printed 2026-09-29";
            Header(ws, 4, "First Name", "SURNAME", "Sign Off Date");
            ws.Cell(5, 1).Value = "Juan"; ws.Cell(5, 2).Value = "Cruz"; ws.Cell(5, 3).Value = "2026-12-01";
        });
        yield return ("header-row-21", wb =>
        {
            var ws = wb.AddWorksheet("report");
            Header(ws, 21, "First name", "Surname");
            ws.Cell(22, 1).Value = "Juan"; ws.Cell(22, 2).Value = "Cruz";
        });
        yield return ("header-variants-and-values", wb =>
        {
            var ws = wb.AddWorksheet("report");
            ws.Cell(1, 1).Value = "First\nname"; ws.Cell(1, 2).Value = "Surname"; ws.Cell(1, 3).Value = "Code"; ws.Cell(1, 4).Value = "Weight";
            ws.Cell(1, 5).Value = "Flag"; ws.Cell(1, 6).Value = "Sign Off Date"; ws.Cell(1, 7).Value = "Note"; ws.Cell(1, 8).Value = "Rank"; ws.Cell(1, 9).Value = "Rank";
            ws.Cell(2, 1).Value = "Juan"; ws.Cell(2, 2).Value = "Cruz"; ws.Cell(2, 3).Value = 12345.0; ws.Cell(2, 4).Value = 180.5;
            ws.Cell(2, 5).Value = true; ws.Cell(2, 6).Value = 46096; ws.Cell(2, 6).Style.NumberFormat.NumberFormatId = 14;
            ws.Cell(2, 7).Value = "  ABC  "; ws.Cell(2, 8).Value = "left"; ws.Cell(2, 9).Value = "right";
            ws.Cell(3, 3).Value = "skipped row"; ws.Cell(3, 7).Value = "no names";
            ws.Cell(4, 1).Value = "Ana"; ws.Cell(4, 2).Value = "Lee";
        });
    }
}
