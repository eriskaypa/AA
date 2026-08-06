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
/// Uses the least-privilege <c>drive.file</c> scope (the app only sees files it creates).</summary>
public static class GoogleDriveUploader
{
    private const string BackupFolderName = "AA Backups";
    private const string SyncFolderName = "AA Sync";
    private const string SyncFileName = "AA-sync.zip";
    private const string LastModifiedProp = "aaLastModified";
    private const string IdentityProp = "aaIdentity";

    /// <summary>True once a client_secret.json has been configured.</summary>
    public static bool IsConfigured => File.Exists(DataStore.GoogleClientSecretFile);

    /// <summary>True if a Google sign-in token is already cached (so a check won't open a browser).</summary>
    public static bool HasToken =>
        Directory.Exists(DataStore.GoogleTokenFolder) &&
        Directory.EnumerateFileSystemEntries(DataStore.GoogleTokenFolder).Any();

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
            new[] { DriveService.Scope.DriveFile },
            "user",
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
        list.Q = folderId != null
            ? $"'{folderId}' in parents and trashed=false and mimeType!='application/vnd.google-apps.folder'"
            : "name contains 'aa-data' and trashed=false";
        list.Fields = "files(id,name,modifiedTime)";
        list.OrderBy = "modifiedTime desc";
        list.PageSize = 100;
        list.Spaces = "drive";
        var res = await list.ExecuteAsync(ct);
        if (res.Files == null) return Array.Empty<DriveBackup>();

        return res.Files.Select(f =>
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
        list.Q = "trashed=false and mimeType!='application/vnd.google-apps.folder' " +
                 "and (name='" + SyncFileName + "' or name contains 'aa-data')";
        list.Fields = "files(id,name,appProperties,modifiedTime)";
        list.OrderBy = "modifiedTime desc";
        list.PageSize = 100;
        list.Spaces = "drive";
        var res = await list.ExecuteAsync(ct);
        if (res.Files == null || res.Files.Count == 0) return null;

        SyncState? best = null;
        DateTime bestKey = DateTime.MinValue;
        foreach (var f in res.Files)
        {
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
