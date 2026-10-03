// Spec: 04 HIER-002 (details disabled without a selection → Mac empty state, Q-01), HIER-025…027 (Name / Description /
//       Tags), HIER-040…044 (selection binds the details, header bar, tab order, Container tab, Export PDF…),
//       HIER-050…055 (lock gate, Lock / Locked / Lock again), HIER-100 (vessel tabs), HIER-112 (detached state),
//       HIER-M04 (focus the name), HIER-M07 (bring the window to front), §6.3, §8 Q-16 (a detached item shows ITS
//       relationships/specifics, disabled), Q-32, Q-33; 11 PDF-001 (Export PDF… lives in the header);
//       ARCHITECTURE.md §2.4 (`.id(ObjectIdentifier(container))`), §7.7 (ContainerEditorView, vessel panels).
import AppKit
import SwiftUI
import AACore

struct HierDetailPane: View {
    @Bindable var model: HierPageModel

    var body: some View {
        Group {
            if let item = model.primaryItem {
                HierItemDetail(model: model, item: item)
                    .id(ObjectIdentifier(item))                 // V2-COMPAT: items sharing an Id get their own details
            } else {
                AAEmptyState(title: HierText.noSelectionTitle, symbol: "sidebar.left", message: HierText.noSelectionMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AAColor.bg)
    }
}

/// The details of one item: header, tab bar and tab content — or the lock gate.
struct HierItemDetail: View {
    @Bindable var model: HierPageModel
    let item: HierarchyItem
    @Environment(AppEnvironment.self) private var env

    /// Bumped when the hosted editor must re-load after an app-password session change (HierEditorReload).
    @State private var editorReload = 0

    private var gated: Bool { env.locks.isGated(item) }
    private var detached: Bool { env.store.detachedItemIDs.contains(item.id) }

    var body: some View {
        VStack(spacing: 0) {
            if gated {
                LockGateView(itemID: item.id)
                    .transition(.opacity)
            } else {
                HierItemHeader(model: model, item: item)
                    .disabled(detached)
                Divider()
                HierTabBar(model: model, kind: item.kind)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: gated)
    }

    private var tabs: [HierDetailTab] {
        item.kind == .vessel ? [.quickCards, .workOrders, .ports, .container, .relationships]
                             : [.container, .relationships, .specifics]
    }

    private var currentTab: HierDetailTab { tabs.contains(model.detailTab) ? model.detailTab : tabs[0] }

    @ViewBuilder private var content: some View {
        switch currentTab {
        case .container:
            if detached {
                HierDetachedCard(itemID: item.id)
            } else {
                ContainerEditorView(container: item.container,
                                    context: ContainerEditorContext(title: item.name, host: .mainPane(item.kind)))
                    .id(HierEditorKey(container: ObjectIdentifier(item.container), reload: editorReload))
                    .modifier(HierEditorReloadCounter(container: item.container, counter: $editorReload))
            }
        case .relationships:
            HierRelationshipsTab(model: model, item: item)
                .disabled(detached)
        case .specifics:
            Group {
                switch item {
                case let e as Equipment: HierEquipmentSpecifics(equipment: e, model: model)
                case let t as TaskItem: HierTaskSpecifics(task: t, model: model)
                case let p as Procedure: HierProcedureSpecifics(procedure: p, model: model)
                default: AAEmptyState(title: HierText.specificsHeader(item.kind), symbol: "square.dashed")
                }
            }
            .disabled(detached)
        case .quickCards:
            QuickCardsPanel(vesselID: item.id).disabled(detached)
        case .workOrders:
            WorkOrdersPanel(vesselID: item.id).disabled(detached)
        case .ports:
            VesselPortsPanel(vesselID: item.id).disabled(detached)
        }
    }
}

/// The identity of a hosted container editor: the container (ARCH §2.4) and a re-load counter, so Tools ▸ Lock Now
/// re-loads the editor of a non-gated item (HIER-056 `RelockCurrent`) while an unlock made by the editor's own
/// CONT-062 gate keeps the same editor instance — caret, scroll and undo survive (DEVIATIONS 05 D-4).
struct HierEditorKey: Hashable {
    var container: ObjectIdentifier
    var reload: Int
}

/// Counts the app-password session changes that must re-load a hosted editor (`HierEditorReload`). The body is read
/// only inside the change handler, so editor saves never re-render the host.
struct HierEditorReloadCounter: ViewModifier {
    let container: Container
    @Binding var counter: Int
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        content.onChange(of: env.passwords.isUnlocked) { was, now in
            if HierEditorReload.onSessionChange(wasUnlocked: was, isUnlocked: now,
                                                bodyIsLegacyEncrypted: LegacyBodyCrypto.isEncrypted(container.richTextXaml)) {
                counter += 1
            }
        }
    }
}

/// HIER-042 tab order as a centred segmented control.
struct HierTabBar: View {
    @Bindable var model: HierPageModel
    let kind: ItemKind

    var body: some View {
        let tabs: [HierDetailTab] = kind == .vessel ? [.quickCards, .workOrders, .ports, .container, .relationships]
                                                    : [.container, .relationships, .specifics]
        let selection = Binding(get: { tabs.contains(model.detailTab) ? model.detailTab : tabs[0] },
                                set: { t in withAnimation(.snappy) { model.detailTab = t } })
        ViewThatFits(in: .horizontal) {
            Picker("", selection: selection) {
                ForEach(tabs, id: \.self) { t in Text(title(t)).tag(t) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Picker("", selection: selection) {
                ForEach(tabs, id: \.self) { t in Text(title(t)).tag(t) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AASpacing.s)
        .padding(.horizontal, AASpacing.m)
    }

    private func title(_ t: HierDetailTab) -> String {
        switch t {
        case .quickCards: return HierText.quickCardsTab
        case .workOrders: return HierText.workOrdersTab
        case .ports: return HierText.portsTab
        case .container: return HierText.containerTab
        case .relationships: return HierText.relationshipsTab
        case .specifics: return HierText.specificsHeader(kind)
        }
    }
}

/// HIER-043 / HIER-112: the parked Container tab of a detached item, with M07.
struct HierDetachedCard: View {
    let itemID: UUID

    var body: some View {
        VStack {
            AACard(padding: AASpacing.l) {
                VStack(spacing: AASpacing.m) {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(AAColor.muted)
                    Text(HierText.detachedNote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AAColor.fg)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        if let w = SceneOpener.shared.itemWindow(itemID) {
                            if w.isMiniaturized { w.deminiaturize(nil) }
                            w.makeKeyAndOrderFront(nil)
                        }
                    } label: {
                        Label(HierText.bringWindowToFront, systemImage: "macwindow")
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: 360)
            }
            .background(AAColor.panelAlt, in: RoundedRectangle(cornerRadius: AARadius.control))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AASpacing.xl)
    }
}

// MARK: Header (HIER-025…027, HIER-041, HIER-053…055, HIER-044)

struct HierItemHeader: View {
    @Bindable var model: HierPageModel
    let item: HierarchyItem
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var tagsText = ""
    @FocusState private var nameFocused: Bool
    @FocusState private var tagsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.s) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: AASpacing.s, verticalSpacing: 6) {
                GridRow {
                    label(HierText.nameField)
                    HStack(alignment: .center, spacing: AASpacing.s) {
                        TextField("", text: nameBinding, prompt: Text("(unnamed)"))
                            .textFieldStyle(.roundedBorder)
                            .font(.aaMono(15, weight: .semibold))
                            .focused($nameFocused)
                            .onSubmit { model.commitRename(stillEditing: nameFocused ? item.id : nil) }
                            .accessibilityLabel("Name")
                        lockButtons
                        Button {
                            exportPDF()
                        } label: {
                            Label(PdfExportCommand.item.title, systemImage: PdfExportCommand.item.symbol)
                        }
                        .buttonStyle(.bordered)
                        .help(PdfExportCommand.item.help ?? "")
                        .accessibilityLabel(PdfExportCommand.item.accessibilityLabel)
                    }
                }
                GridRow {
                    label(HierText.descriptionField)
                    TextField("", text: descriptionBinding, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .accessibilityLabel("Description")
                }
                GridRow {
                    label(HierText.tagsField)
                    TextField("", text: $tagsText, prompt: Text("tag, another tag"))
                        .textFieldStyle(.roundedBorder)
                        .focused($tagsFocused)
                        .help(HierText.tagsHelp)
                        .accessibilityLabel("Tags")
                }
            }
            if model.selection.count > 1 {
                Text(HierText.selectionBanner(model.selection.count))
                    .font(.aaMono(AAType.caption))
                    .foregroundStyle(AAColor.muted)
                    .padding(.leading, 112)
            }
        }
        .padding(.horizontal, AASpacing.l)
        .padding(.vertical, AASpacing.m)
        .onAppear {
            tagsText = TagParser.display(item.tags)
            honourFocusRequest()
        }
        .onChange(of: model.pendingNameFocusID) { _, _ in honourFocusRequest() }
        .onChange(of: nameFocused) { _, focused in
            if focused { model.editingNameID = item.id } else if model.editingNameID == item.id { model.commitRename() }
        }
        .onChange(of: tagsText) { _, text in
            guard tagsFocused, HierPageOps.setTags(item, fromText: text) else { return }
            env.store.markDirty()
        }
        .onChange(of: tagsFocused) { _, focused in
            if !focused { tagsText = TagParser.display(item.tags) }              // HIER-027 on-blur normalisation
        }
        .onChange(of: item.tags) { _, tags in
            if !tagsFocused { tagsText = TagParser.display(tags) }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(AAColor.muted)
            .frame(width: 104, alignment: .trailing)
            .gridColumnAlignment(.trailing)
    }

    private func honourFocusRequest() {
        guard model.pendingNameFocusID == item.id else { return }
        model.pendingNameFocusID = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            nameFocused = true
        }
    }

    private var nameBinding: Binding<String> {
        Binding(get: { item.name }, set: { v in
            if HierPageOps.setName(item, v) { env.store.markDirty() }
        })
    }

    private var descriptionBinding: Binding<String> {
        Binding(get: { item.description }, set: { v in
            if HierPageOps.setDescription(item, v) { env.store.markDirty() }
        })
    }

    // MARK: Lock buttons (HIER-053…055)

    @ViewBuilder private var lockButtons: some View {
        if item.isLockProtected {
            Button {
                env.locks.relock(item.id)
                env.status.post(HierText.lockedAgainStatus(item.name))
            } label: {
                Label(HierText.lockAgain, systemImage: "lock")
            }
            .buttonStyle(.bordered)
            .help(HierText.lockAgainHelp)
            Button {
                Task { await manageLock() }
            } label: {
                Label(HierText.lockedButton, systemImage: "lock.open")
            }
            .buttonStyle(.bordered)
            .help(HierText.lockedButtonHelp)
        } else {
            Button {
                presentLockSheet()
            } label: {
                Label(HierText.lockButton, systemImage: "lock")
            }
            .buttonStyle(.bordered)
            .help(HierText.lockButtonHelp)
        }
    }

    private func presentLockSheet() {
        let id = item.id
        let presenter = dialogs
        Task { @MainActor in
            await presenter.presentSheet(.decision) { _ in ItemLockSheet(itemID: id) }
        }
    }

    /// HIER-054: Change Password / Hint… | Remove Lock | Cancel.
    private func manageLock() async {
        let spec = AlertSpec(title: HierText.manageLockTitle, message: HierText.manageLockMessage, style: .informational,
                             buttons: [AlertButton(title: HierText.changeLockButton, role: .default),
                                       AlertButton(title: HierText.removeLockButton, role: .destructive),
                                       AlertButton(title: "Cancel", role: .cancel)])
        switch await dialogs.alert(spec) {
        case 0:
            presentLockSheet()
        case 1:
            guard let live = env.store.item(id: item.id) else { return }
            env.locks.removeProtection(live)
            HierPersist.save(env, dialogs: dialogs)
            env.status.post(HierText.lockRemovedStatus)
        default:
            break
        }
    }

    /// HIER-044 / PDF-001…007 (the flow, the gate refusal and the save panel are W-PDF's).
    private func exportPDF() {
        env.flushAllEditors()
        let id = item.id
        let presenter = dialogs
        Task { @MainActor in await PdfExportFlows.exportItem(itemID: id, env: env, dialogs: presenter) }
    }
}
