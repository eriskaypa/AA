using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Google.Apis.Auth.OAuth2;
using Google.Apis.Drive.v3;
using Google.Apis.Services;
using Google.Apis.Util.Store;
using DriveData = Google.Apis.Drive.v3.Data;

namespace AA.Services;

/// <summary>Direct upload of a backup ZIP to the user's Google Drive via the Drive API and an
/// OAuth "Desktop app" client. The user supplies their own client_secret.json (from Google Cloud
/// Console); the refresh token is cached under the AA data folder so re-uploads don't re-prompt.
///
/// <para><b>Scopes.</b> AA reads the WHOLE Drive but writes only its own files:
/// <c>drive.readonly</c> lets it find a backup wherever it lives — including one placed by hand, synced
/// in by Google Drive for desktop, or uploaded from the iPhone — while <c>drive.file</c> keeps write
/// access limited to the files AA itself created. AA therefore cannot modify or delete anything it did
/// not make, which is the least privilege that still satisfies "search my whole Drive".</para></summary>
public static class GoogleDriveUploader
{
    private const string BackupFolderName = "AA Backups";
    private const string SyncFolderName = "AA Sync";
    private const string SyncFileName = "AA-sync.zip";
    private const string LastModifiedProp = "aaLastModified";
    private const string IdentityProp = "aaIdentity";

    /// <summary>Read every file in the Drive; create/modify only AA's own.</summary>
    private static readonly string[] Scopes = { DriveService.Scope.DriveReadonly, DriveService.Scope.DriveFile };

    /// <summary>Bumped whenever <see cref="Scopes"/> changes. A cached refresh token only carries the
    /// scopes it was granted under, and Google's library happily reuses it — so a token minted for the
    /// old, narrower scope would keep "working" while silently returning only AA's own files, which is
    /// exactly the bug this change fixes. Versioning the token's user key mints a fresh one instead, so
    /// the broader consent is actually obtained rather than assumed.</summary>
    private const string ScopeVersion = "v2-wholedrive";

    /// <summary>Backup name prefix used by the iOS app (<c>AA-backup-iOS-…​.aaz</c>, or
    /// <c>AA-backup-iOS-dataonly-…​.aaz</c> when it sends text only).</summary>
    private const string IosBackupPrefix = "AA-backup";

    /// <summary>Is this Drive file a bundle AA can restore? This MIRRORS the iOS app's
    /// <c>isRestorableBundle</c> (AA/GoogleDrive.swift) exactly, so both apps agree on what counts —
    /// any <c>.aaz</c>, or a <c>.zip</c> whose name carries <c>aa-data</c> / <c>aa-backup</c>.
    ///
    /// The check matters more now that AA reads the whole Drive: under the old <c>drive.file</c> scope
    /// only AA's own uploads could ever come back, so a bare name match was proof enough. A Google Doc
    /// called "aa-database notes" would match the query today, and offering to import it would fail
    /// confusingly at best.</summary>
    private static bool IsBundleCandidate(DriveData.File f) =>
        IsRestorableBundleName(f.Name, f.MimeType);

    /// <summary>The name rule, exposed so it can be tested directly — it is the contract between the two
    /// apps, and a wrong answer here means either missing a real backup or offering to import a stranger.</summary>
    public static bool IsRestorableBundleName(string? name, string? mimeType = null)
    {
        if (string.IsNullOrEmpty(name)) return false;
        // A Google-native file (Doc/Sheet/folder) is not a download at all.
        if (mimeType != null && mimeType.StartsWith("application/vnd.google-apps", StringComparison.Ordinal)) return false;

        var n = name.ToLowerInvariant();
        if (n.EndsWith(".aaz", StringComparison.Ordinal)) return true;      // covers AA-backup-iOS-*.aaz
        if (!n.EndsWith(".zip", StringComparison.Ordinal)) return false;
        // "aa-data" and "aa-backup" match iOS. "aa-sync" is the Windows-only rolling sync file, which iOS
        // never restores from and so omits — leaving it out here would break sync-on-save detection.
        return n.Contains("aa-data", StringComparison.Ordinal)
            || n.Contains("aa-backup", StringComparison.Ordinal)
            || n.Contains("aa-sync", StringComparison.Ordinal);
    }

