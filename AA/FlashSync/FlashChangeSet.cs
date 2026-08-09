using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace AA.FlashSync;

/// <summary>Builds and applies Flash Sync payloads (spec §10) at the JSON-tree level, so whole changed
/// subtrees ride across untouched (zero-data-loss) and collections the app doesn't model still sync.
/// Everything here is pure over <see cref="JsonNode"/> trees — no coupling to the typed model — which is
/// exactly what the contract requires and what makes it testable.</summary>
public static class FlashChangeSet
{
    // data.json keys that must not travel. LastModified is re-stamped by the applier. Ui is this
    // workstation's window geometry / selected tab — syncing it would yank the receiver's layout around
    // on every change set, and it is never what the user means by "my changes".
    private static readonly HashSet<string> ExcludedDataKeys = new(StringComparer.Ordinal)
    {
        "LastModified", "Ui"
    };

    // settings.json keys that must never travel: secrets, machine-local absolute paths, and per-install
    // identity/policy. PasswordHash/PasswordSalt are the critical ones — carrying them would install the
    // SENDER's master password on the receiver and lock that user out of their own database. AppIdentity
    // must stay put or both installs would claim to be the same machine in bundle stamps, and
    // EncryptLocalData is an at-rest policy whose flip requires rewriting the local file (see
    // DataStore.SetEncryptLocalData), so importing it would leave the on-disk state inconsistent.
    private static readonly HashSet<string> ExcludedSettingsKeys = new(StringComparer.Ordinal)
    {
        "GeminiApiKey", "CurrentDataFile", "GoogleDriveFolder", "FolderBuilderBase", "SharedSaveFile",
        "PasswordHash", "PasswordSalt", "EncryptLocalData", "AppIdentity", "SyncOnSave", "TextOnlyExport"
    };

    // ---------- Full snapshot (kind 1) ----------

    /// <summary>The pairing payload: an envelope carrying both files. Settings are stripped of excluded keys.</summary>
    public static JsonObject BuildSnapshot(JsonObject data, JsonObject? settings)
    {
        return new JsonObject
        {
            ["V"] = 1,
            ["Data"] = StripExcludedData(data),
            ["Settings"] = StripExcludedSettings(settings)
        };
    }

    /// <summary>A copy of data.json without the keys that must never cross the wire, so a full snapshot
    /// and an incremental change set agree on what travels — otherwise pairing would yank the receiver's
    /// window layout around exactly once, and never again.</summary>
    private static JsonObject StripExcludedData(JsonObject data)
    {
        var o = new JsonObject();
        foreach (var (k, v) in data)
            if (!ExcludedDataKeys.Contains(k)) o[k] = v?.DeepClone();
        return o;
    }

    /// <summary>True when a payload is the snapshot envelope (has V + object-valued Data), vs a bare data.json.</summary>
    public static bool IsSnapshotEnvelope(JsonNode? node) =>
        node is JsonObject o && o["V"] != null && o["Data"] is JsonObject;

    // ---------- Change set (kind 0) ----------

