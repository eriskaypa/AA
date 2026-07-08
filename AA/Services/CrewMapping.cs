using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;

namespace AA.Services;

/// <summary>Header/value normalisation for matching COMPAS columns (resilient to spacing / case / apostrophes).</summary>
public static partial class CrewText
{
    /// <summary>Normalise a header/value for matching: plain apostrophe, single spaces, lower-case.</summary>
    public static string Norm(string? s)
    {
        if (string.IsNullOrEmpty(s)) return "";
        s = s.Replace('’', '\'').Replace('\n', ' ').Replace('\r', ' ');
        s = WhitespaceRegex().Replace(s, " ").Trim().ToLowerInvariant();
        return s;
    }

    [GeneratedRegex(@"\s+")]
    private static partial Regex WhitespaceRegex();
}

/// <summary>
/// Translation tables from COMPAS codes/labels to DNV-style controlled vocabularies.
/// Ported from the validated CrewBridge converter.
/// </summary>
public static class CrewMappingTables
{
    public record RankMapping(string Dnv, bool Approximate);
    public record PortMapping(string Unlocode, bool Verify);

    /// <summary>COMPAS rank code → DNV Rank. Approximate=true means "closest match, verify".</summary>
    public static readonly Dictionary<string, RankMapping> Rank = new(StringComparer.OrdinalIgnoreCase)
    {
        ["MAST"]  = new("Master", false),
        ["COFF"]  = new("Chief Officer", false),
        ["2OFF"]  = new("Second Officer", false),
        ["3OFF"]  = new("Third Officer", false),
        ["3OFT"]  = new("Third Officer", true),
        ["CENG"]  = new("Chief Engineer", false),
        ["2ENG"]  = new("Second Engineer", false),
        ["3ENG"]  = new("Third Engineer", false),
        ["4ENG"]  = new("Fourth Engineer", false),
        ["CADE"]  = new("Cadet", false),
        ["ETOF"]  = new("Electrician", true),
        ["BOSN"]  = new("Bosun", false),
        ["AB"]    = new("Able Seaman", false),
        ["OS"]    = new("Ordinary Seaman", false),
        ["EFTR"]  = new("Fitter", false),
        ["MTM"]   = new("Motorman", false),
        ["WPR"]   = new("Wiper", false),
        ["COOK"]  = new("Cook", false),
        ["MSM"]   = new("Messman", false),
        ["CG3C2"] = new("Other", true),
        ["CGOT"]  = new("Other", true),
    };

    /// <summary>ISO-3 nationality code → country name.</summary>
    public static readonly Dictionary<string, string> Iso3Nationality = new(StringComparer.OrdinalIgnoreCase)
    {
        ["IND"] = "India", ["PHL"] = "Philippines", ["CHN"] = "China", ["ROU"] = "Romania",
        ["IDN"] = "Indonesia", ["UKR"] = "Ukraine", ["RUS"] = "Russia", ["MMR"] = "Myanmar",
        ["HRV"] = "Croatia", ["POL"] = "Poland", ["GBR"] = "United Kingdom", ["NOR"] = "Norway",
        ["GRC"] = "Greece", ["ITA"] = "Italy", ["ESP"] = "Spain", ["PRT"] = "Portugal",
        ["TUR"] = "Turkey", ["BGD"] = "Bangladesh", ["LKA"] = "Sri Lanka", ["PAK"] = "Pakistan",
        ["VNM"] = "Vietnam", ["KOR"] = "South Korea", ["MYS"] = "Malaysia", ["SGP"] = "Singapore",
        ["USA"] = "United States", ["NLD"] = "Netherlands", ["DEU"] = "Germany", ["FRA"] = "France",
    };

    /// <summary>Nationality demonym → country name, used when the ISO-3 code is missing.</summary>
    public static readonly Dictionary<string, string> DemonymNationality = new(StringComparer.OrdinalIgnoreCase)
    {
        ["indian"] = "India", ["filipino"] = "Philippines", ["chinese"] = "China",
        ["romanian"] = "Romania", ["indonesian"] = "Indonesia", ["ukrainian"] = "Ukraine",
        ["russian"] = "Russia", ["burmese"] = "Myanmar", ["croatian"] = "Croatia",
        ["polish"] = "Poland", ["british"] = "United Kingdom", ["norwegian"] = "Norway",
        ["greek"] = "Greece", ["italian"] = "Italy", ["turkish"] = "Turkey",
        ["bangladeshi"] = "Bangladesh", ["sri lankan"] = "Sri Lanka", ["pakistani"] = "Pakistan",
        ["vietnamese"] = "Vietnam", ["korean"] = "South Korea", ["malaysian"] = "Malaysia",
        ["singaporean"] = "Singapore", ["american"] = "United States", ["dutch"] = "Netherlands",
        ["german"] = "Germany", ["french"] = "France", ["portuguese"] = "Portugal", ["spanish"] = "Spain",
    };

    /// <summary>Port name (normalised) → UN/LOCODE. Verify=true means best-effort, double-check.</summary>
    public static readonly Dictionary<string, PortMapping> Port = new(StringComparer.OrdinalIgnoreCase)
    {
        ["freeport (usa)"]       = new("USFPO", false),
        ["freeport"]             = new("USFPO", false),
        ["dunkirk"]              = new("FRDKK", false),
        ["milford haven (gbr)"]  = new("GBMLF", false),
        ["aliaga"]               = new("TRALI", false),
        ["corpus christi (usa)"] = new("USCRP", false),
        ["lake charles"]         = new("USLCH", false),
        ["lake charles (usa)"]   = new("USLCH", false),
        ["eemshaven"]            = new("NLEEM", false),
        ["savannah (usa)"]       = new("USSAV", false),
        ["singapore (sgp)"]      = new("SGSIN", false),
        ["cochin"]               = new("INCOK", false),
        ["botas (ceyhan) oil t"] = new("TRCEY", false),
        ["marmara (tur)"]        = new("TRMER", true),
        ["saros, turkey"]        = new("TRGEL", true),
        ["elba islan"]           = new("USELI", true),
        ["montevideo (ury)"]     = new("UYMVD", false),
    };

    /// <summary>NoK grade → relationship.</summary>
    public static readonly Dictionary<string, string> Relationship = new(StringComparer.OrdinalIgnoreCase)
    {
        ["spouse"] = "Spouse", ["wife"] = "Spouse", ["husband"] = "Spouse",
        ["mother"] = "Mother", ["father"] = "Father", ["sister"] = "Sister",
        ["brother"] = "Brother", ["son"] = "Son", ["daughter"] = "Daughter",
        ["partner"] = "Partner", ["parent"] = "Parent", ["child"] = "Child",
        ["not specified"] = "Other",
    };

    /// <summary>COMPAS gender code → gender.</summary>
    public static readonly Dictionary<string, string> Gender = new(StringComparer.OrdinalIgnoreCase)
    {
        ["M"] = "Male", ["F"] = "Female",
    };
}
