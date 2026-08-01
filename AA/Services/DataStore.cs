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
    }

    public static void LoadSettings()
    {
        try
        {
            Directory.CreateDirectory(AppFolder);
            if (!File.Exists(SettingsFile)) { CurrentDataFile = DefaultDataFile; GoogleDriveFolder = null; SyncOnSave = false; DarkMode = false; SharedSaveFile = null; PasswordService.LoadFrom(null, null); return; }
            var s = JsonSerializer.Deserialize<Settings>(File.ReadAllText(SettingsFile), Opts);
            CurrentDataFile = !string.IsNullOrWhiteSpace(s?.CurrentDataFile) && File.Exists(s!.CurrentDataFile)
                ? s.CurrentDataFile! : DefaultDataFile;
            GoogleDriveFolder = s?.GoogleDriveFolder;
            SyncOnSave = s?.SyncOnSave ?? false;
            DarkMode = s?.DarkMode ?? false;
            FolderBuilderBase = s?.FolderBuilderBase;
            PasswordService.LoadFrom(s?.PasswordHash, s?.PasswordSalt);

            // The shared save file is a ZIP bundle (sync target), NOT the active data file — the app
            // always works from its local data file and pushes to / pulls from the bundle.
            SharedSaveFile = string.IsNullOrWhiteSpace(s?.SharedSaveFile) ? null : s!.SharedSaveFile;
        }
        catch { CurrentDataFile = DefaultDataFile; GoogleDriveFolder = null; SyncOnSave = false; DarkMode = false; SharedSaveFile = null; PasswordService.LoadFrom(null, null); }
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

    public static AppData Load()
    {
        Directory.CreateDirectory(AppFolder);
        Directory.CreateDirectory(FilesFolder);
        LastLoadFailed = false;
        if (!File.Exists(CurrentDataFile)) return new AppData();   // genuinely absent — empty is correct
        try
        {
            var json = File.ReadAllText(CurrentDataFile);
            var data = JsonSerializer.Deserialize<AppData>(json, Opts) ?? new AppData();
            NormalizeFilePaths(data);
            return data;
        }
        catch { LastLoadFailed = true; return new AppData(); }      // present but unreadable — do NOT save over it
    }

    /// <summary>Load from an explicit path. Throws on read/parse failure (callers that must not adopt
    /// an empty result — e.g. shared-file reload — rely on this to skip a torn/locked read).</summary>
    public static AppData LoadFrom(string path)
    {
        var json = File.ReadAllText(path);
        var data = JsonSerializer.Deserialize<AppData>(json, Opts) ?? new AppData();
        NormalizeFilePaths(data);
        return data;
    }

    public static void Save(AppData data) => WriteData(SerializeForSave(data));

    /// <summary>Serialize the model to the JSON we persist (normalising file paths first). CPU-bound and
    /// O(model size); the debounced autosave runs this on the UI thread to capture a consistent snapshot,
    /// then hands the string to <see cref="WriteData"/> on a background thread so disk I/O never blocks typing.</summary>
    public static string SerializeForSave(AppData data)
    {
        NormalizeFilePaths(data);
        return JsonSerializer.Serialize(data, Opts);
    }

    /// <summary>Atomically write already-serialized data to the current data file (safe off the UI thread).</summary>
    public static void WriteData(string json)
    {
        Directory.CreateDirectory(AppFolder);
        AtomicWrite(CurrentDataFile, json);
    }

    public static void SaveTo(AppData data, string path)
    {
        NormalizeFilePaths(data);
        AtomicWrite(path, JsonSerializer.Serialize(data, Opts));
    }

    /// <summary>Write via a temp file then rename over the target, so a concurrent reader (another
    /// copy of AA, on a shared/network file) never observes a half-written or truncated file. The
    /// rename is atomic on the same volume; a plain copy is the fallback for filesystems that refuse it.</summary>
    private static void AtomicWrite(string path, string content)
    {
        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        var tmp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(tmp, content);
            try { File.Move(tmp, path, overwrite: true); }        // atomic replace on the same volume
            catch { File.Copy(tmp, path, overwrite: true); }      // fallback for filesystems that disallow it
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

    /// <summary>Read just the LastModified stamp from a data.json file on disk.</summary>
    public static DateTime? PeekFileLastModified(string jsonPath)
    {
        try { return ReadLastModified(File.ReadAllText(jsonPath)); }
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
            if (File.Exists(CurrentDataFile))
                File.Copy(CurrentDataFile, Path.Combine(staging, "data.json"), overwrite: true);
            else if (File.Exists(DefaultDataFile))
                File.Copy(DefaultDataFile, Path.Combine(staging, "data.json"), overwrite: true);
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
                NormalizeFilePaths(data);
                SaveTo(data, DefaultDataFile);
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

            // 2) Switch the local data index to the bundle's (atomic). Now the on-disk data.json only
            //    references attachments that are already present.
            CurrentDataFile = DefaultDataFile;
            AtomicWrite(DefaultDataFile, File.ReadAllText(dataSrc));

            // 3) Only now remove local attachments the bundle no longer has (safe orphans).
            foreach (var f in Directory.EnumerateFiles(FilesFolder))
                if (!bundleNames.Contains(Path.GetFileName(f))) { try { File.Delete(f); } catch { } }

            var data = LoadFrom(DefaultDataFile);
            NormalizeFilePaths(data);
            SaveTo(data, DefaultDataFile);
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
