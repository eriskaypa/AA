// Spec: 05 CONT-087 (Cut / Copy / Paste), §8 D-5 + DECISIONS 05 "File-bank Cut = true move", 05 §6.9 (the clipboard
//       SHOULD be app-wide — superset of the Windows per-editor clipboard), ARCHITECTURE.md §2.4 (hold nothing across a
//       reload: a clipboard filled before `store.replaceData` is stale and pastes nothing).
import Foundation
import Observation

/// The outcome of one paste.
public struct FileBankPasteResult: Equatable, Sendable {
    /// Entries appended to the target (moved entries keep their Id; copies get a new one).
    public var addedCount: Int
    /// Entries removed from their source container by a cut (true move).
    public var removedFromSource: Int
    /// The clipboard was filled before the data was reloaded; nothing was pasted and the clipboard was cleared.
    public var wasStale: Bool

    public init(addedCount: Int = 0, removedFromSource: Int = 0, wasStale: Bool = false) {
        self.addedCount = addedCount; self.removedFromSource = removedFromSource; self.wasStale = wasStale
    }

    public var changedTarget: Bool { addedCount > 0 }
}

/// The app-wide file-bank clipboard (not the OS pasteboard; the AA target mirrors copies to the pasteboard as file
/// URLs for Finder). Holds model references only for the data generation they were taken from.
@MainActor @Observable
public final class FileBankClipboard {
    public static let shared = FileBankClipboard()

    public private(set) var entries: [FileItem] = []
    public private(set) var isCut = false
    @ObservationIgnored public private(set) weak var source: Container?
    @ObservationIgnored private var generation: Int?
    /// `NSPasteboard.general.changeCount` right after the AA target mirrored this clipboard (nil = not mirrored).
    @ObservationIgnored public var mirroredPasteboardChangeCount: Int?

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }

    /// CONT-087 Copy: clipboard = the selection, cut mode off. An empty selection **empties** the clipboard.
    public func copy(_ files: [FileItem], from container: Container, generation: Int) {
        fill(files, from: container, generation: generation, cut: false)
    }

    /// CONT-087 Cut: same, cut mode on. An empty selection empties the clipboard.
    public func cut(_ files: [FileItem], from container: Container, generation: Int) {
        fill(files, from: container, generation: generation, cut: true)
    }

    public func clear() {
        entries = []
        isCut = false
        source = nil
        generation = nil
        mirroredPasteboardChangeCount = nil
    }

    private func fill(_ files: [FileItem], from container: Container, generation g: Int, cut: Bool) {
        guard !files.isEmpty else { clear(); return }
        var seen = Set<ObjectIdentifier>()
        entries = files.filter { seen.insert(ObjectIdentifier($0)).inserted }
        isCut = cut
        source = container
        generation = g
        mirroredPasteboardChangeCount = nil
    }

    /// CONT-087 Paste with the Mac's true move (D-5):
    /// * cut → each entry not already in the target (by identity) is appended **with the same object (same Id)** and
    ///   removed from its source container when that is a different container; cut mode then switches off, so a
    ///   second paste of the same clipboard makes copies (Windows behaviour);
    /// * copy → a new entry per clipboard entry (`FileBankEntries.pastedCopy`), even into the same container.
    /// A clipboard taken from an older data generation pastes nothing and is cleared.
    public func paste(into target: Container, generation g: Int, now: NetDateTime) -> FileBankPasteResult {
        guard !entries.isEmpty else { return FileBankPasteResult() }
        guard generation == g else {
            clear()
            return FileBankPasteResult(wasStale: true)
        }
        var result = FileBankPasteResult()
        if isCut {
            var appended: [FileItem] = []
            for f in entries where !target.files.contains(where: { $0 === f }) {
                appended.append(f)
            }
            if !appended.isEmpty { target.files.append(contentsOf: appended) }
            result.addedCount = appended.count
            if let src = source, src !== target {
                let moving = Set(appended.map { ObjectIdentifier($0) })
                let before = src.files.count
                if !moving.isEmpty {
                    src.files.removeAll { moving.contains(ObjectIdentifier($0)) }
                }
                result.removedFromSource = before - src.files.count
            }
            isCut = false
            source = target
        } else {
            let copies = entries.map { FileBankEntries.pastedCopy(of: $0, added: now) }
            target.files.append(contentsOf: copies)
            result.addedCount = copies.count
        }
        return result
    }
}
