// Spec: 04 (every user-visible string of the hierarchy pages, copied from HierarchyPage / ItemWindow / ItemLockWindow /
//       ComponentEditorWindow / BatchDoneMenu / BatchDeadlineMenu), 03 §6.5.1.9 (key names rendered for the Mac via
//       `MacKeyStrings`), DECISIONS P4 (ellipsis glyph `…` in captions that open a dialog), DECISIONS 04 Q-G
//       (friendly status labels), §8 Q-09 (new "no groups to delete" text), Q-B help text.
import Foundation

/// Every user-visible string of the hierarchy pages, in one place (Windows text verbatim unless noted).
public enum HierText {
    // MARK: Page shell (HIER-001, HIER-003, HIER-004, HIER-006)

    public static func pageTitle(_ kind: ItemKind) -> String {
        switch kind {
        case .equipment: return "Equipment/Area"
        case .task: return "Tasks"
        case .procedure: return "Procedures"
        case .vessel: return "Vessels"
        default: return "Items"
        }
    }

    public static func specificsHeader(_ kind: ItemKind) -> String {
        switch kind {
        case .equipment: return "Components / Procedures / Tasks"
        case .task: return "Schedule & Subtasks"
        case .procedure: return "Checklist"
        default: return "Specifics"
        }
    }

    /// HIER-006 zero-items hint (Ctrl+N → ⌘N on the Mac).
    public static func emptyKindHint(_ kind: ItemKind) -> String {
        let text: String
        switch kind {
        case .equipment: text = "No equipment or areas yet.\n\nClick “+ New” to add your first one."
        case .task: text = "No tasks yet.\n\nClick “+ New” to add a task, or Ctrl+N for the quick-work window."
        case .procedure: text = "No procedures yet.\n\nClick “+ New” to build your first checklist procedure."
        case .vessel: text = "No vessels yet.\n\nClick “+ New” to add a vessel, then import its work orders and ports."
        default: text = "Nothing here yet.\n\nClick “+ New” to add one."
        }
        return MacKeyStrings.render(text)
    }

    public static let noSearchMatches = "No items match your search."
    public static let searchPrompt = "Search..."
    public static let newButton = "+ New"
    public static let deleteButton = "Delete"
    public static let sortAZ = "A→Z"
    public static let sortAZHelp = "Sort items alphabetically (otherwise list order is preserved)."
    public static let newGroupButton = "+ Group"
    public static let newGroupHelp = "Create a new group in this sidebar."
    public static let assignGroupButton = "Assign group…"
    public static let assignGroupHelp = "Move the selected item into a group (or out of all groups)."
    public static let renameGroupButton = "Rename group…"
    public static let renameGroupHelp = "Rename a sidebar group."
    public static let deleteGroupButton = "Delete group"
    public static let deleteGroupHelp = "Delete a sidebar group. Items inside it become ungrouped."
    /// Mac: the icon bar's overflow menu that holds Assign group…, Rename group… and Delete group (design rule 4).
    public static let groupCommandsMenu = "Group commands"
    public static let groupCommandsHelp = "Assign group…, Rename group…, Delete group"
    public static let placeholderRow = "(empty — right-click an item to assign)"

    // MARK: Sidebar context menu (HIER-020)

    public static let openInNewWindow = "Open in new window"
    public static let openInNewWindowHelp = "Open this item in its own window so you can work on several at once. Its notes and files move to that window until you close it."
    public static let moveToGroup = "Move to group…"
    public static let removeFromGroup = "Remove from group"
    public static let newGroupMenu = "New group…"
    public static let deleteSelected = "Delete selected…"
    public static var deleteSelectedHelp: String {
        MacKeyStrings.render("Move every selected item to the Trash. Restore from File \u{25B8} Trash, or undo with Ctrl+Z.")
    }
    /// The ⌘⌫ title of the sidebar list (03 §6.5.1.10 list roles).
    public static let moveToTrash = "Move to Trash"

    // MARK: Groups (HIER-030…034)

    public static let newGroupTitle = "New group"
    public static let nameLabel = "Name:"
    public static func groupCreated(_ name: String) -> String {
        "Group '\(name)' created. Right-click an item and choose 'Move to group…' to fill it."
    }
    public static func moveToGroupTitle(count: Int, firstName: String) -> String {
        count == 1 ? "Move '\(firstName)' to group" : "Move \(count) items to group"
    }
    public static let ungroupedRow = "(Ungrouped)"
    public static let renameGroupTitle = "Rename group"
    public static let noGroupsToRename = "No groups to rename in this tab yet."
    /// §8 Q-09 (new string; Windows does nothing silently).
    public static let deleteGroupTitle = "Delete group"
    public static let noGroupsToDelete = "No groups to delete in this tab yet."
    public static let pickGroupToRename = "Pick a group to rename"
    public static let newNameLabel = "New name:"
    public static let pickGroupToDelete = "Pick a group to delete (items inside become ungrouped)"
    public static let confirmTitle = "Confirm"
    public static func confirmDeleteGroup(_ name: String) -> String { "Delete group '\(name)'?" }

