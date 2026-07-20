using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using AA.Models;
using AA.Services;

namespace AA.Views;

public partial class BoardPage : UserControl
{
    private AppRepository? _repo;
    private bool _built;
    private Point _dragStart;

    private readonly ListBox[] _lists = new ListBox[4];
    private readonly TextBlock[] _counts = new TextBlock[4];

    // Column definitions: status, title, accent colour.
    private static readonly (WorkStatus status, string title, string color)[] Columns =
    {
        (WorkStatus.Todo,       "To Do",       "#FF546E7A"),
        (WorkStatus.InProgress, "In Progress", "#FF1E88E5"),
        (WorkStatus.Blocked,    "Blocked",     "#FFE53935"),
        (WorkStatus.Done,       "Done",        "#FF2E7D32"),
    };

    private static readonly Brush MutedBrush = Freeze("#FF6B6B6B");
    private static readonly Brush OverdueBrush = Freeze("#FFD32F2F");

    public BoardPage() { InitializeComponent(); }

    public void Init(AppRepository repo)
    {
        _repo = repo;
        BuildColumns();
        Refresh();
    }

    private static Brush Freeze(string hex)
    {
        var b = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
        b.Freeze();
        return b;
    }

    private void BuildColumns()
    {
        if (_built) return;
        _built = true;
        var colStyle = (Style)Resources["ColumnList"];
        for (int i = 0; i < Columns.Length; i++)
        {
            var (status, title, color) = Columns[i];
            var accent = Freeze(color);

            var outer = new Border
            {
                Background = (Brush)FindResource("Panel"),
                BorderBrush = (Brush)FindResource("BorderB"),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(6),
                Margin = new Thickness(i == 0 ? 0 : 3, 0, i == Columns.Length - 1 ? 0 : 3, 0)
            };
            var dock = new DockPanel();

            // Coloured column header with live count.
            var headerBorder = new Border
            {
                Background = accent,
                CornerRadius = new CornerRadius(6, 6, 0, 0),
                Padding = new Thickness(10, 6, 10, 6)
            };
            DockPanel.SetDock(headerBorder, Dock.Top);
            var headerDock = new DockPanel();
            headerDock.Children.Add(new TextBlock
            {
                Text = title,
                FontWeight = FontWeights.Bold,
                FontSize = 14,
                Foreground = Brushes.White
            });
            var count = new TextBlock
            {
                Foreground = Brushes.White,
                Opacity = 0.85,
                HorizontalAlignment = HorizontalAlignment.Right,
                FontWeight = FontWeights.Bold
            };
            DockPanel.SetDock(count, Dock.Right);
            headerDock.Children.Add(count);
            headerBorder.Child = headerDock;
            dock.Children.Add(headerBorder);

            var list = new ListBox { Style = colStyle, Tag = status.ToString(), SelectionMode = SelectionMode.Extended };
            list.PreviewMouseLeftButtonDown += List_PreviewMouseLeftButtonDown;
            list.PreviewMouseRightButtonDown += List_PreviewMouseRightButtonDown;
            list.PreviewMouseMove += List_PreviewMouseMove;
            list.DragOver += List_DragOver;
            list.Drop += List_Drop;
            list.MouseDoubleClick += List_MouseDoubleClick;
            list.ContextMenu = BuildCardMenu(list);
            dock.Children.Add(list);

            outer.Child = dock;
            Grid.SetColumn(outer, i);
            ColumnsRoot.Children.Add(outer);
            _lists[i] = list;
            _counts[i] = count;
        }
    }

    private ContextMenu BuildCardMenu(ListBox list)
    {
        var cm = new ContextMenu();
        var open = new MenuItem { Header = "Open / edit task" };
        open.Click += (_, _) => { if (list.SelectedItem is Card c) OpenEditor(c.Task); };
        var openFiles = new MenuItem { Header = "Open all files (routine)" };
        openFiles.Click += (_, _) => { if (list.SelectedItem is Card c) OpenAllFiles(c.Task); };
        cm.Items.Add(open);
        cm.Items.Add(openFiles);
        // Batch done/undone across every selected card.
        BatchDoneMenu.Add(cm, _repo!, () => list.SelectedItems.OfType<Card>().Select(c => (object)c.Task), Refresh);
        BatchDeadlineMenu.Add(cm, _repo!, () => list.SelectedItems.OfType<Card>().Select(c => (object)c.Task), Refresh, separatorFirst: false);
        cm.Items.Add(new Separator());
        var del = new MenuItem { Header = "Delete task" };
        del.Click += (_, _) => { if (list.SelectedItem is Card c) DeleteTask(c.Task); };
        cm.Items.Add(del);
        return cm;
    }

