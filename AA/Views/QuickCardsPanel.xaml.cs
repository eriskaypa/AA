using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using AA.Models;
using AA.Services;

namespace AA.Views;

public partial class QuickCardsPanel : UserControl
{
    private Vessel? _vessel;
    private AppRepository? _repo;

    // active drag state
    private Border? _dragBorder;
    private QuickCard? _dragCard;
    private Point _dragStartMouse;
    private Point _dragOrigin;

    public QuickCardsPanel() { InitializeComponent(); }

    public void Load(Vessel vessel, AppRepository repo)
    {
        _vessel = vessel;
        _repo = repo;
        Refresh();
    }

    private void Refresh()
    {
        CardCanvas.Children.Clear();
        if (_vessel == null) return;

        EmptyHint.Visibility = _vessel.QuickCards.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

        foreach (var card in _vessel.QuickCards)
            CardCanvas.Children.Add(BuildCard(card));

        SizeCanvas();
    }

    private void SizeCanvas()
    {
        double maxX = 1000, maxY = 640;
        if (_vessel != null)
            foreach (var c in _vessel.QuickCards)
            {
                maxX = Math.Max(maxX, c.X + c.Width + 40);
                maxY = Math.Max(maxY, c.Y + c.Height + 40);
            }
        CardCanvas.Width = maxX;
        CardCanvas.Height = maxY;
    }

    private Border BuildCard(QuickCard card)
    {
        var fg = MaritimeIcons.ReadableForegroundBrush(card.Color);
        var border = new Border
        {
            Width = card.Width,
            Height = card.Height,
            Background = MaritimeIcons.BackgroundBrush(card.Color),
            CornerRadius = new CornerRadius(10),
            BorderBrush = (Brush)FindResource("BorderB"),
            BorderThickness = new Thickness(1),
            Cursor = Cursors.Hand,
            Tag = card,
            ToolTip = TargetTooltip(card)
        };
        Canvas.SetLeft(border, card.X);
        Canvas.SetTop(border, card.Y);

        var grid = new Grid();
        var sp = new StackPanel { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(6) };
        double iconSize = Math.Max(18, Math.Min(card.Width, card.Height) * 0.36);
        sp.Children.Add(new TextBlock { Text = card.Icon, FontSize = iconSize, HorizontalAlignment = HorizontalAlignment.Center, Foreground = fg });
        if (!string.IsNullOrWhiteSpace(card.Title))
            sp.Children.Add(new TextBlock
            {
                Text = card.Title,
                FontWeight = FontWeights.Bold,
                FontSize = 13,
                TextWrapping = TextWrapping.Wrap,
                TextAlignment = TextAlignment.Center,
                Foreground = fg,
                Margin = new Thickness(0, 4, 0, 0)
            });
        grid.Children.Add(sp);

        // resize grip (bottom-right)
        var thumb = new Thumb
        {
            Width = 16,
            Height = 16,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(0, 0, 2, 2),
            Cursor = Cursors.SizeNWSE,
            Opacity = 0.55,
            Template = ResizeGripTemplate(fg)
        };
        thumb.DragDelta += (_, e) =>
        {
            card.Width = Math.Max(90, card.Width + e.HorizontalChange);
            card.Height = Math.Max(64, card.Height + e.VerticalChange);
            border.Width = card.Width;
            border.Height = card.Height;
        };
        thumb.DragCompleted += (_, _) => { SizeCanvas(); Save(); Refresh(); };
        grid.Children.Add(thumb);

        border.Child = grid;

        border.ContextMenu = BuildCardMenu(card);
        border.MouseLeftButtonDown += (_, e) => Card_MouseDown(border, card, e);
        border.MouseMove += (_, e) => Card_MouseMove(border, card, e);
        border.MouseLeftButtonUp += (_, e) => Card_MouseUp(border, card);

        return border;
    }

    private static ControlTemplate ResizeGripTemplate(Brush fg)
    {
        // A small triangular grip drawn from a Path, tinted to the readable foreground.
        var t = new ControlTemplate(typeof(Thumb));
        var p = new FrameworkElementFactory(typeof(System.Windows.Shapes.Path));
        p.SetValue(System.Windows.Shapes.Path.DataProperty, Geometry.Parse("M16,0 L16,16 L0,16 Z"));
        p.SetValue(System.Windows.Shapes.Path.FillProperty, fg);
        p.SetValue(FrameworkElement.OpacityProperty, 0.8);
        t.VisualTree = p;
        return t;
    }

