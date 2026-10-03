// Spec: 05 CONT-048, §3.4, §6.11 (Insert Saved List sheet ≈760×560: search + grouped list on the left, Bullets /
//       Numbered radios (bullets every time), duration toggle, monospaced preview, footer note, Cancel (⎋) / Insert
//       (↩, default, bold), empty state), 06 BUILD-100, BUILD-A18, §7.12; ARCHITECTURE.md §7.5 (sheet contract).
import SwiftUI
import AACore

/// The dialog's result: the finished lines and the list style.
struct EditorSavedListChoice: Equatable {
    var lines: [String]
    var numbered: Bool
    var listName: String
}

struct EditorInsertSavedListSheet: View {
    let store: AppStore
    let finish: (EditorSavedListChoice?) -> Void
    @State private var query = ""
    @State private var selection: UUID?
    @State private var numbered = false
    @State private var withDuration = false
    @State private var done = false

    init(store: AppStore, finish: @escaping (EditorSavedListChoice?) -> Void) {
        self.store = store
        self.finish = finish
        _selection = State(initialValue: store.data.checklistTemplates.first?.id)
    }

    private var hasAnyList: Bool { !store.data.checklistTemplates.isEmpty }

    private var groups: [EditorSavedListGroup] {
        EditorSavedListInsert.groups(templates: store.data.checklistTemplates, listGroups: store.data.listGroups,
                                     query: query)
    }

    private var selected: ChecklistTemplate? { selection.flatMap { store.template(id: $0) } }

    private var items: [EditorSavedListItemInfo] { selected.map(EditorSavedListInsert.infos) ?? [] }

    private var lines: [String] { EditorSavedListInsert.lines(items, includeDuration: withDuration) }

    private var footer: String {
        guard hasAnyList else { return EditorSavedListInsert.noListsFooter }
        guard selected != nil else { return "" }
        return EditorSavedListInsert.footer(lineCount: lines.count, items: items)
    }

    private func complete(_ c: EditorSavedListChoice?) {
        guard !done else { return }
        done = true
        finish(c)
    }

    private func insert() {
        guard let t = selected else { return }
        let l = lines
        guard !l.isEmpty else { return }                       // empty → stay open (Windows Ok_Click)
        complete(EditorSavedListChoice(lines: l, numbered: numbered, listName: t.name))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Label(EditorSavedListInsert.header, systemImage: "list.bullet.indent")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AAColor.accent)
                Text(EditorSavedListInsert.subText)
                    .font(.system(size: AAType.small))
                    .foregroundStyle(AAColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 10)

            HStack(alignment: .top, spacing: 12) {
                listColumn.frame(width: 290)
                previewColumn.frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)

            HStack(alignment: .center, spacing: 12) {
                Text(footer)
                    .font(.system(size: AAType.small))
                    .foregroundStyle(AAColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Cancel") { complete(nil) }.keyboardShortcut(.cancelAction)
                Button("Insert") { insert() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasAnyList || lines.isEmpty)
                    .aaProminent()
            }
            .padding(.top, 10)
        }
        .padding(12)
        .frame(width: 760, height: 560)
        .onChange(of: query) { _, _ in selection = groups.first?.rows.first?.id }  // first match selected
        .onDisappear { complete(nil) }
        .aaSheet(.decision)
    }

    private var listColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            AASearchField(text: $query, prompt: EditorSavedListInsert.searchPlaceholder)
                .disabled(!hasAnyList)
            List(selection: $selection) {
                ForEach(groups) { g in
                    Section {
                        ForEach(g.rows) { row in
                            Text(row.display)
                                .font(.system(size: AAType.body))
                                .lineLimit(2)
                                .tag(row.id as UUID?)
                        }
                    } header: {
                        Text(g.name).font(.system(size: AAType.small, weight: .bold)).foregroundStyle(AAColor.muted)
                    }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            .overlay {
                if hasAnyList && groups.isEmpty {
                    Text("No saved list matches.").font(.system(size: AAType.small)).foregroundStyle(AAColor.muted)
                } else if !hasAnyList {
                    AAEmptyState(title: "No saved lists", symbol: "list.bullet.clipboard")
                }
            }
        }
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $numbered) {
                Text(EditorSavedListInsert.bulletsTitle).tag(false)
                Text(EditorSavedListInsert.numberedTitle).tag(true)
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            .labelsHidden()
            .disabled(!hasAnyList)
            Toggle(EditorSavedListInsert.durationTitle, isOn: $withDuration)
                .help(EditorSavedListInsert.durationHelp)
                .disabled(!hasAnyList)
            Text(EditorSavedListInsert.previewTitle)
                .font(.system(size: AAType.small, weight: .bold))
                .foregroundStyle(AAColor.muted)
                .padding(.top, 4)
            ScrollView {
                Text(previewText)
                    .font(.aaMono(AAType.small))
                    .foregroundStyle(selected == nil ? AAColor.muted : AAColor.fg)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            .background(AAColor.panelAlt, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
        }
    }

    private var previewText: String {
        guard selected != nil else { return "" }
        return EditorSavedListInsert.preview(lines, numbered: numbered)
    }
}
