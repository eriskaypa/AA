using System;
using System.IO;
using System.IO.Compression;
using System.Text.Json;
using System.Text.Json.Serialization;
using AA.Models;

namespace AA.Services;

public static class DataStore
{
    public static string AppFolder { get; } = ResolveAppFolder();

    /// <summary>The data folder is normally %LOCALAPPDATA%\AA, but an <c>AA_DATA_DIR</c> environment
    /// variable overrides it (useful for a portable install or isolated testing).</summary>
    private static string ResolveAppFolder()
    {
        var over = Environment.GetEnvironmentVariable("AA_DATA_DIR");
        if (!string.IsNullOrWhiteSpace(over)) return over;
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AA");
    }
    public static string FilesFolder { get; } = Path.Combine(AppFolder, "files");
    public static string DefaultDataFile { get; } = Path.Combine(AppFolder, "data.json");
    public static string SettingsFile { get; } = Path.Combine(AppFolder, "settings.json");

    /// <summary>The OAuth client_secret.json (downloaded from Google Cloud Console) copied here
    /// when the user configures direct Drive upload. Its presence means OAuth upload is set up.</summary>
    public static string GoogleClientSecretFile { get; } = Path.Combine(AppFolder, "google_client_secret.json");
    /// <summary>Where the Google OAuth refresh token is cached so re-uploads don't re-prompt.</summary>
    public static string GoogleTokenFolder { get; } = Path.Combine(AppFolder, "google-token");

    /// <summary>Currently active data file. Persists across launches via settings.json.</summary>
    public static string CurrentDataFile { get; private set; } = Path.Combine(AppFolder, "data.json");

    /// <summary>Back-compat alias for older callers.</summary>
    public static string DataFile => CurrentDataFile;

    /// <summary>Local folder that Google Drive for desktop syncs to the cloud. Backups written
    /// here are uploaded automatically by Google Drive. Persisted in settings.json.</summary>
    public static string? GoogleDriveFolder { get; private set; }

    /// <summary>When true, every explicit Save (Ctrl+S) also pushes the data to Google Drive,
    /// and the app checks for a newer remote save on startup / periodically. Persisted.</summary>
    public static bool SyncOnSave { get; private set; }

    /// <summary>When true, the app uses the dark theme. Persisted.</summary>
    public static bool DarkMode { get; private set; }

    /// <summary>When true, the local active data file is encrypted at rest with Windows DPAPI (tied to
    /// this Windows account). Opt-in and PER-MACHINE: shared-save bundles, ZIP exports and Drive backups
    /// stay portable plaintext (a DPAPI blob can't be read on another machine/account), so cross-PC sync
    /// is unaffected. Persisted.</summary>
    public static bool EncryptLocalData { get; private set; }

    /// <summary>Last base location used by the Folder Builder. Persisted.</summary>
    public static string? FolderBuilderBase { get; private set; }

    /// <summary>Optional single "shared" save file at a user-chosen location (e.g. a network drive
    /// or a cloud-synced folder). When set, it IS the active data file: the app autosaves to it and
    /// watches it so other running copies of AA reload automatically when it changes. Persisted.</summary>
    public static string? SharedSaveFile { get; private set; }

    private class Settings
    {
        public string? CurrentDataFile { get; set; }
        public string? PasswordHash { get; set; }
        public string? PasswordSalt { get; set; }
        public string? GoogleDriveFolder { get; set; }
        public bool SyncOnSave { get; set; }
        public bool DarkMode { get; set; }
        public string? FolderBuilderBase { get; set; }
        public string? SharedSaveFile { get; set; }
        public bool EncryptLocalData { get; set; }
    }

