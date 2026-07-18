using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using AA.Models;
using AA.Services;

namespace AA.Views;

public partial class CalendarPage : UserControl
{
    private AppRepository? _repo;
    private Action<HierarchyItem>? _navigate;
    public CalendarPage() { InitializeComponent(); }

    public void Init(AppRepository repo, Action<HierarchyItem>? navigate = null)
    {
        _repo = repo;
        _navigate = navigate;
        Cal.SelectedDate = repo.Data.Ui.CalendarSelectedDate ?? DateTime.Today;
        switch (repo.Data.Ui.CalendarViewMode)
        {
            case "Week": RbWeek.IsChecked = true; break;
            case "Month": RbMonth.IsChecked = true; break;
            case "All": RbAll.IsChecked = true; break;
            case "Agenda": RbAgenda.IsChecked = true; break;
            default: RbDay.IsChecked = true; break;
        }
        if (repo.Data.Ui.CalendarFontScale is double fs && fs >= 10 && fs <= 30)
            TaskGrid.FontSize = fs;

        // Right-click: batch mark the selected schedule rows done / not done (acts on the underlying items).
        var cm = new ContextMenu();
        BatchDoneMenu.Add(cm, repo, () => TaskGrid.SelectedItems.OfType<ScheduleRow>().Select(r => r.Item),
            Refresh, separatorFirst: false);
        TaskGrid.ContextMenu = cm;

        Refresh();
    }

    private void TaskGrid_RightDown(object sender, MouseButtonEventArgs e)
        => BatchDoneMenu.RightClickSelect(TaskGrid, e.OriginalSource as DependencyObject);

    public DateTime? CalendarSelectedDate => Cal.SelectedDate;
    public string CalendarViewMode =>
        RbWeek.IsChecked == true ? "Week" :
        RbMonth.IsChecked == true ? "Month" :
        RbAll.IsChecked == true ? "All" :
        RbAgenda.IsChecked == true ? "Agenda" : "Day";

    private void Cal_SelectedDatesChanged(object sender, SelectionChangedEventArgs e) => Refresh();
    private void View_Changed(object sender, System.Windows.RoutedEventArgs e) => Refresh();

    private void FontBigger_Click(object sender, RoutedEventArgs e) => SetFontSize(TaskGrid.FontSize + 1.5);
    private void FontSmaller_Click(object sender, RoutedEventArgs e) => SetFontSize(TaskGrid.FontSize - 1.5);
    private void SetFontSize(double size)
    {
        size = Math.Max(11, Math.Min(28, size));
        TaskGrid.FontSize = size;
        if (_repo != null) { _repo.Data.Ui.CalendarFontScale = size; _repo.MarkDirty(); }
    }

