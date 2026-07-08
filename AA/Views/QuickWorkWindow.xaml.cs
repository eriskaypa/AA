using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using AA.Models;
using AA.Services;

namespace AA.Views;

/// <summary>Ctrl+N power window: ALL tasks &amp; procedures on the left (active first, completed/done
/// sorted to the bottom); pick one (assignable) and build it out on the right with a comprehensive
/// builder (header + bulk entry + reorderable children + the full builder).</summary>
public partial class QuickWorkWindow : Window
{
    private AppRepository _repo;
    private readonly Action<HierarchyItem>? _navigate;
    private HierarchyItem? _selected;
    private bool _suppress;

    public QuickWorkWindow(AppRepository repo, Action<HierarchyItem>? navigate = null)
    {
        InitializeComponent();
        _repo = repo;
        _navigate = navigate;
        RefreshPending();
        Closing += (_, _) => _repo.FlushIfDirty();
    }

    /// <summary>Re-point at the current repository after a data reload/import (e.g. shared-file sync),
    /// so edits never write to an orphaned old repository. Re-resolves the selected item by id.</summary>
    public void SetRepo(AppRepository repo)
    {
        var keepId = _selected?.Id;
        _repo = repo;
        _selected = keepId is Guid g ? repo.FindById(g) : null;
        RefreshPending();
        BuildDetail();
    }

    private sealed class PendingRow
    {
        public HierarchyItem Item { get; init; } = null!;
        public string Title { get; init; } = "";
        public string Sub { get; init; } = "";
    }

    // ---- Left: pending list ----
    private void RefreshPending()
    {
        var keepId = _selected?.Id;
        var q = SearchBox.Text?.Trim() ?? "";
        bool tasks = RbAll.IsChecked == true || RbTasks.IsChecked == true;
        bool procs = RbAll.IsChecked == true || RbProcs.IsChecked == true;

        // Show ALL tasks and procedures — not just the incomplete/not-done ones. Completed/done
        // items are sorted to the bottom (below) so active work still leads, but everything is
        // reachable and editable from here.
        var items = new List<HierarchyItem>();
        if (tasks) items.AddRange(_repo.Data.Tasks.Cast<HierarchyItem>());
        if (procs) items.AddRange(_repo.Data.Procedures.Cast<HierarchyItem>());

        if (!string.IsNullOrEmpty(q))
            items = items.Where(i => i.Name.Contains(q, StringComparison.OrdinalIgnoreCase)).ToList();

        var today = DateTime.Today;
        var rows = items
            .OrderBy(i => IsDone(i))                          // active first, completed/done sink to the bottom
            .ThenBy(i => Deadline(i) ?? DateTime.MaxValue)
            .ThenBy(i => i.Name, StringComparer.OrdinalIgnoreCase)
            .Select(i => new PendingRow
            {
                Item = i,
                Title = string.IsNullOrWhiteSpace(i.Name) ? "(unnamed)" : i.Name,
                Sub = Subtitle(i, today)
            }).ToList();

        // Reassigning ItemsSource fires SelectionChanged; suppress it so a routine refresh never
        // tears down / rebuilds the detail panel (which would kill an in-progress edit + focus).
        _suppress = true;
        PendingList.ItemsSource = rows;
        var keep = keepId is Guid g ? rows.FirstOrDefault(r => r.Item.Id == g) : null;
        PendingList.SelectedItem = keep;
        _selected = keep?.Item ?? _selected;
        _suppress = false;
        int doneCount = rows.Count(r => IsDone(r.Item));
        CountText.Text = doneCount > 0
            ? $"{rows.Count} item(s) — {rows.Count - doneCount} active, {doneCount} completed/done."
            : $"{rows.Count} item(s).";
    }

    private static string Subtitle(HierarchyItem i, DateTime today)
    {
        var kind = i is TaskItem ? "Task" : "Procedure";
        var parts = new List<string> { kind };
        if (IsDone(i)) parts.Add("✓ completed");
        if (Deadline(i) is DateTime d)
        {
            int days = (int)(d.Date - today).TotalDays;
            parts.Add(days < 0 ? $"due {d:yyyy-MM-dd} (OVERDUE {-days}d)"
                    : days == 0 ? $"due today" : $"due {d:yyyy-MM-dd} (in {days}d)");
        }
        int children = i is TaskItem t ? t.Subtasks.Count : i is Procedure p ? p.Steps.Count : 0;
        if (children > 0) parts.Add($"{children} " + (i is TaskItem ? "subtask(s)" : "step(s)"));
        return string.Join("  ·  ", parts);
    }