    /// <summary>The name terms that find every bundle either app writes. Deliberately word-PREFIX terms:
    /// Drive's <c>contains</c> on <c>name</c> matches word prefixes, so a term like <c>'.aaz'</c> is not
    /// dependable on its own — <c>AA-backup</c> is what actually finds the iOS uploads. Client-side
    /// <see cref="IsBundleCandidate"/> does the precise filtering.</summary>
    private static string BundleNameQuery =>
        $"(name contains 'aa-data' or name contains '{IosBackupPrefix}' or name contains 'AA-sync' or name contains '.aaz')";

    /// <summary>Search the user's ENTIRE Drive, shared drives included — "my whole Drive" means the
    /// files shared with them too, not just My Drive.</summary>
    private static void SearchWholeDrive(FilesResource.ListRequest list)
    {
        list.Spaces = "drive";
        list.IncludeItemsFromAllDrives = true;
        list.SupportsAllDrives = true;
        list.PageSize = 200;
    }

    /// <summary>Run a whole-Drive search to completion. Paging matters here: the name query is broad, so
    /// a first page full of near-misses could otherwise hide the real backup behind it. Capped so a very
    /// large Drive can't turn a background sync check into an unbounded crawl.</summary>
    private static async Task<List<DriveData.File>> ListAllPagesAsync(
        FilesResource.ListRequest list, CancellationToken ct, int maxPages = 10)
    {
        var all = new List<DriveData.File>();
        string? token = null;
        for (int page = 0; page < maxPages; page++)
        {
            list.PageToken = token;
            var res = await list.ExecuteAsync(ct);
            if (res.Files != null) all.AddRange(res.Files);
            token = res.NextPageToken;
            if (string.IsNullOrEmpty(token)) break;
        }
        return all;
    }

    /// <summary>True once a client_secret.json has been configured.</summary>
    public static bool IsConfigured => File.Exists(DataStore.GoogleClientSecretFile);

    /// <summary>True if a Google sign-in token for the CURRENT scopes is cached (so a check won't open a
    /// browser). Deliberately version-specific: a token left over from the old narrower scope must not
    /// count, or a background sync check would pop a consent browser out of nowhere.</summary>
    public static bool HasToken =>
        Directory.Exists(DataStore.GoogleTokenFolder) &&
        Directory.EnumerateFiles(DataStore.GoogleTokenFolder)
                 .Any(f => Path.GetFileName(f).EndsWith("-" + ScopeVersion, StringComparison.Ordinal));

    /// <summary>True when a sign-in exists but only under the previous, narrower scope — i.e. Drive
    /// searches would quietly see just AA's own files until the user re-consents.</summary>
    public static bool NeedsReconsentForWholeDrive =>
        !HasToken &&
        Directory.Exists(DataStore.GoogleTokenFolder) &&
        Directory.EnumerateFiles(DataStore.GoogleTokenFolder).Any();

    /// <summary>Copy the chosen client_secret.json into the AA data folder.</summary>
    public static void SetClientSecret(string sourceJsonPath)
    {
        Directory.CreateDirectory(DataStore.AppFolder);
        File.Copy(sourceJsonPath, DataStore.GoogleClientSecretFile, overwrite: true);
    }

    /// <summary>Forget the cached Google token so the next upload re-prompts for consent.</summary>
    public static void SignOut()
    {
        try { if (Directory.Exists(DataStore.GoogleTokenFolder)) Directory.Delete(DataStore.GoogleTokenFolder, recursive: true); }
        catch { /* best effort */ }
    }

    public readonly record struct UploadResult(string Name, string? Link);

