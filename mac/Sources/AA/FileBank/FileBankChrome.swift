// Spec: 05 CONT-080 (header: "File Bank" + Add File / Link in place / Add Folder / Add Link / Cut / Copy / Paste /
//       Remove / Open / Open all with their tooltips, accent buttons, the drop hint; the six tabs), 05 §6.9 (labelled
//       buttons with SF Symbols, category switcher with per-tab counts, hint "hold ⌥⌘ or ⇧ to link in place"),
//       CONT-085 + SHELL-679 (drop: none = copy, ⇧ or ⌥⌘ = link in place; any tab accepts), DECISIONS 05 (Sharing
//       menu for `SharedWithContainerIds`); ARCHITECTURE.md §8 (design tokens, native controls, hover, animation).
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

// MARK: - Header

struct FileBankHeaderActions {
    var addFile, linkInPlace, addFolder, addLink, cut, copy, paste, remove, open, openAll: () -> Void
}

struct FileBankHeaderBar: View {
    let title: String
    let total: Int
    let editable: Bool
    let canEditSelection: Bool
    let hasSelection: Bool
    let hasShown: Bool
    let actions: FileBankHeaderActions

    var body: some View {
        HStack(spacing: AASpacing.s) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full").foregroundStyle(AAColor.tint)
                Text(title).font(.aaMono(AAType.small, weight: .bold)).foregroundStyle(AAColor.fg)
                    .fixedSize()
                if total > 0 {
                    Text("\(total)").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(AAColor.muted)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(AAColor.muted.opacity(0.14), in: Capsule())
                }
            }
            .layoutPriority(1)
            Spacer(minLength: AASpacing.s)
            ViewThatFits(in: .horizontal) {
                buttons(.full)
                buttons(.primaryTitles)
                buttons(.iconsOnly)
            }
        }
        .padding(.horizontal, AASpacing.m)
        .padding(.vertical, 6)
        .background(AAColor.panelAlt)
    }

    enum Density { case full, primaryTitles, iconsOnly }

    private func buttons(_ d: Density) -> some View {
        HStack(spacing: 6) {
            group {
                FileBankHeaderButton(title: FileBankText.addFile, symbol: "doc.badge.plus", help: FileBankText.addFileHelp,
                                     showsTitle: d != .iconsOnly, action: actions.addFile)
                FileBankHeaderButton(title: FileBankText.linkInPlace, symbol: "link.badge.plus",
                                     help: FileBankText.linkInPlaceHelp, prominent: true, showsTitle: d != .iconsOnly,
                                     action: actions.linkInPlace)
                FileBankHeaderButton(title: FileBankText.addFolder, symbol: "folder.badge.plus",
                                     help: FileBankText.addFolderHelp, showsTitle: d != .iconsOnly, action: actions.addFolder)
                FileBankHeaderButton(title: FileBankText.addLink, symbol: "globe", help: FileBankText.addLinkHelp,
                                     showsTitle: d != .iconsOnly, action: actions.addLink)
            }
            .disabled(!editable)
            FileBankHeaderSeparator()
            group {
                FileBankHeaderButton(title: FileBankText.cut, symbol: "scissors", help: FileBankText.cut,
                                     showsTitle: d == .full, action: actions.cut)
                    .disabled(!canEditSelection)
                FileBankHeaderButton(title: FileBankText.copy, symbol: "doc.on.doc", help: FileBankText.copy,
                                     showsTitle: d == .full, action: actions.copy)
                FileBankHeaderButton(title: FileBankText.paste, symbol: "doc.on.clipboard", help: FileBankText.paste,
                                     showsTitle: d == .full, action: actions.paste)
                    .disabled(!editable)
                FileBankHeaderButton(title: FileBankText.remove, symbol: "minus.circle", help: FileBankText.remove,
                                     showsTitle: d == .full, action: actions.remove)
                    .disabled(!canEditSelection)
            }
            FileBankHeaderSeparator()
            group {
                FileBankHeaderButton(title: FileBankText.open, symbol: "arrow.up.forward.app", help: FileBankText.open,
                                     showsTitle: d != .iconsOnly, action: actions.open)
                    .disabled(!hasSelection)
                FileBankHeaderButton(title: FileBankText.openAll, symbol: "square.stack.3d.up",
                                     help: FileBankText.openAllHelp, prominent: true, showsTitle: d != .iconsOnly,
                                     action: actions.openAll)
                    .disabled(!hasShown)
            }
        }
        .fixedSize()
    }

    private func group<C: View>(@ViewBuilder _ c: () -> C) -> some View { HStack(spacing: 4) { c() } }
}

struct FileBankHeaderSeparator: View {
    var body: some View {
        Rectangle().fill(AAColor.border).frame(width: 1, height: 16).padding(.horizontal, 2)
    }
}

