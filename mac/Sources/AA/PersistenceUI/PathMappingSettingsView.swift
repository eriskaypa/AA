// Spec: DECISIONS 10 Q4 (per-device path-mapping table in Settings ▸ File Links, applied only when opening; UNC →
//       smb:// fallback), 01 §6.6 (Windows live links: "Locate…" stores a Windows prefix → Mac folder mapping in
//       UserDefaults; derivable from smb://srv/share), 05 §6.9, ARCHITECTURE.md §7.7 (W-SHELL embeds this view), §9.4.
import AppKit
import SwiftUI
import AACore

struct PathMappingSettingsView: View {
    @State private var mapper: PathMapper
    @State private var selection: Set<Int> = []
    @State private var editing: PersistMappingDraft?
    @State private var probe = ""

    init() { _mapper = State(initialValue: PathMapper.shared) }

    /// Snapshots and previews use an in-memory table (never the real preferences).
    init(mapper: PathMapper, probe: String = "") {
        _mapper = State(initialValue: mapper)
        _probe = State(initialValue: probe)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.m) {
            AAHelpText(PersistPathText.intro)
            table
            HStack(spacing: AASpacing.s) {
                ControlGroup {
                    Button { editing = PersistMappingDraft() } label: { Image(systemName: "plus") }
                        .help("Add a mapping")
                    Button { removeSelected() } label: { Image(systemName: "minus") }
                        .disabled(selection.isEmpty)
                        .help("Remove the selected mappings")
                }
                .fixedSize()
                Button("Edit…") { editSelected() }
                    .disabled(selection.count != 1)
                Spacer()
                Text(mapper.mappings.count == 1 ? "1 mapping" : "\(mapper.mappings.count) mappings")
                    .font(.system(size: AAType.caption)).foregroundStyle(AAColor.muted)
            }
            .controlSize(.small)
            Divider().padding(.vertical, 2)
            tester
        }
        .padding(AASpacing.l)
        .frame(minWidth: 560, minHeight: 380, alignment: .topLeading)
        .sheet(item: $editing) { draft in
            PersistMappingEditor(draft: draft) { saved in
                if let saved {
                    if let old = draft.original, old.windowsPrefix != saved.windowsPrefix,
                       let i = mapper.mappings.firstIndex(of: old) {
                        mapper.mappings.remove(at: i)
                    }
                    mapper.upsert(saved)
                }
                editing = nil
            }
        }
    }

    private var table: some View {
        Table(Array(mapper.mappings.enumerated()).map { PersistMappingRow(index: $0.offset, mapping: $0.element) },
              selection: $selection) {
            TableColumn("Windows path") { row in
                Text(row.mapping.windowsPrefix).font(.aaMono(AAType.small)).lineLimit(1).truncationMode(.middle)
                    .help(row.mapping.windowsPrefix)
            }
            .width(min: 140, ideal: 180)
            TableColumn("Folder on this Mac") { row in
                HStack(spacing: 6) {
                    let ok = PersistPathText.reachable(row.mapping.macPath)
                    Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(ok ? AAColor.Status.ok : AAColor.Status.dueSoon)
                        .help(ok ? "Folder found" : "Not reachable right now (not mounted?)")
                    Text(row.mapping.macPath).font(.aaMono(AAType.small)).lineLimit(1).truncationMode(.middle)
                        .help(row.mapping.macPath)
                }
            }
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            if ids.count == 1, let i = ids.first {
                Button("Edit…") { editing = PersistMappingDraft(mapper.mappings[i]) }
                Button("Show in Finder") { revealMac(mapper.mappings[i].macPath) }
            }
            if !ids.isEmpty {
                Divider()
                Button("Remove") { remove(ids) }
            }
        } primaryAction: { ids in
            if ids.count == 1, let i = ids.first { editing = PersistMappingDraft(mapper.mappings[i]) }
        }
        .alternatingRowBackgrounds(mapper.mappings.isEmpty ? .disabled : .enabled)
        .overlay {
            if mapper.mappings.isEmpty {
                AAEmptyState(title: "No mappings", symbol: "externaldrive.connected.to.line.below",
                             message: "Add one with + — for example Z: → /Volumes/Ship.")
            }
        }
        .frame(minHeight: 150)
    }

    private var tester: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Try a Windows path").font(.system(size: AAType.small, weight: .semibold))
            // Verbatim texts: a LocalizedStringKey literal would read `\\` as a Markdown escape and show one backslash.
            TextField(text: $probe, prompt: Text(verbatim: PersistPathText.probePrompt)) {
                Text(verbatim: "Windows path to try")
            }
                .textFieldStyle(.roundedBorder)
                .font(.aaMono(AAType.small))
            let r = PersistPathText.resolve(probe, mapper: mapper)
            if !NetText.isBlank(probe) {
                Label(r.text, systemImage: r.symbol)
                    .font(.system(size: AAType.small))
                    .foregroundStyle(r.ok ? AAColor.Status.ok : AAColor.Status.dueSoon)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.snappy, value: r.text)
            }
        }
    }

    private func editSelected() {
        guard selection.count == 1, let i = selection.first, i < mapper.mappings.count else { return }
        editing = PersistMappingDraft(mapper.mappings[i])
    }

    private func removeSelected() { remove(selection) }

    private func remove(_ ids: Set<Int>) {
        withAnimation(.snappy) {
            mapper.mappings = mapper.mappings.enumerated().filter { !ids.contains($0.offset) }.map(\.element)
        }
        selection.removeAll()
    }

    private func revealMac(_ path: String) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}

