using System.Collections.ObjectModel;
using System.Windows;
using AA.Models;
using AA.Services;

namespace AA.Views;

/// <summary>Edits a saved list's items by round-tripping them through the shared checklist builder:
/// the template items are materialised as steps, edited, then written back on close.</summary>
public partial class TemplateEditorWindow : Window
{
    private readonly ChecklistTemplate _template;
    private readonly AppRepository _repo;
    private readonly ObservableCollection<ChecklistStep> _steps;

    public TemplateEditorWindow(ChecklistTemplate template, AppRepository repo)
    {
        InitializeComponent();
        _template = template;
        _repo = repo;
        HeaderText.Text = $"Edit saved list — {(_template.Name.Length > 0 ? _template.Name : "(unnamed)")}";
        _steps = ChecklistTemplateService.ToSteps(_template);
        Builder.Bind(_steps, repo, _template.Name, "Saved-list item");
        Closing += (_, _) =>
        {
            ChecklistTemplateService.WriteBackFromSteps(_template, _steps);
            _repo.Save();
        };
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
