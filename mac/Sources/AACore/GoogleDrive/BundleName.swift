// Spec: 14 TOOLS-017, §3.1.2 `IsRestorableBundleName` (the contract with the iOS app's `isRestorableBundle`, plus
//       `aa-sync`), vectors 7.2; ARCHITECTURE.md §6.8. Source: AA/Services/GoogleDriveUploader.cs:55-74.
//       All comparisons are ordinal (UTF-16 code units), as in .NET — never Swift's grapheme comparison.
import Foundation

public enum BundleName {
    /// Is this Drive file a bundle AA can restore?
    /// * empty name → false;
    /// * a MIME type starting (ordinal) with `application/vnd.google-apps` (Docs, Sheets, folders, shortcuts) → false;
    /// * the lower-cased name ends with `.aaz` → true;
    /// * it ends with `.zip` and contains `aa-data`, `aa-backup` or `aa-sync` → true; else false.
    public static func isRestorable(name: String, mimeType: String?) -> Bool {
        if name.isEmpty { return false }
        if let mimeType, DriveOrdinal.hasPrefix(mimeType, "application/vnd.google-apps") { return false }
        let n = NetText.toLowerInvariant(name)
        if DriveOrdinal.hasSuffix(n, ".aaz") { return true }
        if !DriveOrdinal.hasSuffix(n, ".zip") { return false }
        return DriveOrdinal.contains(n, "aa-data") || DriveOrdinal.contains(n, "aa-backup") || DriveOrdinal.contains(n, "aa-sync")
    }
}

/// Ordinal (UTF-16 code unit) string tests.
enum DriveOrdinal {
    static func hasPrefix(_ s: String, _ p: String) -> Bool {
        let a = Array(s.utf16), b = Array(p.utf16)
        return a.count >= b.count && Array(a[0..<b.count]) == b
    }

    static func hasSuffix(_ s: String, _ p: String) -> Bool {
        let a = Array(s.utf16), b = Array(p.utf16)
        return a.count >= b.count && Array(a[(a.count - b.count)...]) == b
    }

    static func contains(_ s: String, _ p: String) -> Bool {
        let a = Array(s.utf16), b = Array(p.utf16)
        if b.isEmpty { return true }
        guard a.count >= b.count else { return false }
        outer: for start in 0...(a.count - b.count) {
            for k in 0..<b.count where a[start + k] != b[k] { continue outer }
            return true
        }
        return false
    }
}
