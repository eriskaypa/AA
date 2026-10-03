// Spec: 08 §2.2 (QUICK-051…055 list actions, QUICK-062/064 tiles and pins, QUICK-072 open in main window, QUICK-073
//       delete — through the Trash per DECISIONS 02 Q-4 / 08 OQ-1, Q-16 close a detached window of the item,
//       QUICK-077 child buttons, QUICK-079 children context menu, QUICK-080/081 saved lists), QUICK-230 (date
//       prompt), QUICK-231 (bucket picker, cap in selection order); 07 VIEW-212 rows 2–3 (item-picker callers),
//       VIEW-213, VIEW-215 (BucketIds rewritten on every OK + Save); 06 BUILD-102, BUILD-144/145 (prompt callers B3/B4:
//       quick-work bucket assignment); 08 QUICK-213/214 (safe mode, save failures); ARCHITECTURE.md §7.5, §7.7.
import AppKit
import SwiftUI
import AACore

/// The dialog-driven flows of the quick-work window. Every flow re-resolves its targets by id and saves exactly
/// where Windows calls `Save()` (MarkDirty-only steps stay unsaved until the debounce).
@MainActor enum QuickWorkFlows {
    // MARK: Create (QUICK-055)

    static func newItem(_ kind: ItemKind, env: AppEnvironment, dialogs: DialogPresenter, model: QuickWorkModel) async {
        let title = kind == .task ? QuickWorkText.newTaskTitle : QuickWorkText.newProcedureTitle
        guard case .ok(let name) = await dialogs.prompt(TextPromptRequest(title: title, prompt: QuickWorkText.namePrompt)),
              !NetText.isBlank(name) else { return }
        let item: HierarchyItem? = kind == .task
            ? QuickWorkActions.createTask(named: name, store: env.store)
            : QuickWorkActions.createProcedure(named: name, store: env.store)
        guard let item else { return }
        QuickWorkPersist.save(env, dialogs: dialogs)
        model.select(item.id)
        model.refresh()
    }

    // MARK: Batch done / deadline (QUICK-051, QUICK-052, QUICK-079)

    static func markDone(_ items: [AnyObject], done: Bool, env: AppEnvironment, dialogs: DialogPresenter,
                         model: QuickWorkModel) {
        if BatchDone.setDoneAll(items, done: done) > 0 { QuickWorkPersist.flush(env, dialogs: dialogs) }
        model.refresh()
    }

    static func setDeadline(_ items: [AnyObject], env: AppEnvironment, dialogs: DialogPresenter, model: QuickWorkModel) async {
        guard !items.isEmpty else {
            await dialogs.info(QuickWorkText.setDeadlineTitle, QuickWorkText.setDeadlineNoSelection)
            return
        }
        let shared = BatchDeadline.sharedDeadline(of: items)
        let initial: NetDateTime? = shared ?? nil
        let r = await dialogs.datePrompt(DatePromptRequest(title: QuickWorkText.setDeadlineTitle,
                                                           prompt: QuickWorkText.setDeadlinePrompt(items.count),
                                                           initial: initial))
        let date: NetDateTime?
        switch r {
        case .cancelled: return
        case .cleared: date = nil
        case .ok(let d): date = d
        }
        if BatchDeadline.setDeadlineAll(items, date: date) > 0 { QuickWorkPersist.flush(env, dialogs: dialogs) }
        model.refresh()
    }

    // MARK: Buckets (QUICK-053, QUICK-054, QUICK-231)

    /// Returns true when the assignment changed (the caller refreshes).
    @discardableResult
    static func sortIntoBuckets(_ target: Bucketable, label: String, env: AppEnvironment, dialogs: DialogPresenter) async -> Bool {
        let store = env.store
        guard !store.data.quickBuckets.isEmpty else {
            await dialogs.info(QuickWorkText.bucketsTitle, QuickWorkText.noBuckets)
            return false
        }
        let rows = QuickWorkActions.bucketChoices(store: store).map { ItemPickerRow(display: $0.display, tag: $0.id) }
        let pre = QuickWorkActions.preselectedBuckets(for: target, store: store)
        guard let picked = await dialogs.pickItems(ItemPickerRequest(prompt: QuickWorkText.bucketPrompt(label), rows: rows,
                                                                     preselected: pre, mode: .multi,
                                                                     resultOrder: .selection)) else { return false }
        let live = Set(store.data.quickBuckets.map(\.id))
        let r = QuickWorkActions.applyBuckets(picked.filter { live.contains($0) }, to: target)
        if r.capped { await dialogs.info(QuickWorkText.bucketsTitle, QuickWorkText.bucketCap) }
        QuickWorkPersist.save(env, dialogs: dialogs)
        return true
    }

