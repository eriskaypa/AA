// Spec: ARCHITECTURE.md §9.6 — W-PLAN's debug sheets for the snapshot hook (`--sheet w-plan.<name>`): the saved-list
//       → tasks picker of 07 VIEW-202 / VIEW-214 over the loaded data, and the Board / Buckets prompts with their exact
//       texts (VIEW-053, VIEW-147, VIEW-149). The five tabs themselves are snapshotted by SectionID.
import SwiftUI
import AACore

extension SnapshotRegistry {
    static func registerW_PLAN() {
        register("w-plan.saved-list-picker") { env in
            let rows: [String]
            if case .rows(let r) = BoardSavedListAdd.candidates(env.store.data) {
                rows = r.map(\.display)
            } else {
                rows = []
            }
            return AnyView(ItemPickerSheet(prompt: BoardSavedListAdd.prompt, displays: rows, preselected: [],
                                           single: false, candidateOrder: false) { _ in })
        }
        register("w-plan.new-task") { _ in
            AnyView(TextPromptSheet(request: TextPromptRequest(title: BoardModel.newTaskPromptTitle,
                                                               prompt: BoardModel.newTaskPromptLabel)) { _ in })
        }
        register("w-plan.new-bucket-category") { _ in
            AnyView(TextPromptSheet(request: TextPromptRequest(title: BucketsModel.categoryPromptTitle,
                                                               prompt: BucketsModel.categoryPromptLabel)) { _ in })
        }
        register("w-plan.set-category") { _ in
            AnyView(TextPromptSheet(request: TextPromptRequest(title: BucketsModel.setCategoryPromptTitle,
                                                               prompt: BucketsModel.setCategoryPromptLabel,
                                                               initial: "Location")) { _ in })
        }
    }
}
