// Spec: 12 SIRE-049 / Addendum A.2 — the five evidence keyword lists of TagExtractor.cs l.12-99, VERBATIM (order,
//       casing, spelling variants and near-duplicates kept; ASCII only). Each Swift line mirrors one C# line and
//       names it (`// C# l.N`). Data, not UI copy: never localised (A.5).
import Foundation

/// The keyword arrays (A.2.1–A.2.5) and their scan order (A.2.6).
public enum SireTagKeywords {
    // TagExtractor.cs l.12-35: EquipmentKeywords
    public static let equipment: [String] = [
        "fire extinguisher", "breathing apparatus", "SCBA", "lifejacket", "life jacket",  // C# l.14
        "lifeboat", "life raft", "liferaft", "rescue boat", "EPIRB", "SART",  // C# l.15
        "inert gas", "IG system", "IGS", "oxygen analyser", "oxygen analyzer",  // C# l.16
        "cargo pump", "ballast pump", "fire pump", "emergency pump",  // C# l.17
        "ventilation", "gas detector", "fixed gas detection", "portable gas",  // C# l.18
        "mooring winch", "windlass", "anchor", "crane", "derrick",  // C# l.19
        "radar", "ECDIS", "AIS", "VDR", "GMDSS", "gyro compass", "magnetic compass",  // C# l.20
        "echo sounder", "speed log", "autopilot", "steering gear",  // C# l.21
        "emergency generator", "UPS", "battery", "main engine",  // C# l.22
        "boiler", "incinerator", "oily water separator", "OWS",  // C# l.23
        "oil discharge monitor", "ODM", "sewage treatment",  // C# l.24
        "nitrogen generator", "cargo heating", "tank cleaning",  // C# l.25
        "P/V valve", "PV valve", "pressure vacuum", "flame screen",  // C# l.26
        "deck seal", "cargo manifold", "reducer", "loading arm",  // C# l.27
        "foam system", "CO2 system", "water spray", "water mist", "dry powder",  // C# l.28
        "fire damper", "fire door", "fire flap", "quick-closing valve",  // C# l.29
        "bilge alarm", "high level alarm", "overflow",  // C# l.30
        "gangway", "accommodation ladder", "pilot ladder",  // C# l.31
        "mast riser", "vent riser", "cargo tank", "slop tank", "ballast tank",  // C# l.32
        "bunker tank", "fuel tank", "engine room",  // C# l.33
        "emergency towing", "towing arrangement"  // C# l.34
    ]

    // TagExtractor.cs l.37-55: DocumentKeywords
    public static let document: [String] = [
        "certificate", "IOPP", "ISPP", "COF", "SMC", "DOC", "ISPS",  // C# l.39
        "class survey", "CSSR", "survey status", "classification",  // C# l.40
        "safety management certificate", "cargo ship safety",  // C# l.41
        "HVPQ", "PIQ", "pre-inspection", "Document of Compliance",  // C# l.42
        "permit to work", "hot work permit", "enclosed space entry permit",  // C# l.43
        "work permit", "risk assessment", "JSA", "job safety analysis",  // C# l.44
        "passage plan", "voyage plan", "cargo plan", "stowage plan",  // C# l.45
        "stability", "loading manual", "trim and stability",  // C# l.46
        "P&A manual", "Procedures and Arrangements",  // C# l.47
        "ship security plan", "ISPS plan", "SSP",  // C# l.48
        "oil record book", "ORB", "cargo record book",  // C# l.49
        "garbage record", "ballast water record",  // C# l.50
        "ISM audit", "internal audit", "external audit",  // C# l.51
        "MSDS", "SDS", "safety data sheet", "material safety",  // C# l.52
        "IHM", "inventory of hazardous materials",  // C# l.53
        "polar water operational manual", "PWOM"  // C# l.54
    ]

    // TagExtractor.cs l.57-74: ProcedureKeywords
    public static let procedure: [String] = [
        "procedure", "checklist", "standing orders", "daily orders",  // C# l.59
        "emergency drill", "fire drill", "abandon ship", "man overboard",  // C# l.60
        "muster list", "contingency plan", "emergency plan",  // C# l.61
        "SOPEP", "SMPEP", "VRP", "shipboard oil pollution",  // C# l.62
        "cargo operation", "ballast operation", "tank cleaning procedure",  // C# l.63
        "inerting", "gas freeing", "purging", "crude oil washing", "COW",  // C# l.64
        "bunkering procedure", "STS operation", "ship to ship",  // C# l.65
        "mooring plan", "anchoring procedure",  // C# l.66
        "enclosed space entry", "hot work", "working aloft", "working overside",  // C# l.67
        "lockout tagout", "LOTO", "isolation procedure",  // C# l.68
        "drug and alcohol", "fatigue management",  // C# l.69
        "navigation procedure", "bridge procedure",  // C# l.70
        "maintenance system", "planned maintenance", "PMS",  // C# l.71
        "defect reporting", "non-conformity", "NCR",  // C# l.72
        "management of change", "MOC"  // C# l.73
    ]

    // TagExtractor.cs l.76-87: RecordKeywords
    public static let record: [String] = [
        "log book", "logbook", "deck log", "engine log", "bridge log",  // C# l.78
        "training record", "drill record", "rest hour", "work rest",  // C# l.79
        "maintenance record", "test record", "inspection record",  // C# l.80
        "calibration record", "gas reading", "atmosphere test",  // C# l.81
        "IG pressure", "cargo temperature", "ullage",  // C# l.82
        "familiarisation record", "induction record",  // C# l.83
        "near miss", "incident report", "accident report",  // C# l.84
        "superintendent report", "vessel inspection report",  // C# l.85
        "navigation assessment", "navigational audit"  // C# l.86
    ]

    // TagExtractor.cs l.89-99: PersonnelKeywords
    public static let personnel: [String] = [
        "Master", "Chief Officer", "Chief Mate", "Chief Engineer",  // C# l.91
        "officer of the watch", "OOW", "duty officer",  // C# l.92
        "deck officer", "engineer officer", "rating",  // C# l.93
        "security officer", "SSO", "CSO",  // C# l.94
        "designated person", "DPA",  // C# l.95
        "crew qualification", "STCW", "endorsement",  // C# l.96
        "familiarisation", "induction", "competency",  // C# l.97
        "safety meeting", "toolbox talk", "pre-job briefing"  // C# l.98
    ]

    /// Scan order (`TagExtractor.cs:107-111`): category name and list.
    public static let scanOrder: [(category: String, keywords: [String])] = [
        ("Equipment", equipment), ("Document", document), ("Procedure", procedure), ("Record", record),
        ("Personnel", personnel),
    ]
}