    static func sortCurrentIntoBuckets(_ item: HierarchyItem?, env: AppEnvironment, dialogs: DialogPresenter,
                                       model: QuickWorkModel) async {
        guard let item else {
            await dialogs.info(QuickWorkText.bucketsTitle, QuickWorkText.bucketsNoSelection)
            return
        }
        if await sortIntoBuckets(item, label: item.name.isEmpty ? "this item" : item.name, env: env, dialogs: dialogs) {
            model.refresh()
        }
    }

    static func removeFromBuckets(_ item: HierarchyItem?, env: AppEnvironment, dialogs: DialogPresenter, model: QuickWorkModel) {
        guard let item else { return }
        QuickWorkActions.removeFromBuckets(item)
        QuickWorkPersist.save(env, dialogs: dialogs)
        model.refresh()
    }

    // MARK: Pins and tiles (QUICK-062, QUICK-064)

    static func togglePin(_ id: UUID, env: AppEnvironment, dialogs: DialogPresenter, model: QuickWorkModel) {
        withAnimation(.snappy) {
            QuickWorkActions.togglePin(id, store: env.store)
            QuickWorkPersist.save(env, dialogs: dialogs)
            model.refresh()
        }
    }

    static func setTileDone(_ id: UUID, done: Bool, env: AppEnvironment, dialogs: DialogPresenter, model: QuickWorkModel) {
        guard let item = env.store.item(id: id) else { return }
        withAnimation(.snappy) {
            QuickWorkActions.setItemDone(item, done: done, store: env.store)
            QuickWorkPersist.save(env, dialogs: dialogs)
            model.refresh()
        }
    }

    // MARK: Delete (QUICK-073 → Trash)

    static func delete(_ item: HierarchyItem, env: AppEnvironment, dialogs: DialogPresenter, model: QuickWorkModel) async {
        let ok = await dialogs.confirm(QuickWorkText.deleteTitle, QuickWorkText.deleteMessage(item.name),
                                       confirm: "Move to Trash", destructive: true, defaultIsCancel: true)
        guard ok else { return }
        let id = item.id
        env.flushAllEditors()
        if let w = SceneOpener.shared.itemWindow(id) { w.performClose(nil) }      // 08 Q-16
        guard let live = env.store.item(id: id) else { model.itemDeleted(id); return }
        QuickWorkActions.moveToTrash(live, store: env.store)
        QuickWorkPersist.save(env, dialogs: dialogs)
        env.refreshAfterTrashChange()
        model.itemDeleted(id)
    }

    // MARK: Children (QUICK-075…079)

    static func addChild(to item: HierarchyItem, env: AppEnvironment, dialogs: DialogPresenter, model: QuickWorkModel) async -> UUID? {
        guard let kind = QuickWorkActions.childKind(of: item) else { return nil }
        guard case .ok(let name) = await dialogs.prompt(TextPromptRequest(title: QuickWorkText.newChildTitle(noun: kind.noun),
                                                                          prompt: QuickWorkText.namePrompt)),
              !NetText.isBlank(name) else { return nil }
        let id = QuickWorkActions.addChild(named: name, to: item, store: env.store)
        QuickWorkPersist.save(env, dialogs: dialogs)
        model.refresh()
        return id
    }

    static func deleteChildren(_ ids: Set<UUID>, of item: HierarchyItem, env: AppEnvironment, dialogs: DialogPresenter,
                               model: QuickWorkModel) async -> Bool {
        guard let kind = QuickWorkActions.childKind(of: item), !ids.isEmpty else { return false }
        let n = QuickWorkActions.children(of: item).filter { ids.contains($0.id) }.count
        guard n > 0 else { return false }
        let ok = await dialogs.confirm(QuickWorkText.confirmTitle, QuickWorkText.deleteChildrenMessage(n, noun: kind.noun),
                                       confirm: "Delete", destructive: true, defaultIsCancel: true)
        guard ok else { return false }
        QuickWorkActions.deleteChildren(ids, from: item, store: env.store)
        QuickWorkPersist.save(env, dialogs: dialogs)
        model.refresh()
        return true
    }