    // MARK: Header (HIER-025…027, HIER-041, HIER-044)

    public static let nameField = "Name:"
    public static let descriptionField = "Description:"
    public static let tagsField = "Tags:"
    public static var tagsHelp: String {
        MacKeyStrings.render("Comma- or space-separated tags. Used for filtering, global search and the quick switcher (Ctrl+O).")
    }
    public static let exportPDF = "Export PDF…"
    public static let exportPDFHelp = "Export this item, its hierarchy and relationships to an A4 PDF."
    public static let containerTab = "Container"
    public static let relationshipsTab = "Relationships"
    public static let quickCardsTab = "Quick Cards"
    public static let workOrdersTab = "Work Orders"
    public static let portsTab = "Ports"
    public static let detachedNote = "This item is open in its own window. Close that window to edit it here again."
    /// HIER-M07.
    public static let bringWindowToFront = "Bring Window to Front"
    /// §6.3 empty selection.
    public static let noSelectionTitle = "No Selection"
    public static let noSelectionMessage = "Select an item in the sidebar."
    public static func selectionBanner(_ n: Int) -> String { "\(n) items selected — showing the first one." }

    // MARK: Lock (HIER-050…058)

    public static func kindWord(_ kind: ItemKind) -> String {
        switch kind {
        case .equipment: return "equipment/area"
        case .task: return "task"
        case .procedure: return "procedure"
        case .vessel: return "vessel"
        default: return "entry"
        }
    }
    public static func lockedTitle(_ kind: ItemKind) -> String { "This \(kindWord(kind)) is locked." }
    public static let lockedSubtitle = "Enter its password (or the master password) to view and edit it."
    public static let showHint = "Show hint"
    public static let unlock = "Unlock"
    public static let wrongPassword = "Wrong password. Use the entry's password or the master password (“redemption”)."
    public static func hint(_ lockHint: String?) -> String {
        NetText.isBlank(lockHint) ? "(No hint was set.)" : "Hint: \(lockHint!)"
    }
    public static func unlockedStatus(_ name: String) -> String { "'\(name)' unlocked for this session." }
    public static let lockButton = "Lock"
    public static let lockButtonHelp = "Password-protect this entry (with an optional hint). The master password always unlocks."
    public static let lockedButton = "Locked"
    public static let lockedButtonHelp = "This entry is password-protected. Click to change the password/hint or remove the lock."
    public static func nowLockedStatus(_ name: String) -> String { "'\(name)' is now locked." }
    public static let manageLockTitle = "Manage lock"
    /// Mac form of the Yes/No/Cancel message (the buttons carry the verbs; DECISIONS P4).
    public static let manageLockMessage = "This entry is locked.\n\nChange the password / hint, remove the lock, or keep it as is."
    public static let changeLockButton = "Change Password / Hint…"
    public static let removeLockButton = "Remove Lock"
    public static let lockUpdatedStatus = "Lock updated."
    public static let lockRemovedStatus = "Lock removed."
    public static let lockAgain = "Lock again"
    public static let lockAgainHelp = "Re-gate this entry now — it will need the password again to open (this session)."
    public static func lockedAgainStatus(_ name: String) -> String { "'\(name)' locked again — the password is needed to open it." }
    public static let lockedAlertTitle = "Locked"
    public static let unlockBeforeWindow = "Unlock this entry before opening it in its own window."
    public static let lockSheetWindowTitle = "Lock entry"
    public static func lockSheetTitle(change: Bool, itemName: String) -> String {
        change ? "Change lock on “\(itemName)”" : "Lock “\(itemName)”"
    }
    public static func lockSheetPrompt(change: Bool) -> String {
        change ? "Enter a new password (and, optionally, a new hint). The master password always unlocks it."
               : "Set a password for this entry. It will be required to view or edit the entry. The app master password always unlocks it."
    }
    public static let passwordLabel = "Password:"
    public static let confirmPasswordLabel = "Confirm password:"
    public static let hintLabel = "Hint (optional — shown on the lock screen, never the password):"

    // MARK: Relationships (HIER-060…064)

    public static let addRelationship = "Add relationship…"
    public static let remove = "Remove"
    public static let relationshipsHelp = "Related items (double-click to open). Removing breaks the link both ways."
    public static let backlinksHeading = "Referenced by (backlinks) — items that point to this one:"
    public static let pickRelatedItems = "Pick related items"
    /// DECISIONS 04 Q-B.
    public static let oneWayRemoveHelp = "Linked from the Specifics tab — use Pick… there."
    public static let noRelatedItems = "No related items yet."
    public static let noBacklinks = "Nothing points to this item yet."

