// Spec: 03 SHELL-523 (Help ▸ AA Keyboard Shortcuts: single-instance window, ⌘W closes it, the registry grouped by menu,
//       a search field, columns Command, Mac, Windows (the old gesture) and Menu, generated from the registry so it
//       never drifts), SHELL-630 (section items named after the tabs in display order), §6.5.1.4 (in-window keys),
//       §6.5.1.9 (key renderings); ARCHITECTURE.md §7.6 ("renders `ShortcutRegistry.rows`"), §8.
import AppKit
import SwiftUI
import AACore

struct KeyboardShortcutsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var query = ""

    private var groups: [ShellXShortcutGroup] {
        ShellXShortcutCatalog.groups(sectionTitles: env.navigator.sectionOrder.map(\.title), query: query)
    }

    var body: some View {
        let groups = self.groups
        VStack(spacing: 0) {
            header(count: ShellXShortcutCatalog.count(groups))
            Divider()
            if groups.isEmpty {
                AAEmptyState(title: "No Matching Shortcuts", symbol: "magnifyingglass",
                             message: "Nothing in the registry matches “\(NetText.trim(query))”.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // A native table: real column headers that always line up with the cells, resizable columns.
                Table(of: ShellXShortcutEntry.self) {
                    TableColumn("Command") { ShellXShortcutCommandCell(entry: $0) }
                        .width(min: 190, ideal: 260)
                    TableColumn("Mac") { ShellXKeycaps(chords: $0.chords) }
                        .width(min: 100, ideal: 140)
                    TableColumn("Windows") { e in
                        Text(e.windows)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .help(e.windows)
                    }
                    .width(min: 150, ideal: 250)
                    TableColumn("Menu") { e in
                        Text(e.menu)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(e.menu)
                    }
                    .width(min: 90, ideal: 150)
                } rows: {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.entries) { TableRow($0) }
                        } header: {
                            AASectionHeader(title: group.title, count: group.entries.count)
                        }
                    }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .font(.system(size: AAType.small))
            }
        }
        .frame(minWidth: 820, minHeight: 480)
        .background(AAColor.bg)
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .center, spacing: AASpacing.m) {
            Image(systemName: "keyboard")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(AAColor.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("AA Keyboard Shortcuts").font(.system(size: AAType.title, weight: .semibold))
                Text(count == 1 ? "1 shortcut" : "\(count) shortcuts")
                    .font(.system(size: AAType.caption))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            AASearchField(text: $query, prompt: "Search commands or keys")
                .frame(width: 300)
        }
        .padding(.horizontal, AASpacing.l)
        .padding(.vertical, AASpacing.m)
    }
}

/// The Command cell: the menu item's SF Symbol (a muted ⌘ when it has none) and its title; the WPF tooltip on hover.
private struct ShellXShortcutCommandCell: View {
    let entry: ShellXShortcutEntry

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.symbol ?? "command")
                .foregroundStyle(entry.symbol == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(AAColor.tint))
                .frame(width: 16)
            Text(entry.title).lineLimit(2)
        }
        .help(entry.help ?? entry.title)
        .accessibilityElement(children: .combine)
    }
}

/// Key chords rendered as keycaps (`⇧⌘S`, `⎋`); a dash when the row has no key.
private struct ShellXKeycaps: View {
    let chords: [String]

    var body: some View {
        if chords.isEmpty {
            Text("—").foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 4) {
                ForEach(Array(chords.prefix(3).enumerated()), id: \.offset) { _, chord in
                    Text(chord)
                        .font(.system(size: AAType.caption, weight: .medium, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(AAColor.panelAlt, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(AAColor.border, lineWidth: 1))
                        .fixedSize()
                }
                if chords.count > 3 {
                    Text("+\(chords.count - 3)").font(.system(size: AAType.caption)).foregroundStyle(.secondary)
                }
            }
            .help(chords.joined(separator: ", "))
        }
    }
}
