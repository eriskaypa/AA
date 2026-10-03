// Family (b) `settings.json` — cases S01–S12, one process per case (spec 01 GF.5.b, DATA-316).
//
// Outputs per case: the final file bytes (`settings`, bytes-masked) and the state dump after the listed calls
// (`state`, GF.4.7) — both a Windows record: the Mac writes settings with a key-level merge (01 DATA-182) and keeps
// the Gemini key in the Keychain (DECISIONS 12 Q-6), so its writes are asserted by its own tests — plus the state
// after re-reading the final file (`reload`), which the Mac MUST reproduce when it reads that Windows-written file.
using System.Text.Json.Nodes;
using AA.Services;

namespace WinFixtures;

internal static class FamilyB
{
    private const string F = "settings";
    private const string Hash = "V/LC8HOXSNUWQZsGKohGZjI8WD6krhZVBKgfe1PGKgk=";    // `correct horse` / S (01 §7.1)
    private const string Salt = "AAECAwQFBgcICQoLDA0ODw==";

    public static IEnumerable<CaseDef> Cases()
    {
        yield return Def("S01", "no file → LoadSettings; SetAppIdentity(\"Vessel-Alpha\")", new[] { "01 §3.1", "01 §4.3" }, r =>
        {
            DataStore.LoadSettings();
            DataStore.SetAppIdentity("Vessel-Alpha");
            Finish(r);
        });
        yield return Def("S02", "every setter once, in declaration order", new[] { "01 §3.11", "01 DATA-151" }, r =>
        {
            AllSetters();
            Finish(r);
        });
        yield return Def("S03", "unknown keys, raw numbers, Windows paths → LoadSettings → SetSyncOnSave(true)",
            new[] { "01 §4.3", "01 §6.8" }, r =>
        {
            Precondition(r, "{\"Foo\":1,\"DarkMode\":true,\"Nested\":{\"a\":[1,\"é\"],\"b\":1.50},\"CurrentDataFile\":\"C:\\\\x\\\\data.json\",\"SharedSaveFile\":\"\\\\\\\\srv\\\\share\\\\aa-shared.zip\"}");
            DataStore.LoadSettings();
            r.Json("state.load", "state-load", Dump(), mac: true);
            DataStore.SetSyncOnSave(true);
            Finish(r);
        });
        yield return Def("S04", "S02 file, then clear SharedSaveFile/Gemini/FolderBuilderBase/GoogleDriveFolder (file after each)",
            new[] { "01 D-7", "01 §7.12" }, r =>
        {
            AllSetters();
            var steps = new (string Name, Action Act)[]
            {
                ("SetSharedSaveFile(null)", () => DataStore.SetSharedSaveFile(null)),
                ("SetGeminiApiKey(null)", () => DataStore.SetGeminiApiKey(null)),
                ("SetGeminiApiKey(\"  \")", () => DataStore.SetGeminiApiKey("  ")),
                ("SetFolderBuilderBase(\"\")", () => DataStore.SetFolderBuilderBase("")),
                ("SetGoogleDriveFolder(\"\")", () => DataStore.SetGoogleDriveFolder("")),
            };
            var names = new JsonArray();
            for (int i = 0; i < steps.Length; i++)
            {
                steps[i].Act();
                names.Add(steps[i].Name);
                r.Text($"settings.{i + 1}", $"settings-{i + 1}", "json", File.ReadAllText(DataStore.SettingsFile), mac: false);
            }
            r.Input("steps", names);
            Finish(r);
        });
        yield return Def("S05", "S02 file with \"PasswordSalt\":\"%%%\" → LoadSettings (catch branch) → SetDarkMode(false)",
            new[] { "01 §3.1", "01 §7.12" }, r =>
        {
            AllSetters();
            var text = File.ReadAllText(DataStore.SettingsFile).Replace($"\"PasswordSalt\":\"{Salt}\"", "\"PasswordSalt\":\"%%%\"");
            Precondition(r, text, assertNoToken: false);
            DataStore.LoadSettings();
            r.Json("state.load", "state-load", Dump(), mac: true);
            DataStore.SetDarkMode(false);
            Finish(r);
        });
        yield return Def("S06", "literal null → LoadSettings → SetDarkMode(true)", new[] { "01 §3.1" }, r =>
        {
            Precondition(r, "null");
            DataStore.LoadSettings();
            r.Json("state.load", "state-load", Dump(), mac: true);
            DataStore.SetDarkMode(true);
            Finish(r);
        });
        yield return Def("S07", "S02 file with a UTF-8 BOM → LoadSettings", new[] { "01 §3.1" }, r =>
        {
            AllSetters();
            var text = File.ReadAllText(DataStore.SettingsFile);
            File.WriteAllBytes(DataStore.SettingsFile, new byte[] { 0xEF, 0xBB, 0xBF }.Concat(Fx.Utf8(text)).ToArray());
            r.InputFile("S07.input.bin", File.ReadAllBytes(DataStore.SettingsFile));
            DataStore.LoadSettings();
            r.Json("state.load", "state-load", Dump(), mac: true);
            Finish(r);
        });
        yield return Def("S08", "S02 file with a // comment and a trailing comma → LoadSettings → SetDarkMode(true)",
            new[] { "01 §3.1", "01 D-16" }, r =>
        {
            AllSetters();
            var text = File.ReadAllText(DataStore.SettingsFile);
            text = "// comment\n" + text[..^1] + ",}";
            Precondition(r, text);
            DataStore.LoadSettings();
            r.Json("state.load", "state-load", Dump(), mac: false);       // Mac: per-key tolerance differs by design
            DataStore.SetDarkMode(true);
            Finish(r);
        });
        yield return Def("S09", "{\"DarkMode\":\"true\",\"Foo\":1} → LoadSettings → SetSyncOnSave(true)", new[] { "01 §3.1", "01 DATA-182" }, r =>
        {
            Precondition(r, "{\"DarkMode\":\"true\",\"Foo\":1}");
            DataStore.LoadSettings();
            r.Json("state.load", "state-load", Dump(), mac: true);
            DataStore.SetSyncOnSave(true);
            Finish(r);
        });
        yield return Def("S10", "S02 file; LoadSettings; delete the file; LoadSettings; SetDarkMode(true)", new[] { "01 §3.1" }, r =>
        {
            AllSetters();
            DataStore.LoadSettings();
            File.Delete(DataStore.SettingsFile);
            DataStore.LoadSettings();
            r.Json("state.load", "state-load", Dump(), mac: false);       // in-memory Gemini key: Mac keeps it elsewhere
            DataStore.SetDarkMode(true);
            Finish(r);
        });
        yield return Def("S11", "SavePasswordSettings(correct horse/S); LoadSettings; Verify", new[] { "01 DATA-084", "01 §7.1" }, r =>
        {
            DataStore.SavePasswordSettings(Hash, Salt);
            DataStore.LoadSettings();
            var verify = new JsonObject();
            foreach (var pw in new[] { "correct horse", "x", "redemption" }) verify[pw] = PasswordService.Verify(pw);
            r.Json("verify", "verify", verify, mac: true);
            Finish(r);
        });
        yield return Def("S12", "iOS-style foreign keys → LoadSettings → SetAppIdentity(\"Mac-Test\")", new[] { "13 §3.12", "01 §4.3" }, r =>
        {
            Precondition(r, "{\"iOSOnlyPref\":{\"x\":[true,null]},\"LastSyncDevice\":\"iPhone\",\"DarkMode\":false}");
            DataStore.LoadSettings();
            DataStore.SetAppIdentity("Mac-Test");
            Finish(r);
        });
    }