    public void Refresh()
    {
        if (_repo == null || !_built) return;
        var q = SearchBox.Text?.Trim() ?? "";
        bool hideDone = HideDoneChk.IsChecked == true;

        // Every task AND every nested subtask is its own card, grouped by its own status — so a subtask
        // (regardless of deadline) lands in To Do just like a task. The parent path gives it context.
        var flat = FlattenTasks().ToList();
        if (!string.IsNullOrEmpty(q))
            flat = flat.Where(x => x.task.Name.Contains(q, StringComparison.OrdinalIgnoreCase)).ToList();
        if (hideDone)
            flat = flat.Where(x => x.task.Status != WorkStatus.Done).ToList();

        for (int i = 0; i < Columns.Length; i++)
        {
            var (status, _, color) = Columns[i];
            var accent = Freeze(color);
            var cards = flat.Where(x => x.task.Status == status).Select(x => new Card(x.task, accent, x.path)).ToList();
            _lists[i].ItemsSource = cards;
            _counts[i].Text = cards.Count.ToString();
        }
    }

    /// <summary>Every task and every descendant subtask, paired with the " › "-joined path of its ancestors
    /// ("" for a top-level task). A visited-set guards against accidental cycles.</summary>
    private IEnumerable<(TaskItem task, string path)> FlattenTasks()
    {
        var seen = new HashSet<Guid>();
        foreach (var t in _repo!.Data.Tasks)
            foreach (var x in WalkTasks(t, "", seen)) yield return x;
    }

    private static IEnumerable<(TaskItem task, string path)> WalkTasks(TaskItem t, string parentPath, HashSet<Guid> seen)
    {
        if (!seen.Add(t.Id)) yield break;
        yield return (t, parentPath);
        // Use a placeholder for an empty name so a subtask of an unnamed parent still shows a "↳ …" path
        // (an empty name would otherwise collapse to "" and make the subtask look top-level).
        var seg = string.IsNullOrWhiteSpace(t.Name) ? "(unnamed)" : t.Name;
        var childPath = parentPath.Length == 0 ? seg : $"{parentPath} › {seg}";
        foreach (var st in t.Subtasks)
            foreach (var x in WalkTasks(st, childPath, seen)) yield return x;
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e) => Refresh();
    private void HideDone_Changed(object sender, RoutedEventArgs e) => Refresh();