    private ContextMenu BuildCardMenu(QuickCard card)
    {
        var cm = new ContextMenu();
        var open = new MenuItem { Header = "Open" };
        open.Click += (_, _) => Open(card);
        var edit = new MenuItem { Header = "Edit..." };
        edit.Click += (_, _) => Edit(card);
        var dup = new MenuItem { Header = "Duplicate" };
        dup.Click += (_, _) => Duplicate(card);
        var del = new MenuItem { Header = "Delete" };
        del.Click += (_, _) => Delete(card);
        cm.Items.Add(open);
        cm.Items.Add(edit);
        cm.Items.Add(dup);
        cm.Items.Add(new Separator());
        cm.Items.Add(del);
        return cm;
    }

    // ---- drag to move ----
    private void Card_MouseDown(Border border, QuickCard card, MouseButtonEventArgs e)
    {
        if (e.OriginalSource is DependencyObject d && FindAncestor<Thumb>(d) != null) return; // resizing
        if (e.ClickCount == 2) { Open(card); e.Handled = true; return; }
        _dragBorder = border;
        _dragCard = card;
        _dragStartMouse = e.GetPosition(CardCanvas);
        _dragOrigin = new Point(card.X, card.Y);
        border.CaptureMouse();
        e.Handled = true;
    }

    private void Card_MouseMove(Border border, QuickCard card, MouseEventArgs e)
    {
        if (_dragBorder != border || e.LeftButton != MouseButtonState.Pressed) return;
        var p = e.GetPosition(CardCanvas);
        double nx = Math.Max(0, _dragOrigin.X + (p.X - _dragStartMouse.X));
        double ny = Math.Max(0, _dragOrigin.Y + (p.Y - _dragStartMouse.Y));
        Canvas.SetLeft(border, nx);
        Canvas.SetTop(border, ny);
        card.X = nx;
        card.Y = ny;
    }

    private void Card_MouseUp(Border border, QuickCard card)
    {
        if (_dragBorder != border) return;
        border.ReleaseMouseCapture();
        _dragBorder = null;
        _dragCard = null;
        SizeCanvas();
        Save();
    }

    // ---- actions ----
    private void Add_Click(object sender, RoutedEventArgs e)
    {
        if (_vessel == null) return;
        int n = _vessel.QuickCards.Count;
        var card = new QuickCard { X = 24 + (n % 6) * 28, Y = 24 + (n % 6) * 28 };
        var w = new QuickCardEditorWindow(card) { Owner = Window.GetWindow(this) };
        if (w.ShowDialog() == true)
        {
            _vessel.QuickCards.Add(card);
            Save();
            Refresh();
        }
    }

    private void Edit(QuickCard card)
    {
        var snapshot = card.Clone();
        var w = new QuickCardEditorWindow(card) { Owner = Window.GetWindow(this) };
        if (w.ShowDialog() == true) { Save(); }
        else { card.CopyFrom(snapshot); }   // revert on cancel
        Refresh();
    }

    private void Duplicate(QuickCard card)
    {
        if (_vessel == null) return;
        var copy = card.Clone();
        copy.Id = Guid.NewGuid();
        copy.X += 24; copy.Y += 24;
        _vessel.QuickCards.Add(copy);
        Save();
        Refresh();
    }

    private void Delete(QuickCard card)
    {
        if (_vessel == null) return;
        if (MessageBox.Show(Window.GetWindow(this)!, $"Delete quick card '{(string.IsNullOrWhiteSpace(card.Title) ? card.Icon : card.Title)}'?",
                "Confirm", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        _vessel.QuickCards.Remove(card);
        Save();
        Refresh();
    }

    private void Open(QuickCard card)
    {
        if (string.IsNullOrWhiteSpace(card.Target))
        {
            MessageBox.Show(Window.GetWindow(this)!, "This card has no target yet. Right-click ▸ Edit to point it at a file, folder, or web link.",
                "Quick card", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        try
        {
            string target = card.IsLink || card.LinkInPlace ? card.Target : DataStore.ResolveFilePath(card.Target);
            if (!card.IsLink && !File.Exists(target) && !Directory.Exists(target))
            {
                MessageBox.Show(Window.GetWindow(this)!, $"Not found:\n{target}", "Open failed", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            MessageBox.Show(Window.GetWindow(this)!, ex.Message, "Open failed", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private static string TargetTooltip(QuickCard card)
    {
        var kind = card.IsLink ? "Web link" : card.IsFolder ? "Folder (live)" : card.LinkInPlace ? "File (live)" : "Imported copy";
        var t = string.IsNullOrWhiteSpace(card.Target) ? "(no target — right-click ▸ Edit)" : card.Target;
        return $"{(string.IsNullOrWhiteSpace(card.Title) ? "(untitled)" : card.Title)}\n{kind}: {t}\nDouble-click to open • drag to move • drag corner to resize";
    }

    private void Save()
    {
        _repo?.MarkDirty();
        _repo?.FlushIfDirty();
    }

    private static T? FindAncestor<T>(DependencyObject? d) where T : DependencyObject
    {
        while (d != null && d is not T) d = VisualTreeHelper.GetParent(d);
        return d as T;
    }
}
