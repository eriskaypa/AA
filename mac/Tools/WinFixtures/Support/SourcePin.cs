// Source pinning & provenance (spec 01 DATA-301, GF.3.3 `verify-sources`): before generating, the SHA-256 of every
// linked file is compared with mac/Docs/original-source-checksums.sha256 (`<hex>␠␠<path>` lines). Any mismatch
// aborts with the list of differing files — a CRLF checkout on Windows is the usual cause (GF.6.2: clone with
// core.autocrlf=false).
using System.Security.Cryptography;
using System.Text.Json.Nodes;

namespace WinFixtures;

internal static class SourcePin
{
    /// <summary>The pinned commit of the read-only Windows sources (`37cdab0` when the plan was written).</summary>
    public const string PinnedCommit = "37cdab0";

    /// <summary>Repo-relative paths of every file the WinFixtures.csproj links (kept in sync with the csproj).</summary>
    public static readonly string[] LinkedFiles =
    {
        "AA/Models/Models.cs", "AA/Models/CrewMember.cs", "AA/Sire/SireState.cs", "AA/Sire/SireModels.cs",
        "AA/Services/DataStore.cs", "AA/Services/Dpapi.cs", "AA/Services/PasswordService.cs",
        "AA/Services/ItemLockService.cs", "AA/Services/AppRepository.cs", "AA/Services/DataDiff.cs",
        "AA/Services/SearchService.cs", "AA/Services/ReminderService.cs", "AA/Services/WorkRange.cs",
        "AA/Services/BatchDone.cs", "AA/Services/BatchDeadline.cs", "AA/Services/BatchDelete.cs",
        "AA/Services/SavedListOrder.cs", "AA/Services/DateResolver.cs", "AA/Services/CrewConverter.cs",
        "AA/Services/CrewMapping.cs", "AA/Services/CompasReader.cs", "AA/Services/ChecklistExporter.cs",
        "AA/Services/XlsxWriter.cs", "AA/Services/ChecklistTemplateService.cs", "AA/Services/ScheduleService.cs",
        "AA/Sire/SireExport.cs", "AA/Sire/TagExtractor.cs", "AA/Sire/TaskIdentifierService.cs",
        "AA/Sire/Data/sire2_question_bank.json",
    };

    /// <summary>The repository root: three levels above this project folder (mac/Tools/WinFixtures → repo).</summary>
    public static string RepoRoot()
    {
        // Walk up from the executing assembly until a folder holds both AA/ and mac/.
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null)
        {
            if (Directory.Exists(Path.Combine(dir.FullName, "AA")) && Directory.Exists(Path.Combine(dir.FullName, "mac")))
                return dir.FullName;
            dir = dir.Parent;
        }
        // `dotnet run` from the repo root also works with the current directory.
        var cwd = new DirectoryInfo(Directory.GetCurrentDirectory());
        while (cwd != null)
        {
            if (Directory.Exists(Path.Combine(cwd.FullName, "AA")) && Directory.Exists(Path.Combine(cwd.FullName, "mac")))
                return cwd.FullName;
            cwd = cwd.Parent;
        }
        throw new DirectoryNotFoundException("cannot find the repository root (a folder containing AA/ and mac/)");
    }

    public static Dictionary<string, string> ReadPins(string repo)
    {
        var file = Path.Combine(repo, "mac", "Docs", "original-source-checksums.sha256");
        var map = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var raw in File.ReadAllLines(file))
        {
            var line = raw.TrimEnd('\r');
            if (line.Length < 67 || line[64] != ' ') continue;
            map[line[66..]] = line[..64];
        }
        return map;
    }

    public static string Sha256(string path)
    {
        using var s = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(s)).ToLowerInvariant();
    }

    /// <summary>Returns the differing files (empty = all match). Prints each.</summary>
    public static List<string> Verify(out JsonArray provenance)
    {
        var repo = RepoRoot();
        var pins = ReadPins(repo);
        var bad = new List<string>();
        provenance = new JsonArray();
        foreach (var rel in LinkedFiles)
        {
            var path = Path.Combine(repo, rel.Replace('/', Path.DirectorySeparatorChar));
            if (!File.Exists(path)) { bad.Add($"{rel}: missing"); continue; }
            var actual = Sha256(path);
            provenance.Add(new JsonObject { ["path"] = rel, ["sha256"] = actual });
            if (!pins.TryGetValue(rel, out var pinned)) { bad.Add($"{rel}: not pinned in original-source-checksums.sha256"); continue; }
            if (!string.Equals(pinned, actual, StringComparison.Ordinal))
                bad.Add($"{rel}: sha256 {actual} ≠ pinned {pinned} (CRLF checkout? clone with core.autocrlf=false)");
        }
        return bad;
    }

    /// <summary>`verify-sources` (exit 1 on mismatch).</summary>
    public static int Run()
    {
        var bad = Verify(out _);
        if (bad.Count == 0)
        {
            Console.WriteLine($"verify-sources: {LinkedFiles.Length} linked files match mac/Docs/original-source-checksums.sha256");
            return 0;
        }
        Console.Error.WriteLine("verify-sources: the linked Windows sources differ from the pinned checksums:");
        foreach (var b in bad) Console.Error.WriteLine("  " + b);
        return 1;
    }
}
