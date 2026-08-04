using System;
using System.Collections.Generic;
using System.Linq;

namespace AA.Sire;

/// <summary>Classifies SIRE question content into evidence categories — Equipment, Document, Procedure,
/// Record, Personnel — used both for filtering and to suggest a default AA item kind on quick-add.
/// Ported from the SIRE Knowledge Bank.</summary>
public static class TagExtractor
{
    private static readonly string[] EquipmentKeywords =
    [
        "fire extinguisher", "breathing apparatus", "SCBA", "lifejacket", "life jacket",
        "lifeboat", "life raft", "liferaft", "rescue boat", "EPIRB", "SART",
        "inert gas", "IG system", "IGS", "oxygen analyser", "oxygen analyzer",
        "cargo pump", "ballast pump", "fire pump", "emergency pump",
        "ventilation", "gas detector", "fixed gas detection", "portable gas",
        "mooring winch", "windlass", "anchor", "crane", "derrick",
        "radar", "ECDIS", "AIS", "VDR", "GMDSS", "gyro compass", "magnetic compass",
        "echo sounder", "speed log", "autopilot", "steering gear",
        "emergency generator", "UPS", "battery", "main engine",
        "boiler", "incinerator", "oily water separator", "OWS",
        "oil discharge monitor", "ODM", "sewage treatment",
        "nitrogen generator", "cargo heating", "tank cleaning",
        "P/V valve", "PV valve", "pressure vacuum", "flame screen",
        "deck seal", "cargo manifold", "reducer", "loading arm",
        "foam system", "CO2 system", "water spray", "water mist", "dry powder",
        "fire damper", "fire door", "fire flap", "quick-closing valve",
        "bilge alarm", "high level alarm", "overflow",
        "gangway", "accommodation ladder", "pilot ladder",
        "mast riser", "vent riser", "cargo tank", "slop tank", "ballast tank",
        "bunker tank", "fuel tank", "engine room",
        "emergency towing", "towing arrangement"
    ];

    private static readonly string[] DocumentKeywords =
    [
        "certificate", "IOPP", "ISPP", "COF", "SMC", "DOC", "ISPS",
        "class survey", "CSSR", "survey status", "classification",
        "safety management certificate", "cargo ship safety",
        "HVPQ", "PIQ", "pre-inspection", "Document of Compliance",
        "permit to work", "hot work permit", "enclosed space entry permit",
        "work permit", "risk assessment", "JSA", "job safety analysis",
        "passage plan", "voyage plan", "cargo plan", "stowage plan",
        "stability", "loading manual", "trim and stability",
        "P&A manual", "Procedures and Arrangements",
        "ship security plan", "ISPS plan", "SSP",
        "oil record book", "ORB", "cargo record book",
        "garbage record", "ballast water record",
        "ISM audit", "internal audit", "external audit",
        "MSDS", "SDS", "safety data sheet", "material safety",
        "IHM", "inventory of hazardous materials",
        "polar water operational manual", "PWOM"
    ];

    private static readonly string[] ProcedureKeywords =
    [
        "procedure", "checklist", "standing orders", "daily orders",
        "emergency drill", "fire drill", "abandon ship", "man overboard",
        "muster list", "contingency plan", "emergency plan",
        "SOPEP", "SMPEP", "VRP", "shipboard oil pollution",
        "cargo operation", "ballast operation", "tank cleaning procedure",
        "inerting", "gas freeing", "purging", "crude oil washing", "COW",
        "bunkering procedure", "STS operation", "ship to ship",
        "mooring plan", "anchoring procedure",
        "enclosed space entry", "hot work", "working aloft", "working overside",
        "lockout tagout", "LOTO", "isolation procedure",
        "drug and alcohol", "fatigue management",
        "navigation procedure", "bridge procedure",
        "maintenance system", "planned maintenance", "PMS",
        "defect reporting", "non-conformity", "NCR",
        "management of change", "MOC"
    ];

    private static readonly string[] RecordKeywords =
    [
        "log book", "logbook", "deck log", "engine log", "bridge log",
        "training record", "drill record", "rest hour", "work rest",
        "maintenance record", "test record", "inspection record",
        "calibration record", "gas reading", "atmosphere test",
        "IG pressure", "cargo temperature", "ullage",
        "familiarisation record", "induction record",
        "near miss", "incident report", "accident report",
        "superintendent report", "vessel inspection report",
        "navigation assessment", "navigational audit"
    ];

    private static readonly string[] PersonnelKeywords =
    [
        "Master", "Chief Officer", "Chief Mate", "Chief Engineer",
        "officer of the watch", "OOW", "duty officer",
        "deck officer", "engineer officer", "rating",
        "security officer", "SSO", "CSO",
        "designated person", "DPA",
        "crew qualification", "STCW", "endorsement",
        "familiarisation", "induction", "competency",
        "safety meeting", "toolbox talk", "pre-job briefing"
    ];

    public static List<string> ExtractTags(SireQuestion question)
    {
        var tags = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var searchText = string.Join(" ",
            question.ExpectedEvidence, question.SuggestedInspectorActions,
            question.ShortQuestionText, question.Objective);
        ScanForTags(searchText, EquipmentKeywords, "Equipment", tags);
        ScanForTags(searchText, DocumentKeywords, "Document", tags);
        ScanForTags(searchText, ProcedureKeywords, "Procedure", tags);
        ScanForTags(searchText, RecordKeywords, "Record", tags);
        ScanForTags(searchText, PersonnelKeywords, "Personnel", tags);
        return tags.OrderBy(t => t).ToList();
    }

    private static void ScanForTags(string text, string[] keywords, string category, HashSet<string> tags)
    {
        foreach (var keyword in keywords)
            if (text.Contains(keyword, StringComparison.OrdinalIgnoreCase))
                tags.Add($"{category}: {keyword}");
    }

    public static List<string> ExtractRoviqLocations(string roviqSequence)
    {
        if (string.IsNullOrWhiteSpace(roviqSequence)) return new();
        return roviqSequence
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(loc => loc.TrimEnd('.'))
            .Where(loc => !string.IsNullOrWhiteSpace(loc))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(loc => loc)
            .ToList();
    }

    /// <summary>Best-guess dominant evidence category for a question, used to pre-select the AA item kind
    /// on quick-add (Equipment tag → Equipment, Procedure tag → Procedure, else Task).</summary>
    public static string DominantCategory(SireQuestion q)
    {
        var counts = new Dictionary<string, int> { ["Equipment"] = 0, ["Procedure"] = 0, ["Document"] = 0, ["Record"] = 0, ["Personnel"] = 0 };
        foreach (var t in q.EvidenceTags)
        {
            var idx = t.IndexOf(':');
            if (idx > 0) { var cat = t[..idx]; if (counts.ContainsKey(cat)) counts[cat]++; }
        }
        if (counts["Equipment"] > 0 && counts["Equipment"] >= counts["Procedure"]) return "Equipment";
        if (counts["Procedure"] > 0) return "Procedure";
        return "Task";
    }
}
