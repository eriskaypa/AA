// Spec: DECISIONS "Stage V rulings" (date pickers show ISO dates), ARCHITECTURE.md §9.8 (as amended), AA Mac design
//       rule 14 (ISO yyyy-MM-dd everywhere, date pickers included; weekday and month names in chrome follow
//       Locale.current).
import Foundation

/// The locale every numeric date picker uses so it displays `yyyy-MM-dd` like the rest of the app. It is applied to
/// the picker only (`View.aaISODatePicker()`); stored values and the Gregorian calendar are unchanged.
public enum ShellDateDisplay {
    public static let pickerLocaleIdentifier = "en_CA"
    public static var pickerLocale: Locale { Locale(identifier: pickerLocaleIdentifier) }

    /// What a field-style picker shows for `date` (its short date style), for tests and diagnostics.
    public static func pickerText(_ date: Date, zone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = pickerLocale
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        f.calendar = cal
        f.timeZone = zone
        f.dateStyle = .short
        f.timeStyle = .none
        return f.string(from: date)
    }
}