    private void NewTask_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null) return;
        var p = new PromptWindow("New Task", "Name:") { Owner = Window.GetWindow(this) };
        if (p.ShowDialog() == true && !string.IsNullOrWhiteSpace(p.Value))
        {
            _repo.Data.Tasks.Add(new TaskItem { Name = p.Value, Status = WorkStatus.Todo });
            _repo.Save();
            Refresh();
        }
    }

    private void FromSavedList_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null) return;
        var created = SavedListPicker.PickAndAddTasks(_repo, Window.GetWindow(this));
        if (created.Count > 0) Refresh();
    }

    private void OpenEditor(TaskItem t)
    {
        if (_repo == null) return;
        var w = new SubtaskEditorWindow(t, _repo) { Owner = Window.GetWindow(this) };
        w.ShowDialog();
        _repo.FlushIfDirty();
        Refresh();
    }

    private void OpenAllFiles(TaskItem t)
    {
        var files = t.Container.Files.ToList();
        if (files.Count == 0)
        {
            MessageBox.Show("This task has no files yet. Open the task and add some to the file bank.",
                "Open all files", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (files.Count > 15 &&
            MessageBox.Show($"Open all {files.Count} files for '{t.Name}'?", "Open all files",
                MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        foreach (var fi in files)
        {
            try
            {
                var target = fi.IsLink ? fi.Path : DataStore.ResolveFilePath(fi.Path);
                if (!fi.IsLink && !File.Exists(target) && !Directory.Exists(target)) continue;
                Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
            }
            catch { /* skip the ones that fail, keep launching the rest */ }
        }
    }

    private void DeleteTask(TaskItem t)
    {
        if (_repo == null) return;
        int subs = CountDescendants(t);
        string extra = subs > 0 ? $"\n\nThis also deletes its {subs} subtask(s)." : "";
        if (MessageBox.Show($"Delete task '{t.Name}'?{extra}", "Confirm",
                MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        // A card can be a nested subtask, so remove it from wherever it actually lives.
        RemoveTaskAnywhere(_repo.Data.Tasks, t);
        _repo.PurgeReferences(t.Id);
        _repo.Save();
        Refresh();
    }

    private static bool RemoveTaskAnywhere(System.Collections.Generic.ICollection<TaskItem> coll, TaskItem t)
    {
        if (coll.Remove(t)) return true;
        foreach (var item in coll)
            if (RemoveTaskAnywhere(item.Subtasks, t)) return true;
        return false;
    }

    private static int CountDescendants(TaskItem t)
    {
        int n = t.Subtasks.Count;
        foreach (var s in t.Subtasks) n += CountDescendants(s);
        return n;
    }

    // ---- Drag & drop between columns ----
    private void List_PreviewMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        => _dragStart = e.GetPosition(null);

    private void List_PreviewMouseRightButtonDown(object sender, MouseButtonEventArgs e)
    {
        // WPF doesn't select on right-click. Select the clicked card, but keep an existing multi-selection
        // intact when the click lands on a card that's already selected (so batch actions act on all of them).
        if (sender is Selector list) BatchDoneMenu.RightClickSelect(list, e.OriginalSource as DependencyObject);
    }

    private void List_PreviewMouseMove(object sender, MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed) return;
        var pos = e.GetPosition(null);
        if (Math.Abs(pos.X - _dragStart.X) < SystemParameters.MinimumHorizontalDragDistance &&
            Math.Abs(pos.Y - _dragStart.Y) < SystemParameters.MinimumVerticalDragDistance) return;

        var item = FindAncestor<ListBoxItem>(e.OriginalSource as DependencyObject);
        if (item?.DataContext is not Card card) return;
        DragDrop.DoDragDrop(item, card, DragDropEffects.Move);
    }

    private void List_DragOver(object sender, DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent(typeof(Card)) ? DragDropEffects.Move : DragDropEffects.None;
        e.Handled = true;
    }

    private void List_Drop(object sender, DragEventArgs e)
    {
        if (_repo == null || sender is not ListBox lb) return;
        if (e.Data.GetData(typeof(Card)) is not Card card) return;
        if (lb.Tag is not string tag || !Enum.TryParse<WorkStatus>(tag, out var status)) return;
        if (card.Task.Status == status) return;
        card.Task.Status = status;          // also syncs IsComplete
        _repo.MarkDirty();
        _repo.FlushIfDirty();
        Refresh();
    }

    private void List_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (sender is ListBox lb && lb.SelectedItem is Card card) OpenEditor(card.Task);
    }

    private static T? FindAncestor<T>(DependencyObject? d) where T : DependencyObject => UiTree.FindAncestor<T>(d);

    /// <summary>Lightweight per-card view-model rebuilt on every Refresh.</summary>
    private sealed class Card
    {
        public TaskItem Task { get; }
        public string Name => Task.Name;
        public bool Done => Task.IsComplete;
        public Brush Accent { get; }
        public string Meta { get; }
        public string Badges { get; }
        public string Parent { get; }
        public Brush MetaBrush { get; }
        public Visibility MetaVisible => string.IsNullOrEmpty(Meta) ? Visibility.Collapsed : Visibility.Visible;
        public Visibility BadgesVisible => string.IsNullOrEmpty(Badges) ? Visibility.Collapsed : Visibility.Visible;
        public Visibility ParentVisible => string.IsNullOrEmpty(Parent) ? Visibility.Collapsed : Visibility.Visible;

        public Card(TaskItem t, Brush accent, string parentPath = "")
        {
            Task = t;
            Accent = accent;
            Parent = parentPath.Length > 0 ? $"↳ {parentPath}" : "";

            bool overdue = t.Deadline.HasValue && t.Deadline.Value.Date < DateTime.Today && t.Status != WorkStatus.Done;
            var meta = new List<string>();
            if (t.Deadline.HasValue)
            {
                // Show the working range when set, else the single due date. OVERDUE stays keyed on the deadline (end).
                string when = t.RangeStart.HasValue && t.RangeStart.Value.Date < t.Deadline.Value.Date
                    ? $"{t.RangeStart.Value:yyyy-MM-dd} → {t.Deadline.Value:yyyy-MM-dd}"
                    : $"Due {t.Deadline.Value:yyyy-MM-dd}";
                meta.Add(when + (overdue ? "  ·  OVERDUE" : ""));
            }
            if (t.Recurrence != RecurrenceKind.None) meta.Add(t.Recurrence.ToString());
            Meta = string.Join("   ·   ", meta);
            MetaBrush = overdue ? OverdueBrush : MutedBrush;

            var badges = new List<string>();
            int files = t.Container?.Files.Count ?? 0;
            if (files > 0) badges.Add($"📎 {files} file{(files == 1 ? "" : "s")}");
            int subs = t.Subtasks.Count;
            if (subs > 0) badges.Add($"☑ {t.Subtasks.Count(s => s.IsComplete)}/{subs}");
            Badges = string.Join("    ", badges);
        }
    }
}
