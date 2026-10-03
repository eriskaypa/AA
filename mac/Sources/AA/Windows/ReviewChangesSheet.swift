// Spec: 08 §2.7 (QUICK-190…196: header, age box, summary, tree — roots expanded, deeper rows collapsed — buttons
//       Cancel = Esc / Import = Enter, enabled even with no differences), §6.2-G (a sheet returning Bool; glyph column
//       20 pt; lighter glyph colours in dark appearance); 01 DATA-100…103; DECISIONS 01 Q-3 (opt-in "Other data"
//       section: crew, saved lists, schedules, ports, SIRE); 03 §6.5.1.5 (decision sheet: ⌘W refused, ⎋ = Cancel);
//       ARCHITECTURE.md §7.5 (`DialogPresenter.reviewChanges` hosts this sheet), §7.7.
import AppKit
import SwiftUI
import AACore

/// "Review changes before importing" — the change preview shown before any import overwrites the data.
struct ReviewChangesSheet: View {
    let request: ReviewChangesRequest
    let finish: (Bool) -> Void

    /// QUICK-192: top-level rows start expanded, deeper rows collapsed. Seeded here (not in `onAppear`) so the
    /// outline never re-enters its NSTableView delegate while it lays out the first pass.
    init(request: ReviewChangesRequest, finish: @escaping (Bool) -> Void) {
        self.request = request
        self.finish = finish
        _expanded = State(initialValue: Set(request.diff.roots.map(\.id)).union(request.otherData.roots.map(\.id)))
    }

    @State private var expanded: Set<UUID>
    @State private var showOther = false
    @State private var finished = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)
            tree
                .padding(.horizontal, 18)
            footer
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        }
        .frame(minWidth: 760, idealWidth: 760, minHeight: 580, idealHeight: 580)
        .onDisappear { complete(false) }
        .aaSheet(.decision)
    }

    private func complete(_ ok: Bool) {
        guard !finished else { return }
        finished = true
        finish(ok)
    }

    // MARK: Header (QUICK-191)

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "arrow.down.doc").foregroundStyle(AAColor.tint)
                Text(ReviewChangesText.source(request.sourceName))
                    .font(.system(size: 14, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Text(request.ageText)
                .font(.aaMono(AAType.small))
                .foregroundStyle(AAColor.fg)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(AAColor.panelAlt, in: RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous)
                    .strokeBorder(AAColor.border, lineWidth: 1))
                .textSelection(.enabled)
            Text(ReviewChangesText.summary(request.diff))
                .font(.system(size: AAType.body, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(ReviewChangesText.explanation)
                .font(.system(size: AAType.small))
                .foregroundStyle(AAColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Tree (QUICK-192)

    private var tree: some View {
        List {
            if request.diff.roots.isEmpty {
                Label(ReviewChangesText.noDifferences, systemImage: "checkmark.seal")
                    .foregroundStyle(AAColor.muted)
            }
            ForEach(request.diff.roots) { node in
                ReviewNodeView(node: node, expanded: $expanded)
            }
            if showOther {
                Section {
                    if request.otherData.roots.isEmpty {
                        Text(ReviewChangesText.otherDataNone).foregroundStyle(AAColor.muted)
                    }
                    ForEach(request.otherData.roots) { node in
                        ReviewNodeView(node: node, expanded: $expanded)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ReviewChangesText.otherDataHeader).font(.system(size: AAType.small, weight: .bold))
                        Text(ReviewChangesText.otherSummary(request.otherData))
                            .font(.system(size: AAType.caption)).foregroundStyle(AAColor.muted)
                    }
                    .padding(.top, 6)
                }
            }
        }
        .listStyle(.bordered)
        .alternatingRowBackgrounds(.disabled)
        .animation(.snappy, value: showOther)
    }

    // MARK: Footer (QUICK-193)

    private var footer: some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle(isOn: $showOther) {
                Text(ReviewChangesText.otherDataToggle).font(.system(size: AAType.small))
            }
            .toggleStyle(.checkbox)
            .help(ReviewChangesText.otherDataHelp)
            if request.otherData.hasChanges {
                AAStatusCapsule(text: "\(request.otherData.added + request.otherData.changed + request.otherData.removed)",
                                symbol: "tray.full", color: AAColor.Status.diffChanged)
            }
            Spacer(minLength: 12)
            Button(ReviewChangesText.cancel) { complete(false) }
                .keyboardShortcut(.cancelAction)
                .frame(minWidth: 90)
            Button(ReviewChangesText.importButton) { complete(true) }
                .keyboardShortcut(.defaultAction)
                .aaProminent()
                .frame(minWidth: 150)
        }
    }
}

/// One node: glyph column (20 pt, bold, coloured by change) + wrapping text; children in a disclosure group.
struct ReviewNodeView: View {
    let node: DiffNode
    @Binding var expanded: Set<UUID>

    var body: some View {
        if node.children.isEmpty {
            ReviewNodeLabel(node: node)
        } else {
            DisclosureGroup(isExpanded: Binding(get: { expanded.contains(node.id) },
                                                set: { open in
                                                    if open { expanded.insert(node.id) } else { expanded.remove(node.id) }
                                                })) {
                ForEach(node.children) { child in
                    AnyView(ReviewNodeView(node: child, expanded: $expanded))
                }
            } label: {
                ReviewNodeLabel(node: node)
            }
        }
    }
}

struct ReviewNodeLabel: View {
    let node: DiffNode

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(ReviewChangesText.glyph(node.change))
                .font(.system(size: AAType.body, weight: .bold))
                .foregroundStyle(ReviewNodeLabel.color(node.change))
                .frame(width: 20, alignment: .leading)
                .accessibilityLabel(ReviewNodeLabel.accessibility(node.change))
            Text(node.text)
                .font(.aaMono(AAType.body))
                .foregroundStyle(AAColor.fg)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 640, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
    }

    static func color(_ c: DiffNode.Change) -> Color {
        switch c {
        case .added: return AAColor.Status.diffAdded
        case .removed: return AAColor.Status.diffRemoved
        case .changed: return AAColor.Status.diffChanged
        }
    }

    static func accessibility(_ c: DiffNode.Change) -> String {
        switch c {
        case .added: return "Added"
        case .removed: return "Removed"
        case .changed: return "Changed"
        }
    }
}
