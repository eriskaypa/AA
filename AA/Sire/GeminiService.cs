using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace AA.Sire;

/// <summary>Calls the Google Gemini REST API to suggest inspection tasks for a SIRE question. The API key
/// is supplied by the user (stored in AA settings, never hardcoded or committed). Ported from the SIRE
/// Knowledge Bank; no NuGet dependency (built-in HttpClient + System.Text.Json).</summary>
public static class GeminiService
{
    private const string Model = "gemini-2.5-pro";
    private const string BaseUrl = "https://generativelanguage.googleapis.com/v1beta";
    private static readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(60) };

    public static async Task<(List<string> Tasks, string? Error)> GenerateTaskSuggestionsAsync(SireQuestion question, string apiKey)
    {
        if (string.IsNullOrWhiteSpace(apiKey))
            return (new(), "No Gemini API key set. Use Tools ▸ 'Set Gemini API key…' first.");
        try
        {
            var prompt = BuildPrompt(question);
            var requestBody = new
            {
                contents = new[] { new { parts = new[] { new { text = prompt } } } },
                generationConfig = new { temperature = 0.4, maxOutputTokens = 2048 }
            };
            var json = JsonSerializer.Serialize(requestBody);
            var content = new StringContent(json, Encoding.UTF8, "application/json");
            var url = $"{BaseUrl}/models/{Model}:generateContent?key={Uri.EscapeDataString(apiKey)}";

            var response = await _http.PostAsync(url, content);
            var responseText = await response.Content.ReadAsStringAsync();
            if (!response.IsSuccessStatusCode)
                return (new(), $"Gemini API error {(int)response.StatusCode}: {ExtractErrorMessage(responseText)}");

            var tasks = ParseResponse(responseText);
            return tasks.Count == 0 ? (new(), "Gemini returned an empty response. Try again.") : (tasks, null);
        }
        catch (TaskCanceledException) { return (new(), "Request timed out. Check your internet connection and try again."); }
        catch (HttpRequestException ex) { return (new(), $"Network error: {ex.Message}"); }
        catch (Exception ex) { return (new(), $"Unexpected error: {ex.Message}"); }
    }

    private static string BuildPrompt(SireQuestion q)
    {
        var sb = new StringBuilder();
        sb.AppendLine("You are a maritime SIRE 2.0 inspection expert. Based on the following SIRE 2.0 inspection question, generate specific, actionable inspection tasks that an inspector should complete. Generate as many tasks as needed to thoroughly cover the question — do not limit yourself.");
        sb.AppendLine();
        sb.AppendLine("Each task must be a concrete action using verbs like: verify, check, review, confirm, inspect, examine, ensure, compare, test, record.");
        sb.AppendLine("Return ONLY a numbered list (1. 2. 3. etc.) with one task per line. No headings, explanations, or additional commentary.");
        sb.AppendLine();
        sb.AppendLine("=== QUESTION CONTEXT ===");
        sb.AppendLine();
        sb.AppendLine($"Question Number: {q.QuestionNumber}");
        sb.AppendLine($"Chapter: {q.ChapterDisplay}");
        sb.AppendLine($"Vessel Types: {q.VesselTypesDisplay}");
        sb.AppendLine($"ROVIQ Sequence: {q.RoviqSequence}");
        sb.AppendLine();
        sb.AppendLine($"Full Question Text:\n{q.FullQuestionText}");
        if (!string.IsNullOrWhiteSpace(q.Objective)) sb.AppendLine($"\nObjective:\n{q.Objective}");
        if (!string.IsNullOrWhiteSpace(q.ExpectedEvidence)) sb.AppendLine($"\nExpected Evidence:\n{q.ExpectedEvidence}");
        if (!string.IsNullOrWhiteSpace(q.SuggestedInspectorActions)) sb.AppendLine($"\nSuggested Inspector Actions:\n{q.SuggestedInspectorActions}");
        if (!string.IsNullOrWhiteSpace(q.PotentialNegativeObservationGrounds)) sb.AppendLine($"\nPotential Negative Observation Grounds:\n{q.PotentialNegativeObservationGrounds}");
        if (!string.IsNullOrWhiteSpace(q.IndustryGuidance)) sb.AppendLine($"\nIndustry Guidance:\n{q.IndustryGuidance}");
        if (!string.IsNullOrWhiteSpace(q.InspectionGuidance)) sb.AppendLine($"\nInspection Guidance:\n{q.InspectionGuidance}");
        if (!string.IsNullOrWhiteSpace(q.Publications)) sb.AppendLine($"\nPublications:\n{q.Publications}");
        return sb.ToString();
    }

    private static List<string> ParseResponse(string responseJson)
    {
        var tasks = new List<string>();
        using var doc = JsonDocument.Parse(responseJson);
        if (!doc.RootElement.TryGetProperty("candidates", out var candidates)) return tasks;
        foreach (var candidate in candidates.EnumerateArray())
        {
            if (!candidate.TryGetProperty("content", out var content)) continue;
            if (!content.TryGetProperty("parts", out var parts)) continue;
            foreach (var part in parts.EnumerateArray())
            {
                if (!part.TryGetProperty("text", out var textElem)) continue;
                var text = textElem.GetString() ?? "";
                foreach (var line in text.Split('\n', StringSplitOptions.RemoveEmptyEntries))
                {
                    var taskText = System.Text.RegularExpressions.Regex.Replace(line.Trim(), @"^\d+[\.\)\-]\s*", "").Trim();
                    if (taskText.Length > 5) tasks.Add(taskText);
                }
            }
        }
        return tasks;
    }

    private static string ExtractErrorMessage(string responseJson)
    {
        try
        {
            using var doc = JsonDocument.Parse(responseJson);
            if (doc.RootElement.TryGetProperty("error", out var error) && error.TryGetProperty("message", out var msg))
                return msg.GetString() ?? "Unknown error";
        }
        catch { }
        return responseJson.Length > 200 ? responseJson[..200] + "..." : responseJson;
    }
}
