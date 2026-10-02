// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §6.5
// Spec: 02 REPO-140…146, 06 BUILD-A19/A20 (saved-list templates). Compiling stub created by F1; F2 replaces this
// file in place. Capture/clone stubs return EMPTY detached objects; apply stubs change nothing (ARCH §11).
import Foundation

@MainActor public enum ChecklistTemplateService {
    public static func captureFromSteps(name: String, steps: [ChecklistStep]) -> ChecklistTemplate {
        // PLACEHOLDER(F2)
        ChecklistTemplate(name: name)
    }

    public static func captureFromSubtasks(name: String, subtasks: [TaskItem]) -> ChecklistTemplate {
        // PLACEHOLDER(F2)
        ChecklistTemplate(name: name)
    }

    @discardableResult
    public static func applyToSteps(_ t: ChecklistTemplate, steps: inout [ChecklistStep], replace: Bool) -> Int {
        // PLACEHOLDER(F2)
        0
    }

    @discardableResult
    public static func applyToSubtasks(_ t: ChecklistTemplate, subtasks: inout [TaskItem], replace: Bool) -> Int {
        // PLACEHOLDER(F2)
        0
    }

    public static func clone(_ t: ChecklistTemplate, newName: String) -> ChecklistTemplate {
        // PLACEHOLDER(F2)
        ChecklistTemplate(name: newName)
    }

    public static func itemToTask(_ item: ChecklistTemplateItem) -> TaskItem {
        // PLACEHOLDER(F2)
        TaskItem()
    }

    public static func toSteps(_ t: ChecklistTemplate) -> [ChecklistStep] {
        // PLACEHOLDER(F2)
        []
    }

    public static func writeBackFromSteps(_ t: ChecklistTemplate, steps: [ChecklistStep]) {
        // PLACEHOLDER(F2)
    }

    public static func cloneContainer(_ c: Container?) -> Container {
        // PLACEHOLDER(F2)
        Container()
    }

    public static func cloneFile(_ f: FileItem) -> FileItem {
        // PLACEHOLDER(F2)
        FileItem()
    }
}
