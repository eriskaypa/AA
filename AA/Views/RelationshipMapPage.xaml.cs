using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using AA.Models;
using AA.Services;

namespace AA.Views;

public partial class RelationshipMapPage : UserControl
{
    private AppRepository? _repo;
    private List<PickerItem> _all = new();
    private HierarchyItem? _currentCenter;

    public RelationshipMapPage() { InitializeComponent(); }

    public Guid? FocusedItemId => _currentCenter?.Id;

    public void Init(AppRepository repo)
    {
        _repo = repo;
        RefreshSidebar();
        if (repo.Data.Ui.MapFocusedItemId is Guid id)
        {
            var item = repo.FindById(id);
            if (item != null) FocusOn(item);
        }
    }

    public void RefreshSidebar()
    {
        if (_repo == null) return;
        _all = _repo.AllItems().Select(i => new PickerItem { Display = $"[{i.Kind}] {i.Name}", Tag = i }).ToList();
        ApplyFilter();
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e) => ApplyFilter();

    private void ApplyFilter()
    {
        var q = SearchBox.Text?.Trim() ?? "";
        Lb.ItemsSource = string.IsNullOrEmpty(q) ? _all :
            _all.Where(i => i.Display.Contains(q, StringComparison.OrdinalIgnoreCase)).ToList();
    }

    private void Lb_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (Lb.SelectedItem is PickerItem p && p.Tag is HierarchyItem h) DrawMap(h);
    }

    public void FocusOn(HierarchyItem item)
    {
        RefreshSidebar();
        var match = _all.FirstOrDefault(p => p.Tag == item);
        if (match != null) Lb.SelectedItem = match;
        DrawMap(item);
    }

    private void DrawMap(HierarchyItem center)
    {
        if (_repo == null) return;
        _currentCenter = center;
        MapCanvas.Children.Clear();
        MapTitle.Text = $"Relationship Map — {center.Name}";

        // Nodes: center + related (1-hop)
        var related = _repo.RelatedItems(center).Distinct().ToList();
        var nodes = new List<HierarchyItem> { center };
        nodes.AddRange(related);

        var cx = MapCanvas.Width / 2.0;
        var cy = MapCanvas.Height / 2.0;
        var positions = new Dictionary<Guid, Point> { [center.Id] = new Point(cx, cy) };

        // Place related nodes on a circle
        int n = related.Count;
        double radius = Math.Min(cx, cy) - 140;
        for (int i = 0; i < n; i++)
        {
            double angle = 2 * Math.PI * i / Math.Max(1, n);
            var pt = new Point(cx + radius * Math.Cos(angle), cy + radius * Math.Sin(angle));
            positions[related[i].Id] = pt;
        }

        // Edges from center
        foreach (var r in related)
        {
            var p1 = positions[center.Id];
            var p2 = positions[r.Id];
            var line = new Line { X1 = p1.X, Y1 = p1.Y, X2 = p2.X, Y2 = p2.Y, Stroke = (Brush)Application.Current.Resources["Accent"], StrokeThickness = 1.5, Opacity = 0.65 };
            MapCanvas.Children.Add(line);
        }
        // Edges among related (when they relate to each other too)
        for (int i = 0; i < related.Count; i++)
            for (int j = i + 1; j < related.Count; j++)
                if (related[i].RelatedIds.Contains(related[j].Id))
                {
                    var p1 = positions[related[i].Id];
                    var p2 = positions[related[j].Id];
                    MapCanvas.Children.Add(new Line { X1 = p1.X, Y1 = p1.Y, X2 = p2.X, Y2 = p2.Y, Stroke = (Brush)Application.Current.Resources["Muted"], StrokeThickness = 1, StrokeDashArray = new DoubleCollection { 4, 3 }, Opacity = 0.6 });
                }

        // Nodes
        foreach (var node in nodes)
            DrawNode(node, positions[node.Id], node.Id == center.Id);
    }

    private void DrawNode(HierarchyItem item, Point p, bool isCenter)
    {
        var border = new Border
        {
            Background = new SolidColorBrush(Colors.White),
            BorderBrush = new SolidColorBrush(Colors.Black),
            BorderThickness = new Thickness(isCenter ? 3 : 1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(10, 6, 10, 6),
            Cursor = Cursors.Hand
        };
        var stack = new StackPanel();
        stack.Children.Add(new TextBlock { Text = item.Kind.ToString(), FontSize = 10, Foreground = new SolidColorBrush(Colors.Black) });
        stack.Children.Add(new TextBlock { Text = item.Name, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Colors.Black) });
        border.Child = stack;

        border.MouseLeftButtonUp += (_, _) => DrawMap(item);

        border.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        Canvas.SetLeft(border, p.X - border.DesiredSize.Width / 2);
        Canvas.SetTop(border, p.Y - border.DesiredSize.Height / 2);
        MapCanvas.Children.Add(border);
    }
}
