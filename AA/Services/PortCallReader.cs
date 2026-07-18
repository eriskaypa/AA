using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using AA.Models;
using ClosedXML.Excel;

namespace AA.Services;

/// <summary>Reads a "ports of call" Excel export into <see cref="PortCall"/> rows. Auto-detects the two
/// supported layouts:
///   A — "Last Ports of Call - 2 Years": No | Port Name, Country | Date Arrived | Date Departured |
///       Security level in Port | on Vessel | SSP followed | Special measures (dates only, no times).
///   B — "Port of Call List - Last 10 Ports": a Vessel Name / IMO / Call sign header, then a two-row
///       header with Port Name, UN/LOCODE, Port Facility, Security Level (PF/Vessel), Arrival Date+Time,
///       Departure Date+Time, Special measures.</summary>
public static class PortCallReader
{
    public sealed class Result
    {
        public List<PortCall> Calls { get; } = new();
        public string VesselName { get; set; } = "";
        public string Imo { get; set; } = "";
        public string CallSign { get; set; } = "";
        public string Format { get; set; } = "";
    }

    public static Result Read(string path)
    {
        using var wb = new XLWorkbook(path);
        var ws = wb.Worksheets.FirstOrDefault(w => w.RangeUsed() != null) ?? wb.Worksheet(1);
        var used = ws.RangeUsed() ?? throw new InvalidDataException("The workbook is empty.");
        int firstRow = used.FirstRow().RowNumber(), lastRow = used.LastRow().RowNumber();
        int firstCol = used.FirstColumn().ColumnNumber(), lastCol = used.LastColumn().ColumnNumber();

        bool looksA = false, looksB = false;
        string vesselName = "", imo = "", callSign = "";
        for (int r = firstRow; r <= Math.Min(lastRow, firstRow + 12); r++)
            for (int c = firstCol; c <= lastCol; c++)
            {
                var v = Cell(ws, r, c);
                var lv = v.ToLowerInvariant();
                if (lv.Contains("un locator") || lv.Contains("un/locode") || lv.Contains("port of call list")) looksB = true;
                if (lv.Contains("date arrived") || lv.Contains("port name, country") || lv.Contains("last ports of call")) looksA = true;
                if (lv == "vessel name" && vesselName.Length == 0) vesselName = NextValue(ws, r, c, lastCol);
                if (lv.Contains("imo number") && imo.Length == 0) imo = NextValue(ws, r, c, lastCol);
                if (lv.Contains("call sign") && callSign.Length == 0) callSign = NextValue(ws, r, c, lastCol);
            }

        Result result;
        if (looksB && !looksA) result = ReadFormatB(ws, firstRow, lastRow, firstCol, lastCol);
        else if (looksA) result = ReadFormatA(ws, firstRow, lastRow, firstCol, lastCol);
        else if (looksB) result = ReadFormatB(ws, firstRow, lastRow, firstCol, lastCol);
        else throw new InvalidDataException(
            "Couldn't recognise this as a ports-of-call list. Expected either a 'Last Ports of Call' sheet " +
            "or a 'Port of Call List' sheet with an Arrival/Departure header.");

        result.VesselName = vesselName;
        result.Imo = imo;
        result.CallSign = callSign;
        var stamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm");
        foreach (var call in result.Calls) call.ImportedAt = stamp;
        return result;
    }

