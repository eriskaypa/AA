using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using AA.Models;

namespace AA.Services;

/// <summary>Save a crew member's schedule as a reusable template, apply a template to any crew member,
/// and export/import schedule templates as portable JSON files.</summary>
public static class ScheduleService
{
    /// <summary>Copy an entry for reuse — keeps the item link and timing, drops the id and done state.</summary>
    public static ScheduleEntry CloneEntry(ScheduleEntry e) => new()
    {
        Title = e.Title,
        Kind = e.Kind,
        RefId = e.RefId,
        Date = e.Date,
        Time = e.Time,
        EndDate = e.EndDate,
        EndTime = e.EndTime,
        Notes = e.Notes
    };

    public static ScheduleTemplate CaptureFromCrew(string name, CrewMember crew, AppData data)
    {
        var t = new ScheduleTemplate { Name = name.Trim(), VesselId = crew.ScheduleVesselId };
        t.VesselName = crew.ScheduleVesselId is Guid vid ? data.Vessels.FirstOrDefault(v => v.Id == vid)?.Name ?? "" : "";
        foreach (var e in crew.Schedule) t.Entries.Add(CloneEntry(e));
        return t;
    }

    /// <summary>Apply a saved schedule to a crew member (append or replace). Returns the entry count.</summary>
    public static int ApplyToCrew(ScheduleTemplate t, CrewMember crew, bool replace)
    {
        if (replace) crew.Schedule.Clear();
        foreach (var e in t.Entries) crew.Schedule.Add(CloneEntry(e));
        if (t.VesselId is Guid) crew.ScheduleVesselId = t.VesselId;
        return t.Entries.Count;
    }

    public static void ExportJson(ScheduleTemplate t, string path)
    {
        File.WriteAllText(path, JsonSerializer.Serialize(t, new JsonSerializerOptions { WriteIndented = true }));
    }

    public static ScheduleTemplate ImportJson(string path)
    {
        var t = JsonSerializer.Deserialize<ScheduleTemplate>(File.ReadAllText(path))
                ?? throw new InvalidDataException("This file is not a valid schedule.");
        // Fresh ids so importing never collides with existing data.
        t.Id = Guid.NewGuid();
        foreach (var e in t.Entries) e.Id = Guid.NewGuid();
        return t;
    }
}
