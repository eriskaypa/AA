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
    /// The table's rows, rebuilt only when the query or the section titles change (ARCH §9.7), never per body pass.
    @State private var rows: [ShellXShortcutTableRow] = []
    @State private var shown = 0

    private var sectionTitles: [String] { env.navigator.sectionOrder.map(\.title) }

    var body: some View {
        VStack(spacing: 0) {
            header(count: shown)
            Divider()
            if rows.isEmpty {
                AAEmptyState(title: "No Matching Shortcuts", symbol: "magnifyingglass",
                             message: "Nothing in the registry matches “\(NetText.trim(query))”.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
            }
        }
        .frame(minWidth: 820, minHeight: 480)
        .background(AAColor.bg)
        .onAppear(perform: rebuild)
        .onChange(of: query) { _, _ in rebuild() }
        .onChange(of: sectionTitles) { _, _ in rebuild() }
    }

    /// A native table (real column headers that line up with the cells, resizable columns). The menu groups are title
    /// rows of the same flat table: `Section`s make SwiftUI build an outline view that logs an AppKit reentrancy
    /// warning on every render (rule 18).
    private var table: some View {
        Table(rows) {
            TableColumn("Command") { row in
                switch row {
                case .header(let title, let count, let isFirst):
                    AASectionHeader(title: title, count: count)
                        .padding(.top, isFirst ? 2 : AASpacing.m)
                        .accessibilityAddTraits(.isHeader)
                case .entry(let e):
                    ShellXShortcutCommandCell(entry: e)
                }
            }
            .width(min: 190, ideal: 260)
            TableColumn("Mac") { row in
                if let e = row.entry { ShellXKeycaps(chords: e.chords) }
            }
            .width(min: 100, ideal: 140)
            TableColumn("Windows") { row in
                if let e = row.entry {
                    Text(e.windows)
                        .foregroundStyle(AAColor.muted)
                        .lineLimit(2)
                        .help(e.windows)
                }
            }
            .width(min: 150, ideal: 250)
            TableColumn("Menu") { row in
                if let e = row.entry {
                    Text(e.menu)
                        .foregroundStyle(AAColor.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(e.menu)
                }
            }
            .width(min: 90, ideal: 150)
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .font(.aaMono(AAType.small))
    }

    private func rebuild() {
        let groups = ShellXShortcutCatalog.groups(sectionTitles: sectionTitles, query: query)
        rows = ShellXShortcutCatalog.tableRows(groups)
        shown = ShellXShortcutCatalog.count(groups)
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .center, spacing: AASpacing.m) {
            Image(systemName: "keyboard")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(AAColor.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("AA Keyboard Shortcuts").font(.aaMono(AAType.title, weight: .bold))
                Text(count == 1 ? "1 shortcut" : "\(count) shortcuts")
                    .font(.aaMono(AAType.caption))
                    .foregroundStyle(AAColor.muted)
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
            Text("—").foregroundStyle(AAColor.muted)
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
                    Text("+\(chords.count - 3)").font(.aaMono(AAType.caption)).foregroundStyle(AAColor.muted)
                }
            }
            .help(chords.joined(separator: ", "))
        }
    }
}
