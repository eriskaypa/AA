// Spec: 03 SHELL-115 (About AA: "Created by B.E.P. Avida - May 2026"), SHELL-182 (Info.plist keys AABuildDate /
//       AAGitCommit), BD.3.11 (version stamping: "Version 1.0.0 (412)", credits unchanged), BD.7.5, SHELL-199
//       (unbundled runs), D26.
import Foundation

/// The version texts About AA and the smoke report show, read from an Info dictionary.
public struct ShellXVersionInfo: Sendable, Equatable {
    public var shortVersion: String?
    public var build: String?
    public var buildDate: String?
    public var gitCommit: String?
    public var unbundled: Bool

    public init(shortVersion: String?, build: String?, buildDate: String?, gitCommit: String?, unbundled: Bool) {
        self.shortVersion = shortVersion; self.build = build; self.buildDate = buildDate; self.gitCommit = gitCommit
        self.unbundled = unbundled
    }

    /// From `Bundle.infoDictionary`; template placeholders (`@VERSION@` …) count as absent.
    public init(info: [String: Any]?, unbundled: Bool) {
        func value(_ key: String) -> String? {
            guard let s = info?[key] as? String, !NetText.isBlank(s), !s.hasPrefix("@") else { return nil }
            return s
        }
        self.init(shortVersion: value("CFBundleShortVersionString"), build: value("CFBundleVersion"),
                  buildDate: value("AABuildDate"), gitCommit: value("AAGitCommit"), unbundled: unbundled)
    }

    public static var current: ShellXVersionInfo {
        ShellXVersionInfo(info: Bundle.main.infoDictionary, unbundled: ShellLaunchEnvironment.isCurrentProcessUnbundled)
    }

    /// The About credits (SHELL-115 / D26 / `NSHumanReadableCopyright`).
    public static let credits = "Created by B.E.P. Avida - May 2026"

    /// `Version 1.0.0 (412)`; unbundled runs say `Development build (unbundled)`.
    public var versionLine: String {
        if unbundled { return "Development build (unbundled)" }
        return "Version \(shortVersion ?? "1.0.0") (\(build ?? "1"))"
    }

    /// `Built 2026-10-02 · a1b2c3d` (nil when neither key is known).
    public var buildLine: String? {
        let parts = [buildDate.map { "Built \($0)" }, gitCommit].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The smoke report's `version` / `build` fields (BD.4.7): `dev` / `0` when unbundled.
    public var reportVersion: String { unbundled ? "dev" : (shortVersion ?? "1.0.0") }
    public var reportBuild: String { unbundled ? "0" : (build ?? "1") }
}