struct PersistMappingRow: Identifiable {
    let index: Int
    let mapping: PathMapping
    var id: Int { index }
}

/// The add/edit sheet's working copy.
struct PersistMappingDraft: Identifiable {
    let id = UUID()
    var original: PathMapping?
    var windowsPrefix = ""
    var macPath = ""

    init() {}
    init(_ m: PathMapping) { original = m; windowsPrefix = m.windowsPrefix; macPath = m.macPath }
}

struct PersistMappingEditor: View {
    @State var draft: PersistMappingDraft
    let finish: (PathMapping?) -> Void

    init(draft: PersistMappingDraft, finish: @escaping (PathMapping?) -> Void) {
        _draft = State(initialValue: draft); self.finish = finish
    }

    private var valid: Bool { PathMapper.isValidPrefix(draft.windowsPrefix) && !NetText.isBlank(draft.macPath) }

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.m) {
            Text(draft.original == nil ? "Add a mapping" : "Edit mapping").font(.system(size: 14, weight: .bold))
            Form {
                TextField(text: $draft.windowsPrefix, prompt: Text(verbatim: PersistPathText.prefixPrompt)) {
                    Text(verbatim: "Windows path")
                }
                    .font(.aaMono(AAType.body))
                HStack {
                    TextField(text: $draft.macPath, prompt: Text(verbatim: "/Volumes/Share or smb://server/share")) {
                        Text(verbatim: "Folder on this Mac")
                    }
                        .font(.aaMono(AAType.body))
                    Button("Choose…") { choose() }
                }
            }
            .formStyle(.columns)
            if !NetText.isBlank(draft.windowsPrefix), !PathMapper.isValidPrefix(draft.windowsPrefix) {
                Label { Text(verbatim: PersistPathText.invalidPrefix) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                    .font(.system(size: AAType.small)).foregroundStyle(AAColor.Status.dueSoon)
            } else {
                AAHelpText("Everything after the Windows path is added to the Mac folder when a file is opened.")
            }
            HStack {
                Spacer()
                Button("Cancel") { finish(nil) }.keyboardShortcut(.cancelAction)
                Button(draft.original == nil ? "Add" : "Save") {
                    finish(PathMapping(windowsPrefix: draft.windowsPrefix, macPath: draft.macPath))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
                .aaProminent()
            }
        }
        .padding(AASpacing.l)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .aaSheet(.decision)
    }

    private func choose() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.prompt = "Choose"
        p.message = "Choose the folder on this Mac that matches \(NetText.isBlank(draft.windowsPrefix) ? "the Windows path" : draft.windowsPrefix)"
        if p.runModal() == .OK, let url = p.url { draft.macPath = url.path }
    }
}

/// Texts and resolution summaries of the File Links settings.
enum PersistPathText {
    static let intro = "Files linked on Windows keep their Windows paths (Z:\\…, \\\\server\\share\\…). When you open one on this Mac, AA replaces the Windows part with the folder you map here. The stored paths never change, and these mappings stay on this Mac."

    static let probePrompt = "Z:\\Manuals\\Pump.pdf or \\\\server\\share\\file.pdf"
    static let prefixPrompt = "Z:  or  \\\\server\\share"
    static let invalidPrefix = "Use a drive (Z: or Z:\\Folder) or a share (\\\\server\\share)."

    static func reachable(_ macPath: String) -> Bool {
        let t = NetText.trim(macPath)
        if t.lowercased().hasPrefix("smb://") || t.lowercased().hasPrefix("afp://") { return true }
        return FileManager.default.fileExists(atPath: (t as NSString).expandingTildeInPath)
    }

    @MainActor static func resolve(_ text: String, mapper: PathMapper) -> (text: String, symbol: String, ok: Bool) {
        let s = NetText.trim(text)
        guard PathMapper.isWindowsPath(s) else {
            return ("Not a Windows path — paths like Z:\\Folder\\file.pdf or \\\\server\\share\\file.pdf are mapped.",
                    "questionmark.circle", false)
        }
        if let url = mapper.macURL(for: s) {
            if !url.isFileURL { return ("Opens \(url.absoluteString) (Finder connects to the share)", "network", true) }
            let exists = FileManager.default.fileExists(atPath: url.path)
            return (exists ? "Opens \(url.path)" : "Maps to \(url.path) — not found right now",
                    exists ? "checkmark.circle.fill" : "exclamationmark.circle.fill", exists)
        }
        if let smb = PathMapper.smbShareURL(forUNC: s) {
            return ("No mapping — AA offers to connect to \(smb.absoluteString)", "network", false)
        }
        return (PersistOpenerText.unmapped(s), "exclamationmark.triangle.fill", false)
    }
}
