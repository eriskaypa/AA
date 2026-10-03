// Spec: 04 HIER-136 (read-only container viewer: "View — {title}", header card with bold 16 pt accent title and muted
//       11 pt subtitle, read-only rich text on the light paper colours with clickable links, 6 px splitter, 180 px files
//       pane "Files — none" / "Files ({n}) — double-click to open", columns Name 260 · Kind 80 · Source 70 ·
//       Path / URL 380, "Open all files" + "Close" (default and cancel), Open-all texts, missing / launch-failure
//       texts), 04 §4.6 + §6.8 (same XAML converter, NSTextView, `clickedOnLink`, Space = Quick Look addition),
//       HIER-M06 (Quick Look), 05 CONT-098, 01 OC-12 (messages name the RESOLVED path), 03 SHELL-685 (⎋ passes to the
//       sheet), SHELL-669/671 (Space / ⌘↓ in the viewer's file list); ARCHITECTURE.md §7.5 (sheet contract:
//       `.aaSheet(.closeType, role: .viewer)`), §7.6 (`AARichTextResponder` with `aaRichKind == .viewer`), §7.7.
import AppKit
import SwiftUI
import AACore

struct ContainerViewerSheet: View {
    let title: String
    let container: Container
    let subtitle: String?

    /// `subtitle == nil` (or blank) shows `FileBankText.viewerDefaultSubtitle`; Saved Lists passes
    /// `BuilderSavedLists.viewerSubtitle(listName:)` (HIER-136, BUILD-076; DECISIONS "Contract amendments
    /// (post-wave)", REQ-W-BUILD-01 / REQ-W-FILES-01).
    init(title: String, container: Container, subtitle: String? = nil) {
        self.title = title; self.container = container; self.subtitle = subtitle
    }

    var body: some View {
        FileBankViewerContent(title: title, container: container,
                              subtitle: NetText.isBlank(subtitle) ? FileBankText.viewerDefaultSubtitle : subtitle ?? "")
            .id(ObjectIdentifier(container))
    }
}

struct FileBankViewerContent: View {
    let title: String
    let container: Container
    let subtitle: String

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<FileBankRow.ID> = []
    @State private var keys = FileBankKeyMonitor()

