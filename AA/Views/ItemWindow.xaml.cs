using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using AA.Models;
using AA.Services;

namespace AA.Views;

/// <summary>One task / procedure / equipment open in its own window, so several can be worked on at once.
///
/// The safety of this rests on two rules. First, it holds the item's <b>Id</b>, never a long-lived model
/// reference: when the database is reloaded (File ▸ Reload, an import, a shared-save pull, Flash Sync) the
/// old object is replaced wholesale, and a window still pointing at it would write edits into an orphan
/// that is never saved. <see cref="SetRepo"/> re-resolves by Id instead.
///
/// Second, only ONE editor may be bound to a given container at a time. <see cref="ContainerEditor"/>
/// persists by serialising its whole document over the container's text with no dirty check, so two live
/// editors on one item means whichever saves last silently wins. The main window's details pane unbinds
/// while an item is detached, and rebinds when this window closes.</summary>
public partial class ItemWindow : Window
{
    private AppRepository _repo;
    private readonly Guid _id;
    private HierarchyItem? _item;
    private bool _suppress;      // set while fields are populated, so handlers don't write back
    private bool _orphaned;      // the item is no longer in the loaded data

    /// <summary>Raised when the item's name changes, so the main list can re-label its row.</summary>
    public event Action<Guid>? NameChanged;

    public Guid ItemId => _id;

    public ItemWindow(AppRepository repo, HierarchyItem item)
    {
        InitializeComponent();
        _repo = repo;
        _id = item.Id;
        _item = item;
        Bind();
    }

    private void Bind()
    {
        if (_item == null) { GoOrphaned(); return; }

        _suppress = true;
        try
        {
            Title = $"{_item.Kind} — {(_item.Name.Length > 0 ? _item.Name : "(unnamed)")}";
            KindText.Text = _item.Kind.ToString();
            NameBox.Text = _item.Name;
            DescBox.Text = _item.Description;
            TagsBox.Text = string.Join(", ", _item.Tags);
            StateText.Text = "";
            ContainerCtrl.Load(_item.Container, _repo);   // repo argument is required, or edits are dropped
        }
        finally { _suppress = false; }
    }

    /// <summary>Point this window at a reloaded database. The item is looked up again by Id, because the
    /// reload replaced every model object; if it is gone, the window goes read-only rather than writing
    /// into something that no longer exists.</summary>
    public void SetRepo(AppRepository repo)
    {
        // Anything typed before the reload belongs to the OLD object and cannot be carried across safely.
        try { ContainerCtrl.FlushPending(); } catch { }
        _repo = repo;
        _item = repo.FindById(_id);
        if (_item == null) { GoOrphaned(); return; }
        _orphaned = false;
        Bind();
    }

    /// <summary>Write any buffered rich-text edit into the model now. Called before the app saves, syncs,
    /// exports or closes, so a detached window's work is never left sitting in a timer.</summary>
    public void Flush()
    {
        if (_orphaned) return;
        try { ContainerCtrl.FlushPending(); } catch { }
    }

    /// <summary>The item has been deleted (or lost in a reload). Stop editing rather than resurrect it.</summary>
    public void GoOrphaned()
    {
        _orphaned = true;
        _item = null;
        _suppress = true;
        try
        {
            StateText.Text = "This item is no longer in the loaded data — nothing typed here will be saved.";
            NameBox.IsEnabled = DescBox.IsEnabled = TagsBox.IsEnabled = false;
            ContainerCtrl.IsEnabled = false;
        }
        finally { _suppress = false; }
    }

    private void NameBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (_suppress || _orphaned || _item == null) return;
        _item.Name = NameBox.Text;
        Title = $"{_item.Kind} — {(_item.Name.Length > 0 ? _item.Name : "(unnamed)")}";
        _repo.MarkDirty();
        NameChanged?.Invoke(_id);
    }

    private void DescBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (_suppress || _orphaned || _item == null) return;
        _item.Description = DescBox.Text;
        _repo.MarkDirty();
    }

    private void TagsBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (_suppress || _orphaned || _item == null) return;
        _item.Tags.Clear();
        foreach (var t in TagsBox.Text.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            _item.Tags.Add(t);
        _repo.MarkDirty();
    }

    private void Window_Closing(object sender, System.ComponentModel.CancelEventArgs e)
    {
        // Guarded: a throw here would cancel the close and trap the window open.
        try { ContainerCtrl.FlushPending(); } catch { }
    }
}
