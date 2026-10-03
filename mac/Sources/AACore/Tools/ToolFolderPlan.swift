// Spec: 14 TOOLS-042…050, §3.3.1 Parse, §3.3.2 Sanitize, §3.3.4 create, §6.7 (canonical spelling on case-sensitive
//       volumes, Q-15; non-absolute stored bases ignored, Q-17), vectors 7.3. Source: AA/Views/FolderBuilderWindow.xaml.cs.
import Foundation

/// One folder of the preview tree. `id` is the canonical relative path folded to lower case (unique in a plan,
/// because siblings merge case-insensitively).
public struct ToolFolderNode: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    /// nil for a leaf (so `OutlineGroup` shows no disclosure triangle).
    public let children: [ToolFolderNode]?

    public init(id: String, name: String, children: [ToolFolderNode]?) {
        self.id = id; self.name = name; self.children = children
    }
}

/// The parsed folder list: the preview tree and the relative paths to create (parent before child).
public struct ToolFolderPlan: Sendable, Equatable {
    public let roots: [ToolFolderNode]
    /// The Windows `rels` list: each path once (case-insensitive), spelled as the line that introduced it typed it.
    public let rels: [String]
    /// The same paths spelled with the tree's canonical (first-seen) names — used for creation (Q-15).
    public let creationPaths: [String]

    public var count: Int { rels.count }

    /// `Preview ({n} folder{s})` (TOOLS-047).
    public var header: String { "Preview (\(count) folder\(count == 1 ? "" : "s"))" }

    /// The text the **Example** button fills in (TOOLS-048), ending with a newline.
    public static let exampleText = "Project A\n\tDocuments\n\tImages\n\tReports\n\t\t2026\nProject B\n\tDrawings\nShared/Templates\n"

    /// The muted help line under the heading (TOOLS-040, exact).
    public static let helpText = "Type one folder name per line on the left. Indent a line (Tab, or 2 spaces) to nest it as a subfolder of the line above. A line may also contain '\\' or '/' to create a nested path directly. The right panel previews the structure that will be created under the base location."

    // MARK: Sanitize (§3.3.2)

    private static let trailingDotSpace: Set<UInt16> = [0x2E, 0x20]

    /// Trim → every Windows-invalid file-name character becomes `_` → trim → strip trailing `.` and spaces.
    public static func sanitize(_ s: String) -> String {
        let t = NetText.trim(s)
        var out = String.UnicodeScalarView()
        for sc in t.unicodeScalars {
            if sc.value < 0x20 || "\"<>|:*?\\/".unicodeScalars.contains(sc) { out.append("_") } else { out.append(sc) }
        }
        let u = Array(NetText.trim(String(out)).utf16)
        var end = u.count
        while end > 0, trailingDotSpace.contains(u[end - 1]) { end -= 1 }
        return String(decoding: u[0..<end], as: UTF16.self)
    }

    // MARK: Parse (§3.3.1)

    private final class Node {
        let name: String
        let canonicalRel: String
        var children: [Node] = []
        init(name: String, canonicalRel: String) { self.name = name; self.canonicalRel = canonicalRel }

        func value() -> ToolFolderNode {
            ToolFolderNode(id: NetText.toLowerInvariant(canonicalRel), name: name,
                           children: children.isEmpty ? nil : children.map { $0.value() })
        }
    }

