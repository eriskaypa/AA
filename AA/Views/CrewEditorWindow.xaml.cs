using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using AA.Models;
using AA.Services;

namespace AA.Views;

/// <summary>Modal editor for every field of a <see cref="CrewMember"/> (dates via calendar pickers),
/// plus a "Checklist" tab with the shared comprehensive checklist builder. Detail edits are applied
/// on Save / discarded on Cancel; checklist edits save immediately (like every other builder).</summary>
public partial class CrewEditorWindow : Window
{
    private readonly CrewMember _m;
    private readonly List<Action> _apply = new();

    public CrewEditorWindow(CrewMember m, AppRepository repo, bool showChecklist = false)
    {
        InitializeComponent();
        _m = m;
        LblTitle.Text = $"Edit crew member — {(_m.FullName.Length > 0 ? _m.FullName : "(unnamed)")}";
        BuildForm();
        Builder.Bind(_m.Checklist, repo, _m.FullName, "Crew checklist item");
        ScheduleCtrl.Bind(_m, repo);
        if (showChecklist) Tabs.SelectedIndex = 1;
    }

    private void BuildForm()
    {
        Header("Identity");
        Text("First name", () => _m.FirstName, v => _m.FirstName = v);
        Text("Middle name", () => _m.MiddleName, v => _m.MiddleName = v);
        Text("Last name", () => _m.LastName, v => _m.LastName = v);
        Text("Employee ID", () => _m.EmployeeId, v => _m.EmployeeId = v);
        Text("Nationality", () => _m.Nationality, v => _m.Nationality = v);
        Date("Date of birth", () => _m.DateOfBirth, v => _m.DateOfBirth = v);
        Text("Place of birth", () => _m.PlaceOfBirth, v => _m.PlaceOfBirth = v);
        Text("Gender", () => _m.Gender, v => _m.Gender = v);

        Header("Employment & Sign-On / Sign-Off");
        Text("Rank", () => _m.Rank, v => _m.Rank = v);
        Text("Rank code", () => _m.RankCode, v => _m.RankCode = v);
        Text("Status (On/Off)", () => _m.SignedOnOff, v => _m.SignedOnOff = v);
        Text("Company", () => _m.Company, v => _m.Company = v);
        Text("Vessel", () => _m.Vessel, v => _m.Vessel = v);
        Date("Sign-on date", () => _m.SignOnDate, v => _m.SignOnDate = v);
        Text("Sign-on port", () => _m.SignOnPort, v => _m.SignOnPort = v);
        Date("Sign-off date  (contract)", () => _m.SignOffDate, v => _m.SignOffDate = v, emphasize: true);
        Text("Sign-off port", () => _m.SignOffPort, v => _m.SignOffPort = v);

        Header("Travel Documents");
        Text("Passport no.", () => _m.PassportNumber, v => _m.PassportNumber = v);
        Date("Passport issued", () => _m.PassportIssued, v => _m.PassportIssued = v);
        Date("Passport expiry", () => _m.PassportExpiry, v => _m.PassportExpiry = v);
        Text("Seaman's book no.", () => _m.SeamansBookNumber, v => _m.SeamansBookNumber = v);
        Date("Seaman's book issued", () => _m.SeamansBookIssued, v => _m.SeamansBookIssued = v);
        Date("Seaman's book expiry", () => _m.SeamansBookExpiry, v => _m.SeamansBookExpiry = v);

        Header("Certificates & Medical");
        Text("CoC number", () => _m.CocNumber, v => _m.CocNumber = v);
        Date("CoC issued", () => _m.CocIssue, v => _m.CocIssue = v);
        Date("CoC expiry", () => _m.CocExpiry, v => _m.CocExpiry = v);
        Date("Health cert. expiry", () => _m.HealthCertExpiry, v => _m.HealthCertExpiry = v);

        Header("Physical");
        Text("Height (cm)", () => _m.Height, v => _m.Height = v);
        Text("Eyes", () => _m.EyesColor, v => _m.EyesColor = v);
        Text("Hair", () => _m.HairColor, v => _m.HairColor = v);

        Header("Next of Kin");
        Text("First name", () => _m.NokFirstName, v => _m.NokFirstName = v);
        Text("Last name", () => _m.NokLastName, v => _m.NokLastName = v);
        Text("Relationship", () => _m.NokRelationship, v => _m.NokRelationship = v);
    }

    private void Header(string t) => FormHost.Children.Add(new TextBlock
    {
        Text = t, FontWeight = FontWeights.Bold, Foreground = (Brush)FindResource("Accent"),
        Margin = new Thickness(0, 12, 0, 4)
    });

    private void Text(string label, Func<string> get, Action<string> set)
    {
        var dock = new DockPanel { Margin = new Thickness(0, 2, 0, 2) };
        dock.Children.Add(new TextBlock { Text = label, Width = 170, VerticalAlignment = VerticalAlignment.Center });
        var tb = new TextBox { Text = get() };
        dock.Children.Add(tb);
        FormHost.Children.Add(dock);
        _apply.Add(() => set(tb.Text?.Trim() ?? ""));
    }

    private void Date(string label, Func<string> get, Action<string> set, bool emphasize = false)
    {
        var dock = new DockPanel { Margin = new Thickness(0, 2, 0, 2) };
        var lbl = new TextBlock { Text = label, Width = 170, VerticalAlignment = VerticalAlignment.Center };
        if (emphasize) { lbl.FontWeight = FontWeights.Bold; lbl.Foreground = (Brush)FindResource("Accent"); }
        dock.Children.Add(lbl);
        var raw = new TextBox { Width = 130, VerticalAlignment = VerticalAlignment.Center,
            ToolTip = "Free-text form of the date (kept in sync with the picker)." };
        DockPanel.SetDock(raw, Dock.Right);
        var dp = new DatePicker { SelectedDate = CrewMember.ParseDate(get()) };
        // Keep the two in sync: picking a date fills the text; the text is the source of truth on Save
        // (so unparseable legacy values survive untouched unless the user changes them).
        raw.Text = get();
        dp.SelectedDateChanged += (_, _) => { if (dp.SelectedDate is DateTime d) raw.Text = d.ToString("yyyy-MM-dd"); };
        dock.Children.Add(raw);
        dock.Children.Add(dp);
        FormHost.Children.Add(dock);
        _apply.Add(() =>
        {
            var text = raw.Text?.Trim() ?? "";
            // Normalise to yyyy-MM-dd when it parses; otherwise keep whatever the user typed.
            var parsed = CrewMember.ParseDate(text);
            set(parsed != null ? parsed.Value.ToString("yyyy-MM-dd") : text);
        });
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        foreach (var a in _apply) a();
        DialogResult = true;
        Close();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
}
