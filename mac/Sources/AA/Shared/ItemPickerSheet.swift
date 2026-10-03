// Spec: 04 HIER-131 / 06 BUILD-131 (item picker: bold prompt, search box, list, Cancel / OK default; 500×500),
//       07 VIEW-208 (selection order), VIEW-210 (selections survive filtering; "{n} selected · {k} hidden by search";
//       ⌘A appends visible rows), VIEW-211 (single mode: OK disabled until chosen; double-click = choose + OK),
//       VIEW-212 row 23 (candidate order), VIEW-216 (rows by index), A.6 (multi mode: a click anywhere on the row
//       toggles it at once, a double-click is two toggles, Space toggles the focused row, rows are exposed as
//       toggles); ARCHITECTURE.md §7.5.
import AppKit
import SwiftUI
import AACore

struct ItemPickerSheet: View {
    let prompt: String
    let candidateOrder: Bool
    let finish: ([Int]?) -> Void
    @State private var model: ShellPickerSelection
    @State private var done = false
    /// The keyboard cursor of the list (multi mode): ↑/↓ move it, Space toggles that row.
    @State private var cursor: Int?
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool

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
            Text(prompt).font(.aaMono(AAType.body, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            TextField("Search", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit { if model.canConfirm { complete(model.result(candidateOrder: candidateOrder)) } }
            List(selection: model.single ? .constant(nil) : $cursor) {
                ForEach(model.visible, id: \.self) { i in
                    row(i)
                }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds(.disabled)
            .focused($listFocused)
            .onKeyPress(.space) {
                guard !model.single, let c = cursor, model.visible.contains(c) else { return .ignored }
                withAnimation(.snappy(duration: 0.15)) { model.toggle(c) }
                return .handled
            }
            .overlay {
                if model.visible.isEmpty {
                    Text(model.displays.isEmpty ? "Nothing to pick." : "No matches.")
                        .font(.aaMono(AAType.body))
                        .foregroundStyle(AAColor.muted)
                }
            }
            HStack {
                Text(model.footer).font(.aaMono(AAType.caption)).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { complete(nil) }.keyboardShortcut(.cancelAction)
                Button("OK") { complete(model.result(candidateOrder: candidateOrder)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canConfirm)
                    .aaProminent()
            }
        }
        .padding(AASpacing.l)
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

    @ViewBuilder
    private func row(_ i: Int) -> some View {
        let selected = model.isSelected(i)
        let content = HStack(spacing: AASpacing.s) {
            Image(systemName: model.single ? (selected ? "largecircle.fill.circle" : "circle")
                                           : (selected ? "checkmark.square.fill" : "square"))
                .foregroundStyle(selected ? AAColor.tint : AAColor.muted)
                .contentTransition(.symbolEffect(.replace))
            Text(model.displays[i]).font(.aaMono(AAType.body)).lineLimit(2)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.vertical, AASpacing.xs)
        .listRowSeparator(.visible)
        .tag(i)
        if model.single {
            // VIEW-211: double-click = choose + OK; a click chooses.
            content
                .onTapGesture(count: 2) {
                    model.toggle(i)
                    complete(model.result(candidateOrder: candidateOrder))
                }
                .onTapGesture { withAnimation(.snappy(duration: 0.15)) { model.toggle(i) } }
                .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            // A.6: no double-click action in multi mode — each click toggles immediately (a double-click is two
            // toggles, as on Windows); the row is one accessible toggle.
            content
                .onTapGesture {
                    cursor = i
                    listFocused = true
                    withAnimation(.snappy(duration: 0.15)) { model.toggle(i) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.displays[i])
                .accessibilityValue(selected ? "checked" : "unchecked")
                .accessibilityAddTraits(.isToggle)
                .accessibilityAction { model.toggle(i) }
        }
    }
}
