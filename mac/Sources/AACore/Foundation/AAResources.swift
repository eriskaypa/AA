// Spec: 03 BD.3.4, SHELL-198 (one resource locator, never traps); ARCHITECTURE.md §6.1, §9.5.
import Foundation

private final class AAResourcesToken {}

/// Finds bundled resources in `Bundle.main` first (flat copy in the assembled .app), then in the SwiftPM
/// resource bundles `AA_AACore.bundle` / `AA_AA.bundle`. Never uses `Bundle.module` (it traps when missing).
public enum AAResources {
    /// SwiftPM names resource bundles "{package}_{target}.bundle"; the package is named "AA".
    static let bundleNames = ["AA_AACore.bundle", "AA_AA.bundle"]

    public static func url(name: String, ext: String) -> URL? {
        if let u = Bundle.main.url(forResource: name, withExtension: ext) { return u }
        let token = Bundle(for: AAResourcesToken.self)
        let bases: [URL?] = [Bundle.main.resourceURL, Bundle.main.bundleURL,
                             Bundle.main.executableURL?.deletingLastPathComponent(),
                             token.resourceURL, token.bundleURL,
                             token.bundleURL.deletingLastPathComponent()]
        for bundleName in bundleNames {
            for base in bases {
                guard let base else { continue }
                let candidate = base.appending(path: bundleName)
                if let b = Bundle(url: candidate), let u = b.url(forResource: name, withExtension: ext) { return u }
                // A SwiftPM resource bundle built for macOS may be a flat folder without Info.plist.
                let flat = candidate.appending(path: "\(name).\(ext)")
                if FileManager.default.fileExists(atPath: flat.path) { return flat }
            }
        }
        return nil
    }

    public static func data(name: String, ext: String) -> Data? {
        guard let u = url(name: name, ext: ext) else { return nil }
        return try? Data(contentsOf: u)
    }
}
