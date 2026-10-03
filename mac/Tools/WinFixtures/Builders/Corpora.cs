// Synthetic data sets of the services family (spec 01 GF.5.e): the 01 §7.8 DataDiff example, the 02 §7.7 search
// corpus, the 02 §7.8 reminder data set, and small builders. Every object gets an explicit G(n) id so the inputs are
// deterministic; the sets are written as AA-format JSON inputs (loaded by the Swift codec on the Mac side).
using AA.Models;
using static WinFixtures.Fx;

namespace WinFixtures;

internal static class Corpora
{
    public const string NS = "xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\" xml:space=\"preserve\"";

    public static string Xaml(string runText) => $"<Section {NS}><Paragraph><Run>{runText}</Run></Paragraph></Section>";

    public static Container C(int n, string? xaml = null) => new() { Id = G(n), RichTextXaml = xaml ?? "" };

    public static FileItem MkFile(int n, string name, string path, FileKind kind = FileKind.Document) =>
        new() { Id = G(n), Name = name, Path = path, Kind = kind, Added = D_L };

    public static TaskItem MkTask(int n, string name) => new() { Id = G(n), Name = name, Container = C(1000 + n) };
    public static Equipment Equip(int n, string name) => new() { Id = G(n), Name = name, Container = C(1000 + n) };
    public static Procedure Proc(int n, string name) => new() { Id = G(n), Name = name, Container = C(1000 + n) };
    public static Vessel Ship(int n, string name) => new() { Id = G(n), Name = name, Container = C(1000 + n) };
    public static ChecklistStep Step(int n, string title) => new() { Id = G(n), Title = title, Container = C(1000 + n) };
    public static Component Comp(int n, string name) => new() { Id = G(n), Name = name, Container = C(1000 + n) };

    // ---- 01 §7.8 ----

    public static (AppData Current, AppData Incoming) DiffExample()
    {
        var cur = new AppData();
        cur.Tasks.Add(MkTask(3, "Pump"));
        cur.Equipment.Add(Equip(1, "Boiler"));
        var inc = new AppData();
        var t = MkTask(3, "Pump 2");
        t.Deadline = Day(2026, 10, 1);
        t.Subtasks.Add(MkTask(5, "Check oil"));
        inc.Tasks.Add(t);
        var v = Ship(8, "Alpha");
        v.Container.Files.Add(MkFile(201, "manual.pdf", "files/x_manual.pdf"));
        inc.Vessels.Add(v);
        return (cur, inc);
    }

    // ---- 02 §7.7 ----

    public static AppData SearchCorpus()
    {
        var d = new AppData();
        var me = Equip(1, "Main Engine");
        me.Tags.Add("engine"); me.Tags.Add("ME");
        me.Components.Add(new Component { Id = G(2), Name = "Fuel pump", Notes = "check every 500 h", Container = C(1002) });
        d.Equipment.Add(me);
        var t = MkTask(3, "Replace the fuel filter on the main engine");
        var sub = MkTask(5, "Drain water");
        sub.Container.RichTextXaml = Xaml("Open the drain cock");
        t.Subtasks.Add(sub);
        d.Tasks.Add(t);
        var p = Proc(4, "Bunkering");
        p.Steps.Add(Step(7, "Sample fuel"));
        d.Procedures.Add(p);
        d.Vessels.Add(Ship(8, "Aurora"));
        return d;
    }

    // ---- 02 §7.8 (today 2026-09-29) ----

    public static AppData ReminderSet()
    {
        var d = new AppData();
        var t1 = MkTask(31, "T1"); t1.Deadline = Day(2026, 9, 28);
        var s1 = MkTask(32, "S1"); s1.Deadline = Day(2026, 9, 29);
        t1.Subtasks.Add(s1);
        var t2 = MkTask(33, "T2"); t2.Deadline = Day(2026, 10, 6);
        var t3 = MkTask(34, "T3"); t3.Deadline = Day(2026, 10, 7);
        var t4 = MkTask(35, "T4"); t4.Deadline = Day(2026, 9, 20); t4.IsComplete = true;
        var t5 = MkTask(36, "T5"); t5.RangeStart = Day(2026, 9, 25); t5.Deadline = Day(2026, 10, 2);
        d.Tasks.Add(t1); d.Tasks.Add(t2); d.Tasks.Add(t3); d.Tasks.Add(t4); d.Tasks.Add(t5);
        var p1 = Proc(41, "P1"); p1.Status = WorkStatus.InProgress; p1.Deadline = Day(2026, 9, 29);
        var p1s = Step(42, "P1 step"); p1s.Deadline = Day(2026, 9, 30);
        p1.Steps.Add(p1s);
        var p2 = Proc(43, "P2"); p2.Status = WorkStatus.Done; p2.Deadline = Day(2026, 9, 1);
        var p2s = Step(44, "P2 step"); p2s.Deadline = Day(2026, 9, 2);
        p2.Steps.Add(p2s);
        d.Procedures.Add(p1); d.Procedures.Add(p2);
        var crew = new CrewMember { Id = G(11), FirstName = "Ana", LastName = "Cruz" };
        var cs = Step(45, "crew step"); cs.Deadline = Day(2026, 9, 29); cs.Done = true;
        crew.Checklist.Add(cs);
        d.Crew.Add(crew);
        return d;
    }
}
