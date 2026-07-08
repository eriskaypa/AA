using System;
using System.Collections.Generic;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;

namespace AA.Views;

/// <summary>Comprehensive, maritime-focused unit converter: type a value in any unit and every other
/// unit in the category updates at once.</summary>
public partial class UnitConverterWindow : Window
{
    /// <summary>A unit within a category, defined by conversions to/from the category's base unit.</summary>
    private sealed class Unit
    {
        public string Name = "";
        public Func<double, double> ToBase = v => v;
        public Func<double, double> FromBase = v => v;

        public static Unit Linear(string name, double perBase) => new()
        {
            Name = name, ToBase = v => v * perBase, FromBase = v => v / perBase
        };
        public static Unit Custom(string name, Func<double, double> toBase, Func<double, double> fromBase) => new()
        {
            Name = name, ToBase = toBase, FromBase = fromBase
        };
    }

    private sealed class Category
    {
        public string Name = "";
        public List<Unit> Units = new();
    }

    private readonly List<Category> _categories = BuildCategories();
    private readonly List<(Unit unit, TextBox box)> _rows = new();
    private bool _suppress;

    public UnitConverterWindow()
    {
        InitializeComponent();
        foreach (var c in _categories) CategoryBox.Items.Add(c.Name);
        CategoryBox.SelectedIndex = 0;   // triggers Category_Changed -> BuildRows
    }