    var body: some View {
        let rows = viewerRows()
        VStack(spacing: 0) {
            header
            VSplitView {
                FileBankViewerTextArea(content: FileBankViewerBody.make(xaml: container.richTextXaml),
                                       openLink: { target in Task { await openLink(target) } })
                    .frame(minHeight: 140, maxHeight: .infinity)
                filesPane(rows)
                    .frame(minHeight: 110, idealHeight: 180, maxHeight: .infinity)
            }
            footer(rows)
        }
        .frame(width: 820, height: 620)                                    // HIER-136 window size
        .background(AAColor.panel)
        .navigationTitle(FileBankText.viewerWindowTitle(title))
        .accessibilityLabel(FileBankText.viewerWindowTitle(title))
        .aaSheet(.closeType, role: .viewer)
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.aaMono(AAType.title, weight: .bold))
                .foregroundStyle(AAColor.accent)
                .lineLimit(2)
                .textSelection(.enabled)
            Text(subtitle)
                .font(.aaMono(AAType.caption))
                .foregroundStyle(AAColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AASpacing.l)
        .padding(.vertical, AASpacing.m)
        .background(AAColor.panelAlt)
        .overlay(alignment: .bottom) { Rectangle().fill(AAColor.border).frame(height: 1) }
    }

    private func filesPane(_ rows: [FileBankRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "paperclip").foregroundStyle(AAColor.tint)
                Text(rows.isEmpty ? FileBankText.viewerFilesNone : FileBankText.viewerFilesCount(rows.count))
                    .font(.aaMono(AAType.small, weight: .bold))
                    .foregroundStyle(AAColor.fg)
                Spacer()
            }
            .padding(.horizontal, AASpacing.m)
            .padding(.vertical, 6)
            if rows.isEmpty {
                Text(FileBankText.viewerNoFiles)
                    .font(.system(size: AAType.small))
                    .foregroundStyle(AAColor.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                filesTable(rows)
            }
        }
        .background(AAColor.panel)
    }

    private func filesTable(_ rows: [FileBankRow]) -> some View {
        Table(of: FileBankRow.self, selection: $selection) {
            TableColumn(FileBankText.columnName) { r in
                HStack(spacing: 6) {
                    FileBankFileIcon(visual: r.visual, size: 16)
                    Text(r.file.name).lineLimit(1).truncationMode(.middle)
                }
                .help(r.file.name)
            }
            .width(min: 120, ideal: 260)
            TableColumn(FileBankText.columnKind) { r in Text(FileBankDisplay.kindName(r.file.kind)) }
                .width(min: 50, ideal: 80, max: 120)
            TableColumn(FileBankText.columnSource) { r in FileBankSourceLabel(file: r.file) }
                .width(min: 70, ideal: 86, max: 120)
            TableColumn(FileBankText.viewerPathColumn) { r in
                Text(r.file.path).font(.aaMono(AAType.caption)).foregroundStyle(AAColor.muted)
                    .lineLimit(1).truncationMode(.middle).help(r.file.path)
            }
            .width(min: 120, ideal: 380)
        } rows: {
            ForEach(rows) { r in
                TableRow(r).itemProvider { [url = r.dragURL, web = r.isWeb] in FileBankTable.provider(url, web: web) }
            }
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds(.enabled)
        .contextMenu(forSelectionType: FileBankRow.ID.self) { ids in
            let picked = rows.filter { ids.contains($0.id) }
            if !picked.isEmpty {
                Button(FileBankText.menuOpen) { open(picked.map(\.file)) }
                Button(FileBankText.menuShowInFinder) {
                    if let f = picked.first?.file { Task { await FileBankOpening.showInFinder(f, env: env, dialogs: dialogs) } }
                }
                Button(FileBankText.menuQuickLook) { quickLook(rows, ids, toggle: false) }
                    .disabled(!picked.contains { $0.visual.localURL != nil })
                Divider()
                Button(FileBankText.menuCopyPath) {
                    let text = picked.map { FileBankResolve.target(of: $0.file, dataStore: env.dataStore) }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text.joined(separator: "\n"), forType: .string)
                }
            }
        } primaryAction: { ids in
            open(rows.filter { ids.contains($0.id) }.map(\.file))         // double-click opens (HIER-136)
        }
        .background(FileBankKeyAnchor(monitor: keys, onSpace: { [sel = selection] in quickLook(rows, sel, toggle: true) },
                                      onOpen: { [sel = selection] in open(rows.filter { sel.contains($0.id) }.map(\.file)) }))
        .onAppear { keys.install() }
        .onDisappear { keys.remove() }
        .aaListCommands(viewerListCommands(rows))
    }

    /// SHELL-543 / SHELL-669: Open and Quick Look only; Quick Look while the selection holds a local file.
    private func viewerListCommands(_ rows: [FileBankRow]) -> ListCommands {
        let sel = selection
        let hasLocal = rows.contains { sel.contains($0.id) && $0.visual.localURL != nil }
        return ListCommands(role: .viewerFiles, selectionCount: sel.count,
                            quickLook: FileBankListPolicy.quickLookAvailable(selectionHasLocalFile: hasLocal)
                                ? { quickLook(rows, sel, toggle: false) } : nil,
                            primary: { open(rows.filter { sel.contains($0.id) }.map(\.file)) })
    }

    private func footer(_ rows: [FileBankRow]) -> some View {
        HStack(spacing: AASpacing.s) {
            Spacer()
            Button {
                Task { await openAll(rows.map(\.file)) }
            } label: {
                Label(FileBankText.viewerOpenAllFiles, systemImage: "square.stack.3d.up")
            }
            .help(FileBankText.viewerOpenAllFilesHelp)
            Button(FileBankText.viewerClose) { dismiss() }
                .keyboardShortcut(.defaultAction)
                .aaProminent()
        }
        .padding(.horizontal, AASpacing.l)
        .padding(.vertical, AASpacing.m)
        .background(AAColor.panelAlt)
        .overlay(alignment: .top) { Rectangle().fill(AAColor.border).frame(height: 1) }
    }

    // MARK: Behaviour

    private func viewerRows() -> [FileBankRow] {
        var occurrences: [ObjectIdentifier: Int] = [:]
        return container.files.map { f in
            let key = ObjectIdentifier(f)
            let n = occurrences[key, default: 0]
            occurrences[key] = n + 1
            return FileBankRow(id: .init(container: ObjectIdentifier(container), file: key, occurrence: n), file: f,
                               container: container, owner: nil, visual: FileBankVisual(f, dataStore: env.dataStore),
                               linkedSummary: "", added: "")
        }
    }

    private func open(_ files: [FileItem]) {
        Task { for f in files { await FileBankOpening.open(f, env: env, dialogs: dialogs, style: .viewer) } }
    }

    private func quickLook(_ rows: [FileBankRow], _ ids: Set<FileBankRow.ID>, toggle: Bool) {
        if toggle, QuickLookCoordinator.shared.isVisible { QuickLookCoordinator.shared.close(); return }
        let sel = rows.filter { ids.contains($0.id) }.map(\.file)
        guard !sel.isEmpty else { NSSound.beep(); return }
        FileBankOpening.quickLook(sel.count > 1 ? sel : rows.map(\.file), selected: sel.first, env: env, toggle: false)
    }

    /// HIER-136: none → "This item has no files."; more than 15 → "Open all {n} files?" (Yes/No).
    private func openAll(_ files: [FileItem]) async {
        guard !files.isEmpty else {
            await dialogs.info(FileBankText.viewerOpenAllFilesTitle, FileBankText.viewerNoFiles)
            return
        }
        if FileBankDisplay.openAllNeedsConfirmation(files.count) {
            let yes = await dialogs.alert(AlertSpec(title: FileBankText.viewerOpenAllFilesTitle,
                                                    message: FileBankText.viewerOpenAllPrompt(files.count),
                                                    buttons: [AlertButton(title: FileBankText.yes, role: .default),
                                                              AlertButton(title: FileBankText.no, role: .cancel)])) == 0
            guard yes else { return }
        }
        for f in files { await FileBankOpening.open(f, env: env, dialogs: dialogs, style: .viewer) }
    }

    /// A clicked hyperlink (single click, HIER-136): web text is normalised (`www.` → https, `x@y` → mailto).
    private func openLink(_ target: String) async {
        guard !NetText.isBlank(target) else { return }
        let url = AttachmentOpener.normalizeWebLink(target) ?? URL(string: target)
        guard let url, NSWorkspace.shared.open(url) else {
            await dialogs.warning(FileBankText.viewerOpenTitle,
                                  FileBankText.viewerCouldNotOpen(target, FileBankText.viewerNoLinkHandler))
            return
        }
    }
}

