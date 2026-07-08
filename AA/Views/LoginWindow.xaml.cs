using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace AA.Views;

public partial class LoginWindow : Window
{
    // Hardcoded credentials, as requested. NOTE: this is a basic gate, not real security —
    // the values live in the binary and the local data is not encrypted by this check.
    private const string ExpectedUser = "44233";
    private const string ExpectedPass = "redemption";

    public LoginWindow()
    {
        InitializeComponent();
        Loaded += (_, _) => UserBox.Focus();
    }

    private void PassBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) TryLogin();
    }

    private void Login_Click(object sender, RoutedEventArgs e) => TryLogin();

    private void TryLogin()
    {
        if (string.Equals(UserBox.Text?.Trim(), ExpectedUser, StringComparison.Ordinal) &&
            string.Equals(PassBox.Password, ExpectedPass, StringComparison.Ordinal))
        {
            DialogResult = true;
            Close();
        }
        else
        {
            ErrorText.Text = "Incorrect username or password.";
            PassBox.Clear();
            PassBox.Focus();
        }
    }

    private void Exit_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
}