    // ---- Format A ----
    private static Result ReadFormatA(IXLWorksheet ws, int firstRow, int lastRow, int firstCol, int lastCol)
    {
        int hdr = FindRow(ws, firstRow, lastRow, firstCol, lastCol, "port name");
        if (hdr < 0) throw new InvalidDataException("Could not find the 'Port Name' header row.");

        int portCol = -1, arrCol = -1, depCol = -1, secPortCol = -1, secVesselCol = -1, sspCol = -1, specialCol = -1;
        for (int c = firstCol; c <= lastCol; c++)
        {
            var h = Cell(ws, hdr, c).ToLowerInvariant();
            if (h.Length == 0) continue;
            if (h.Contains("port name")) portCol = c;
            else if (h.Contains("date arrived")) arrCol = c;
            else if (h.Contains("date depart")) depCol = c;
            else if (h.Contains("security level in port")) secPortCol = c;
            else if (h.Contains("security level on vessel")) secVesselCol = c;
            else if (h.Contains("appropriate measures") || h.Contains("ssp")) sspCol = c;
            else if (h.Contains("special security")) specialCol = c;
        }
        if (portCol < 0) throw new InvalidDataException("Could not find the port-name column.");

        var res = new Result { Format = "Last Ports of Call (2 years)" };
        for (int r = hdr + 1; r <= lastRow; r++)
        {
            var raw = Cell(ws, r, portCol);
            if (raw.Length == 0) continue;
            var (name, country) = SplitPort(raw);
            res.Calls.Add(new PortCall
            {
                PortName = name,
                Country = country,
                ArrivalDate = arrCol > 0 ? NormDate(Cell(ws, r, arrCol)) : "",
                DepartureDate = depCol > 0 ? NormDate(Cell(ws, r, depCol)) : "",
                SecurityLevelPort = secPortCol > 0 ? Cell(ws, r, secPortCol) : "",
                SecurityLevelVessel = secVesselCol > 0 ? Cell(ws, r, secVesselCol) : "",
                SspFollowed = sspCol > 0 ? Cell(ws, r, sspCol) : "",
                SpecialMeasures = specialCol > 0 ? Cell(ws, r, specialCol) : "",
            });
        }
        return res;
    }

    // ---- Format B ----
    private static Result ReadFormatB(IXLWorksheet ws, int firstRow, int lastRow, int firstCol, int lastCol)
    {
        int subRow = FindRow(ws, firstRow, lastRow, firstCol, lastCol, "un locator");
        if (subRow < 0) subRow = FindRow(ws, firstRow, lastRow, firstCol, lastCol, "un/locode");
        if (subRow < 0) throw new InvalidDataException("Could not find the 'UN locator' header row.");
        int catRow = subRow - 1;

        int portNameCol = -1, unlocodeCol = -1, facilityCol = -1, pfNoCol = -1,
            secPortCol = -1, secVesselCol = -1, arrDateCol = -1, arrTimeCol = -1,
            depDateCol = -1, depTimeCol = -1, specialCol = -1;
        string cat = "";
        for (int c = firstCol; c <= lastCol; c++)
        {
            var catRaw = catRow >= firstRow ? Cell(ws, catRow, c) : "";
            if (catRaw.Length > 0) cat = catRaw.ToLowerInvariant();
            var sub = Cell(ws, subRow, c).ToLowerInvariant();

            if (cat.Contains("port facility"))
            {
                if (sub.Contains("name")) facilityCol = c;
                else if (sub.Contains("pf no")) pfNoCol = c;
            }
            else if (cat.StartsWith("port"))
            {
                if (sub.Contains("name")) portNameCol = c;
                else if (sub.Contains("un locator") || sub.Contains("locode")) unlocodeCol = c;
            }
            else if (cat.Contains("security level"))
            {
                if (sub.Contains("vessel")) secVesselCol = c;
                else if (sub.Length > 0) secPortCol = c;   // "PF"
            }
            else if (cat.Contains("arrival"))
            {
                if (sub.Contains("date")) arrDateCol = c;
                else if (sub.Contains("time")) arrTimeCol = c;
            }
            else if (cat.Contains("departure"))
            {
                if (sub.Contains("date")) depDateCol = c;
                else if (sub.Contains("time")) depTimeCol = c;
            }
            else if (cat.Contains("special"))
            {
                specialCol = c;
            }
        }
        if (portNameCol < 0) portNameCol = firstCol;

        var res = new Result { Format = "Port of Call List (last 10 ports)" };
        for (int r = subRow + 1; r <= lastRow; r++)
        {
            var name = Cell(ws, r, portNameCol);
            if (name.Length == 0) continue;
            res.Calls.Add(new PortCall
            {
                PortName = name,
                UnLocode = unlocodeCol > 0 ? Cell(ws, r, unlocodeCol) : "",
                PortFacility = facilityCol > 0 ? Cell(ws, r, facilityCol) : "",
                PfNo = pfNoCol > 0 ? Cell(ws, r, pfNoCol) : "",
                SecurityLevelPort = secPortCol > 0 ? Cell(ws, r, secPortCol) : "",
                SecurityLevelVessel = secVesselCol > 0 ? Cell(ws, r, secVesselCol) : "",
                ArrivalDate = arrDateCol > 0 ? NormDate(Cell(ws, r, arrDateCol)) : "",
                ArrivalTime = arrTimeCol > 0 ? NormTime(Cell(ws, r, arrTimeCol)) : "",
                DepartureDate = depDateCol > 0 ? NormDate(Cell(ws, r, depDateCol)) : "",
                DepartureTime = depTimeCol > 0 ? NormTime(Cell(ws, r, depTimeCol)) : "",
                SpecialMeasures = specialCol > 0 ? Cell(ws, r, specialCol) : "",
            });
        }
        return res;
    }

