using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using AA.Models;
using AA.Services;

namespace AA.FlashSync;

/// <summary>Bridges Flash Sync's JSON-tree world to the app's database and settings.
///
/// The baseline is what makes an incremental sync possible: it records the tree as it stood the last time
/// the other device confirmed it received a transfer. Diffing against it turns "my whole database" into
/// "the four things I changed since Tuesday" — a couple of QR frames instead of five hundred.
///
/// The baseline only advances when the USER confirms the other side got it. Guessing here would be the
/// one unrecoverable mistake in the design: an advanced-but-not-received baseline means the next change
/// set silently omits those edits, and they never arrive at all.</summary>
public static class FlashSyncStore
{
    private static string BaselinePath => Path.Combine(DataStore.AppFolder, "qrsync-baseline.json");

    // ---------- reading the current state ----------

    /// <summary>The live database as a JSON tree, exactly as it would be written to disk.</summary>
    public static JsonObject ReadDataTree() =>
        JsonNode.Parse(DataStore.SerializeForSave(DataStore.Load()))?.AsObject() ?? new JsonObject();

    /// <summary>The same, for an AppData already in hand (avoids a reload mid-edit).</summary>
    public static JsonObject ReadDataTree(AppData data) =>
        JsonNode.Parse(DataStore.SerializeForSave(data))?.AsObject() ?? new JsonObject();

    /// <summary>settings.json as a tree, or an empty object when absent/unreadable.</summary>
    public static JsonObject ReadSettingsTree()
    {
        try
        {
            if (File.Exists(DataStore.SettingsFile))
                return JsonNode.Parse(File.ReadAllText(DataStore.SettingsFile))?.AsObject() ?? new JsonObject();
        }
        catch { }
        return new JsonObject();
    }

    // ---------- the baseline ----------

    /// <summary>The last state the other device confirmed receiving: {"Data":…,"Settings":…}. Null when
    /// the two have never completed a transfer, which is what makes the first sync a full snapshot.</summary>
    public static (JsonObject? Data, JsonObject? Settings) ReadBaseline()
    {
        try
        {
            if (!File.Exists(BaselinePath)) return (null, null);
            var root = JsonNode.Parse(File.ReadAllText(BaselinePath))?.AsObject();
            return (root?["Data"]?.AsObject(), root?["Settings"]?.AsObject());
        }
        catch { return (null, null); }   // unreadable baseline just means "send everything", never an error
    }

    /// <summary>Record the state the other device has now confirmed. Called ONLY on explicit user
    /// confirmation — see the class remarks for why guessing is unsafe.</summary>
    public static void WriteBaseline(JsonObject data, JsonObject? settings)
    {
        try
        {
            Directory.CreateDirectory(DataStore.AppFolder);
            var root = new JsonObject
            {
                ["StampedUtc"] = DateTime.UtcNow.ToString("O"),
                ["Data"] = data.DeepClone(),
                ["Settings"] = settings?.DeepClone()
            };
            var tmp = BaselinePath + ".tmp";
            File.WriteAllText(tmp, root.ToJsonString());
            File.Move(tmp, BaselinePath, overwrite: true);   // atomic: a torn baseline would resend forever
        }
        catch { }   // non-fatal: worst case the next sync is a full snapshot
    }

    /// <summary>Forget the baseline, so the next send is a complete snapshot. The recovery path when the
    /// two devices have drifted apart.</summary>
    public static void ClearBaseline()
    {
        try { if (File.Exists(BaselinePath)) File.Delete(BaselinePath); } catch { }
    }

    public static bool HasBaseline => File.Exists(BaselinePath);

    // ---------- building what to send ----------

    /// <summary>The payload to flash: an incremental change set when a baseline exists and something
    /// changed, otherwise a full snapshot. Returns null when there is genuinely nothing to send.</summary>
    public static (byte[] Payload, FrameKind Kind, string Label)? BuildOutgoing(string from)
    {
        var data = ReadDataTree();
        var settings = ReadSettingsTree();
        var (baseData, baseSettings) = ReadBaseline();

        if (baseData != null)
        {
            var cs = FlashChangeSet.BuildChangeSet(data, baseData, settings, baseSettings, from, DateTime.Now);
            if (cs == null) return null;                       // nothing changed since they last confirmed
            return (System.Text.Encoding.UTF8.GetBytes(cs.ToJsonString()), FrameKind.ChangeSet, FlashChangeSet.Summarize(cs));
        }

        var snap = FlashChangeSet.BuildSnapshot(data, settings);
        return (System.Text.Encoding.UTF8.GetBytes(snap.ToJsonString()), FrameKind.FullSnapshot, "full database");
    }

    // ---------- applying what arrived ----------

    /// <summary>What an incoming payload would do, decided WITHOUT touching anything, so the user can be
    /// shown it and refuse. Returns null when the payload is not valid Flash Sync JSON.</summary>
    public static IncomingChange? Preview(byte[] payload, FrameKind kind)
    {
        try
        {
            var node = JsonNode.Parse(System.Text.Encoding.UTF8.GetString(payload));
            if (node is not JsonObject obj) return null;
            bool snapshot = kind == FrameKind.FullSnapshot || FlashChangeSet.IsSnapshotEnvelope(obj);
            return new IncomingChange
            {
                Payload = obj,
                IsSnapshot = snapshot,
                Summary = snapshot ? "the sender's entire database (replaces yours)" : FlashChangeSet.Summarize(obj)
            };
        }
        catch { return null; }
    }

    /// <summary>Apply a previewed change. Settings are MERGED into the local tree — never replaced — so
    /// this machine's password, Google state and paths survive; the sender's tree has those stripped
    /// before it is ever built, and this is the second line of that defence.</summary>
    public static AppData Apply(IncomingChange change)
    {
        var settings = ReadSettingsTree();
        JsonObject applied;

        if (change.IsSnapshot)
        {
            applied = FlashChangeSet.ApplySnapshot(change.Payload, settings, DateTime.Now, out _, ReadDataTree());
        }
        else
        {
            applied = ReadDataTree();
            FlashChangeSet.ApplyChangeSet(change.Payload, applied, settings, DateTime.Now);
        }

        WriteSettingsTree(settings);
        var data = DataStore.ApplySyncedData(applied.ToJsonString());

        // The receiver is now identical to the sender for everything that travels, so that IS the new
        // baseline — and unlike the send side there is no doubt about delivery.
        WriteBaseline(ReadDataTree(data), ReadSettingsTree());
        return data;
    }

    private static void WriteSettingsTree(JsonObject settings)
    {
        try
        {
            File.WriteAllText(DataStore.SettingsFile, settings.ToJsonString(new JsonSerializerOptions { WriteIndented = false }));
            DataStore.LoadSettings();
        }
        catch { }
    }
}

/// <summary>A decoded, not-yet-applied transfer.</summary>
public sealed class IncomingChange
{
    public JsonObject Payload { get; init; } = new();
    public bool IsSnapshot { get; init; }
    public string Summary { get; init; } = "";
}
