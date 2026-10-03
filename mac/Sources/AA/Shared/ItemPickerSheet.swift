// Spec: 04 HIER-131 / 06 BUILD-131 (item picker: bold prompt, search box, list, Cancel / OK default; 500×500),
//       07 VIEW-208 (selection order), VIEW-210 (selections survive filtering; "{n} selected · {k} hidden by search";
//       ⌘A appends visible rows), VIEW-211 (single mode: OK disabled until chosen; double-click = choose + OK),
//       VIEW-212 row 23 (candidate order), VIEW-216 (rows by index); ARCHITECTURE.md §7.5.
import AppKit
import SwiftUI
import AACore

struct ItemPickerSheet: View {
    let prompt: String
    let candidateOrder: Bool
    let finish: ([Int]?) -> Void
    @State private var model: ShellPickerSelection
    @State private var done = false
    @FocusState private var searchFocused: Bool

    init(prompt: String, displays: [String], preselected: Set<Int>, single: Bool, candidateOrder: Bool,
         finish: @escaping ([Int]?) -> Void) {
        self.prompt = prompt
        self.candidateOrder = candidateOrder
        self.finish = finish
        _model = State(initialValue: ShellPickerSelection(displays: displays, preselected: preselected, single: single))
    }

    private func complete(_ r: [Int]?) {
        guard !done else { return }
        done = true
        finish(r)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prompt).font(.system(size: 14, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            TextField("Search", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit { if model.canConfirm { complete(model.result(candidateOrder: candidateOrder)) } }
            List {
                ForEach(model.visible, id: \.self) { i in
                    row(i)
                }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds(.disabled)
            .overlay {
                if model.visible.isEmpty {
                    Text(model.displays.isEmpty ? "Nothing to pick." : "No matches.")
                        .foregroundStyle(AAColor.muted)
                }
            }
            HStack {
                Text(model.footer).font(.system(size: AAType.caption)).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { complete(nil) }.keyboardShortcut(.cancelAction)
                Button("OK") { complete(model.result(candidateOrder: candidateOrder)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canConfirm)
                    .aaProminent()
            }
        }
        .padding(14)
        .frame(width: 500, height: 500)
        .onAppear { searchFocused = true }
        .onDisappear { complete(nil) }
        .background {
            if !model.single {
                Button("") { model.selectAllVisible() }.keyboardShortcut("a", modifiers: .command).hidden()
            }
        }
        .aaSheet(.decision)
    }

    private func row(_ i: Int) -> some View {
        let selected = model.isSelected(i)
        return HStack(spacing: 8) {
            Image(systemName: model.single ? (selected ? "largecircle.fill.circle" : "circle")
                                           : (selected ? "checkmark.square.fill" : "square"))
                .foregroundStyle(selected ? AAColor.tint : AAColor.muted)
                .contentTransition(.symbolEffect(.replace))
            Text(model.displays[i]).lineLimit(2)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
        .listRowSeparator(.visible)
        .onTapGesture(count: 2) {
            if model.single {
                model.toggle(i)
                complete(model.result(candidateOrder: candidateOrder))
            }
        }
        .onTapGesture { withAnimation(.snappy(duration: 0.15)) { model.toggle(i) } }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