    public static void LoadSettings()
    {
        try
        {
            Directory.CreateDirectory(AppFolder);
            if (!File.Exists(SettingsFile)) { CurrentDataFile = DefaultDataFile; GoogleDriveFolder = null; SyncOnSave = false; DarkMode = false; SharedSaveFile = null; EncryptLocalData = false; PasswordService.LoadFrom(null, null); return; }
            var s = JsonSerializer.Deserialize<Settings>(File.ReadAllText(SettingsFile), Opts);
            CurrentDataFile = !string.IsNullOrWhiteSpace(s?.CurrentDataFile) && File.Exists(s!.CurrentDataFile)
                ? s.CurrentDataFile! : DefaultDataFile;
            GoogleDriveFolder = s?.GoogleDriveFolder;
            SyncOnSave = s?.SyncOnSave ?? false;
            DarkMode = s?.DarkMode ?? false;
            EncryptLocalData = s?.EncryptLocalData ?? false;
            FolderBuilderBase = s?.FolderBuilderBase;
            PasswordService.LoadFrom(s?.PasswordHash, s?.PasswordSalt);

            // The shared save file is a ZIP bundle (sync target), NOT the active data file — the app
            // always works from its local data file and pushes to / pulls from the bundle.
            SharedSaveFile = string.IsNullOrWhiteSpace(s?.SharedSaveFile) ? null : s!.SharedSaveFile;
        }
        catch { CurrentDataFile = DefaultDataFile; GoogleDriveFolder = null; SyncOnSave = false; DarkMode = false; SharedSaveFile = null; EncryptLocalData = false; PasswordService.LoadFrom(null, null); }
    }

    public static void SetCurrentDataFile(string path)
    {
        CurrentDataFile = path;
        WriteSettings();
    }

    public static void SavePasswordSettings(string hash, string salt) => WriteSettings(hash, salt);

    public static void SetGoogleDriveFolder(string path)
    {
        GoogleDriveFolder = path;
        WriteSettings();
    }

    public static void SetSyncOnSave(bool on)
    {
        SyncOnSave = on;
        WriteSettings();
    }

    public static void SetDarkMode(bool on)
    {
        DarkMode = on;
        WriteSettings();
    }

    /// <summary>Turn local at-rest DPAPI encryption on/off and persist the choice. The caller is
    /// responsible for re-writing the active data file afterwards so it switches format.</summary>
    public static void SetEncryptLocalData(bool on)
    {
        EncryptLocalData = on;
        WriteSettings();
    }

    public static void SetFolderBuilderBase(string path)
    {
        FolderBuilderBase = path;
        WriteSettings();
    }

    /// <summary>Set (or, with null, clear) the shared save file — a ZIP bundle of the data AND
    /// attachments at a user-chosen location. It's a sync target; the app keeps working from its
    /// local data file, pushing to / pulling from this bundle.</summary>
    public static void SetSharedSaveFile(string? path)
    {
        SharedSaveFile = string.IsNullOrWhiteSpace(path) ? null : path;
        WriteSettings();
    }

    /// <summary>Best-effort auto-detection of the Google Drive for desktop folder across the
    /// common install layouts (profile-based Backup&amp;Sync and the "My Drive" virtual drive).</summary>
    public static string? DetectGoogleDriveFolder()
    {
        var up = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var candidates = new List<string>
        {
            Path.Combine(up, "My Drive"),
            Path.Combine(up, "Google Drive"),
            Path.Combine(up, "GoogleDrive"),
        };
        try
        {
            foreach (var d in DriveInfo.GetDrives())
                try { candidates.Add(Path.Combine(d.RootDirectory.FullName, "My Drive")); } catch { }
        }
        catch { }
        foreach (var c in candidates)
            try { if (Directory.Exists(c)) return c; } catch { }
        return null;
    }

    private static void WriteSettings(string? newHash = null, string? newSalt = null)
    {
        try
        {
            Directory.CreateDirectory(AppFolder);
            // Preserve any setting we don't overwrite this call.
            Settings? existing = null;
            if (File.Exists(SettingsFile))
                try { existing = JsonSerializer.Deserialize<Settings>(File.ReadAllText(SettingsFile), Opts); } catch { }
            var s = new Settings
            {
                CurrentDataFile = CurrentDataFile,
                PasswordHash = newHash ?? existing?.PasswordHash,
                PasswordSalt = newSalt ?? existing?.PasswordSalt,
                GoogleDriveFolder = GoogleDriveFolder ?? existing?.GoogleDriveFolder,
                SyncOnSave = SyncOnSave,
                DarkMode = DarkMode,
                FolderBuilderBase = FolderBuilderBase ?? existing?.FolderBuilderBase,
                SharedSaveFile = SharedSaveFile,
                EncryptLocalData = EncryptLocalData,
            };
            File.WriteAllText(SettingsFile, JsonSerializer.Serialize(s, Opts));
        }
        catch { /* non-fatal */ }
    }

