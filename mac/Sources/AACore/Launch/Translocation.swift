// Spec: 03 BD.3.6 (translocation detection, informational only — the sheet is W-SHELL's SHELL-190),
//       BD.3.8 / SHELL-199 (unbundled guards), SHELL-192 (--version line); ARCHITECTURE.md §6.9. Vectors: BD.7.2, BD.7.5.
import Foundation

public enum Translocation {
    /// True when macOS runs the app from an App Translocation mount.
    public static func isTranslocated(bundlePath: String) -> Bool { bundlePath.contains("/AppTranslocation/") }

    public static var isCurrentProcessTranslocated: Bool { isTranslocated(bundlePath: Bundle.main.bundlePath) }
}

/// SHELL-199 detection and the `--version` text (SHELL-192, BD.7.5).
public enum ShellLaunchEnvironment {
    /// `Bundle.main.bundleIdentifier == nil || Bundle.main.bundleURL.pathExtension != "app"`.
    public static func isUnbundled(bundleIdentifier: String?, bundlePathExtension: String) -> Bool {
        bundleIdentifier == nil || bundlePathExtension != "app"
    }

    public static var isCurrentProcessUnbundled: Bool {
        isUnbundled(bundleIdentifier: Bundle.main.bundleIdentifier, bundlePathExtension: Bundle.main.bundleURL.pathExtension)
    }

    /// The running slice: "arm64" or "x86_64".
    public static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    /// `AA {CFBundleShortVersionString} ({CFBundleVersion}) {arch}`, or `AA dev (unbundled) {arch}`.
    public static func versionLine(shortVersion: String?, build: String?, unbundled: Bool, arch: String) -> String {
        if unbundled { return "AA dev (unbundled) \(arch)" }
        return "AA \(shortVersion ?? "0") (\(build ?? "1")) \(arch)"
    }

    public static var currentVersionLine: String {
        let info = Bundle.main.infoDictionary
        return versionLine(shortVersion: info?["CFBundleShortVersionString"] as? String,
                           build: info?["CFBundleVersion"] as? String,
                           unbundled: isCurrentProcessUnbundled, arch: architecture)
    }
}
