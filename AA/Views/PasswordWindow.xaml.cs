using System.Windows;
using AA.Services;

namespace AA.Views;

public partial class PasswordWindow : Window
{
    public enum Mode { Unlock, SetNew, ChangeExisting }
    private readonly Mode _mode;
    public string Password { get; private set; } = "";

    public PasswordWindow(Mode mode)
    {
        InitializeComponent();
        _mode = mode;
        switch (mode)
        {
            case Mode.Unlock:
                LblTitle.Text = "Unlock";
                LblPrompt.Text = "Enter the app password to unlock locked containers:";
                Pb2.Visibility = Visibility.Collapsed;
                break;
            case Mode.SetNew:
                LblTitle.Text = "Set app password";
                LblPrompt.Text = "Pick a password (used to lock/unlock every container).\nConfirm it on the second line.";
                Pb2.Visibility = Visibility.Visible;
                break;
            case Mode.ChangeExisting:
                LblTitle.Text = "Change app password";
                LblPrompt.Text = "Enter the new password and confirm it on the second line.";
                Pb2.Visibility = Visibility.Visible;
                break;
        }
        Loaded += (_, _) => Pb1.Focus();
    }

    private void Ok_Click(object sender, RoutedEventArgs e)
    {
        var p1 = Pb1.Password;
        if (string.IsNullOrEmpty(p1)) { LblError.Text = "Password cannot be empty."; return; }
        if (_mode != Mode.Unlock)
        {
            if (p1.Length < 4) { LblError.Text = "Password must be at least 4 characters."; return; }
            if (p1 != Pb2.Password) { LblError.Text = "Passwords do not match."; return; }
        }
        else
        {
            if (!PasswordService.Verify(p1)) { LblError.Text = "Wrong password."; return; }
        }
        Password = p1;
        DialogResult = true;
        Close();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
}