    // MARK: Equipment specifics (HIER-070…073)

    public static let components = "Components"
    public static let add = "+ Add"
    public static let edit = "Edit…"
    public static let componentEditHelp = "Open this component in a dedicated editor with its own rich-text container and file bank."
    public static let newComponentTitle = "New Component"
    public static let notesColumn = "Notes"
    public static let nameColumn = "Name"
    public static func componentEditorTitle(_ name: String) -> String { "Edit component — \(name)" }
    public static let shortNotesLabel = "Short notes:"
    public static let shortNotesHelp = "One-line summary shown in the components list. Use the rich-text area below for the full container content."
    public static let close = "Close"
    public static let relatedProcedures = "Related Procedures (auto-relates sub-hierarchy)"
    public static let pick = "Pick…"
    public static let newProcedureButton = "+ New procedure"
    public static let newProcedureHelp = "Create a new Procedure and auto-link it to this Equipment/Area."
    public static let pickProcedures = "Pick procedures"
    public static let newProcedureTitle = "New Procedure"
    public static let relatedTasks = "Related Tasks"
    public static let newTaskButton = "+ New task"
    public static let newTaskHelp = "Create a new Task and auto-link it to this Equipment/Area."
    public static let pickTasks = "Pick tasks"
    public static let newTaskTitle = "New Task"

    // MARK: Task specifics (HIER-080…087)

    public static let deadlineLabel = "Deadline:"
    public static let taskDeadlineHelp = "Due date — also the LAST day of the working range."
    public static let startLabel = "Start (optional):"
    public static let startHelp = "Optional first day of the working range. Leave empty for a single-day task."
    public static let recurrenceLabel = "Recurrence:"
    public static let statusLabel = "Status:"
    public static let taskStatusHelp = "Workflow status used by the Board (Done keeps Completed in sync)."
    public static let completed = "Completed"
    public static let schedulableJob = "Schedulable job"
    public static let schedulableJobHelp = "Tag this task as a Job so it can be dragged onto the Planner."
    public static let durationLabel = "Duration (min):"
    public static let subtaskBuilder = "Open Comprehensive Subtask Builder"
    public static let subtaskBuilderHelp = "Open a dedicated window to bulk-create, reorder, edit and delete subtasks."
    public static let subtasks = "Subtasks"
    public static let whenColumn = "When"
    public static let statusColumn = "Status"
    public static let doneColumn = "Done"
    public static let newSubtaskTitle = "New Subtask"
    public static let subtaskEditHelp = "Open this subtask in a dedicated editor with its own deadline, container and files."
    public static let noSubtasks = "No subtasks yet."

    // MARK: Procedure specifics (HIER-090)

    public static let procedureDeadlineHelp = "Optional deadline for this procedure. Shown in the Calendar-style floating due-dates window."
    public static let procedureStatusHelp = "Workflow status for this procedure."
    public static let procedureJob = "Mark this procedure as a schedulable job"
    public static let procedureJobHelp = "Tag the whole procedure as a Job so it can be dragged onto the Planner."

    // MARK: Item window (HIER-111, HIER-114)

    public static let itemWindowFooter = "Schedule, subtasks, steps and relationships stay in the main window — this window covers the notes and file bank."
    public static let orphaned = "This item is no longer in the loaded data — nothing typed here will be saved."
    public static let windowName = "Name"
    public static let windowDescription = "Description"
    public static let windowTags = "Tags"
    /// `"{Kind} — {name}"`, `(unnamed)` when the name is empty (Kind = enum name).
    public static func itemWindowTitle(kind: ItemKind, name: String) -> String {
        "\(kind.name) — \(name.isEmpty ? "(unnamed)" : name)"
    }

    // MARK: Batch menus (HIER-133, HIER-134; 02 REPO-043, REPO-053)

    public static let markDone = "Mark selected as done"
    public static let markNotDone = "Mark selected as not done"
    public static let setDeadline = "Set deadline for selected…"
    public static let setDeadlineHelp = "Give every selected item the same deadline (or clear it)."
    public static let setDeadlineTitle = "Set deadline"
    public static let setDeadlineEmpty = "Select one or more items first, then set the deadline."
    public static func setDeadlinePrompt(_ n: Int) -> String { "Apply one deadline to \(n) selected item\(n == 1 ? "" : "s"):" }

    // MARK: Errors (§8 Q-26)

    public static let saveFailedTitle = "Save failed"

    /// `"[{Kind}] {Name}"` (Kind = enum name, HIER-060).
    public static func label(_ item: HierItemSummary) -> String { "[\(item.kind.name)] \(item.name)" }
}

/// A value summary of an item for labels and pickers.
public struct HierItemSummary: Sendable, Hashable {
    public var id: UUID
    public var kind: ItemKind
    public var name: String
    public init(id: UUID, kind: ItemKind, name: String) { self.id = id; self.kind = kind; self.name = name }
}
