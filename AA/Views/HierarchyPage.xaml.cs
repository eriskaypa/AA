using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using AA.Models;
using AA.Services;

namespace AA.Views;

public partial class HierarchyPage : UserControl
{
    private AppRepository? _repo;
    private ItemKind _kind;
    private HierarchyItem? _selected;
    private bool _suppress;

    /// <summary>Set by the host so relationship / backlink rows can jump to another item (any kind).</summary>
    public Action<HierarchyItem>? Navigate { get; set; }

    public HierarchyPage() { InitializeComponent(); }

    public Guid? SelectedItemId => _selected?.Id;

    public void FlushPendingEditors() => ContainerCtrl.FlushPending();

    public void SelectItemById(Guid id)
    {
        if (ItemsList.ItemsSource is ListCollectionView lcv)
        {
            foreach (Row r in lcv.OfType<Row>())
            {
                if (r.Item != null && r.Item.Id == id) { ItemsList.SelectedItem = r; return; }
            }
        }
        var items = (ItemsList.ItemsSource as IEnumerable<HierarchyItem>);
        var match = items?.FirstOrDefault(i => i.Id == id);
        if (match != null) ItemsList.SelectedItem = match;
    }

    public void Init(AppRepository repo, ItemKind kind)
    {
        _repo = repo;
        _kind = kind;
        PageTitle.Text = kind switch
        {
            ItemKind.Equipment => "Equipment/Area",
            ItemKind.Task => "Tasks",
            ItemKind.Procedure => "Procedures",
            ItemKind.Vessel => "Vessels",
            _ => "Items"
        };
        SpecificsTab.Header = kind switch
        {
            ItemKind.Equipment => "Components / Procedures / Tasks",
            ItemKind.Task => "Schedule & Subtasks",
            ItemKind.Procedure => "Checklist",
            _ => "Specifics"
        };
        SpecificsTab.Visibility = kind == ItemKind.Vessel ? Visibility.Collapsed : Visibility.Visible;
        QuickCardsTab.Visibility = kind == ItemKind.Vessel ? Visibility.Visible : Visibility.Collapsed;
        WorkOrdersTab.Visibility = kind == ItemKind.Vessel ? Visibility.Visible : Visibility.Collapsed;
        // Non-vessel pages: the Quick Cards / Work Orders tabs are collapsed, so front the Container.
        if (kind != ItemKind.Vessel) DetailsTabs.SelectedItem = ContainerTab;
        SortAZBtn.IsChecked = _repo.Data.Ui.SortAZ.TryGetValue(kind.ToString(), out var s) && s;
        RefreshList();
    }

    private System.Collections.IList Source() => _kind switch
    {
        ItemKind.Equipment => (System.Collections.IList)_repo!.Data.Equipment,
        ItemKind.Task => _repo!.Data.Tasks,
        ItemKind.Procedure => _repo!.Data.Procedures,
        ItemKind.Vessel => _repo!.Data.Vessels,
        _ => Array.Empty<object>()
    };

    /// <summary>Lightweight row that binds Group name for CollectionView grouping while
    /// keeping the underlying HierarchyItem reachable. Item may be null for "empty group"
    /// placeholders so freshly-created groups (with no items yet) still render a header.</summary>
    private sealed class Row : System.ComponentModel.INotifyPropertyChanged
    {
        public HierarchyItem? Item { get; init; }
        public bool IsPlaceholder => Item == null;
        public string Name => IsPlaceholder ? "  (empty \u2014 right-click an item to assign)" : Item!.Name;
        public string GroupKey { get; init; } = "";
        public override string ToString() => Name;

        public event System.ComponentModel.PropertyChangedEventHandler? PropertyChanged;
        /// <summary>Raise PropertyChanged for Name so the bound ListBoxItem text refreshes
        /// without rebinding the entire ItemsSource (which would drop selection/focus).</summary>
        public void NotifyNameChanged() =>
            PropertyChanged?.Invoke(this, new System.ComponentModel.PropertyChangedEventArgs(nameof(Name)));
    }

    private void RefreshList()
    {
        if (_repo == null) return;
        var q = SearchBox.Text?.Trim() ?? "";
        var items = Source().Cast<HierarchyItem>();
        if (!string.IsNullOrEmpty(q))
            items = items.Where(i => i.Name.Contains(q, StringComparison.OrdinalIgnoreCase));

        var groups = _repo.GroupsFor(_kind).ToList();
        var groupNames = groups.ToDictionary(g => g.Id, g => g.Name);
        var rows = items.Select(i => new Row
        {
            Item = i,
            GroupKey = i.GroupId.HasValue && groupNames.TryGetValue(i.GroupId.Value, out var gn) ? gn : "Ungrouped"
        }).ToList();

        // Add a placeholder row for every group that currently has zero items so the header
        // is still visible — otherwise CollectionView hides empty groups and "Create group"
        // appears to do nothing.
        var populated = rows.Select(r => r.GroupKey).ToHashSet();
        foreach (var g in groups)
            if (!populated.Contains(g.Name))
                rows.Add(new Row { Item = null, GroupKey = g.Name });

        var view = new ListCollectionView(rows);
        view.GroupDescriptions.Add(new PropertyGroupDescription(nameof(Row.GroupKey)));

        // Always order groups: real groups alphabetically, "Ungrouped" last for clarity.
        // Within a group, placeholders sink to the bottom so the (empty) hint never displaces real items.
        view.CustomSort = Comparer<object>.Create((a, b) =>
        {
            var ra = (Row)a; var rb = (Row)b;
            int gc = string.Compare(GroupSortKey(ra.GroupKey), GroupSortKey(rb.GroupKey), StringComparison.OrdinalIgnoreCase);
            if (gc != 0) return gc;
            if (ra.IsPlaceholder != rb.IsPlaceholder) return ra.IsPlaceholder ? 1 : -1;
            return SortAZBtn.IsChecked == true
                ? string.Compare(ra.Name, rb.Name, StringComparison.OrdinalIgnoreCase)
                : 0; // preserve insertion order within group
        });

        ItemsList.ItemsSource = view;
        // Row.Name is bound via the ListBox.ItemTemplate (a wrapping TextBlock), so the
        // sidebar wraps long task/item names to the panel width instead of clipping.
    }