    /// <summary>Diff the current tree against the baseline, structurally (no allowlist), producing a change
    /// set. Returns null when nothing changed.</summary>
    public static JsonObject? BuildChangeSet(JsonObject current, JsonObject? baselineData,
        JsonObject? currentSettings, JsonObject? baselineSettings, string from, DateTime createdLocal)
    {
        var sets = new JsonObject();
        var deletes = new JsonObject();
        var blocks = new JsonObject();
        var blockDeletes = new JsonArray();
        var order = new JsonObject();

        foreach (var name in UnionKeys(current, baselineData))
        {
            if (ExcludedDataKeys.Contains(name)) continue;
            var c = current[name];
            var b = baselineData?[name];
            if (DeepEquals(c, b)) continue;

            if (c == null) { blockDeletes.Add(name); continue; }   // key removed since baseline

            bool isColl = IsIdCollection(c) || IsIdCollection(b);
            if (!isColl) { blocks[name] = c.DeepClone(); continue; }

            var cArr = c as JsonArray;
            if (cArr == null || cArr.Any(e => e is not JsonObject o || o["Id"] == null))
            {
                blocks[name] = c.DeepClone();   // an element without an Id: can't address items -> whole array
                continue;
            }

            var (bIds, bMap) = OrderedIds(b as JsonArray);
            var (cIds, cMap) = OrderedIds(cArr);

            var itemSets = new JsonArray();
            foreach (var id in cIds)
                if (!bMap.TryGetValue(id, out var bo) || !DeepEquals(cMap[id], bo))
                    itemSets.Add(cMap[id].DeepClone());
            if (itemSets.Count > 0) sets[name] = itemSets;

            var dels = new JsonArray();
            foreach (var id in bIds) if (!cMap.ContainsKey(id)) dels.Add(id);
            if (dels.Count > 0) deletes[name] = dels;

            // Order — only when applying Sets/Deletes wouldn't already leave the receiver in this order.
            var delSet = new HashSet<string>(dels.Select(n => (n?.ToString() ?? "")));
            var predicted = bIds.Where(id => !delSet.Contains(id)).ToList();
            foreach (var id in cIds) if (!predicted.Contains(id)) predicted.Add(id);   // new ids append
            if (!predicted.SequenceEqual(cIds))
                order[name] = new JsonArray(cIds.Select(id => (JsonNode)id!).ToArray());
        }

        var (settingsOut, settingsDeletes) = DiffSettings(currentSettings, baselineSettings);

        if (sets.Count == 0 && deletes.Count == 0 && blocks.Count == 0 && blockDeletes.Count == 0
            && order.Count == 0 && settingsOut == null && settingsDeletes.Count == 0)
            return null;

        var cs = new JsonObject
        {
            ["V"] = 1,
            ["From"] = from,
            ["Created"] = createdLocal.ToString("yyyy-MM-ddTHH:mm:ss")
        };
        if (sets.Count > 0) cs["Sets"] = sets;
        if (deletes.Count > 0) cs["Deletes"] = deletes;
        if (blocks.Count > 0) cs["Blocks"] = blocks;
        if (blockDeletes.Count > 0) cs["BlockDeletes"] = blockDeletes;
        if (order.Count > 0) cs["Order"] = order;
        if (settingsOut != null) cs["Settings"] = settingsOut;
        if (settingsDeletes.Count > 0) cs["SettingsDeletes"] = settingsDeletes;
        return cs;
    }

    private static (JsonObject? settings, JsonArray deletes) DiffSettings(JsonObject? current, JsonObject? baseline)
    {
        var cur = StripExcludedSettings(current) ?? new JsonObject();
        var bas = StripExcludedSettings(baseline) ?? new JsonObject();
        var deletes = new JsonArray();
        if (DeepEquals(cur, bas)) return (null, deletes);
        foreach (var name in UnionKeys(bas, cur))   // keys removed since baseline
            if (bas[name] != null && cur[name] == null) deletes.Add(name);
        return (cur, deletes);
    }

    // ---------- Apply ----------

