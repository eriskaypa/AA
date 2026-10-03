// The kitchen-sink database (spec 01 GF.5.a "KS"). Coverage rules (normative): every type of 01 §4.2 present at
// least once; every persisted property non-default at least once; every enum at a non-zero value; at least one
// Guid? set and one null; every DateTime kind; fractions with 1 and 7 digits; the GF.5.a strings. The Swift
// mac-out emitter builds the same database (Tests/AACoreTests/WinFixtures/GoldKitchenSink.swift) — keep them in step.
using System.Collections.ObjectModel;
using System.Text.Json;
using AA.Models;
using AA.Sire;
using static WinFixtures.Fx;

namespace WinFixtures;

internal static class KitchenSink
{
    public const string LockHash = "V/LC8HOXSNUWQZsGKohGZjI8WD6krhZVBKgfe1PGKgk=";     // `correct horse` / S (01 §7.1)
    public const string LockSalt = "AAECAwQFBgcICQoLDA0ODw==";                         // S = 00 01 … 0F
    public const string ManualPath = "files/0123456789abcdef0123456789abcdef_Manual v2.pdf";

    /// <summary>S-6-like body: the WPF root attribute set, an entity, non-ASCII text and the lock-sentinel
    /// background #FFFFE699.</summary>
    public const string EquipmentXaml =
        "<Section xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\" xml:space=\"preserve\" " +
        "TextAlignment=\"Left\" LineHeight=\"Auto\" IsHyphenationEnabled=\"False\" xml:lang=\"en-us\" " +
        "FlowDirection=\"LeftToRight\" NumberSubstitution.CultureSource=\"User\" NumberSubstitution.Substitution=\"AsCulture\" " +
        "FontFamily=\"Consolas\" FontStyle=\"Normal\" FontWeight=\"Normal\" FontStretch=\"Normal\" FontSize=\"14\" " +
        "Foreground=\"#FF1A1A1A\" Typography.StandardLigatures=\"True\" Typography.ContextualLigatures=\"True\" " +
        "Typography.DiscretionaryLigatures=\"False\" Typography.HistoricalLigatures=\"False\" Typography.AnnotationAlternates=\"0\" " +
        "Typography.ContextualAlternates=\"True\" Typography.HistoricalForms=\"False\" Typography.Kerning=\"True\" " +
        "Typography.CapitalSpacing=\"False\" Typography.CaseSensitiveForms=\"False\" Typography.StylisticSet1=\"False\" " +
        "Typography.Fraction=\"Normal\" Typography.SlashedZero=\"False\" Typography.MathematicalGreek=\"False\" " +
        "Typography.EastAsianExpertForms=\"False\" Typography.Variants=\"Normal\" Typography.Capitals=\"Normal\" " +
        "Typography.NumeralStyle=\"Normal\" Typography.NumeralAlignment=\"Normal\" Typography.EastAsianWidths=\"Normal\" " +
        "Typography.EastAsianLanguage=\"Normal\" Typography.StandardSwashes=\"0\" Typography.ContextualSwashes=\"0\" " +
        "Typography.StylisticAlternates=\"0\"><Paragraph><Run>Check oil &amp; filters → Wärtsilä </Run>" +
        "<Run Background=\"#FFFFE699\">locked part</Run></Paragraph></Section>";

    public const string SireBody =
        "<Section xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\" xml:space=\"preserve\">" +
        "<Paragraph><Run>Edited body</Run></Paragraph></Section>";

    private static Container C(int n) => new() { Id = G(n) };

    private static FileItem File(int n, string name, string path, FileKind kind, bool isLink = false, bool inPlace = false) =>
        new() { Id = G(n), Name = name, Path = path, Kind = kind, Added = D_L, IsLink = isLink, LinkInPlace = inPlace };

    private static Dictionary<string, JsonElement> Extra(string json)
    {
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.EnumerateObject().ToDictionary(p => p.Name, p => p.Value.Clone());
    }