// MARK: - The read-only text (NSTextView)

struct FileBankViewerTextArea: NSViewRepresentable {
    let content: FileBankViewerBody
    let openLink: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(openLink: openLink) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = AAColor.NS.editorPaper
        scroll.appearance = NSAppearance(named: .aqua)                       // paper in both appearances (HIER-150)
        let tv = FileBankViewerTextView(frame: .zero)
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = true
        tv.drawsBackground = true
        tv.backgroundColor = AAColor.NS.editorPaper
        tv.textColor = AAColor.NS.editorInk
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticLinkDetectionEnabled = false
        tv.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue,
                                 .cursor: NSCursor.pointingHand]
        tv.delegate = context.coordinator
        tv.setAccessibilityLabel(FileBankText.viewerNotesAccessibility)
        scroll.documentView = tv
        apply(content, to: tv)
        context.coordinator.shown = content.identity
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.openLink = openLink
        guard let tv = nsView.documentView as? NSTextView, context.coordinator.shown != content.identity else { return }
        context.coordinator.shown = content.identity
        apply(content, to: tv)
    }

    private func apply(_ c: FileBankViewerBody, to tv: NSTextView) {
        let mono = AAFont.mono(AAType.editor)
        let s: NSAttributedString
        switch c {
        case .placeholder(let text):
            s = NSAttributedString(string: text, attributes: [.font: mono, .foregroundColor: NSColor.gray])
        case .raw(let text):
            s = NSAttributedString(string: text, attributes: [.font: mono, .foregroundColor: AAColor.NS.editorInk])
        case .document(let doc):
            s = doc
        }
        tv.textStorage?.setAttributedString(s)
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        tv.scrollToBeginningOfDocument(nil)
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var openLink: (String) -> Void
        var shown: String?
        init(openLink: @escaping (String) -> Void) { self.openLink = openLink }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            switch link {
            case let u as URL: openLink(u.absoluteString)
            case let s as String: openLink(s)
            default: return false
            }
            return true
        }
    }
}

extension FileBankViewerBody {
    /// A cheap identity so the text view reloads only when the content changes.
    var identity: String {
        switch self {
        case .placeholder(let t): return "p:" + t
        case .raw(let t): return "r:\(t.hashValue)"
        case .document(let d): return "d:\(d.string.hashValue)|\(d.length)"
        }
    }
}

/// The viewer's text view: read-only, find bar, Find menu routed through `AARichTextResponder` (`.viewer`), and ⎋
/// passed on to the sheet (SHELL-685).
final class FileBankViewerTextView: NSTextView, AARichTextResponder {
    var aaRichKind: RichKind { .viewer }

    func aaValidate(_ c: FormatCommand) -> Bool {
        switch c {
        case .showFind, .findNext, .findPrevious, .useSelectionForFind, .jumpToSelection: return true
        default: return false
        }
    }

    func aaPerform(_ c: FormatCommand) {
        let action: NSTextFinder.Action
        switch c {
        case .showFind: action = .showFindInterface
        case .findNext: action = .nextMatch
        case .findPrevious: action = .previousMatch
        case .useSelectionForFind: action = .setSearchString
        case .jumpToSelection:
            scrollRangeToVisible(selectedRange())
            return
        default: return
        }
        let item = NSMenuItem()
        item.tag = action.rawValue
        performTextFinderAction(item)
    }

    override func cancelOperation(_ sender: Any?) {
        if nextResponder?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: sender) != true {
            super.cancelOperation(sender)
        }
    }
}