    /// <summary>Apply a change set to the data + settings trees, in the contract's order. Mutates in place.</summary>
    public static void ApplyChangeSet(JsonObject changeSet, JsonObject data, JsonObject settings, DateTime nowLocal)
    {
        // 1) upsert Sets by Id (replace in place or append)
        if (changeSet["Sets"] is JsonObject sets)
            foreach (var (name, arrNode) in sets)
            {
                if (arrNode is not JsonArray items) continue;
                var target = data[name] as JsonArray;
                if (target == null) { target = new JsonArray(); data[name] = target; }
                foreach (var item in items)
                {
                    if (item is not JsonObject io) continue;
                    var id = io["Id"]?.ToString();
                    int at = IndexOfId(target, id);
                    if (at >= 0) target[at] = item.DeepClone();
                    else target.Add(item.DeepClone());
                }
            }

        // 2) remove Deletes ids
        if (changeSet["Deletes"] is JsonObject dels)
            foreach (var (name, idsNode) in dels)
            {
                if (data[name] is not JsonArray target || idsNode is not JsonArray ids) continue;
                var idSet = new HashSet<string>(ids.Select(n => (n?.ToString() ?? "")));
                for (int i = target.Count - 1; i >= 0; i--)
                    if (target[i] is JsonObject o && o["Id"] != null && idSet.Contains(o["Id"]!.ToString()))
                        target.RemoveAt(i);
            }

        // 3) Order (after adds+removes, so every named Id exists)
        if (changeSet["Order"] is JsonObject order)
            foreach (var (name, idsNode) in order)
            {
                if (data[name] is not JsonArray target || idsNode is not JsonArray ids) continue;
                Reorder(target, ids.Select(n => (n?.ToString() ?? "")).ToList());
            }

        // 4) Blocks wholesale
        if (changeSet["Blocks"] is JsonObject blocks)
            foreach (var (name, val) in blocks)
                data[name] = val?.DeepClone();

        // 5) BlockDeletes
        if (changeSet["BlockDeletes"] is JsonArray bdel)
            foreach (var n in bdel) data.Remove((n?.ToString() ?? ""));

        // 6) merge Settings
        if (changeSet["Settings"] is JsonObject incoming)
            foreach (var (k, v) in incoming)
                if (!ExcludedSettingsKeys.Contains(k)) settings[k] = v?.DeepClone();

        // 7) remove SettingsDeletes
        if (changeSet["SettingsDeletes"] is JsonArray sdel)
            foreach (var n in sdel) settings.Remove((n?.ToString() ?? ""));

        // 8) re-stamp LastModified
        data["LastModified"] = nowLocal.ToString("yyyy-MM-ddTHH:mm:ss.fffffff");
    }

    /// <summary>Apply a snapshot: replace the whole data tree; merge settings (both from the envelope, or
    /// treat a bare data.json as data-only). Returns the new data tree; settings merged into <paramref name="settings"/>.</summary>
    /// <param name="existingData">The receiver's current data tree, if any. Keys that never travel
    /// (window layout) are carried forward from it, so a full snapshot replaces the database without
    /// disturbing this workstation's own view of it.</param>
    public static JsonObject ApplySnapshot(JsonObject payload, JsonObject settings, DateTime nowLocal,
        out bool hadSettings, JsonObject? existingData = null)
    {
        JsonObject data;
        hadSettings = false;
        if (IsSnapshotEnvelope(payload))
        {
            data = (JsonObject)payload["Data"]!.DeepClone();
            if (payload["Settings"] is JsonObject incoming)
            {
                hadSettings = true;
                foreach (var (k, v) in incoming)
                    if (!ExcludedSettingsKeys.Contains(k)) settings[k] = v?.DeepClone();
            }
        }
        else data = (JsonObject)payload.DeepClone();   // bare data.json, no settings

        // Never let a sender's excluded keys land here (a bare data.json or an older sender may still
        // carry them), and keep this workstation's own instead.
        foreach (var k in ExcludedDataKeys) data.Remove(k);
        if (existingData != null)
            foreach (var k in ExcludedDataKeys)
                if (existingData[k] is JsonNode keep) data[k] = keep.DeepClone();

        data["LastModified"] = nowLocal.ToString("yyyy-MM-ddTHH:mm:ss.fffffff");
        return data;
    }

    // ---------- Human summary (for the label + the review sheet) ----------

    public static string Summarize(JsonObject changeSet)
    {
        var parts = new List<string>();
        if (changeSet["Sets"] is JsonObject sets)
            foreach (var (name, arr) in sets)
                if (arr is JsonArray a && a.Count > 0) parts.Add($"{a.Count} {name}");
        if (changeSet["Deletes"] is JsonObject dels)
        {
            int n = dels.Sum(kv => (kv.Value as JsonArray)?.Count ?? 0);
            if (n > 0) parts.Add($"{n} deleted");
        }
        if (changeSet["Blocks"] is JsonObject b && b.Count > 0) parts.Add(string.Join(", ", b.Select(kv => kv.Key)));
        // Destructive operations MUST be named. ApplyChangeSet removes these whole sections, so a change
        // set carrying only BlockDeletes previously summarised as "no changes" — the review sheet would
        // promise nothing and then drop an entire section of the database.
        if (changeSet["BlockDeletes"] is JsonArray bd && bd.Count > 0)
            parts.Add("REMOVES " + string.Join(", ", bd.Select(n => n?.ToString() ?? "?")));
        if (changeSet["Settings"] != null) parts.Add("settings");
        if (changeSet["SettingsDeletes"] is JsonArray sd && sd.Count > 0)
            parts.Add($"clears {sd.Count} setting{(sd.Count == 1 ? "" : "s")}");
        // BuildChangeSet returns null when nothing changed, so a change set that reaches here always
        // changes something — never claim otherwise, even if no branch above recognised it.
        return parts.Count == 0 ? "other changes" : string.Join(", ", parts);
    }

