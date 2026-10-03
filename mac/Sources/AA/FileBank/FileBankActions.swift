// Spec: 05 CONT-082…093 (every file-bank action and its exact texts), §8 K-9 (copy failure → "Link in place
//       instead"), K-10 (Show in Finder reveals linked folders too), D-5 + DECISIONS 05 (Cut = true move), 05 §6.9
//       (Mac dialogs, Open With, Copy Path, pasteboard, Windows paths), 07 VIEW-212 row 26 + VIEW-215 (Link to items
//       picker caller), DECISIONS 05 (shared containers UI), 01 OC-12, ARCHITECTURE.md §2.1 (the AA target never
//       touches files itself: AttachmentStore / AttachmentOpener do), §2.4 (resolve by identity at OK time),
//       §9.1 (errors), §9.4 (open / reveal / UNC "Connect to Server…").
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

/// One file-bank action context: the container, the environment and the presenter of the window it lives in.
@MainActor struct FileBankController {
    let container: Container
    let env: AppEnvironment
    let dialogs: DialogPresenter

    private var store: AppStore { env.store }
    private var now: NetDateTime { env.clock.now() }

    /// The container is still part of the loaded data (not detached by a reload or a delete).
    var isLive: Bool { FileBankDirectory(store: store).owner(of: container) != nil }

    // MARK: Add (CONT-082…086)

    func addFiles() async {
        let urls = await dialogs.openPanel(OpenPanelConfig(allowsMultiple: true, canChooseFiles: true,
                                                           canChooseDirectories: false))
        guard !urls.isEmpty else { return }
        await importCopies(urls)
    }

    func linkInPlace() async {
        let urls = await dialogs.openPanel(OpenPanelConfig(message: FileBankText.linkInPlacePanelMessage,
                                                           allowsMultiple: true, canChooseFiles: true,
                                                           canChooseDirectories: true))
        guard !urls.isEmpty else { return }
        _ = try? FileBankOperations.addFiles(urls, linkInPlace: true, to: container, env: env)
    }

    func addFolder() async {
        guard let url = await dialogs.chooseFolder(message: FileBankText.addFolderPanelMessage, directory: nil) else { return }
        await importCopies([url])
    }

    func addLink() async {
        let r = await dialogs.prompt(TextPromptRequest(title: FileBankText.addLinkTitle, prompt: FileBankText.addLinkPrompt,
                                                      initial: FileBankText.addLinkInitial))
        guard case .ok(let value) = r else { return }
        addWebLinks([value])
    }

    /// CONT-086 entries for each non-blank text (untrimmed).
    func addWebLinks(_ texts: [String]) {
        var added = 0
        for t in texts {
            if let item = FileBankEntries.webLink(t, added: now) {
                container.files.append(item)
                added += 1
            }
        }
        if added > 0 { store.markDirty() }
    }

    /// Imports copies; on failures offers "Link in Place Instead" for the failed files (K-9).
    func importCopies(_ urls: [URL]) async {
        do {
            _ = try FileBankOperations.addFiles(urls, linkInPlace: false, to: container, env: env)
        } catch let e as FileBankImportError {
            let pick = await dialogs.alert(AlertSpec(
                title: FileBankText.importFailedTitle,
                message: e.errorDescription ?? "",
                style: .warning,
                buttons: [AlertButton(title: FileBankText.linkInPlaceInstead, role: .default),
                          AlertButton(title: FileBankText.cancel, role: .cancel)]))
            if pick == 0 {
                _ = try? FileBankOperations.addFiles(e.failures.map(\.url), linkInPlace: true, to: container, env: env)
            }
        } catch {
            env.reportError(error, context: "File bank import")
        }
    }

    /// A drop (CONT-085, SHELL-679): file URLs as copies or links in place; web URLs as links (05 §6.9 SHOULD).
    /// Files already in this bank (the same stored copy or the same live target) are skipped, so dragging a row
    /// onto its own bank does nothing.
    func handleDrop(fileURLs: [URL], webURLs: [URL], linkInPlace: Bool) async {
        let present = Set(container.files.compactMap { FileBankResolve.fileURL(of: $0, dataStore: env.dataStore)?
            .standardizedFileURL.path })
        let incoming = fileURLs.filter { !present.contains($0.standardizedFileURL.path) }
        if !incoming.isEmpty {
            if linkInPlace {
                _ = try? FileBankOperations.addFiles(incoming, linkInPlace: true, to: container, env: env)
            } else {
                await importCopies(incoming)
            }
        }
        if !webURLs.isEmpty { addWebLinks(webURLs.map(\.absoluteString)) }
    }