struct FileBankHeaderButton: View {
    let title: String
    let symbol: String
    let help: String
    var prominent = false
    var showsTitle = true
    let action: () -> Void

    var body: some View {
        if prominent {
            button.buttonStyle(.borderedProminent).fontWeight(.semibold)        // WPF AccentButton (03 §6.6.5)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var button: some View {
        Button(action: action) {
            if showsTitle {
                Label(title, systemImage: symbol).labelStyle(.titleAndIcon)
            } else {
                Label(title, systemImage: symbol).labelStyle(.iconOnly).frame(minWidth: 16)
            }
        }
        .controlSize(.small)
        .help(help)
        .accessibilityLabel(title)
    }
}

// MARK: - Scope bar (tabs, view mode, sharing)

struct FileBankScopeBar<Trailing: View>: View {
    @Binding var scope: FileBankScope
    @Binding var mode: FileBankViewMode
    let counts: [FileBankTab: Int]
    let sharedInCount: Int
    let showsShared: Bool
    /// The trailing control (the Sharing menu); `true` asks for its compact form.
    @ViewBuilder var trailing: (_ compact: Bool) -> Trailing

    enum Density { case full, noIcons, iconsOnly }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(.full)
            row(.noIcons)
            row(.iconsOnly)
        }
        .padding(.horizontal, AASpacing.m)
        .padding(.vertical, 5)
    }

    private func row(_ d: Density) -> some View {
        HStack(spacing: AASpacing.s) {
            HStack(spacing: 2) {
                ForEach(FileBankTab.allCases, id: \.self) { t in
                    chip(.tab(t), title: t.title, symbol: t.symbol, count: counts[t] ?? 0, density: d)
                }
                if showsShared {
                    Rectangle().fill(AAColor.border).frame(width: 1, height: 14).padding(.horizontal, 4)
                    chip(.shared, title: FileBankText.sharedTab, symbol: "folder.badge.person.crop", count: sharedInCount,
                         density: d)
                }
            }
            .fixedSize()
            Spacer(minLength: AASpacing.s)
            Picker("", selection: $mode) {
                Label(FileBankText.viewAsList, systemImage: "list.bullet").tag(FileBankViewMode.list)
                Label(FileBankText.viewAsIcons, systemImage: "square.grid.2x2").tag(FileBankViewMode.icons)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .fixedSize()
            .help("View the files as a list or as icons")
            trailing(d == .iconsOnly)
        }
    }

    private func chip(_ s: FileBankScope, title: String, symbol: String, count: Int, density: Density) -> some View {
        FileBankScopeChip(title: title, symbol: symbol, count: count, selected: scope == s,
                          showsIcon: density != .noIcons, showsTitle: density != .iconsOnly) {
            withAnimation(.snappy(duration: 0.22)) { scope = s }
        }
    }
}

