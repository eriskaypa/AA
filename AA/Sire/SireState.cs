using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json.Serialization;

namespace AA.Sire;

/// <summary>A user task attached to a SIRE question, persisted with the AA database.</summary>
public class SireTask
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string QuestionNumber { get; set; } = "";
    public string Text { get; set; } = "";
    public bool IsCompleted { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.Now;
}

/// <summary>The SIRE inspection session state (per-question status, bookmarks, for-export flags and
/// tasks), stored inside <see cref="AA.Models.AppData"/> so it persists, backs up and syncs like the rest
/// of the app — no separate .sire file needed (though .sire import/export is offered for interop).</summary>
public class SireState
{
    public Dictionary<string, string> QuestionStatuses { get; set; } = new();
    public List<string> Bookmarks { get; set; } = new();
    public List<string> ForExport { get; set; } = new();
    public List<SireTask> Tasks { get; set; } = new();
    /// <summary>Per-question edited body (AA rich-text / Section XAML), keyed by question number. Set when
    /// the user edits the question body in the SIRE tab (line breaks, re-wording, formatting). Absent = show
    /// the generated original. Persists with the database so edits are saved and synced.</summary>
    public Dictionary<string, string> QuestionBodies { get; set; } = new();

    public QuestionStatus GetStatus(string q) =>
        QuestionStatuses.TryGetValue(q, out var s) && Enum.TryParse<QuestionStatus>(s, out var v) ? v : QuestionStatus.None;

    public void SetStatus(string q, QuestionStatus status)
    {
        if (status == QuestionStatus.None) QuestionStatuses.Remove(q);
        else QuestionStatuses[q] = status.ToString();
    }

    public int CountByStatus(QuestionStatus status)
    {
        var s = status.ToString();
        return QuestionStatuses.Count(kv => kv.Value == s);
    }

    public bool IsBookmarked(string q) => Bookmarks.Contains(q);
    public void ToggleBookmark(string q) { if (!Bookmarks.Remove(q)) Bookmarks.Add(q); }

    public bool IsForExport(string q) => ForExport.Contains(q);
    public void ToggleForExport(string q) { if (!ForExport.Remove(q)) ForExport.Add(q); }

    public List<SireTask> GetTasksForQuestion(string q) => Tasks.Where(t => t.QuestionNumber == q).ToList();

    [JsonIgnore] public int TotalTaskCount => Tasks.Count;
    [JsonIgnore] public int CompletedTaskCount => Tasks.Count(t => t.IsCompleted);
}
