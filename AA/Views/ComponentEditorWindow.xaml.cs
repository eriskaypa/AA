using System.Windows;
using System.Windows.Controls;
using AA.Models;
using AA.Services;

namespace AA.Views;

public partial class ComponentEditorWindow : Window
{
    private readonly Component _component;
    private readonly AppRepository _repo;
    private bool _suppress;

    public ComponentEditorWindow(Component component, AppRepository repo)
    {
        InitializeComponent();
        _component = component;
        _repo = repo;

        _suppress = true;
        NameBox.Text = component.Name;
        NotesBox.Text = component.Notes;
        ContainerCtrl.Load(component.Container, repo);
        _suppress = false;

        Title = $"Edit component — {component.Name}";
        Closing += (_, _) => { ContainerCtrl.FlushPending(); _repo.FlushIfDirty(); };
    }

    private void Name_Changed(object sender, TextChangedEventArgs e)
    {
        if (_suppress) return;
        _component.Name = NameBox.Text;
        Title = $"Edit component — {_component.Name}";
        _repo.MarkDirty();
    }
    private void Notes_Changed(object sender, TextChangedEventArgs e)
    {
        if (_suppress) return;
        _component.Notes = NotesBox.Text;
        _repo.MarkDirty();
    }
    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
