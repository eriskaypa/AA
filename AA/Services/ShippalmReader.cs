using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using AA.Models;
using ClosedXML.Excel;

namespace AA.Services;

/// <summary>Reads a Shippalm "Work Order List" export (.xlsx) into <see cref="ShipJob"/> records.
/// Columns are matched by header text (resilient to reordering); Excel date serials in the date
/// columns are converted to yyyy-MM-dd. Keyed by the "No." column (the job number).</summary>
public static class ShippalmReader
{
    public static List<ShipJob> Read(string path)
    {
        using var wb = new XLWorkbook(path);
        // The export has a single sheet holding a table; take the first worksheet with data.
        var ws = wb.Worksheets.FirstOrDefault(w => w.RangeUsed() != null) ?? wb.Worksheets.First();
        var used = ws.RangeUsed();
        if (used == null) return new List<ShipJob>();
        int lastRow = used.LastRow().RowNumber();
        int firstRow = used.FirstRow().RowNumber();
        int lastCol = used.LastColumn().ColumnNumber();
        int firstCol = used.FirstColumn().ColumnNumber();

        // Locate the header row (the one containing 'no.' and 'title').
        int headerRow = -1;
        for (int r = firstRow; r <= Math.Min(lastRow, firstRow + 15); r++)
        {
            bool hasNo = false, hasTitle = false;
            for (int c = firstCol; c <= lastCol; c++)
            {
                var h = CrewText.Norm(Cell(ws, r, c));
                if (h == "no.") hasNo = true;
                else if (h == "title") hasTitle = true;
            }
            if (hasNo && hasTitle) { headerRow = r; break; }
        }
        if (headerRow < 0)
            throw new InvalidDataException("Could not find the Shippalm header row (expected 'No.' and 'Title').");

        var col = new Dictionary<string, int>();
        for (int c = firstCol; c <= lastCol; c++)
        {
            var h = CrewText.Norm(Cell(ws, headerRow, c));
            if (h.Length > 0 && !col.ContainsKey(h)) col[h] = c;
        }
        int Col(string name) => col.TryGetValue(CrewText.Norm(name), out var c) ? c : -1;

        var imported = DateTime.Now.ToString("yyyy-MM-dd HH:mm");
        var list = new List<ShipJob>();
        for (int r = headerRow + 1; r <= lastRow; r++)
        {
            string G(string name) { var c = Col(name); return c < 0 ? "" : Cell(ws, r, c); }
            var no = G("No.").Trim();
            if (string.IsNullOrWhiteSpace(no)) continue;
            int.TryParse(G("Overdue Days"), NumberStyles.Any, CultureInfo.InvariantCulture, out var od);
            list.Add(new ShipJob
            {
                JobNo = no,
                Title = G("Title"),
                WorkPlanNo = G("Work Plan No."),
                Status = G("Work Order Status"),
                ClassCode = G("Class Code"),
                Category = G("Work Order Category Code"),
                ResponsibleRank = G("Responsible Rank"),
                FunctionNo = G("Function No."),
                FunctionDescription = G("Function Description"),
                Interval = G("Interval"),
                DueStatus = G("Due Status"),
                DueDate = ExcelDate(G("Due Date")),
                FinishedDate = ExcelDate(G("Finished Date-Time")),
                LastDoneDate = ExcelDate(G("Last Done Date")),
                OverdueDays = od,
                Notify = ParseBool(G("Notify")),   // present in AA's own exports; absent in raw Shippalm files
                ImportedAt = imported,
            });
        }
        return list;
    }

    /// <summary>Export a vessel's work orders to an .xlsx whose headers match what <see cref="Read"/>
    /// expects, so it round-trips (including each job's Notify choice) back into any ship.</summary>
    public static void Write(IReadOnlyList<ShipJob> jobs, string path)
    {
        using var wb = new XLWorkbook();
        var ws = wb.AddWorksheet("report");
        var headers = new[]
        {
            "No.", "Title", "Work Plan No.", "Work Order Status", "Class Code", "Work Order Category Code",
            "Responsible Rank", "Finished Date-Time", "Due Date", "Interval", "Function Description",
            "Due Status", "Function No.", "Last Done Date", "Overdue Days", "Notify",
        };
        for (int c = 0; c < headers.Length; c++) ws.Cell(1, c + 1).Value = headers[c];
        ws.Row(1).Style.Font.Bold = true;

        int r = 2;
        foreach (var j in jobs)
        {
            int c = 1;
            ws.Cell(r, c++).Value = j.JobNo;
            ws.Cell(r, c++).Value = j.Title;
            ws.Cell(r, c++).Value = j.WorkPlanNo;
            ws.Cell(r, c++).Value = j.Status;
            ws.Cell(r, c++).Value = j.ClassCode;
            ws.Cell(r, c++).Value = j.Category;
            ws.Cell(r, c++).Value = j.ResponsibleRank;
            ws.Cell(r, c++).Value = j.FinishedDate;
            ws.Cell(r, c++).Value = j.DueDate;         // kept as yyyy-MM-dd text so it re-reads cleanly
            ws.Cell(r, c++).Value = j.Interval;
            ws.Cell(r, c++).Value = j.FunctionDescription;
            ws.Cell(r, c++).Value = j.DueStatus;
            ws.Cell(r, c++).Value = j.FunctionNo;
            ws.Cell(r, c++).Value = j.LastDoneDate;
            ws.Cell(r, c++).Value = j.OverdueDays;
            ws.Cell(r, c++).Value = j.Notify ? "Yes" : "No";
            r++;
        }
        ws.Column(9).Style.NumberFormat.Format = "@";   // keep Due Date column as text
        ws.Column(14).Style.NumberFormat.Format = "@";  // keep Last Done Date column as text
        ws.Columns().AdjustToContents();
        wb.SaveAs(path);
    }

    private static bool ParseBool(string s)
    {
        s = (s ?? "").Trim();
        return s.Equals("yes", StringComparison.OrdinalIgnoreCase)
            || s.Equals("true", StringComparison.OrdinalIgnoreCase)
            || s == "1"
            || s.Equals("y", StringComparison.OrdinalIgnoreCase);
    }

    private static string Cell(IXLWorksheet ws, int r, int c)
    {
        var cell = ws.Cell(r, c);
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

    /// <summary>Convert a Shippalm date value to yyyy-MM-dd. Handles already-formatted dates and
    /// bare Excel date serials (e.g. 48108) that come through unformatted.</summary>
    private static string ExcelDate(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return "";
        raw = raw.Trim();
        var parsed = CrewMember.ParseDate(raw);
        if (parsed != null) return parsed.Value.ToString("yyyy-MM-dd");
        if (double.TryParse(raw, NumberStyles.Any, CultureInfo.InvariantCulture, out var serial)
            && serial > 20000 && serial < 200000)
        {
            try { return DateTime.FromOADate(serial).ToString("yyyy-MM-dd"); } catch { }
        }
        return raw;
    }
}
