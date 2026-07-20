using System;
using System.Windows;

namespace AA.Views;

/// <summary>Small modal that asks for a single date. <see cref="SelectedDate"/> is the chosen date, or
/// null when the user pressed "Clear deadline" — both cases return <c>DialogResult == true</c>, so callers
/// distinguish "set to this date" from "clear it" purely by the value.</summary>
public partial class DatePromptWindow : Window
{
    public DateTime? SelectedDate { get; private set; }

    public DatePromptWindow(string title, string prompt, DateTime? initial = null)
    {
        InitializeComponent();
        Title = title;
        LblTitle.Text = title;
        LblPrompt.Text = prompt;
        Picker.SelectedDate = initial;
    }

    private void Ok_Click(object sender, RoutedEventArgs e)
    {
        if (Picker.SelectedDate is null)
        {
            MessageBox.Show(this, "Pick a date, or use \"Clear deadline\" to remove it.",
                "Set deadline", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        SelectedDate = Picker.SelectedDate.Value.Date;
        DialogResult = true;
    }

    private void Clear_Click(object sender, RoutedEventArgs e)
    {
        SelectedDate = null;
        DialogResult = true;
    }

    private void Cancel_Click(object sender, RoutedEventArgs e) => DialogResult = false;
}
