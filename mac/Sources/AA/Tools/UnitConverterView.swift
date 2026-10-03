// Spec: 14 TOOLS-080 (window: Category combo, bottom note, unit rows — a card that hugs the rows, design rule 16;
//       many independent windows), TOOLS-081…090
//       (rows, seed "1", live conversion where the edited box is never rewritten, invalid clears the others, category
//       switch resets, nothing persisted, theme), §6.9 (popup Picker with SF Symbols, 210-pt wrapping labels, focus
//       tracking, .NET parse/format emulations — never a NumberFormatter field, monospaced digits);
//       ARCHITECTURE.md §7.7 (`UnitConverterView(sessionID:)`).
import AppKit
import SwiftUI
import AACore

struct UnitConverterView: View {
    let sessionID: UUID
    @State private var state: ToolUnitConverterState
    @FocusState private var focusedRow: Int?

    init(sessionID: UUID) {
        self.sessionID = sessionID
        _state = State(initialValue: ToolUnitConverterState())
    }

    /// For the debug snapshot registry: a window showing another category / an edited row.
    init(sessionID: UUID, state: ToolUnitConverterState) {
        self.sessionID = sessionID
        _state = State(initialValue: state)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.m) {
            HStack(spacing: AASpacing.s) {
                Text("Category:").font(.aaMono(AAType.body, weight: .bold))
                Picker("Category", selection: Binding(get: { state.categoryIndex },
                                                      set: { i in withAnimation(.snappy) { state.selectCategory(i) } })) {
                    ForEach(Array(ToolUnitCatalog.categories.enumerated()), id: \.offset) { i, c in
                        Label(c.name, systemImage: c.symbol).tag(i)
                    }
                }
                .labelsHidden()
                .frame(width: 260)
                Spacer(minLength: 0)
            }
            // Design rule 16: the card hugs the category's rows (at most 10) instead of a scroll area stretched to
            // the window's foot; the window follows the content height (scene `.windowResizability(.contentSize)`).
            Grid(alignment: .leading, horizontalSpacing: AASpacing.m, verticalSpacing: 6) {
                ForEach(Array(state.category.units.enumerated()), id: \.offset) { i, unit in
                    GridRow {
                        Text(unit.name)
                            .foregroundStyle(AAColor.fg)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 210, alignment: .leading)
                        TextField(unit.name, text: Binding(get: { i < state.texts.count ? state.texts[i] : "" },
                                                           set: { new in
                                                               // TextChanged fires only on a real change (TOOLS-083).
                                                               guard i < state.texts.count, state.texts[i] != new else { return }
                                                               state.edit(row: i, text: new)
                                                           }))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .font(.aaMono(AAType.body))
                            .focused($focusedRow, equals: i)
                            .gridColumnAlignment(.leading)
                    }
                }
            }
            .padding(AASpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(state.categoryIndex)
            .transition(.opacity)
            .background(AAColor.panel, in: RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border))
            Text(ToolUnitCatalog.note)
                .font(.aaMono(AAType.small))
                .foregroundStyle(AAColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(minWidth: 460, idealWidth: 500, maxWidth: .infinity, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(AAColor.bg)
    }
}
