using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using AA.Models;
using AA.Services;
using AA.Sire;

namespace AA.Views;

/// <summary>The SIRE 2.0 Knowledge Bank tab: browse/filter the 410-question OCIMF library, track a
/// per-question inspection session (status/bookmark/tasks) persisted in the AA database, generate tasks
/// offline or via Gemini AI, and quick-add any question / section / chapter into AA as an
/// Equipment / Task / Procedure with cross-linked top-level tasks.</summary>
public partial class SirePage : UserControl
{
    private AppRepository? _repo;
    private Action<HierarchyItem>? _navigate;
    private Action? _refreshAa;
    private bool _loaded;      // combos/checkboxes wired
    private bool _bankReady;   // bank loaded + list populated
    private SireQuestion? _selected;
    private readonly List<CheckBox> _chapterBoxes = new();
    private readonly List<CheckBox> _vesselBoxes = new();
    private readonly List<CheckBox> _typeBoxes = new();

    public SirePage() { InitializeComponent(); }

    private SireState State => _repo!.Data.Sire;

    public void Init(AppRepository repo, Action<HierarchyItem> navigate, Action refreshAa)
    {
        _repo = repo; _navigate = navigate; _refreshAa = refreshAa;
        if (_bankReady) { SyncQuestionFlags(); UpdateStats(); RefreshTasks(); UpdateActionButtons(); }
    }

    /// <summary>Deferred load — the 3.2 MB question bank is parsed only when the SIRE tab is first shown.</summary>
    public async void EnsureLoaded()
    {
        if (_bankReady || _repo == null) return;
        _bankReady = true;   // guard re-entry during the async load
        LoadingOverlay.Visibility = Visibility.Visible;
        LoadingText.Text = "Loading SIRE 2.0 question bank…";
        await System.Threading.Tasks.Task.Run(() => SireBank.EnsureLoaded());
        if (SireBank.LoadError != null)
        {
            LoadingText.Text = $"Could not load the SIRE question bank:\n{SireBank.LoadError}";
            _bankReady = false;
            return;
        }
        BuildFilters();
        SyncQuestionFlags();
        _loaded = true;
        ApplyFilters();
        UpdateStats();
        LoadingOverlay.Visibility = Visibility.Collapsed;
    }

    // ---------- Filters ----------

    private void BuildFilters()
    {
        SortCombo.ItemsSource = new[] { "Question Number", "Chapter", "Short Question Text", "Vessel Types", "ROVIQ Sequence", "Question Type" };
        SortCombo.SelectedIndex = 0;
        EvidenceCombo.ItemsSource = new[] { "All", "Equipment", "Document", "Procedure", "Record", "Personnel" };
        EvidenceCombo.SelectedIndex = 0;
        StatusFilterCombo.ItemsSource = new[] { "All", "In Progress", "Checked", "Not Applicable", "Bookmarked", "For Export", "Has Tasks", "No Status" };
        StatusFilterCombo.SelectedIndex = 0;

        _chapterBoxes.Clear(); ChapterPanel.Children.Clear();
        foreach (var g in SireBank.ByChapter())
        {
            var name = g.First().ChapterName;
            AddCheck(ChapterPanel, _chapterBoxes, g.Key, $"Ch {g.Key}: {name} ({g.Count()})");
        }
        _vesselBoxes.Clear(); VesselPanel.Children.Clear();
        foreach (var vt in SireBank.Questions.SelectMany(q => q.VesselTypes).Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(v => v))
            AddCheck(VesselPanel, _vesselBoxes, vt, vt);
        _typeBoxes.Clear(); TypePanel.Children.Clear();
        foreach (var t in SireBank.Questions.Select(q => q.QuestionTypeDisplay).Distinct().OrderBy(t => t))
            AddCheck(TypePanel, _typeBoxes, t, t);
    }

    private void AddCheck(Panel host, List<CheckBox> track, string key, string display)
    {
        var cb = new CheckBox { Content = display, Tag = key, IsChecked = true, Margin = new Thickness(0, 1, 0, 1) };
        cb.Checked += Filter_Changed; cb.Unchecked += Filter_Changed;
        host.Children.Add(cb); track.Add(cb);
    }

