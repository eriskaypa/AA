// Spec: 04 HIER-133 (batch done), HIER-134 (batch deadline), HIER-135 / HIER-022 / HIER-023 (confirm-then-trash),
//       HIER-115 (deleting closes the item windows), §8 Q-20 (status names the first item actually trashed; only
//       trashed ids close windows); 02 REPO-043, REPO-053, REPO-075, §6.4 (Mac wording: "Move to Trash", default
//       button = Cancel), §6.5; 07 VIEW-200, VIEW-201; DECISIONS 02 Q-4 (nested subtasks go through the Trash with
//       `trashSubtask`); ARCHITECTURE.md §7.7.
import AppKit
import SwiftUI
import AACore

/// The batch "Mark selected as (not) done" and "Set deadline for selected…" entries, for any context menu. The
/// selection is evaluated **at click time**; `refresh` is always called afterwards.
struct BatchContextMenuItems: View {
    let selection: () -> [AnyObject]
    let refresh: () -> Void
    let done: Bool
    let deadline: Bool
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs

    init(selection: @escaping () -> [AnyObject], refresh: @escaping () -> Void, done: Bool = true, deadline: Bool = true) {
        self.selection = selection; self.refresh = refresh; self.done = done; self.deadline = deadline
    }

    var body: some View {
        if done {
            Button {
                _ = BatchActions.markDone(selection(), done: true, env: env)
                refresh()
            } label: {
                Label(HierText.markDone, systemImage: "checkmark.circle")
            }
            Button {
                _ = BatchActions.markDone(selection(), done: false, env: env)
                refresh()
            } label: {
                Label(HierText.markNotDone, systemImage: "circle")
            }
        }
        if deadline {
            if done { Divider() }
            Button {
                let items = selection()
                let presenter = dialogs
                Task { @MainActor in
                    _ = await BatchActions.setDeadline(items, env: env, dialogs: presenter)
                    refresh()
                }
            } label: {
                Label(HierText.setDeadline, systemImage: "calendar.badge.clock")
            }
            .help(HierText.setDeadlineHelp)
        }
    }
}

@MainActor enum BatchActions {
    /// HIER-133 / REPO-043: `BatchDone.SetDoneAll`; if anything changed, **Flush** (MarkDirty + FlushIfDirty).
    static func markDone(_ items: [AnyObject], done: Bool, env: AppEnvironment) -> Int {
        let n = BatchDone.setDoneAll(items, done: done)
        if n > 0 { HierPersist.flush(env, dialogs: env.mainDialogs) }
        return n
    }

    /// HIER-134 / REPO-053: empty → info; else the date prompt pre-filled with the shared deadline; OK / Clear →
    /// `BatchDeadline.SetDeadlineAll`; if anything changed, **Flush**. Returns the number changed.
    static func setDeadline(_ items: [AnyObject], env: AppEnvironment, dialogs: DialogPresenter) async -> Int {
        guard !items.isEmpty else {
            await dialogs.info(HierText.setDeadlineTitle, HierText.setDeadlineEmpty)
            return 0
        }
        let initial: NetDateTime? = BatchDeadline.sharedDeadline(of: items) ?? nil
        let request = DatePromptRequest(title: HierText.setDeadlineTitle, prompt: HierText.setDeadlinePrompt(items.count),
                                        initial: initial)
        let date: NetDateTime?
        switch await dialogs.datePrompt(request) {
        case .ok(let d): date = d
        case .cleared: date = nil
        case .cancelled: return 0
        }
        let n = BatchDeadline.setDeadlineAll(items, date: date)
        if n > 0 { HierPersist.flush(env, dialogs: dialogs) }
        return n
    }

    /// HIER-135 / REPO-075: describe → "nothing" / "all locked" info → confirmation (default Cancel) → trash every
    /// non-gated top-level pick as ONE undo batch (nested subtasks through `trashSubtask`, DECISIONS 02 Q-4) →
    /// **Save** → close the item windows of the trashed ids → status. Returns the number trashed.
    static func confirmAndTrash(_ items: [AnyObject], env: AppEnvironment, dialogs: DialogPresenter) async -> Int {
        let store = env.store
        let isGated: (HierarchyItem) -> Bool = { env.locks.isGated($0) }
        let description = BatchDelete.describe(items, store: store, isGated: isGated)
        if let info = BatchDelete.nothingToDeleteMessage(description) {
            await dialogs.info(info.title, info.message)
            return 0
        }
        let message = BatchDelete.confirmationMessage(description, trashCount: store.data.trash.count)
        let ok = await dialogs.confirm("Confirm delete", message, confirm: HierText.moveToTrash, cancel: "Cancel",
                                       destructive: true, defaultIsCancel: true)
        guard ok else { return 0 }
        env.flushAllEditors()
        // Re-evaluate after the confirmation (the model may have changed while the alert was up).
        let picks = BatchDelete.topLevel(items).filter { !isGated($0) }
        let batch = UUID()
        var trashed: [HierarchyItem] = []
        for item in picks {
            let entry: TrashedItem?
            if let t = item as? TaskItem { entry = store.trashSubtask(t, batchID: batch) } else { entry = store.trash(item, batchID: batch) }
            if entry != nil { trashed.append(item) }
        }
        guard !trashed.isEmpty else { return 0 }
        HierPersist.save(env, dialogs: dialogs)
        for item in trashed {
            store.detachedItemIDs.remove(item.id)
            SceneOpener.shared.itemWindow(item.id)?.close()
        }
        env.status.post(BatchDelete.statusAfterDelete(count: trashed.count, firstName: trashed[0].name))
        env.refreshAfterTrashChange()
        return trashed.count
    }
}