    private static readonly JsonSerializerOptions Opts = new()
    {
        // Compact (not indented): with large imports (e.g. 2500+ Shippalm work orders per ship) this
        // makes every save ~5x faster and the data file ~35% smaller — measured 108ms→21ms / 1.6MB→1.0MB
        // for one ship of 2524 jobs. Parsing is unaffected by the lack of whitespace.
        WriteIndented = false,
        ReferenceHandler = ReferenceHandler.IgnoreCycles,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    /// <summary>True when the last <see cref="Load"/> found the data file present but could NOT read
    /// it (locked / mid-write / corrupt), so the returned empty data must NOT be trusted or saved back
    /// over the real file. False when the file was genuinely absent (empty is correct) or read fine.</summary>
    public static bool LastLoadFailed { get; private set; }

    /// <summary>The current on-disk data-format version this build writes. Bump when the model grows a
    /// field older builds must not silently drop; pair the bump with any needed forward migration.</summary>
    public const int CurrentSchemaVersion = 1;

    /// <summary>Set by <see cref="Load"/> to the file's schema version when it is NEWER than this build
    /// understands (else null). The app warns rather than silently downgrading the file — unknown top-level
    /// members are preserved via <see cref="AppData.ExtraData"/>, but a warning is still owed to the user.</summary>
    public static int? LoadedNewerSchema { get; private set; }

    public static AppData Load()
    {
        Directory.CreateDirectory(AppFolder);
        Directory.CreateDirectory(FilesFolder);
        LastLoadFailed = false;
        LoadedNewerSchema = null;
        if (!File.Exists(CurrentDataFile)) return new AppData();   // genuinely absent — empty is correct
        try
        {
            var json = ReadDataText(CurrentDataFile);
            var data = JsonSerializer.Deserialize<AppData>(json, Opts) ?? new AppData();
            if (data.SchemaVersion > CurrentSchemaVersion) LoadedNewerSchema = data.SchemaVersion;
            MigrateSchema(data);
            NormalizeFilePaths(data);
            return data;
        }
        catch { LastLoadFailed = true; return new AppData(); }      // present but unreadable — do NOT save over it
    }

    /// <summary>Load from an explicit path. Throws on read/parse failure (callers that must not adopt
    /// an empty result — e.g. shared-file reload — rely on this to skip a torn/locked read).</summary>
    public static AppData LoadFrom(string path)
    {
        var json = ReadDataText(path);   // transparently decrypts an encrypted local file
        var data = JsonSerializer.Deserialize<AppData>(json, Opts) ?? new AppData();
        MigrateSchema(data);
        NormalizeFilePaths(data);
        return data;
    }

    /// <summary>One-time forward migrations applied to any file older than <see cref="CurrentSchemaVersion"/>.
    /// v1 introduced recurrence regeneration: mark every ALREADY-completed recurring Task/Procedure as
    /// spawned, so upgrading doesn't retroactively generate a backlog of (overdue) occurrences for work the
    /// user completed under an older build. Recurrence then applies only to completions made from now on.</summary>
    private static void MigrateSchema(AppData data)
    {
        if (data.SchemaVersion < 1)
        {
            foreach (var t in data.Tasks) MarkRecurringDoneAsSpawned(t);
            foreach (var p in data.Procedures)
                if (p.Recurrence != RecurrenceKind.None && p.Status == WorkStatus.Done) p.RecurrenceSpawned = true;
        }
    }

    private static void MarkRecurringDoneAsSpawned(TaskItem t)
    {
        if (t.Recurrence != RecurrenceKind.None && t.IsComplete) t.RecurrenceSpawned = true;
        foreach (var st in t.Subtasks) MarkRecurringDoneAsSpawned(st);
    }

    public static void Save(AppData data) => WriteData(SerializeForSave(data));

    /// <summary>Serialize the model to the JSON we persist (normalising file paths first). CPU-bound and
    /// O(model size); the debounced autosave runs this on the UI thread to capture a consistent snapshot,
    /// then hands the string to <see cref="WriteData"/> on a background thread so disk I/O never blocks typing.</summary>
    public static string SerializeForSave(AppData data)
    {
        NormalizeFilePaths(data);
        // Stamp the format version so an older build can detect (and warn about) a newer file. Never
        // downgrade a higher stamp we're round-tripping — its newer fields live on in ExtraData.
        if (data.SchemaVersion < CurrentSchemaVersion) data.SchemaVersion = CurrentSchemaVersion;
        return JsonSerializer.Serialize(data, Opts);
    }

    /// <summary>Atomically write already-serialized data to the current data file (safe off the UI thread).
    /// Applies local at-rest encryption when <see cref="EncryptLocalData"/> is on.</summary>
    public static void WriteData(string json)
    {
        Directory.CreateDirectory(AppFolder);
        WriteLocalDataFile(CurrentDataFile, json);
    }

    // ---- Local at-rest encryption (DPAPI, per-machine, opt-in) ----
    // An encrypted local file is [EncMagic][DPAPI(UTF-8 JSON)]. Only the LOCAL active data file is ever
    // encrypted; every portable artifact (shared bundle, ZIP export, Drive backup) is written plaintext
    // via ReadDataText, so a DPAPI blob — unreadable on another machine/account — never leaves this PC.
    private static readonly byte[] EncMagic = System.Text.Encoding.ASCII.GetBytes("AAENC1\n");

    private static bool StartsWith(byte[] data, byte[] prefix)
    {
        if (data.Length < prefix.Length) return false;
        for (int i = 0; i < prefix.Length; i++) if (data[i] != prefix[i]) return false;
        return true;
    }

    /// <summary>Write JSON to a local data file, DPAPI-encrypting it when <see cref="EncryptLocalData"/>
    /// is on (else plaintext). Always atomic.</summary>
    /// <summary>True when <paramref name="path"/> resolves to somewhere inside the AA data folder — the
    /// only place local encryption is applied (so an external active file chosen via Import / Save As stays
    /// portable plaintext and is never rewritten as a machine-locked DPAPI blob).</summary>
    private static bool IsUnderAppFolder(string path)
    {
        try
        {
            var full = Path.GetFullPath(path);
            var root = Path.GetFullPath(AppFolder).TrimEnd('\\', '/') + Path.DirectorySeparatorChar;
            return full.StartsWith(root, StringComparison.OrdinalIgnoreCase);
        }
        catch { return false; }
    }

    private static void WriteLocalDataFile(string path, string json)
    {
        if (EncryptLocalData && IsUnderAppFolder(path))
        {
            var plain = new System.Text.UTF8Encoding(false).GetBytes(json);
            var enc = Dpapi.Protect(plain);
            var buf = new byte[EncMagic.Length + enc.Length];
            Buffer.BlockCopy(EncMagic, 0, buf, 0, EncMagic.Length);
            Buffer.BlockCopy(enc, 0, buf, EncMagic.Length, enc.Length);
            AtomicWrite(path, buf);
        }
        else AtomicWrite(path, json);
    }

    /// <summary>Read a data file as plaintext JSON, transparently DPAPI-decrypting an encrypted local
    /// file. Throws if an encrypted file can't be decrypted (wrong machine/account, or corrupt) — callers
    /// that must not adopt an empty result treat that as an unreadable file.</summary>
    private static string ReadDataText(string path)
    {
        var raw = File.ReadAllBytes(path);
        if (StartsWith(raw, EncMagic))
        {
            var enc = new byte[raw.Length - EncMagic.Length];
            Buffer.BlockCopy(raw, EncMagic.Length, enc, 0, enc.Length);
            return System.Text.Encoding.UTF8.GetString(Dpapi.Unprotect(enc));
        }
        // Plaintext (legacy or unencrypted). Strip a UTF-8 BOM if present so the parser is happy.
        int off = (raw.Length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF) ? 3 : 0;
        return System.Text.Encoding.UTF8.GetString(raw, off, raw.Length - off);
    }

    public static void SaveTo(AppData data, string path)
    {
        NormalizeFilePaths(data);
        AtomicWrite(path, JsonSerializer.Serialize(data, Opts));
    }

    /// <summary>Write via a temp file then swap it over the target, so a concurrent reader (another copy
    /// of AA polling a shared/network file) never observes a half-written or truncated file. The temp is
    /// flushed to disk (fsync) BEFORE the swap so a power loss on the vessel can't leave a zero-length or
    /// partially-flushed file; the swap itself is atomic — File.Move-overwrite first, else File.Replace
    /// (still atomic via ReplaceFile) — never a byte-by-byte copy a reader could catch mid-write. A plain
    /// copy survives only as an absolute last resort for exotic filesystems that reject both atomic ops,
    /// where persisting the save at all beats failing it.</summary>
    private static void AtomicWrite(string path, string content)
        => AtomicWrite(path, new System.Text.UTF8Encoding(false).GetBytes(content));

    private static void AtomicWrite(string path, byte[] bytes)
    {
        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        var tmp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var fs = new FileStream(tmp, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                fs.Write(bytes, 0, bytes.Length);
                fs.Flush(flushToDisk: true);                      // durable on disk before we swap it in
            }
            if (!File.Exists(path))
            {
                File.Move(tmp, path);                             // first write — nothing to replace
            }
            else
            {
                try { File.Move(tmp, path, overwrite: true); }    // atomic replace on the same volume
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                {
                    try { File.Replace(tmp, path, null, ignoreMetadataErrors: true); } // still atomic
                    catch (Exception ex2) when (ex2 is IOException or UnauthorizedAccessException or PlatformNotSupportedException)
                    {
                        File.Copy(tmp, path, overwrite: true);    // last resort only: keep the data over losing it
                    }
                }
            }
        }
        finally { try { if (File.Exists(tmp)) File.Delete(tmp); } catch { } }
    }