struct FileBankScopeChip: View {
    let title: String
    let symbol: String
    let count: Int
    let selected: Bool
    var showsIcon = true
    var showsTitle = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if showsIcon { Image(systemName: symbol).imageScale(.small) }
                if showsTitle { Text(title).fixedSize() }
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(selected ? Color.white.opacity(0.9) : AAColor.muted)
            }
            .font(.system(size: AAType.caption, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Color.white : AAColor.fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                if selected {
                    Capsule().fill(AAColor.tint)
                } else if hovering {
                    Capsule().fill(AAColor.hover)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(showsTitle ? "" : title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel("\(title), \(count)")
    }
}

// MARK: - Sharing menu (DECISIONS 05, CONT-095)

struct FileBankSharingMenu: View {
    let container: Container
    let controller: FileBankController
    let editable: Bool
    var compact = false
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let sharedWithCount = container.sharedWithContainerIds.count
        Menu {
            Button(FileBankText.shareWith) { Task { await controller.shareWith() } }
                .disabled(!editable)
            menuSections
        } label: {
            if compact {
                Label(FileBankText.sharing, systemImage: "folder.badge.person.crop").labelStyle(.iconOnly)
            } else {
                Label(sharedWithCount > 0 ? FileBankText.sharedWithCount(sharedWithCount) : FileBankText.sharing,
                      systemImage: "folder.badge.person.crop")
                    .labelStyle(.titleAndIcon)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .help(FileBankText.sharePickerPrompt("this file bank"))
    }

    @ViewBuilder private var menuSections: some View {
        let dir = FileBankDirectory(store: env.store)
        let with = dir.sharedWith(container)
        let into = dir.sharedInto(container)
        Section(FileBankText.sharedWithHeader) {
            if with.isEmpty {
                Text(FileBankText.notShared)
            } else {
                ForEach(Array(with.enumerated()), id: \.offset) { _, e in
                    Menu(e.owner.label) {
                        Button(FileBankText.menuGoToOwner) { FileBankNavigation.reveal(e.owner, env: env) }
                        Button("Stop Sharing") { controller.stopSharing(with: e.container) }.disabled(!editable)
                    }
                }
            }
        }
        Section(FileBankText.sharedIntoHeader) {
            if into.isEmpty {
                Text(FileBankText.nothingSharedIn)
            } else {
                ForEach(Array(into.enumerated()), id: \.offset) { _, e in
                    Button(e.owner.label) { FileBankNavigation.reveal(e.owner, env: env) }
                }
            }
        }
    }
}

// MARK: - Footer

struct FileBankFooter: View {
    let shown: Int
    let selected: Int
    let isShared: Bool
    let lockedSharers: [String]

    var body: some View {
        HStack(spacing: AASpacing.s) {
            Text(countText).monospacedDigit().foregroundStyle(AAColor.muted)
            if !lockedSharers.isEmpty {
                Label("\(lockedSharers.count) locked", systemImage: "lock.fill")
                    .foregroundStyle(AAColor.muted)
                    .help(lockedSharers.map { "\($0) \(FileBankText.lockedOwnerFiles)" }.joined(separator: "\n"))
            }
            Spacer(minLength: AASpacing.s)
            Text(isShared ? FileBankText.sharedReadOnlyHint : FileBankText.dropHint)
                .foregroundStyle(AAColor.muted)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: AAType.caption))
        .padding(.horizontal, AASpacing.m)
        .padding(.vertical, 4)
        .background(AAColor.panelAlt)
        .overlay(alignment: .top) { Rectangle().fill(AAColor.border).frame(height: 1) }
    }

    private var countText: String {
        let items = shown == 1 ? "1 item" : "\(shown) items"
        return selected > 0 ? "\(selected) of \(items) selected" : items
    }
}

// MARK: - Drop (CONT-085, SHELL-679)

/// Live drop feedback (observed by the overlay).
@MainActor @Observable final class FileBankDropState {
    var targeted = false
    var linkInPlace = false
}

struct FileBankDropDelegate: DropDelegate {
    let state: FileBankDropState
    let enabled: Bool
    let perform: @MainActor ([URL], [URL], Bool) -> Void

    /// ⇧, or ⌥⌘ (Finder's make-alias gesture), held at drop time → link in place.
    @MainActor static func linkModifierActive() -> Bool {
        let f = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return f.contains(.shift) || (f.contains(.option) && f.contains(.command))
    }

    func validateDrop(info: DropInfo) -> Bool { enabled && info.hasItemsConforming(to: [.fileURL, .url]) }

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated {
            withAnimation(.easeOut(duration: 0.12)) { state.targeted = true }
            state.linkInPlace = Self.linkModifierActive()
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        MainActor.assumeIsolated {
            let link = Self.linkModifierActive()
            if state.linkInPlace != link { state.linkInPlace = link }
            return DropProposal(operation: enabled ? .copy : .forbidden)     // SwiftUI has no link operation; the overlay names the mode
        }
    }

    func dropExited(info: DropInfo) {
        MainActor.assumeIsolated { withAnimation(.easeOut(duration: 0.12)) { state.targeted = false } }
    }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated {
            let link = Self.linkModifierActive()
            state.targeted = false
            guard enabled else { return false }
            let providers = info.itemProviders(for: [.fileURL, .url])
            guard !providers.isEmpty else { return false }
            Task { @MainActor in
                var files: [URL] = []
                var webs: [URL] = []
                for p in providers {
                    let isFile = p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                    guard let url = await FileBankDropDelegate.loadURL(p) else { continue }
                    if isFile || url.isFileURL { files.append(url) } else { webs.append(url) }
                }
                perform(files, webs, link)
            }
            return true
        }
    }

    @MainActor static func loadURL(_ p: NSItemProvider) async -> URL? {
        await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            _ = p.loadObject(ofClass: URL.self) { url, _ in cont.resume(returning: url) }
        }
    }
}

struct FileBankDropOverlay: View {
    let state: FileBankDropState

    var body: some View {
        if state.targeted {
            ZStack {
                RoundedRectangle(cornerRadius: AARadius.tile, style: .continuous)
                    .fill(AAColor.tint.opacity(0.08))
                RoundedRectangle(cornerRadius: AARadius.tile, style: .continuous)
                    .strokeBorder(AAColor.tint, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                Label(state.linkInPlace ? "Drop to link in place (originals are referenced)"
                                        : "Drop to import a copy",
                      systemImage: state.linkInPlace ? "link" : "plus.rectangle.on.folder")
                    .font(.system(size: AAType.small, weight: .semibold))
                    .foregroundStyle(AAColor.tint)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(AAColor.panel, in: Capsule())
                    .overlay(Capsule().strokeBorder(AAColor.tint.opacity(0.4)))
                    .contentTransition(.opacity)
            }
            .padding(4)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}
