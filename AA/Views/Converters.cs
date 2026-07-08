using System;
using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace AA.Views;

/// <summary>true → a strikethrough decoration; false/null → none. Used to cross out
/// completed checklist steps / tasks throughout the UI.</summary>
public sealed class BoolToStrikethroughConverter : IValueConverter
{
    public static readonly BoolToStrikethroughConverter Instance = new();

    public object? Convert(object value, Type targetType, object parameter, CultureInfo culture)
        => value is true ? TextDecorations.Strikethrough : null;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => throw new NotSupportedException();
}