    public static string ImportFile(string sourcePath)
    {
        Directory.CreateDirectory(FilesFolder);
        var name = Path.GetFileName(sourcePath);
        var dest = Path.Combine(FilesFolder, $"{Guid.NewGuid():N}_{name}");
        File.Copy(sourcePath, dest, overwrite: true);
        // Return a path relative to AppFolder so the database stays portable across
        // machines / user profiles. Resolve via ResolveFilePath when actually opening.
        return Path.Combine("files", Path.GetFileName(dest)).Replace('\\', '/');
    }

    /// <summary>Turn a stored FileItem.Path (relative or legacy absolute) into an
    /// absolute path on the current machine. URLs and absolute paths outside
    /// AppFolder pass through unchanged.</summary>
    public static string ResolveFilePath(string? stored)
    {
        if (string.IsNullOrEmpty(stored)) return "";
        if (stored.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
            stored.StartsWith("https://", StringComparison.OrdinalIgnoreCase) ||
            stored.StartsWith("mailto:", StringComparison.OrdinalIgnoreCase))
            return stored;
        if (Path.IsPathRooted(stored)) return stored;
        return Path.GetFullPath(Path.Combine(AppFolder, stored));
    }

    /// <summary>Rewrite every FileItem.Path inside the database so attachments
    /// stay reachable. Three cases are handled:
    ///   1. Absolute path inside the current AppFolder → rewritten to relative ("files/xxx").
    ///   2. Foreign absolute path of the form ".../files/&lt;name&gt;" where
    ///      &lt;name&gt; also exists under the current FilesFolder (typical after a
    ///      cross-machine ZIP import) → rewritten to relative.
    ///   3. Anything else (real external files, URLs, links) is left untouched.
    /// Called on every load and before every save so legacy databases self-heal.</summary>
    public static void NormalizeFilePaths(AppData data)
    {
        if (data == null) return;
        var appFull = Path.GetFullPath(AppFolder).TrimEnd('\\', '/') + Path.DirectorySeparatorChar;
        Directory.CreateDirectory(FilesFolder);
        foreach (var c in EnumerateContainers(data))
        {
            foreach (var f in c.Files)
            {
                // Links (URLs) and in-place references (live network/local files) keep their
                // original path verbatim — never copied, never rewritten.
                if (f.IsLink || f.LinkInPlace) continue;
                var p = f.Path;
                if (string.IsNullOrEmpty(p) || !Path.IsPathRooted(p)) continue;

                // Case 1: rooted under the current AppFolder.
                try
                {
                    var full = Path.GetFullPath(p);
                    if (full.StartsWith(appFull, StringComparison.OrdinalIgnoreCase))
                    {
                        f.Path = full.Substring(appFull.Length).Replace('\\', '/');
                        continue;
                    }
                }
                catch { }

                // Case 2: foreign absolute path that still ends in "...\files\<name>"
                // — typical after importing a ZIP from another workstation. If the
                // same file name exists under our local files/, repoint to it.
                var norm = p.Replace('\\', '/');
                var idx = norm.LastIndexOf("/files/", StringComparison.OrdinalIgnoreCase);
                if (idx >= 0)
                {
                    var rel = norm.Substring(idx + 1); // "files/<name>"
                    var leafName = rel.Substring("files/".Length);
                    var candidate = Path.Combine(FilesFolder, leafName);
                    if (File.Exists(candidate))
                        f.Path = rel;
                }
            }
        }
    }

