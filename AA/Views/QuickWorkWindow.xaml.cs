using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Media;
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
    private string _selectedBucketKey = "";   // which bucket group the selected row is under
    private bool _suppress;
    // The detail pane's deadline + optional working-range-start pickers (tasks only), kept so each can
    // clamp the other (start <= deadline). Reset on every BuildDetail.
    private DatePicker? _qwDeadline;
    private DatePicker? _qwStart;
    private bool _qwDateSync;

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
        public bool IsDone { get; init; }
        public string Bucket { get; init; } = "";       // bucket display name, or "(No bucket)"
        public string BucketKey { get; init; } = "";    // GROUP KEY: bucket id (unique) or "" for none
        public string BucketSort { get; init; } = "";   // group ordering (unbucketed sinks last)
        public DateTime DeadlineSort { get; init; }
    }

    // ---- Left: pending list ----

    private void RefreshPending()
    {
        var keepId = _selected?.Id;
        var q = SearchBox.Text?.Trim() ?? "";
        bool tasks = RbAll.IsChecked == true || RbTasks.IsChecked == true;
        bool procs = RbAll.IsChecked == true || RbProcs.IsChecked == true;

        // Show ALL tasks and procedures — not just the incomplete/not-done ones. Completed/done
        // items sort to the bottom of each bucket so active work still leads.
        var items = new List<HierarchyItem>();
        if (tasks) items.AddRange(_repo.Data.Tasks.Cast<HierarchyItem>());
        if (procs) items.AddRange(_repo.Data.Procedures.Cast<HierarchyItem>());

        if (!string.IsNullOrEmpty(q))
            items = items.Where(i => i.Name.Contains(q, StringComparison.OrdinalIgnoreCase)).ToList();

        var today = DateTime.Today;
        // A task/procedure can be in up to two buckets, so it appears under each of its buckets
        // (one row per bucket); items in no bucket appear once under "(No bucket)". Rows are GROUPED by
        // bucket ID (not name) so two buckets that happen to share a name stay distinct.
        var rows = new List<PendingRow>();
        foreach (var i in items)
        {
            var title = string.IsNullOrWhiteSpace(i.Name) ? "(unnamed)" : i.Name;
            var sub = Subtitle(i, today);
            bool done = IsDone(i);
            var dl = Deadline(i) ?? DateTime.MaxValue;
            var buckets = i.BucketIds
                .Select(id => _repo.Data.QuickBuckets.FirstOrDefault(b => b.Id == id))
                .Where(b => b != null).Cast<QuickBucket>()
                .GroupBy(b => b.Id).Select(g => g.First())   // guard against a duplicated id on one item
                .ToList();
            if (buckets.Count == 0)
                rows.Add(new PendingRow { Item = i, Title = title, Sub = sub, IsDone = done, Bucket = "(No bucket)", BucketKey = "", BucketSort = "￿", DeadlineSort = dl });
            else
                foreach (var b in buckets)
                {
                    var bn = b.Name.Length > 0 ? b.Name : "(unnamed bucket)";
                    rows.Add(new PendingRow { Item = i, Title = title, Sub = sub, IsDone = done, Bucket = bn, BucketKey = b.Id.ToString(), BucketSort = bn.ToLowerInvariant(), DeadlineSort = dl });
                }
        }

        var view = new ListCollectionView(rows);
        bool grouped = _repo.Data.QuickBuckets.Count > 0;
        if (grouped)
        {
            view.SortDescriptions.Add(new SortDescription(nameof(PendingRow.BucketSort), ListSortDirection.Ascending));
            view.SortDescriptions.Add(new SortDescription(nameof(PendingRow.BucketKey), ListSortDirection.Ascending));
        }
        view.SortDescriptions.Add(new SortDescription(nameof(PendingRow.IsDone), ListSortDirection.Ascending));
        view.SortDescriptions.Add(new SortDescription(nameof(PendingRow.DeadlineSort), ListSortDirection.Ascending));
        view.SortDescriptions.Add(new SortDescription(nameof(PendingRow.Title), ListSortDirection.Ascending));
        if (grouped)
            view.GroupDescriptions.Add(new PropertyGroupDescription(nameof(PendingRow.BucketKey)));

        // Reassigning ItemsSource fires SelectionChanged; suppress it so a routine refresh never
        // tears down / rebuilds the detail panel (which would kill an in-progress edit + focus).
        _suppress = true;
        PendingList.ItemsSource = view;
        // Restore the exact row the user had (same item AND same bucket group) so a two-bucket item's
        // selection doesn't jump between groups on refresh; fall back to any row for that item.
        var keep = keepId is Guid g
            ? (rows.FirstOrDefault(r => r.Item.Id == g && r.BucketKey == _selectedBucketKey) ?? rows.FirstOrDefault(r => r.Item.Id == g))
            : null;
        PendingList.SelectedItem = keep;
        _selected = keep?.Item ?? _selected;
        _suppress = false;
        int doneCount = items.Count(IsDone);
        CountText.Text = doneCount > 0
            ? $"{items.Count} item(s) — {items.Count - doneCount} active, {doneCount} completed/done."
            : $"{items.Count} item(s).";

        RefreshPinned();   // keep the pinned squares (progress / done state) in step with every change
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
        var row = PendingList.SelectedItem as PendingRow;
        _selected = row?.Item;
        _selectedBucketKey = row?.BucketKey ?? "";
        BuildDetail();
    }

    /// <summary>WPF doesn't select a row on right-click, so a context menu would act on the previously
    /// left-selected item. Select the right-clicked row first (keeping an existing multi-selection when the
    /// click lands on an already-selected row) so the menu targets what was clicked.</summary>
    private void List_RightButtonSelect(object sender, MouseButtonEventArgs e)
    {
        if (sender is ListBox lb) BatchDoneMenu.RightClickSelect(lb, e.OriginalSource as DependencyObject);
    }

    private void MarkSelectedDone_Click(object sender, RoutedEventArgs e) => MarkSelected(true);
    private void MarkSelectedNotDone_Click(object sender, RoutedEventArgs e) => MarkSelected(false);
    private void MarkSelected(bool done)
    {
        var items = PendingList.SelectedItems.OfType<PendingRow>().Select(r => (object)r.Item).ToList();
        int n = AA.Services.BatchDone.SetDoneAll(items, done);
        if (n > 0) { _repo.MarkDirty(); _repo.FlushIfDirty(); }
        RefreshPending();
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

    // ---- Pinned board (squares) ----
    private List<Guid> PinIds => _repo.Data.Ui.QuickViewPinIds;
    private bool IsPinned(HierarchyItem i) => PinIds.Contains(i.Id);

    private void TogglePin(HierarchyItem item)
    {
        if (!PinIds.Remove(item.Id)) PinIds.Add(item.Id);
        _repo.MarkDirty();
        _repo.Save();
        RefreshPinned();
        if (ReferenceEquals(item, _selected)) BuildDetail();   // refresh the Pin button label
    }

    /// <summary>Rebuild the pinned squares from the persisted pin ids, pruning any that no longer exist.</summary>
    private void RefreshPinned()
    {
        if (PinnedHost == null) return;   // not yet loaded
        PinnedHost.Children.Clear();

        var live = new List<HierarchyItem>();
        bool pruned = false;
        foreach (var id in PinIds.ToList())
        {
            var it = _repo.FindById(id);
            if (it is TaskItem or Procedure) live.Add(it!);
            else { PinIds.Remove(id); pruned = true; }   // task/procedure was deleted elsewhere
        }
        if (pruned) _repo.MarkDirty();

        PinnedEmptyHint.Visibility = live.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

        // Active first, then done; stable by name.
        foreach (var it in live.OrderBy(IsDone).ThenBy(i => i.Name, StringComparer.OrdinalIgnoreCase))
            PinnedHost.Children.Add(BuildTile(it));
    }

    private static readonly Brush OverdueBrush = FrozenBrush("#FFD45050");
    private static Brush FrozenBrush(string hex)
    { var b = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex)); b.Freeze(); return b; }

    private UIElement BuildTile(HierarchyItem item)
    {
        bool done = IsDone(item);
        bool isTask = item is TaskItem;
        var (pdone, ptotal) = ChildProgress(item);
        bool selected = ReferenceEquals(item, _selected);

        var border = new Border
        {
            Width = 172,
            MinHeight = 156,   // grows if the name wraps to several lines — no clipping
            Margin = new Thickness(0, 0, 8, 8),
            CornerRadius = new CornerRadius(8),
            Background = (Brush)FindResource(done ? "PanelAlt" : "Panel"),
            BorderBrush = selected ? (Brush)FindResource("Accent") : (Brush)FindResource("BorderB"),
            BorderThickness = new Thickness(selected ? 2 : 1),
            Padding = new Thickness(9),
            Cursor = Cursors.Hand,
            Opacity = done ? 0.72 : 1.0,
            ToolTip = "Click to edit. Tick “Done” to mark it complete everywhere."
        };

        var grid = new Grid();
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });   // header
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });   // name (wraps fully)
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });   // progress
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });   // footer

        // Header: kind label + unpin.
        var header = new DockPanel();
        var unpin = new Button
        {
            Content = "📌", Padding = new Thickness(2, 0, 2, 0), FontSize = 12,
            Background = Brushes.Transparent, BorderThickness = new Thickness(0),
            ToolTip = "Unpin (remove this square). The task/procedure itself is kept.",
            Cursor = Cursors.Hand
        };
        unpin.Click += (_, _) => TogglePin(item);
        DockPanel.SetDock(unpin, Dock.Right);
        header.Children.Add(unpin);
        header.Children.Add(new TextBlock
        {
            Text = isTask ? "✓ Task" : "📋 Procedure",
            FontSize = 11, Foreground = (Brush)FindResource("Muted"), VerticalAlignment = VerticalAlignment.Center
        });
        Grid.SetRow(header, 0);
        grid.Children.Add(header);

        // Name (wraps fully — no clipping; struck through when the item is done).
        var name = new TextBlock
        {
            Text = item.Name.Length > 0 ? item.Name : "(unnamed)",
            FontWeight = FontWeights.Bold, TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 4, 0, 4),
            TextDecorations = done ? TextDecorations.Strikethrough : null
        };
        Grid.SetRow(name, 1);
        grid.Children.Add(name);

        // Progress (children done / total).
        var progWrap = new StackPanel();
        if (ptotal > 0)
        {
            progWrap.Children.Add(new TextBlock
            {
                Text = $"{pdone}/{ptotal} {(isTask ? "subtask" : "step")}{(ptotal == 1 ? "" : "s")} done",
                FontSize = 11, Foreground = (Brush)FindResource("Muted")
            });
            var track = new Border
            {
                Height = 5, CornerRadius = new CornerRadius(3), Margin = new Thickness(0, 2, 0, 0),
                Background = (Brush)FindResource("PanelAlt"), BorderBrush = (Brush)FindResource("BorderB"), BorderThickness = new Thickness(0.6)
            };
            var fill = new Border
            {
                Height = 5, CornerRadius = new CornerRadius(3), HorizontalAlignment = HorizontalAlignment.Left,
                Background = (Brush)FindResource("Accent")
            };
            // Width set once laid out (bind to fraction of the track).
            double frac = ptotal == 0 ? 0 : (double)pdone / ptotal;
            track.Child = fill;
            track.Loaded += (_, _) => fill.Width = Math.Max(0, track.ActualWidth * frac);
            track.SizeChanged += (_, _) => fill.Width = Math.Max(0, track.ActualWidth * frac);
            progWrap.Children.Add(track);
        }
        else
        {
            progWrap.Children.Add(new TextBlock
            {
                Text = done ? "completed" : "no items yet",
                FontSize = 11, Foreground = (Brush)FindResource("Muted")
            });
        }
        Grid.SetRow(progWrap, 2);
        grid.Children.Add(progWrap);

        // Footer: deadline chip + Done checkbox.
        var footer = new DockPanel { Margin = new Thickness(0, 6, 0, 0) };
        var doneCheck = new CheckBox { Content = "Done", IsChecked = done, VerticalAlignment = VerticalAlignment.Center };
        doneCheck.Click += (_, _) => SetItemDone(item, doneCheck.IsChecked == true);
        DockPanel.SetDock(doneCheck, Dock.Right);
        footer.Children.Add(doneCheck);
        if (Deadline(item) is DateTime dl)
        {
            int days = (int)(dl.Date - DateTime.Today).TotalDays;
            bool overdue = days < 0 && !done;
            footer.Children.Add(new TextBlock
            {
                Text = overdue ? $"OVERDUE {dl:MM-dd}" : $"due {dl:MM-dd}",
                FontSize = 11, VerticalAlignment = VerticalAlignment.Center,
                Foreground = overdue ? OverdueBrush : (Brush)FindResource("Muted")
            });
        }
        Grid.SetRow(footer, 3);
        grid.Children.Add(footer);

        border.Child = grid;
        // Click the tile body (not a button/checkbox) to select + edit it.
        border.MouseLeftButtonUp += (_, e) =>
        {
            if (FindAncestor<ButtonBase>(e.OriginalSource as DependencyObject) != null) return;
            SelectItem(item);
        };
        return border;
    }

    private static (int done, int total) ChildProgress(HierarchyItem i) => i switch
    {
        TaskItem t => (t.Subtasks.Count(s => s.IsComplete), t.Subtasks.Count),
        Procedure p => (p.Steps.Count(s => s.Done), p.Steps.Count),
        _ => (0, 0)
    };

    /// <summary>Mark a whole task/procedure complete (or not). Writes to the real item so it applies
    /// everywhere — Calendar, Board, the due-dates window, etc.</summary>
    private void SetItemDone(HierarchyItem item, bool done)
    {
        if (item is TaskItem t) t.IsComplete = done;          // auto-syncs Status
        else if (item is Procedure p) p.Status = done ? WorkStatus.Done : WorkStatus.Todo;
        _repo.MarkDirty();
        _repo.Save();
        RefreshPending();   // re-sorts (done sinks) and RefreshPinned() via the coupling
        if (ReferenceEquals(item, _selected)) BuildDetail();
    }

    private static T? FindAncestor<T>(DependencyObject? d) where T : DependencyObject => UiTree.FindAncestor<T>(d);

    /// <summary>Delete a whole task/procedure from the quick window — removed from the data (and any
    /// dangling references + its pin) so it disappears everywhere.</summary>
    private void DeleteItem(HierarchyItem item)
    {
        if (MessageBox.Show(this, $"Delete '{item.Name}' and everything under it? This removes it everywhere.",
                "Delete", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        _repo.LogRemoved(item is TaskItem ? "Task" : "Procedure", item.Name);
        if (item is TaskItem t) _repo.Data.Tasks.Remove(t);
        else if (item is Procedure p) _repo.Data.Procedures.Remove(p);
        _repo.PurgeReferences(item.Id);
        PinIds.Remove(item.Id);
        if (ReferenceEquals(item, _selected)) _selected = null;
        _repo.Save();
        RefreshPending();
        BuildDetail();
    }

    // ---- Buckets (defined in the Buckets tab; here you just sort items into up to two) ----
    private void MoveToBucket_Click(object sender, RoutedEventArgs e)
    {
        if (_selected == null)
        {
            MessageBox.Show(this, "Select a task or procedure first, then sort it into buckets.",
                "Sort into buckets", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (SortIntoBuckets(_selected, _selected.Name.Length > 0 ? _selected.Name : "this item")) RefreshPending();
    }

    /// <summary>Sort any bucketable (task, subtask, procedure, checklist step) into up to two predefined
    /// buckets via the picker. Returns true if the assignment changed (caller refreshes).</summary>
    private bool SortIntoBuckets(IBucketable target, string label)
    {
        if (_repo.Data.QuickBuckets.Count == 0)
        {
            MessageBox.Show(this, "No buckets are defined yet. Open the Buckets tab to create some (e.g. a location or a rank).",
                "Sort into buckets", MessageBoxButton.OK, MessageBoxImage.Information);
            return false;
        }
        var options = _repo.Data.QuickBuckets.Select(b => new PickerItem { Display = b.Display, Tag = b }).ToList();
        var preselect = _repo.Data.QuickBuckets.Where(b => target.BucketIds.Contains(b.Id)).Cast<object>();
        var dlg = new ItemPickerWindow($"Sort '{label}' into buckets (pick up to 2)", options, preselect, singleSelect: false) { Owner = this };
        if (dlg.ShowDialog() != true) return false;
        var picked = dlg.SelectedTags.OfType<QuickBucket>().ToList();
        if (picked.Count > 2)
        {
            MessageBox.Show(this, "An item can be in at most two buckets — keeping the first two you picked.",
                "Sort into buckets", MessageBoxButton.OK, MessageBoxImage.Information);
            picked = picked.Take(2).ToList();
        }
        target.BucketIds.Clear();
        foreach (var b in picked) target.BucketIds.Add(b.Id);
        _repo.Save();
        return true;
    }

    private void RemoveFromBucket_Click(object sender, RoutedEventArgs e)
    {
        if (_selected == null) return;
        _selected.BucketIds.Clear();
        _repo.Save();
        RefreshPending();
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

        // Title row + pin / delete / "open in main app".
        var titleRow = new DockPanel { Margin = new Thickness(0, 0, 0, 10) };

        var openBtn = new Button { Content = "Open in main window ↗", Padding = new Thickness(10, 4, 10, 4), Margin = new Thickness(6, 0, 0, 0) };
        openBtn.Click += (_, _) => { if (_selected != null) _navigate?.Invoke(_selected); };
        DockPanel.SetDock(openBtn, Dock.Right);
        titleRow.Children.Add(openBtn);

        var delBtn = new Button { Content = "🗑 Delete", Padding = new Thickness(10, 4, 10, 4), Margin = new Thickness(6, 0, 0, 0) };
        delBtn.Click += (_, _) => { if (_selected != null) DeleteItem(_selected); };
        DockPanel.SetDock(delBtn, Dock.Right);
        titleRow.Children.Add(delBtn);

        bool pinned = IsPinned(_selected);
        var pinBtn = new Button
        {
            Content = pinned ? "📌 Unpin" : "📌 Pin",
            Padding = new Thickness(10, 4, 10, 4),
            ToolTip = pinned ? "Remove this from the pinned squares above." : "Pin this as a square in the board above.",
            FontWeight = FontWeights.Bold
        };
        pinBtn.Click += (_, _) => { if (_selected != null) TogglePin(_selected); };
        DockPanel.SetDock(pinBtn, Dock.Right);
        titleRow.Children.Add(pinBtn);

        titleRow.Children.Add(new TextBlock
        {
            Text = _selected is TaskItem ? "Task" : "Procedure",
            FontSize = 20, FontWeight = FontWeights.Bold, Foreground = (Brush)FindResource("Accent"),
            VerticalAlignment = VerticalAlignment.Center
        });
        DetailHost.Children.Add(titleRow);

        // Header fields (shared by tasks and procedures).
        _qwDeadline = null; _qwStart = null;   // rebuilt fresh per selection
        AddField("Name:", MakeNameBox());
        AddField("Deadline:", MakeDeadlinePicker());
        if (_selected is TaskItem tRange) AddField("Range start:", MakeRangeStartPicker(tRange));
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
                () => LoadSubtaskTemplate(t),
                nameof(TaskItem.IsComplete));
        else if (_selected is Procedure p)
            BuildChildren(p.Steps, "Title", "step",
                title => new ChecklistStep { Title = title },
                child => new ChecklistStepEditorWindow(child, _repo) { Owner = this }.ShowDialog(),
                () => new ChecklistBuilderWindow(p, _repo) { Owner = this }.ShowDialog(),
                p.Name,
                () => SaveStepTemplate(p),
                () => LoadStepTemplate(p),
                nameof(ChecklistStep.Done));
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
        var dp = new DatePicker { SelectedDate = Deadline(_selected!), Width = 200, HorizontalAlignment = HorizontalAlignment.Left,
            ToolTip = "Due date — for a task this is also the LAST day of the working range." };
        _qwDeadline = dp;
        dp.SelectedDateChanged += (_, _) =>
        {
            if (_suppress || _selected == null || _qwDateSync) return;
            if (_selected is TaskItem tt && _qwStart != null)
            {
                var (s, d) = AA.Services.WorkRange.Coerce(_qwStart.SelectedDate, dp.SelectedDate, editedStart: false);
                _qwDateSync = true; _qwStart.SelectedDate = s; dp.SelectedDate = d; _qwDateSync = false;
                tt.RangeStart = s; tt.Deadline = d;
            }
            else SetDeadline(_selected, dp.SelectedDate);
            _repo.MarkDirty();
        };
        return dp;
    }

    private DatePicker MakeRangeStartPicker(TaskItem t)
    {
        var dp = new DatePicker { SelectedDate = t.RangeStart, Width = 200, HorizontalAlignment = HorizontalAlignment.Left,
            ToolTip = "Optional first day of the working range. Leave empty for a single-day task; the deadline stays the last day." };
        _qwStart = dp;
        dp.SelectedDateChanged += (_, _) =>
        {
            if (_suppress || _qwDateSync) return;
            var (s, d) = AA.Services.WorkRange.Coerce(dp.SelectedDate, _qwDeadline?.SelectedDate, editedStart: true);
            _qwDateSync = true; dp.SelectedDate = s; if (_qwDeadline != null) _qwDeadline.SelectedDate = d; _qwDateSync = false;
            t.RangeStart = s; t.Deadline = d;
            _repo.MarkDirty();
        };
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
        Action saveTemplate, Action loadTemplate, string donePath) where T : class
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

        // Children list — done children are struck through (their done state is the real model state,
        // so it matches everywhere else in the app).
        var list = new ListBox { Height = 300, SelectionMode = SelectionMode.Extended, ItemsSource = coll };
        var tmpl = new DataTemplate();
        var tb = new FrameworkElementFactory(typeof(TextBlock));
        tb.SetBinding(TextBlock.TextProperty, new System.Windows.Data.Binding(displayPath));
        tb.SetValue(TextBlock.TextWrappingProperty, TextWrapping.Wrap);
        tb.SetBinding(TextBlock.TextDecorationsProperty,
            new System.Windows.Data.Binding(donePath) { Converter = (System.Windows.Data.IValueConverter)FindResource("BoolToStrike") });
        tmpl.VisualTree = tb;
        list.ItemTemplate = tmpl;
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
        B("🪣 Buckets...", (_, _) =>
        {
            if (list.SelectedItem is IBucketable ib)
            {
                if (SortIntoBuckets(ib, ChildName(list.SelectedItem, displayPath))) RefreshPending();
            }
            else MessageBox.Show(this, $"Select a {noun} first, then sort it into buckets.",
                "Sort into buckets", MessageBoxButton.OK, MessageBoxImage.Information);
        });
        B("Open full builder...", (_, _) => { openFull(); RefreshPending(); });
        B("💾 Save as list...", (_, _) => saveTemplate());
        B("📋 Load a saved list...", (_, _) => { loadTemplate(); RefreshPending(); });
        DetailHost.Children.Add(btns);

        list.MouseDoubleClick += (_, _) => { if (list.SelectedItem is T c) { edit(c); _repo.FlushIfDirty(); RefreshPending(); } };
        // Right-click: batch mark selected children done / not done.
        var childMenu = new ContextMenu();
        BatchDoneMenu.Add(childMenu, _repo, () => list.SelectedItems.Cast<object>(), RefreshPending, separatorFirst: false);
        list.ContextMenu = childMenu;
        list.PreviewMouseRightButtonDown += (_, e) => BatchDoneMenu.RightClickSelect(list, e.OriginalSource as DependencyObject);

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
