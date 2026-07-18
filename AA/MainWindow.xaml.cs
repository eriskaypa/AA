using System;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using AA.Models;
using AA.Services;
using AA.Views;
using Microsoft.Win32;

namespace AA;

public partial class MainWindow : Window
{
    private AppRepository _repo = null!;
    private DispatcherTimer? _autoSaveTimer;
    private bool _restoringUi;
    private Views.FloatingTasksWindow? _floating;
    private Views.QuickWorkWindow? _quickWork;

    // Google Drive sync-on-save state.
    private DispatcherTimer? _syncDebounce;
    private bool _syncRunning, _syncQueued;
    private DateTime? _lastSeenRemote;

    // Shared save file (single-file multi-instance sync) state.
    private DispatcherTimer? _sharedSaveTimer;   // periodic save to the shared file (every 10 min)
    private DispatcherTimer? _sharedSyncTimer;   // periodic poll for external updates
    private DispatcherTimer? _sharedDebounce;    // debounce for FileSystemWatcher bursts
    private FileSystemWatcher? _sharedWatcher;
    private DateTime? _sharedLastSeen;           // last BUNDLE stamp we've handled (dedup / self-write)
    private DateTime? _lastSyncedStamp;          // data stamp we last pushed to / pulled from the bundle
    private bool _handlingSharedUpdate;

