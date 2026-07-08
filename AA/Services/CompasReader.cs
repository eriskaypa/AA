using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using ClosedXML.Excel;

namespace AA.Services;

/// <summary>One COMPAS data row, addressable by (normalised) header name.</summary>
public sealed class CompasRow
{
    private readonly Dictionary<string, string> _values;
    public CompasRow(Dictionary<string, string> values) => _values = values;

    public string Get(string header)
        => _values.TryGetValue(CrewText.Norm(header), out var s) ? s : "";

    public bool Has(string header) => !string.IsNullOrWhiteSpace(Get(header));
}

/// <summary>Reads a COMPAS crew report (sheet 'report') into header-addressable rows. Resilient to
/// column reordering — everything is looked up by header text, not position.</summary>
public static class CompasReader
{
    public static List<CompasRow> Read(string path)
    {
        using var wb = new XLWorkbook(path);
        var ws = wb.Worksheets.FirstOrDefault(w => w.Name.Equals("report", StringComparison.OrdinalIgnoreCase))
                 ?? wb.Worksheets.First();

        var used = ws.RangeUsed();
        if (used == null) return new List<CompasRow>();
        int lastRow = used.LastRow().RowNumber();
        int lastCol = used.LastColumn().ColumnNumber();

        // Locate the header row (the one containing 'first name' and 'surname').
        int headerRow = -1;
        for (int r = 1; r <= Math.Min(lastRow, 20); r++)
        {
            var set = new HashSet<string>();
            for (int c = 1; c <= lastCol; c++)
                set.Add(CrewText.Norm(CellString(ws.Cell(r, c))));
            if (set.Contains("first name") && set.Contains("surname")) { headerRow = r; break; }
        }
        if (headerRow < 0)
            throw new InvalidDataException("Could not find the COMPAS header row (expected 'First name' and 'Surname').");

        var headers = new Dictionary<int, string>();
        for (int c = 1; c <= lastCol; c++)
        {
            var h = CrewText.Norm(CellString(ws.Cell(headerRow, c)));
            if (h.Length > 0) headers[c] = h;
        }

        var rows = new List<CompasRow>();
        for (int r = headerRow + 1; r <= lastRow; r++)
        {
            var dict = new Dictionary<string, string>();
            foreach (var kv in headers)
                dict[kv.Value] = CellString(ws.Cell(r, kv.Key));
            var row = new CompasRow(dict);
            if (row.Has("first name") || row.Has("surname"))
                rows.Add(row);
        }
        return rows;
    }

    /// <summary>Extract a cell as a clean string regardless of stored type.</summary>
    private static string CellString(IXLCell cell)
    {
        if (cell == null || cell.IsEmpty()) return "";
        switch (cell.DataType)
        {
            case XLDataType.Number:
                double d = cell.GetDouble();
                return d == Math.Floor(d)
                    ? ((long)d).ToString(CultureInfo.InvariantCulture)
                    : d.ToString(CultureInfo.InvariantCulture);
            case XLDataType.DateTime:
                return cell.GetDateTime().ToString("yyyy-MM-dd");
            case XLDataType.Boolean:
                return cell.GetBoolean() ? "TRUE" : "FALSE";
            default:
                return cell.GetString().Trim();
        }
    }
}
