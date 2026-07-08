using System.Windows;

namespace AA.Views;

public partial class PromptWindow : Window
{
    public string Value => Tb.Text;
    public PromptWindow(string title, string prompt, string initial = "")
    {
        InitializeComponent();
        Title = title;
        LblTitle.Text = title;
        LblPrompt.Text = prompt;
        Tb.Text = initial;
        Tb.Focus();
        Tb.SelectAll();
    }
    private void Ok_Click(object sender, RoutedEventArgs e) { DialogResult = true; Close(); }
    private void Cancel_Click(object sender, RoutedEventArgs e) { DialogResult = false; Close(); }
}
