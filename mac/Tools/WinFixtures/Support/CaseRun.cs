// Case definitions, the per-case run context and the GF.4.4 case record (spec 01 GF.3.4, GF.4.2–GF.4.4, DATA-307).
using System.Text.Json;
using System.Text.Json.Nodes;

namespace WinFixtures;

/// <summary>Which runs execute a case (DATA-310).</summary>
internal enum Runs
{
    /// <summary>`platform: any` — committed from the unix run; the windows run regenerates it only for the
    /// neutrality cross-check (GF.3.12).</summary>
    Any,
    /// <summary>`platform: unix` — local-time and POSIX-path cases; unix run only.</summary>
    Unix,
    /// <summary>`platform: windows` — windows run only; committed under windows/ with a `w` id suffix.</summary>
    Windows,
    /// <summary>Both runs commit: the unix run as `platform: unix`, the windows run as `<id>w`, `platform: windows`.</summary>
    Both,
}

internal sealed class CaseDef
{
    public required string Id { get; init; }
    /// <summary>json | settings | bundles | crypto | services | ext.</summary>
    public required string Family { get; init; }
    public required string Title { get; init; }
    public Runs Runs { get; init; } = Runs.Any;
    public string Tz { get; init; } = Fx.DefaultZone;
    public string Normative { get; init; } = "must";
    /// <summary>Normative level of the windows-run twin when it differs (A25x: record-only on unix, must on windows).</summary>
    public string? NormativeWindows { get; init; }
    public string Compare { get; init; } = "bytes-masked";
    public bool DependsOnToday { get; init; }
    public string[] Settles { get; init; } = Array.Empty<string>();
    /// <summary>Outputs that are random by design and cannot be masked without losing their value (K04's random-IV
    /// blobs are decrypt-only vectors): `--verify-only` skips them (DATA-303 determinism, documented exception).</summary>
    public bool NonDeterministic { get; init; }
    /// <summary>Settings and bundle-matrix cases mutate statics LoadSettings does not reset: one process per case.</summary>
    public bool OwnProcess { get; init; }
    public required Action<CaseRun> Run { get; init; }

    public bool RunsOn(RunPlatform p) => Runs switch
    {
        Runs.Any => true,
        Runs.Unix => p == RunPlatform.Unix,
        Runs.Windows => p == RunPlatform.Windows,
        Runs.Both => true,
        _ => false,
    };

    /// <summary>Whether the run's outputs are committed (the windows run of an `any` case is neutrality-only).</summary>
    public bool Commits(RunPlatform p) => Runs switch
    {
        Runs.Any => p == RunPlatform.Unix,
        Runs.Unix => p == RunPlatform.Unix,
        Runs.Windows => p == RunPlatform.Windows,
        Runs.Both => true,
        _ => false,
    };
}

/// <summary>The context a case body runs in: where to write, what to mask, and the case record being built.</summary>
internal sealed class CaseRun
{
    public CaseDef Def { get; }
    /// <summary>The staging root (MANIFEST.json sits here); for neutrality-only runs a scratch root.</summary>
    public string Root { get; }
    public string DataDir { get; }
    public RunPlatform Platform { get; }
    public string RunId { get; }
    public string Today { get; }
    public Masker Mask { get; } = new();

    private readonly JsonObject _inputs = new();
    private readonly JsonArray _outputs = new();
    private JsonObject? _mac;
    private string? _normative;

    public CaseRun(CaseDef def, string root, string dataDir, RunPlatform platform, string runId, string today)
    {
        Def = def; Root = root; DataDir = dataDir; Platform = platform; RunId = runId; Today = today;
        // GF.3.5: every literal occurrence of the data folder → %%DATADIR%% (and its /private alias on macOS).
        Mask.Literal(dataDir, "%%DATADIR%%");
        if (dataDir.StartsWith("/tmp/", StringComparison.Ordinal)) Mask.Literal("/private" + dataDir, "%%DATADIR%%");
        // A25 also stores the data folder upper-cased (case-insensitive file systems) — a W-GOLD extension token.
        if (dataDir.ToUpperInvariant() != dataDir) Mask.Literal(dataDir.ToUpperInvariant(), "%%DATADIRUPPER%%");
        try { Mask.QuotedLiteral(Environment.MachineName, "%%MACHINE%%"); } catch { }
        // %%TEMP%% is registered only by the cases that put a scratch path into an output (FamilyC.Scratch): a global
        // /tmp literal would also hit ordinary values such as the S02 FolderBuilderBase "/tmp/fb".
    }

