// Spec: 14 TOOLS-081 (14 categories, order, default Speed), TOOLS-082 (rows, seed "1"), TOOLS-083 (live conversion,
//       the edited box is never rewritten), TOOLS-085 (invalid/blank clears the others), TOOLS-087 (factor table,
//       division for fromBase, temperature formulas), TOOLS-088 (category switch resets), §3.5.1–3.5.3 (exact table,
//       86 units), 6.9 (SF Symbols per category). Source: AA/Views/UnitConverterWindow.xaml.cs.
import Foundation

/// One unit of a category, defined by its conversions to and from the category's base unit.
public struct ToolUnit: Sendable {
    public let name: String
    public let toBase: @Sendable (Double) -> Double
    public let fromBase: @Sendable (Double) -> Double

    public init(name: String, toBase: @escaping @Sendable (Double) -> Double,
                fromBase: @escaping @Sendable (Double) -> Double) {
        self.name = name; self.toBase = toBase; self.fromBase = fromBase
    }

    /// `Linear(name, perBase)`: `toBase = v × perBase`, `fromBase = v ÷ perBase` (division, not a reciprocal).
    public static func linear(_ name: String, _ perBase: Double) -> ToolUnit {
        ToolUnit(name: name, toBase: { $0 * perBase }, fromBase: { $0 / perBase })
    }
}

public struct ToolUnitCategory: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    /// SF Symbol for the Mac category picker (14 §6.9).
    public let symbol: String
    public let units: [ToolUnit]

    public init(name: String, symbol: String, units: [ToolUnit]) {
        self.name = name; self.symbol = symbol; self.units = units
    }
}

public enum ToolUnitCatalog {
    /// The 14 categories in menu order (exact names and factors of 14 §3.5.3).
    public static let categories: [ToolUnitCategory] = [
        ToolUnitCategory(name: "Speed", symbol: "gauge.with.needle", units: [            // base: metre / second
            .linear("Knots (nautical mile/h)", 0.514444),
            .linear("Kilometres per hour (km/h)", 0.277778),
            .linear("Miles per hour (mph)", 0.44704),
            .linear("Metres per second (m/s)", 1.0),
            .linear("Feet per second (ft/s)", 0.3048),
            .linear("Nautical miles per day", 1852.0 / 86400.0),
        ]),
        ToolUnitCategory(name: "Distance / Length", symbol: "ruler", units: [               // base: metre
            .linear("Nautical miles (NM)", 1852.0),
            .linear("Statute miles", 1609.344),
            .linear("Kilometres (km)", 1000.0),
            .linear("Metres (m)", 1.0),
            .linear("Cables", 185.2),
            .linear("Fathoms", 1.8288),
            .linear("Yards", 0.9144),
            .linear("Feet", 0.3048),
            .linear("Inches", 0.0254),
            .linear("Centimetres (cm)", 0.01),
        ]),
        ToolUnitCategory(name: "Pressure", symbol: "barometer", units: [                     // base: pascal
            .linear("Bar", 100000.0),
            .linear("Millibar / hPa", 100.0),
            .linear("Pounds per sq inch (psi)", 6894.757293),
            .linear("Kilopascal (kPa)", 1000.0),
            .linear("Megapascal (MPa)", 1000000.0),
            .linear("Atmospheres (atm)", 101325.0),
            .linear("kg-force / cm\u{00B2}", 98066.5),
            .linear("mm of mercury (mmHg/torr)", 133.322387),
            .linear("in of mercury (inHg)", 3386.389),
            .linear("Pascal (Pa)", 1.0),
        ]),
        ToolUnitCategory(name: "Temperature", symbol: "thermometer.medium", units: [        // base: Celsius
            ToolUnit(name: "Celsius (\u{00B0}C)", toBase: { $0 }, fromBase: { $0 }),
            ToolUnit(name: "Fahrenheit (\u{00B0}F)", toBase: { ($0 - 32.0) * 5.0 / 9.0 }, fromBase: { $0 * 9.0 / 5.0 + 32.0 }),
            ToolUnit(name: "Kelvin (K)", toBase: { $0 - 273.15 }, fromBase: { $0 + 273.15 }),
        ]),
        ToolUnitCategory(name: "Volume", symbol: "drop", units: [                           // base: litre
            .linear("Litres (L)", 1.0),
            .linear("Cubic metres (m\u{00B3})", 1000.0),
            .linear("Cubic feet (ft\u{00B3})", 28.316846),
            .linear("US gallons", 3.785412),
            .linear("Imperial gallons", 4.546090),
            .linear("Oil barrels (42 US gal)", 158.987295),
            .linear("US quarts", 0.946353),
            .linear("Millilitres (mL)", 0.001),
        ]),
        ToolUnitCategory(name: "Mass / Weight", symbol: "scalemass", units: [               // base: kilogram
            .linear("Kilograms (kg)", 1.0),
            .linear("Metric tonnes (t)", 1000.0),
            .linear("Long tons (2240 lb)", 1016.0469),
            .linear("Short tons (2000 lb)", 907.18474),
            .linear("Pounds (lb)", 0.45359237),
            .linear("Stone", 6.35029318),
            .linear("Grams (g)", 0.001),
        ]),
        ToolUnitCategory(name: "Angle / Bearing", symbol: "safari", units: [                // base: degree
            .linear("Degrees (\u{00B0})", 1.0),
            .linear("Radians", 57.29577951),
            .linear("Gradians (gon)", 0.9),
            .linear("Compass points (32-pt)", 11.25),
            .linear("Mils (NATO, 6400)", 0.05625),
            .linear("Arcminutes (')", 1.0 / 60.0),
        ]),
        ToolUnitCategory(name: "Time", symbol: "clock", units: [                            // base: second
            .linear("Seconds", 1.0),
            .linear("Minutes", 60.0),
            .linear("Hours", 3600.0),
            .linear("Days", 86400.0),
            .linear("Weeks", 604800.0),
            .linear("Watches (4 h)", 14400.0),
        ]),
        ToolUnitCategory(name: "Power", symbol: "bolt", units: [                            // base: watt
            .linear("Kilowatts (kW)", 1000.0),
            .linear("Watts (W)", 1.0),
            .linear("Metric horsepower (PS)", 735.49875),
            .linear("Mechanical horsepower (hp)", 745.699872),
            .linear("BTU per hour", 0.29307107),
        ]),
        ToolUnitCategory(name: "Force", symbol: "arrow.right.to.line", units: [             // base: newton
            .linear("Newtons (N)", 1.0),
            .linear("Kilonewtons (kN)", 1000.0),
            .linear("Tonnes-force (tf)", 9806.65),
            .linear("Kilograms-force (kgf)", 9.80665),
            .linear("Pounds-force (lbf)", 4.4482216),
        ]),
        ToolUnitCategory(name: "Density", symbol: "cube", units: [                          // base: kg/m³
            .linear("Kilograms / m\u{00B3}", 1.0),
            .linear("Grams / cm\u{00B3} (= t/m\u{00B3})", 1000.0),
            .linear("Pounds / cubic foot", 16.018463),
            .linear("Pounds / US gallon", 119.826427),
        ]),
        ToolUnitCategory(name: "Flow rate", symbol: "water.waves", units: [                 // base: m³/hour
            .linear("Cubic metres / hour (m\u{00B3}/h)", 1.0),
            .linear("Cubic metres / day", 1.0 / 24.0),
            .linear("Litres / minute", 0.06),
            .linear("Litres / hour", 0.001),
            .linear("US gallons / minute (GPM)", 0.2271247),
            .linear("Oil barrels / day", 158.987295 / 1000.0 / 24.0),
        ]),
        ToolUnitCategory(name: "Area", symbol: "square.dashed", units: [                    // base: m²
            .linear("Square metres (m\u{00B2})", 1.0),
            .linear("Square kilometres (km\u{00B2})", 1000000.0),
            .linear("Hectares", 10000.0),
            .linear("Square feet (ft\u{00B2})", 0.09290304),
            .linear("Acres", 4046.8564),
        ]),
        ToolUnitCategory(name: "Energy", symbol: "flame", units: [                          // base: joule
            .linear("Kilojoules (kJ)", 1000.0),
            .linear("Joules (J)", 1.0),
            .linear("Kilowatt-hours (kWh)", 3600000.0),
            .linear("Kilocalories (kcal)", 4184.0),
            .linear("BTU", 1055.05585),
        ]),
    ]

