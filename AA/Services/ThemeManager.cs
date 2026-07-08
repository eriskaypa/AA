using System.Windows;
using System.Windows.Media;

namespace AA.Services;

/// <summary>Swaps the app's theme brushes (and the system-colour brushes used by default control
/// templates) at runtime. Every view binds these keys with DynamicResource, so toggling re-themes
/// the whole app live (no restart).</summary>
public static class ThemeManager
{
    public static bool IsDark { get; private set; }

    public static void Apply(bool dark)
    {
        IsDark = dark;
        var res = Application.Current.Resources;

        SolidColorBrush B(byte r, byte g, byte b)
        {
            var br = new SolidColorBrush(Color.FromRgb(r, g, b));
            br.Freeze();
            return br;
        }

        SolidColorBrush bg, panel, panelAlt, accent, accentHover, fg, muted, border, hover, selBg, selFg;
        if (dark)
        {
            bg = B(0x1E, 0x1E, 0x1E); panel = B(0x25, 0x25, 0x26); panelAlt = B(0x2D, 0x2D, 0x30);
            accent = B(0xFF, 0xFF, 0xFF); accentHover = B(0xCC, 0xCC, 0xCC);
            fg = B(0xF0, 0xF0, 0xF0); muted = B(0xB0, 0xB0, 0xB0); border = B(0x3F, 0x3F, 0x46);
            hover = B(0x3A, 0x3A, 0x3D); selBg = B(0x09, 0x47, 0x71); selFg = B(0xFF, 0xFF, 0xFF);
        }
        else
        {
            bg = B(0xFF, 0xFF, 0xFF); panel = B(0xFF, 0xFF, 0xFF); panelAlt = B(0xFF, 0xFF, 0xFF);
            accent = B(0x00, 0x00, 0x00); accentHover = B(0x00, 0x00, 0x00);
            fg = B(0x00, 0x00, 0x00); muted = B(0x00, 0x00, 0x00); border = B(0x00, 0x00, 0x00);
            hover = B(0xEF, 0xEF, 0xEF); selBg = B(0xCC, 0xE8, 0xFF); selFg = B(0x00, 0x00, 0x00);
        }

        res["Bg"] = bg; res["Panel"] = panel; res["PanelAlt"] = panelAlt;
        res["Accent"] = accent; res["AccentHover"] = accentHover;
        res["Fg"] = fg; res["Muted"] = muted; res["BorderB"] = border;
        res["HoverBg"] = hover; res["SelBg"] = selBg; res["SelFg"] = selFg;

        // System-colour brushes used by default templates (menus, context menus, tooltips, the
        // calendar/date-picker popups, selection, etc.). In dark mode we override them; in light we
        // remove the overrides so the native light system colours return.
        void Sys(object key, SolidColorBrush v) { if (dark) res[key] = v; else res.Remove(key); }
        Sys(SystemColors.WindowBrushKey, panel);
        Sys(SystemColors.WindowTextBrushKey, fg);
        Sys(SystemColors.ControlBrushKey, panel);
        Sys(SystemColors.ControlTextBrushKey, fg);
        Sys(SystemColors.ControlLightBrushKey, panelAlt);
        Sys(SystemColors.ControlLightLightBrushKey, panel);
        Sys(SystemColors.ControlDarkBrushKey, border);
        Sys(SystemColors.GrayTextBrushKey, muted);
        Sys(SystemColors.HighlightBrushKey, selBg);
        Sys(SystemColors.HighlightTextBrushKey, selFg);
        Sys(SystemColors.MenuBrushKey, panel);
        Sys(SystemColors.MenuTextBrushKey, fg);
        Sys(SystemColors.InfoBrushKey, panel);
        Sys(SystemColors.InfoTextBrushKey, fg);
        Sys(SystemColors.WindowFrameBrushKey, border);
    }
}
