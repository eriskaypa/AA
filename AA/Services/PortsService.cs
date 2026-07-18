using System;
using System.Collections.Generic;
using System.Linq;
using AA.Models;
using ClosedXML.Excel;

namespace AA.Services;

/// <summary>Applies imported ports of call to (a) a vessel's own port list and (b) the global ports
/// database (which vessel called each port and when), and exports a vessel's ports to Excel.</summary>
public static class PortsService
{
    public static (int addedCalls, int updatedCalls, int newVisits) Apply(AppData data, Vessel vessel, IEnumerable<PortCall> calls)
    {
        const StringComparison oic = StringComparison.OrdinalIgnoreCase;
        int added = 0, updated = 0, newVisits = 0;

        var byKey = new Dictionary<string, PortCall>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in vessel.PortCalls) byKey[p.Key] = p;

        foreach (var call in calls)
        {
            // (a) vessel's own port list — upsert by port+arrival key.
            if (byKey.TryGetValue(call.Key, out var existing)) { CopyInto(existing, call); updated++; }
            else { vessel.PortCalls.Add(call); byKey[call.Key] = call; added++; }

            // (b) global ports database — match by UN/LOCODE, else by name (+ compatible country).
            var port = data.Ports.FirstOrDefault(p =>
                (call.UnLocode.Length > 0 && p.UnLocode.Equals(call.UnLocode, oic)) ||
                (p.Name.Equals(call.PortName, oic) &&
                 (p.Country.Length == 0 || call.Country.Length == 0 || p.Country.Equals(call.Country, oic))));
            if (port == null)
            {
                port = new Port { Name = call.PortName, Country = call.Country, UnLocode = call.UnLocode };
                data.Ports.Add(port);
            }
            else
            {
                if (port.UnLocode.Length == 0 && call.UnLocode.Length > 0) port.UnLocode = call.UnLocode;
                if (port.Country.Length == 0 && call.Country.Length > 0) port.Country = call.Country;
            }

            // One visit per (this vessel, arrival date). Enrich an existing visit (e.g. add times) rather
            // than adding a duplicate when the other format is imported later.
            var existingVisit = port.Visits.FirstOrDefault(v =>
                (v.VesselId == vessel.Id || v.VesselName.Equals(vessel.Name, oic)) && v.ArrivalDate == call.ArrivalDate);
            if (existingVisit == null)
            {
                port.Visits.Add(new PortVisit
                {
                    VesselName = vessel.Name,
                    VesselId = vessel.Id,
                    ArrivalDate = call.ArrivalDate,
                    ArrivalTime = call.ArrivalTime,
                    DepartureDate = call.DepartureDate,
                    DepartureTime = call.DepartureTime,
                    ImportedAt = call.ImportedAt
                });
                newVisits++;
            }
            else
            {
                existingVisit.VesselId ??= vessel.Id;
                if (existingVisit.ArrivalTime.Length == 0) existingVisit.ArrivalTime = call.ArrivalTime;
                if (existingVisit.DepartureDate.Length == 0) existingVisit.DepartureDate = call.DepartureDate;
                if (existingVisit.DepartureTime.Length == 0) existingVisit.DepartureTime = call.DepartureTime;
            }
        }
        return (added, updated, newVisits);
    }

    /// <summary>Remove a vessel's port call AND the matching visit in the global ports database.</summary>
    public static void RemoveCall(AppData data, Vessel vessel, PortCall call)
    {
        vessel.PortCalls.Remove(call);
        var vk = $"{vessel.Name}|{call.ArrivalDate}|{call.ArrivalTime}".ToLowerInvariant();
        foreach (var port in data.Ports)
        {
            var visit = port.Visits.FirstOrDefault(v =>
                (v.VesselId == vessel.Id || v.VesselName.Equals(vessel.Name, StringComparison.OrdinalIgnoreCase))
                && v.VisitKey == vk);
            if (visit != null) port.Visits.Remove(visit);
        }
        // Drop ports left with no visits.
        for (int i = data.Ports.Count - 1; i >= 0; i--)
            if (data.Ports[i].Visits.Count == 0) data.Ports.RemoveAt(i);
    }

    // Merge src into dst: always take the required fields, but only overwrite optional fields when the
    // incoming value is non-empty (so importing the times-only format doesn't blank the other's fields).
    private static void CopyInto(PortCall dst, PortCall src)
    {
        dst.PortName = src.PortName;
        static string Keep(string incoming, string existing) => incoming.Length > 0 ? incoming : existing;
        dst.Country = Keep(src.Country, dst.Country);
        dst.UnLocode = Keep(src.UnLocode, dst.UnLocode);
        dst.PortFacility = Keep(src.PortFacility, dst.PortFacility);
        dst.PfNo = Keep(src.PfNo, dst.PfNo);
        dst.ArrivalTime = Keep(src.ArrivalTime, dst.ArrivalTime);
        dst.DepartureDate = Keep(src.DepartureDate, dst.DepartureDate);
        dst.DepartureTime = Keep(src.DepartureTime, dst.DepartureTime);
        dst.SecurityLevelPort = Keep(src.SecurityLevelPort, dst.SecurityLevelPort);
        dst.SecurityLevelVessel = Keep(src.SecurityLevelVessel, dst.SecurityLevelVessel);
        dst.SspFollowed = Keep(src.SspFollowed, dst.SspFollowed);
        dst.SpecialMeasures = Keep(src.SpecialMeasures, dst.SpecialMeasures);
        dst.ImportedAt = src.ImportedAt;
    }

    // ---- Excel export of a vessel's ports ----
    public static void Export(Vessel vessel, string path)
    {
        using var wb = new XLWorkbook();
        var ws = wb.AddWorksheet("Ports of Call");
        string[] headers =
        {
            "Port", "Country", "UN/LOCODE", "Port Facility", "PF no.",
            "Arrival Date", "Arrival Time", "Departure Date", "Departure Time",
            "Sec. Port", "Sec. Vessel", "SSP", "Special measures"
        };
        for (int i = 0; i < headers.Length; i++)
        {
            var h = ws.Cell(1, i + 1);
            h.Value = headers[i];
            h.Style.Font.Bold = true;
        }
        int r = 2;
        foreach (var c in vessel.PortCalls.OrderByDescending(c => c.ArrivalValue ?? DateTime.MinValue))
        {
            ws.Cell(r, 1).Value = c.PortName;
            ws.Cell(r, 2).Value = c.Country;
            ws.Cell(r, 3).Value = c.UnLocode;
            ws.Cell(r, 4).Value = c.PortFacility;
            ws.Cell(r, 5).Value = c.PfNo;
            ws.Cell(r, 6).Value = c.ArrivalDate;
            ws.Cell(r, 7).Value = c.ArrivalTime;
            ws.Cell(r, 8).Value = c.DepartureDate;
            ws.Cell(r, 9).Value = c.DepartureTime;
            ws.Cell(r, 10).Value = c.SecurityLevelPort;
            ws.Cell(r, 11).Value = c.SecurityLevelVessel;
            ws.Cell(r, 12).Value = c.SspFollowed;
            ws.Cell(r, 13).Value = c.SpecialMeasures;
            r++;
        }
        ws.Columns().AdjustToContents();
        wb.SaveAs(path);
    }
}
