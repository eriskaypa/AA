using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using AA.Models;
using AA.Services;
using Microsoft.Win32;

namespace AA.Views;

/// <summary>Crew roster + info card. Imports COMPAS reports into crew cards and tracks contract
/// (sign-off) expiries.</summary>
public partial class CrewPage : UserControl
{
    private AppRepository? _repo;
    private CrewMember? _selected;
    private bool _expiringOnly;

    /// <summary>Contracts within this many days (or already past) are treated as "expiring".</summary>
    public const int WarnDays = 60;
    private const int CriticalDays = 30;

    // Contract-status colours.
    private static readonly Brush RedBrush    = Frozen("#FFD45050");
    private static readonly Brush OrangeBrush = Frozen("#FFE8890C");
    private static readonly Brush AmberBrush  = Frozen("#FFC9A227");
    private static readonly Brush GreenBrush  = Frozen("#FF2E9E5B");
    private static readonly Brush GrayBrush   = Frozen("#FF8A8A8A");

    private static SolidColorBrush Frozen(string hex)
    {
        var b = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
        b.Freeze();
        return b;
    }

    /// <summary>Raised after the roster changes (import/delete/clear) so the host can refresh the tab badge.</summary>
    public event Action? Changed;

    public CrewPage() { InitializeComponent(); }

    public void Init(AppRepository repo)
    {
        _repo = repo;
        _selected = null;
        Refresh();
    }

    /// <summary>Crew whose contract is overdue or within <see cref="WarnDays"/> days.</summary>
    public int ExpiringCount
    {
        get
        {
            if (_repo == null) return 0;
            var today = DateTime.Today;
            return _repo.Data.Crew.Count(c => c.DaysUntilSignOff(today) is int d && d <= WarnDays);
        }
    }

    /// <summary>Select a crew member in the roster (used when navigating in from the due-dates window).
    /// Clears any active filter/search so the member is guaranteed visible.</summary>
    public void SelectMember(CrewMember m)
    {
        if (_repo == null) return;
        // Drop filters so the target is present in the list, then rebuild and select by stable id.
        if (_expiringOnly) { _expiringOnly = false; ExpiringOnlyBtn.IsChecked = false; }
        if (!string.IsNullOrEmpty(SearchBox.Text)) SearchBox.Text = "";
        Refresh();
        if (Roster.ItemsSource is IEnumerable<CrewRow> rows)
        {
            var row = rows.FirstOrDefault(r => r.Member.Id == m.Id) ?? rows.FirstOrDefault(r => r.Member.Key == m.Key);
            if (row != null) { Roster.SelectedItem = row; Roster.ScrollIntoView(row); }
        }
    }

    // ---- Roster ----
    public void Refresh()
    {
        if (_repo == null) return;
        var today = DateTime.Today;
        var q = SearchBox.Text?.Trim() ?? "";
        // Capture selection before reassigning ItemsSource (which raises SelectionChanged and
        // would otherwise clear _selected before we can restore it).
        var keepKey = _selected?.Key;

        IEnumerable<CrewMember> crew = _repo.Data.Crew;
        if (!string.IsNullOrEmpty(q))
            crew = crew.Where(c =>
                c.FullName.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                c.Rank.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                c.Nationality.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                c.EmployeeId.Contains(q, StringComparison.OrdinalIgnoreCase));
        if (_expiringOnly)
            crew = crew.Where(c => c.DaysUntilSignOff(today) is int d && d <= WarnDays);

        // Soonest-expiring first (unknown dates sink to the bottom), then by name.
        var rows = crew
            .OrderBy(c => c.DaysUntilSignOff(today) ?? int.MaxValue)
            .ThenBy(c => c.FullName, StringComparer.OrdinalIgnoreCase)
            .Select(c =>
            {
                var (text, brush) = Expiry(c, today);
                var sub = string.Join("   ·   ", new[] { RankDisplay(c), c.Nationality, c.Vessel }
                    .Where(s => !string.IsNullOrWhiteSpace(s)));
                return new CrewRow
                {
                    Member = c,
                    Name = c.FullName.Length > 0 ? c.FullName : "(unnamed)",
                    Sub = sub + (c.HasFlags ? $"   ⚑ {c.Flags.Count}" : ""),
                    ExpiryText = text,
                    ExpiryBrush = brush,
                };
            })
            .ToList();

        Roster.ItemsSource = rows;

        // Restore selection by identity key (Roster_SelectionChanged keeps _selected / the card in sync).
        if (keepKey != null)
        {
            var keep = rows.FirstOrDefault(r => r.Member.Key == keepKey);
            if (keep != null) Roster.SelectedItem = keep;
        }
        if (Roster.SelectedItem == null && rows.Count > 0)
            Roster.SelectedItem = rows[0];

        int total = _repo.Data.Crew.Count;
        int expiring = ExpiringCount;
        RosterStatus.Text = total == 0
            ? "No crew yet — click “Import COMPAS...” to load a crew report."
            : $"{total} crew" + (expiring > 0 ? $"  ·  ⚠ {expiring} contract(s) expiring ≤{WarnDays}d" : "");
    }

