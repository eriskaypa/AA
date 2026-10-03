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
        // Complex editor layout (V-DESIGN rule 7): BuilderSheetHeader, content, footer bar (Divider + 44 pt: the
        // help note leading, Cancel / Insert trailing).
        VStack(alignment: .leading, spacing: 0) {
            BuilderSheetHeader(title: EditorSavedListInsert.header, subtitle: EditorSavedListInsert.subText,
                               symbol: "list.bullet.indent")
                .padding([.horizontal, .top], AASpacing.l)
                .padding(.bottom, AASpacing.m)

            HStack(alignment: .top, spacing: AASpacing.m) {
                listColumn.frame(width: 290)
                previewColumn.frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, AASpacing.l)
            .padding(.bottom, AASpacing.m)

            Divider()
            HStack(alignment: .center, spacing: AASpacing.m) {
                Text(footer)
                    .font(.aaMono(AAType.caption))
                    .foregroundStyle(AAColor.muted)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Cancel") { complete(nil) }.keyboardShortcut(.cancelAction)
                Button("Insert") { insert() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasAnyList || lines.isEmpty)
                    .aaProminent()
            }
            .padding(.horizontal, AASpacing.l)
            .frame(height: 44)
        }
        .frame(width: 760, height: 560)
        .onChange(of: query) { _, _ in selection = groups.first?.rows.first?.id }  // first match selected
        .onDisappear { complete(nil) }
        .aaSheet(.decision)
    }

    private var listColumn: some View {
        VStack(alignment: .leading, spacing: AASpacing.s) {
            AASearchField(text: $query, prompt: EditorSavedListInsert.searchPlaceholder)
                .disabled(!hasAnyList)
            List(selection: $selection) {
                ForEach(groups) { g in
                    Section {
                        ForEach(g.rows) { row in
                            Text(row.display)
                                .font(.aaMono(AAType.body))
                                .lineLimit(2)
                                .padding(.vertical, AASpacing.xs / 2)
                                .frame(minHeight: 22, alignment: .leading)
                                .tag(row.id as UUID?)
                        }
                    } header: {
                        HStack(spacing: AASpacing.xs) {
                            Text(g.name).font(.aaMono(AAType.small, weight: .bold)).foregroundStyle(AAColor.fg)
                            Text("(\(g.rows.count))").font(.aaMono(AAType.caption).monospacedDigit())
                                .foregroundStyle(AAColor.muted)
                        }
                    }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            .overlay {
                if hasAnyList && groups.isEmpty {
                    AAEmptyState(title: "No saved list matches.", symbol: "magnifyingglass",
                                 message: "Change or clear the search to see your saved lists.")
                } else if !hasAnyList {
                    AAEmptyState(title: "No saved lists", symbol: "list.bullet.clipboard",
                                 message: "Build one in the Saved Lists tab first.")
                }
            }
        }
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: AASpacing.s) {
            Picker("", selection: $numbered) {
                Text(EditorSavedListInsert.bulletsTitle).tag(false)
                Text(EditorSavedListInsert.numberedTitle).tag(true)
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            .labelsHidden()
            .font(.body)                                       // native controls stay system (ARCH §8.3)
            .disabled(!hasAnyList)
            Toggle(EditorSavedListInsert.durationTitle, isOn: $withDuration)
                .font(.body)
                .help(EditorSavedListInsert.durationHelp)
                .disabled(!hasAnyList)
            Text(EditorSavedListInsert.previewTitle)
                .font(.aaMono(AAType.body, weight: .semibold))
                .foregroundStyle(AAColor.fg)
                .padding(.top, AASpacing.xs)
            ScrollView {
                Text(previewText)
                    .font(.aaMono(AAType.small))
                    .foregroundStyle(selected == nil ? AAColor.muted : AAColor.fg)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(AASpacing.m)
            }
            .background(AAColor.panelAlt, in: RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
        }
    }

    private var previewText: String {
        guard selected != nil else { return "" }
        return EditorSavedListInsert.preview(lines, numbered: numbered)
    }
}