    private void Filter_Changed(object sender, RoutedEventArgs e) => ApplyFilters();
    private void Filter_Changed(object sender, TextChangedEventArgs e) => ApplyFilters();
    private void Filter_Changed(object sender, SelectionChangedEventArgs e) => ApplyFilters();

    private void Reset_Click(object sender, RoutedEventArgs e)
    {
        if (!_loaded) return;
        SearchBox.Text = "";
        SortCombo.SelectedIndex = 0; EvidenceCombo.SelectedIndex = 0; StatusFilterCombo.SelectedIndex = 0;
        foreach (var c in _chapterBoxes.Concat(_vesselBoxes).Concat(_typeBoxes)) c.IsChecked = true;
        ApplyFilters();
    }

    private void AllChapters_Click(object sender, RoutedEventArgs e) { foreach (var c in _chapterBoxes) c.IsChecked = true; }
    private void NoChapters_Click(object sender, RoutedEventArgs e) { foreach (var c in _chapterBoxes) c.IsChecked = false; }

    private void ApplyFilters()
    {
        if (!_loaded || _repo == null) return;
        var chapters = _chapterBoxes.Where(c => c.IsChecked == true).Select(c => (string)c.Tag).ToHashSet();
        var vessels = _vesselBoxes.Where(c => c.IsChecked == true).Select(c => (string)c.Tag).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var types = _typeBoxes.Where(c => c.IsChecked == true).Select(c => (string)c.Tag).ToHashSet();
        var evCat = EvidenceCombo.SelectedItem as string ?? "All";
        var statusFilter = StatusFilterCombo.SelectedItem as string ?? "All";
        var sort = SortCombo.SelectedItem as string ?? "Question Number";
        var search = (SearchBox.Text ?? "").Trim();

        var filtered = SireBank.Questions.Where(q =>
        {
            if (!chapters.Contains(q.Chapter)) return false;
            if (q.VesselTypes.Count > 0 && !q.VesselTypes.Any(v => vessels.Contains(v))) return false;
            if (!types.Contains(q.QuestionTypeDisplay)) return false;
            if (evCat != "All")
            {
                var prefix = evCat + ":";
                if (!q.EvidenceTags.Any(t => t.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))) return false;
            }
            if (!string.IsNullOrEmpty(search) && !MatchesSearch(q, search)) return false;
            if (statusFilter != "All" && !MatchesStatus(q, statusFilter)) return false;
            return true;
        });

        var qc = QuestionNumberComparer.Instance;
        filtered = sort switch
        {
            "Chapter" => filtered.OrderBy(q => int.TryParse(q.Chapter, out var n) ? n : 999).ThenBy(q => q.QuestionNumber, qc),
            "Short Question Text" => filtered.OrderBy(q => q.ShortQuestionText),
            "Vessel Types" => filtered.OrderBy(q => q.VesselTypesDisplay).ThenBy(q => q.QuestionNumber, qc),
            "ROVIQ Sequence" => filtered.OrderBy(q => q.RoviqSequence).ThenBy(q => q.QuestionNumber, qc),
            "Question Type" => filtered.OrderBy(q => q.QuestionTypeDisplay).ThenBy(q => q.QuestionNumber, qc),
            _ => filtered.OrderBy(q => q.QuestionNumber, qc)
        };

