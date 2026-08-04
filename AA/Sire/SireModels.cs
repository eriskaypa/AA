using System.Collections.Generic;
using System.ComponentModel;
using System.Text.Json.Serialization;

namespace AA.Sire;

/// <summary>Per-question inspection status within a SIRE session.</summary>
public enum QuestionStatus { None, InProgress, Checked, NotApplicable }

/// <summary>Root of the embedded SIRE 2.0 question bank JSON (OCIMF question library).</summary>
public class QuestionBank
{
    [JsonPropertyName("metadata")] public BankMetadata Metadata { get; set; } = new();
    [JsonPropertyName("questions")] public List<SireQuestion> Questions { get; set; } = new();
}

public class BankMetadata
{
    [JsonPropertyName("title")] public string Title { get; set; } = "";
    [JsonPropertyName("version")] public string Version { get; set; } = "";
    [JsonPropertyName("date")] public string Date { get; set; } = "";
    [JsonPropertyName("source")] public string Source { get; set; } = "";
    [JsonPropertyName("total_questions")] public int TotalQuestions { get; set; }
}

/// <summary>One SIRE 2.0 question with all parsed sections, plus runtime session-state flags
/// (status / bookmark / for-export / selected) used to badge the list.</summary>
public class SireQuestion : INotifyPropertyChanged
{
    [JsonPropertyName("question_number")] public string QuestionNumber { get; set; } = "";
    [JsonPropertyName("chapter")] public string Chapter { get; set; } = "";
    [JsonPropertyName("section")] public string Section { get; set; } = "";
    [JsonPropertyName("chapter_name")] public string ChapterName { get; set; } = "";
    [JsonPropertyName("type")] public string Type { get; set; } = "";
    [JsonPropertyName("full_question_text")] public string FullQuestionText { get; set; } = "";
    [JsonPropertyName("short_question_text")] public string ShortQuestionText { get; set; } = "";
    [JsonPropertyName("vessel_types")] public List<string> VesselTypes { get; set; } = new();
    [JsonPropertyName("roviq_sequence")] public string RoviqSequence { get; set; } = "";
    [JsonPropertyName("publications")] public string Publications { get; set; } = "";
    [JsonPropertyName("objective")] public string Objective { get; set; } = "";
    [JsonPropertyName("industry_guidance")] public string IndustryGuidance { get; set; } = "";
    [JsonPropertyName("inspection_guidance")] public string InspectionGuidance { get; set; } = "";
    [JsonPropertyName("suggested_inspector_actions")] public string SuggestedInspectorActions { get; set; } = "";
    [JsonPropertyName("expected_evidence")] public string ExpectedEvidence { get; set; } = "";
    [JsonPropertyName("potential_negative_observation_grounds")] public string PotentialNegativeObservationGrounds { get; set; } = "";
    [JsonPropertyName("data_source")] public string DataSource { get; set; } = "";

    // --- Computed display properties ---
    [JsonIgnore] public string VesselTypesDisplay => VesselTypes.Count > 0 ? string.Join(", ", VesselTypes) : "All";
    [JsonIgnore] public string ChapterDisplay => $"Ch {Chapter}: {ChapterName}";
    [JsonIgnore] public string QuestionTypeDisplay => Type switch
    {
        "data_field" => "Data Field",
        "inspection_question" when FullQuestionText.Contains("photograph", System.StringComparison.OrdinalIgnoreCase) => "Photograph",
        "inspection_question" => "Inspection",
        _ => Type
    };
    [JsonIgnore] public string ListTitle => $"Q {QuestionNumber} — {ShortQuestionText}";

    /// <summary>Smart tags (Equipment/Document/Procedure/Record/Personnel) extracted at load.</summary>
    [JsonIgnore] public List<string> EvidenceTags { get; set; } = new();
    /// <summary>ROVIQ locations split from the sequence string, for filtering.</summary>
    [JsonIgnore] public List<string> RoviqLocations { get; set; } = new();

    /// <summary>True when this question has the full detailed section set (not a Ch1 data field or a
    /// minimal Ch11 photo question) — the ones the task engine and AI can meaningfully act on.</summary>
    [JsonIgnore] public bool IsDetailedQuestion => Type == "inspection_question" && !string.IsNullOrEmpty(Objective);

    // --- Runtime session-state (bound to the list for badges; persisted separately in SireState) ---
    private QuestionStatus _status;
    private bool _isBookmarked, _isForExport, _isSelected;

    [JsonIgnore] public QuestionStatus Status { get => _status; set { if (_status != value) { _status = value; Raise(nameof(Status)); Raise(nameof(StatusDisplay)); Raise(nameof(HasStatus)); } } }
    [JsonIgnore] public string StatusDisplay => Status switch { QuestionStatus.InProgress => "In Progress", QuestionStatus.Checked => "Checked", QuestionStatus.NotApplicable => "N/A", _ => "" };
    [JsonIgnore] public bool HasStatus => Status != QuestionStatus.None;
    [JsonIgnore] public bool IsBookmarked { get => _isBookmarked; set { _isBookmarked = value; Raise(nameof(IsBookmarked)); } }
    [JsonIgnore] public bool IsForExport { get => _isForExport; set { _isForExport = value; Raise(nameof(IsForExport)); } }
    [JsonIgnore] public bool IsSelected { get => _isSelected; set { _isSelected = value; Raise(nameof(IsSelected)); } }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void Raise(string n) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(n));
}

/// <summary>Natural sort for question numbers like "1.1.1", "2.3.10", "11.1.95".</summary>
public sealed class QuestionNumberComparer : IComparer<string>
{
    public static readonly QuestionNumberComparer Instance = new();
    public int Compare(string? x, string? y)
    {
        if (x == y) return 0;
        if (x == null) return -1;
        if (y == null) return 1;
        var px = System.Array.ConvertAll(x.Split('.'), p => int.TryParse(p, out var n) ? n : 0);
        var py = System.Array.ConvertAll(y.Split('.'), p => int.TryParse(p, out var n) ? n : 0);
        for (int i = 0; i < System.Math.Max(px.Length, py.Length); i++)
        {
            int a = i < px.Length ? px[i] : 0, b = i < py.Length ? py[i] : 0;
            int c = a.CompareTo(b);
            if (c != 0) return c;
        }
        return 0;
    }
}
