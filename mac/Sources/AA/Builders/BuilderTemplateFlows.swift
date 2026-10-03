// Spec: 06 BUILD-015 (Save as list), BUILD-016 (Load a saved list), BUILD-017 (Manage saved lists), BUILD-044
//       (subtask wording), 02 REPO-142, REPO-147; Addendum caller registry rows #17–#19, #21 (prompts: trim in the
//       service, blank = no-op); 07 VIEW-212 rows 18, 21, 22 (single-select pickers); 06 §6.2 (Replace / Append /
//       Cancel, Rename… / Delete… / Cancel button verbs).
// The saved-list strip of every builder ("Saved lists:" Save as list… / Load a saved list… / Manage saved lists…).
import AppKit
import SwiftUI
import AACore

@MainActor enum BuilderTemplateFlows {
    /// BUILD-015 / BUILD-044: empty → info; prompt (initial = owner name); capture, append, log, Save, info.
    static func saveAsList<Item: AnyObject>(_ engine: BuilderEngine<Item>, env: AppEnvironment,
                                            dialogs: DialogPresenter, emptyMessage: String) async {
        guard engine.isBound else { return }
        if engine.items.isEmpty {
            await dialogs.info("Save list", emptyMessage)
            return
        }
        guard let name = await BuilderUI.nonBlankPrompt(dialogs, title: "Save as reusable list",
                                                        prompt: "Name for this saved list:",
                                                        initial: engine.ownerName) else { return }
        let tpl = engine.saveAsList(name: name)
        BuilderUI.save(env)
        await dialogs.info("Saved list", BuilderWording.savedListMessage(name: tpl.name, count: tpl.items.count))
    }

    /// BUILD-016 / BUILD-044: no lists → info; single-select picker "Insert a saved list" (arranged order); then
    /// Replace (Yes) / Append (No) / Cancel; apply, log, MarkDirty. Returns the ids now in the list (for selection).
    @discardableResult
    static func load<Item: AnyObject>(_ engine: BuilderEngine<Item>, env: AppEnvironment, dialogs: DialogPresenter,
                                      subtasks: Bool) async -> Bool {
        guard engine.isBound else { return false }
        let data = env.store.data
        if data.checklistTemplates.isEmpty {
            await dialogs.info("Load a saved list",
                               "No saved lists yet. Build a list and click 'Save as list...' to create one.")
            return false
        }
        let rows = BuilderSavedLists.templatePickerRows(data).map { (display: $0.display, tag: $0.id) }
        guard let id = await BuilderUI.pickOne(dialogs, prompt: "Insert a saved list", rows: rows),
              let tpl = env.store.template(id: id) else { return false }
        let choice = await BuilderUI.threeWay(dialogs, title: "Insert a saved list",
                                              message: BuilderWording.insertQuestion(name: tpl.name, count: tpl.items.count,
                                                                                    subtasks: subtasks),
                                              first: "Replace", second: "Append")
        guard choice != .cancel, env.store.template(id: id) === tpl else { return false }
        engine.apply(tpl, replace: choice == .first)
        return true
    }

    /// BUILD-017 (checklist builders only): no lists → info; picker; Rename… (Yes) / Delete… (No) / Cancel.
    static func manage(env: AppEnvironment, dialogs: DialogPresenter) async {
        let data = env.store.data
        if data.checklistTemplates.isEmpty {
            await dialogs.info("Manage saved lists", "No saved lists yet.")
            return
        }
        let rows = BuilderSavedLists.templatePickerRows(data).map { (display: $0.display, tag: $0.id) }
        guard let id = await BuilderUI.pickOne(dialogs, prompt: "Manage saved lists — pick one", rows: rows),
              let tpl = env.store.template(id: id) else { return }
        let choice = await BuilderUI.threeWay(dialogs, title: "Manage saved list",
                                              message: BuilderWording.manageListQuestion(name: tpl.name,
                                                                                        count: tpl.items.count),
                                              first: "Rename…", second: "Delete…", secondDestructive: true)
        switch choice {
        case .first:
            guard let v = await BuilderUI.prompt(dialogs, title: "Rename saved list", prompt: "New name:",
                                                 initial: tpl.name),
                  env.store.template(id: id) === tpl,
                  BuilderSavedLists.rename(env.store, tpl, rawName: v) else { return }
            BuilderUI.save(env)
        case .second:
            guard await BuilderUI.confirmDelete(dialogs, title: "Delete saved list",
                                                message: BuilderWording.deleteListQuestion(name: tpl.name)),
                  env.store.template(id: id) === tpl else { return }
            BuilderSavedLists.delete(env.store, tpl)
            BuilderUI.save(env)
        case .cancel:
            return
        }
    }
}
