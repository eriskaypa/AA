using System;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;

namespace AA.Views;

public partial class DateCalculatorWindow : Window
{
    private bool _ready;

    public DateCalculatorWindow()
    {
        InitializeComponent();

        var today = DateTime.Today;
        FromDate.SelectedDate = today;
        ToDate.SelectedDate = today;
        BaseDate.SelectedDate = today;

        OpBox.ItemsSource = new[] { "Add", "Subtract" };
        OpBox.SelectedIndex = 0;
        UnitBox.ItemsSource = new[] { "Days", "Weeks", "Months", "Years" };
        UnitBox.SelectedIndex = 0;

        _ready = true;
        ComputeDiff();
        ComputeAdd();
    }

    private void Diff_Changed(object sender, RoutedEventArgs e) { if (_ready) ComputeDiff(); }
    private void Add_Changed(object sender, RoutedEventArgs e) { if (_ready) ComputeAdd(); }

    private void ComputeDiff()
    {
        if (FromDate.SelectedDate is not DateTime a || ToDate.SelectedDate is not DateTime b)
        {
            DiffResult.Text = "Pick both dates.";
            return;
        }
        a = a.Date; b = b.Date;
        int totalDays = (b - a).Days;
        bool inclusive = IncludeEnd.IsChecked == true;
        int shownDays = totalDays + (inclusive ? (totalDays >= 0 ? 1 : -1) : 0);

        int absDays = Math.Abs(totalDays);
        int weeks = absDays / 7, remDays = absDays % 7;

        var (s, e2) = a <= b ? (a, b) : (b, a);
        int years = e2.Year - s.Year;
        int months = e2.Month - s.Month;
        int days = e2.Day - s.Day;
        if (days < 0) { months--; var pm = e2.AddMonths(-1); days += DateTime.DaysInMonth(pm.Year, pm.Month); }
        if (months < 0) { years--; months += 12; }

        string dir = totalDays < 0 ? "  (To is before From)" : "";
        DiffResult.Text =
            $"Total: {shownDays:N0} day{(Math.Abs(shownDays) == 1 ? "" : "s")}{(inclusive ? " (inclusive)" : "")}{dir}\n" +
            $"≈ {weeks:N0} week{(weeks == 1 ? "" : "s")}, {remDays} day{(remDays == 1 ? "" : "s")}\n" +
            $"= {Plural(years, "year")}, {Plural(months, "month")}, {Plural(days, "day")}";
    }

    private void ComputeAdd()
    {
        if (BaseDate.SelectedDate is not DateTime d)
        {
            AddResult.Text = "Pick a date.";
            return;
        }
        if (!int.TryParse(AmountBox.Text, NumberStyles.Integer, CultureInfo.InvariantCulture, out var amt))
        {
            AddResult.Text = "Enter a whole number.";
            return;
        }
        bool subtract = (OpBox.SelectedItem as string) == "Subtract";
        int n = subtract ? -amt : amt;
        var unit = UnitBox.SelectedItem as string ?? "Days";
        DateTime r = unit switch
        {
            "Weeks" => d.AddDays(n * 7),
            "Months" => d.AddMonths(n),
            "Years" => d.AddYears(n),
            _ => d.AddDays(n),
        };
        var deltaDays = (r.Date - d.Date).Days;
        AddResult.Text =
            $"Result: {r:yyyy-MM-dd} ({r:dddd})\n" +
            $"({(deltaDays >= 0 ? "+" : "")}{deltaDays:N0} days from {d:yyyy-MM-dd})";
    }

    private static string Plural(int n, string word) => $"{n} {word}{(Math.Abs(n) == 1 ? "" : "s")}";

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
