// Spec: 04 HIER-060 (related list "[Kind] Name", buttons, help text), HIER-061 (Add relationship… picker: every
//       other item by kind then name, multi, no preselection, additive, Save), HIER-062 (Remove → RemoveRelation, Save),
//       HIER-063 (backlinks heading + 160 pt list), HIER-064 (double-click navigates across kinds), §6.3, DECISIONS 04
//       Q-B (Remove disabled for one-way Equipment links, with help), DECISIONS 05 (FileBacklinksSection — files that
//       link to this item); 02 REPO-028; 07 VIEW-212 row 10 (selection order); "live via observation" (HIER-064 note).
import AppKit
import SwiftUI
import AACore

struct HierRelationshipsTab: View {
    let model: HierPageModel
    let item: HierarchyItem
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var selectedRelated: UUID?
    @State private var selectedBacklink: UUID?

    var body: some View {
        let related = HierRelations.relatedRows(store: env.store, item: item)
        let backlinks = HierRelations.backlinkRows(store: env.store, item: item)
        let selectedRow = related.first { $0.id == selectedRelated }
        let removable: (() -> Void)? = (selectedRow.map { !$0.isOneWay } ?? false) ? { removeSelected(selectedRow) } : nil
        ScrollView {
            VStack(alignment: .leading, spacing: AASpacing.l) {
                VStack(alignment: .leading, spacing: AASpacing.s) {
                    HStack(spacing: AASpacing.s) {
                        Button {
                            Task { await addRelationship() }
                        } label: {
                            Label(HierText.addRelationship, systemImage: "link.badge.plus")
                        }
                        .aaProminent()
                        Button {
                            removeSelected(selectedRow)
                        } label: {
                            Label(HierText.remove, systemImage: "minus.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedRow == nil || selectedRow?.isOneWay == true)
                        .help(selectedRow?.isOneWay == true ? HierText.oneWayRemoveHelp : "")
                        Text(HierText.relationshipsHelp)
                            .font(.aaMono(AAType.caption))
                            .foregroundStyle(AAColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HierLinkList(rows: related, selection: $selectedRelated, emptyText: HierText.noRelatedItems,
                                 minHeight: 150, role: .relationships,
                                 onOpen: { open($0) },
                                 deleteAction: removable)
                }
                VStack(alignment: .leading, spacing: AASpacing.s) {
                    Label(HierText.backlinksHeading, systemImage: "arrow.uturn.backward")
                        .font(.aaMono(AAType.body, weight: .bold))
                        .foregroundStyle(AAColor.accent)
                    HierLinkList(rows: backlinks, selection: $selectedBacklink, emptyText: HierText.noBacklinks,
                                 minHeight: 160, role: .relationships, onOpen: { open($0) }, deleteAction: nil)
                        .frame(height: 160)
                }
                FileBacklinksSection(itemID: item.id)
            }
            .padding(AASpacing.l)
        }
    }

    private func open(_ id: UUID) { env.navigator.navigate(to: id) }

    /// HIER-061.
    private func addRelationship() async {
        let candidates = HierRelations.candidates(store: env.store, excluding: item)
        let request = ItemPickerRequest(prompt: HierText.pickRelatedItems,
                                        rows: candidates.map { ItemPickerRow(display: HierText.label($0), tag: $0.id) },
                                        mode: .multi)
        guard let picked = await dialogs.pickItems(request), let live = env.store.item(id: item.id) else { return }
        HierRelations.addRelations(store: env.store, item: live, pickedIDs: picked)
        HierPersist.save(env, dialogs: dialogs)
    }

    /// HIER-062.
    private func removeSelected(_ row: HierRelationRow?) {
        guard let row, !row.isOneWay, let other = env.store.item(id: row.id) else { return }
        env.store.removeRelation(item, other)
        HierPersist.save(env, dialogs: dialogs)
        selectedRelated = nil
    }
}

/// A bordered list of "[Kind] Name" rows with a kind swatch; double-click (or ↩) opens.
struct HierLinkList: View {
    let rows: [HierRelationRow]
    @Binding var selection: UUID?
    let emptyText: String
    var minHeight: CGFloat
    var role: ListRole
    var onOpen: (UUID) -> Void
    var deleteAction: (() -> Void)?

    var body: some View {
        List(selection: $selection) {
            ForEach(rows) { row in
                HStack(spacing: AASpacing.s) {
                    Circle().fill(AAColor.kind(row.item.kind)).frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(AAColor.border, lineWidth: 0.5))
                    Text(row.label).lineLimit(1).truncationMode(.tail)
                    if row.isOneWay {
                        Image(systemName: "arrow.right")
                            .imageScale(.small)
                            .foregroundStyle(AAColor.muted)
                            .help(HierText.oneWayRemoveHelp)
                    }
                    Spacer(minLength: 0)
                }
                .tag(row.id)
            }
        }
        .listStyle(.bordered)
        .alternatingRowBackgrounds(.disabled)
        .frame(minHeight: minHeight)
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first {
                Button("Open") { onOpen(id) }
            }
        } primaryAction: { ids in
            if let id = ids.first { onOpen(id) }
        }
        .overlay {
            if rows.isEmpty {
                Text(emptyText).font(.aaMono(AAType.small)).foregroundStyle(AAColor.muted).allowsHitTesting(false)
            }
        }
        .aaListCommands(ListCommands(role: role, selectionCount: selection == nil ? 0 : 1,
                                     deleteTitle: deleteAction == nil ? nil : HierText.remove, delete: deleteAction,
                                     deleteConfirms: false,
                                     primary: selection.map { id in { onOpen(id) } }))
    }
}