    /// The bottom note of the window (TOOLS-080, exact).
    public static let note = "Type a value in any unit \u{2014} every other unit updates instantly. Maritime-focused units included."
}

/// The converter's row texts and edit rules, independent of any UI (TOOLS-082…088).
public struct ToolUnitConverterState: Sendable, Equatable {
    public private(set) var categoryIndex: Int
    /// One text per unit of the current category, in table order.
    public private(set) var texts: [String]

    /// A new window: `Speed`, the first unit seeded with `1` (TOOLS-082, TOOLS-088).
    public init(categoryIndex: Int = 0) {
        self.categoryIndex = 0
        self.texts = []
        selectCategory(categoryIndex)
    }

    public var category: ToolUnitCategory { ToolUnitCatalog.categories[categoryIndex] }

    /// Rebuilds the rows of a category (an out-of-range index is ignored, like `Category_Changed`) and seeds the
    /// first unit with `"1"`, which fills every other row.
    public mutating func selectCategory(_ index: Int) {
        guard index >= 0, index < ToolUnitCatalog.categories.count else { return }
        categoryIndex = index
        texts = Array(repeating: "", count: ToolUnitCatalog.categories[index].units.count)
        if !texts.isEmpty { edit(row: 0, text: "1") }
    }

    /// The user typed `text` into `row`: that row keeps the text; every other row is rewritten from it (or cleared
    /// when the text does not parse).
    public mutating func edit(row: Int, text: String) {
        guard row >= 0, row < texts.count else { return }
        texts[row] = text
        let units = category.units
        guard let v = ToolNetNumber.parseDouble(text) else {
            for i in texts.indices where i != row { texts[i] = "" }
            return
        }
        let base = units[row].toBase(v)
        for i in texts.indices where i != row {
            texts[i] = ToolNetDoubleFormat.unitConverterText(units[i].fromBase(base))
        }
    }
}