    public static AppData Build()
    {
        var d = new AppData();

        // ---- Equipment G(1) ----
        var eqContainer = C(101);
        eqContainer.RichTextXaml = EquipmentXaml;
        var manual = File(201, "Manual v2.pdf", ManualPath, FileKind.Document);
        manual.LinkedItemIds.Add(G(3));
        eqContainer.Files.Add(manual);
        eqContainer.Files.Add(File(203, "Daily log.xlsx", @"\\shipserver\ops\Daily log.xlsx", FileKind.Document, inPlace: true));
        eqContainer.Files.Add(File(204, "Routine  (folder)", @"Z:\Routine", FileKind.Other, inPlace: true));
        eqContainer.Files.Add(File(205, "IMO", "https://www.imo.org", FileKind.Link, isLink: true));
        eqContainer.Files.Add(File(206, "deck.jpg", "files/00000000000000000000000000000206_deck.jpg", FileKind.Image));
        eqContainer.Files.Add(File(207, "drill.mp4", "files/00000000000000000000000000000207_drill.mp4", FileKind.Video));
        eqContainer.SharedWithContainerIds.Add(G(103));
        eqContainer.IsLocked = true;

        var pumpContainer = C(102);
        pumpContainer.Files.Add(File(202, "pump.pdf", "files/00000000000000000000000000000202_pump.pdf", FileKind.Document));

        var eq = new Equipment
        {
            Id = G(1),
            Name = "Main Engine → ⚓ <ME>",
            Description = "Two-stroke & 'slow' \"speed\" +1",
            Container = eqContainer,
            GroupId = G(40),
            LockHash = LockHash,
            LockSalt = LockSalt,
            LockHint = "the usual",
        };
        eq.Tags.Add("engine"); eq.Tags.Add("ME");
        eq.RelatedIds.Add(G(3));
        eq.BucketIds.Add(G(50)); eq.BucketIds.Add(G(51));
        eq.ProcedureIds.Add(G(4));
        eq.TaskIds.Add(G(3));
        eq.Components.Add(new Component { Id = G(2), Name = "Fuel pump", Notes = "check every 500 h", Container = pumpContainer });
        d.Equipment.Add(eq);

        // ---- Task G(3) with nested subtasks ----
        var grandchild = new TaskItem
        {
            Id = G(6), Name = "Count heads", Container = C(106), Recurrence = RecurrenceKind.Yearly,
            RangeStart = Day(2026, 9, 28),
        };
        var child = new TaskItem { Id = G(5), Name = "Muster", Container = C(105), Deadline = D_U7 };
        child.Status = WorkStatus.Blocked;
        child.Subtasks.Add(grandchild);
        var task = new TaskItem
        {
            Id = G(3),
            Name = "Fire drill 😀",
            Container = C(103),
            Deadline = D_U,
            RangeStart = Day(2026, 9, 27, DateTimeKind.Local),
            IsJob = true,
            DurationMinutes = 90,
            ScheduledStart = D_L,
            Recurrence = RecurrenceKind.Monthly,
            RecurrenceSpawned = true,
        };
        task.IsComplete = true;                          // → Status Done via the setter
        task.Subtasks.Add(child);
        d.Tasks.Add(task);

        // ---- Procedure G(4) ----
        var step = new ChecklistStep
        {
            Id = G(7), Title = "Sample fuel", Done = true, Deadline = D_Z, IsJob = true, DurationMinutes = 15,
            ScheduledStart = D_U7, Container = C(107),
        };
        step.BucketIds.Add(G(50));
        step.TaskIds.Add(G(3));
        step.EquipmentIds.Add(G(1));
        var proc = new Procedure
        {
            Id = G(4), Name = "Bunkering", Container = C(104), Deadline = D_L, Recurrence = RecurrenceKind.Weekly,
            Status = WorkStatus.InProgress, IsJob = true, DurationMinutes = 120, ScheduledStart = D_Z0,
        };
        proc.Steps.Add(step);
        d.Procedures.Add(proc);

        // ---- Vessel G(8) ----
        var vessel = new Vessel { Id = G(8), Name = "Alpha", Container = C(108), NotificationsEnabled = false };
        vessel.QuickCards.Add(new QuickCard
        {
            Id = G(9), Title = "Manuals", Target = ManualPath, IsFolder = true, LinkInPlace = true, Icon = "🛟",
            Color = "#80FF0000", X = 12.5, Y = -24, Width = 333.25, Height = 0.1,
        });
        vessel.QuickCards.Add(new QuickCard { Id = G(30), Title = "IMO", Target = "https://www.imo.org", IsLink = true });
        vessel.Jobs.Add(new ShipJob
        {
            JobNo = "ARA.22.3120", Title = "Overhaul purifier", WorkPlanNo = "WP-7", Status = "Execution", ClassCode = "MC",
            Category = "ROUTINE", ResponsibleRank = "2E", FunctionNo = "601.01", FunctionDescription = "Fuel oil purifier",
            Interval = "64,000 H", DueStatus = "in Window", DueDate = "2026-10-15", FinishedDate = "2026-10-16",
            LastDoneDate = "2024-03-01", OverdueDays = -3, Notify = true, IsCompleted = true, CompletedDate = "2026-10-16",
            ImportedAt = "2026-09-29 14:05",
        });
        vessel.PortCalls.Add(new PortCall
        {
            Id = G(10), PortName = "Bonny", Country = "Nigeria", UnLocode = "NGBON", PortFacility = "Bonny LNG Terminal",
            PfNo = "NGBON-0001", ArrivalDate = "2026-05-01", ArrivalTime = "08:00", DepartureDate = "2026-05-03",
            DepartureTime = "17:30", SecurityLevelPort = "1", SecurityLevelVessel = "1", SspFollowed = "YES",
            SpecialMeasures = "none", ImportedAt = "2026-09-29 14:05",
        });
        d.Vessels.Add(vessel);

        // ---- Group G(40) ----
        d.Groups.Add(new ItemGroup { Id = G(40), Kind = ItemKind.Vessel, Name = "Engine room", Expanded = false });

        // ---- Crew G(11) ----
        var crew = new CrewMember
        {
            Id = G(11), ScheduleVesselId = G(8),
            EmployeeId = "E-1001", FirstName = "José", MiddleName = "Ωmega", LastName = "Cruz", Nationality = "Philippines",
            DateOfBirth = "1985-03-04", PlaceOfBirth = "Manila", Gender = "Male", Height = "175", EyesColor = "Brown",
            HairColor = "Black", UserType = "Officer", Rank = "Chief Officer", RankCode = "CO", SignedOnOff = "Off",
            Company = "Fixture Shipping", Vessel = "Alpha", SignOnDate = "2026-06-01", SignOnPort = "SGSIN",
            SignOnPortRaw = "Singapore", SignOffDate = "2026-12-01", SignOffPort = "NLRTM", SignOffPortRaw = "Rotterdam",
            PassportNumber = "P1234567", PassportExpiry = "2030-01-01", PassportIssued = "2020-01-02",
            SeamansBookNumber = "SB-765", SeamansBookExpiry = "2029-05-05", SeamansBookIssued = "2019-05-06",
            CocNumber = "COC-42", CocExpiry = "2028-08-08", CocIssue = "2023-08-09", HealthCertExpiry = "2027-02-02",
            NokFirstName = "Maria", NokLastName = "Cruz", NokRelationship = "Spouse", RawNationality = "FILIPINO",
            ImportedAt = "2026-09-29 14:05", SourceFile = "compas-fixture.xlsx",
        };
        crew.Checklist.Add(new ChecklistStep { Id = G(12), Title = "Familiarisation", Container = C(112) });
        crew.Schedule.Add(new ScheduleEntry { Id = G(13), Title = "Joining briefing", Kind = ScheduleKind.Note, Date = "2026-06-01", Time = "09:00", Notes = "bring documents" });
        crew.Schedule.Add(new ScheduleEntry { Id = G(14), Title = "Fire drill", Kind = ScheduleKind.Task, RefId = G(3), Date = "2026-10-01", Done = true });
        crew.Schedule.Add(new ScheduleEntry { Id = G(15), Title = "Bunkering", Kind = ScheduleKind.Procedure, RefId = G(4), Date = "2026-10-02", EndDate = "2026-10-03", EndTime = "18:00" });
        crew.Schedule.Add(new ScheduleEntry { Id = G(16), Title = "Main engine rounds", Kind = ScheduleKind.Equipment, RefId = G(1), Date = "2026-10-04" });
        crew.Flags.Add(new CrewReviewFlag(CrewFlagSeverity.Info, "Rank", "Mapped CO → Chief Officer"));
        crew.Flags.Add(new CrewReviewFlag(CrewFlagSeverity.Warning, "SignOffPort", "Guessed UN/LOCODE from 'Rotterdam'"));
        crew.Flags.Add(new CrewReviewFlag(CrewFlagSeverity.Error, "PassportNumber", "Mandatory field missing in a fixture row"));
        d.Crew.Add(crew);

        // ---- Log ----
        d.Log.Add(new LogEntry { TimestampUtc = D_Z0, Action = "Added", Kind = "Task", Name = "Fire drill 😀", Detail = "fixture" });

        // ---- Saved lists, list groups, buckets ----
        var tpl = new ChecklistTemplate { Id = G(20), Name = "Daily rounds", CreatedUtc = D_Z, GroupId = G(21) };
        tpl.Items.Add(new ChecklistTemplateItem { Title = "Check oil", DurationMinutes = 45, IsJob = true, Container = C(120) });
        d.ChecklistTemplates.Add(tpl);
        d.ChecklistTemplates.Add(new ChecklistTemplate { Id = G(29), Name = "Orphan list", CreatedUtc = D_Z, GroupId = G(99) });
        d.ListGroups.Add(new ListGroup { Id = G(21), Name = "Engine", CreatedUtc = D_Z });
        d.QuickBuckets.Add(new QuickBucket { Id = G(50), Name = "Deck", Category = "Location", CreatedUtc = D_Z });
        d.QuickBuckets.Add(new QuickBucket { Id = G(51), Name = "Bosun", Category = "", CreatedUtc = D_Z });

        // ---- Ports, schedule templates ----
        var port = new Port { Id = G(22), Name = "Bonny", Country = "Nigeria", UnLocode = "NGBON" };
        port.Visits.Add(new PortVisit
        {
            VesselName = "Alpha", VesselId = G(8), ArrivalDate = "2026-05-01", ArrivalTime = "08:00",
            DepartureDate = "2026-05-03", DepartureTime = "17:30", ImportedAt = "2026-09-29 14:05",
        });
        d.Ports.Add(port);
        var sched = new ScheduleTemplate { Id = G(23), Name = "Port rota", VesselId = G(8), VesselName = "Alpha", CreatedUtc = D_Z };
        sched.Entries.Add(new ScheduleEntry
        {
            Id = G(24), Title = "Gangway watch", Kind = ScheduleKind.Note, Date = "2026-05-01", Time = "08:00",
            EndDate = "2026-05-01", EndTime = "12:00", Notes = "bring radio",
        });
        d.ScheduleTemplates.Add(sched);

        // ---- Trash ----
        var trashed = new Vessel { Id = G(26), Name = "Old tug", Container = C(126) };
        d.Trash.Add(new TrashedItem
        {
            Id = G(25), ItemType = "Vessel", ItemId = G(26), BatchId = G(27), Name = "Old tug", KindLabel = "Vessel",
            DeletedUtc = D_Z0, PayloadJson = JsonSerializer.Serialize(trashed, typeof(Vessel), Opts),
        });

        // ---- SIRE ----
        d.Sire.QuestionStatuses["1.1.1"] = "InProgress";
        d.Sire.QuestionStatuses["2.1.1"] = "Checked";
        d.Sire.QuestionStatuses["11.1.2"] = "NotApplicable";
        d.Sire.Bookmarks.Add("1.1.1");
        d.Sire.ForExport.Add("2.1.1");
        d.Sire.Tasks.Add(new SireTask { Id = G(28), QuestionNumber = "1.1.1", Text = "Check the certificate", IsCompleted = true, CreatedAt = D_L });
        d.Sire.QuestionBodies["1.1.1"] = SireBody;

        // ---- Ui (every key non-null) ----
        var ui = d.Ui;
        ui.WindowLeft = -1280.5; ui.WindowTop = 0; ui.WindowWidth = 1600; ui.WindowHeight = 900.25;
        ui.WindowState = "Maximized"; ui.SelectedMainTabIndex = 3;
        ui.SelectedEquipmentId = G(1); ui.SelectedTaskId = G(3); ui.SelectedProcedureId = G(4); ui.SelectedVesselId = G(8);
        ui.CalendarSelectedDate = D_U; ui.CalendarViewMode = "Week"; ui.CalendarFontScale = 13.5; ui.ShowShortcutBar = false;
        ui.QuickViewPinIds.Add(G(3)); ui.QuickViewPinIds.Add(G(4));
        ui.TabColors["TabTasks"] = "#FF00AA00";
        ui.TabOrder.Add("TabTasks"); ui.TabOrder.Add("TabEquipment");
        ui.DueWindowWidth = 420; ui.DueWindowHeight = 640.5; ui.MapFocusedItemId = G(8);
        ui.SortAZ["Task"] = true; ui.SortAZ["savedlists"] = false;
        ui.GroupExpanded["Vessel|Engine room"] = false;
        ui.CrewSortMode = "Name";
        ui.CrewTableColumns.AddRange(new[] { "Rank", "Name", "SignOff" });
        ui.CrewTableShownColumns.AddRange(new[] { "Rank", "Name" });
        ui.CrewTableDateFormat = "DayMonthYear"; ui.CrewTableDateSeparator = "/";
        ui.LastDigestDate = "2026-09-29";
        ui.ExtraData = Extra("{\"NewPref\":true}");

        // ---- Root ----
        d.LastModified = D_LM;
        d.SchemaVersion = 1;
        d.ExtraData = Extra("{\"FutureThing\":{\"a\":[1,2]}}");
        return d;
    }

