using System;
using System.Collections.Generic;
using System.Linq;

namespace AA.Sire;

/// <summary>Offline task-extraction engine: scans SIRE question bodies (Suggested Inspector Actions,
/// Expected Evidence, Negative Observation Grounds) and produces actionable inspection tasks — no AI or
/// internet required. Ported verbatim from the SIRE Knowledge Bank so AA reproduces the same generated
/// tasks the standalone app derives at runtime.</summary>
public static class TaskIdentifierService
{
    private static readonly string[] SkipPrefixes =
    [
        "Pre-Inspection", "Pre-inspection", "On-board", "On board",
        "Inspectors must not", "Inspector must not",
        "Where the vessel", "Where no defects", "Where defects",
        "In the case that", "In such cases",
        "This question will only", "Note that", "Note:",
    ];

    private static readonly char[] BulletChars = ['•', '●', '■', '▪'];

    /// <summary>Identify actionable tasks for every detailed question. Keyed by QuestionNumber.</summary>
    public static Dictionary<string, List<string>> IdentifyAllTasks(IEnumerable<SireQuestion> questions)
    {
        var result = new Dictionary<string, List<string>>();
        foreach (var q in questions)
        {
            if (!q.IsDetailedQuestion) continue;
            var tasks = IdentifyTasksForQuestion(q);
            if (tasks.Count > 0) result[q.QuestionNumber] = tasks;
        }
        return result;
    }

