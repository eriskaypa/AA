// Spec: 10 §X.4.1–§X.4.2 (OPC package: officeDocument relationship, relative/absolute targets, case-insensitive
//       part names with %XX decoding, External targets ignored, transitional + Strict relationship namespaces,
//       part-size and entry-count caps), VESSEL-302.
import Foundation

/// An opened .xlsx package: the archive bytes plus a case-insensitive part index. Sendable; parts are inflated on
/// demand with the AACore ZIP reader.
struct SvcXlsxPackage: Sendable {
    struct Relationship: Sendable {
        var id: String
        var type: String
        var target: String
        var external: Bool
    }

    static let maxPartSize: UInt64 = 1 << 30            // 1 GiB inflated
    static let maxEntries = 10_000

    private let archive: Data
    /// normalised (lower-cased, %-decoded, no leading "/") part name → the entry's real name.
    private let index: [String: String]

    init(archive: Data) throws(XlsxReadError) {
        self.archive = archive
        let reader: ZipReader
        do { reader = try ZipReader(data: archive) } catch {
            throw .corrupt(detail: error.errorDescription ?? "The file is not a ZIP archive.")
        }
        guard reader.entries.count <= Self.maxEntries else {
            throw .corrupt(detail: "The package has more than \(Self.maxEntries) parts.")
        }
        var idx: [String: String] = [:]
        for e in reader.entries where !e.isDirectory {
            let key = Self.normalise(e.name)
            if idx[key] == nil { idx[key] = e.name }
        }
        index = idx
    }

    static func normalise(_ name: String) -> String {
        var n = name.removingPercentEncoding ?? name
        while n.hasPrefix("/") { n.removeFirst() }
        return n.lowercased()
    }

    func exists(_ path: String) -> Bool { index[Self.normalise(path)] != nil }

    /// The inflated bytes of a part, or nil when the package has no such part.
    func part(_ path: String) throws(XlsxReadError) -> Data? {
        guard let name = index[Self.normalise(path)] else { return nil }
        do {
            let reader = try ZipReader(data: archive)
            guard let entry = reader.entry(named: name) else { return nil }
            guard entry.uncompressedSize <= Self.maxPartSize else {
                throw XlsxReadError.corrupt(detail: "The part \(path) is too large.")
            }
            return try reader.data(for: entry)
        } catch let e as XlsxReadError {
            throw e
        } catch {
            throw .corrupt(detail: (error as? ZipError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// The relationships of `source` ("" = the package root): `{dir}/_rels/{file}.rels`, targets resolved to
    /// package-absolute part names. A missing .rels part → no relationships.
    func relationships(of source: String) throws(XlsxReadError) -> [Relationship] {
        let relsPath: String
        let base: String
        if source.isEmpty {
            relsPath = "_rels/.rels"
            base = ""
        } else {
            let dir = Self.directory(of: source)
            let file = String(source.dropFirst(dir.count))
            relsPath = dir + "_rels/" + file + ".rels"
            base = dir
        }
        guard let data = try part(relsPath) else { return [] }
        var scanner = try SvcXmlScanner(data)
        var out: [Relationship] = []
        while let ev = try scanner.next() {
            guard case .start(let name, let attrs) = ev, name == "Relationship" else { continue }
            func attr(_ n: String) -> String? { attrs.first { $0.name == n }?.value }
            let external = (attr("TargetMode") ?? "").caseInsensitiveCompare("External") == .orderedSame
            let target = attr("Target") ?? ""
            out.append(Relationship(id: attr("Id") ?? "", type: attr("Type") ?? "",
                                    target: external ? target : Self.resolve(target, base: base), external: external))
        }
        return out
    }

    /// `xl/workbook.xml` → `xl/`.
    static func directory(of path: String) -> String {
        guard let k = path.lastIndex(of: "/") else { return "" }
        return String(path[...k])
    }

    /// Resolves a relationship target against the source part's folder; a leading "/" is package-absolute; "." and
    /// ".." segments are collapsed.
    static func resolve(_ target: String, base: String) -> String {
        let raw = target.hasPrefix("/") ? String(target.dropFirst()) : base + target
        var parts: [Substring] = []
        for seg in raw.split(separator: "/", omittingEmptySubsequences: true) {
            if seg == "." { continue }
            if seg == ".." { if !parts.isEmpty { parts.removeLast() }; continue }
            parts.append(seg)
        }
        return parts.joined(separator: "/")
    }

    /// True when a relationship type ends with `/{suffix}` in the transitional or Strict namespace.
    static func isType(_ type: String, _ suffix: String) -> Bool {
        type.hasSuffix("/" + suffix)
            && (type.hasPrefix("http://schemas.openxmlformats.org/officeDocument/2006/relationships/")
                || type.hasPrefix("http://purl.oclc.org/ooxml/officeDocument/relationships/")
                || type.hasPrefix("http://schemas.microsoft.com/office/"))
    }
}