    // ---- helpers ----
    private static int FindRow(IXLWorksheet ws, int firstRow, int lastRow, int firstCol, int lastCol, string needle)
    {
        for (int r = firstRow; r <= lastRow; r++)
            for (int c = firstCol; c <= lastCol; c++)
                if (Cell(ws, r, c).ToLowerInvariant().Contains(needle)) return r;
        return -1;
    }

    private static string NextValue(IXLWorksheet ws, int r, int c, int lastCol)
    {
        for (int cc = c + 1; cc <= lastCol; cc++)
        {
            var v = Cell(ws, r, cc);
            if (v.Length > 0) return v;
        }
        return "";
    }

    private static (string name, string country) SplitPort(string s)
    {
        var i = s.LastIndexOf(',');
        return i < 0 ? (s.Trim(), "") : (s[..i].Trim(), s[(i + 1)..].Trim());
    }

    private static string Cell(IXLWorksheet ws, int r, int c)
    {
        var cell = ws.Cell(r, c);
        if (cell.IsEmpty()) return "";
        return cell.DataType switch
        {
            XLDataType.DateTime => cell.GetDateTime() is var d && d.TimeOfDay == TimeSpan.Zero
                ? d.ToString("yyyy-MM-dd") : d.ToString("yyyy-MM-dd HH:mm"),
            XLDataType.TimeSpan => cell.GetTimeSpan().ToString(@"hh\:mm"),
            XLDataType.Number => cell.GetDouble().ToString("0.####", CultureInfo.InvariantCulture),
            _ => cell.GetString().Trim()
        };
    }

    private static string NormDate(string s)
    {
        s = s.Trim();
        if (s.Length == 0) return "";
        var m = Regex.Match(s, @"^(\d{4})-(\d{1,2})-(\d{1,2})");
        if (m.Success && int.TryParse(m.Groups[2].Value, out var mo1) && int.TryParse(m.Groups[3].Value, out var d1))
            try { return new DateTime(int.Parse(m.Groups[1].Value), mo1, d1).ToString("yyyy-MM-dd"); } catch { }
        m = Regex.Match(s, @"^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})");
        if (m.Success)
        {
            int d = int.Parse(m.Groups[1].Value), mo = int.Parse(m.Groups[2].Value), y = int.Parse(m.Groups[3].Value);
            if (y < 100) y += 2000;
            try { return new DateTime(y, mo, d).ToString("yyyy-MM-dd"); } catch { }
        }
        if (DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.None, out var dt)) return dt.ToString("yyyy-MM-dd");
        return s;
    }

    private static string NormTime(string s)
    {
        s = s.Trim();
        var m = Regex.Match(s, @"(\d{1,2}):(\d{2})");
        return m.Success ? $"{int.Parse(m.Groups[1].Value):00}:{m.Groups[2].Value}" : "";
    }
}