    /// <summary>One backup file living in the Drive "AA Backups" folder.</summary>
    public readonly record struct DriveBackup(string Id, string Name, DateTimeOffset? Modified)
    {
        public string Display => Modified.HasValue
            ? $"{Name}    (uploaded {Modified.Value.LocalDateTime:yyyy-MM-dd HH:mm})"
            : Name;
    }

    /// <summary>Authorize (opening a browser the first time) and build a Drive service.</summary>
    private static async Task<DriveService> GetServiceAsync(CancellationToken ct)
    {
        if (!IsConfigured)
            throw new InvalidOperationException(
                "No Google OAuth client configured. Use File ▸ 'Set Google OAuth client...' first.");

        ClientSecrets secrets;
        await using (var s = File.OpenRead(DataStore.GoogleClientSecretFile))
            secrets = (await GoogleClientSecrets.FromStreamAsync(s, ct)).Secrets;

        var credential = await GoogleWebAuthorizationBroker.AuthorizeAsync(
            secrets,
            Scopes,
            ScopeVersion,
            ct,
            // DPAPI-encrypt the cached refresh token at rest (migrates an existing plaintext token on
            // first read) instead of the library's default cleartext FileDataStore.
            new DpapiDataStore(DataStore.GoogleTokenFolder));

        return new DriveService(new BaseClientService.Initializer
        {
            HttpClientInitializer = credential,
            ApplicationName = "AA"
        });
    }

    /// <summary>Authorize (opening a browser the first time) and upload the file to Drive,
    /// inside an "AA Backups" folder. Returns the uploaded file's name and web link.</summary>
    public static async Task<UploadResult> UploadAsync(string localFilePath, CancellationToken ct = default)
    {
        using var service = await GetServiceAsync(ct);
        var folderId = await EnsureBackupFolderAsync(service, ct);

        var meta = new DriveData.File
        {
            Name = Path.GetFileName(localFilePath),
            AppProperties = new Dictionary<string, string> { [IdentityProp] = DataStore.AppIdentity }
        };
        if (folderId != null) meta.Parents = new List<string> { folderId };

        await using var media = File.OpenRead(localFilePath);
        var request = service.Files.Create(meta, media, "application/zip");
        request.Fields = "id, name, webViewLink";
        var progress = await request.UploadAsync(ct);
        if (progress.Status != Google.Apis.Upload.UploadStatus.Completed)
            throw progress.Exception ?? new Exception("Upload did not complete.");

        var file = request.ResponseBody;
        return new UploadResult(file?.Name ?? meta.Name, file?.WebViewLink);
    }

    /// <summary>List the backups this app has stored in the Drive "AA Backups" folder, newest first.</summary>
    public static async Task<IReadOnlyList<DriveBackup>> ListBackupsAsync(CancellationToken ct = default)
    {
        using var service = await GetServiceAsync(ct);
        var folderId = await EnsureBackupFolderAsync(service, ct);

        var list = service.Files.List();
        // The AA Backups folder contents PLUS any aa-data* / .aaz bundle anywhere in the Drive.
        var where = folderId != null
            ? $"('{folderId}' in parents or {BundleNameQuery})"
            : BundleNameQuery;
        list.Q = where + " and trashed=false and mimeType!='application/vnd.google-apps.folder'";
        list.Fields = "files(id,name,modifiedTime,mimeType)";
        list.OrderBy = "modifiedTime desc";
        SearchWholeDrive(list);
        var files = await ListAllPagesAsync(list, ct);
        if (files.Count == 0) return Array.Empty<DriveBackup>();

        return files.Where(IsBundleCandidate).Select(f =>
        {
            DateTimeOffset? when = DateTimeOffset.TryParse(f.ModifiedTimeRaw, out var dto) ? dto : null;
            return new DriveBackup(f.Id, f.Name, when);
        }).ToList();
    }