    /// <summary>A04: one instance of every type with ONLY ids and dates fixed — everything else at its C# default,
    /// so the golden shows which defaults are written.</summary>
    public static AppData Defaults()
    {
        var d = new AppData();
        var eq = new Equipment { Id = G(1), Container = C(101) };
        var f = new FileItem { Id = G(201), Added = D_L };
        eq.Container.Files.Add(f);
        eq.Components.Add(new Component { Id = G(2), Container = C(102) });
        d.Equipment.Add(eq);
        var t = new TaskItem { Id = G(3), Container = C(103) };
        t.Subtasks.Add(new TaskItem { Id = G(5), Container = C(105) });
        d.Tasks.Add(t);
        var p = new Procedure { Id = G(4), Container = C(104) };
        p.Steps.Add(new ChecklistStep { Id = G(7), Container = C(107) });
        d.Procedures.Add(p);
        var v = new Vessel { Id = G(8), Container = C(108) };
        v.QuickCards.Add(new QuickCard { Id = G(9) });
        v.Jobs.Add(new ShipJob());
        v.PortCalls.Add(new PortCall { Id = G(10) });
        d.Vessels.Add(v);
        d.Groups.Add(new ItemGroup { Id = G(40) });
        var c = new CrewMember { Id = G(11) };
        c.Checklist.Add(new ChecklistStep { Id = G(12), Container = C(112) });
        c.Schedule.Add(new ScheduleEntry { Id = G(13) });
        c.Flags.Add(new CrewReviewFlag());
        d.Crew.Add(c);
        d.Log.Add(new LogEntry { TimestampUtc = D_Z0 });
        var tpl = new ChecklistTemplate { Id = G(20), CreatedUtc = D_Z };
        tpl.Items.Add(new ChecklistTemplateItem { Container = C(120) });
        d.ChecklistTemplates.Add(tpl);
        d.ListGroups.Add(new ListGroup { Id = G(21), CreatedUtc = D_Z });
        d.QuickBuckets.Add(new QuickBucket { Id = G(50), CreatedUtc = D_Z });
        var port = new Port { Id = G(22) };
        port.Visits.Add(new PortVisit());
        d.Ports.Add(port);
        var st = new ScheduleTemplate { Id = G(23), CreatedUtc = D_Z };
        st.Entries.Add(new ScheduleEntry { Id = G(24) });
        d.ScheduleTemplates.Add(st);
        d.Trash.Add(new TrashedItem { Id = G(25), DeletedUtc = D_Z0 });
        d.Sire.Tasks.Add(new SireTask { Id = G(28), CreatedAt = D_L });
        return d;
    }

    /// <summary>A minimal database holding the given tasks (each with a fixed container id).</summary>
    public static AppData WithTasks(IEnumerable<TaskItem> tasks)
    {
        var d = new AppData();
        foreach (var t in tasks) d.Tasks.Add(t);
        return d;
    }

    public static TaskItem Task(int n, string name) => new() { Id = G(n), Name = name, Container = C(1000 + n) };

    public static ObservableCollection<T> Coll<T>(params T[] items) => new(items);
}