    /// `Edit…` / double-click: the subtask editor or the checklist-step editor (W-BUILD sheets); then Flush + rebuild.
    static func editChild(_ id: UUID, of item: HierarchyItem, env: AppEnvironment, dialogs: DialogPresenter,
                          model: QuickWorkModel) async {
        if item is TaskItem {
            await dialogs.presentSheet(.closeType) { _ in TaskItemEditorSheet(taskID: id) }
        } else if item is Procedure {
            await dialogs.presentSheet(.closeType) { _ in ChecklistStepEditorSheet(stepID: id) }
        }
        flushIfDirty(env, dialogs: dialogs)
        model.refresh()
    }

    /// `Open full builder…`: the subtask builder / checklist builder (W-BUILD sheets); then rebuild.
    static func openFullBuilder(_ item: HierarchyItem, env: AppEnvironment, dialogs: DialogPresenter, model: QuickWorkModel) async {
        let id = item.id
        if item is TaskItem {
            await dialogs.presentSheet(.closeType) { _ in SubtaskBuilderSheet(taskID: id) }
        } else if item is Procedure {
            await dialogs.presentSheet(.closeType) { _ in ChecklistBuilderSheet(host: .procedure(id)) }
        }
        flushIfDirty(env, dialogs: dialogs)
        model.refresh()
    }

    static func childBuckets(_ childID: UUID?, of item: HierarchyItem, env: AppEnvironment, dialogs: DialogPresenter,
                             model: QuickWorkModel) async {
        guard let kind = QuickWorkActions.childKind(of: item) else { return }
        guard let childID, let child = QuickWorkActions.childModel(childID, of: item) as? Bucketable else {
            await dialogs.info(QuickWorkText.bucketsTitle, QuickWorkText.childBucketsNoSelection(noun: kind.noun))
            return
        }
        let label = (child as? TaskItem)?.name ?? (child as? ChecklistStep)?.title ?? ""
        if await sortIntoBuckets(child, label: label, env: env, dialogs: dialogs) { model.refresh() }
    }

    // MARK: Saved lists (QUICK-080, QUICK-081)

    static func saveAsList(_ item: HierarchyItem, env: AppEnvironment, dialogs: DialogPresenter) async {
        guard !QuickWorkActions.children(of: item).isEmpty else {
            await dialogs.info(QuickWorkText.saveListTitle, QuickWorkText.saveListEmpty)
            return
        }
        guard case .ok(let raw) = await dialogs.prompt(TextPromptRequest(title: QuickWorkText.saveAsListTitle,
                                                                         prompt: QuickWorkText.saveAsListPrompt,
                                                                         initial: item.name)),
              !NetText.isBlank(raw) else { return }
        guard let live = env.store.item(id: item.id),
              let tpl = QuickWorkActions.saveAsList(named: NetText.trim(raw), from: live, store: env.store) else { return }
        QuickWorkPersist.save(env, dialogs: dialogs)
        await dialogs.info(QuickWorkText.savedListTitle, QuickWorkText.savedList(tpl.name, tpl.items.count))
    }

    static func loadSavedList(_ item: HierarchyItem, env: AppEnvironment, dialogs: DialogPresenter, model: QuickWorkModel) async {
        let templates = env.store.data.checklistTemplates
        guard !templates.isEmpty else {
            await dialogs.info(QuickWorkText.loadListTitle, QuickWorkText.noSavedLists)
            return
        }
        let rows = templates.map { ItemPickerRow(display: $0.display, tag: $0.id) }
        guard let picked = await dialogs.pickItems(ItemPickerRequest(prompt: QuickWorkText.insertListTitle, rows: rows,
                                                                     mode: .single)),
              let tplID = picked.first, let tpl = env.store.template(id: tplID) else { return }
        let spec = AlertSpec(title: QuickWorkText.insertListTitle,
                             message: QuickWorkText.insertListMessage(tpl.name, tpl.items.count), style: .informational,
                             buttons: [AlertButton(title: "Replace", role: .default), AlertButton(title: "Append"),
                                       AlertButton(title: "Cancel", role: .cancel)])
        let answer = await dialogs.alert(spec)
        guard answer == 0 || answer == 1, let live = env.store.item(id: item.id) else { return }
        QuickWorkActions.insertList(tpl, into: live, replace: answer == 0, store: env.store)
        model.refresh()
    }

    static func flushIfDirty(_ env: AppEnvironment, dialogs: DialogPresenter) {
        guard env.store.isDirty else { return }
        QuickWorkPersist.flush(env, dialogs: dialogs)
    }
}