    private static string RankDisplay(CrewMember c) =>
        string.IsNullOrWhiteSpace(c.RankCode) ? c.Rank : $"{c.Rank} ({c.RankCode})";

    /// <summary>Contract-expiry chip text + colour for a crew member.</summary>
    private static (string text, Brush brush) Expiry(CrewMember c, DateTime today)
    {
        var days = c.DaysUntilSignOff(today);
        if (days == null) return ("", GrayBrush);
        int d = days.Value;
        string date = c.SignOffDate;
        if (d < 0) return ($"⚠ Contract ended {-d}d ago  ({date})", RedBrush);
        if (d == 0) return ($"⚠ Signs off today  ({date})", RedBrush);
        if (d <= CriticalDays) return ($"⚠ Signs off in {d}d  ({date})", OrangeBrush);
        if (d <= WarnDays) return ($"Signs off in {d}d  ({date})", AmberBrush);
        return ($"Signs off in {d}d  ({date})", GreenBrush);
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e) => Refresh();

    private void ExpiringOnly_Click(object sender, RoutedEventArgs e)
    {
        _expiringOnly = ExpiringOnlyBtn.IsChecked == true;
        Refresh();
    }

    private void Roster_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        _selected = (Roster.SelectedItem as CrewRow)?.Member;
        CardHost.Content = _selected == null ? null : BuildCard(_selected);
    }

    // ---- Import ----
    private void Import_Click(object sender, RoutedEventArgs e) => ImportCompas();

    /// <summary>Pick a COMPAS .xlsx, convert every row into a crew card, and upsert into the roster
    /// (existing members are updated by employee id / name). Persisted with the rest of the data.</summary>
    public void ImportCompas()
    {
        if (_repo == null) return;
        var dlg = new OpenFileDialog
        {
            Title = "Select COMPAS crew report",
            Filter = "Excel workbook (*.xlsx)|*.xlsx|All files (*.*)|*.*"
        };
        if (dlg.ShowDialog() != true) return;

        try
        {
            Mouse.OverrideCursor = System.Windows.Input.Cursors.Wait;
            var rows = CompasReader.Read(dlg.FileName);
            var converter = new CrewConverter(System.IO.Path.GetFileName(dlg.FileName));
            var members = rows.Select(converter.Convert).ToList();

            int added = 0, updated = 0;
            foreach (var m in members)
            {
                var existing = _repo.Data.Crew.FirstOrDefault(c => c.Key == m.Key);
                if (existing != null)
                {
                    // Preserve the member's stable id and their personal checklist across re-import —
                    // the COMPAS file has neither, so a blind replace would wipe the checklist.
                    m.Id = existing.Id;
                    m.Checklist = existing.Checklist;
                    var idx = _repo.Data.Crew.IndexOf(existing);
                    _repo.Data.Crew[idx] = m;
                    updated++;
                }
                else { _repo.Data.Crew.Add(m); added++; }
            }
            _repo.LogAdded("Crew import", $"{added} added, {updated} updated", System.IO.Path.GetFileName(dlg.FileName));
            _repo.Save();
            Refresh();
            Changed?.Invoke();

            int flags = members.Sum(m => m.Flags.Count);
            RosterStatus.Text = $"Imported {members.Count} from {System.IO.Path.GetFileName(dlg.FileName)} " +
                                $"({added} new, {updated} updated) — {flags} review note(s).";
            // Surface any contracts that are already due/overdue right after import.
            CheckExpiries(interactive: false);
        }
        catch (Exception ex)
        {
            MessageBox.Show(Window.GetWindow(this),
                $"Could not import the COMPAS file:\n\n{ex.Message}",
                "Import failed", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally { Mouse.OverrideCursor = null; }
    }

    // ---- Contract-expiry tracking / notification ----
    private void CheckExpiries_Click(object sender, RoutedEventArgs e) => CheckExpiries(interactive: true);

    /// <summary>List crew whose contracts are overdue or due within <see cref="WarnDays"/> days.
    /// When <paramref name="interactive"/> is false, a "nothing due" result stays silent (used at
    /// startup and after import); when true it always reports.</summary>
    public void CheckExpiries(bool interactive)
    {
        if (_repo == null) return;
        var today = DateTime.Today;
        var due = _repo.Data.Crew
            .Select(c => (c, days: c.DaysUntilSignOff(today)))
            .Where(x => x.days is int d && d <= WarnDays)
            .OrderBy(x => x.days!.Value)
            .ToList();

        if (due.Count == 0)
        {
            if (interactive)
                MessageBox.Show(Window.GetWindow(this),
                    $"No crew contracts are overdue or due within {WarnDays} days.",
                    "Contract expiries", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        var lines = due.Select(x =>
        {
            int d = x.days!.Value;
            string when = d < 0 ? $"OVERDUE by {-d}d" : d == 0 ? "signs off TODAY" : $"in {d}d";
            return $"  •  {x.c.FullName}  ({RankDisplay(x.c)})  —  {x.c.SignOffDate}  [{when}]";
        });

        MessageBox.Show(Window.GetWindow(this),
            $"{due.Count} crew contract(s) overdue or due within {WarnDays} days:\n\n" +
            string.Join("\n", lines),
            "Contract expiries", MessageBoxButton.OK, MessageBoxImage.Warning);
    }

    // ---- Delete / clear ----
    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || _selected == null) return;
        if (MessageBox.Show(Window.GetWindow(this), $"Remove {_selected.FullName} from the roster?",
                "Confirm", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        _repo.LogRemoved("Crew", _selected.FullName);
        _repo.Data.Crew.Remove(_selected);
        _selected = null;
        _repo.Save();
        Refresh();
        Changed?.Invoke();
    }

    private void ClearAll_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || _repo.Data.Crew.Count == 0) return;
        if (MessageBox.Show(Window.GetWindow(this), "Remove ALL crew from the roster?",
                "Confirm clear", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        _repo.LogRemoved("Crew", $"all {_repo.Data.Crew.Count} member(s)");
        _repo.Data.Crew.Clear();
        _selected = null;
        _repo.Save();
        Refresh();
        Changed?.Invoke();
    }

    /// <summary>Open the modal editor for a crew member. The card itself is read-only, so this is the
    /// only way to change data — no field can be edited by accident.</summary>
    private void EditCrew(CrewMember m, bool showChecklist = false)
    {
        if (_repo == null) return;
        var w = new CrewEditorWindow(m, _repo, showChecklist) { Owner = Window.GetWindow(this) };
        bool saved = w.ShowDialog() == true;
        // Detail-field edits apply on Save only; the Checklist tab edits live. Persist either way so
        // a checklist change made before Cancel isn't left dangling, and rebuild the card so its
        // checklist summary reflects those live edits.
        if (saved) _repo.Save(); else _repo.FlushIfDirty();
        _selected = m;
        Refresh();               // recompute contract expiry + rebuild the card (incl. checklist summary)
        Changed?.Invoke();       // sign-off may have changed → refresh the tab badge
    }

    /// <summary>A summary of the crew member's checklist on the read-only card, with a button that opens
    /// the editor straight to the Checklist tab.</summary>
    private UIElement BuildChecklistSummary(CrewMember m)
    {
        var border = new Border
        {
            Background = (Brush)FindResource("PanelAlt"), BorderBrush = (Brush)FindResource("BorderB"),
            BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(4),
            Padding = new Thickness(10, 8, 10, 8), Margin = new Thickness(0, 0, 0, 10)
        };
        var dock = new DockPanel();
        var openBtn = new Button
        {
            Content = "🗒 Open checklist...", Padding = new Thickness(10, 4, 10, 4), VerticalAlignment = VerticalAlignment.Top,
            ToolTip = "Build this crew member's checklist — items with a due date show in the due-dates window and Calendar."
        };
        DockPanel.SetDock(openBtn, Dock.Right);
        openBtn.Click += (_, _) => EditCrew(m, showChecklist: true);
        dock.Children.Add(openBtn);

        int total = m.Checklist.Count;
        int done = m.Checklist.Count(s => s.Done);
        var next = m.Checklist.Where(s => !s.Done && s.Deadline != null).OrderBy(s => s.Deadline).FirstOrDefault();
        var sp = new StackPanel();
        sp.Children.Add(new TextBlock { Text = "✅  Checklist", FontWeight = FontWeights.Bold, Foreground = (Brush)FindResource("Accent") });
        string line = total == 0
            ? "No items yet — open to add tasks (each can have a due date)."
            : $"{total} item(s), {done} done"
              + (next != null ? $"   ·   next due {next.Deadline:yyyy-MM-dd} — {(next.Title.Length > 40 ? next.Title[..39] + "…" : next.Title)}" : "");
        sp.Children.Add(new TextBlock { Text = line, Foreground = GrayBrush, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 2, 0, 0) });
        dock.Children.Add(sp);
        border.Child = dock;
        return border;
    }

    // ---- Info card ----
    private UIElement BuildCard(CrewMember m)
    {
        var root = new StackPanel();
        var head = new DockPanel();
        var editBtn = new Button
        {
            Content = "✎ Edit...", Margin = new Thickness(8, 0, 0, 0), Padding = new Thickness(10, 4, 10, 4),
            VerticalAlignment = VerticalAlignment.Top,
            ToolTip = "Edit this crew member's details (including the sign-off / contract date)."
        };
        DockPanel.SetDock(editBtn, Dock.Right);
        editBtn.Click += (_, _) => EditCrew(m);
        head.Children.Add(editBtn);
        head.Children.Add(new TextBlock
        {
            Text = m.FullName.Length > 0 ? m.FullName : "(unnamed)",
            FontSize = 22, FontWeight = FontWeights.Bold, TextWrapping = TextWrapping.Wrap
        });
        root.Children.Add(head);
        var subtitle = string.Join("   ·   ", new[] { RankDisplay(m), m.Nationality, m.Vessel }
            .Where(s => !string.IsNullOrWhiteSpace(s)));
        if (subtitle.Length > 0)
            root.Children.Add(new TextBlock { Text = subtitle, Foreground = GrayBrush, Margin = new Thickness(0, 2, 0, 10), TextWrapping = TextWrapping.Wrap });

        root.Children.Add(BuildContractBanner(m));
        root.Children.Add(BuildChecklistSummary(m));

        root.Children.Add(Section("Identity", "🪪",
            ("First name", m.FirstName),
            ("Middle name", m.MiddleName),
            ("Last name", m.LastName),
            ("Employee ID", m.EmployeeId),
            ("Nationality", m.Nationality + (string.IsNullOrWhiteSpace(m.RawNationality) || m.RawNationality == m.Nationality ? "" : $"   (COMPAS: {m.RawNationality})")),
            ("Date of birth", m.DateOfBirth),
            ("Place of birth", m.PlaceOfBirth),
            ("Gender", m.Gender)));

        root.Children.Add(Section("Employment & Sign-On / Sign-Off", "⚓",
            ("Rank", RankDisplay(m)),
            ("User type", m.UserType),
            ("Status", m.SignedOnOff),
            ("Company", m.Company),
            ("Vessel", m.Vessel),
            ("Sign-on date", m.SignOnDate),
            ("Sign-on port", PortDisplay(m.SignOnPort, m.SignOnPortRaw)),
            ("Sign-off date", m.SignOffDate),
            ("Sign-off port", PortDisplay(m.SignOffPort, m.SignOffPortRaw))));

        root.Children.Add(Section("Travel Documents", "🛂",
            ("Passport no.", m.PassportNumber),
            ("Passport issued", m.PassportIssued),
            ("Passport expiry", m.PassportExpiry),
            ("Seaman's book no.", m.SeamansBookNumber),
            ("Seaman's book issued", m.SeamansBookIssued),
            ("Seaman's book expiry", m.SeamansBookExpiry)));

        root.Children.Add(Section("Certificates & Medical", "📜",
            ("CoC number", m.CocNumber),
            ("CoC issued", m.CocIssue),
            ("CoC expiry", m.CocExpiry),
            ("Health cert. expiry", m.HealthCertExpiry)));

        root.Children.Add(Section("Physical", "📏",
            ("Height (cm)", m.Height),
            ("Eyes", m.EyesColor),
            ("Hair", m.HairColor)));

        root.Children.Add(Section("Next of Kin", "👥",
            ("First name", m.NokFirstName),
            ("Last name", m.NokLastName),
            ("Relationship", m.NokRelationship)));

        if (m.HasFlags) root.Children.Add(BuildFlags(m));

        if (!string.IsNullOrWhiteSpace(m.ImportedAt) || !string.IsNullOrWhiteSpace(m.SourceFile))
            root.Children.Add(new TextBlock
            {
                Text = $"Imported {m.ImportedAt}" + (string.IsNullOrWhiteSpace(m.SourceFile) ? "" : $" from {m.SourceFile}"),
                Foreground = GrayBrush, FontSize = 11, Margin = new Thickness(0, 12, 0, 0), TextWrapping = TextWrapping.Wrap
            });

        return root;
    }

    private UIElement BuildContractBanner(CrewMember m)
    {
        var (text, brush) = Expiry(m, DateTime.Today);
        bool known = m.SignOffDateValue != null;
        var border = new Border
        {
            BorderBrush = known ? brush : GrayBrush,
            BorderThickness = new Thickness(0, 0, 0, 3),
            Background = (Brush)FindResource("PanelAlt"),
            Padding = new Thickness(12, 8, 12, 8),
            Margin = new Thickness(0, 0, 0, 12),
            CornerRadius = new CornerRadius(4)
        };
        var sp = new StackPanel();
        sp.Children.Add(new TextBlock { Text = "CONTRACT", FontSize = 11, FontWeight = FontWeights.Bold, Foreground = GrayBrush });
        sp.Children.Add(new TextBlock
        {
            Text = known ? text : "No sign-off date on file — contract expiry can't be tracked.",
            FontSize = 15, FontWeight = FontWeights.Bold, Foreground = known ? brush : GrayBrush,
            TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 2, 0, 0)
        });
        return border.Also(sp);
    }

    private UIElement BuildFlags(CrewMember m)
    {
        var border = new Border
        {
            BorderBrush = (Brush)FindResource("BorderB"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(4),
            Padding = new Thickness(10),
            Margin = new Thickness(0, 6, 0, 0)
        };
        var sp = new StackPanel();
        sp.Children.Add(new TextBlock { Text = $"⚑ Review notes ({m.Flags.Count})", FontWeight = FontWeights.Bold, Margin = new Thickness(0, 0, 0, 6) });
        foreach (var f in m.Flags)
        {
            var brush = f.Severity switch
            {
                CrewFlagSeverity.Error => RedBrush,
                CrewFlagSeverity.Warning => OrangeBrush,
                _ => GrayBrush
            };
            var row = new DockPanel { Margin = new Thickness(0, 1, 0, 1) };
            row.Children.Add(new TextBlock { Text = "●", Foreground = brush, Width = 16, VerticalAlignment = VerticalAlignment.Top });
            row.Children.Add(new TextBlock { Text = $"{f.Field}: {f.Message}", TextWrapping = TextWrapping.Wrap });
            sp.Children.Add(row);
        }
        return border.Also(sp);
    }

    private UIElement Section(string title, string glyph, params (string label, string value)[] fields)
    {
        var border = new Border
        {
            BorderBrush = (Brush)FindResource("BorderB"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(4),
            Padding = new Thickness(10),
            Margin = new Thickness(0, 0, 0, 8)
        };
        var sp = new StackPanel();
        sp.Children.Add(new TextBlock
        {
            Text = $"{glyph}  {title}",
            FontWeight = FontWeights.Bold, Foreground = (Brush)FindResource("Accent"),
            Margin = new Thickness(0, 0, 0, 6)
        });
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(170) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        int r = 0;
        foreach (var (label, value) in fields)
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var lbl = new TextBlock { Text = label, Foreground = GrayBrush, Margin = new Thickness(0, 1, 8, 1), TextWrapping = TextWrapping.Wrap };
            Grid.SetRow(lbl, r); Grid.SetColumn(lbl, 0); grid.Children.Add(lbl);
            var val = new TextBlock { Text = string.IsNullOrWhiteSpace(value) ? "—" : value, Margin = new Thickness(0, 1, 0, 1), TextWrapping = TextWrapping.Wrap };
            Grid.SetRow(val, r); Grid.SetColumn(val, 1); grid.Children.Add(val);
            r++;
        }
        sp.Children.Add(grid);
        return border.Also(sp);
    }

    private static string PortDisplay(string code, string raw)
    {
        if (string.IsNullOrWhiteSpace(code) && string.IsNullOrWhiteSpace(raw)) return "";
        if (string.IsNullOrWhiteSpace(raw) || raw == code) return code;
        return $"{code}   (COMPAS: {raw})";
    }
}

/// <summary>Roster row projection bound by the ListBox item template.</summary>
public sealed class CrewRow
{
    public CrewMember Member { get; init; } = null!;
    public string Name { get; init; } = "";
    public string Sub { get; init; } = "";
    public string ExpiryText { get; init; } = "";
    public Brush ExpiryBrush { get; init; } = Brushes.Gray;
}

/// <summary>Tiny fluent helper: set a Border's child and return the Border.</summary>
internal static class BorderExtensions
{
    public static Border Also(this Border b, UIElement child) { b.Child = child; return b; }
}