    /// <summary>Download a Drive file (by id) to a local path.</summary>
    public static async Task DownloadAsync(string fileId, string destPath, CancellationToken ct = default)
    {
        using var service = await GetServiceAsync(ct);
        await using var fs = File.Create(destPath);
        var progress = await service.Files.Get(fileId).DownloadAsync(fs, ct);
        if (progress.Status != Google.Apis.Download.DownloadStatus.Completed)
            throw progress.Exception ?? new Exception("Download did not complete.");
    }

    private static Task<string?> EnsureBackupFolderAsync(DriveService service, CancellationToken ct)
        => EnsureFolderAsync(service, BackupFolderName, ct);

    private static async Task<string?> EnsureFolderAsync(DriveService service, string name, CancellationToken ct)
    {
        try
        {
            var list = service.Files.List();
            list.Q = $"mimeType='application/vnd.google-apps.folder' and name='{name}' and trashed=false";
            list.Fields = "files(id,name)";
            list.Spaces = "drive";
            var res = await list.ExecuteAsync(ct);
            if (res.Files is { Count: > 0 }) return res.Files[0].Id;

            var meta = new DriveData.File { Name = name, MimeType = "application/vnd.google-apps.folder" };
            var create = service.Files.Create(meta);
            create.Fields = "id";
            var created = await create.ExecuteAsync(ct);
            return created.Id;
        }
        catch
        {
            return null; // fall back to Drive root
        }
    }

    // ---- Real-time sync (single rolling AA-sync.zip carrying the data's save time) ----

    /// <summary>State of the remote sync file: its Drive id and the data's own LastModified
    /// (read cheaply from appProperties, no download).</summary>
    public readonly record struct SyncState(string FileId, DateTime? LastModified, DateTimeOffset? DriveModified, string? Identity);

    /// <summary>Read the remote sync file's metadata only (no content download). Null if none yet.</summary>
    public static async Task<SyncState?> GetSyncStateAsync(CancellationToken ct = default)
    {
        using var service = await GetServiceAsync(ct);
        var folderId = await EnsureFolderAsync(service, SyncFolderName, ct);

        var list = service.Files.List();
        list.Q = folderId != null
            ? $"'{folderId}' in parents and name='{SyncFileName}' and trashed=false"
            : $"name='{SyncFileName}' and trashed=false";
        list.Fields = "files(id,appProperties,modifiedTime)";
        list.Spaces = "drive";
        list.PageSize = 1;
        var res = await list.ExecuteAsync(ct);
        var f = res.Files?.FirstOrDefault();
        if (f == null) return null;

        DateTime? last = null;
        if (f.AppProperties != null && f.AppProperties.TryGetValue(LastModifiedProp, out var raw) &&
            DateTime.TryParse(raw, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var dt))
            last = dt;
        string? identity = null;
        if (f.AppProperties != null && f.AppProperties.TryGetValue(IdentityProp, out var idRaw) && !string.IsNullOrWhiteSpace(idRaw))
            identity = idRaw;
        DateTimeOffset? driveMod = DateTimeOffset.TryParse(f.ModifiedTimeRaw, out var dto) ? dto : null;
        return new SyncState(f.Id, last, driveMod, identity);
    }