    public string Id => Platform == RunPlatform.Windows && Def.Runs is Runs.Both or Runs.Windows ? Def.Id + "w" : Def.Id;

    public string PlatformText => Def.Runs switch
    {
        Runs.Any => "any",
        Runs.Unix => "unix",
        Runs.Windows => "windows",
        _ => Platform == RunPlatform.Windows ? "windows" : "unix",
    };

    /// <summary>`<family>/<name>`, under `windows/` on the windows run.</summary>
    public string Rel(string name) => (Platform == RunPlatform.Windows ? "windows/" : "") + Def.Family + "/" + name;

    /// <summary>GF.4.2 golden name: `<caseId>.<artefact>.golden.<ext>`.</summary>
    public string GoldenName(string artefact, string ext) => $"{Id}.{artefact}.golden.{ext}";

    public void OverrideNormative(string level) => _normative = level;

    // ---- inputs -------------------------------------------------------------------------------------------------

    public void Input(string key, JsonNode? value) => _inputs[key] = value;
    public void Input(string key, string value) => _inputs[key] = JsonValue.Create(value);

    /// <summary>Writes a synthetic input under inputs/ (shared by Swift and C#) and records it.</summary>
    public string InputFile(string name, byte[] content, string key = "file")
    {
        var rel = "inputs/" + name;
        WriteRaw(rel, content);
        _inputs[key] = rel;
        return rel;
    }

    /// <summary>A text input: asserted token-free, then masked like an output (a data-folder path in a settings
    /// precondition becomes %%DATADIR%%; the Swift side substitutes its own folder back).</summary>
    public string InputFile(string name, string content, string key = "file")
    {
        Masker.AssertNoToken(content, name);
        return InputFile(name, Fx.Utf8(Mask.Apply(content)), key);
    }

    /// <summary>Reads an authored input (committed under inputs/, never written by the generator).</summary>
    public string AuthoredInput(string name, string key = "file")
    {
        var path = Path.Combine(Root, "inputs", name);
        if (!File.Exists(path)) throw new FileNotFoundException("authored input missing (commit it first)", path);
        _inputs[key] = "inputs/" + name;
        var text = File.ReadAllText(path, Fx.Utf8NoBom);
        Masker.AssertNoToken(text, name);
        return text;
    }

    // ---- outputs --------------------------------------------------------------------------------------------------

    /// <summary>Writes a masked text output and records it.</summary>
    public string Text(string role, string artefact, string ext, string content, string? compare = null, bool mac = true,
                       string? pointer = null)
    {
        var name = GoldenName(artefact, ext);
        var rel = Rel(name);
        WriteRaw(rel, Fx.Utf8(Mask.Apply(content)));
        AddOutput(role, rel, compare, mac, pointer);
        return rel;
    }

    /// <summary>Writes raw bytes (crypto, ZIP, binary samples) unmasked and records them.</summary>
    public string Bytes(string role, string artefact, string ext, byte[] content, string? compare = null, bool mac = true)
    {
        var rel = Rel(GoldenName(artefact, ext));
        WriteRaw(rel, content);
        AddOutput(role, rel, compare, mac, null);
        return rel;
    }

    /// <summary>Writes a GF.3.8 expectation document (json-semantic) and records it.</summary>
    public string Json(string role, string artefact, JsonNode? node, bool mac = true) =>
        Text(role, artefact, "json", Fx.Expect(node), "json-semantic", mac);

    /// <summary>Writes a file next to the outputs without recording it as an output (payloads referenced by a
    /// zip manifest).</summary>
    public string Side(string name, byte[] content, bool mask)
    {
        var rel = Rel(name);
        WriteRaw(rel, mask ? Fx.Utf8(Mask.Apply(Fx.Utf8NoBom.GetString(content))) : content);
        return rel;
    }

