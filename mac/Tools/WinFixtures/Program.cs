// WinFixtures — the golden-fixture oracle of the Mac port (spec 01 Addendum GF, DATA-300…320, DATA-324).
//
//   dotnet run --project mac/Tools/WinFixtures -c Release -- <mode> …
//
//   verify-sources                                                   DATA-301; exit 1 on mismatch
//   generate [--out <root>] [--platform unix|windows] [--families a,b,c,d,e,f] [--verify-only]
//   case <family> --out <root> --tz <id> --run <runId> --platform <p> [--only <caseId>] [--neutral <dir>] [--today d]
//                                                                    child process; never run by hand
//   selfcheck [--out <root>]                                         GF.3.10; rewrites specConflicts[]
//   check-mac <mac-out dir> --report <file> [--platform unix|windows] GF.3.11 reverse check
//   list                                                             prints the case catalogue
//
// Default --out is mac/Tests/AACoreTests/Fixtures/winfixtures (the SwiftPM fixture folder, ARCH §10.2); default
// platform is the host's (OperatingSystem.IsWindows()).
using System.Text.Json.Nodes;
using WinFixtures;

return Cli.Main(args);

internal static class Cli
{
    public static int Main(string[] args)
    {
        if (args.Length == 0) { Usage(); return 2; }
        try
        {
            return args[0] switch
            {
                "verify-sources" => SourcePin.Run(),
                "generate" => Driver.Generate(Opt(args, "--out") ?? DefaultRoot(), Platform(args), Families(args),
                                              args.Contains("--verify-only")),
                "case" => Driver.Case(Catalog.FamilyOf(args[1]), Required(args, "--out"), Opt(args, "--neutral"),
                                      Required(args, "--tz"), Required(args, "--run"), Platform(args), Opt(args, "--only"),
                                      Opt(args, "--today") ?? DateTime.Today.ToString("yyyy-MM-dd")),
                "selfcheck" => SelfCheck.RunStandalone(Opt(args, "--out") ?? DefaultRoot()),
                "check-mac" => CheckMac.Run(args.Length > 1 ? args[1] : DefaultMacOut(), Required(args, "--report"), Platform(args)),
                "list" => List(),
                _ => Bad(args[0]),
            };
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex);
            return 1;
        }
    }

    private static int Bad(string mode) { Console.Error.WriteLine($"unknown mode '{mode}'"); Usage(); return 2; }

    private static void Usage() => Console.Error.WriteLine(
        "usage: WinFixtures verify-sources | generate [--out <root>] [--platform unix|windows] [--families a,b,c,d,e,f] " +
        "[--verify-only] | selfcheck [--out <root>] | check-mac <mac-out dir> --report <file> [--platform unix|windows] | list");

    private static string? Opt(string[] a, string name)
    {
        var i = Array.IndexOf(a, name);
        return i >= 0 && i + 1 < a.Length ? a[i + 1] : null;
    }

    private static string Required(string[] a, string name) =>
        Opt(a, name) ?? throw new ArgumentException($"missing {name}");

    private static RunPlatform Platform(string[] a) => (Opt(a, "--platform") ?? (OperatingSystem.IsWindows() ? "windows" : "unix")) switch
    {
        "unix" => RunPlatform.Unix,
        "windows" => RunPlatform.Windows,
        var p => throw new ArgumentException($"--platform must be unix or windows, not {p}"),
    };

    private static string[] Families(string[] a) =>
        (Opt(a, "--families") ?? "a,b,c,d,e,f").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(Catalog.FamilyOf).Distinct().ToArray();

    public static string DefaultRoot() =>
        Path.Combine(SourcePin.RepoRoot(), "mac", "Tests", "AACoreTests", "Fixtures", "winfixtures");

    public static string DefaultMacOut() =>
        Path.Combine(SourcePin.RepoRoot(), "mac", "Tests", "AACoreTests", "Fixtures", "mac-out");

    private static int List()
    {
        foreach (var c in Catalog.All)
            Console.WriteLine($"{c.Id,-14} {c.Family,-9} {c.Runs,-8} {c.Tz,-18} {c.Normative,-12} {c.Title}");
        Console.WriteLine($"{Catalog.All.Count} case definitions");
        return 0;
    }
}
