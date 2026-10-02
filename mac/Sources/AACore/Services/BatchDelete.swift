// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §6.5
// Spec: 02 REPO-073…075 (§3.7 BatchDelete; Mac key strings per 03 §6.5.1.9). Compiling stub created by F1; F2
// replaces this file in place. The stubs describe an empty selection and trash nothing (ARCH §11).
import Foundation

@MainActor public enum BatchDelete {
    /// The confirmation summary of a selection (02 §3.7 `Summary`).
    nonisolated public struct Description: Sendable, Equatable {
        public var equipment, tasks, procedures, vessels, descendants, withAttachments, linkedFromElsewhere, locked: Int

        public init(equipment: Int = 0, tasks: Int = 0, procedures: Int = 0, vessels: Int = 0, descendants: Int = 0,
                    withAttachments: Int = 0, linkedFromElsewhere: Int = 0, locked: Int = 0) {
            self.equipment = equipment; self.tasks = tasks; self.procedures = procedures; self.vessels = vessels
            self.descendants = descendants; self.withAttachments = withAttachments
            self.linkedFromElsewhere = linkedFromElsewhere; self.locked = locked
        }

        /// Top-level items in the selection.
        public var total: Int { equipment + tasks + procedures + vessels }
        public var isEmpty: Bool { total == 0 }

        /// "{n} task{s}, {n} procedure{s}, …" or "nothing".
        public func kindBreakdown() -> String {
            // PLACEHOLDER(F2)
            ""
        }
    }

    public static func topLevel(_ selection: [AnyObject]) -> [HierarchyItem] {
        // PLACEHOLDER(F2)
        []
    }

    public static func describe(_ selection: [AnyObject], store: AppStore,
                                isGated: (HierarchyItem) -> Bool) -> Description {
        // PLACEHOLDER(F2)
        Description()
    }

    /// Mac key strings (03 §6.5.1.9).
    public static func confirmationMessage(_ d: Description, trashCount: Int) -> String {
        // PLACEHOLDER(F2)
        ""
    }

    public static func nothingToDeleteMessage(_ d: Description) -> (title: String, message: String)? {
        // PLACEHOLDER(F2)
        nil
    }

    @discardableResult public static func trashAll(_ selection: [AnyObject], store: AppStore,
                                                   isGated: (HierarchyItem) -> Bool) -> Int {
        // PLACEHOLDER(F2)
        0
    }

    public static func statusAfterDelete(count: Int, firstName: String) -> String {
        // PLACEHOLDER(F2)
        ""
    }
}
