// Spec: 04 HIER-111 (item window: title "{Kind} — {name}" / "(unnamed)", kind line + state text, Name / Description
//       (multi-line) / Tags, the footer note, the container editor), HIER-112 (one editor per container: the main pane
//       parks while the item is detached), HIER-113 (one window per item — SceneOpener focuses it), HIER-114 (reload
//       safety: re-resolve by id; orphaned → read-only with the exact message), HIER-115 (deletion orphans/closes),
//       HIER-116 (flush everywhere — the editor registers with EditorFlushCenter), HIER-117 (name edits re-label the
//       sidebar live), §6.7, §8 Q-15 → DECISIONS 04 Q-A (the unified tag parser here too), Q-18 → DECISIONS 04 Q-D
//       (Lock now gates an open window in place), Q-19 (deleted from anywhere → orphaned); ARCHITECTURE.md §2.4, §7.4.
import AppKit
import SwiftUI
import AACore

struct ItemWindowView: View {
    let itemID: UUID
    @Environment(AppEnvironment.self) private var env
    /// The last known identity, for the orphaned state (never edited).
    @State private var lastKind: ItemKind = .equipment
    @State private var lastName = ""
    @State private var lastDescription = ""
    @State private var lastTags = ""

    init(itemID: UUID) { self.itemID = itemID }

    private var item: HierarchyItem? { env.store.item(id: itemID) }

    var body: some View {
        Group {
            if let item {
                if env.locks.isGated(item) {
                    LockGateView(itemID: item.id)
                        .transition(.opacity)
                } else if env.store.detachedItemIDs.contains(itemID) {
                    // HIER-112: the editor binds only once the main pane has parked (one editor per container).
                    HierItemWindowContent(item: item)
                        .id(ObjectIdentifier(item))
                        .transition(.opacity)
                } else {
                    Color.clear
                }
            } else {
                orphaned
            }
        }
        .animation(.snappy, value: item.map { env.locks.isGated($0) } ?? false)
        .frame(minWidth: 560, minHeight: 420)
        .background(AAColor.bg)
        .navigationTitle(HierText.itemWindowTitle(kind: item?.kind ?? lastKind, name: item?.name ?? lastName))
        .onAppear {
            env.store.detachedItemIDs.insert(itemID)                                       // HIER-112 (before binding)
            remember()
        }
        .onChange(of: item?.name) { _, _ in remember() }
        .onDisappear {
            env.flushAllEditors()                                                            // HIER-116
            env.store.detachedItemIDs.remove(itemID)
        }
    }

    private func remember() {
        guard let item else { return }
        lastKind = item.kind
        lastName = item.name
        lastDescription = item.description
        lastTags = TagParser.display(item.tags)
    }