    private static IEnumerable<Container> EnumerateContainers(AppData data)
    {
        foreach (var eq in data.Equipment)
        {
            if (eq.Container != null) yield return eq.Container;
            foreach (var c in eq.Components)
                if (c.Container != null) yield return c.Container;
        }
        foreach (var t in data.Tasks)
            foreach (var c in WalkTask(t)) yield return c;
        foreach (var p in data.Procedures)
        {
            if (p.Container != null) yield return p.Container;
            foreach (var step in p.Steps)
                if (step.Container != null) yield return step.Container;
        }
        foreach (var v in data.Vessels)
            if (v.Container != null) yield return v.Container;
        // Crew members' personal checklists each have a per-step container.
        foreach (var cm in data.Crew)
            foreach (var s in cm.Checklist)
                if (s.Container != null) yield return s.Container;
        // Reusable checklist templates carry a full copy of each item's container (notes/files).
        foreach (var tpl in data.ChecklistTemplates)
            foreach (var it in tpl.Items)
                if (it.Container != null) yield return it.Container;
    }
    private static IEnumerable<Container> WalkTask(TaskItem t)
    {
        if (t.Container != null) yield return t.Container;
        foreach (var st in t.Subtasks)
            foreach (var c in WalkTask(st)) yield return c;
    }