    private static string GroupSortKey(string g) => g == "Ungrouped" ? "\uFFFF" + g : g;

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e) => RefreshList();

    private void SortAZ_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null) return;
        _repo.Data.Ui.SortAZ[_kind.ToString()] = SortAZBtn.IsChecked == true;
        _repo.MarkDirty();
        RefreshList();
    }

    private void NewGroup_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null) return;
        var p = new PromptWindow("New group", "Name:") { Owner = Window.GetWindow(this) };
        if (p.ShowDialog() == true && !string.IsNullOrWhiteSpace(p.Value))
        {
            var g = _repo.CreateGroup(_kind, p.Value);
            _repo.Save();
            RefreshList();
            // Surface a confirmation so the user sees the new group appear in the sidebar.
            if (Window.GetWindow(this)?.FindName("StatusBlock") is TextBlock sb)
                sb.Text = $"Group '{g.Name}' created. Right-click an item and choose 'Move to group...' to fill it.";
        }
    }

    private void UngroupItem_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null) return;
        var picks = SelectedHierarchyItems();
        if (picks.Count == 0) return;
        var changed = 0;
        foreach (var item in picks)
        {
            if (item.GroupId == null) continue;
            item.GroupId = null;
            changed++;
        }
        if (changed == 0) return;
        _repo.Save();
        var keepIds = picks.Select(p => p.Id).ToList();
        RefreshList();
        SelectItemsByIds(keepIds);
    }

    // ---- Group expand/collapse state (per page kind, persisted in Ui.GroupExpanded) ----

    private string GroupKey(object? name) => $"{_kind}|{name as string ?? ""}";

    private void GroupExpander_Loaded(object sender, RoutedEventArgs e)
    {
        if (_repo == null || sender is not Expander ex) return;
        var key = GroupKey(ex.Tag);
        if (_repo.Data.Ui.GroupExpanded.TryGetValue(key, out var open))
            ex.IsExpanded = open;
        // else: leave default IsExpanded="True"
    }

    private void GroupExpander_Expanded(object sender, RoutedEventArgs e) => PersistGroupState(sender, true);
    private void GroupExpander_Collapsed(object sender, RoutedEventArgs e) => PersistGroupState(sender, false);

    private void PersistGroupState(object sender, bool expanded)
    {
        if (_repo == null || sender is not Expander ex) return;
        // Tag is bound to {Binding Name} on the CollectionViewGroup, but during template
        // teardown this can be null — guard so we don't write a stray "" entry.
        var name = ex.Tag as string;
        if (string.IsNullOrEmpty(name)) return;
        var key = GroupKey(name);
        if (_repo.Data.Ui.GroupExpanded.TryGetValue(key, out var existing) && existing == expanded) return;
        _repo.Data.Ui.GroupExpanded[key] = expanded;
        _repo.MarkDirty();
    }

    private void AssignGroup_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null) return;
        var picks = SelectedHierarchyItems();
        if (picks.Count == 0) return;

        var groups = _repo.GroupsFor(_kind).ToList();
        var items = new List<PickerItem>
        {
            new() { Display = "(Ungrouped)", Tag = (object)Guid.Empty }
        };
        items.AddRange(groups.Select(g => new PickerItem { Display = g.Name, Tag = (object)g.Id }));

        // Preselect the common group if every picked item shares one; otherwise leave blank
        // so the user sees "no current group in common".
        object[] current;
        var distinctGroups = picks.Select(p => p.GroupId ?? Guid.Empty).Distinct().ToList();
        current = distinctGroups.Count == 1 ? new object[] { distinctGroups[0] } : Array.Empty<object>();

        var title = picks.Count == 1
            ? $"Move '{picks[0].Name}' to group"
            : $"Move {picks.Count} items to group";
        var dlg = new ItemPickerWindow(title, items, current, singleSelect: true)
        { Owner = Window.GetWindow(this) };
        if (dlg.ShowDialog() != true) return;

        var pick = dlg.SelectedTags.Cast<Guid>().FirstOrDefault();
        Guid? newGid = pick == Guid.Empty ? null : pick;
        foreach (var item in picks) item.GroupId = newGid;
        _repo.Save();
        var keepIds = picks.Select(p => p.Id).ToList();
        RefreshList();
        SelectItemsByIds(keepIds);
    }

    /// <summary>All currently-selected real items (skipping the empty-group placeholder rows).</summary>
    private List<HierarchyItem> SelectedHierarchyItems() =>
        ItemsList.SelectedItems
            .Cast<object>()
            .Select(o => (o as Row)?.Item ?? o as HierarchyItem)
            .Where(x => x != null)
            .Cast<HierarchyItem>()
            .ToList();

    private void SelectItemsByIds(IList<Guid> ids)
    {
        if (ItemsList.ItemsSource is not System.Collections.IEnumerable src) return;
        ItemsList.SelectedItems.Clear();
        var idSet = ids.ToHashSet();
        object? first = null;
        foreach (var o in src)
        {
            var item = (o as Row)?.Item ?? o as HierarchyItem;
            if (item != null && idSet.Contains(item.Id))
            {
                ItemsList.SelectedItems.Add(o);
                first ??= o;
            }
        }
        if (first != null) ItemsList.ScrollIntoView(first);
    }

    private void RenameGroup_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null) return;
        var groups = _repo.GroupsFor(_kind).ToList();
        if (groups.Count == 0)
        {
            MessageBox.Show("No groups to rename in this tab yet.", "Rename group", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var dlg = new ItemPickerWindow("Pick a group to rename",
            groups.Select(g => new PickerItem { Display = g.Name, Tag = (object)g.Id }), singleSelect: true)
        { Owner = Window.GetWindow(this) };
        if (dlg.ShowDialog() != true) return;
        var gid = dlg.SelectedTags.Cast<Guid>().FirstOrDefault();
        var grp = groups.FirstOrDefault(g => g.Id == gid);
        if (grp == null) return;
        var p = new PromptWindow("Rename group", "New name:", grp.Name) { Owner = Window.GetWindow(this) };
        if (p.ShowDialog() == true && !string.IsNullOrWhiteSpace(p.Value))
        {
            _repo.RenameGroup(grp, p.Value);
            _repo.Save();
            RefreshList();
        }
    }

    private void DeleteGroup_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null) return;
        var groups = _repo.GroupsFor(_kind).ToList();
        if (groups.Count == 0) return;
        var dlg = new ItemPickerWindow("Pick a group to delete (items inside become ungrouped)",
            groups.Select(g => new PickerItem { Display = g.Name, Tag = (object)g.Id }), singleSelect: true)
        { Owner = Window.GetWindow(this) };
        if (dlg.ShowDialog() != true) return;
        var gid = dlg.SelectedTags.Cast<Guid>().FirstOrDefault();
        var grp = groups.FirstOrDefault(g => g.Id == gid);
        if (grp == null) return;
        if (MessageBox.Show($"Delete group '{grp.Name}'?", "Confirm", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        _repo.DeleteGroup(grp);
        _repo.Save();
        RefreshList();
    }

    private void New_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null) return;
        HierarchyItem item = _kind switch
        {
            ItemKind.Equipment => new Equipment { Name = "New Equipment/Area" },
            ItemKind.Task => new TaskItem { Name = "New Task" },
            ItemKind.Procedure => new Procedure { Name = "New Procedure" },
            ItemKind.Vessel => new Vessel { Name = "New Vessel" },
            _ => throw new InvalidOperationException()
        };
        switch (item)
        {
            case Equipment eq: _repo.Data.Equipment.Add(eq); break;
            case TaskItem t: _repo.Data.Tasks.Add(t); break;
            case Procedure p: _repo.Data.Procedures.Add(p); break;
            case Vessel v: _repo.Data.Vessels.Add(v); break;
        }
        _repo.LogAdded(AppRepository.KindLabel(item.Kind), item.Name);
        _repo.Save();
        RefreshList();
        // Find the newly-added item by id and select it.
        SelectItemById(item.Id);
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || _selected == null) return;
        if (ItemLockService.IsGated(_selected))
        {
            MessageBox.Show("Unlock this entry before deleting it.", "Locked",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (MessageBox.Show($"Delete '{_selected.Name}'?", "Confirm", MessageBoxButton.YesNo) != MessageBoxResult.Yes) return;
        _repo.LogRemoved(AppRepository.KindLabel(_selected.Kind), _selected.Name);
        switch (_selected)
        {
            case Equipment eq: _repo.Data.Equipment.Remove(eq); break;
            case TaskItem t: _repo.Data.Tasks.Remove(t); break;
            case Procedure p: _repo.Data.Procedures.Remove(p); break;
            case Vessel v: _repo.Data.Vessels.Remove(v); break;
        }
        // Remove dangling references (two-way relations AND one-way procedure/task/equipment links).
        _repo.PurgeReferences(_selected.Id);
        _repo.Save();
        _selected = null;
        DetailsRoot.IsEnabled = false;
        RefreshList();
    }

    private void ItemsList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        // Persist any in-flight rich-text edits before switching items.
        ContainerCtrl.FlushPending();
        _selected = (ItemsList.SelectedItem as Row)?.Item ?? ItemsList.SelectedItem as HierarchyItem;
        DetailsRoot.IsEnabled = _selected != null;
        if (_selected == null)
        {
            LockOverlay.Visibility = Visibility.Collapsed;
            DetailsTabs.Visibility = Visibility.Visible;
            HeaderBar.Visibility = Visibility.Visible;
            LockBtn.Visibility = Visibility.Collapsed;
            return;
        }
        _suppress = true;
        NameBox.Text = _selected.Name;
        DescBox.Text = _selected.Description;
        TagsBox.Text = string.Join(", ", _selected.Tags);
        _suppress = false;
        ContainerCtrl.Load(_selected.Container, _repo);
        RefreshRelList();
        BuildSpecifics();

        // Vessels open on their Quick Cards screen first.
        if (_selected is Vessel v)
        {
            QuickCardsCtrl.Load(v, _repo!);
            ShipJobsCtrl.Load(v, _repo!);
            DetailsTabs.SelectedItem = QuickCardsTab;
        }

        // Show / hide the password-lock gate for the newly-selected item.
        ApplyLockGate();
    }

    // ---- Per-item password lock ----

    /// <summary>Re-apply the lock gate to the currently-selected item (used by Tools ▸ Lock now),
    /// so a just-relocked entry shows its padlock at once without needing to be reselected.</summary>
    public void RelockCurrent()
    {
        if (_selected == null) return;
        ContainerCtrl.FlushPending();
        // Refresh the container so its own (text-level) lock state re-renders when the entry
        // itself isn't gated; a gated entry hides the container behind the padlock anyway.
        if (_repo != null && !ItemLockService.IsGated(_selected))
            ContainerCtrl.Load(_selected.Container, _repo);
        ApplyLockGate();
    }

    /// <summary>Show the unlock overlay (and hide the detail tabs) when the selected item is
    /// password-locked and hasn't been unlocked in this session.</summary>
    private void ApplyLockGate()
    {
        bool gated = _selected != null && ItemLockService.IsGated(_selected);
        LockOverlay.Visibility = gated ? Visibility.Visible : Visibility.Collapsed;
        DetailsTabs.Visibility = gated ? Visibility.Hidden : Visibility.Visible;
        // Hide the Name/Description header too, so a gated entry exposes and lets you edit nothing
        // until it's unlocked (the overlay alone only covers the tabs below the header).
        HeaderBar.Visibility = gated ? Visibility.Collapsed : Visibility.Visible;
        UpdateLockButton();
        if (gated)
        {
            LockMsg.Text = $"This {KindWord()} is locked.";
            UnlockPb.Password = "";
            UnlockError.Text = "";
            LockHintText.Text = "";
            LockHintText.Visibility = Visibility.Collapsed;
            Dispatcher.BeginInvoke(new Action(() => UnlockPb.Focus()), System.Windows.Threading.DispatcherPriority.Input);
        }
    }

    private void UpdateLockButton()
    {
        if (_selected == null) { LockBtn.Visibility = Visibility.Collapsed; return; }
        bool gated = ItemLockService.IsGated(_selected);
        // While gated, the overlay handles unlocking; hide the manage button until unlocked.
        LockBtn.Visibility = gated ? Visibility.Collapsed : Visibility.Visible;
        LockBtn.Content = _selected.IsLockProtected ? "🔓 Locked" : "🔒 Lock";
        LockBtn.ToolTip = _selected.IsLockProtected
            ? "This entry is password-protected. Click to change the password/hint or remove the lock."
            : "Password-protect this entry (with an optional hint). The master password always unlocks.";
    }

    private string KindWord() => _kind switch
    {
        ItemKind.Equipment => "equipment/area",
        ItemKind.Task => "task",
        ItemKind.Procedure => "procedure",
        ItemKind.Vessel => "vessel",
        _ => "entry"
    };

    private void LockBtn_Click(object sender, RoutedEventArgs e)
    {
        if (_selected == null || _repo == null) return;
        if (!_selected.IsLockProtected)
        {
            var w = new ItemLockWindow(ItemLockWindow.Mode.Set, _selected.Name, null) { Owner = Window.GetWindow(this) };
            if (w.ShowDialog() != true) return;
            ItemLockService.Protect(_selected, w.Password, w.Hint);
            _repo.Save();
            StatusText($"'{_selected.Name}' is now locked.");
        }
        else
        {
            var choice = MessageBox.Show(Window.GetWindow(this),
                "This entry is locked.\n\nYes  = Change the password / hint\nNo   = Remove the lock\nCancel = keep it as is",
                "Manage lock", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
            if (choice == MessageBoxResult.Yes)
            {
                var w = new ItemLockWindow(ItemLockWindow.Mode.Change, _selected.Name, _selected.LockHint) { Owner = Window.GetWindow(this) };
                if (w.ShowDialog() != true) return;
                ItemLockService.Protect(_selected, w.Password, w.Hint);
                _repo.Save();
                StatusText("Lock updated.");
            }
            else if (choice == MessageBoxResult.No)
            {
                ItemLockService.RemoveProtection(_selected);
                _repo.Save();
                StatusText("Lock removed.");
            }
            else return;
        }
        ApplyLockGate();
    }

    private void Unlock_Click(object sender, RoutedEventArgs e) => TryUnlockSelected();

    private void UnlockPb_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) { TryUnlockSelected(); e.Handled = true; }
    }

    private void TryUnlockSelected()
    {
        if (_selected == null) return;
        if (ItemLockService.TryUnlock(_selected, UnlockPb.Password))
        {
            UnlockPb.Password = "";
            ApplyLockGate();
            StatusText($"'{_selected.Name}' unlocked for this session.");
        }
        else UnlockError.Text = "Wrong password. Use the entry's password or the master password (“redemption”).";
    }

    private void ShowHint_Click(object sender, RoutedEventArgs e)
    {
        if (_selected == null) return;
        LockHintText.Text = string.IsNullOrWhiteSpace(_selected.LockHint)
            ? "(No hint was set.)"
            : $"Hint: {_selected.LockHint}";
        LockHintText.Visibility = Visibility.Visible;
    }

    private void StatusText(string msg)
    {
        if (Window.GetWindow(this)?.FindName("StatusBlock") is TextBlock sb) sb.Text = msg;
    }

    private void NameBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (_suppress || _selected == null) return;
        _selected.Name = NameBox.Text;
        _repo?.MarkDirty();
        // Update only the visible row text in place. Calling RefreshList() here
        // would rebuild the ListCollectionView, drop ListBox selection, and steal
        // focus from NameBox after a single keystroke. A full refresh (re-sort,
        // group recalc) is deferred until the user finishes editing (LostFocus).
        if (ItemsList.SelectedItem is Row row) row.NotifyNameChanged();
    }

    private void NameBox_LostFocus(object sender, RoutedEventArgs e)
    {
        if (_suppress || _selected == null || _repo == null) return;
        // Now safe to re-sort/regroup; preserve the selection by id.
        var id = _selected.Id;
        RefreshList();
        SelectItemById(id);
    }

    private void NameBox_KeyDown(object sender, KeyEventArgs e)
    {
        // Pressing Enter commits the rename: re-sort the sidebar without leaving the field.
        if (e.Key == Key.Enter && _selected != null && _repo != null)
        {
            var id = _selected.Id;
            RefreshList();
            SelectItemById(id);
            e.Handled = true;
        }
    }
    private void DescBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (_suppress || _selected == null) return;
        _selected.Description = DescBox.Text;
        _repo?.MarkDirty();
    }

    private void TagsBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (_suppress || _selected == null || _repo == null) return;
        _selected.Tags.Clear();
        foreach (var t in ParseTags(TagsBox.Text)) _selected.Tags.Add(t);
        _repo.MarkDirty();
    }

    private void TagsBox_LostFocus(object sender, RoutedEventArgs e)
    {
        if (_selected == null) return;
        // Normalise the displayed text to the parsed tags.
        _suppress = true; TagsBox.Text = string.Join(", ", _selected.Tags); _suppress = false;
    }

    private static IEnumerable<string> ParseTags(string? s) =>
        (s ?? "").Split(new[] { ',', ';', '\n', '\r', '\t', ' ' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(t => t.TrimStart('#'))
            .Where(t => t.Length > 0)
            .Distinct(StringComparer.OrdinalIgnoreCase);

    private void RelList_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (RelList.SelectedItem is PickerItem pi && pi.Tag is HierarchyItem hi) Navigate?.Invoke(hi);
    }
    private void BackRef_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (BackRefList.SelectedItem is PickerItem pi && pi.Tag is HierarchyItem hi) Navigate?.Invoke(hi);
    }

    // ---- Export PDF ----
    private void ExportPdf_Click(object sender, RoutedEventArgs e)
    {
        if (_selected == null || _repo == null) return;
        // Don't let a PDF export leak the contents of a still-locked entry.
        if (ItemLockService.IsGated(_selected))
        {
            MessageBox.Show("Unlock this entry before exporting it to PDF.", "Locked",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        // Flush in-flight edits so the PDF reflects the latest text.
        ContainerCtrl.FlushPending();
        _repo.FlushIfDirty();

        var safe = string.Concat((_selected.Name ?? "item").Select(ch => System.IO.Path.GetInvalidFileNameChars().Contains(ch) ? '_' : ch));
        var dlg = new Microsoft.Win32.SaveFileDialog
        {
            Title = "Export to PDF",
            Filter = "PDF document (*.pdf)|*.pdf",
            FileName = $"{_selected.Kind}-{safe}.pdf",
            DefaultExt = ".pdf",
            AddExtension = true
        };
        if (dlg.ShowDialog(Window.GetWindow(this)) != true) return;

        try
        {
            Mouse.OverrideCursor = System.Windows.Input.Cursors.Wait;
            PdfExporter.Export(_selected, _repo, dlg.FileName);
        }
        catch (Exception ex)
        {
            MessageBox.Show("Failed to export PDF:\n" + ex.Message, "Export error", MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }
        finally
        {
            Mouse.OverrideCursor = null;
        }

        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(dlg.FileName) { UseShellExecute = true }); }
        catch { /* user can open it manually */ }
    }

    // ---- Relationships ----
    private void RefreshRelList()
    {
        if (_selected == null || _repo == null) { RelList.ItemsSource = null; BackRefList.ItemsSource = null; return; }
        RelList.ItemsSource = _repo.RelatedItems(_selected)
            .Select(r => new PickerItem { Display = $"[{r.Kind}] {r.Name}", Tag = r }).ToList();
        BackRefList.ItemsSource = _repo.ReferencedBy(_selected)
            .Select(r => new PickerItem { Display = $"[{r.Kind}] {r.Name}", Tag = r }).ToList();
    }
    private void AddRel_Click(object sender, RoutedEventArgs e)
    {
        if (_selected == null || _repo == null) return;
        // Order candidates by tab (Equipment, Tasks, Procedures, Vessels), then by name.
        static int KindOrder(ItemKind k) => k switch
        {
            ItemKind.Equipment => 0,
            ItemKind.Task => 1,
            ItemKind.Procedure => 2,
            ItemKind.Vessel => 3,
            _ => 99
        };
        var candidates = _repo.AllItems().Where(i => i.Id != _selected.Id)
            .OrderBy(i => KindOrder(i.Kind))
            .ThenBy(i => i.Name, StringComparer.OrdinalIgnoreCase)
            .Select(i => new PickerItem { Display = $"[{i.Kind}] {i.Name}", Tag = i });
        var dlg = new ItemPickerWindow("Pick related items", candidates) { Owner = Window.GetWindow(this) };
        if (dlg.ShowDialog() == true)
        {
            foreach (var tag in dlg.SelectedTags) _repo.AddRelation(_selected, (HierarchyItem)tag);
            _repo.Save();
            RefreshRelList();
        }
    }
    private void RemoveRel_Click(object sender, RoutedEventArgs e)
    {
        if (_selected == null || _repo == null || RelList.SelectedItem is not PickerItem pi) return;
        _repo.RemoveRelation(_selected, (HierarchyItem)pi.Tag);
        _repo.Save();
        RefreshRelList();
    }

    /// <summary>A GridView column whose cell wraps its bound text to the column width
    /// (instead of clipping a long task/checklist-step name onto one line).</summary>
    private static GridViewColumn WrapColumn(string header, string path, double width)
    {
        var f = new FrameworkElementFactory(typeof(TextBlock));
        f.SetBinding(TextBlock.TextProperty, new System.Windows.Data.Binding(path));
        f.SetValue(TextBlock.TextWrappingProperty, TextWrapping.Wrap);
        return new GridViewColumn { Header = header, Width = width, CellTemplate = new DataTemplate { VisualTree = f } };
    }

    /// <summary>Like <see cref="WrapColumn"/> but strikes the text through when the bound
    /// <paramref name="donePath"/> property is true — so completed steps/tasks read as done.</summary>
    private static GridViewColumn StrikeWrapColumn(string header, string textPath, string donePath, double width)
    {
        var f = new FrameworkElementFactory(typeof(TextBlock));
        f.SetBinding(TextBlock.TextProperty, new System.Windows.Data.Binding(textPath));
        f.SetValue(TextBlock.TextWrappingProperty, TextWrapping.Wrap);
        f.SetBinding(TextBlock.TextDecorationsProperty,
            new System.Windows.Data.Binding(donePath) { Converter = BoolToStrikethroughConverter.Instance });
        return new GridViewColumn { Header = header, Width = width, CellTemplate = new DataTemplate { VisualTree = f } };
    }

    // ---- Specifics ----
    private void BuildSpecifics()
    {
        if (_repo == null || _selected == null) { SpecificsHost.Content = null; return; }
        SpecificsHost.Content = _selected switch
        {
            Equipment eq => BuildEquipmentSpecifics(eq),
            TaskItem t => BuildTaskSpecifics(t),
            Procedure p => BuildProcedureSpecifics(p),
            _ => null
        };
    }

    private object BuildEquipmentSpecifics(Equipment eq)
    {
        var grid = new Grid { Margin = new Thickness(6) };
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        var hdr1 = new DockPanel { Margin = new Thickness(0, 0, 0, 4) };
        hdr1.Children.Add(new TextBlock { Text = "Components", FontWeight = FontWeights.Bold });
        var addComp = new Button { Content = "+ Add", Margin = new Thickness(8, 0, 0, 0) };
        var delComp = new Button { Content = "Remove", Margin = new Thickness(4, 0, 0, 0) };
        var editComp = new Button { Content = "Edit...", Margin = new Thickness(4, 0, 0, 0), ToolTip = "Open this component in a dedicated editor with its own rich-text container and file bank." };
        hdr1.Children.Add(addComp); hdr1.Children.Add(delComp); hdr1.Children.Add(editComp);
        Grid.SetRow(hdr1, 0); grid.Children.Add(hdr1);

        var compList = new ListView { Margin = new Thickness(0, 0, 0, 8) };
        // UI virtualization keeps the row cost flat for thousands of components; the per-row
        // container (rich text + files) is never realized until the user opens the editor.
        VirtualizingPanel.SetIsVirtualizing(compList, true);
        VirtualizingPanel.SetVirtualizationMode(compList, VirtualizationMode.Recycling);
        ScrollViewer.SetCanContentScroll(compList, true);
        var gv = new GridView();
        gv.Columns.Add(new GridViewColumn { Header = "Name", Width = 260, DisplayMemberBinding = new System.Windows.Data.Binding("Name") });
        gv.Columns.Add(new GridViewColumn { Header = "Notes", Width = 360, DisplayMemberBinding = new System.Windows.Data.Binding("Notes") });
        compList.View = gv;
        compList.ItemsSource = eq.Components;
        Grid.SetRow(compList, 1); grid.Children.Add(compList);
        addComp.Click += (_, _) =>
        {
            var p = new PromptWindow("New Component", "Name:") { Owner = Window.GetWindow(this) };
            if (p.ShowDialog() == true && !string.IsNullOrWhiteSpace(p.Value))
            { eq.Components.Add(new Component { Name = p.Value }); _repo!.Save(); }
        };
        delComp.Click += (_, _) =>
        {
            if (compList.SelectedItem is Component c) { eq.Components.Remove(c); _repo!.Save(); }
        };
        void OpenCompEditor()
        {
            if (compList.SelectedItem is not Component c || _repo == null) return;
            var w = new ComponentEditorWindow(c, _repo) { Owner = Window.GetWindow(this) };
            w.ShowDialog();
            compList.Items.Refresh();
        }
        editComp.Click += (_, _) => OpenCompEditor();
        compList.MouseDoubleClick += (_, _) => OpenCompEditor();

        var hdr2 = new DockPanel { Margin = new Thickness(0, 0, 0, 4) };
        hdr2.Children.Add(new TextBlock { Text = "Related Procedures (auto-relates sub-hierarchy)", FontWeight = FontWeights.Bold });
        var addProc = new Button { Content = "Pick...", Margin = new Thickness(8, 0, 0, 0) };
        var newProc = new Button { Content = "+ New procedure", Margin = new Thickness(4, 0, 0, 0),
            ToolTip = "Create a new Procedure and auto-link it to this Equipment/Area." };
        hdr2.Children.Add(addProc); hdr2.Children.Add(newProc);
        Grid.SetRow(hdr2, 2); grid.Children.Add(hdr2);
        var procList = new ListBox { Margin = new Thickness(0, 0, 0, 8), DisplayMemberPath = "Display" };
        Grid.SetRow(procList, 3); grid.Children.Add(procList);
        Action refreshProc = () => procList.ItemsSource = eq.ProcedureIds
            .Select(id => new PickerItem { Display = _repo!.Label(id), Tag = id }).ToList();
        refreshProc();
        addProc.Click += (_, _) =>
        {
            var dlg = new ItemPickerWindow("Pick procedures", _repo!.Data.Procedures
                .Select(p => new PickerItem { Display = p.Name, Tag = (object)p.Id }), eq.ProcedureIds.Cast<object>())
            { Owner = Window.GetWindow(this) };
            if (dlg.ShowDialog() == true)
            {
                eq.ProcedureIds.Clear();
                foreach (var id in dlg.SelectedTags.Cast<Guid>()) eq.ProcedureIds.Add(id);
                _repo!.Save(); refreshProc(); RefreshRelList();
            }
        };
        newProc.Click += (_, _) =>
        {
            var pr = new PromptWindow("New Procedure", "Name:") { Owner = Window.GetWindow(this) };
            if (pr.ShowDialog() != true || string.IsNullOrWhiteSpace(pr.Value)) return;
            var proc = new Procedure { Name = pr.Value };
            _repo!.Data.Procedures.Add(proc);
            eq.ProcedureIds.Add(proc.Id);
            _repo.LogAdded("Procedure", proc.Name, $"linked to {eq.Name}");
            _repo.Save();
            refreshProc(); RefreshRelList();
        };

        var hdr3 = new DockPanel { Margin = new Thickness(0, 0, 0, 4) };
        hdr3.Children.Add(new TextBlock { Text = "Related Tasks", FontWeight = FontWeights.Bold });
        var addTask = new Button { Content = "Pick...", Margin = new Thickness(8, 0, 0, 0) };
        var newTask = new Button { Content = "+ New task", Margin = new Thickness(4, 0, 0, 0),
            ToolTip = "Create a new Task and auto-link it to this Equipment/Area." };
        hdr3.Children.Add(addTask); hdr3.Children.Add(newTask);
        Grid.SetRow(hdr3, 4); grid.Children.Add(hdr3);
        var taskList = new ListBox { DisplayMemberPath = "Display" };
        Grid.SetRow(taskList, 5); grid.Children.Add(taskList);
        Action refreshTasks = () => taskList.ItemsSource = eq.TaskIds
            .Select(id => new PickerItem { Display = _repo!.Label(id), Tag = id }).ToList();
        refreshTasks();
        addTask.Click += (_, _) =>
        {
            var dlg = new ItemPickerWindow("Pick tasks", _repo!.Data.Tasks
                .Select(t => new PickerItem { Display = t.Name, Tag = (object)t.Id }), eq.TaskIds.Cast<object>())
            { Owner = Window.GetWindow(this) };
            if (dlg.ShowDialog() == true)
            {
                eq.TaskIds.Clear();
                foreach (var id in dlg.SelectedTags.Cast<Guid>()) eq.TaskIds.Add(id);
                _repo!.Save(); refreshTasks(); RefreshRelList();
            }
        };
        newTask.Click += (_, _) =>
        {
            var pr = new PromptWindow("New Task", "Name:") { Owner = Window.GetWindow(this) };
            if (pr.ShowDialog() != true || string.IsNullOrWhiteSpace(pr.Value)) return;
            var task = new TaskItem { Name = pr.Value };
            _repo!.Data.Tasks.Add(task);
            eq.TaskIds.Add(task.Id);
            _repo.LogAdded("Task", task.Name, $"linked to {eq.Name}");
            _repo.Save();
            refreshTasks(); RefreshRelList();
        };
        return new ScrollViewer { Content = grid, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    private object BuildTaskSpecifics(TaskItem t)
    {
        var sp = new StackPanel { Margin = new Thickness(8) };
        var dock1 = new DockPanel { Margin = new Thickness(0, 0, 0, 6) };
        dock1.Children.Add(new TextBlock { Text = "Deadline:", Width = 120, VerticalAlignment = VerticalAlignment.Center });
        var dp = new DatePicker { SelectedDate = t.Deadline, Width = 200, HorizontalAlignment = HorizontalAlignment.Left };
        dp.SelectedDateChanged += (_, _) => { t.Deadline = dp.SelectedDate; _repo!.MarkDirty(); };
        dock1.Children.Add(dp);
        sp.Children.Add(dock1);

        var dock2 = new DockPanel { Margin = new Thickness(0, 0, 0, 6) };
        dock2.Children.Add(new TextBlock { Text = "Recurrence:", Width = 120, VerticalAlignment = VerticalAlignment.Center });
        var cb = new ComboBox { Width = 200, HorizontalAlignment = HorizontalAlignment.Left,
            ItemsSource = Enum.GetValues(typeof(RecurrenceKind)), SelectedItem = t.Recurrence };
        cb.SelectionChanged += (_, _) => { if (cb.SelectedItem is RecurrenceKind r) { t.Recurrence = r; _repo!.MarkDirty(); } };
        dock2.Children.Add(cb);
        sp.Children.Add(dock2);

        var dockS = new DockPanel { Margin = new Thickness(0, 0, 0, 6) };
        dockS.Children.Add(new TextBlock { Text = "Status:", Width = 120, VerticalAlignment = VerticalAlignment.Center });
        var statusCb = new ComboBox { Width = 200, HorizontalAlignment = HorizontalAlignment.Left,
            ItemsSource = Enum.GetValues(typeof(WorkStatus)), SelectedItem = t.Status,
            ToolTip = "Workflow status used by the Board (Done keeps Completed in sync)." };
        dockS.Children.Add(statusCb);
        sp.Children.Add(dockS);

        var dock3 = new DockPanel { Margin = new Thickness(0, 0, 0, 10) };
        var chk = new CheckBox { Content = "Completed", IsChecked = t.IsComplete };
        bool syncing = false;
        statusCb.SelectionChanged += (_, _) =>
        {
            if (syncing || statusCb.SelectedItem is not WorkStatus st) return;
            t.Status = st;
            syncing = true; chk.IsChecked = t.IsComplete; syncing = false;
            _repo!.MarkDirty();
        };
        chk.Checked += (_, _) =>
        {
            if (syncing) return;
            t.IsComplete = true;
            syncing = true; statusCb.SelectedItem = t.Status; syncing = false;
            _repo!.MarkDirty();
        };
        chk.Unchecked += (_, _) =>
        {
            if (syncing) return;
            t.IsComplete = false;
            syncing = true; statusCb.SelectedItem = t.Status; syncing = false;
            _repo!.MarkDirty();
        };
        dock3.Children.Add(chk);
        sp.Children.Add(dock3);

        var dockJob = new DockPanel { Margin = new Thickness(0, 0, 0, 10) };
        var jobChk = new CheckBox { Content = "Schedulable job", IsChecked = t.IsJob, VerticalAlignment = VerticalAlignment.Center,
            ToolTip = "Tag this task as a Job so it can be dragged onto the Planner." };
        jobChk.Checked += (_, _) => { t.IsJob = true; _repo!.MarkDirty(); };
        jobChk.Unchecked += (_, _) => { t.IsJob = false; _repo!.MarkDirty(); };
        dockJob.Children.Add(jobChk);
        dockJob.Children.Add(new TextBlock { Text = "Duration (min):", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(14, 0, 4, 0) });
        var durBox = new TextBox { Width = 80, Text = t.DurationMinutes.ToString(), VerticalAlignment = VerticalAlignment.Center };
        durBox.TextChanged += (_, _) => { if (int.TryParse(durBox.Text, out var m) && m > 0) { t.DurationMinutes = m; _repo!.MarkDirty(); } };
        dockJob.Children.Add(durBox);
        sp.Children.Add(dockJob);

        // Prominent comprehensive subtask builder (mirrors the procedure Checklist builder).
        var subBuilderBtn = new Button
        {
            Content = "🛠  Open Comprehensive Subtask Builder",
            FontWeight = FontWeights.Bold,
            FontSize = 14,
            Padding = new Thickness(14, 8, 14, 8),
            Margin = new Thickness(0, 8, 0, 6),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Center,
            ToolTip = "Open a dedicated window to bulk-create, reorder, edit and delete subtasks.",
            Style = (Style?)Application.Current.TryFindResource("AccentButton")
        };
        subBuilderBtn.Click += (_, _) =>
        {
            if (_repo == null) return;
            new SubtaskBuilderWindow(t, _repo) { Owner = Window.GetWindow(this) }.ShowDialog();
        };
        sp.Children.Add(subBuilderBtn);

        sp.Children.Add(new TextBlock { Text = "Subtasks", FontWeight = FontWeights.Bold, Margin = new Thickness(0, 4, 0, 4) });
        var btnRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 4) };
        var addSub = new Button { Content = "+ Add" };
        var delSub = new Button { Content = "Remove", Margin = new Thickness(4, 0, 0, 0) };
        var editSub = new Button { Content = "Edit...", Margin = new Thickness(4, 0, 0, 0), ToolTip = "Open this subtask in a dedicated editor with its own deadline, container and files." };
        btnRow.Children.Add(addSub); btnRow.Children.Add(delSub); btnRow.Children.Add(editSub);
        sp.Children.Add(btnRow);
        var sub = new ListView { Height = 220 };
        var gv = new GridView();
        gv.Columns.Add(StrikeWrapColumn("Name", "Name", "IsComplete", 280));
        gv.Columns.Add(new GridViewColumn { Header = "Deadline", Width = 160, DisplayMemberBinding = new System.Windows.Data.Binding("Deadline") });
        gv.Columns.Add(new GridViewColumn { Header = "Status", Width = 110, DisplayMemberBinding = new System.Windows.Data.Binding("Status") });
        gv.Columns.Add(new GridViewColumn { Header = "Done", Width = 60, DisplayMemberBinding = new System.Windows.Data.Binding("IsComplete") });
        sub.View = gv;
        sub.ItemsSource = t.Subtasks;
        sp.Children.Add(sub);
        addSub.Click += (_, _) =>
        {
            var p = new PromptWindow("New Subtask", "Name:") { Owner = Window.GetWindow(this) };
            if (p.ShowDialog() == true && !string.IsNullOrWhiteSpace(p.Value))
            {
                var subItem = new TaskItem { Name = p.Value };
                t.Subtasks.Add(subItem);
                _repo!.LogAdded("Subtask", subItem.Name, t.Name);
                _repo.Save();
            }
        };
        delSub.Click += (_, _) =>
        {
            if (sub.SelectedItem is TaskItem st) { _repo!.LogRemoved("Subtask", st.Name, t.Name); t.Subtasks.Remove(st); _repo.Save(); }
        };
        void OpenSubEditor()
        {
            if (sub.SelectedItem is not TaskItem st || _repo == null) return;
            var w = new SubtaskEditorWindow(st, _repo) { Owner = Window.GetWindow(this) };
            w.ShowDialog();
            // Force the ListView to re-pull name/deadline/done columns.
            sub.Items.Refresh();
        }
        editSub.Click += (_, _) => OpenSubEditor();
        sub.MouseDoubleClick += (_, _) => OpenSubEditor();
        VirtualizingPanel.SetIsVirtualizing(sub, true);
        VirtualizingPanel.SetVirtualizationMode(sub, VirtualizationMode.Recycling);
        ScrollViewer.SetCanContentScroll(sub, true);

        return new ScrollViewer { Content = sp, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    private object BuildProcedureSpecifics(Procedure p)
    {
        var grid = new Grid { Margin = new Thickness(8) };
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // job row
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        // Row 0 groups the procedure deadline and the schedulable-job tagging.
        var row0 = new StackPanel();

        // Deadline (parallels a Task's deadline; surfaces in the floating due-dates window).
        var deadDock = new DockPanel { Margin = new Thickness(0, 0, 0, 8) };
        deadDock.Children.Add(new TextBlock { Text = "Deadline:", Width = 120, VerticalAlignment = VerticalAlignment.Center });
        var procDp = new DatePicker { SelectedDate = p.Deadline, Width = 200, HorizontalAlignment = HorizontalAlignment.Left,
            ToolTip = "Optional deadline for this procedure. Shown in the Calendar-style floating due-dates window." };
        procDp.SelectedDateChanged += (_, _) => { p.Deadline = procDp.SelectedDate; _repo!.MarkDirty(); };
        deadDock.Children.Add(procDp);
        row0.Children.Add(deadDock);

        // Recurrence (like a Task's).
        var recDock = new DockPanel { Margin = new Thickness(0, 0, 0, 8) };
        recDock.Children.Add(new TextBlock { Text = "Recurrence:", Width = 120, VerticalAlignment = VerticalAlignment.Center });
        var recCb = new ComboBox { Width = 200, HorizontalAlignment = HorizontalAlignment.Left,
            ItemsSource = Enum.GetValues(typeof(RecurrenceKind)), SelectedItem = p.Recurrence };
        recCb.SelectionChanged += (_, _) => { if (recCb.SelectedItem is RecurrenceKind r) { p.Recurrence = r; _repo!.MarkDirty(); } };
        recDock.Children.Add(recCb);
        row0.Children.Add(recDock);

        // Workflow status (like a Task's).
        var statDock = new DockPanel { Margin = new Thickness(0, 0, 0, 8) };
        statDock.Children.Add(new TextBlock { Text = "Status:", Width = 120, VerticalAlignment = VerticalAlignment.Center });
        var statCb = new ComboBox { Width = 200, HorizontalAlignment = HorizontalAlignment.Left,
            ItemsSource = Enum.GetValues(typeof(WorkStatus)), SelectedItem = p.Status,
            ToolTip = "Workflow status for this procedure." };
        statCb.SelectionChanged += (_, _) => { if (statCb.SelectedItem is WorkStatus s) { p.Status = s; _repo!.MarkDirty(); } };
        statDock.Children.Add(statCb);
        row0.Children.Add(statDock);

        // Tag the whole procedure as a schedulable Job (with a duration) for the Planner.
        var procJobDock = new DockPanel { Margin = new Thickness(0, 0, 0, 8) };
        var procJobChk = new CheckBox { Content = "Mark this procedure as a schedulable job", IsChecked = p.IsJob, VerticalAlignment = VerticalAlignment.Center,
            ToolTip = "Tag the whole procedure as a Job so it can be dragged onto the Planner." };
        procJobChk.Checked += (_, _) => { p.IsJob = true; _repo!.MarkDirty(); _repo.FlushIfDirty(); };
        procJobChk.Unchecked += (_, _) => { p.IsJob = false; _repo!.MarkDirty(); _repo.FlushIfDirty(); };
        procJobDock.Children.Add(procJobChk);
        procJobDock.Children.Add(new TextBlock { Text = "Duration (min):", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(14, 0, 4, 0) });
        var procDurBox = new TextBox { Width = 80, Text = p.DurationMinutes.ToString(), VerticalAlignment = VerticalAlignment.Center };
        procDurBox.TextChanged += (_, _) => { if (int.TryParse(procDurBox.Text, out var m) && m > 0) { p.DurationMinutes = m; _repo!.MarkDirty(); } };
        procJobDock.Children.Add(procDurBox);
        row0.Children.Add(procJobDock);

        Grid.SetRow(row0, 0); grid.Children.Add(row0);

        var checklistHdr = new TextBlock { Text = "Checklist Steps", FontWeight = FontWeights.Bold, Margin = new Thickness(0, 0, 0, 6) };
        Grid.SetRow(checklistHdr, 1); grid.Children.Add(checklistHdr);

        // Prominent banner so the comprehensive builder is impossible to miss.
        var topBar = new DockPanel { Margin = new Thickness(0, 0, 0, 6), LastChildFill = true };
        var exportPdfBtn = new Button
        {
            Content = "Export checklist (PDF)",
            Margin = new Thickness(6, 0, 0, 0),
            Padding = new Thickness(10, 6, 10, 6),
            ToolTip = "Export ONLY the checklist (no notes, no relationships) as a printable A4 PDF."
        };
        var exportXlsxBtn = new Button
        {
            Content = "Export checklist (Excel)",
            Margin = new Thickness(6, 0, 0, 0),
            Padding = new Thickness(10, 6, 10, 6),
            ToolTip = "Export ONLY the checklist as an Excel workbook (.xlsx)."
        };
        var exportPanel = new StackPanel { Orientation = Orientation.Horizontal };
        exportPanel.Children.Add(exportPdfBtn);
        exportPanel.Children.Add(exportXlsxBtn);
        DockPanel.SetDock(exportPanel, Dock.Right);
        topBar.Children.Add(exportPanel);

        var builderBtn = new Button
        {
            Content = "🛠  Open Comprehensive Checklist Builder",
            FontWeight = FontWeights.Bold,
            FontSize = 14,
            Padding = new Thickness(14, 8, 14, 8),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Center,
            ToolTip = "Open a dedicated window to bulk-create, reorder, edit and delete checklist steps.",
            Style = (Style?)Application.Current.TryFindResource("AccentButton")
        };
        topBar.Children.Add(builderBtn);
        Grid.SetRow(topBar, 2); grid.Children.Add(topBar);

        var bar = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 6, 0, 6) };
        var addStep = new Button { Content = "+ Step" };
        var delStep = new Button { Content = "Remove", Margin = new Thickness(4, 0, 0, 0) };
        var linkTasks = new Button { Content = "Link tasks...", Margin = new Thickness(8, 0, 0, 0) };
        var newStepTask = new Button { Content = "+ New task", Margin = new Thickness(4, 0, 0, 0),
            ToolTip = "Create a new Task and auto-link it to the selected checklist step." };
        var linkEq = new Button { Content = "Link equipment/area...", Margin = new Thickness(4, 0, 0, 0) };
        var editStep = new Button { Content = "Edit...", Margin = new Thickness(4, 0, 0, 0), ToolTip = "Open this checklist step in a dedicated editor with its own rich-text container and file bank." };
        bar.Children.Add(addStep); bar.Children.Add(delStep); bar.Children.Add(linkTasks); bar.Children.Add(newStepTask); bar.Children.Add(linkEq); bar.Children.Add(editStep);
        Grid.SetRow(bar, 3); grid.Children.Add(bar);

        var lv = new ListView();
        var gv = new GridView();
        var doneCol = new GridViewColumn { Header = "Done", Width = 50 };
        var tmpl = new DataTemplate();
        var cbFactory = new FrameworkElementFactory(typeof(CheckBox));
        cbFactory.SetBinding(CheckBox.IsCheckedProperty, new System.Windows.Data.Binding("Done"));
        cbFactory.AddHandler(System.Windows.Controls.Primitives.ToggleButton.ClickEvent,
            new RoutedEventHandler((_, _) => { _repo!.MarkDirty(); _repo.FlushIfDirty(); }));
        tmpl.VisualTree = cbFactory;
        doneCol.CellTemplate = tmpl;
        gv.Columns.Add(doneCol);

        // "Job" checkbox so steps can be tagged as schedulable Jobs right from the Procedures tab
        // (duration is set in the step editor). Persists immediately on toggle.
        var jobCol = new GridViewColumn { Header = "Job", Width = 44 };
        var jtmpl = new DataTemplate();
        var jcb = new FrameworkElementFactory(typeof(CheckBox));
        jcb.SetValue(CheckBox.ToolTipProperty, "Mark this step as a schedulable Job (set its duration in the step editor).");
        jcb.SetBinding(CheckBox.IsCheckedProperty, new System.Windows.Data.Binding("IsJob"));
        jcb.AddHandler(System.Windows.Controls.Primitives.ToggleButton.ClickEvent,
            new RoutedEventHandler((_, _) => { _repo!.MarkDirty(); _repo.FlushIfDirty(); }));
        jtmpl.VisualTree = jcb;
        jobCol.CellTemplate = jtmpl;
        gv.Columns.Add(jobCol);

        gv.Columns.Add(StrikeWrapColumn("Title", "Title", "Done", 300));
        // Per-step deadline (edit via the step editor / double-click) — lets a step act like a subtask.
        var stepDueCol = new GridViewColumn { Header = "Deadline", Width = 120 };
        var dueF = new FrameworkElementFactory(typeof(TextBlock));
        dueF.SetBinding(TextBlock.TextProperty, new System.Windows.Data.Binding("Deadline") { StringFormat = "yyyy-MM-dd" });
        dueF.SetValue(TextBlock.TextWrappingProperty, TextWrapping.Wrap);
        stepDueCol.CellTemplate = new DataTemplate { VisualTree = dueF };
        gv.Columns.Add(stepDueCol);
        lv.View = gv;
        lv.ItemsSource = p.Steps;
        Grid.SetRow(lv, 4); grid.Children.Add(lv);

        builderBtn.Click += (_, _) =>
        {
            if (_repo == null) return;
            var w = new ChecklistBuilderWindow(p, _repo) { Owner = Window.GetWindow(this) };
            w.ShowDialog();
            lv.Items.Refresh();
        };
        exportPdfBtn.Click += (_, _) => ExportChecklist(p, asExcel: false);
        exportXlsxBtn.Click += (_, _) => ExportChecklist(p, asExcel: true);

        addStep.Click += (_, _) =>
        {
            var pr = new PromptWindow("New Step", "Title:") { Owner = Window.GetWindow(this) };
            if (pr.ShowDialog() == true && !string.IsNullOrWhiteSpace(pr.Value))
            {
                var step = new ChecklistStep { Title = pr.Value };
                p.Steps.Add(step);
                _repo!.LogAdded("Checklist step", step.Title, p.Name);
                _repo.Save();
            }
        };
        delStep.Click += (_, _) =>
        {
            if (lv.SelectedItem is ChecklistStep st) { _repo!.LogRemoved("Checklist step", st.Title, p.Name); p.Steps.Remove(st); _repo.Save(); }
        };
        linkTasks.Click += (_, _) =>
        {
            if (lv.SelectedItem is not ChecklistStep st) return;
            var dlg = new ItemPickerWindow("Pick tasks for this step",
                _repo!.Data.Tasks.Select(t => new PickerItem { Display = t.Name, Tag = (object)t.Id }),
                st.TaskIds.Cast<object>()) { Owner = Window.GetWindow(this) };
            if (dlg.ShowDialog() == true)
            {
                st.TaskIds.Clear();
                foreach (var id in dlg.SelectedTags.Cast<Guid>()) st.TaskIds.Add(id);
                _repo!.Save();
            }
        };
        newStepTask.Click += (_, _) =>
        {
            if (lv.SelectedItem is not ChecklistStep st)
            {
                MessageBox.Show("Select a checklist step first.", "New task", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            var pr = new PromptWindow("New Task", "Name:") { Owner = Window.GetWindow(this) };
            if (pr.ShowDialog() != true || string.IsNullOrWhiteSpace(pr.Value)) return;
            var task = new TaskItem { Name = pr.Value };
            _repo!.Data.Tasks.Add(task);
            st.TaskIds.Add(task.Id);
            _repo.LogAdded("Task", task.Name, $"linked to step '{st.Title}'");
            _repo.Save();
        };
        linkEq.Click += (_, _) =>
        {
            if (lv.SelectedItem is not ChecklistStep st) return;
            var dlg = new ItemPickerWindow("Pick equipment/area for this step",
                _repo!.Data.Equipment.Select(e => new PickerItem { Display = e.Name, Tag = (object)e.Id }),
                st.EquipmentIds.Cast<object>()) { Owner = Window.GetWindow(this) };
            if (dlg.ShowDialog() == true)
            {
                st.EquipmentIds.Clear();
                foreach (var id in dlg.SelectedTags.Cast<Guid>()) st.EquipmentIds.Add(id);
                _repo!.Save();
            }
        };
        void OpenStepEditor()
        {
            if (lv.SelectedItem is not ChecklistStep st || _repo == null) return;
            var w = new ChecklistStepEditorWindow(st, _repo) { Owner = Window.GetWindow(this) };
            w.ShowDialog();
            lv.Items.Refresh();
        }
        editStep.Click += (_, _) => OpenStepEditor();
        lv.MouseDoubleClick += (_, _) => OpenStepEditor();
        VirtualizingPanel.SetIsVirtualizing(lv, true);
        VirtualizingPanel.SetVirtualizationMode(lv, VirtualizationMode.Recycling);
        ScrollViewer.SetCanContentScroll(lv, true);

        return grid;
    }

    private void ExportChecklist(Procedure p, bool asExcel)
    {
        if (_repo == null) return;
        _repo.FlushIfDirty();
        var safe = string.Concat((p.Name ?? "procedure").Select(ch => System.IO.Path.GetInvalidFileNameChars().Contains(ch) ? '_' : ch));
        var dlg = new Microsoft.Win32.SaveFileDialog
        {
            Title = asExcel ? "Export checklist to Excel" : "Export checklist to PDF",
            Filter = asExcel ? "Excel workbook (*.xlsx)|*.xlsx" : "PDF document (*.pdf)|*.pdf",
            FileName = $"checklist-{safe}.{(asExcel ? "xlsx" : "pdf")}",
            DefaultExt = asExcel ? ".xlsx" : ".pdf",
            AddExtension = true
        };
        if (dlg.ShowDialog(Window.GetWindow(this)) != true) return;
        try
        {
            Mouse.OverrideCursor = Cursors.Wait;
            if (asExcel) ChecklistExporter.ExportXlsx(p, _repo, dlg.FileName);
            else ChecklistExporter.ExportPdf(p, _repo, dlg.FileName);
        }
        catch (Exception ex)
        {
            MessageBox.Show("Failed to export checklist:\n" + ex.Message, "Export error",
                MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }
        finally { Mouse.OverrideCursor = null; }

        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(dlg.FileName) { UseShellExecute = true }); }
        catch { /* user can open manually */ }
    }
}
