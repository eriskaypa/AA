using System.Windows;
using System.Windows.Controls;
using AA.Models;
using AA.Services;

namespace AA.Views;

public partial class ChecklistStepEditorWindow : Window
{
    private readonly ChecklistStep _step;
    private readonly AppRepository _repo;
    private bool _suppress;

    public ChecklistStepEditorWindow(ChecklistStep step, AppRepository repo)
    {
        InitializeComponent();
        _step = step;
        _repo = repo;

        _suppress = true;
        TitleBox.Text = step.Title;
        DeadlinePicker.SelectedDate = step.Deadline;
        DoneBox.IsChecked = step.Done;
        JobBox.IsChecked = step.IsJob;
        DurationBox.Text = step.DurationMinutes.ToString();
        ContainerCtrl.Load(step.Container, repo);
        _suppress = false;

        Title = $"Edit checklist step — {step.Title}";
        Closing += (_, _) => { ContainerCtrl.FlushPending(); _repo.FlushIfDirty(); };
    }

    private void Title_Changed(object sender, TextChangedEventArgs e)
    {
        if (_suppress) return;
        _step.Title = TitleBox.Text;
        Title = $"Edit checklist step — {_step.Title}";
        _repo.MarkDirty();
    }
    private void Deadline_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_suppress) return;
        _step.Deadline = DeadlinePicker.SelectedDate;
        _repo.MarkDirty();
    }
    private void Done_Changed(object sender, RoutedEventArgs e)
    {
        if (_suppress) return;
        _step.Done = DoneBox.IsChecked == true;
        _repo.MarkDirty();
    }
    private void Job_Changed(object sender, RoutedEventArgs e)
    {
        if (_suppress) return;
        _step.IsJob = JobBox.IsChecked == true;
        _repo.MarkDirty();
    }
    private void Duration_Changed(object sender, TextChangedEventArgs e)
    {
        if (_suppress) return;
        if (int.TryParse(DurationBox.Text, out var m) && m > 0) { _step.DurationMinutes = m; _repo.MarkDirty(); }
    }
    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
