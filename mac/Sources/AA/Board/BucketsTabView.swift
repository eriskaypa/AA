// Spec: 07 §3.4 VIEW-140…152, VIEW-155 (Buckets tab: header + help, + New bucket / Rename / Set category... / Delete,
//       grouped list with counts, status line, selection kept by id, members pane, open / remove member), §7.4 (Mac
//       structure), 06 BUILD-145 B3 / B4 (blank category clears / means none; Cancel on prompt 2 still creates),
//       DECISIONS 07 Q-11 (case-insensitive category groups, display only), VIEW-205 (navigate to top-level members),
//       02 REPO-091 (log Kind "Bucket"); ARCHITECTURE.md §7.6 (list roles buckets / bucketMembers).
import AppKit
import SwiftUI
import AACore

struct BucketsTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var selectedBucket: UUID?
    @State private var selectedMember: String?
    /// VIEW-147: the new bucket is selected and scrolled into view.
    @State private var scrollTarget: UUID?
    /// V2-SCALE: the member rows (a walk over every item) are cached and rebuilt only when something they read
    /// changes — and not at all while the section is hidden (rebuilt once when it is shown again).
    @State private var rows = CalLive<[BucketMemberRow]>([])
    @Environment(\.aaSectionIsVisible) private var isVisible

    var body: some View {
        let data = env.store.data
        let memberRows = rows.value
        let groups = BucketsModel.groups(data, rows: memberRows)
        let bucket = selectedBucket.flatMap { id in data.quickBuckets.first { $0.id == id } }
        let members = bucket.map { BucketsModel.members(of: $0.id, in: memberRows) } ?? []
        CalSplitView(minLeading: 280, idealLeading: 340, maxLeading: 460, minTrailing: 380) {
            sidebar(groups: groups, count: data.quickBuckets.count)
        } trailing: {
            membersPane(bucket: bucket, members: members)
        }
        .background(AAColor.bg)
        .onChange(of: env.store.generation) { _, _ in
            // VIEW-145 / VIEW-207: keep the selection by id when it still exists after a reload.
            if let id = selectedBucket, env.store.bucket(id: id) == nil { selectedBucket = nil }
            selectedMember = nil
        }
        .onChange(of: selectedBucket) { _, _ in selectedMember = nil }
        .onChange(of: isVisible, initial: true) { _, v in rows.setActive(v) }
        .onAppear {
            let store = env.store
            rows.bind { BucketsModel.memberRows(store.data) }
            #if DEBUG
            if ProcessInfo.processInfo.environment["AA_WPLAN_SELECT_FIRST_BUCKET"] != nil, selectedBucket == nil {
                selectedBucket = groups.first?.rows.first?.id
            }
            #endif
        }
        .aaSectionCommands(.buckets, SectionCommands(newItemTitle: "New Bucket", newItem: { newBucket() },
                                                     rename: selectedBucket == nil ? nil : { rename() }))
    }

    // MARK: Sidebar (VIEW-141…145)

    private func sidebar(groups: [BucketGroup], count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CalPaneTitle(title: BucketsModel.headerTitle, symbol: "tray.2") {
                Text("\(count)")
                    .font(.aaMono(AAType.caption))
                    .foregroundStyle(AAColor.muted)
                    .monospacedDigit()
                    .accessibilityLabel("\(count) buckets")
            }
            AAHelpText(BucketsModel.help)
                .padding(.horizontal, AASpacing.m)
                .padding(.bottom, AASpacing.s)
            iconBar
                .padding(.horizontal, AASpacing.s)
                .padding(.bottom, AASpacing.xs)
            Divider()
            ScrollViewReader { proxy in
                List(selection: $selectedBucket) {
                    ForEach(groups) { g in
                        Section {
                            ForEach(g.rows) { row in
                                BucketListRow(row: row).tag(row.id).id(row.id)
                            }
                        } header: {
                            HStack(spacing: 0) {
                                Text(g.label).font(.aaMono(AAType.small, weight: .bold)).foregroundStyle(AAColor.accent)
                                Text(g.countText).font(.aaMono(AAType.small)).foregroundStyle(AAColor.muted)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .tint(AAColor.tint)
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if let id = ids.first, ids.count == 1 {
                        Button(BucketsModel.renameTitle) { selectedBucket = id; rename() }
                        Button(BucketsModel.setCategoryTitle) { selectedBucket = id; setCategory() }
                        Divider()
                        Button(BucketsModel.deleteTitle, role: .destructive) { selectedBucket = id; delete() }
                    }
                }
                .aaListCommands(ListCommands(role: .buckets, selectionCount: selectedBucket == nil ? 0 : 1,
                                             deleteTitle: "Delete Bucket",
                                             delete: selectedBucket == nil ? nil : { delete() }))
                .onChange(of: scrollTarget) { _, id in
                    guard let id else { return }
                    withAnimation(.snappy) { proxy.scrollTo(id) }
                    scrollTarget = nil
                }
            }
            Divider()
            Text(BucketsModel.statusLine(bucketCount: count))
                .font(.aaMono(AAType.caption))
                .foregroundStyle(AAColor.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AASpacing.m)
                .padding(.vertical, AASpacing.s)
        }
        .background(AAPaneBackground())
    }

    /// VIEW-141 toolbar as one icon bar (V-DESIGN rule 4): `plus` "+ New bucket", `trash` "Delete", and an overflow
    /// menu holding "Rename" and "Set category..." by their spec names. Same commands as the row context menu.
    private var iconBar: some View {
        HStack(spacing: AASpacing.xs) {
            BucketIconButton(symbol: "plus", label: BucketsModel.newBucketTitle, help: BucketsModel.newBucketTitle) {
                newBucket()
            }
            BucketIconButton(symbol: "trash", label: BucketsModel.deleteTitle, help: BucketsModel.deleteTitle) {
                delete()
            }
            Spacer(minLength: 0)
            Menu {
                Button(BucketsModel.renameTitle, systemImage: "pencil") { rename() }
                Button(BucketsModel.setCategoryTitle, systemImage: "tag") { setCategory() }
                    .help(BucketsModel.setCategoryHelp)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .symbolRenderingMode(.hierarchical)
                    .fontWeight(.regular)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(.secondary)                       // rule 4: the overflow menu is grey like its sibling icons
            .fixedSize()
            .frame(width: 24, height: 24)
            .help("More bucket commands: \(BucketsModel.renameTitle), \(BucketsModel.setCategoryTitle)")
            .accessibilityLabel("More")
        }
        .frame(height: 28)
    }

    // MARK: Members (VIEW-146, VIEW-151, VIEW-152)

    private func membersPane(bucket: QuickBucket?, members: [BucketMemberRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(BucketsModel.membersHeader(bucket, memberCount: members.count))
                    .font(.aaMono(AAType.title, weight: .bold))
                    .foregroundStyle(AAColor.accent)
                    .fixedSize(horizontal: false, vertical: true)
                Text(BucketsModel.membersHelp)
                    .font(.aaMono(AAType.caption))
                    .foregroundStyle(AAColor.muted)
            }
            .padding(.horizontal, AASpacing.l)
            .padding(.vertical, AASpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            .overlay(alignment: .bottom) { Rectangle().fill(AAColor.border).frame(height: 1) }
            if bucket == nil {
                AAEmptyState(title: "No bucket selected", symbol: "tray.2",
                             message: "Choose a bucket on the left to see its members.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if members.isEmpty {
                AAEmptyState(title: "This bucket is empty", symbol: "tray",
                             message: "Sort tasks, procedures and checklist steps into it in the \u{2318}N quick-work window.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedMember) {
                    ForEach(members) { m in
                        BucketMemberListRow(member: m).tag(m.id)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
                .tint(AAColor.tint)
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first, let m = members.first(where: { $0.id == id }) {
                        Button(BucketsModel.openTitle, systemImage: "arrow.up.forward.app") { open(m) }
                        Button(BucketsModel.removeMemberTitle, systemImage: "minus.circle") { remove(m) }
                    }
                } primaryAction: { ids in
                    if let id = ids.first, let m = members.first(where: { $0.id == id }) { open(m) }
                }
                .aaListCommands(ListCommands(role: .bucketMembers,
                                             selectionCount: selectedMember == nil ? 0 : 1,
                                             primary: selectedMember.flatMap { id in
                                                 members.first(where: { $0.id == id }).map { m in { open(m) } }
                                             }))
            }
        }
    }

    // MARK: Actions (each saves immediately — Windows `Save()`)

    private func save() { CalPersist.saveNow(env, dialogs) }

    private func needSelection() async -> QuickBucket? {
        if let id = selectedBucket, let b = env.store.bucket(id: id) { return b }
        await dialogs.info(BucketsModel.headerTitle, BucketsModel.selectFirstMessage)
        return nil
    }

    /// VIEW-147 (+ B4).
    private func newBucket() {
        Task { @MainActor in
            guard case .ok(let name) = await dialogs.prompt(TextPromptRequest(title: BucketsModel.newPromptTitle,
                                                                              prompt: BucketsModel.newPromptLabel)),
                  !NetText.isBlank(name) else { return }
            let r = await dialogs.prompt(TextPromptRequest(title: BucketsModel.categoryPromptTitle,
                                                           prompt: BucketsModel.categoryPromptLabel))
            let category: String? = if case .ok(let c) = r { c } else { nil }
            guard let b = BucketsModel.create(name: name, category: category, store: env.store) else { return }
            save()
            withAnimation(.snappy) { selectedBucket = b.id }
            scrollTarget = b.id
        }
    }

    /// VIEW-148.
    private func rename() {
        Task { @MainActor in
            guard let b = await needSelection() else { return }
            let id = b.id
            guard case .ok(let v) = await dialogs.prompt(TextPromptRequest(title: BucketsModel.renamePromptTitle,
                                                                           prompt: BucketsModel.renamePromptLabel,
                                                                           initial: b.name)),
                  let live = env.store.bucket(id: id), BucketsModel.rename(live, to: v) else { return }
            save()
        }
    }

    /// VIEW-149 (B3: every OK saves; blank clears).
    private func setCategory() {
        Task { @MainActor in
            guard let b = await needSelection() else { return }
            let id = b.id
            guard case .ok(let v) = await dialogs.prompt(TextPromptRequest(title: BucketsModel.setCategoryPromptTitle,
                                                                           prompt: BucketsModel.setCategoryPromptLabel,
                                                                           initial: b.category)),
                  let live = env.store.bucket(id: id) else { return }
            BucketsModel.setCategory(live, to: v)
            save()
        }
    }

    /// VIEW-150.
    private func delete() {
        Task { @MainActor in
            guard let b = await needSelection() else { return }
            let n = BucketsModel.members(of: b.id, in: BucketsModel.memberRows(env.store.data)).count
            let ok = await dialogs.confirm(BucketsModel.deleteAlertTitle, BucketsModel.deleteMessage(b, memberCount: n),
                                           confirm: "Delete", destructive: true, defaultIsCancel: true)
            guard ok, let live = env.store.bucket(id: b.id) else { return }
            BucketsModel.delete(live, store: env.store)
            save()
            selectedBucket = nil
        }
    }

    /// VIEW-151: Task / Procedure → navigate (VIEW-205); Subtask → subtask editor; Checklist step → step editor.
    private func open(_ m: BucketMemberRow) {
        switch m.kind {
        case .task, .procedure:
            env.navigator.navigate(to: m.itemID)
        case .subtask:
            Task { @MainActor in await CalPersist.editTask(m.itemID, env: env, dialogs: dialogs) }
        case .step:
            Task { @MainActor in await CalPersist.editStep(m.itemID, env: env, dialogs: dialogs) }
        }
    }

    /// VIEW-152: no confirmation.
    private func remove(_ m: BucketMemberRow) {
        guard let id = selectedBucket else { return }
        if BucketsModel.removeMember(m.item, from: id) { save() }
    }
}

/// A 24-pt borderless icon button of the Buckets icon bar (help = the spec tooltip / button text).
private struct BucketIconButton: View {
    let symbol: String
    let label: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .fontWeight(.regular)
                .foregroundStyle(.secondary)        // rule 4: every icon in the bar is .secondary (no accent tint)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.accessoryBar)             // grey like the Hierarchy / Crew icon bars (a borderless button tints)
        .help(help)
        .accessibilityLabel(label)
    }
}

private struct BucketListRow: View {
    let row: BucketRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AASpacing.s) {
            Image(systemName: "tray.fill")
                .foregroundStyle(AAColor.tint.opacity(0.8))
                .font(.system(size: 11))
            Text(row.displayName)
                .font(.aaMono(AAType.body))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: AASpacing.s)
            Text(row.countText)
                .font(.aaMono(AAType.caption))
                .foregroundStyle(AAColor.muted)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

private struct BucketMemberListRow: View {
    let member: BucketMemberRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AASpacing.s) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16)
            Text(member.text)
                .font(.aaMono(AAType.body))
                .foregroundStyle(AAColor.fg)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }

    private var symbol: String {
        switch member.kind {
        case .task: return "checklist"
        case .subtask: return "arrow.turn.down.right"
        case .procedure: return "list.number"
        case .step: return "checkmark.square"
        }
    }

    private var color: Color {
        switch member.kind {
        case .task, .subtask: return AAColor.kindGlyph(.task)
        case .procedure, .step: return AAColor.kindGlyph(.procedure)
        }
    }
}