    public static func parse(_ text: String?) -> ToolFolderPlan {
        var roots: [Node] = []
        var rels: [String] = []
        var creation: [String] = []
        var seen = Set<String>()                                   // folded rel paths
        var stack: [(depth: Int, node: Node, rel: String)] = []
        var lastDepth = -1
        let normalized = (text ?? "").replacingOccurrences(of: "\r\n", with: "\n")
        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if NetText.isBlank(raw) { continue }
            let u = Array(raw.utf16)
            var i = 0, spaces = 0, depth = 0
            while i < u.count, u[i] == 0x20 || u[i] == 0x09 {
                if u[i] == 0x09 { depth += 1 } else { spaces += 1 }
                i += 1
            }
            depth += spaces / 2
            let name = NetText.trim(String(decoding: u[i...], as: UTF16.self))
            if name.isEmpty { continue }
            if depth > lastDepth + 1 { depth = lastDepth + 1 }
            let segments = splitSegments(name).map(sanitize).filter { !$0.isEmpty }
            if segments.isEmpty { continue }
            var parent: Node?
            var parentRel = ""
            if depth > 0 {
                if let entry = stack.last(where: { $0.depth == depth - 1 }) {
                    parent = entry.node
                    parentRel = entry.rel
                } else {
                    depth = 0
                }
            }
            var current = parent
            var currentRel = parentRel
            for seg in segments {
                currentRel = currentRel.isEmpty ? seg : currentRel + "/" + seg
                let siblings = current?.children ?? roots
                let node: Node
                if let existing = siblings.first(where: { NetText.equalsIgnoreCase($0.name, seg) }) {
                    node = existing
                } else {
                    let canonical = (current?.canonicalRel).map { $0 + "/" + seg } ?? seg
                    node = Node(name: seg, canonicalRel: canonical)
                    if let current { current.children.append(node) } else { roots.append(node) }
                }
                let key = folded(currentRel)
                if !seen.contains(key) {
                    seen.insert(key)
                    rels.append(currentRel)
                    creation.append(node.canonicalRel)
                }
                current = node
            }
            stack.removeAll { $0.depth >= depth }
            if let current { stack.append((depth, current, currentRel)) }
            lastDepth = depth
        }
        return ToolFolderPlan(roots: roots.map { $0.value() }, rels: rels, creationPaths: creation)
    }

    /// `name.Split('/', '\\')` (empty segments kept here; the caller drops them after sanitising).
    static func splitSegments(_ s: String) -> [String] {
        var out: [String] = []
        var cur = String.UnicodeScalarView()
        for sc in s.unicodeScalars {
            if sc == "/" || sc == "\\" { out.append(String(cur)); cur = String.UnicodeScalarView() } else { cur.append(sc) }
        }
        out.append(String(cur))
        return out
    }

    /// OrdinalIgnoreCase key of a path.
    static func folded(_ s: String) -> String {
        String(decoding: s.utf16.map(NetText.simpleUpper), as: UTF16.self)
    }

    // MARK: Create (TOOLS-049 step 5)

    public struct CreateResult: Sendable, Equatable {
        public var created: Int, existed: Int, failed: Int
        public init(created: Int, existed: Int, failed: Int) { self.created = created; self.existed = existed; self.failed = failed }

        /// `Created {c}, already existed {e}[, failed {f}].`
        public var statusText: String {
            "Created \(created), already existed \(existed)" + (failed > 0 ? ", failed \(failed)" : "") + "."
        }
    }

    /// For each path: an existing directory counts as existed; otherwise it is created with intermediates; any
    /// failure (e.g. a regular file in the way) counts as failed and the run continues.
    public func create(under base: URL, fileManager: FileManager = .default) -> CreateResult {
        var r = CreateResult(created: 0, existed: 0, failed: 0)
        for rel in creationPaths {
            var url = base
            for seg in rel.split(separator: "/") { url.append(path: String(seg), directoryHint: .isDirectory) }
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                r.existed += 1
                continue
            }
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                r.created += 1
            } catch {
                r.failed += 1
            }
        }
        return r
    }

    /// `Directory.Exists(path)` (false for blank paths and regular files).
    public static func directoryExists(_ path: String) -> Bool {
        guard !NetText.isBlank(path) else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// TOOLS-049 step 3: create the missing base location with every intermediate level.
    public static func createBase(_ path: String) throws {
        try FileManager.default.createDirectory(at: URL(filePath: path, directoryHint: .isDirectory),
                                                withIntermediateDirectories: true)
    }

    // MARK: Messages (exact)

    public static let title = "Folder builder"
    public static let chooseBaseFirst = "Choose a base location first (Browse...)."
    public static let nothingToCreate = "Nothing to create \u{2014} type some folder names."
    public static let baseNotFound = "Base location not found."
    public static let browseMessage = "Choose the base location where folders will be created"

    public static func baseMissingQuestion(_ base: String) -> String { "The base location does not exist:\n\(base)\n\nCreate it?" }

    public static func confirmCreate(count n: Int, base: String) -> String {
        "Create \(n) folder\(n == 1 ? "" : "s") under:\n\(base)?"
    }

    public static func openAfterCreate(created c: Int) -> String { "Created \(c) folder(s). Open the base location?" }

    /// A stored base is usable on the Mac only when it is an absolute POSIX path (Q-17: a Windows `D:\Projects`
    /// from a copied settings file shows as empty and is left untouched until a new base is chosen).
    public static func usableStoredBase(_ stored: String?) -> String {
        guard let s = stored, s.hasPrefix("/") else { return "" }
        return s
    }
}