    private static CaseDef Def(string id, string title, string[] settles, Action<CaseRun> run) => new()
    {
        Id = id, Family = F, Title = title, Settles = settles, OwnProcess = true, Compare = "json-semantic", Run = run,
    };

    /// <summary>S02: every setter once, in this order (01 GF.5.b).</summary>
    private static void AllSetters()
    {
        DataStore.SetCurrentDataFile(Path.Combine(DataStore.AppFolder, "data.json"));
        DataStore.SavePasswordSettings(Hash, Salt);
        DataStore.SetGoogleDriveFolder("/Users/u/My Drive");
        DataStore.SetSyncOnSave(true);
        DataStore.SetTextOnlyExport(true);
        DataStore.SetDarkMode(true);
        DataStore.SetEncryptLocalData(false);
        DataStore.SetGeminiApiKey("  key-123  ");
        DataStore.SetAppIdentity(" Vessel-Alpha ");
        DataStore.SetFolderBuilderBase("/tmp/fb");
        DataStore.SetSharedSaveFile("/Volumes/share/aa-shared.zip");
    }

    private static void Precondition(CaseRun r, string text, bool assertNoToken = true)
    {
        if (assertNoToken) Masker.AssertNoToken(text, r.Id);
        File.WriteAllText(DataStore.SettingsFile, text, Fx.Utf8NoBom);
        r.InputFile($"{r.Id}.input.json", Fx.Utf8(text));
    }

    /// <summary>The state dump (GF.4.7).</summary>
    internal static JsonObject Dump() => new()
    {
        ["CurrentDataFile"] = DataStore.CurrentDataFile,
        ["GoogleDriveFolder"] = DataStore.GoogleDriveFolder,
        ["SyncOnSave"] = DataStore.SyncOnSave,
        ["TextOnlyExport"] = DataStore.TextOnlyExport,
        ["DarkMode"] = DataStore.DarkMode,
        ["EncryptLocalData"] = DataStore.EncryptLocalData,
        ["GeminiApiKey"] = DataStore.GeminiApiKey,
        ["AppIdentity"] = DataStore.AppIdentity,
        ["FolderBuilderBase"] = DataStore.FolderBuilderBase,
        ["SharedSaveFile"] = DataStore.SharedSaveFile,
        ["HasPassword"] = PasswordService.HasPassword,
        ["IsUnlocked"] = PasswordService.IsUnlocked,
    };

    /// <summary>The final file, the state after the calls, and the state after re-reading the final file.</summary>
    private static void Finish(CaseRun r)
    {
        r.Text("settings", "settings", "json", File.Exists(DataStore.SettingsFile) ? File.ReadAllText(DataStore.SettingsFile) : "", "bytes-masked", mac: false);
        r.Json("state", "state", Dump(), mac: false);
        DataStore.LoadSettings();
        r.Json("reload", "reload", Dump(), mac: true);
    }
}