    // ---------- helpers ----------

    private static JsonObject? StripExcludedSettings(JsonObject? settings)
    {
        if (settings == null) return null;
        var o = new JsonObject();
        foreach (var (k, v) in settings)
            if (!ExcludedSettingsKeys.Contains(k)) o[k] = v?.DeepClone();
        return o;
    }

    private static IEnumerable<string> UnionKeys(JsonObject? a, JsonObject? b)
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        if (a != null) foreach (var kv in a) if (seen.Add(kv.Key)) yield return kv.Key;
        if (b != null) foreach (var kv in b) if (seen.Add(kv.Key)) yield return kv.Key;
    }

    private static bool IsIdCollection(JsonNode? n) =>
        n is JsonArray arr && arr.Any(e => e is JsonObject o && o["Id"] != null);

    private static (List<string> ids, Dictionary<string, JsonNode> map) OrderedIds(JsonArray? arr)
    {
        var ids = new List<string>();
        var map = new Dictionary<string, JsonNode>(StringComparer.Ordinal);
        if (arr != null)
            foreach (var e in arr)
                if (e is JsonObject o && o["Id"] is JsonNode idn)
                {
                    var id = idn.ToString();
                    if (!map.ContainsKey(id)) { ids.Add(id); map[id] = o; }
                }
        return (ids, map);
    }

    private static int IndexOfId(JsonArray arr, string? id)
    {
        if (id == null) return -1;
        for (int i = 0; i < arr.Count; i++)
            if (arr[i] is JsonObject o && o["Id"] != null && o["Id"]!.ToString() == id) return i;
        return -1;
    }

    private static void Reorder(JsonArray target, List<string> orderIds)
    {
        // Place the named ids first (in the requested order), then append everything not named, in its
        // original relative order. Ids named but absent are skipped; items without an Id keep their place.
        var items = target.ToList();
        var byId = new Dictionary<string, JsonNode?>(StringComparer.Ordinal);
        foreach (var e in items)
        {
            var id = (e as JsonObject)?["Id"]?.ToString();
            if (id != null && !byId.ContainsKey(id)) byId[id] = e;
        }
        var used = new HashSet<string>(StringComparer.Ordinal);
        var rebuilt = new List<JsonNode?>();
        foreach (var id in orderIds)
            if (byId.TryGetValue(id, out var node) && used.Add(id)) rebuilt.Add(node);
        foreach (var e in items)
        {
            var id = (e as JsonObject)?["Id"]?.ToString();
            if (id != null && used.Contains(id)) continue;   // already placed
            rebuilt.Add(e);
        }
        target.Clear();
        foreach (var e in rebuilt) target.Add(e?.DeepClone());
    }

    public static bool DeepEquals(JsonNode? a, JsonNode? b)
    {
        if (a is null && b is null) return true;
        if (a is null || b is null) return false;
        if (a is JsonObject oa && b is JsonObject ob)
        {
            if (oa.Count != ob.Count) return false;
            foreach (var kv in oa)
            {
                if (!ob.TryGetPropertyValue(kv.Key, out var bv)) return false;
                if (!DeepEquals(kv.Value, bv)) return false;
            }
            return true;
        }
        if (a is JsonArray aa && b is JsonArray ba)
        {
            if (aa.Count != ba.Count) return false;
            for (int i = 0; i < aa.Count; i++) if (!DeepEquals(aa[i], ba[i])) return false;
            return true;
        }
        if (a is JsonValue && b is JsonValue) return a.ToJsonString() == b.ToJsonString();
        return false;
    }
}