    public MainWindow()
    {
        InitializeComponent();
        Loaded += OnLoaded;
        Closing += OnClosing;
        // Keep the Crew tab badge in sync whenever the roster changes.
        CrewPg.Changed += UpdateCrewTabHeader;

        // Coalesce rapid Ctrl+S into a single background push to Drive.
        _syncDebounce = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1500) };
        _syncDebounce.Tick += (_, _) => { _syncDebounce!.Stop(); RunSyncPush(); };
    }

    private void OnLoaded(object? sender, RoutedEventArgs e)
    {
        LoadDataAndInitUi();
        StartAutoSaveTimer();
        SyncOnSaveMenu.IsChecked = DataStore.SyncOnSave;
        DarkModeMenu.IsChecked = DataStore.DarkMode;
        // On startup, if sync is on and we're already signed in, see if another PC pushed a newer save.
        if (DataStore.SyncOnSave && GoogleDriveUploader.IsConfigured && GoogleDriveUploader.HasToken)
            CheckRemoteNewer(false);

        // Notify (once) about any crew contracts already overdue or due soon.
        Dispatcher.BeginInvoke(new Action(() => CrewPg.CheckExpiries(interactive: false)),
            DispatcherPriority.Background);

        // If a shared save file is configured, start the 10-min push + external-update watch, and do an
        // immediate check so we adopt a newer bundle another copy wrote while this PC was closed.
        _sharedLastSeen = _repo?.Data.LastModified;
        _lastSyncedStamp = _repo?.Data.LastModified;   // treat startup state as in-sync with the bundle
        StartSharedSaveSync();
        if (!string.IsNullOrWhiteSpace(DataStore.SharedSaveFile))
            Dispatcher.BeginInvoke(new Action(() => CheckSharedFileForUpdate()), DispatcherPriority.Background);
    }

    private void OnClosing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        StopSharedSaveSync();   // stop the watcher so our final save doesn't trip a reload
        // Flush rich-text edits from whichever container is currently loaded.
        FlushAllEditors();
        CaptureUiState();
        try { _repo.Save(); } catch { /* ignore on close */ }
        // Push our final state (data + attachments) to the shared bundle, but only if we're not older
        // than it — never clobber a newer version another copy just wrote.
        if (!string.IsNullOrWhiteSpace(DataStore.SharedSaveFile))
        {
            try
            {
                var fileStamp = DataStore.PeekZipLastModified(DataStore.SharedSaveFile);
                var local = _repo.Data.LastModified;
                if (!fileStamp.HasValue || (local.HasValue && local.Value >= fileStamp.Value))
                    PushToShared("Shared save (on close)");
            }
            catch { }
        }
    }

    private void FlushAllEditors()
    {
        try
        {
            EquipmentPage.FlushPendingEditors();
            TasksPage.FlushPendingEditors();
            ProceduresPage.FlushPendingEditors();
            VesselsPage.FlushPendingEditors();
        }
        catch { }
    }

    private void StartAutoSaveTimer()
    {
        _autoSaveTimer?.Stop();
        _autoSaveTimer = new DispatcherTimer { Interval = TimeSpan.FromMinutes(5) };
        _autoSaveTimer.Tick += (_, _) => { DoAutosave(); CheckRemoteNewer(false); };
        _autoSaveTimer.Start();
    }

    private void DoAutosave()
    {
        try
        {
            if (_repo == null) return;
            EquipmentPage.FlushPendingEditors();
            TasksPage.FlushPendingEditors();
            ProceduresPage.FlushPendingEditors();
            VesselsPage.FlushPendingEditors();
            if (!_repo.IsDirty)
            {
                StatusBlock.Text = $"Autosave \u2014 no changes ({DateTime.Now:HH:mm:ss})";
                return;
            }
            CaptureUiState();
            _repo.Save();
            StatusBlock.Text = $"Autosaved {DateTime.Now:HH:mm:ss}";
        }
        catch (Exception ex)
        {
            StatusBlock.Text = $"Autosave failed: {ex.Message}";
        }
    }

    private void SaveCommand_Executed(object sender, ExecutedRoutedEventArgs e) => DoSave();
    private void MenuSave_Click(object sender, RoutedEventArgs e) => DoSave();

    private void FindCommand_Executed(object sender, ExecutedRoutedEventArgs e) => OpenSearch();
    private void NewCommand_Executed(object sender, ExecutedRoutedEventArgs e) => OpenQuickWork();
    private void OpenCommand_Executed(object sender, ExecutedRoutedEventArgs e) => OpenQuickSwitcher();

    // ---- Quick switcher (Ctrl+O) — Obsidian-style fuzzy jump ----
    private void MenuQuickSwitcher_Click(object sender, RoutedEventArgs e) => OpenQuickSwitcher();
    private void OpenQuickSwitcher()
    {
        if (_repo == null) return;
        new Views.QuickSwitcherWindow(_repo, NavigateToItem) { Owner = this }.ShowDialog();
    }

    // ---- Quick work window (Ctrl+N) + Activity log + Unit converter ----
    private void MenuQuickWork_Click(object sender, RoutedEventArgs e) => OpenQuickWork();
    private void OpenQuickWork()
    {
        if (_quickWork != null) { _quickWork.Activate(); return; }
        _quickWork = new Views.QuickWorkWindow(_repo, NavigateToItem) { Owner = this };
        _quickWork.Closed += (_, _) => _quickWork = null;
        _quickWork.Show();
    }

    private void MenuActivityLog_Click(object sender, RoutedEventArgs e)
        => new Views.ActivityLogWindow(_repo) { Owner = this }.Show();

    private void MenuUnitConverter_Click(object sender, RoutedEventArgs e)
        => new Views.UnitConverterWindow { Owner = this }.Show();
    private void OpenSearch_Click(object sender, RoutedEventArgs e) => OpenSearch();
    private void OpenSearch()
    {
        var w = new Views.SearchWindow(_repo, NavigateToItem) { Owner = this };
        w.Show();
    }

    private void NavigateToItem(AA.Models.HierarchyItem item)
    {
        var (idx, page) = item.Kind switch
        {
            AA.Models.ItemKind.Equipment => (0, EquipmentPage),
            AA.Models.ItemKind.Task      => (1, TasksPage),
            AA.Models.ItemKind.Procedure => (2, ProceduresPage),
            AA.Models.ItemKind.Vessel    => (3, VesselsPage),
            _ => (0, EquipmentPage)
        };
        MainTabs.SelectedIndex = idx;
        Dispatcher.BeginInvoke(new Action(() => page.SelectItemById(item.Id)),
            System.Windows.Threading.DispatcherPriority.Background);
    }

    private void DoSave()
    {
        try
        {
            EquipmentPage.FlushPendingEditors();
            TasksPage.FlushPendingEditors();
            ProceduresPage.FlushPendingEditors();
            VesselsPage.FlushPendingEditors();
            CaptureUiState();
            _repo.Save();
            StatusBlock.Text = $"Saved {DateTime.Now:HH:mm:ss}";
            MaybeQueueSync();
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Save failed", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    // ---- Google Drive real-time sync ----
    private void MaybeQueueSync()
    {
        if (!DataStore.SyncOnSave || !GoogleDriveUploader.IsConfigured) return;
        _syncDebounce?.Stop();
        _syncDebounce?.Start();
    }

    /// <summary>Push the current data to the rolling Drive sync file in the background. Coalesces:
    /// if a push is already running, the latest request runs again right after it finishes.</summary>
    private async void RunSyncPush()
    {
        if (_repo == null || !DataStore.SyncOnSave || !GoogleDriveUploader.IsConfigured) return;
        if (_syncRunning) { _syncQueued = true; return; }
        _syncRunning = true;
        try
        {
            do
            {
                _syncQueued = false;
                var stamp = _repo.Data.LastModified;
                var temp = Path.Combine(Path.GetTempPath(), $"aa-sync-{Guid.NewGuid():N}.zip");
                try
                {
                    StatusBlock.Text = "Syncing to Google Drive…";
                    await System.Threading.Tasks.Task.Run(() => DataStore.ExportFolderToZip(temp));
                    await GoogleDriveUploader.PushSyncAsync(temp, stamp);
                    _lastSeenRemote = stamp;   // our own push is now the latest remote
                    StatusBlock.Text = $"Synced to Google Drive {DateTime.Now:HH:mm:ss}";
                }
                finally { try { File.Delete(temp); } catch { } }
            }
            while (_syncQueued);
        }
        catch (Exception ex)
        {
            StatusBlock.Text = $"Drive sync failed: {ex.Message}";
        }
        finally { _syncRunning = false; }
    }

    /// <summary>Check the Drive sync file for a newer save than the local one. When found, offer to
    /// load it. <paramref name="interactive"/> = launched from a menu (may open a sign-in browser).</summary>
    private async void CheckRemoteNewer(bool interactive)
    {
        if (_repo == null) return;
        if (!DataStore.SyncOnSave || !GoogleDriveUploader.IsConfigured)
        {
            if (interactive)
                MessageBox.Show(this, "Turn on 'Sync to Google Drive on save' and set a Google OAuth client first.",
                    "Google Drive sync", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (!interactive && !GoogleDriveUploader.HasToken) return; // don't pop a browser unprompted

        string? temp = null;
        try
        {
            var state = await GoogleDriveUploader.GetSyncStateAsync();
            if (state == null) { if (interactive) StatusBlock.Text = "No sync file on Google Drive yet."; return; }

            var remote = state.Value.LastModified;
            var local = _repo.Data.LastModified;
            bool newer = remote.HasValue && (!local.HasValue || remote.Value > local.Value);
            if (!newer) { StatusBlock.Text = $"Google Drive is up to date ({DateTime.Now:HH:mm:ss})."; return; }

            // Avoid re-prompting for the same remote version we already declined.
            if (!interactive && _lastSeenRemote.HasValue && remote.HasValue && remote.Value == _lastSeenRemote.Value) return;
            _lastSeenRemote = remote;

            StatusBlock.Text = "Newer save on Google Drive — downloading to preview…";
            temp = Path.Combine(Path.GetTempPath(), $"aa-sync-{Guid.NewGuid():N}.zip");
            await GoogleDriveUploader.DownloadSyncAsync(state.Value.FileId, temp);
            var incoming = DataStore.PeekZipData(temp);
            if (!ReviewAndConfirmImport(incoming, remote, "Google Drive (newer save)"))
            { StatusBlock.Text = "Kept local version (Drive has a newer one)."; return; }

            DataStore.ImportFolderFromZip(temp);
            LoadDataAndInitUi();
            SyncOnSaveMenu.IsChecked = DataStore.SyncOnSave;
            _lastSeenRemote = _repo.Data.LastModified;
            StatusBlock.Text = "Loaded newer save from Google Drive.";
        }
        catch (Exception ex)
        {
            if (interactive) MessageBox.Show(this, ex.Message, "Drive sync check failed", MessageBoxButton.OK, MessageBoxImage.Error);
            else StatusBlock.Text = $"Drive check failed: {ex.Message}";
        }
        finally
        {
            if (temp != null) { try { File.Delete(temp); } catch { } }
        }
    }

    private void MenuSyncOnSave_Click(object sender, RoutedEventArgs e)
    {
        DataStore.SetSyncOnSave(SyncOnSaveMenu.IsChecked);
        if (SyncOnSaveMenu.IsChecked)
        {
            StatusBlock.Text = "Google Drive sync on save: ON";
            if (!GoogleDriveUploader.IsConfigured)
                MessageBox.Show(this,
                    "Sync is on. Set your Google OAuth client via File ▸ 'Set Google OAuth client...' so saves can reach Drive.",
                    "Google Drive sync", MessageBoxButton.OK, MessageBoxImage.Information);
            else
                CheckRemoteNewer(true);
        }
        else StatusBlock.Text = "Google Drive sync on save: OFF";
    }

    private void MenuCheckRemote_Click(object sender, RoutedEventArgs e) => CheckRemoteNewer(true);

    private void MenuSaveAs_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new SaveFileDialog
        {
            Filter = "AA data (*.json)|*.json|All files (*.*)|*.*",
            FileName = "aa-data.json",
            InitialDirectory = DataStore.AppFolder
        };
        if (dlg.ShowDialog() == true)
        {
            try
            {
                CaptureUiState();
                _repo.Data.LastModified = DateTime.Now;
                DataStore.SaveTo(_repo.Data, dlg.FileName);
                StatusBlock.Text = $"Exported to {dlg.FileName}";
            }
            catch (Exception ex)
            {
                MessageBox.Show(ex.Message, "Save As failed", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }

    private void MenuLoad_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show("Reload data from disk? Unsaved changes will be lost.",
                "Confirm reload", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        LoadDataAndInitUi();
        StatusBlock.Text = $"Reloaded {DateTime.Now:HH:mm:ss}";
    }

    private void MenuImport_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog
        {
            Filter = "AA data (*.json)|*.json|All files (*.*)|*.*",
            InitialDirectory = DataStore.AppFolder
        };
        if (dlg.ShowDialog() == true)
        {
            AppData data;
            try { data = DataStore.LoadFrom(dlg.FileName); }
            catch (Exception ex) { MessageBox.Show(ex.Message, "Import failed", MessageBoxButton.OK, MessageBoxImage.Error); return; }

            if (!ReviewAndConfirmImport(data, data.LastModified, Path.GetFileName(dlg.FileName))) return;
            try
            {
                _repo = new AppRepository(data);
                InitPagesAndRestoreUi();
                // Remember this path as the active data file so future Saves and the next
                // launch route to it instead of the default %LOCALAPPDATA%\AA\data.json.
                DataStore.SetCurrentDataFile(dlg.FileName);
                DataStore.Save(_repo.Data);
                StatusBlock.Text = $"Loaded \u2014 {DataStore.CurrentDataFile}";
            }
            catch (Exception ex)
            {
                MessageBox.Show(ex.Message, "Import failed", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }

    private void MenuOpenFolder_Click(object sender, RoutedEventArgs e)
    {
        try { Process.Start(new ProcessStartInfo("explorer.exe", DataStore.AppFolder)); }
        catch (Exception ex) { MessageBox.Show(ex.Message, "Open failed"); }
    }

    private void MenuExportFolder_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new SaveFileDialog
        {
            Filter = "ZIP archive (*.zip)|*.zip|All files (*.*)|*.*",
            FileName = $"aa-data-{DateTime.Now:yyyyMMdd-HHmm}.zip"
        };
        if (dlg.ShowDialog() != true) return;
        try
        {
            CaptureUiState();
            _repo.Save();   // stamps LastModified, then ExportFolderToZip bundles the saved file
            DataStore.ExportFolderToZip(dlg.FileName);
            StatusBlock.Text = $"Exported data folder to {dlg.FileName}";
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Export failed", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void MenuImportFolder_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog
        {
            Filter = "ZIP archive (*.zip)|*.zip|All files (*.*)|*.*"
        };
        if (dlg.ShowDialog() != true) return;
        var incoming = DataStore.PeekZipData(dlg.FileName);
        if (!ReviewAndConfirmImport(incoming, incoming?.LastModified, Path.GetFileName(dlg.FileName))) return;
        try
        {
            DataStore.ImportFolderFromZip(dlg.FileName);
            LoadDataAndInitUi();
            StatusBlock.Text = $"Imported data folder from {Path.GetFileName(dlg.FileName)}";
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Import failed", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    /// <summary>Show a full change preview (added / changed / removed) plus an age comparison for an
    /// incoming database, and let the user decide whether to overwrite. Used by every import path.</summary>
    private bool ReviewAndConfirmImport(AppData? incoming, DateTime? incomingLast, string sourceName)
    {
        if (incoming == null)
        {
            // Couldn't read the incoming data for a preview — fall back to a plain confirm.
            return MessageBox.Show(this,
                $"Replace your current data with '{sourceName}'?\n(Could not read a change preview for this source.)",
                "Confirm import", MessageBoxButton.YesNo, MessageBoxImage.Warning) == MessageBoxResult.Yes;
        }
        var diff = DataDiff.Compare(_repo.Data, incoming);
        var age = AgeVerdict(incomingLast, _repo.Data.LastModified);
        var win = new Views.DiffWindow(sourceName, age, diff) { Owner = this };
        return win.ShowDialog() == true;
    }

    /// <summary>Human-readable comparison of two save times (newer / older / same / unknown).</summary>
    private static string AgeVerdict(DateTime? incoming, DateTime? current)
    {
        string inc = incoming?.ToString("yyyy-MM-dd HH:mm:ss") ?? "(no save date)";
        string cur = current?.ToString("yyyy-MM-dd HH:mm:ss") ?? "(no save date)";
        string verdict;
        if (incoming.HasValue && current.HasValue)
            verdict = incoming.Value > current.Value ? "➜ The incoming data is NEWER than your current data."
                    : incoming.Value < current.Value ? "➜ The incoming data is OLDER than your current data."
                    : "➜ The incoming data is the SAME age as your current data.";
        else if (incoming.HasValue && !current.HasValue) verdict = "➜ Your current data has no save date; relative age is unknown.";
        else if (!incoming.HasValue && current.HasValue) verdict = "➜ The incoming data has no save date (older format); it may be older.";
        else verdict = "➜ Neither copy has a save date; relative age is unknown.";
        return $"Incoming saved: {inc}\nCurrent saved:  {cur}\n{verdict}";
    }

    // ---- Google Drive (synced-folder backup) ----
    private void MenuSaveToDrive_Click(object sender, RoutedEventArgs e)
    {
        var folder = ResolveDriveFolder(forcePick: false);
        if (folder == null) return;
        try
        {
            EquipmentPage.FlushPendingEditors(); TasksPage.FlushPendingEditors();
            ProceduresPage.FlushPendingEditors(); VesselsPage.FlushPendingEditors();
            CaptureUiState();
            _repo.Save();   // stamps LastModified
            var backups = Path.Combine(folder, "AA Backups");
            Directory.CreateDirectory(backups);
            var zip = Path.Combine(backups, $"aa-data-{DateTime.Now:yyyyMMdd-HHmmss}.zip");
            DataStore.ExportFolderToZip(zip);
            StatusBlock.Text = $"Saved a copy to Google Drive: {zip}";
            MessageBox.Show(this,
                $"A backup was saved to your Google Drive folder:\n\n{zip}\n\nGoogle Drive for desktop will sync it to the cloud.",
                "Saved to Google Drive", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Save to Google Drive failed", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void MenuSetDriveFolder_Click(object sender, RoutedEventArgs e) => ResolveDriveFolder(forcePick: true);

    // ---- Google Drive (direct OAuth upload via the Drive API) ----
    private void MenuSetOAuthClient_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog
        {
            Title = "Select the OAuth client_secret.json downloaded from Google Cloud Console",
            Filter = "Google client secret (*.json)|*.json|All files (*.*)|*.*"
        };
        if (dlg.ShowDialog() != true) return;
        try
        {
            GoogleDriveUploader.SetClientSecret(dlg.FileName);
            StatusBlock.Text = "Google OAuth client set.";
            MessageBox.Show(this,
                "Google OAuth client saved.\n\nMake sure in Google Cloud Console you have:\n" +
                "  • Enabled the Google Drive API\n" +
                "  • Created an OAuth client of type 'Desktop app'\n" +
                "  • Added your Google account as a test user (if the consent screen is in Testing)\n\n" +
                "Now use File ▸ 'Upload backup to Google Drive (OAuth)...'.",
                "Google OAuth", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Set OAuth client failed", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async void MenuUploadDriveOAuth_Click(object sender, RoutedEventArgs e)
    {
        if (!GoogleDriveUploader.IsConfigured)
        {
            if (MessageBox.Show(this,
                    "No Google OAuth client is configured yet. Choose your client_secret.json now?",
                    "Google OAuth", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
            MenuSetOAuthClient_Click(sender, e);
            if (!GoogleDriveUploader.IsConfigured) return;
        }

        string? temp = null;
        try
        {
            EquipmentPage.FlushPendingEditors(); TasksPage.FlushPendingEditors();
            ProceduresPage.FlushPendingEditors(); VesselsPage.FlushPendingEditors();
            CaptureUiState();
            _repo.Save();   // stamps LastModified

            temp = Path.Combine(Path.GetTempPath(), $"aa-data-{DateTime.Now:yyyyMMdd-HHmmss}.zip");
            DataStore.ExportFolderToZip(temp);

            StatusBlock.Text = "Signing in to Google and uploading… (a browser window may open)";
            var result = await GoogleDriveUploader.UploadAsync(temp);

            StatusBlock.Text = $"Uploaded to Google Drive: {result.Name}";
            MessageBox.Show(this,
                $"Uploaded '{result.Name}' to your Google Drive (folder 'AA Backups')." +
                (string.IsNullOrEmpty(result.Link) ? "" : $"\n\n{result.Link}"),
                "Uploaded to Google Drive", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            StatusBlock.Text = "Google Drive upload failed.";
            MessageBox.Show(this, ex.Message, "Google Drive upload failed", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            if (temp != null) { try { File.Delete(temp); } catch { } }
        }
    }

    private async void MenuLoadDriveOAuth_Click(object sender, RoutedEventArgs e)
    {
        if (!GoogleDriveUploader.IsConfigured)
        {
            if (MessageBox.Show(this,
                    "No Google OAuth client is configured yet. Choose your client_secret.json now?",
                    "Google OAuth", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
            MenuSetOAuthClient_Click(sender, e);
            if (!GoogleDriveUploader.IsConfigured) return;
        }

        string? temp = null;
        try
        {
            StatusBlock.Text = "Signing in to Google and listing backups… (a browser window may open)";
            var backups = await GoogleDriveUploader.ListBackupsAsync();
            if (backups.Count == 0)
            {
                StatusBlock.Text = "No backups found on Google Drive.";
                MessageBox.Show(this, "No backups were found in your Google Drive 'AA Backups' folder.\n\n" +
                    "Upload one first with File ▸ 'Upload backup to Google Drive (OAuth)...'.",
                    "Load from Google Drive", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            var picker = new Views.ItemPickerWindow("Choose a backup to load from Google Drive (newest first)",
                backups.Select(b => new Views.PickerItem { Display = b.Display, Tag = b }), singleSelect: true)
            { Owner = this };
            if (picker.ShowDialog() != true) return;
            if (picker.SelectedTags.FirstOrDefault() is not GoogleDriveUploader.DriveBackup chosen) return;

            StatusBlock.Text = $"Downloading {chosen.Name}…";
            temp = Path.Combine(Path.GetTempPath(), $"aa-drive-{DateTime.Now:yyyyMMddHHmmss}.zip");
            await GoogleDriveUploader.DownloadAsync(chosen.Id, temp);

            // Preview changes (and the newer/older comparison) before overwriting.
            var incoming = DataStore.PeekZipData(temp);
            if (!ReviewAndConfirmImport(incoming, incoming?.LastModified, $"Google Drive: {chosen.Name}"))
            { StatusBlock.Text = "Load from Google Drive cancelled."; return; }

            DataStore.ImportFolderFromZip(temp);
            LoadDataAndInitUi();
            StatusBlock.Text = $"Loaded backup from Google Drive: {chosen.Name}";
        }
        catch (Exception ex)
        {
            StatusBlock.Text = "Load from Google Drive failed.";
            MessageBox.Show(this, ex.Message, "Load from Google Drive failed", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            if (temp != null) { try { File.Delete(temp); } catch { } }
        }
    }

    private void MenuGoogleSignOut_Click(object sender, RoutedEventArgs e)
    {
        GoogleDriveUploader.SignOut();
        StatusBlock.Text = "Signed out of Google (OAuth token cleared).";
    }

    /// <summary>Resolve the Google Drive folder: use the remembered one, else auto-detect, else
    /// ask the user to locate it (and remember the choice). forcePick always re-prompts.</summary>
    private string? ResolveDriveFolder(bool forcePick)
    {
        if (!forcePick)
        {
            var saved = DataStore.GoogleDriveFolder;
            if (!string.IsNullOrWhiteSpace(saved) && Directory.Exists(saved)) return saved;
            var detected = DataStore.DetectGoogleDriveFolder();
            if (detected != null) { DataStore.SetGoogleDriveFolder(detected); return detected; }
        }
        MessageBox.Show(this, forcePick
            ? "Select your Google Drive folder — the local folder that Google Drive for desktop syncs."
            : "Couldn't find your Google Drive folder automatically. Please locate the local folder that Google Drive for desktop syncs.",
            "Locate Google Drive", MessageBoxButton.OK, MessageBoxImage.Information);
        var dlg = new System.Windows.Forms.FolderBrowserDialog { Description = "Select your Google Drive folder" };
        if (dlg.ShowDialog() == System.Windows.Forms.DialogResult.OK && Directory.Exists(dlg.SelectedPath))
        {
            DataStore.SetGoogleDriveFolder(dlg.SelectedPath);
            StatusBlock.Text = $"Google Drive folder set: {dlg.SelectedPath}";
            return dlg.SelectedPath;
        }
        return null;
    }

    private void MenuDarkMode_Click(object sender, RoutedEventArgs e)
    {
        DataStore.SetDarkMode(DarkModeMenu.IsChecked);
        ThemeManager.Apply(DarkModeMenu.IsChecked);
        StatusBlock.Text = DarkModeMenu.IsChecked ? "Dark mode on." : "Dark mode off.";
    }

    private void MenuExit_Click(object sender, RoutedEventArgs e) => Close();

    private void MenuAbout_Click(object sender, RoutedEventArgs e)
        => MessageBox.Show(this, "Created by B.E.P. Avida - May 2026", "About AA", MessageBoxButton.OK, MessageBoxImage.Information);

    private void MenuFolderBuilder_Click(object sender, RoutedEventArgs e)
    {
        var w = new Views.FolderBuilderWindow { Owner = this };
        w.ShowDialog();
    }

    private void MenuDateCalc_Click(object sender, RoutedEventArgs e)
    {
        var w = new Views.DateCalculatorWindow { Owner = this };
        w.ShowDialog();
    }

    private void MenuSetPassword_Click(object sender, RoutedEventArgs e)
    {
        var mode = PasswordService.HasPassword ? PasswordWindow.Mode.ChangeExisting : PasswordWindow.Mode.SetNew;
        var w = new PasswordWindow(mode) { Owner = this };
        if (w.ShowDialog() != true || string.IsNullOrEmpty(w.Password)) return;
        var (hash, salt) = PasswordService.SetPassword(w.Password);
        DataStore.SavePasswordSettings(hash, salt);
        StatusBlock.Text = "App password updated.";
    }

    private void MenuLockNow_Click(object sender, RoutedEventArgs e)
    {
        PasswordService.Lock();
        ItemLockService.RelockAll();   // forget per-item session unlocks too
        StatusBlock.Text = "Locked. Locked containers and entries will require re-unlocking.";
        // Re-apply the lock gate to each page's current selection (preserving it), so any open
        // locked entry immediately shows its padlock instead of its contents.
        EquipmentPage.RelockCurrent();
        TasksPage.RelockCurrent();
        ProceduresPage.RelockCurrent();
        VesselsPage.RelockCurrent();
    }

    // ---- Crew (COMPAS import + contract expiries) ----
    private void MenuImportCompas_Click(object sender, RoutedEventArgs e)
    {
        MainTabs.SelectedItem = CrewTab;
        CrewPg.ImportCompas();
    }

    private void MenuCheckExpiries_Click(object sender, RoutedEventArgs e)
    {
        MainTabs.SelectedItem = CrewTab;
        CrewPg.CheckExpiries(interactive: true);
    }

    /// <summary>Badge the Crew tab with the count of contracts overdue or due soon.</summary>
    private void UpdateCrewTabHeader()
    {
        int n = CrewPg.ExpiringCount;
        CrewTab.Header = n > 0 ? $"Crew  ⚠ {n}" : "Crew";
    }

    // ---- Floating due-dates window ----
    private void OpenFloating_Click(object sender, RoutedEventArgs e) => OpenDueDatesWindow();
    private void RefreshDueCommand_Executed(object sender, ExecutedRoutedEventArgs e) => OpenDueDatesWindow();

    private void OpenDueDatesWindow()
    {
        if (_floating != null) { _floating.Activate(); _floating.Refresh(); return; }
        _floating = new Views.FloatingTasksWindow(_repo, NavigateToItem, NavigateToCrew) { Owner = this };
        _floating.Closed += (_, _) => _floating = null;
        _floating.Show();
    }

    /// <summary>Switch to the Crew tab and select a crew member (from the due-dates window).</summary>
    private void NavigateToCrew(AA.Models.CrewMember m)
    {
        MainTabs.SelectedItem = CrewTab;
        Dispatcher.BeginInvoke(new Action(() => CrewPg.SelectMember(m)),
            System.Windows.Threading.DispatcherPriority.Background);
    }

    // ---- Shared save file (one ZIP bundle: data + attachments, at a location you choose) ----

    private void StartSharedSaveSync()
    {
        StopSharedSaveSync();
        var path = DataStore.SharedSaveFile;
        if (string.IsNullOrWhiteSpace(path)) return;

        // Save to the shared file every 10 minutes (only when there are changes, to avoid churn).
        _sharedSaveTimer = new DispatcherTimer { Interval = TimeSpan.FromMinutes(10) };
        _sharedSaveTimer.Tick += (_, _) => SharedSaveTick();
        _sharedSaveTimer.Start();

        // Poll for external updates (reliable fallback for network/synced folders where the OS
        // watcher may not raise events).
        _sharedSyncTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(60) };
        _sharedSyncTimer.Tick += (_, _) => CheckSharedFileForUpdate();
        _sharedSyncTimer.Start();

        // Debounce a burst of watcher events into a single check.
        _sharedDebounce = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1500) };
        _sharedDebounce.Tick += (_, _) => { _sharedDebounce!.Stop(); CheckSharedFileForUpdate(); };

        try
        {
            var dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(dir) && Directory.Exists(dir))
            {
                _sharedWatcher = new FileSystemWatcher(dir, Path.GetFileName(path)!)
                {
                    NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.FileName | NotifyFilters.CreationTime
                };
                void Bump() => Dispatcher.BeginInvoke(new Action(() => { _sharedDebounce?.Stop(); _sharedDebounce?.Start(); }));
                _sharedWatcher.Changed += (_, _) => Bump();
                _sharedWatcher.Created += (_, _) => Bump();
                _sharedWatcher.Renamed += (_, _) => Bump();
                _sharedWatcher.EnableRaisingEvents = true;
            }
        }
        catch { /* watcher is best-effort; the 60s poll still detects changes */ }
    }

    private void StopSharedSaveSync()
    {
        _sharedSaveTimer?.Stop(); _sharedSaveTimer = null;
        _sharedSyncTimer?.Stop(); _sharedSyncTimer = null;
        _sharedDebounce?.Stop(); _sharedDebounce = null;
        if (_sharedWatcher != null)
        {
            try { _sharedWatcher.EnableRaisingEvents = false; _sharedWatcher.Dispose(); } catch { }
            _sharedWatcher = null;
        }
    }

    /// <summary>Every 10 minutes: first reconcile (adopt a newer bundle another copy wrote), then push
    /// our data AND attachments to the shared bundle if we have changes.</summary>
    private void SharedSaveTick()
    {
        if (_repo == null || string.IsNullOrWhiteSpace(DataStore.SharedSaveFile) || _handlingSharedUpdate) return;
        CheckSharedFileForUpdate();                 // don't overwrite a newer version from another copy
        FlushAllEditors();
        if (!_repo.IsDirty) return;                 // nothing changed — don't churn the shared bundle
        PushToShared("Shared save");
    }

    /// <summary>Bundle the current data AND all attachments into the shared ZIP, written atomically
    /// (temp file + rename) so another copy never reads a half-written bundle.</summary>
    private void PushToShared(string label)
    {
        var path = DataStore.SharedSaveFile;
        if (_repo == null || string.IsNullOrWhiteSpace(path)) return;
        var tmp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            FlushAllEditors();
            CaptureUiState();
            _repo.Save();                            // write local data.json (attachments already live in files/)
            DataStore.ExportFolderToZip(tmp);        // bundle data.json + files/ into a temp zip
            File.Move(tmp, path!, overwrite: true);  // atomic replace
            _sharedLastSeen = _repo.Data.LastModified;
            _lastSyncedStamp = _repo.Data.LastModified;   // our local state now matches the bundle
            StatusBlock.Text = $"{label} written {DateTime.Now:HH:mm:ss} (data + attachments).";
        }
        catch (Exception ex) { StatusBlock.Text = $"{label} failed: {ex.Message}"; }
        finally { try { if (File.Exists(tmp)) File.Delete(tmp); } catch { } }
    }

    /// <summary>If the shared bundle is newer than our data (another copy of AA saved it), reload it —
    /// with its attachments — silently when we have no unsaved changes, otherwise after confirming.</summary>
    private void CheckSharedFileForUpdate()
    {
        if (_repo == null || _handlingSharedUpdate) return;
        var path = DataStore.SharedSaveFile;
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) return;

        var fileStamp = DataStore.PeekZipLastModified(path);
        if (fileStamp == null) return;                  // unreadable / mid-write — try again next tick
        var local = _repo.Data.LastModified;
        bool newer = !local.HasValue || fileStamp.Value > local.Value;
        if (!newer) return;
        if (_sharedLastSeen.HasValue && fileStamp.Value == _sharedLastSeen.Value) return;

        _handlingSharedUpdate = true;
        try
        {
            FlushAllEditors();
            // "Unsynced local changes" = in-flight edits (IsDirty) OR data saved locally that we haven't
            // pushed to the bundle yet (local stamp newer than what we last synced). Either way, don't
            // silently discard them — confirm first.
            bool unsynced = _repo.IsDirty
                || (_repo.Data.LastModified is DateTime lm && (_lastSyncedStamp == null || lm > _lastSyncedStamp.Value));
            if (unsynced)
            {
                var choice = MessageBox.Show(this,
                    "The shared save file was updated by another copy of AA.\n\n" +
                    "Reload it now (data + attachments)? Changes on this PC that aren't in the shared file yet will be lost.\n\n" +
                    "Yes = reload (discard my changes)\n" +
                    "No = keep mine (they overwrite the shared file on the next save)",
                    "Shared save updated", MessageBoxButton.YesNo, MessageBoxImage.Question);
                if (choice != MessageBoxResult.Yes) { _sharedLastSeen = fileStamp; return; }
            }
            // Validates + extracts to a temp folder first, so a torn/locked bundle leaves local data intact.
            DataStore.ImportSharedBundle(path);
            LoadDataAndInitUi();
            _sharedLastSeen = _repo.Data.LastModified;
            _lastSyncedStamp = _repo.Data.LastModified;   // now in sync with the bundle
            StatusBlock.Text = $"Reloaded the shared save with attachments ({DateTime.Now:HH:mm:ss}).";
        }
        catch (Exception ex) { StatusBlock.Text = $"Shared reload skipped (busy): {ex.Message}"; }
        finally { _handlingSharedUpdate = false; }
    }

    private void MenuSetSharedFile_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new SaveFileDialog
        {
            Title = "Choose the single shared save file (put it on a network drive or synced folder). It bundles your data AND attachments.",
            Filter = "AA shared save (*.zip)|*.zip|All files (*.*)|*.*",
            FileName = "aa-shared.zip",
            OverwritePrompt = false
        };
        if (dlg.ShowDialog() != true) return;
        var path = dlg.FileName;
        try
        {
            FlushAllEditors();
            if (File.Exists(path))
            {
                var choice = MessageBox.Show(this,
                    $"'{Path.GetFileName(path)}' already exists.\n\n" +
                    "Use ITS contents (data + attachments) as your data (Yes), or keep your current data and overwrite it (No)?",
                    "Shared save file", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
                if (choice == MessageBoxResult.Cancel) return;
                DataStore.SetSharedSaveFile(path);
                if (choice == MessageBoxResult.Yes)
                {
                    DataStore.ImportSharedBundle(path);   // adopt the existing bundle (data + attachments)
                    LoadDataAndInitUi();
                    _sharedLastSeen = _repo.Data.LastModified;
                    _lastSyncedStamp = _repo.Data.LastModified;
                }
                else PushToShared("Shared save");         // overwrite it with our data + attachments
            }
            else
            {
                DataStore.SetSharedSaveFile(path);
                PushToShared("Shared save");              // create the bundle from our data + attachments
            }
            StartSharedSaveSync();
            StatusBlock.Text = $"Shared save file set — {path}";
            MessageBox.Show(this,
                $"This copy of AA now saves to and syncs from:\n\n{path}\n\n" +
                "It bundles your data AND all attachments, autosaves there every 10 minutes, and reloads " +
                "automatically when another copy of AA updates it. Point every PC at this same file.",
                "Shared save file", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            DataStore.SetSharedSaveFile(null);
            MessageBox.Show(this, ex.Message, "Set shared save file failed", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void MenuStopSharedFile_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(DataStore.SharedSaveFile))
        {
            StatusBlock.Text = "No shared save file is set.";
            return;
        }
        if (MessageBox.Show(this,
                "Stop using the shared save file and save locally on this PC only from now on?\n(Your current data is kept.)",
                "Stop shared save file", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        StopSharedSaveSync();
        DataStore.SetSharedSaveFile(null);
        StatusBlock.Text = "Stopped using the shared save file (now saving locally).";
    }

    private void LoadDataAndInitUi()
    {
        DataStore.LoadSettings();
        var data = DataStore.Load();
        _repo = new AppRepository(data);
        InitPagesAndRestoreUi();
        StatusBlock.Text = $"Loaded \u2014 {DataStore.CurrentDataFile}";
    }

    private void InitPagesAndRestoreUi()
    {
        _restoringUi = true;
        EquipmentPage.Init(_repo, ItemKind.Equipment);
        TasksPage.Init(_repo, ItemKind.Task);
        ProceduresPage.Init(_repo, ItemKind.Procedure);
        VesselsPage.Init(_repo, ItemKind.Vessel);
        CalendarPg.Init(_repo, NavigateToItem);
        BoardPg.Init(_repo);
        PlannerPg.Init(_repo);
        MapPage.Init(_repo);
        EquipmentPage.Navigate = NavigateToItem;
        TasksPage.Navigate = NavigateToItem;
        ProceduresPage.Navigate = NavigateToItem;
        VesselsPage.Navigate = NavigateToItem;
        CrewPg.Init(_repo);
        ListsPg.Init(_repo);
        BucketsPg.Init(_repo);
        BucketsPg.Navigate = NavigateToItem;
        PortsPg.Init(_repo);
        UpdateCrewTabHeader();
        _floating?.SetRepo(_repo);    // keep the floating due-dates window pointed at the current data
        _quickWork?.SetRepo(_repo);   // and the Ctrl+N quick-work window (avoids writing to an orphaned repo)

        var ui = _repo.Data.Ui;
        if (ui.WindowWidth is double w && w > 200) Width = w;
        if (ui.WindowHeight is double h && h > 200) Height = h;
        if (ui.WindowLeft is double l) Left = l;
        if (ui.WindowTop is double t) Top = t;
        if (Enum.TryParse<WindowState>(ui.WindowState, out var ws))
            WindowState = ws == WindowState.Minimized ? WindowState.Normal : ws;

        if (ui.SelectedEquipmentId is Guid eid) EquipmentPage.SelectItemById(eid);
        if (ui.SelectedTaskId is Guid tid) TasksPage.SelectItemById(tid);
        if (ui.SelectedProcedureId is Guid pid) ProceduresPage.SelectItemById(pid);
        if (ui.SelectedVesselId is Guid vid) VesselsPage.SelectItemById(vid);

        if (ui.SelectedMainTabIndex >= 0 && ui.SelectedMainTabIndex < MainTabs.Items.Count)
            MainTabs.SelectedIndex = ui.SelectedMainTabIndex;

        // Restore the shortcuts strip visibility.
        ShortcutBarMenu.IsChecked = ui.ShowShortcutBar;
        ShortcutBar.Visibility = ui.ShowShortcutBar ? Visibility.Visible : Visibility.Collapsed;

        // Apply the saved tab order, then any customised tab colours.
        ApplyTabOrder();
        ApplyTabColors();

        _restoringUi = false;
    }

    // ---- Drag-to-reorder main tabs ----
    private TabItem? _dragTab;
    private System.Windows.Point _tabDragStart;

    private void Tab_PreviewMouseDown(object sender, MouseButtonEventArgs e)
    {
        _tabDragStart = e.GetPosition(null);
        _dragTab = FindAncestor<TabItem>(e.OriginalSource as System.Windows.DependencyObject);
    }

    private void Tab_PreviewMouseMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed || _dragTab == null) return;
        var pos = e.GetPosition(null);
        if (Math.Abs(pos.X - _tabDragStart.X) < SystemParameters.MinimumHorizontalDragDistance &&
            Math.Abs(pos.Y - _tabDragStart.Y) < SystemParameters.MinimumVerticalDragDistance) return;
        try { System.Windows.DragDrop.DoDragDrop(_dragTab, _dragTab, System.Windows.DragDropEffects.Move); }
        catch { /* drag cancelled */ }
    }

    private void Tab_Drop(object sender, System.Windows.DragEventArgs e)
    {
        var dragged = _dragTab;
        _dragTab = null;
        if (dragged == null) return;
        var target = FindAncestor<TabItem>(e.OriginalSource as System.Windows.DependencyObject);
        if (target == null || ReferenceEquals(target, dragged)) return;
        int to = MainTabs.Items.IndexOf(target);
        if (to < 0 || !MainTabs.Items.Contains(dragged)) return;
        MainTabs.Items.Remove(dragged);
        MainTabs.Items.Insert(to, dragged);
        MainTabs.SelectedItem = dragged;
        PersistTabOrder();
    }

    private void PersistTabOrder()
    {
        if (_repo == null) return;
        _repo.Data.Ui.TabOrder = MainTabs.Items.OfType<TabItem>()
            .Select(t => t.Name).Where(n => !string.IsNullOrEmpty(n)).ToList();
        _repo.MarkDirty();
    }

    /// <summary>Reorder the main tabs to the saved order (names not in the list keep their relative order
    /// after the listed ones, so newly-added tabs still appear).</summary>
    private void ApplyTabOrder()
    {
        var order = _repo?.Data.Ui.TabOrder;
        if (order == null || order.Count == 0) return;
        var byName = MainTabs.Items.OfType<TabItem>()
            .Where(t => !string.IsNullOrEmpty(t.Name)).ToDictionary(t => t.Name);
        var desired = new List<TabItem>();
        foreach (var name in order)
            if (byName.TryGetValue(name, out var t) && !desired.Contains(t)) desired.Add(t);
        foreach (var t in MainTabs.Items.OfType<TabItem>())
            if (!desired.Contains(t)) desired.Add(t);
        if (desired.Count != MainTabs.Items.Count) return;   // safety
        // Only reorder if it actually differs.
        bool same = !desired.Where((t, i) => !ReferenceEquals(MainTabs.Items[i], t)).Any();
        if (same) return;
        var sel = MainTabs.SelectedItem;
        MainTabs.Items.Clear();
        foreach (var t in desired) MainTabs.Items.Add(t);
        MainTabs.SelectedItem = sel ?? (desired.Count > 0 ? desired[0] : null);
    }

    // Content-safe: e.OriginalSource can be a FlowDocument/Run (rich-text content) when a tab hosts a
    // rich-text editor; walking that via VisualTreeHelper.GetParent would throw. UiTree handles it.
    private static T? FindAncestor<T>(System.Windows.DependencyObject? d) where T : System.Windows.DependencyObject
        => AA.Views.UiTree.FindAncestor<T>(d);

    // ---- Custom tab colours ----
    private void MenuTabColors_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null) return;
        var tabs = MainTabs.Items.OfType<TabItem>()
            .Where(t => !string.IsNullOrEmpty(t.Name))
            .Select(t => (t.Name, Label: t.Name == "CrewTab" ? "Crew" : (t.Header?.ToString() ?? t.Name)))
            .ToList();
        var dlg = new Views.TabColorsWindow(tabs, _repo.Data.Ui.TabColors) { Owner = this };
        if (dlg.ShowDialog() != true) return;
        _repo.Data.Ui.TabColors = dlg.Result;
        _repo.MarkDirty();
        ApplyTabColors();
    }

    /// <summary>Apply the persisted per-tab colours to the main tabs (clearing any tab without a
    /// custom colour so it falls back to the theme default).</summary>
    private void ApplyTabColors()
    {
        var colors = _repo?.Data.Ui.TabColors;
        foreach (var item in MainTabs.Items.OfType<TabItem>())
        {
            if (!string.IsNullOrEmpty(item.Name) && colors != null
                && colors.TryGetValue(item.Name, out var hex) && TryBrush(hex, out var brush))
            {
                item.Background = brush;
                item.Foreground = ContrastBrush(brush.Color);
            }
            else
            {
                item.ClearValue(TabItem.BackgroundProperty);
                item.ClearValue(TabItem.ForegroundProperty);
            }
        }
    }

    private static bool TryBrush(string hex, out System.Windows.Media.SolidColorBrush brush)
    {
        try
        {
            var c = (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(hex);
            brush = new System.Windows.Media.SolidColorBrush(c); brush.Freeze(); return true;
        }
        catch { brush = System.Windows.Media.Brushes.Transparent; return false; }
    }

    /// <summary>Black or white, whichever reads better on the given background colour.</summary>
    private static System.Windows.Media.Brush ContrastBrush(System.Windows.Media.Color c)
    {
        double lum = (0.299 * c.R + 0.587 * c.G + 0.114 * c.B);
        return lum > 150 ? System.Windows.Media.Brushes.Black : System.Windows.Media.Brushes.White;
    }

    // ---- Keyboard-shortcuts reminder strip ----
    private void HideShortcutBar_Click(object sender, RoutedEventArgs e) => SetShortcutBar(false);
    private void MenuShortcutBar_Click(object sender, RoutedEventArgs e) => SetShortcutBar(ShortcutBarMenu.IsChecked);
    private void SetShortcutBar(bool show)
    {
        ShortcutBar.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
        ShortcutBarMenu.IsChecked = show;
        if (_repo != null) { _repo.Data.Ui.ShowShortcutBar = show; _repo.MarkDirty(); }
    }

    private void CaptureUiState()
    {
        if (_repo == null) return;
        var ui = _repo.Data.Ui;
        if (WindowState == WindowState.Normal)
        {
            ui.WindowLeft = Left;
            ui.WindowTop = Top;
            ui.WindowWidth = Width;
            ui.WindowHeight = Height;
        }
        ui.WindowState = WindowState.ToString();
        ui.SelectedMainTabIndex = MainTabs.SelectedIndex;
        ui.SelectedEquipmentId = EquipmentPage.SelectedItemId;
        ui.SelectedTaskId = TasksPage.SelectedItemId;
        ui.SelectedProcedureId = ProceduresPage.SelectedItemId;
        ui.SelectedVesselId = VesselsPage.SelectedItemId;
        ui.CalendarSelectedDate = CalendarPg.CalendarSelectedDate;
        ui.CalendarViewMode = CalendarPg.CalendarViewMode;
        ui.MapFocusedItemId = MapPage.FocusedItemId;
    }

    private void MainTabs_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (e.OriginalSource != MainTabs) return;
        if (MainTabs.SelectedItem is TabItem ti)
        {
            if (ti.Content == CalendarPg) CalendarPg.Refresh();
            if (ti.Content == BoardPg) BoardPg.Refresh();
            if (ti.Content == PlannerPg) PlannerPg.Refresh();
            if (ti.Content == MapPage) MapPage.RefreshSidebar();
            if (ti.Content == CrewPg) CrewPg.Refresh();
            if (ti.Content == ListsPg) ListsPg.Refresh();
            if (ti.Content == BucketsPg) BucketsPg.Refresh();
            if (ti.Content == PortsPg) PortsPg.Refresh();
        }
        if (!_restoringUi && _repo != null)
            _repo.Data.Ui.SelectedMainTabIndex = MainTabs.SelectedIndex;
    }
}