        // Capture the selection BEFORE swapping ItemsSource — the assignment raises SelectionChanged
        // synchronously, which nulls _selected; reading the field after would always restore nothing.
        var keep = _selected;
        var list = filtered.ToList();
        QuestionList.ItemsSource = list;
        ListHeader.Text = $"Questions ({list.Count})";
        if (keep != null && list.Contains(keep)) QuestionList.SelectedItem = keep;
    }

    private static bool MatchesSearch(SireQuestion q, string s)
    {
        bool C(string f) => f.Contains(s, StringComparison.OrdinalIgnoreCase);
        return C(q.QuestionNumber) || C(q.ShortQuestionText) || C(q.FullQuestionText) || C(q.Objective)
            || C(q.ExpectedEvidence) || C(q.PotentialNegativeObservationGrounds) || C(q.IndustryGuidance)
            || C(q.InspectionGuidance) || C(q.SuggestedInspectorActions) || C(q.Publications) || C(q.RoviqSequence);
    }

    private bool MatchesStatus(SireQuestion q, string filter) => filter switch
    {
        "In Progress" => State.GetStatus(q.QuestionNumber) == QuestionStatus.InProgress,
        "Checked" => State.GetStatus(q.QuestionNumber) == QuestionStatus.Checked,
        "Not Applicable" => State.GetStatus(q.QuestionNumber) == QuestionStatus.NotApplicable,
        "Bookmarked" => State.IsBookmarked(q.QuestionNumber),
        "For Export" => State.IsForExport(q.QuestionNumber),
        "Has Tasks" => State.GetTasksForQuestion(q.QuestionNumber).Count > 0,
        "No Status" => State.GetStatus(q.QuestionNumber) == QuestionStatus.None,
        _ => true
    };

    // ---------- Selection + detail ----------

    private void QuestionList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        _selected = QuestionList.SelectedItem as SireQuestion;
        DetailRoot.IsEnabled = _selected != null;
        RenderDetail(_selected);
        RefreshTasks();
        UpdateActionButtons();
    }

    private void RenderDetail(SireQuestion? q)
    {
        DetailHost.Children.Clear();
        if (q == null) return;
        AddHeading($"Q {q.QuestionNumber}  —  {q.ShortQuestionText}", 16);
        AddMeta($"{q.ChapterDisplay}   ·   {q.QuestionTypeDisplay}   ·   Vessel: {q.VesselTypesDisplay}"
            + (string.IsNullOrWhiteSpace(q.RoviqSequence) ? "" : $"   ·   ROVIQ: {q.RoviqSequence}"));
        AddBody(q.FullQuestionText);
        AddSection("Data Source", q.DataSource);
        AddSection("Objective", q.Objective);
        AddSection("Industry Guidance", q.IndustryGuidance);
        AddSection("Inspection Guidance", q.InspectionGuidance);
        AddSection("Suggested Inspector Actions", q.SuggestedInspectorActions);
        AddSection("Expected Evidence", q.ExpectedEvidence);
        AddSection("Potential Negative Observation Grounds", q.PotentialNegativeObservationGrounds);
        AddSection("Publications", q.Publications);
    }

    private void AddHeading(string text, double size)
        => DetailHost.Children.Add(new TextBlock { Text = text, FontWeight = FontWeights.Bold, FontSize = size, TextWrapping = TextWrapping.Wrap, Foreground = (Brush)FindResource("Accent"), Margin = new Thickness(0, 0, 0, 4) });

    private void AddMeta(string text)
        => DetailHost.Children.Add(new TextBlock { Text = text, FontStyle = FontStyles.Italic, TextWrapping = TextWrapping.Wrap, Foreground = (Brush)FindResource("Muted"), Margin = new Thickness(0, 0, 0, 8) });

    private void AddBody(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return;
        DetailHost.Children.Add(new TextBlock { Text = text.Trim(), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 6) });
    }

    private void AddSection(string label, string? body)
    {
        if (string.IsNullOrWhiteSpace(body)) return;
        DetailHost.Children.Add(new TextBlock { Text = label, FontWeight = FontWeights.Bold, Foreground = (Brush)FindResource("Accent"), Margin = new Thickness(0, 8, 0, 2), TextWrapping = TextWrapping.Wrap });
        AddBody(body);
    }

    // ---------- Status / bookmark / for-export ----------

    private void SetStatus(QuestionStatus status)
    {
        if (_selected == null || _repo == null) return;
        State.SetStatus(_selected.QuestionNumber, status);
        _selected.Status = status;
        _repo.MarkDirty();
        UpdateStats();
        if (StatusFilterCombo.SelectedItem as string != "All") ApplyFilters();
    }

    private void StatusInProgress_Click(object sender, RoutedEventArgs e) => SetStatus(QuestionStatus.InProgress);
    private void StatusChecked_Click(object sender, RoutedEventArgs e) => SetStatus(QuestionStatus.Checked);
    private void StatusNa_Click(object sender, RoutedEventArgs e) => SetStatus(QuestionStatus.NotApplicable);
    private void StatusClear_Click(object sender, RoutedEventArgs e) => SetStatus(QuestionStatus.None);

    private void Bookmark_Click(object sender, RoutedEventArgs e)
    {
        if (_selected == null || _repo == null) return;
        State.ToggleBookmark(_selected.QuestionNumber);
        _selected.IsBookmarked = State.IsBookmarked(_selected.QuestionNumber);
        _repo.MarkDirty(); UpdateStats(); UpdateActionButtons();
    }

    private void ForExport_Click(object sender, RoutedEventArgs e)
    {
        if (_selected == null || _repo == null) return;
        State.ToggleForExport(_selected.QuestionNumber);
        _selected.IsForExport = State.IsForExport(_selected.QuestionNumber);
        _repo.MarkDirty(); UpdateStats(); UpdateActionButtons();
    }

    private void UpdateActionButtons()
    {
        BookmarkBtn.IsChecked = _selected != null && State.IsBookmarked(_selected.QuestionNumber);
        ForExportBtn.IsChecked = _selected != null && State.IsForExport(_selected.QuestionNumber);
    }

    private void SyncQuestionFlags()
    {
        if (_repo == null) return;
        foreach (var q in SireBank.Questions)
        {
            q.Status = State.GetStatus(q.QuestionNumber);
            q.IsBookmarked = State.IsBookmarked(q.QuestionNumber);
            q.IsForExport = State.IsForExport(q.QuestionNumber);
        }
    }

    private void UpdateStats()
    {
        if (_repo == null || !_bankReady && !_loaded) { StatsText.Text = ""; return; }
        StatsText.Text =
            $"{SireBank.Questions.Count} questions · {SireBank.TotalIdentifiedTasks} auto-identified tasks\n" +
            $"Session — ✓ {State.CountByStatus(QuestionStatus.Checked)}  ⧗ {State.CountByStatus(QuestionStatus.InProgress)}  " +
            $"N/A {State.CountByStatus(QuestionStatus.NotApplicable)}  ★ {State.Bookmarks.Count}  tasks {State.TotalTaskCount}";
    }

    // ---------- Tasks ----------

    private void RefreshTasks()
    {
        if (_selected == null || _repo == null) { TaskList.ItemsSource = null; TasksHeader.Text = "Tasks"; return; }
        var tasks = State.GetTasksForQuestion(_selected.QuestionNumber);
        TaskList.ItemsSource = null;
        TaskList.ItemsSource = tasks;
        TasksHeader.Text = $"Tasks ({tasks.Count})";
    }

    private void AddTask_Click(object sender, RoutedEventArgs e) => CommitNewTask();
    private void NewTaskBox_KeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Enter) { CommitNewTask(); e.Handled = true; } }

    private void CommitNewTask()
    {
        if (_selected == null || _repo == null) return;
        var text = (NewTaskBox.Text ?? "").Trim();
        if (text.Length == 0) return;
        State.Tasks.Add(new SireTask { QuestionNumber = _selected.QuestionNumber, Text = text });
        NewTaskBox.Text = "";
        _repo.MarkDirty(); RefreshTasks(); UpdateStats();
        NewTaskBox.Focus();
    }

    private void TaskDone_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || (sender as FrameworkElement)?.Tag is not SireTask t) return;
        t.IsCompleted = !t.IsCompleted;
        _repo.MarkDirty(); RefreshTasks();
    }

    private void TaskRemove_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || (sender as FrameworkElement)?.Tag is not SireTask t) return;
        State.Tasks.Remove(t);
        _repo.MarkDirty(); RefreshTasks(); UpdateStats();
    }

    // ---------- Identified (offline) + AI (Gemini) suggestions ----------

    private void Identified_Click(object sender, RoutedEventArgs e)
    {
        if (_selected == null || _repo == null) return;
        var identified = SireBank.GetIdentifiedTasks(_selected.QuestionNumber);
        if (identified.Count == 0)
        {
            MessageBox.Show(Window.GetWindow(this), "No tasks could be identified from this question's guidance text.",
                "Identified tasks", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        PickAndAddTasks($"{identified.Count} tasks identified for Q {_selected.QuestionNumber} — tick to add:", identified);
    }

    private async void AiSuggest_Click(object sender, RoutedEventArgs e)
    {
        if (_selected == null || _repo == null) return;
        if (!_selected.IsDetailedQuestion)
        {
            MessageBox.Show(Window.GetWindow(this), "AI task suggestions only apply to detailed inspection questions.",
                "AI Suggest", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var key = DataStore.GeminiApiKey;
        if (string.IsNullOrWhiteSpace(key))
        {
            MessageBox.Show(Window.GetWindow(this),
                "No Gemini API key is set. Add yours via Tools ▸ 'Set Gemini API key…' to enable AI task suggestions.",
                "AI Suggest", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        AiBtn.IsEnabled = false; var prev = AiBtn.Content; AiBtn.Content = "✦ Asking Gemini…";
        try
        {
            var (tasks, error) = await GeminiService.GenerateTaskSuggestionsAsync(_selected, key!);
            if (error != null)
            {
                MessageBox.Show(Window.GetWindow(this), error, "AI Suggest", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            PickAndAddTasks($"Gemini suggested {tasks.Count} tasks for Q {_selected.QuestionNumber} — tick to add:", tasks);
        }
        finally { AiBtn.IsEnabled = true; AiBtn.Content = prev; }
    }

    /// <summary>Present a checkable list of candidate task strings (pre-ticked) and add the chosen ones to
    /// the current question's session tasks, skipping duplicates.</summary>
    private void PickAndAddTasks(string prompt, List<string> candidates)
    {
        if (_selected == null || _repo == null) return;
        var items = candidates.Select(t => new PickerItem { Display = t, Tag = t }).ToList();
        var dlg = new ItemPickerWindow(prompt, items, items.Select(i => i.Tag), singleSelect: false) { Owner = Window.GetWindow(this) };
        if (dlg.ShowDialog() != true) return;
        var existing = State.GetTasksForQuestion(_selected.QuestionNumber).Select(t => t.Text).ToHashSet(StringComparer.OrdinalIgnoreCase);
        int added = 0;
        foreach (var obj in dlg.SelectedTags)
        {
            var text = obj as string ?? "";
            if (text.Length == 0 || existing.Contains(text)) continue;
            State.Tasks.Add(new SireTask { QuestionNumber = _selected.QuestionNumber, Text = text });
            existing.Add(text); added++;
        }
        if (added > 0) { _repo.MarkDirty(); RefreshTasks(); UpdateStats(); }
    }

    // ---------- Quick-add to AA ----------

    private SireToAa.Kind? PickKind(string defaultCategory)
    {
        var items = new List<PickerItem>
        {
            new() { Display = "Procedure", Tag = SireToAa.Kind.Procedure },
            new() { Display = "Task", Tag = SireToAa.Kind.Task },
            new() { Display = "Equipment / Area", Tag = SireToAa.Kind.Equipment },
        };
        var def = defaultCategory == "Equipment" ? SireToAa.Kind.Equipment
                : defaultCategory == "Procedure" ? SireToAa.Kind.Procedure : SireToAa.Kind.Task;
        var dlg = new ItemPickerWindow("Add to AA as which kind?", items, new object[] { def }, singleSelect: true) { Owner = Window.GetWindow(this) };
        if (dlg.ShowDialog() != true) return null;
        return dlg.SelectedTags.FirstOrDefault() is SireToAa.Kind k ? k : null;
    }

    private void AddQuestion_Click(object sender, RoutedEventArgs e)
    {
        if (_selected == null || _repo == null) return;
        var kind = PickKind(TagExtractor.DominantCategory(_selected));
        if (kind == null) return;
        var result = SireToAa.AddQuestion(_repo, _selected, kind.Value, createTopLevelTasks: true);
        FinishAdd(result);
    }

    private void AddSection_Click(object sender, RoutedEventArgs e)
    {
        if (_selected == null || _repo == null) return;
        var count = SireBank.InSection(_selected.Section).Count();
        if (MessageBox.Show(Window.GetWindow(this),
                $"Add all {count} question(s) in section {_selected.Section} to AA under one item (plus their identified tasks as top-level Tasks)?",
                "Add section", MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK) return;
        var kind = PickKind(TagExtractor.DominantCategory(_selected));
        if (kind == null) return;
        FinishAdd(SireToAa.AddSection(_repo, _selected.Section, kind.Value, createTopLevelTasks: true));
    }

    private void AddChapter_Click(object sender, RoutedEventArgs e)
    {
        if (_selected == null || _repo == null) return;
        var count = SireBank.InChapter(_selected.Chapter).Count();
        if (MessageBox.Show(Window.GetWindow(this),
                $"Add all {count} question(s) in chapter {_selected.Chapter} to AA under one item (plus their identified tasks as top-level Tasks)?\n\nThis can create many items and tasks.",
                "Add chapter", MessageBoxButton.OKCancel, MessageBoxImage.Warning) != MessageBoxResult.OK) return;
        var kind = PickKind(TagExtractor.DominantCategory(_selected));
        if (kind == null) return;
        FinishAdd(SireToAa.AddChapter(_repo, _selected.Chapter, kind.Value, createTopLevelTasks: true));
    }

    private void FinishAdd(SireToAa.Result result)
    {
        if (_repo == null) return;
        if (result.Primary == null)
        {
            MessageBox.Show(Window.GetWindow(this), result.Summary, "Add to AA", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        try { _repo.Save(); } catch { }
        _refreshAa?.Invoke();   // rebuild the hierarchy pages so the new items appear
        var go = MessageBox.Show(Window.GetWindow(this), result.Summary + "\n\nGo to it now?",
            "Added to AA", MessageBoxButton.YesNo, MessageBoxImage.Information);
        if (go == MessageBoxResult.Yes) _navigate?.Invoke(result.Primary);
    }

    // ---------- Export (called from the Tools menu) ----------

    public void ShowExportDialog()
    {
        if (_repo == null) return;
        EnsureLoaded();
        if (!_bankReady) { MessageBox.Show(Window.GetWindow(this), "The SIRE question bank is still loading — try again in a moment.", "SIRE export", MessageBoxButton.OK, MessageBoxImage.Information); return; }
        var items = SireExport.Modes.Select(m => new PickerItem { Display = m, Tag = m }).ToList();
        var dlg = new ItemPickerWindow("Choose a SIRE export:", items, new object[] { "Print Checklist" }, singleSelect: true) { Owner = Window.GetWindow(this) };
        if (dlg.ShowDialog() != true) return;
        if (dlg.SelectedTags.FirstOrDefault() is not string mode) return;

        var filtered = (QuestionList.ItemsSource as IEnumerable<SireQuestion>)?.ToList() ?? SireBank.Questions.ToList();
        var text = SireExport.Build(mode, SireBank.Questions, State, SireBank.IdentifiedTasks, filtered);

        var choice = MessageBox.Show(Window.GetWindow(this), $"SIRE export “{mode}” ready.\n\nYes = save to a .txt file\nNo = copy to clipboard",
            "SIRE export", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
        if (choice == MessageBoxResult.Cancel) return;
        if (choice == MessageBoxResult.No)
        {
            try { Clipboard.SetText(text); if (Window.GetWindow(this)?.FindName("StatusBlock") is TextBlock sb) sb.Text = "SIRE export copied to clipboard."; }
            catch (Exception ex) { MessageBox.Show(ex.Message, "Clipboard failed"); }
            return;
        }
        var save = new Microsoft.Win32.SaveFileDialog
        {
            Filter = "Text file (*.txt)|*.txt|All files (*.*)|*.*",
            FileName = $"SIRE_{mode.Replace(' ', '_')}_{DateTime.Now:yyyyMMdd_HHmm}.txt"
        };
        if (save.ShowDialog() == true)
        {
            try { System.IO.File.WriteAllText(save.FileName, text); }
            catch (Exception ex) { MessageBox.Show(ex.Message, "Save failed", MessageBoxButton.OK, MessageBoxImage.Error); }
        }
    }

    /// <summary>True once the bank has loaded (so the host can decide whether export/AI is ready).</summary>
    public bool IsReady => _bankReady && _loaded;
}
