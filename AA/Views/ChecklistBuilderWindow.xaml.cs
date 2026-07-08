using System.Windows;
using AA.Models;
using AA.Services;

namespace AA.Views;

/// <summary>Full-window checklist builder for a procedure's steps. Hosts the shared
/// <see cref="ChecklistBuilderControl"/> so procedures and crew members use the same builder.</summary>
public partial class ChecklistBuilderWindow : Window
{
    public ChecklistBuilderWindow(Procedure proc, AppRepository repo)
    {
        InitializeComponent();
        HeaderText.Text = $"Checklist builder — {proc.Name}";
        Builder.Bind(proc.Steps, repo, proc.Name, "Checklist step");
        Closing += (_, _) => repo.FlushIfDirty();
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
