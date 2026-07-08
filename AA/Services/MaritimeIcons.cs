using System;
using System.Windows.Media;

namespace AA.Services;

/// <summary>Curated set of common maritime/ship-operations icons (glyphs) for Quick Cards,
/// plus colour helpers (preset palette + readable-foreground calculation).</summary>
public static class MaritimeIcons
{
    /// <summary>(glyph, friendly name) pairs shown in the icon picker.</summary>
    public static readonly (string Glyph, string Name)[] All =
    {
        ("⚓", "Anchor"), ("🚢", "Ship"), ("⛴️", "Ferry"), ("⛵", "Sailboat"), ("🛥️", "Motorboat"),
        ("🛟", "Lifebuoy"), ("⛑️", "Rescue"), ("🧭", "Compass"), ("🗺️", "Chart"), ("🛞", "Helm/Wheel"),
        ("⚙️", "Engine"), ("🔧", "Wrench"), ("🛠️", "Tools"), ("🧰", "Toolbox"), ("🔩", "Fasteners"),
        ("⚡", "Electrical"), ("💡", "Lights"), ("🔦", "Torch"), ("📡", "Radar"), ("📻", "Radio"),
        ("📞", "Phone"), ("🔥", "Fire"), ("🧯", "Extinguisher"), ("🚨", "Alarm"), ("⚠️", "Warning"),
        ("⛽", "Fuel"), ("🛢️", "Oil/Bunker"), ("💧", "Fresh water"), ("🌊", "Sea/Ballast"), ("❄️", "Reefer"),
        ("🌡️", "Temperature"), ("📦", "Cargo"), ("🗃️", "Stores"), ("🗂️", "Files"), ("📁", "Folder"),
        ("📄", "Document"), ("📋", "Checklist"), ("📅", "Schedule"), ("🩺", "Medical"), ("🧪", "Lab/Test"),
        ("🪝", "Hook/Crane"), ("🔗", "Link"), ("🚪", "Door/Hatch"), ("🪟", "Bridge"), ("🧑‍✈️", "Crew"),
        ("🌐", "Network"), ("☎️", "Comms"), ("🧭", "Navigation"), ("🔔", "Bell"), ("⭐", "Favourite"),
    };

    public const string DefaultIcon = "⚓";

    /// <summary>A pleasant preset palette for card colours.</summary>
    public static readonly string[] Palette =
    {
        "#FF1E88E5", "#FF3949AB", "#FF00897B", "#FF43A047", "#FF7CB342",
        "#FFFDD835", "#FFFB8C00", "#FFF4511E", "#FFE53935", "#FFD81B60",
        "#FF8E24AA", "#FF5E35B1", "#FF546E7A", "#FF6D4C41", "#FF26A69A",
        "#FF455A64", "#FF263238", "#FF9E9E9E", "#FFEEEEEE", "#FFFFFFFF",
    };

    public static Color ParseColor(string? hex)
    {
        try { return (Color)ColorConverter.ConvertFromString(string.IsNullOrWhiteSpace(hex) ? "#FF1E88E5" : hex); }
        catch { return (Color)ColorConverter.ConvertFromString("#FF1E88E5"); }
    }

    /// <summary>Black or white, whichever reads better on the given background colour.</summary>
    public static Color ReadableForeground(Color bg)
    {
        // Relative luminance (sRGB approximation).
        double l = (0.299 * bg.R + 0.587 * bg.G + 0.114 * bg.B) / 255.0;
        return l > 0.6 ? Color.FromRgb(0x1A, 0x1A, 0x1A) : Colors.White;
    }

    public static Brush ReadableForegroundBrush(string? hex)
    {
        var b = new SolidColorBrush(ReadableForeground(ParseColor(hex)));
        b.Freeze();
        return b;
    }

    public static Brush BackgroundBrush(string? hex)
    {
        var b = new SolidColorBrush(ParseColor(hex));
        b.Freeze();
        return b;
    }
}