    /// <summary>Read just the LastModified stamp from the data.json inside a backup ZIP,
    /// without extracting anything. Returns null if absent or unreadable (treated as unknown/old).</summary>
    public static DateTime? PeekZipLastModified(string zipPath)
    {
        try
        {
            using var z = ZipFile.OpenRead(zipPath);
            var entry = z.GetEntry("data.json");
            if (entry == null) return null;
            using var s = entry.Open();
            using var r = new StreamReader(s);
            return ReadLastModified(r.ReadToEnd());
        }
        catch { return null; }
    }

    /// <summary>Read just the LastModified stamp from a data.json file on disk (decrypting a local
    /// encrypted file if needed).</summary>
    public static DateTime? PeekFileLastModified(string jsonPath)
    {
        try { return ReadLastModified(ReadDataText(jsonPath)); }
        catch { return null; }
    }

    /// <summary>Deserialize the data.json inside a backup ZIP (without extracting anything),
    /// for previewing changes before an import. Returns null if unreadable.</summary>
    public static AppData? PeekZipData(string zipPath)
    {
        try
        {
            using var z = ZipFile.OpenRead(zipPath);
            var entry = z.GetEntry("data.json");
            if (entry == null) return null;
            using var s = entry.Open();
            using var r = new StreamReader(s);
            return JsonSerializer.Deserialize<AppData>(r.ReadToEnd(), Opts);
        }
        catch { return null; }
    }

