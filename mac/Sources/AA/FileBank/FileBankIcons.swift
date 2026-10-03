// Spec: 05 §6.9 (Name column SHOULD show a file icon/thumbnail — `QLThumbnailGenerator` for images/videos/PDFs,
//       `NSWorkspace.icon(for: UTType)` otherwise, `globe` for links, `folder` for linked folders, a warning badge
//       when the target is missing), CONT-096; ARCHITECTURE.md §8.5 (SF Symbols), §9.7 (no per-row recomputation:
//       thumbnails are cached and generated off the main thread by Quick Look).
import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers
import AACore

/// Thumbnail cache shared by every file bank (keyed by path, pixel size and modification date).
@MainActor final class FileBankThumbnailCache {
    static let shared = FileBankThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() { cache.countLimit = 600 }

    private func key(_ url: URL, _ size: CGFloat, _ scale: CGFloat) -> NSString {
        let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?
            .timeIntervalSince1970 ?? 0
        return "\(url.path)|\(Int(size * scale))|\(mod)" as NSString
    }

    func cached(_ url: URL, size: CGFloat, scale: CGFloat) -> NSImage? { cache.object(forKey: key(url, size, scale)) }

    /// A Quick Look thumbnail (nil when Quick Look cannot draw one).
    func thumbnail(_ url: URL, size: CGFloat, scale: CGFloat) async -> NSImage? {
        let k = key(url, size, scale)
        if let hit = cache.object(forKey: k) { return hit }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size), scale: scale,
                                                   representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        let image = rep.nsImage
        cache.setObject(image, forKey: k)
        return image
    }

    /// The Finder icon of an existing file, or the type icon for its extension.
    static func icon(for url: URL?, pathExtension ext: String) -> NSImage {
        if let url, FileManager.default.fileExists(atPath: url.path) { return NSWorkspace.shared.icon(forFile: url.path) }
        let type = ext.isEmpty ? UTType.data : (UTType(filenameExtension: ext) ?? .data)
        return NSWorkspace.shared.icon(for: type)
    }
}

/// What one file-bank entry looks like (computed once per row build).
struct FileBankVisual {
    enum Glyph { case web, folder, file }
    var glyph: Glyph
    var state: FileBankResolve.State
    var ext: String
    var kind: FileKind

    var localURL: URL? { if case .present(let u) = state { return u }; return nil }
    var isMissing: Bool { if case .missing = state { return true }; return false }
    var isUnmapped: Bool { if case .windowsUnmapped = state { return true }; return false }
    var wantsThumbnail: Bool {
        guard localURL != nil, glyph == .file else { return false }
        return kind == .image || kind == .video || ext == "pdf" || ext == "heic"
    }

    @MainActor init(_ f: FileItem, dataStore: DataStore) {
        state = FileBankResolve.state(of: f, dataStore: dataStore)
        ext = FileBankDisplay.pathExtension(f.path)
        kind = f.kind
        if f.isLink { glyph = .web } else if FileBankDisplay.isLinkedFolder(f) { glyph = .folder } else {
            var isDir: ObjCBool = false
            if case .present(let u) = state, FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir),
               isDir.boolValue, !FileBankFolderScan.isPackage(u) {
                glyph = .folder
            } else {
                glyph = .file
            }
        }
    }
}

/// The icon / thumbnail of an entry, with the missing / unmapped badge.
struct FileBankFileIcon: View {
    let visual: FileBankVisual
    var size: CGFloat = 16
    @Environment(\.displayScale) private var scale
    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            base
                .frame(width: size, height: size)
                .opacity(visual.isMissing || visual.isUnmapped ? 0.55 : 1)
            badge
        }
        .frame(width: size, height: size)
        .task(id: taskKey) { await loadThumbnail() }
        .accessibilityHidden(true)
    }

    private var taskKey: String { "\(visual.localURL?.path ?? "-")|\(size)" }

    @ViewBuilder private var base: some View {
        switch visual.glyph {
        case .web:
            Image(systemName: "globe")
                .resizable().scaledToFit()
                .padding(size * 0.08)
                .foregroundStyle(AAColor.tint)
        case .folder:
            if let u = visual.localURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable().scaledToFit()
            } else {
                Image(systemName: "folder.fill").resizable().scaledToFit().foregroundStyle(AAColor.tint.opacity(0.85))
            }
        case .file:
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size > 32 ? 4 : 2, style: .continuous))
                    .shadow(color: .black.opacity(size > 32 ? 0.18 : 0), radius: 1.5, y: 0.5)
            } else {
                Image(nsImage: FileBankThumbnailCache.icon(for: visual.localURL, pathExtension: visual.ext))
                    .resizable().scaledToFit()
            }
        }
    }

    @ViewBuilder private var badge: some View {
        let b = max(8, size * 0.42)
        if visual.isMissing {
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable().scaledToFit()
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, AAColor.Status.dueSoon)
                .frame(width: b, height: b)
                .offset(x: b * 0.2, y: b * 0.15)
                .help(FileBankText.missingBadgeHelp)
        } else if visual.isUnmapped {
            Image(systemName: "externaldrive.fill.badge.questionmark")
                .resizable().scaledToFit()
                .symbolRenderingMode(.palette)
                .foregroundStyle(AAColor.Status.warning, AAColor.muted)
                .frame(width: b * 1.2, height: b)
                .offset(x: b * 0.25, y: b * 0.15)
                .help(FileBankText.unmappedBadgeHelp)
        }
    }

    private func loadThumbnail() async {
        guard visual.wantsThumbnail, let u = visual.localURL else { thumbnail = nil; return }
        let px = size
        if let hit = FileBankThumbnailCache.shared.cached(u, size: px, scale: scale) { thumbnail = hit; return }
        let image = await FileBankThumbnailCache.shared.thumbnail(u, size: px, scale: scale)
        if !Task.isCancelled { withAnimation(.easeOut(duration: 0.15)) { thumbnail = image } }
    }
}

/// The Source column: a coloured dot + `Copy` / `Live` / `Web link` (CONT-094).
struct FileBankSourceLabel: View {
    let file: FileItem

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(file.sourceLabel).foregroundStyle(AAColor.fg)
        }
        .help(help)
    }

    private var color: Color {
        if file.isLink { return AAColor.tint }
        if file.linkInPlace { return AAColor.Status.ok }
        return AAColor.Status.neutral
    }

    private var help: String {
        if file.isLink { return "A web link." }
        if file.linkInPlace { return "Linked in place — opening it edits the original file." }
        return "A copy stored in AA's data folder."
    }
}