    // MARK: Clipboard (CONT-087, D-5, SHELL-577)

    func copy(_ files: [FileItem], from source: Container? = nil) {
        FileBankClipboard.shared.copy(files, from: source ?? container, generation: store.generation)
        FileBankPasteboard.mirror(files, dataStore: env.dataStore)
    }

    func cut(_ files: [FileItem]) {
        FileBankClipboard.shared.cut(files, from: container, generation: store.generation)
        FileBankPasteboard.mirror(files, dataStore: env.dataStore)
    }

    /// Pastes the file-bank clipboard, or — when the system pasteboard changed since (Finder ⌘C) — imports its files
    /// as copies and its web URLs as links.
    func paste() async {
        let clip = FileBankClipboard.shared
        let pbChanged = clip.mirroredPasteboardChangeCount.map { $0 != NSPasteboard.general.changeCount } ?? false
        if !clip.isEmpty && !pbChanged {
            pasteInternal()
            return
        }
        let external = FileBankPasteboard.read()
        if !external.files.isEmpty || !external.webs.isEmpty {
            await handleDrop(fileURLs: external.files, webURLs: external.webs, linkInPlace: false)
        } else if !clip.isEmpty {
            pasteInternal()
        } else {
            NSSound.beep()
        }
    }

    private func pasteInternal() {
        let r = FileBankClipboard.shared.paste(into: container, generation: store.generation, now: now)
        if r.changedTarget || r.removedFromSource > 0 { store.markDirty() }
    }

    // MARK: Remove / rename / link (CONT-088, 092, 093)

    /// CONT-088: no confirmation, no undo; the physical file stays in files/.
    func remove(_ files: [FileItem]) {
        guard !files.isEmpty else { return }
        let ids = Set(files.map { ObjectIdentifier($0) })
        let before = container.files.count
        container.files.removeAll { ids.contains(ObjectIdentifier($0)) }
        if container.files.count != before { store.markDirty() }
        if QuickLookCoordinator.shared.isVisible { QuickLookCoordinator.shared.close() }
    }

    func rename(_ file: FileItem) async {
        let r = await dialogs.prompt(TextPromptRequest(title: FileBankText.renameTitle, prompt: FileBankText.renamePrompt,
                                                      initial: file.name))
        guard case .ok(let value) = r, !NetText.isBlank(value) else { return }
        guard stillHolds(file) else { return }
        file.name = value                                               // display name only; untrimmed (CONT-092)
        store.markDirty()
    }

    func linkToItems(_ file: FileItem) async {
        let rows = FileBankLinkPicker.rows(store).map { ItemPickerRow(display: $0.display, tag: $0.id) }
        let picked = await dialogs.pickItems(ItemPickerRequest(prompt: FileBankText.linkPickerPrompt(file.name), rows: rows,
                                                               preselected: file.linkedItemIds, mode: .multi,
                                                               resultOrder: .selection))
        guard let picked else { return }
        guard stillHolds(file) else { return }
        FileBankLinkPicker.apply(picked, to: file, store: store)        // VIEW-215: replace + normalise + MarkDirty
    }

    /// ARCH §2.4: the entry must still be in this container of the loaded data; otherwise warn, change nothing.
    private func stillHolds(_ file: FileItem) -> Bool {
        if isLive, container.files.contains(where: { $0 === file }) { return true }
        Task { @MainActor in
            await dialogs.warning(FileBankText.title, "That file is no longer in the loaded data — nothing was changed.")
        }
        return false
    }

    // MARK: Sharing (DECISIONS 05, CONT-095)

    func shareWith() async {
        let dir = FileBankDirectory(store: store)
        guard let me = dir.owner(of: container) else { return }
        let candidates = dir.shareCandidates(excluding: container)
        let rows = candidates.map { ItemPickerRow(display: $0.owner.label, tag: $0.container.id) }
        let picked = await dialogs.pickItems(ItemPickerRequest(prompt: FileBankText.sharePickerPrompt(me.label), rows: rows,
                                                               preselected: container.sharedWithContainerIds, mode: .multi,
                                                               resultOrder: .selection))
        guard let picked else { return }
        let fresh = FileBankDirectory(store: store)
        guard fresh.owner(of: container) != nil else { return }
        if let updated = fresh.applyingSharePick(picked, to: container) {
            container.sharedWithContainerIds = updated
            store.markDirty()
        }
    }

