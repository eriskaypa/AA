using System.Windows;

namespace AA.Views;

/// <summary>Dialog to set or change a per-item password lock (password + confirm + optional hint).</summary>
public partial class ItemLockWindow : Window
{
    public enum Mode { Set, Change }

    public string Password { get; private set; } = "";
    public string Hint { get; private set; } = "";

    public ItemLockWindow(Mode mode, string itemName, string? existingHint)
    {
        InitializeComponent();
        HintBox.Text = existingHint ?? "";
        if (mode == Mode.Set)
        {
            LblTitle.Text = $"Lock “{itemName}”";
            LblPrompt.Text = "Set a password for this entry. It will be required to view or edit the entry. " +
                             "The app master password always unlocks it.";
        }
        else
        {
            LblTitle.Text = $"Change lock on “{itemName}”";
            LblPrompt.Text = "Enter a new password (and, optionally, a new hint). The master password always unlocks it.";
        }
        Loaded += (_, _) => Pb1.Focus();
    }

    private void Ok_Click(object sender, RoutedEventArgs e)
    {
        var p1 = Pb1.Password;
        if (string.IsNullOrEmpty(p1)) { LblError.Text = "Password cannot be empty."; return; }
        if (p1.Length < 4) { LblError.Text = "Password must be at least 4 characters."; return; }
        if (p1 != Pb2.Password) { LblError.Text = "Passwords do not match."; return; }
        Password = p1;
        Hint = HintBox.Text?.Trim() ?? "";
        DialogResult = true;
        Close();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
}
