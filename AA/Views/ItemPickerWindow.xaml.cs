using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;

namespace AA.Views;

public class PickerItem
{
    public string Display { get; set; } = "";
    public object Tag { get; set; } = null!;
}

public partial class ItemPickerWindow : Window
{
    private readonly List<PickerItem> _all;
    public List<object> SelectedTags { get; private set; } = new();

    public ItemPickerWindow(string prompt, IEnumerable<PickerItem> items, IEnumerable<object>? preselect = null, bool singleSelect = false)
    {
        InitializeComponent();
        LblPrompt.Text = prompt;
        _all = items.ToList();
        Lb.SelectionMode = singleSelect ? SelectionMode.Single : SelectionMode.Multiple;
        Lb.ItemsSource = _all;
        if (preselect != null)
        {
            var set = preselect.ToHashSet();
            var matches = _all.Where(it => set.Contains(it.Tag)).ToList();
            if (singleSelect)
            {
                // SelectedItems is read-only in Single mode — using SelectedItem instead avoids
                // an InvalidOperationException when preselecting (e.g. AssignGroup_Click).
                Lb.SelectedItem = matches.FirstOrDefault();
            }
            else
            {
                foreach (var it in matches) Lb.SelectedItems.Add(it);
            }
        }
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        var q = SearchBox.Text?.Trim() ?? "";
        Lb.ItemsSource = string.IsNullOrEmpty(q) ? _all :
            _all.Where(i => i.Display.Contains(q, System.StringComparison.OrdinalIgnoreCase)).ToList();
    }
    private void Ok_Click(object sender, RoutedEventArgs e)
    {
        SelectedTags = Lb.SelectedItems.Cast<PickerItem>().Select(p => p.Tag).ToList();
        DialogResult = true; Close();
    }
    private void Cancel_Click(object sender, RoutedEventArgs e) { DialogResult = false; Close(); }
}
