using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Windows;

namespace AA.Sire;

/// <summary>Loads the embedded SIRE 2.0 question bank once, enriches each question with evidence tags and
/// ROVIQ locations, and runs the offline task-identifier so the generated tasks are available in AA (the
/// standalone app re-derives these at runtime and never stores them — here we regenerate them the same
/// way). Cached for the process lifetime.</summary>
public static class SireBank
{
    private static readonly object _gate = new();
    private static List<SireQuestion>? _questions;
    private static Dictionary<string, List<string>>? _identified;
    public static BankMetadata Metadata { get; private set; } = new();
    public static string? LoadError { get; private set; }

    public static bool IsLoaded => _questions != null;

    /// <summary>All 410 questions (empty on load failure — see <see cref="LoadError"/>).</summary>
    public static IReadOnlyList<SireQuestion> Questions
    {
        get { EnsureLoaded(); return _questions ?? (IReadOnlyList<SireQuestion>)Array.Empty<SireQuestion>(); }
    }

    /// <summary>Offline-identified tasks per question number.</summary>
    public static Dictionary<string, List<string>> IdentifiedTasks
    {
        get { EnsureLoaded(); return _identified ?? new(); }
    }

    public static List<string> GetIdentifiedTasks(string questionNumber)
        => IdentifiedTasks.TryGetValue(questionNumber, out var t) ? t : new();

    public static void EnsureLoaded()
    {
        if (_questions != null) return;
        lock (_gate)
        {
            if (_questions != null) return;
            try
            {
                // Assembly-qualified so it resolves to AA.dll's resources regardless of the entry
                // assembly (the real app and the headless test harness both work).
                var uri = new Uri("pack://application:,,,/AA;component/Sire/Data/sire2_question_bank.json");
                var res = Application.GetResourceStream(uri)
                          ?? throw new InvalidOperationException("Embedded SIRE question bank not found.");
                QuestionBank? bank;
                using (var s = res.Stream)
                    bank = JsonSerializer.Deserialize<QuestionBank>(s);
                if (bank?.Questions == null || bank.Questions.Count == 0)
                    throw new InvalidOperationException("SIRE question bank is empty.");

                foreach (var q in bank.Questions)
                {
                    q.EvidenceTags = TagExtractor.ExtractTags(q);
                    q.RoviqLocations = TagExtractor.ExtractRoviqLocations(q.RoviqSequence);
                }
                Metadata = bank.Metadata;
                _identified = TaskIdentifierService.IdentifyAllTasks(bank.Questions);
                _questions = bank.Questions;
                LoadError = null;
            }
            catch (Exception ex)
            {
                LoadError = ex.Message;
                _questions = new();
                _identified = new();
            }
        }
    }

    // ---- Convenience groupings for the browser / quick-add ----

    public static IEnumerable<IGrouping<string, SireQuestion>> ByChapter() =>
        Questions.GroupBy(q => q.Chapter).OrderBy(g => int.TryParse(g.Key, out var n) ? n : 999);

    public static IEnumerable<SireQuestion> InChapter(string chapter) =>
        Questions.Where(q => q.Chapter == chapter).OrderBy(q => q.QuestionNumber, QuestionNumberComparer.Instance);

    public static IEnumerable<SireQuestion> InSection(string section) =>
        Questions.Where(q => q.Section == section).OrderBy(q => q.QuestionNumber, QuestionNumberComparer.Instance);

    public static SireQuestion? Get(string questionNumber) =>
        Questions.FirstOrDefault(q => q.QuestionNumber == questionNumber);

    /// <summary>Total offline-identified tasks across the whole bank.</summary>
    public static int TotalIdentifiedTasks => IdentifiedTasks.Values.Sum(v => v.Count);
}