    /// HIER-114: read-only with the exact message; nothing typed here is saved.
    private var orphaned: some View {
        VStack(alignment: .leading, spacing: AASpacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: AASpacing.s) {
                AAKindBadge(kind: lastKind)
                Label(HierText.orphaned, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(AAColor.Status.dueSoon)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HierItemWindowFields(name: .constant(lastName), description: .constant(lastDescription),
                                 tags: .constant(lastTags), tagsFocused: nil)
                .disabled(true)
            AAEmptyState(title: "Notes unavailable", symbol: "doc.text.magnifyingglass",
                         message: "This window is read-only. Close it and open the item again from the main window.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(AASpacing.l)
    }
}

/// The live item window body.
struct HierItemWindowContent: View {
    let item: HierarchyItem
    @Environment(AppEnvironment.self) private var env
    @State private var tagsText = ""
    @FocusState private var tagsFocused: Bool
    @State private var editorReload = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: AASpacing.m) {
                // HIER-111 kind line: the shared kind badge on the fields' leading edge (the title already reads
                // "{Kind} — {name}").
                HStack(alignment: .center, spacing: AASpacing.s) {
                    AAKindBadge(kind: item.kind)
                    if item.isLockProtected {
                        Image(systemName: "lock.fill")
                            .imageScale(.small)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .help("Password-protected")
                            .accessibilityLabel("Password-protected")
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, HierItemWindowFields.labelWidth + AASpacing.s)
                HierItemWindowFields(name: nameBinding, description: descriptionBinding, tags: $tagsText,
                                     tagsFocused: $tagsFocused)
                ContainerEditorView(container: item.container,
                                    context: ContainerEditorContext(title: item.name, host: .itemWindow(item.id)))
                    .id(HierEditorKey(container: ObjectIdentifier(item.container), reload: editorReload))
                    .modifier(HierEditorReloadCounter(container: item.container, counter: $editorReload))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding([.horizontal, .top], AASpacing.l)
            .padding(.bottom, AASpacing.m)
            // Footer bar (design rule 7/11): Divider + the help note.
            Divider()
            HStack(spacing: AASpacing.s) {
                Image(systemName: "info.circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AAColor.muted)
                AAHelpText(HierText.itemWindowFooter)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AASpacing.l)
            .padding(.vertical, AASpacing.s)
            .frame(minHeight: 44)
        }
        .onAppear { tagsText = TagParser.display(item.tags) }
        .onChange(of: tagsText) { _, text in
            guard tagsFocused, HierPageOps.setTags(item, fromText: text) else { return }
            env.store.markDirty()
        }
        .onChange(of: tagsFocused) { _, focused in
            if !focused { tagsText = TagParser.display(item.tags) }
        }
        .onChange(of: item.tags) { _, tags in
            if !tagsFocused { tagsText = TagParser.display(tags) }
        }
    }

    private var nameBinding: Binding<String> {
        Binding(get: { item.name }, set: { v in if HierPageOps.setName(item, v) { env.store.markDirty() } })
    }

    private var descriptionBinding: Binding<String> {
        Binding(get: { item.description }, set: { v in if HierPageOps.setDescription(item, v) { env.store.markDirty() } })
    }
}

/// Name / Description (2–4 lines, Return = new line) / Tags with muted labels (HIER-111).
struct HierItemWindowFields: View {
    @Binding var name: String
    @Binding var description: String
    @Binding var tags: String
    var tagsFocused: FocusState<Bool>.Binding?

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: AASpacing.s, verticalSpacing: 6) {
            GridRow {
                label(HierText.windowName)
                TextField("", text: $name, prompt: Text("(unnamed)"))
                    .textFieldStyle(.roundedBorder)
                    .font(.aaMono(15, weight: .semibold))
                    .accessibilityLabel("Name")
            }
            GridRow(alignment: .top) {
                label(HierText.windowDescription).padding(.top, 5)
                HierMultilineField(text: $description)
                    .frame(height: 58)
                    .accessibilityLabel("Description")
            }
            GridRow {
                label(HierText.windowTags)
                tagsField
                    .help(HierText.tagsHelp)
            }
        }
    }

    @ViewBuilder private var tagsField: some View {
        if let tagsFocused {
            TextField("", text: $tags).textFieldStyle(.roundedBorder).focused(tagsFocused).accessibilityLabel("Tags")
        } else {
            TextField("", text: $tags).textFieldStyle(.roundedBorder).accessibilityLabel("Tags")
        }
    }

    /// The fixed label column (design rule 6); the kind badge above the fields aligns with the fields' edge.
    static let labelWidth: CGFloat = 90

    private func label(_ text: String) -> some View {
        Text(text).font(.aaMono(AAType.body)).foregroundStyle(AAColor.muted)
            .frame(width: Self.labelWidth, alignment: .trailing).gridColumnAlignment(.trailing)
    }
}

/// A bordered multi-line plain-text field where Return inserts a new line (the WPF `AcceptsReturn` box).
struct HierMultilineField: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.aaMono(AAType.body))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(AAColor.panelAlt, in: RoundedRectangle(cornerRadius: AARadius.control + 1, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AARadius.control + 1, style: .continuous)
                .strokeBorder(AAColor.border, lineWidth: 1))
    }
}