    func stopSharing(with other: Container) {
        let before = container.sharedWithContainerIds
        container.sharedWithContainerIds.removeAll { $0 == other.id }
        if container.sharedWithContainerIds != before { store.markDirty() }
    }

    // MARK: Open (CONT-089, 090), Show in Finder (CONT-091), Quick Look, Open With, Copy Path

    func open(_ files: [FileItem]) async {
        for f in files { await FileBankOpening.open(f, env: env, dialogs: dialogs, style: .fileBank) }
    }

    /// CONT-090: every entry shown in the current tab (not the selection); > 15 asks first.
    func openAll(_ shown: [FileItem]) async {
        guard !shown.isEmpty else { return }
        if FileBankDisplay.openAllNeedsConfirmation(shown.count) {
            let ok = await dialogs.alert(AlertSpec(title: FileBankText.openAllTitle,
                                                   message: FileBankText.openAllPrompt(shown.count), style: .informational,
                                                   buttons: [AlertButton(title: "Yes", role: .default),
                                                             AlertButton(title: "No", role: .cancel)])) == 0
            guard ok else { return }
        }
        await open(shown)
    }

    func showInFinder(_ file: FileItem) async {
        await FileBankOpening.showInFinder(file, env: env, dialogs: dialogs)
    }

    func copyPath(_ files: [FileItem]) {
        let text = files.map { FileBankResolve.target(of: $0, dataStore: env.dataStore) }.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

// MARK: - Opening (shared by the file bank, the viewer and the backlinks section)

@MainActor enum FileBankOpening {
    enum Style { case fileBank, viewer }

    /// CONT-089 (file bank) / HIER-136 (viewer) with the OC-12 resolved target in every message.
    static func open(_ f: FileItem, env: AppEnvironment, dialogs: DialogPresenter, style: Style) async {
        let ds = env.dataStore
        let target = FileBankResolve.target(of: f, dataStore: ds)
        switch FileBankResolve.state(of: f, dataStore: ds) {
        case .missing(let path):
            await reportMissing(path.isEmpty ? target : path, dialogs: dialogs, style: style)
            return
        case .windowsUnmapped(let p):
            await reportUnmapped(p, file: f, env: env, dialogs: dialogs) { await open(f, env: env, dialogs: dialogs, style: style) }
            return
        case .web, .present:
            break
        }
        switch AttachmentOpener.open(stored: f.path, isLink: f.isLink, dataStore: ds) {
        case .opened:
            return
        case .notFound(let t):
            await reportMissing(t, dialogs: dialogs, style: style)
        case .windowsPathUnmapped(let p):
            await reportUnmapped(p, file: f, env: env, dialogs: dialogs) { await open(f, env: env, dialogs: dialogs, style: style) }
        case .failed(let message):
            switch style {
            case .fileBank: await dialogs.info(FileBankText.openFailedTitle, message)
            case .viewer: await dialogs.warning(FileBankText.viewerOpenTitle, FileBankText.viewerCouldNotOpen(target, message))
            }
        }
    }

    private static func reportMissing(_ target: String, dialogs: DialogPresenter, style: Style) async {
        switch style {
        case .fileBank:
            await dialogs.info(FileBankText.openFailedTitle, FileBankText.notFound(target))
        case .viewer:
            await dialogs.warning(FileBankText.viewerMissingTitle, FileBankText.viewerMissing(target))
        }
    }

    /// ARCH §9.4: drive letters point to Settings ▸ File Links; UNC shares also offer "Connect to Server…" (Finder
    /// mounts `smb://server/share`), then retry once the share appears (up to 15 s).
    static func reportUnmapped(_ path: String, file: FileItem, env: AppEnvironment, dialogs: DialogPresenter,
                               retry: @escaping @MainActor () async -> Void) async {
        let root = FileBankResolve.windowsRoot(of: path)
        if path.hasPrefix("\\\\"), let smb = PathMapper.smbURL(forUNC: path) {
            let pick = await dialogs.alert(AlertSpec(
                title: FileBankText.openFailedTitle, message: FileBankText.windowsShareUnmapped(root), style: .warning,
                buttons: [AlertButton(title: FileBankText.connectToServer, role: .default),
                          AlertButton(title: FileBankText.fileLinksSettings),
                          AlertButton(title: FileBankText.cancel, role: .cancel)]))
            if pick == 0 {
                NSWorkspace.shared.open(smb)
                for _ in 0..<30 {
                    try? await Task.sleep(for: .milliseconds(500))
                    if case .present = FileBankResolve.state(of: file, dataStore: env.dataStore) {
                        await retry()
                        return
                    }
                }
            } else if pick == 1 {
                env.open(.settings(tab: .fileLinks))
            }
            return
        }
        let pick = await dialogs.alert(AlertSpec(
            title: FileBankText.openFailedTitle, message: FileBankText.windowsDriveUnmapped(root), style: .warning,
            buttons: [AlertButton(title: FileBankText.fileLinksSettings, role: .default),
                      AlertButton(title: FileBankText.ok, role: .cancel)]))
        if pick == 0 { env.open(.settings(tab: .fileLinks)) }
    }

    /// CONT-091 with K-10: links open their URL; copies / live files reveal in Finder (folders too).
    static func showInFinder(_ f: FileItem, env: AppEnvironment, dialogs: DialogPresenter) async {
        if f.isLink {
            await open(f, env: env, dialogs: dialogs, style: .fileBank)
            return
        }
        let ds = env.dataStore
        switch FileBankResolve.state(of: f, dataStore: ds) {
        case .missing(let path):
            await dialogs.info(FileBankText.openFolderTitle, FileBankText.fileNotFound(path))
            return
        case .windowsUnmapped(let p):
            await reportUnmapped(p, file: f, env: env, dialogs: dialogs) { await showInFinder(f, env: env, dialogs: dialogs) }
            return
        case .present, .web:
            break
        }
        switch AttachmentOpener.revealInFinder(stored: f.path, dataStore: ds) {
        case .opened: return
        case .notFound(let p): await dialogs.info(FileBankText.openFolderTitle, FileBankText.fileNotFound(p))
        case .windowsPathUnmapped(let p):
            await reportUnmapped(p, file: f, env: env, dialogs: dialogs) { await showInFinder(f, env: env, dialogs: dialogs) }
        case .failed(let message): await dialogs.info(FileBankText.openFolderFailedTitle, message)
        }
    }

    /// Open With ▸ (05 §6.9 addition): the applications that can open a local file.
    static func applications(for url: URL) -> [URL] {
        let all = NSWorkspace.shared.urlsForApplications(toOpen: url)
        var seen = Set<String>()
        return all.filter { seen.insert($0.path).inserted }
    }

    static func open(_ url: URL, with app: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    static func chooseApplication(for url: URL, dialogs: DialogPresenter) async {
        let apps = await dialogs.openPanel(OpenPanelConfig(allowedTypes: [.application], allowsMultiple: false,
                                                           directory: URL(fileURLWithPath: "/Applications")))
        if let app = apps.first { open(url, with: app) }
    }

    /// Quick Look over `files`, starting at `selected` (only local, present files are previewed).
    static func quickLook(_ files: [FileItem], selected: FileItem?, env: AppEnvironment, toggle: Bool) {
        let ds = env.dataStore
        var urls: [URL] = []
        var start = 0
        for f in files {
            guard case .present(let u) = FileBankResolve.state(of: f, dataStore: ds) else { continue }
            if let selected, f === selected { start = urls.count }
            urls.append(u)
        }
        if toggle { QuickLookCoordinator.shared.toggle(urls, selectedIndex: start) } else {
            QuickLookCoordinator.shared.preview(urls, selectedIndex: start)
        }
    }
}

// MARK: - System pasteboard mirror (05 §6.9: ⌘C in the file bank also works in Finder / Mail)

@MainActor enum FileBankPasteboard {
    /// Writes the entries' local files (and web links) to the general pasteboard and records the change count so a
    /// later paste knows the pasteboard still holds this file-bank clipboard.
    static func mirror(_ files: [FileItem], dataStore: DataStore) {
        guard !files.isEmpty else { return }
        var objects: [NSPasteboardWriting] = []
        var text: [String] = []
        for f in files {
            switch FileBankResolve.state(of: f, dataStore: dataStore) {
            case .present(let u): objects.append(u as NSURL)
            case .web(let u): if let u { objects.append(u as NSURL) }
            default: break
            }
            text.append(FileBankResolve.target(of: f, dataStore: dataStore))
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        if !objects.isEmpty { pb.writeObjects(objects) }
        if objects.isEmpty { pb.setString(text.joined(separator: "\n"), forType: .string) }
        FileBankClipboard.shared.mirroredPasteboardChangeCount = pb.changeCount
    }

    /// File URLs and web URLs on the general pasteboard.
    static func read() -> (files: [URL], webs: [URL]) {
        let pb = NSPasteboard.general
        let files = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let all = (pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        let webs = all.filter { !$0.isFileURL && ($0.scheme == "http" || $0.scheme == "https" || $0.scheme == "mailto") }
        return (files, webs)
    }
}