    public void Refresh()
    {
        if (_repo == null) return;

        // Tasks + subtasks (flattened) AND procedure checklist steps — every dated item is wrapped in
        // a uniform ScheduleRow so a step "acts like a subtask" on the schedule.
        var rows = new List<ScheduleRow>();
        foreach (var t in _repo.Data.Tasks)
            foreach (var ft in Flatten(t))
                if (ft.Deadline != null) rows.Add(ScheduleRow.ForTask(ft));
        foreach (var p in _repo.Data.Procedures)
        {
            if (p.Deadline != null) rows.Add(ScheduleRow.ForProcedure(p));
            foreach (var s in p.Steps)
                if (s.Deadline != null) rows.Add(ScheduleRow.ForStep(s, p));
        }
        // Crew members' personal checklist items with a due date.
        foreach (var c in _repo.Data.Crew)
            foreach (var s in c.Checklist)
                if (s.Deadline != null) rows.Add(ScheduleRow.ForCrewStep(s, c));

        var d = Cal.SelectedDate ?? DateTime.Today;
        IEnumerable<ScheduleRow> filtered;
        bool agenda = RbAgenda.IsChecked == true;
        if (RbDay.IsChecked == true)
        {
            // A ranged task shows on EVERY day of its span, not just its deadline.
            filtered = rows.Where(r => r.Covers(d));
            DayLabel.Text = $"Schedule — {d:yyyy-MM-dd}";
        }
        else if (RbWeek.IsChecked == true)
        {
            var start = d.AddDays(-(int)d.DayOfWeek);
            var end = start.AddDays(7);
            // Interval overlap: any range touching the week appears, even if it starts before / ends after.
            filtered = rows.Where(r => r.EffectiveStart.Date < end.Date && r.Deadline!.Value.Date >= start.Date);
            DayLabel.Text = $"Schedule — week of {start:yyyy-MM-dd}";
        }
        else if (RbMonth.IsChecked == true)
        {
            var monthStart = new DateTime(d.Year, d.Month, 1);
            var monthEnd = monthStart.AddMonths(1);
            filtered = rows.Where(r => r.EffectiveStart.Date < monthEnd && r.Deadline!.Value.Date >= monthStart);
            DayLabel.Text = $"Schedule — {d:yyyy-MM}";
        }
        else if (agenda)
        {
            filtered = rows.Where(r => r.Deadline!.Value.Date >= DateTime.Today || r.Covers(DateTime.Today));
            DayLabel.Text = "Agenda — upcoming by day";
        }
        else
        {
            filtered = rows.Where(r => r.Deadline!.Value.Date >= DateTime.Today || r.Covers(DateTime.Today));
            DayLabel.Text = "Schedule — all upcoming";
        }

        if (agenda)
        {
            // Fan each ranged row out into one occurrence per covered day (from today onward) so it appears
            // under every day it spans; long ranges are capped so the list can't explode.
            const int MaxSpanDays = 31;
            var occurrences = new List<ScheduleRow>();
            foreach (var r in filtered)
            {
                if (!r.IsRanged) { occurrences.Add(r); continue; }
                var from = r.EffectiveStart.Date < DateTime.Today ? DateTime.Today : r.EffectiveStart.Date;
                var to = r.Deadline!.Value.Date;
                if ((to - from).TotalDays > MaxSpanDays) { occurrences.Add(r.AtOccurrence(to)); continue; }
                for (var day = from; day <= to; day = day.AddDays(1))
                    occurrences.Add(r.AtOccurrence(day));
            }
            var view = new ListCollectionView(occurrences.OrderBy(r => r.GroupKey).ThenBy(r => r.Name).ToList());
            view.GroupDescriptions.Add(new PropertyGroupDescription(nameof(ScheduleRow.GroupKey), new DateGroupConverter()));
            TaskGrid.ItemsSource = view;
        }
        else
        {
            TaskGrid.ItemsSource = filtered.OrderBy(r => r.EffectiveStart).ThenBy(r => r.Deadline).ToList();
        }
    }

    private static System.Collections.Generic.IEnumerable<TaskItem> Flatten(TaskItem t)
    {
        yield return t;
        foreach (var s in t.Subtasks)
            foreach (var x in Flatten(s)) yield return x;
    }

    private void TaskDone_Toggled(object sender, RoutedEventArgs e)
    {
        // Two-way binding already mutated TaskItem.IsComplete; we just persist.
        _repo?.MarkDirty();
        _repo?.FlushIfDirty();
    }

    private void TaskGrid_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (_repo == null) return;
        // Ignore double-clicks on column headers or empty area.
        if (e.OriginalSource is DependencyObject d && FindAncestor<GridViewColumnHeader>(d) != null) return;
        if (TaskGrid.SelectedItem is not ScheduleRow row) return;

