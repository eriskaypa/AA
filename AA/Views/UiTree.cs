using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Media3D;

namespace AA.Views;

/// <summary>Tree-walking helpers that are safe for BOTH the visual tree and the content tree.
/// <para>
/// The pitfall this guards against: <see cref="VisualTreeHelper.GetParent"/> throws
/// <c>InvalidOperationException: '…' is not a Visual or Visual3D</c> when handed a
/// <see cref="System.Windows.ContentElement"/> — e.g. a <c>FlowDocument</c>, <c>Paragraph</c>, <c>Run</c>
/// or <c>Hyperlink</c> inside a rich-text box. A mouse handler that walks up from
/// <c>e.OriginalSource</c> will receive exactly those content elements when the click lands on rich text,
/// so any <c>FindAncestor</c> built directly on <c>VisualTreeHelper.GetParent</c> crashes there.
/// </para>
/// This helper hops content elements via the content/logical tree and only visuals via the visual tree,
/// so <see cref="FindAncestor{T}"/> can be called from any input handler without a crash.</summary>
public static class UiTree
{
    /// <summary>Nearest ancestor of type <typeparamref name="T"/> starting at (and including)
    /// <paramref name="d"/>, walking whichever tree each node belongs to. Returns null if none — callers
    /// treat "no match" as "the click wasn't on something I care about".</summary>
    public static T? FindAncestor<T>(DependencyObject? d) where T : DependencyObject
    {
        while (d != null)
        {
            if (d is T t) return t;
            d = GetParent(d);
        }
        return null;
    }

    /// <summary>Parent of any node without ever throwing: visuals walk the visual tree; content elements
    /// (which are NOT visuals) walk the content/logical tree; anything else falls back to the logical tree.</summary>
    public static DependencyObject? GetParent(DependencyObject? d)
    {
        if (d == null) return null;

        // Visuals and 3-D visuals live in the visual tree.
        if (d is Visual || d is Visual3D)
        {
            var vp = VisualTreeHelper.GetParent(d);
            if (vp != null) return vp;
        }

        // ContentElements (FlowDocument, Paragraph, Run, Hyperlink, …) live in the content tree —
        // VisualTreeHelper would throw on these, so use ContentOperations instead.
        if (d is ContentElement ce)
        {
            var cp = ContentOperations.GetParent(ce);
            if (cp != null) return cp;
        }

        // Fallback (a visual with no visual parent, or a framework content element): the logical parent.
        return LogicalTreeHelper.GetParent(d);
    }
}