    private void Category_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (CategoryBox.SelectedIndex < 0 || CategoryBox.SelectedIndex >= _categories.Count) return;
        BuildRows(_categories[CategoryBox.SelectedIndex]);
    }

    private void BuildRows(Category cat)
    {
        RowsHost.Children.Clear();
        _rows.Clear();
        foreach (var u in cat.Units)
        {
            var dock = new DockPanel { Margin = new Thickness(0, 3, 0, 3) };
            dock.Children.Add(new TextBlock
            {
                Text = u.Name, Width = 210, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.Wrap
            });
            var box = new TextBox { VerticalAlignment = VerticalAlignment.Center, Tag = u };
            box.TextChanged += Value_Changed;
            dock.Children.Add(box);
            RowsHost.Children.Add(dock);
            _rows.Add((u, box));
        }
        // Seed with 1 of the first unit so the table is immediately meaningful.
        if (_rows.Count > 0) _rows[0].box.Text = "1";
    }

    private void Value_Changed(object sender, TextChangedEventArgs e)
    {
        if (_suppress || sender is not TextBox src || src.Tag is not Unit srcUnit) return;
        if (!double.TryParse(src.Text, NumberStyles.Any, CultureInfo.InvariantCulture, out var v))
        {
            // Blank/invalid input clears the other fields (but not the one being edited).
            _suppress = true;
            foreach (var (_, box) in _rows) if (!ReferenceEquals(box, src)) box.Text = "";
            _suppress = false;
            return;
        }
        var baseVal = srcUnit.ToBase(v);
        _suppress = true;
        foreach (var (unit, box) in _rows)
            if (!ReferenceEquals(box, src)) box.Text = Format(unit.FromBase(baseVal));
        _suppress = false;
    }

    private static string Format(double v)
    {
        if (double.IsNaN(v) || double.IsInfinity(v)) return "";
        if (v == 0) return "0";
        var abs = Math.Abs(v);
        // Use scientific notation only at the extremes; otherwise a clean fixed form.
        if (abs < 1e-4 || abs >= 1e12) return v.ToString("G6", CultureInfo.InvariantCulture);
        return v.ToString("0.######", CultureInfo.InvariantCulture);
    }

    private static List<Category> BuildCategories() => new()
    {
        new Category { Name = "Speed", Units =   // base: metre / second
        {
            Unit.Linear("Knots (nautical mile/h)", 0.514444),
            Unit.Linear("Kilometres per hour (km/h)", 0.277778),
            Unit.Linear("Miles per hour (mph)", 0.44704),
            Unit.Linear("Metres per second (m/s)", 1.0),
            Unit.Linear("Feet per second (ft/s)", 0.3048),
            Unit.Linear("Nautical miles per day", 1852.0 / 86400.0),
        }},
        new Category { Name = "Distance / Length", Units =   // base: metre
        {
            Unit.Linear("Nautical miles (NM)", 1852.0),
            Unit.Linear("Statute miles", 1609.344),
            Unit.Linear("Kilometres (km)", 1000.0),
            Unit.Linear("Metres (m)", 1.0),
            Unit.Linear("Cables", 185.2),
            Unit.Linear("Fathoms", 1.8288),
            Unit.Linear("Yards", 0.9144),
            Unit.Linear("Feet", 0.3048),
            Unit.Linear("Inches", 0.0254),
            Unit.Linear("Centimetres (cm)", 0.01),
        }},
        new Category { Name = "Pressure", Units =   // base: pascal
        {
            Unit.Linear("Bar", 100000.0),
            Unit.Linear("Millibar / hPa", 100.0),
            Unit.Linear("Pounds per sq inch (psi)", 6894.757293),
            Unit.Linear("Kilopascal (kPa)", 1000.0),
            Unit.Linear("Megapascal (MPa)", 1000000.0),
            Unit.Linear("Atmospheres (atm)", 101325.0),
            Unit.Linear("kg-force / cm²", 98066.5),
            Unit.Linear("mm of mercury (mmHg/torr)", 133.322387),
            Unit.Linear("in of mercury (inHg)", 3386.389),
            Unit.Linear("Pascal (Pa)", 1.0),
        }},
        new Category { Name = "Temperature", Units =   // base: Celsius
        {
            Unit.Custom("Celsius (°C)", c => c, c => c),
            Unit.Custom("Fahrenheit (°F)", f => (f - 32.0) * 5.0 / 9.0, c => c * 9.0 / 5.0 + 32.0),
            Unit.Custom("Kelvin (K)", k => k - 273.15, c => c + 273.15),
        }},
        new Category { Name = "Volume", Units =   // base: litre
        {
            Unit.Linear("Litres (L)", 1.0),
            Unit.Linear("Cubic metres (m³)", 1000.0),
            Unit.Linear("Cubic feet (ft³)", 28.316846),
            Unit.Linear("US gallons", 3.785412),
            Unit.Linear("Imperial gallons", 4.546090),
            Unit.Linear("Oil barrels (42 US gal)", 158.987295),
            Unit.Linear("US quarts", 0.946353),
            Unit.Linear("Millilitres (mL)", 0.001),
        }},
        new Category { Name = "Mass / Weight", Units =   // base: kilogram
        {
            Unit.Linear("Kilograms (kg)", 1.0),
            Unit.Linear("Metric tonnes (t)", 1000.0),
            Unit.Linear("Long tons (2240 lb)", 1016.0469),
            Unit.Linear("Short tons (2000 lb)", 907.18474),
            Unit.Linear("Pounds (lb)", 0.45359237),
            Unit.Linear("Stone", 6.35029318),
            Unit.Linear("Grams (g)", 0.001),
        }},
        new Category { Name = "Angle / Bearing", Units =   // base: degree
        {
            Unit.Linear("Degrees (°)", 1.0),
            Unit.Linear("Radians", 57.29577951),
            Unit.Linear("Gradians (gon)", 0.9),
            Unit.Linear("Compass points (32-pt)", 11.25),
            Unit.Linear("Mils (NATO, 6400)", 0.05625),
            Unit.Linear("Arcminutes (')", 1.0 / 60.0),
        }},
        new Category { Name = "Time", Units =   // base: second
        {
            Unit.Linear("Seconds", 1.0),
            Unit.Linear("Minutes", 60.0),
            Unit.Linear("Hours", 3600.0),
            Unit.Linear("Days", 86400.0),
            Unit.Linear("Weeks", 604800.0),
            Unit.Linear("Watches (4 h)", 14400.0),
        }},
        new Category { Name = "Power", Units =   // base: watt
        {
            Unit.Linear("Kilowatts (kW)", 1000.0),
            Unit.Linear("Watts (W)", 1.0),
            Unit.Linear("Metric horsepower (PS)", 735.49875),
            Unit.Linear("Mechanical horsepower (hp)", 745.699872),
            Unit.Linear("BTU per hour", 0.29307107),
        }},
        new Category { Name = "Force", Units =   // base: newton
        {
            Unit.Linear("Newtons (N)", 1.0),
            Unit.Linear("Kilonewtons (kN)", 1000.0),
            Unit.Linear("Tonnes-force (tf)", 9806.65),
            Unit.Linear("Kilograms-force (kgf)", 9.80665),
            Unit.Linear("Pounds-force (lbf)", 4.4482216),
        }},
        new Category { Name = "Density", Units =   // base: kg/m³
        {
            Unit.Linear("Kilograms / m³", 1.0),
            Unit.Linear("Grams / cm³ (= t/m³)", 1000.0),
            Unit.Linear("Pounds / cubic foot", 16.018463),
            Unit.Linear("Pounds / US gallon", 119.826427),
        }},
        new Category { Name = "Flow rate", Units =   // base: m³/hour
        {
            Unit.Linear("Cubic metres / hour (m³/h)", 1.0),
            Unit.Linear("Cubic metres / day", 1.0 / 24.0),
            Unit.Linear("Litres / minute", 0.06),
            Unit.Linear("Litres / hour", 0.001),
            Unit.Linear("US gallons / minute (GPM)", 0.2271247),
            Unit.Linear("Oil barrels / day", 158.987295 / 1000.0 / 24.0),
        }},
        new Category { Name = "Area", Units =   // base: square metre
        {
            Unit.Linear("Square metres (m²)", 1.0),
            Unit.Linear("Square kilometres (km²)", 1000000.0),
            Unit.Linear("Hectares", 10000.0),
            Unit.Linear("Square feet (ft²)", 0.09290304),
            Unit.Linear("Acres", 4046.8564),
        }},
        new Category { Name = "Energy", Units =   // base: joule
        {
            Unit.Linear("Kilojoules (kJ)", 1000.0),
            Unit.Linear("Joules (J)", 1.0),
            Unit.Linear("Kilowatt-hours (kWh)", 3600000.0),
            Unit.Linear("Kilocalories (kcal)", 4184.0),
            Unit.Linear("BTU", 1055.05585),
        }},
    };
}