    private static DateTime? ReadLastModified(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.TryGetProperty("LastModified", out var p) && p.ValueKind != JsonValueKind.Null)
                return p.GetDateTime();
        }
        catch { }
        return null;
    }

    public static FileKind ClassifyFile(string path)
    {
        var ext = Path.GetExtension(path).ToLowerInvariant();
        return ext switch
        {
            ".pdf" or ".docx" or ".doc" or ".xlsx" or ".xls" or ".pptx" or ".ppt" or ".txt" or ".rtf" => FileKind.Document,
            ".jpg" or ".jpeg" or ".png" or ".tif" or ".tiff" or ".bmp" or ".heic" or ".gif" => FileKind.Image,
            ".mov" or ".mp4" or ".wmv" or ".avi" or ".mkv" or ".m4v" or ".webm" => FileKind.Video,
            _ => FileKind.Other
        };
    }

    public static void ExportFolderToZip(string zipPath)
    {
        Directory.CreateDirectory(AppFolder);
        Directory.CreateDirectory(FilesFolder);
        if (Path.GetFullPath(zipPath).StartsWith(Path.GetFullPath(AppFolder), StringComparison.OrdinalIgnoreCase))
            throw new IOException("Choose a destination outside the AA data folder.");
        if (File.Exists(zipPath)) File.Delete(zipPath);

        // Stage the export in a temp folder so we can:
        //   1. Bundle the currently-active data file (which may live OUTSIDE AppFolder) as data.json.
        //   2. Bundle the files/ attachments folder under a relative path.
        //   3. Strip per-workstation state (settings.json with absolute CurrentDataFile).
        var staging = Path.Combine(Path.GetTempPath(), "AA_export_" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(staging);
            // Always bundle PLAINTEXT (ReadDataText decrypts a local encrypted file) so the export /
            // shared bundle / Drive backup is portable to any machine.
            if (File.Exists(CurrentDataFile))
                File.WriteAllText(Path.Combine(staging, "data.json"), ReadDataText(CurrentDataFile));
            else if (File.Exists(DefaultDataFile))
                File.WriteAllText(Path.Combine(staging, "data.json"), ReadDataText(DefaultDataFile));
            if (Directory.Exists(FilesFolder))
                CopyDirectory(FilesFolder, Path.Combine(staging, "files"));
            ZipFile.CreateFromDirectory(staging, zipPath, CompressionLevel.Optimal, includeBaseDirectory: false);
        }
        finally
        {
            try { if (Directory.Exists(staging)) Directory.Delete(staging, recursive: true); } catch { }
        }
    }

    private static void CopyDirectory(string src, string dst)
    {
        Directory.CreateDirectory(dst);
        foreach (var f in Directory.EnumerateFiles(src))
            File.Copy(f, Path.Combine(dst, Path.GetFileName(f)), overwrite: true);
        foreach (var d in Directory.EnumerateDirectories(src))
            CopyDirectory(d, Path.Combine(dst, Path.GetFileName(d)));
    }

    public static void ImportFolderFromZip(string zipPath)
    {
        Directory.CreateDirectory(AppFolder);

        // Preserve the Google OAuth client + cached token across the wipe (backup ZIPs never
        // contain them), so loading a backup from Drive doesn't log the user out / forget the client.
        byte[]? gClient = File.Exists(GoogleClientSecretFile) ? File.ReadAllBytes(GoogleClientSecretFile) : null;
        string? gTokenTemp = null;
        if (Directory.Exists(GoogleTokenFolder))
        {
            gTokenTemp = Path.Combine(Path.GetTempPath(), "AA_gtok_" + Guid.NewGuid().ToString("N"));
            try { CopyDirectory(GoogleTokenFolder, gTokenTemp); } catch { gTokenTemp = null; }
        }

        foreach (var f in Directory.GetFiles(AppFolder)) { try { File.Delete(f); } catch { } }
        foreach (var d in Directory.GetDirectories(AppFolder)) { try { Directory.Delete(d, recursive: true); } catch { } }
        ZipFile.ExtractToDirectory(zipPath, AppFolder, overwriteFiles: true);
        // Drop any settings.json the source workstation may have left in the zip:
        // its CurrentDataFile points to that machine's absolute path. Reset to default
        // so attachments resolve via the freshly-extracted relative files/ folder.
        try { var s = Path.Combine(AppFolder, "settings.json"); if (File.Exists(s)) File.Delete(s); } catch { }

        // Restore the preserved Google client + token (the extracted ZIP won't have them).
        try { if (gClient != null && !File.Exists(GoogleClientSecretFile)) File.WriteAllBytes(GoogleClientSecretFile, gClient); } catch { }
        try
        {
            if (gTokenTemp != null)
            {
                if (!Directory.Exists(GoogleTokenFolder)) CopyDirectory(gTokenTemp, GoogleTokenFolder);
                Directory.Delete(gTokenTemp, recursive: true);
            }
        }
        catch { }

        SetCurrentDataFile(DefaultDataFile);
        // Migrate any legacy absolute paths inside the imported data.json to relative.
        try
        {
            if (File.Exists(DefaultDataFile))
            {
                var data = LoadFrom(DefaultDataFile);
                MigrateLegacyAbsolutePaths(data);
                WriteLocalDataFile(DefaultDataFile, SerializeForSave(data));   // honors local encryption
            }
        }
        catch { }
    }

    /// <summary>Pull a shared-save ZIP bundle into the local app folder: replace the local data file
    /// AND the files/ attachments to match the bundle, WITHOUT touching settings / password / Google
    /// state. Extracts to a temp folder and validates BEFORE modifying anything local, so a torn or
    /// locked bundle never corrupts the local data. The active data file is (re)pointed to the local
    /// default.</summary>
    public static void ImportSharedBundle(string zipPath)
    {
        Directory.CreateDirectory(AppFolder);
        var staging = Path.Combine(Path.GetTempPath(), "AA_shared_" + Guid.NewGuid().ToString("N"));
        try
        {
            ZipFile.ExtractToDirectory(zipPath, staging);              // throws on a bad/torn bundle -> local untouched
            var dataSrc = Path.Combine(staging, "data.json");
            if (!File.Exists(dataSrc))
                throw new InvalidDataException("The shared save bundle has no data.json.");

            Directory.CreateDirectory(FilesFolder);
            var filesSrc = Path.Combine(staging, "files");
            var bundleNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            // 1) Bring in the bundle's attachments FIRST (additive: copy/overwrite, never delete yet), so
            //    the attachments exist before the data index that references them is switched over.
            if (Directory.Exists(filesSrc))
                foreach (var f in Directory.EnumerateFiles(filesSrc))
                {
                    var name = Path.GetFileName(f);
                    bundleNames.Add(name);
                    File.Copy(f, Path.Combine(FilesFolder, name), overwrite: true);
                }

            // 2) Switch the local data index to the bundle's (atomic). The bundle is plaintext; write it
            //    through the local encryption policy. Now the on-disk data.json only references attachments
            //    that are already present.
            CurrentDataFile = DefaultDataFile;
            WriteLocalDataFile(DefaultDataFile, File.ReadAllText(dataSrc));

            // 3) Only now remove local attachments the bundle no longer has (safe orphans).
            foreach (var f in Directory.EnumerateFiles(FilesFolder))
                if (!bundleNames.Contains(Path.GetFileName(f))) { try { File.Delete(f); } catch { } }

            var data = LoadFrom(DefaultDataFile);
            WriteLocalDataFile(DefaultDataFile, SerializeForSave(data));
            WriteSettings();   // persist CurrentDataFile; settings/password/Google preserved via existing
        }
        finally { try { if (Directory.Exists(staging)) Directory.Delete(staging, recursive: true); } catch { } }
    }

    /// <summary>Best-effort recovery: when an imported database still references
    /// the old workstation's absolute paths under "...\\AA\\files\\<file>", rewrite
    /// the trailing "files\\<file>" segment as the new relative path so attachments
    /// re-link to the just-extracted files/ folder.</summary>
    private static void MigrateLegacyAbsolutePaths(AppData data)
    {
        foreach (var c in EnumerateContainers(data))
        {
            foreach (var f in c.Files)
            {
                if (f.IsLink || f.LinkInPlace) continue;
                var p = f.Path;
                if (string.IsNullOrEmpty(p) || !Path.IsPathRooted(p)) continue;
                var norm = p.Replace('\\', '/');
                var idx = norm.LastIndexOf("/files/", StringComparison.OrdinalIgnoreCase);
                if (idx >= 0)
                    f.Path = norm.Substring(idx + 1); // "files/<name>"
            }
        }
    }
}
