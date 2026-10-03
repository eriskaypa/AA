// Spec: 09 §3.4 (CrewMappingTables, verbatim; every table case-insensitive ordinal), §4.9.
import Foundation

/// COMPAS codes and names → DNV-style controlled vocabularies.
public enum CrewMappingTables {
    public struct RankMapping: Sendable, Equatable {
        public let dnv: String
        public let approximate: Bool
        public init(dnv: String, approximate: Bool) { self.dnv = dnv; self.approximate = approximate }
    }

    public struct PortMapping: Sendable, Equatable {
        public let unlocode: String
        public let verify: Bool
        public init(unlocode: String, verify: Bool) { self.unlocode = unlocode; self.verify = verify }
    }

    /// COMPAS rank code → DNV rank (keys upper-cased invariant).
    public static let rank: [String: RankMapping] = [
        "MAST": RankMapping(dnv: "Master", approximate: false),
        "COFF": RankMapping(dnv: "Chief Officer", approximate: false),
        "2OFF": RankMapping(dnv: "Second Officer", approximate: false),
        "3OFF": RankMapping(dnv: "Third Officer", approximate: false),
        "3OFT": RankMapping(dnv: "Third Officer", approximate: true),
        "CENG": RankMapping(dnv: "Chief Engineer", approximate: false),
        "2ENG": RankMapping(dnv: "Second Engineer", approximate: false),
        "3ENG": RankMapping(dnv: "Third Engineer", approximate: false),
        "4ENG": RankMapping(dnv: "Fourth Engineer", approximate: false),
        "CADE": RankMapping(dnv: "Cadet", approximate: false),
        "ETOF": RankMapping(dnv: "Electrician", approximate: true),
        "BOSN": RankMapping(dnv: "Bosun", approximate: false),
        "AB": RankMapping(dnv: "Able Seaman", approximate: false),
        "OS": RankMapping(dnv: "Ordinary Seaman", approximate: false),
        "EFTR": RankMapping(dnv: "Fitter", approximate: false),
        "MTM": RankMapping(dnv: "Motorman", approximate: false),
        "WPR": RankMapping(dnv: "Wiper", approximate: false),
        "COOK": RankMapping(dnv: "Cook", approximate: false),
        "MSM": RankMapping(dnv: "Messman", approximate: false),
        "CG3C2": RankMapping(dnv: "Other", approximate: true),
        "CGOT": RankMapping(dnv: "Other", approximate: true),
    ]

    /// ISO-3 nationality code → country (28).
    public static let iso3Nationality: [String: String] = [
        "IND": "India", "PHL": "Philippines", "CHN": "China", "ROU": "Romania", "IDN": "Indonesia", "UKR": "Ukraine",
        "RUS": "Russia", "MMR": "Myanmar", "HRV": "Croatia", "POL": "Poland", "GBR": "United Kingdom", "NOR": "Norway",
        "GRC": "Greece", "ITA": "Italy", "ESP": "Spain", "PRT": "Portugal", "TUR": "Turkey", "BGD": "Bangladesh",
        "LKA": "Sri Lanka", "PAK": "Pakistan", "VNM": "Vietnam", "KOR": "South Korea", "MYS": "Malaysia",
        "SGP": "Singapore", "USA": "United States", "NLD": "Netherlands", "DEU": "Germany", "FRA": "France",
    ]

    /// Normalised demonym → country (28).
    public static let demonymNationality: [String: String] = [
        "indian": "India", "filipino": "Philippines", "chinese": "China", "romanian": "Romania",
        "indonesian": "Indonesia", "ukrainian": "Ukraine", "russian": "Russia", "burmese": "Myanmar",
        "croatian": "Croatia", "polish": "Poland", "british": "United Kingdom", "norwegian": "Norway",
        "greek": "Greece", "italian": "Italy", "turkish": "Turkey", "bangladeshi": "Bangladesh",
        "sri lankan": "Sri Lanka", "pakistani": "Pakistan", "vietnamese": "Vietnam", "korean": "South Korea",
        "malaysian": "Malaysia", "singaporean": "Singapore", "american": "United States", "dutch": "Netherlands",
        "german": "Germany", "french": "France", "portuguese": "Portugal", "spanish": "Spain",
    ]

    /// Normalised port name → UN/LOCODE (COMPAS's own truncations kept verbatim).
    public static let port: [String: PortMapping] = [
        "freeport (usa)": PortMapping(unlocode: "USFPO", verify: false),
        "freeport": PortMapping(unlocode: "USFPO", verify: false),
        "dunkirk": PortMapping(unlocode: "FRDKK", verify: false),
        "milford haven (gbr)": PortMapping(unlocode: "GBMLF", verify: false),
        "aliaga": PortMapping(unlocode: "TRALI", verify: false),
        "corpus christi (usa)": PortMapping(unlocode: "USCRP", verify: false),
        "lake charles": PortMapping(unlocode: "USLCH", verify: false),
        "lake charles (usa)": PortMapping(unlocode: "USLCH", verify: false),
        "eemshaven": PortMapping(unlocode: "NLEEM", verify: false),
        "savannah (usa)": PortMapping(unlocode: "USSAV", verify: false),
        "singapore (sgp)": PortMapping(unlocode: "SGSIN", verify: false),
        "cochin": PortMapping(unlocode: "INCOK", verify: false),
        "botas (ceyhan) oil t": PortMapping(unlocode: "TRCEY", verify: false),
        "marmara (tur)": PortMapping(unlocode: "TRMER", verify: true),
        "saros, turkey": PortMapping(unlocode: "TRGEL", verify: true),
        "elba islan": PortMapping(unlocode: "USELI", verify: true),
        "montevideo (ury)": PortMapping(unlocode: "UYMVD", verify: false),
    ]

    /// Normalised next-of-kin grade → relationship.
    public static let relationship: [String: String] = [
        "spouse": "Spouse", "wife": "Spouse", "husband": "Spouse", "mother": "Mother", "father": "Father",
        "sister": "Sister", "brother": "Brother", "son": "Son", "daughter": "Daughter", "partner": "Partner",
        "parent": "Parent", "child": "Child", "not specified": "Other",
    ]

    /// Gender code → gender.
    public static let gender: [String: String] = ["M": "Male", "F": "Female"]

    // MARK: Case-insensitive ordinal lookups (keys above are stored upper- or lower-case; .NET OrdinalIgnoreCase)

    public static func rank(for code: String) -> RankMapping? { rank[NetText.toUpperInvariant(code)] }
    public static func country(forISO3 code: String) -> String? { iso3Nationality[NetText.toUpperInvariant(code)] }
    public static func country(forDemonym normalised: String) -> String? {
        demonymNationality[NetText.toLowerInvariant(normalised)]
    }
    public static func port(forNormalised key: String) -> PortMapping? { port[NetText.toLowerInvariant(key)] }
    public static func relationship(forNormalised grade: String) -> String? {
        relationship[NetText.toLowerInvariant(grade)]
    }
    public static func gender(for code: String) -> String? { gender[NetText.toUpperInvariant(code)] }
}