    private void AddOutput(string role, string rel, string? compare, bool mac, string? pointer)
    {
        var o = new JsonObject { ["role"] = role, ["file"] = rel };
        if (pointer != null) o["pointer"] = pointer;
        if (compare != null) o["compare"] = compare;
        if (!mac) o["mac"] = false;
        _outputs.Add(o);
    }

    // ---- Mac expectation (GF.4.4) ---------------------------------------------------------------------------------

    /// <summary>The Mac knowingly differs; <paramref name="content"/> is the Mac-expected golden for
    /// <paramref name="role"/>, derived from the Windows behaviour by the rule the reason cites.</summary>
    public void Divergent(string role, string content, string reason, string? compare = null)
    {
        var rel = Rel(GoldenName("mac-expected", "json"));
        WriteRaw(rel, Fx.Utf8(Mask.Apply(content)));
        _mac = new JsonObject { ["kind"] = "divergent", ["file"] = rel, ["role"] = role, ["reason"] = reason };
        if (compare != null) _mac["compare"] = compare;
    }

    /// <summary>Divergent without a Mac golden: the goldens are a Windows record only; the Mac rule is asserted by
    /// the owner's own tests (the reason cites them).</summary>
    public void DivergentRecordOnly(string reason) =>
        _mac = new JsonObject { ["kind"] = "divergent", ["reason"] = reason };

    // ---- record -----------------------------------------------------------------------------------------------------

    public JsonObject Record()
    {
        var r = new JsonObject
        {
            ["id"] = Id,
            ["family"] = Def.Family,
            ["title"] = Def.Title,
            ["platform"] = PlatformText,
            ["tz"] = Platform == RunPlatform.Unix ? Def.Tz : TimeZoneInfo.Local.Id,
            ["normative"] = _normative ?? (Platform == RunPlatform.Windows && Def.NormativeWindows != null ? Def.NormativeWindows : Def.Normative),
            ["compare"] = Def.Compare,
            ["dependsOnToday"] = Def.DependsOnToday,
        };
        if (Def.DependsOnToday) r["today"] = Today;
        if (Def.NonDeterministic) r["nonDeterministic"] = true;
        r["inputs"] = _inputs.DeepClone();
        r["outputs"] = _outputs.DeepClone();
        r["macExpectation"] = _mac?.DeepClone() ?? new JsonObject { ["kind"] = "same" };
        r["settles"] = new JsonArray(Def.Settles.Select(s => (JsonNode?)JsonValue.Create(s)).ToArray());
        return r;
    }

    // ---- io -------------------------------------------------------------------------------------------------------

    public void WriteRaw(string rel, byte[] content)
    {
        var path = Path.Combine(Root, rel.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, content);
    }

    /// <summary>A path inside the data folder.</summary>
    public string Data(params string[] parts) => Path.Combine(new[] { DataDir }.Concat(parts).ToArray());

    /// <summary>A golden already written by an earlier group of this run (A14 reads A12.1).</summary>
    public string ReadStaged(string rel) => File.ReadAllText(Path.Combine(Root, rel.Replace('/', Path.DirectorySeparatorChar)), Fx.Utf8NoBom);
}

/// <summary>The case catalogue (GF.5).</summary>
internal static class Catalog
{
    public static IReadOnlyList<CaseDef> All { get; } = Build();

    private static List<CaseDef> Build()
    {
        var all = new List<CaseDef>();
        all.AddRange(FamilyA.Cases());
        all.AddRange(FamilyB.Cases());
        all.AddRange(FamilyC.Cases());
        all.AddRange(FamilyD.Cases());
        all.AddRange(FamilyE.Cases());
        all.AddRange(FamilyF.Cases());
        var dup = all.GroupBy(c => c.Id).FirstOrDefault(g => g.Count() > 1);
        if (dup != null) throw new InvalidOperationException("duplicate case id " + dup.Key);
        return all;
    }

    public static readonly string[] Families = { "json", "settings", "bundles", "crypto", "services", "ext" };

    /// <summary>`--families a,b,c,d,e,f` letters → family names.</summary>
    public static string FamilyOf(string letterOrName) => letterOrName switch
    {
        "a" => "json", "b" => "settings", "c" => "bundles", "d" => "crypto", "e" => "services", "f" => "ext",
        _ => letterOrName,
    };
}