    private void Search_Changed(object sender, TextChangedEventArgs e) => RefreshPending();
    private void Filter_Changed(object sender, RoutedEventArgs e) { if (IsLoaded) RefreshPending(); }

    private void Pending_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppress) return;   // ignore programmatic selection changes from RefreshPending
        _selected = (PendingList.SelectedItem as PendingRow)?.Item;
        BuildDetail();
    }

    private void NewTask_Click(object sender, RoutedEventArgs e)
    {
        var p = new PromptWindow("New Task", "Name:") { Owner = this };
        if (p.ShowDialog() != true || string.IsNullOrWhiteSpace(p.Value)) return;
        var t = new TaskItem { Name = p.Value };
        _repo.Data.Tasks.Add(t);
        _repo.LogAdded("Task", t.Name);
        _repo.Save();
        SelectItem(t);
    }

    private void NewProc_Click(object sender, RoutedEventArgs e)
    {
        var p = new PromptWindow("New Procedure", "Name:") { Owner = this };
        if (p.ShowDialog() != true || string.IsNullOrWhiteSpace(p.Value)) return;
        var proc = new Procedure { Name = p.Value };
        _repo.Data.Procedures.Add(proc);
        _repo.LogAdded("Procedure", proc.Name);
        _repo.Save();
        SelectItem(proc);
    }

    private void SelectItem(HierarchyItem item)
    {
        _selected = item;
        RefreshPending();     // suppressed; selects the row and keeps _selected
        BuildDetail();        // build the detail pane for the (new) selection
    }

    // ---- Right: comprehensive builder ----
    private void BuildDetail()
    {
        DetailHost.Children.Clear();
        if (_selected == null)
        {
            DetailHost.Children.Add(new TextBlock
            {
                Text = "Select a task or procedure on the left (or create one) to build it out here.",
                Foreground = (System.Windows.Media.Brush)FindResource("Muted"),
                TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 20, 0, 0), TextAlignment = TextAlignment.Center
            });
            return;
        }

        // Title row + "open in main app".
        var titleRow = new DockPanel { Margin = new Thickness(0, 0, 0, 10) };
        var openBtn = new Button { Content = "Open in main window ↗", Padding = new Thickness(10, 4, 10, 4) };
        DockPanel.SetDock(openBtn, Dock.Right);
        openBtn.Click += (_, _) => { if (_selected != null) _navigate?.Invoke(_selected); };
        titleRow.Children.Add(openBtn);
        titleRow.Children.Add(new TextBlock
        {
            Text = _selected is TaskItem ? "Task" : "Procedure",
            FontSize = 20, FontWeight = FontWeights.Bold, Foreground = (System.Windows.Media.Brush)FindResource("Accent")
        });
        DetailHost.Children.Add(titleRow);

        // Header fields (shared by tasks and procedures).
        AddField("Name:", MakeNameBox());
        AddField("Deadline:", MakeDeadlinePicker());
        AddField("Status:", MakeStatusCombo());
        AddField("Recurrence:", MakeRecurrenceCombo());

        DetailHost.Children.Add(new Separator { Margin = new Thickness(0, 10, 0, 10) });

        if (_selected is TaskItem t)
            BuildChildren(t.Subtasks, "Name", "subtask",
                name => new TaskItem { Name = name },
                child => new SubtaskEditorWindow(child, _repo) { Owner = this }.ShowDialog(),
                () => new SubtaskBuilderWindow(t, _repo) { Owner = this }.ShowDialog(),
                t.Name,
                () => SaveSubtaskTemplate(t),
                () => LoadSubtaskTemplate(t));
        else if (_selected is Procedure p)
            BuildChildren(p.Steps, "Title", "step",
                title => new ChecklistStep { Title = title },
                child => new ChecklistStepEditorWindow(child, _repo) { Owner = this }.ShowDialog(),
                () => new ChecklistBuilderWindow(p, _repo) { Owner = this }.ShowDialog(),
                p.Name,
                () => SaveStepTemplate(p),
                () => LoadStepTemplate(p));
    }

    private void AddField(string label, FrameworkElement control)
    {
        var dock = new DockPanel { Margin = new Thickness(0, 3, 0, 3) };
        dock.Children.Add(new TextBlock { Text = label, Width = 100, VerticalAlignment = VerticalAlignment.Center });
        dock.Children.Add(control);
        DetailHost.Children.Add(dock);
    }

    private TextBox MakeNameBox()
    {
        var tb = new TextBox { Text = _selected!.Name };
        // Only mutate + mark dirty; do NOT refresh the pending list per keystroke (that would rebuild
        // the detail panel and steal focus). The left-list title refreshes on the next real refresh.
        tb.TextChanged += (_, _) =>
        {
            if (_suppress || _selected == null) return;
            _selected.Name = tb.Text;
            _repo.MarkDirty();
        };
        return tb;
    }

    private DatePicker MakeDeadlinePicker()
    {
        var dp = new DatePicker { SelectedDate = Deadline(_selected!), Width = 200, HorizontalAlignment = HorizontalAlignment.Left };
        dp.SelectedDateChanged += (_, _) => { if (!_suppress && _selected != null) { SetDeadline(_selected, dp.SelectedDate); _repo.MarkDirty(); } };
        return dp;
    }

    private ComboBox MakeStatusCombo()
    {
        var cb = new ComboBox { Width = 200, HorizontalAlignment = HorizontalAlignment.Left,
            ItemsSource = Enum.GetValues(typeof(WorkStatus)), SelectedItem = Status(_selected!) };
        cb.SelectionChanged += (_, _) => { if (!_suppress && _selected != null && cb.SelectedItem is WorkStatus s) { SetStatus(_selected, s); _repo.MarkDirty(); } };
        return cb;
    }

    private ComboBox MakeRecurrenceCombo()
    {
        var cb = new ComboBox { Width = 200, HorizontalAlignment = HorizontalAlignment.Left,
            ItemsSource = Enum.GetValues(typeof(RecurrenceKind)), SelectedItem = Recurrence(_selected!) };
        cb.SelectionChanged += (_, _) => { if (!_suppress && _selected != null && cb.SelectedItem is RecurrenceKind r) { SetRecurrence(_selected, r); _repo.MarkDirty(); } };
        return cb;
    }

    // ---- Saved lists (reusable checklist templates) ----
    private void SaveSubtaskTemplate(TaskItem t)
    {
        if (!ConfirmHasItems(t.Subtasks.Count)) return;
        var name = AskTemplateName(t.Name);
        if (name == null) return;
        var tpl = ChecklistTemplateService.CaptureFromSubtasks(name, t.Subtasks);
        StoreTemplate(tpl);
    }

    private void SaveStepTemplate(Procedure p)
    {
        if (!ConfirmHasItems(p.Steps.Count)) return;
        var name = AskTemplateName(p.Name);
        if (name == null) return;
        var tpl = ChecklistTemplateService.CaptureFromSteps(name, p.Steps);
        StoreTemplate(tpl);
    }

    private void LoadSubtaskTemplate(TaskItem t)
    {
        if (PickTemplate() is not ChecklistTemplate tpl) return;
        var mode = AskReplaceOrAppend(tpl);
        if (mode == null) return;
        int n = ChecklistTemplateService.ApplyToSubtasks(tpl, t.Subtasks, mode.Value);
        _repo.LogAdded("Subtask", $"{n} added (from saved list '{tpl.Name}')", t.Name);
        _repo.MarkDirty(); RefreshPending();
    }

    private void LoadStepTemplate(Procedure p)
    {
        if (PickTemplate() is not ChecklistTemplate tpl) return;
        var mode = AskReplaceOrAppend(tpl);
        if (mode == null) return;
        int n = ChecklistTemplateService.ApplyToSteps(tpl, p.Steps, mode.Value);
        _repo.LogAdded("Checklist step", $"{n} added (from saved list '{tpl.Name}')", p.Name);
        _repo.MarkDirty(); RefreshPending();
    }

    private bool ConfirmHasItems(int count)
    {
        if (count > 0) return true;
        MessageBox.Show(this, "Add some items first, then save the list.", "Save list",
            MessageBoxButton.OK, MessageBoxImage.Information);
        return false;
    }

    private string? AskTemplateName(string suggested)
    {
        var p = new PromptWindow("Save as reusable list", "Name for this saved list:", suggested) { Owner = this };
        return p.ShowDialog() == true && !string.IsNullOrWhiteSpace(p.Value) ? p.Value.Trim() : null;
    }

    private void StoreTemplate(ChecklistTemplate tpl)
    {
        _repo.Data.ChecklistTemplates.Add(tpl);
        _repo.LogAdded("Saved list", tpl.Name, $"{tpl.Items.Count} item(s)");
        _repo.Save();
        MessageBox.Show(this, $"Saved '{tpl.Name}' ({tpl.Items.Count} item(s)). You can reuse it from any checklist builder.",
            "Saved list", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private ChecklistTemplate? PickTemplate()
    {
        if (_repo.Data.ChecklistTemplates.Count == 0)
        {
            MessageBox.Show(this, "No saved lists yet. Build a list and click 'Save as list...' to create one.",
                "Load a saved list", MessageBoxButton.OK, MessageBoxImage.Information);
            return null;
        }
        var options = _repo.Data.ChecklistTemplates.Select(x => new PickerItem { Display = x.Display, Tag = x }).ToList();
        var dlg = new ItemPickerWindow("Insert a saved list", options, Array.Empty<object>(), singleSelect: true) { Owner = this };
        return dlg.ShowDialog() == true && dlg.SelectedTags.FirstOrDefault() is ChecklistTemplate tpl ? tpl : null;
    }

    /// <summary>Yes = replace, No = append, Cancel/null = abort.</summary>
    private bool? AskReplaceOrAppend(ChecklistTemplate tpl)
    {
        var how = MessageBox.Show(this,
            $"Insert '{tpl.Name}' ({tpl.Items.Count} item(s)).\n\nYes = replace the current items\nNo = append to the end\nCancel = do nothing",
            "Insert a saved list", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
        return how == MessageBoxResult.Yes ? true : how == MessageBoxResult.No ? false : null;
    }

    private void BuildChildren<T>(ObservableCollection<T> coll, string displayPath, string noun,
        Func<string, T> create, Action<T> edit, Action openFull, string ownerName,
        Action saveTemplate, Action loadTemplate) where T : class
    {
        DetailHost.Children.Add(new TextBlock
        {
            Text = $"Comprehensive {noun} builder", FontWeight = FontWeights.Bold, FontSize = 14,
            Foreground = (System.Windows.Media.Brush)FindResource("Accent"), Margin = new Thickness(0, 0, 0, 6)
        });

        // Bulk entry.
        DetailHost.Children.Add(new TextBlock { Text = $"Bulk add — one {noun} per line:", Margin = new Thickness(0, 0, 0, 2) });
        var bulk = new TextBox { AcceptsReturn = true, Height = 96, TextWrapping = TextWrapping.NoWrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto, FontFamily = new System.Windows.Media.FontFamily("Consolas") };
        DetailHost.Children.Add(bulk);
        var bulkRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 4, 0, 8) };
        var addAll = new Button { Content = "Add all", Style = (Style?)Application.Current.TryFindResource("AccentButton"), Padding = new Thickness(12, 4, 12, 4) };
        var replace = new CheckBox { Content = "Replace existing", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(10, 0, 0, 0) };
        bulkRow.Children.Add(addAll); bulkRow.Children.Add(replace);
        DetailHost.Children.Add(bulkRow);

        // Children list.
        var list = new ListBox { Height = 300, SelectionMode = SelectionMode.Extended, DisplayMemberPath = displayPath, ItemsSource = coll };
        DetailHost.Children.Add(list);

        var btns = new WrapPanel { Margin = new Thickness(0, 6, 0, 0) };
        Button B(string c, RoutedEventHandler h) { var b = new Button { Content = c, Margin = new Thickness(0, 0, 6, 6), Padding = new Thickness(8, 3, 8, 3) }; b.Click += h; btns.Children.Add(b); return b; }
        B($"+ {noun}", (_, _) =>
        {
            var p = new PromptWindow($"New {noun}", "Name:") { Owner = this };
            if (p.ShowDialog() != true || string.IsNullOrWhiteSpace(p.Value)) return;
            var child = create(p.Value);
            coll.Add(child);
            _repo.LogAdded(Cap(noun), ChildName(child, displayPath), ownerName);
            _repo.Save(); RefreshPending();
        });
        B("Edit...", (_, _) => { if (list.SelectedItem is T c) { edit(c); _repo.FlushIfDirty(); RefreshPending(); } });
        B("↑", (_, _) => Move(list, coll, -1));
        B("↓", (_, _) => Move(list, coll, +1));
        B("Delete", (_, _) =>
        {
            var picks = list.SelectedItems.Cast<T>().ToList();
            if (picks.Count == 0) return;
            if (MessageBox.Show(this, $"Delete {picks.Count} {noun}(s)?", "Confirm", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
            _repo.LogRemoved(Cap(noun), $"{picks.Count} removed", ownerName);
            foreach (var c in picks) coll.Remove(c);
            _repo.Save(); RefreshPending();
        });
        B("Open full builder...", (_, _) => { openFull(); RefreshPending(); });
        B("💾 Save as list...", (_, _) => saveTemplate());
        B("📋 Load a saved list...", (_, _) => { loadTemplate(); RefreshPending(); });
        DetailHost.Children.Add(btns);

        list.MouseDoubleClick += (_, _) => { if (list.SelectedItem is T c) { edit(c); _repo.FlushIfDirty(); RefreshPending(); } };

        addAll.Click += (_, _) =>
        {
            var lines = (bulk.Text ?? "").Replace("\r\n", "\n").Split('\n').Select(l => l.Trim()).Where(l => l.Length > 0).ToList();
            if (lines.Count == 0) return;
            if (replace.IsChecked == true) coll.Clear();
            foreach (var line in lines) coll.Add(create(line));
            bulk.Clear();
            _repo.LogAdded(Cap(noun), $"{lines.Count} added (bulk)", ownerName);
            _repo.Save(); RefreshPending();
        };
    }

    private void Move<T>(ListBox list, ObservableCollection<T> coll, int dir) where T : class
    {
        var picks = list.SelectedItems.Cast<T>().Select(c => coll.IndexOf(c)).Where(i => i >= 0).OrderBy(i => i).ToList();
        if (picks.Count == 0) return;
        if (dir < 0)
        {
            if (picks[0] == 0) return;
            foreach (var i in picks) coll.Move(i, i - 1);
        }
        else
        {
            if (picks[^1] == coll.Count - 1) return;
            foreach (var i in picks.AsEnumerable().Reverse()) coll.Move(i, i + 1);
        }
        _repo.MarkDirty();
    }

    private static string ChildName<T>(T child, string path) where T : class =>
        (child?.GetType().GetProperty(path)?.GetValue(child) as string) ?? "";
    private static string Cap(string s) => string.IsNullOrEmpty(s) ? s : char.ToUpperInvariant(s[0]) + s.Substring(1);

    // ---- shared field accessors (tasks & procedures both have these) ----
    private static bool IsDone(HierarchyItem i) => i switch { TaskItem t => t.IsComplete, Procedure p => p.Status == WorkStatus.Done, _ => false };
    private static DateTime? Deadline(HierarchyItem i) => i switch { TaskItem t => t.Deadline, Procedure p => p.Deadline, _ => null };
    private static void SetDeadline(HierarchyItem i, DateTime? v) { if (i is TaskItem t) t.Deadline = v; else if (i is Procedure p) p.Deadline = v; }
    private static WorkStatus Status(HierarchyItem i) => i switch { TaskItem t => t.Status, Procedure p => p.Status, _ => WorkStatus.Todo };
    private static void SetStatus(HierarchyItem i, WorkStatus v) { if (i is TaskItem t) t.Status = v; else if (i is Procedure p) p.Status = v; }
    private static RecurrenceKind Recurrence(HierarchyItem i) => i switch { TaskItem t => t.Recurrence, Procedure p => p.Recurrence, _ => RecurrenceKind.None };
    private static void SetRecurrence(HierarchyItem i, RecurrenceKind v) { if (i is TaskItem t) t.Recurrence = v; else if (i is Procedure p) p.Recurrence = v; }
}
