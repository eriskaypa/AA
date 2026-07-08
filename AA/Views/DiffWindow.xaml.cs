using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using AA.Services;

namespace AA.Views;

public partial class DiffWindow : Window
{
    public DiffWindow(string sourceName, string ageText, DataDiff.Result diff)
    {
        InitializeComponent();
        SourceText.Text = $"Importing from: {sourceName}";
        AgeText.Text = ageText;
        SummaryText.Text = diff.HasChanges
            ? $"This import will   ＋ add {diff.Added}     ～ change {diff.Changed}     － remove {diff.Removed}   item(s).  Expand a row to see details."
            : "No differences detected — the incoming data appears identical to your current data.";
        // Top-level rows expanded so the first level of detail shows immediately; deeper levels
        // stay collapsed until the user drills in.
        Tree.ItemsSource = diff.Roots.Select(r => new Row(r, expanded: true)).ToList();
    }

    private void Import_Click(object sender, RoutedEventArgs e) { DialogResult = true; Close(); }
    private void Cancel_Click(object sender, RoutedEventArgs e) { DialogResult = false; Close(); }

    private sealed class Row
    {
        public string Glyph { get; }
        public Brush Brush { get; }
        public string Text { get; }
        public bool IsExpanded { get; set; }
        public List<Row> Children { get; }

        public Row(DataDiff.Node n, bool expanded = false)
        {
            (Glyph, Brush) = n.Change switch
            {
                DataDiff.Change.Added => ("＋", new SolidColorBrush(Color.FromRgb(0x2E, 0x7D, 0x32))),
                DataDiff.Change.Removed => ("－", new SolidColorBrush(Color.FromRgb(0xC6, 0x28, 0x28))),
                _ => ("～", new SolidColorBrush(Color.FromRgb(0xEF, 0x6C, 0x00))),
            };
            Text = n.Text;
            IsExpanded = expanded;
            Children = n.Children.Select(c => new Row(c)).ToList();
        }
    }
}