        // Open the right editor for the underlying item — a task/subtask or a checklist step; a
        // procedure has no modal editor, so navigate to it in the Procedures tab instead.
        if (row.Item is TaskItem t)
            new SubtaskEditorWindow(t, _repo) { Owner = Window.GetWindow(this) }.ShowDialog();
        else if (row.Item is ChecklistStep s)
            new ChecklistStepEditorWindow(s, _repo) { Owner = Window.GetWindow(this) }.ShowDialog();
        else if (row.Item is Procedure p) { _navigate?.Invoke(p); return; }
        _repo.FlushIfDirty();
        Refresh();
    }

    private static T? FindAncestor<T>(DependencyObject? d) where T : DependencyObject => UiTree.FindAncestor<T>(d);

    /// <summary>Uniform schedule row wrapping either a TaskItem (or subtask) or a procedure
    /// ChecklistStep, exposing the same property names the grid binds to (Name/Deadline/Status/
    /// Recurrence/IsComplete) so both kinds appear together. Toggling IsComplete writes back to the
    /// underlying item.</summary>
    public sealed class ScheduleRow : System.ComponentModel.INotifyPropertyChanged
    {
        public object Item { get; }
        public string Name { get; }
        public DateTime? Deadline { get; }
        /// <summary>Optional working-range start (tasks only). The range END is the Deadline.</summary>
        public DateTime? RangeStart { get; }
        public string Recurrence { get; }

        /// <summary>First day this row occupies — the range start if set and valid, else the deadline. The
        /// start is clamped to the deadline so an out-of-order range from an imported/hand-edited file
        /// degrades to a single-day point (matching TaskItem.CoversDay and PlannerPage.DueSpan) instead of
        /// vanishing from the Day/Week filters.</summary>
        public DateTime EffectiveStart =>
            RangeStart is DateTime s && Deadline is DateTime d && s.Date <= d.Date ? s.Date : Deadline!.Value;
        /// <summary>True when this row spans more than a single day.</summary>
        public bool IsRanged => RangeStart is DateTime s && Deadline is DateTime d && s.Date < d.Date;
        /// <summary>True when [start..deadline] covers <paramref name="day"/> (point rows cover only the deadline).</summary>
        public bool Covers(DateTime day) => Deadline != null && EffectiveStart.Date <= day.Date && Deadline.Value.Date >= day.Date;
        /// <summary>"start → deadline" when ranged, else the plain deadline date. Bound by the schedule grid.</summary>
        public string RangeDisplay => IsRanged ? $"{RangeStart:yyyy-MM-dd} → {Deadline:yyyy-MM-dd}" : $"{Deadline:yyyy-MM-dd}";
        /// <summary>Agenda-only: the specific covered day this occurrence represents (null = group by deadline).</summary>
        public DateTime? OccurrenceDate { get; set; }
        /// <summary>Day-bucket key for grouping (Agenda occurrence day if set, else the deadline).</summary>
        public DateTime? GroupKey => OccurrenceDate ?? Deadline;
        // Status reflects the LIVE underlying state so it updates the instant Done is toggled on the
        // schedule (a task's IsComplete flips its WorkStatus; a step just toggles Done).
        public string Status => Item switch
        {
            TaskItem t => t.Status.ToString(),
            Procedure p => p.Status.ToString(),
            ChecklistStep s => s.Done ? "Done" : "Step",
            _ => ""
        };
        private readonly Action<bool> _apply;
        private bool _isComplete;
        public bool IsComplete
        {
            get => _isComplete;
            set
            {
                if (_isComplete == value) return;
                _isComplete = value;
                _apply(value);
                PropertyChanged?.Invoke(this, new System.ComponentModel.PropertyChangedEventArgs(nameof(IsComplete)));
                PropertyChanged?.Invoke(this, new System.ComponentModel.PropertyChangedEventArgs(nameof(Status)));
            }
        }
        public event System.ComponentModel.PropertyChangedEventHandler? PropertyChanged;

        private ScheduleRow(object item, string name, DateTime? rangeStart, DateTime? deadline, string recurrence,
            bool complete, Action<bool> apply)
        {
            Item = item; Name = name; RangeStart = rangeStart; Deadline = deadline; Recurrence = recurrence;
            _isComplete = complete; _apply = apply;
        }

        /// <summary>A lightweight copy pinned to one covered day, for the Agenda per-day fan-out.</summary>
        public ScheduleRow AtOccurrence(DateTime day) =>
            new(Item, Name, RangeStart, Deadline, Recurrence, _isComplete, _apply) { OccurrenceDate = day.Date };

        public static ScheduleRow ForTask(TaskItem t) =>
            new(t, t.Name, t.RangeStart, t.Deadline, t.Recurrence.ToString(), t.IsComplete, v => t.IsComplete = v);

        public static ScheduleRow ForStep(ChecklistStep s, Procedure p) =>
            new(s, $"{s.Title}   ·  [{p.Name}]", null, s.Deadline, "", s.Done, v => s.Done = v);

        public static ScheduleRow ForCrewStep(ChecklistStep s, CrewMember c) =>
            new(s, $"{s.Title}   ·  👤 {(c.FullName.Length > 0 ? c.FullName : "(unnamed)")}", null, s.Deadline, "", s.Done, v => s.Done = v);

        public static ScheduleRow ForProcedure(Procedure p) =>
            new(p, p.Name, null, p.Deadline, p.Recurrence.ToString(), p.Status == WorkStatus.Done,
                v => p.Status = v ? WorkStatus.Done : WorkStatus.Todo);
    }

    /// <summary>Buckets a row's Deadline into a friendly day label for the Agenda view.</summary>
    private sealed class DateGroupConverter : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        {
            if (value is DateTime dt)
            {
                var day = dt.Date;
                var today = DateTime.Today;
                if (day == today) return "Today";
                if (day == today.AddDays(1)) return "Tomorrow";
                return day.ToString("ddd, yyyy-MM-dd");
            }
            return "No date";
        }
        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
            => throw new NotSupportedException();
    }
}