    public static List<string> IdentifyTasksForQuestion(SireQuestion q)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var tasks = new List<string>();
        ExtractBulletTasks(q.SuggestedInspectorActions, tasks, seen, TaskMode.Direct);
        ExtractBulletTasks(q.ExpectedEvidence, tasks, seen, TaskMode.Evidence);
        ExtractBulletTasks(q.PotentialNegativeObservationGrounds, tasks, seen, TaskMode.NegativeToPositive);
        return tasks;
    }

    private enum TaskMode { Direct, Evidence, NegativeToPositive }

    private static void ExtractBulletTasks(string? text, List<string> tasks, HashSet<string> seen, TaskMode mode)
    {
        if (string.IsNullOrWhiteSpace(text)) return;
        foreach (var raw in SplitOnBullets(text))
        {
            var line = CleanFragment(raw);
            if (line.Length < 10) continue;
            if (IsSkippableLine(line)) continue;
            if (IsSubItem(line)) continue;

            var task = mode switch
            {
                TaskMode.Direct => EnsureCapitalized(line),
                TaskMode.Evidence => FormatEvidenceTask(line),
                TaskMode.NegativeToPositive => FormatNegativeAsPositive(line),
                _ => line
            };
            if (string.IsNullOrWhiteSpace(task)) continue;

            var key = NormalizeForDedup(task);
            if (key.Length < 8) continue;
            if (!seen.Add(key)) continue;
            tasks.Add(task);
        }
    }

    private static List<string> SplitOnBullets(string text)
    {
        var result = new List<string>();
        var parts = text.Split(BulletChars, StringSplitOptions.RemoveEmptyEntries);
        foreach (var part in parts)
        {
            var trimmed = part.Trim();
            if (trimmed.Length > 0) result.Add(CollapseWhitespace(trimmed));
        }
        if (parts.Length <= 1 && !text.Any(c => BulletChars.Contains(c)))
            foreach (var line in text.Split('\n', StringSplitOptions.RemoveEmptyEntries))
            {
                var trimmed = line.Trim();
                if (trimmed.Length > 0) result.Add(trimmed);
            }
        return result;
    }

    private static string CollapseWhitespace(string text)
    {
        var chars = new char[text.Length];
        int j = 0; bool lastSpace = false;
        foreach (var c in text)
        {
            if (c is '\n' or '\r' or '\t') { if (!lastSpace) { chars[j++] = ' '; lastSpace = true; } }
            else if (c == ' ') { if (!lastSpace) { chars[j++] = ' '; lastSpace = true; } }
            else { chars[j++] = c; lastSpace = false; }
        }
        return new string(chars, 0, j).Trim();
    }

    private static string CleanFragment(string text)
    {
        var t = text.Trim();
        if (t.StartsWith("- ")) t = t[2..].Trim();
        if (t.Length > 3 && char.IsDigit(t[0]) && (t[1] == '.' || t[1] == ')') && t[2] == ' ') t = t[3..].Trim();
        if (t.Length > 3 && char.IsLetter(t[0]) && (t[1] == '.' || t[1] == ')') && t[2] == ' ') t = t[3..].Trim();
        if (t.EndsWith('.') && !t.EndsWith("etc.") && !t.EndsWith("e.g.") && !t.EndsWith("i.e.")) t = t[..^1].Trim();
        return t;
    }

    private static bool IsSkippableLine(string line)
    {
        foreach (var prefix in SkipPrefixes)
            if (line.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return true;
        if (line.Length > 2 && char.IsDigit(line[0]) && line[1] == '.' && (char.IsDigit(line[2]) || line[2] == ' ')) return true;
        return false;
    }

    private static bool IsSubItem(string line) => line.StartsWith("o ") && line.Length > 3 && char.IsUpper(line[2]);

    private static string EnsureCapitalized(string text)
        => text.Length == 0 || char.IsUpper(text[0]) ? text : char.ToUpper(text[0]) + text[1..];

    private static string FormatEvidenceTask(string text)
        => StartsWithActionVerb(text) ? EnsureCapitalized(text) : $"Verify availability of: {char.ToLower(text[0])}{text[1..]}";

    private static string FormatNegativeAsPositive(string line)
    {
        var text = line;
        if (text.StartsWith("There was no ", StringComparison.OrdinalIgnoreCase)) return $"Verify that there is a {text[13..]}";
        if (text.StartsWith("There were no ", StringComparison.OrdinalIgnoreCase)) return $"Verify that there are {text[14..]}";
        if (text.StartsWith("No ", StringComparison.OrdinalIgnoreCase)) return $"Verify that {char.ToLower(text[0])}{text[1..]} — confirm this is not the case";
        if (text.Contains(" was not ", StringComparison.OrdinalIgnoreCase)) { var c = text.Replace(" was not ", " is ", StringComparison.OrdinalIgnoreCase); return $"Verify that {char.ToLower(c[0])}{c[1..]}"; }
        if (text.Contains(" were not ", StringComparison.OrdinalIgnoreCase)) { var c = text.Replace(" were not ", " are ", StringComparison.OrdinalIgnoreCase); return $"Verify that {char.ToLower(c[0])}{c[1..]}"; }
        if (text.Contains(" had not been ", StringComparison.OrdinalIgnoreCase)) { var c = text.Replace(" had not been ", " has been ", StringComparison.OrdinalIgnoreCase); return $"Verify that {char.ToLower(c[0])}{c[1..]}"; }
        if (text.Contains(" had not ", StringComparison.OrdinalIgnoreCase)) { var c = text.Replace(" had not ", " has ", StringComparison.OrdinalIgnoreCase); return $"Verify that {char.ToLower(c[0])}{c[1..]}"; }
        if (text.Contains(" did not ", StringComparison.OrdinalIgnoreCase)) { var c = text.Replace(" did not ", " does ", StringComparison.OrdinalIgnoreCase); return $"Verify that {char.ToLower(c[0])}{c[1..]}"; }
        return $"Verify that {char.ToLower(text[0])}{text[1..]}";
    }

    private static bool StartsWithActionVerb(string text)
    {
        string[] verbs =
        [
            "Verify", "Check", "Review", "Confirm", "Inspect", "Examine", "Ensure", "Compare", "Test",
            "Record", "Sight", "Interview", "Observe", "Note", "Assess", "Evaluate", "Monitor", "Measure",
            "The company", "The vessel", "A printed", "Shore based", "Communications", "Records", "Evidence", "Documentary"
        ];
        return verbs.Any(v => text.StartsWith(v, StringComparison.OrdinalIgnoreCase));
    }

    private static string NormalizeForDedup(string task)
        => new string(task.ToLowerInvariant().Where(c => char.IsLetterOrDigit(c) || c == ' ').ToArray()).Trim();
}
