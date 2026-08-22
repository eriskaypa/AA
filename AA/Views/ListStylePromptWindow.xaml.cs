using System.Windows;

namespace AA.Views;

/// <summary>Asks whether a list should be exported bulleted or numbered.
///
/// Deliberately asked EVERY time, with bullets preselected. Numbering implies the items run in sequence,
/// which is a claim about the content — a saved list is just as often a set of things to check in any
/// order. Defaulting to numbers quietly asserts an order that may not exist, so the choice is always the
/// user's and never remembered.</summary>
public partial class ListStylePromptWindow : Window
{
    /// <summary>True when the user chose a numbered list.</summary>
    public bool Numbered { get; private set; }

    public ListStylePromptWindow(string? prompt = null)
    {
        InitializeComponent();
        if (!string.IsNullOrWhiteSpace(prompt)) PromptText.Text = prompt;
    }

    /// <summary>Show the chooser. Returns null if the user cancelled.</summary>
    public static bool? Ask(Window? owner, string? prompt = null)
    {
        var dlg = new ListStylePromptWindow(prompt) { Owner = owner };
        return dlg.ShowDialog() == true ? dlg.Numbered : null;
    }

    private void Ok_Click(object sender, RoutedEventArgs e)
    {
        Numbered = NumbersRadio.IsChecked == true;
        DialogResult = true;
    }
}