    /// <summary>Detect the newest AA save anywhere in the user's Drive — the rolling <c>AA-sync.zip</c> OR
    /// any <c>aa-data*</c> backup (uploaded via OAuth or synced into Drive by Google Drive for desktop),
    /// wherever it lives. Keyed by the data's own LastModified (from appProperties) when present, otherwise
    /// by the Drive modifiedTime (for synced-folder backups that carry no appProperties). Null if none.</summary>
    public static async Task<SyncState?> GetBestRemoteAsync(CancellationToken ct = default)
    {
        using var service = await GetServiceAsync(ct);
        var list = service.Files.List();
        // Match the rolling sync file, any aa-data* backup, OR any .aaz bundle — anywhere in the Drive.
        list.Q = "trashed=false and mimeType!='application/vnd.google-apps.folder' " +
                 $"and (name='{SyncFileName}' or {BundleNameQuery})";
        list.Fields = "files(id,name,appProperties,modifiedTime,mimeType)";
        list.OrderBy = "modifiedTime desc";
        SearchWholeDrive(list);
        var files = await ListAllPagesAsync(list, ct);
        if (files.Count == 0) return null;

        SyncState? best = null;
        DateTime bestKey = DateTime.MinValue;
        foreach (var f in files)
        {
            if (!IsBundleCandidate(f)) continue;   // a name match is not proof of an AA bundle any more
            DateTime? last = null;
            if (f.AppProperties != null && f.AppProperties.TryGetValue(LastModifiedProp, out var raw) &&
                DateTime.TryParse(raw, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var dt))
                last = dt;
            string? identity = null;
            if (f.AppProperties != null && f.AppProperties.TryGetValue(IdentityProp, out var idr) && !string.IsNullOrWhiteSpace(idr))
                identity = idr;
            DateTimeOffset? driveMod = DateTimeOffset.TryParse(f.ModifiedTimeRaw, out var dto) ? dto : null;
            var key = last ?? driveMod?.UtcDateTime ?? DateTime.MinValue;
            if (key > bestKey) { bestKey = key; best = new SyncState(f.Id, last, driveMod, identity); }
        }
        return best;
    }

    /// <summary>Push the local backup to the single rolling sync file (create or overwrite),
    /// stamping the data's LastModified into appProperties. Returns the updated state.</summary>
    public static async Task<SyncState> PushSyncAsync(string localZipPath, DateTime? lastModified, CancellationToken ct = default)
    {
        using var service = await GetServiceAsync(ct);
        var folderId = await EnsureFolderAsync(service, SyncFolderName, ct);

        // Does the rolling file already exist?
        string? existingId = null;
        {
            var list = service.Files.List();
            list.Q = folderId != null
                ? $"'{folderId}' in parents and name='{SyncFileName}' and trashed=false"
                : $"name='{SyncFileName}' and trashed=false";
            list.Fields = "files(id)";
            list.Spaces = "drive";
            list.PageSize = 1;
            var res = await list.ExecuteAsync(ct);
            existingId = res.Files?.FirstOrDefault()?.Id;
        }

        var props = new Dictionary<string, string>
        {
            [LastModifiedProp] = lastModified?.ToString("o") ?? "",
            [IdentityProp] = DataStore.AppIdentity
        };

        string id;
        await using (var media = File.OpenRead(localZipPath))
        {
            if (existingId != null)
            {
                var body = new DriveData.File { AppProperties = props };   // no Parents on update
                var req = service.Files.Update(body, existingId, media, "application/zip");
                req.Fields = "id";
                var progress = await req.UploadAsync(ct);
                if (progress.Status != Google.Apis.Upload.UploadStatus.Completed)
                    throw progress.Exception ?? new Exception("Sync upload did not complete.");
                id = req.ResponseBody?.Id ?? existingId;
            }
            else
            {
                var body = new DriveData.File { Name = SyncFileName, AppProperties = props };
                if (folderId != null) body.Parents = new List<string> { folderId };
                var req = service.Files.Create(body, media, "application/zip");
                req.Fields = "id";
                var progress = await req.UploadAsync(ct);
                if (progress.Status != Google.Apis.Upload.UploadStatus.Completed)
                    throw progress.Exception ?? new Exception("Sync upload did not complete.");
                id = req.ResponseBody?.Id ?? "";
            }
        }
        return new SyncState(id, lastModified, null, DataStore.AppIdentity);
    }

    /// <summary>Download the rolling sync file to a local path.</summary>
    public static Task DownloadSyncAsync(string fileId, string destPath, CancellationToken ct = default)
        => DownloadAsync(fileId, destPath, ct);
}
