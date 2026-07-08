using System;
using System.Windows;
using System.Windows.Controls;
using AA.Models;
using AA.Services;

namespace AA.Views;

public partial class SubtaskEditorWindow : Window
{
    private readonly TaskItem _task;
    private readonly AppRepository _repo;
    private bool _suppress;

    public SubtaskEditorWindow(TaskItem task, AppRepository repo)
    {
        InitializeComponent();
        _task = task;
        _repo = repo;

        _suppress = true;
        NameBox.Text = task.Name;
        DescBox.Text = task.Description;
        DeadlinePicker.SelectedDate = task.Deadline;
        RecurrenceBox.ItemsSource = Enum.GetValues(typeof(RecurrenceKind));
        RecurrenceBox.SelectedItem = task.Recurrence;
        StatusBox.ItemsSource = Enum.GetValues(typeof(WorkStatus));
        StatusBox.SelectedItem = task.Status;
        DoneBox.IsChecked = task.IsComplete;
        JobBox.IsChecked = task.IsJob;
        DurationBox.Text = task.DurationMinutes.ToString();
        ContainerCtrl.Load(task.Container, repo);
        _suppress = false;

        Title = $"Edit subtask — {task.Name}";
        Closing += (_, _) => { ContainerCtrl.FlushPending(); _repo.FlushIfDirty(); };
    }

    private void Name_Changed(object sender, TextChangedEventArgs e)
    {
        if (_suppress) return;
        _task.Name = NameBox.Text;
        Title = $"Edit subtask — {_task.Name}";
        _repo.MarkDirty();
    }
    private void Desc_Changed(object sender, TextChangedEventArgs e)
    {
        if (_suppress) return;
        _task.Description = DescBox.Text;
        _repo.MarkDirty();
    }
    private void Deadline_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_suppress) return;
        _task.Deadline = DeadlinePicker.SelectedDate;
        _repo.MarkDirty();
    }
    private void Recurrence_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_suppress) return;
        if (RecurrenceBox.SelectedItem is RecurrenceKind r)
        {
            _task.Recurrence = r;
            _repo.MarkDirty();
        }
    }
    private void Status_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_suppress) return;
        if (StatusBox.SelectedItem is not WorkStatus st) return;
        _task.Status = st;
        // The model keeps IsComplete in sync; reflect it in the checkbox.
        _suppress = true;
        DoneBox.IsChecked = _task.IsComplete;
        _suppress = false;
        _repo.MarkDirty();
    }
    private void Done_Changed(object sender, RoutedEventArgs e)
    {
        if (_suppress) return;
        _task.IsComplete = DoneBox.IsChecked == true;
        // The model keeps Status in sync; reflect it in the combo.
        _suppress = true;
        StatusBox.SelectedItem = _task.Status;
        _suppress = false;
        _repo.MarkDirty();
    }
    private void Job_Changed(object sender, RoutedEventArgs e)
    {
        if (_suppress) return;
        _task.IsJob = JobBox.IsChecked == true;
        _repo.MarkDirty();
    }
    private void Duration_Changed(object sender, TextChangedEventArgs e)
    {
        if (_suppress) return;
        if (int.TryParse(DurationBox.Text, out var m) && m > 0) { _task.DurationMinutes = m; _repo.MarkDirty(); }
    }
    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
