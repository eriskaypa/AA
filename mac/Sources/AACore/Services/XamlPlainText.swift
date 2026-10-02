// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §6.5 (lives in Services, not RichText — ARCH §1.2)
// Spec: 02 REPO-104 (search text: XmlReader text nodes + spaces, fallback regex), 01 §3.15 (DataDiff.PlainText:
// regex strip + HTML decode + whitespace collapse). Compiling stub created by F1; F2 replaces this file in place.
// ARCH §11 requires the stub to strip tags with the regex so foundation tests are meaningful.
import Foundation

public enum XamlPlainText {
    /// REPO-104. Stub = the Windows fallback branch: every `<…>` tag replaced by one space.
    public static func searchText(_ xaml: String) -> String {
        // PLACEHOLDER(F2)
        guard !xaml.isEmpty else { return "" }
        return xaml.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    /// 01 §3.15. Stub: tags → space, the five XML entities decoded, whitespace runs collapsed, trimmed.
    public static func diffText(_ xaml: String) -> String {
        // PLACEHOLDER(F2)
        guard !xaml.isEmpty else { return "" }
        var s = xaml.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, char) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&amp;", "&")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
