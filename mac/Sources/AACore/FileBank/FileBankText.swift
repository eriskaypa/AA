// Spec: 05 CONT-080…098 (exact Windows strings), 05 §6.9 (Mac labels, hint, empty state, Windows-drive alert),
//       04 HIER-136 (viewer strings), 01 OC-12 (missing-file text shows the resolved path), 05 §8 K-9 (copy failure →
//       "Link in place instead"), DECISIONS P4 (ellipsis glyph in menu titles, "Finder" for "Explorer").
// Every user-visible string of the file bank, the read-only viewer and the backlinks section lives here so the
// views and the tests use one source.
import Foundation

public enum FileBankText {
    // MARK: Header and buttons (CONT-080, 05 §6.9)

    public static let title = "File Bank"
    public static let addFile = "Add File"
    public static let addFileHelp = "Import a COPY of the file into the app's data folder."
    public static let linkInPlace = "Link in Place"
    public static let linkInPlaceHelp =
        "Link a file/folder at its ORIGINAL location (e.g. on a network drive) without copying. Opening it edits the live file."
    public static let addFolder = "Add Folder"
    public static let addFolderHelp = "Import copies of every file inside a folder."
    public static let addLink = "Add Link"
    public static let addLinkHelp = "Add a web link (URL)."
    public static let cut = "Cut"
    public static let copy = "Copy"
    public static let paste = "Paste"
    public static let remove = "Remove"
    public static let open = "Open"
    public static let openAll = "Open All"
    public static let openAllHelp = "Open every file shown in the current tab at once — ideal for launching a whole routine."
    /// 05 §6.9 (Mac modifiers, SHELL-679).
    public static let dropHint = "Drag & drop to import — hold ⌥⌘ or ⇧ to link in place"

    // MARK: Context menu (CONT-080 + 05 §6.9 additions)

    public static let menuOpen = "Open"
    public static let menuShowInFinder = "Show in Finder"            // = "Open containing folder"
    public static let menuRename = "Rename…"
    public static let menuLinkToItems = "Link to Items…"
    public static let menuRemove = "Remove"
    public static let menuQuickLook = "Quick Look"
    public static let menuCopyPath = "Copy Path"
    public static let menuOpenWith = "Open With"
    public static let menuOtherApp = "Other…"
    public static let menuGoToOwner = "Show Owner"

    // MARK: Dialogs (CONT-084, 086, 092, 093)

    public static let linkInPlacePanelMessage = "Link file(s) in place (the originals are referenced, not copied)"
    public static let addFolderPanelMessage = "Choose a folder to import copies of every file inside it."
    public static let addLinkTitle = "Add link"
    public static let addLinkPrompt = "URL:"
    public static let addLinkInitial = "https://"
    public static let renameTitle = "Rename"
    public static let renamePrompt = "New name:"
    public static func linkPickerPrompt(_ fileName: String) -> String { "Link '\(fileName)' to items" }

    // MARK: Open / reveal (CONT-089…091)

    public static let openFailedTitle = "Open failed"
    public static func notFound(_ target: String) -> String { "Not found:\n\(target)" }
    public static let openAllTitle = "Open all"
    public static func openAllPrompt(_ n: Int) -> String { "Open all \(n) items in this tab now?" }
    public static let openFolderTitle = "Open folder"
    public static func fileNotFound(_ path: String) -> String { "File not found:\n\(path)" }
    public static let openFolderFailedTitle = "Open folder failed"
    /// Windows drive letter without a mapping (05 §6.9, ARCH §9.4).
    public static func windowsDriveUnmapped(_ drive: String) -> String {
        "This file is on a Windows drive (\(drive)). Map the drive letter to a folder on this Mac in Settings ▸ File Links."
    }
    /// UNC path without a mapping or a mounted share (ARCH §9.4 "offer Connect to Server…").
    public static func windowsShareUnmapped(_ share: String) -> String {
        "This file is on a Windows network share (\(share)). Connect to the server, or map the share to a folder on this Mac in Settings ▸ File Links."
    }
    public static let fileLinksSettings = "File Links Settings…"
    public static let connectToServer = "Connect to Server…"
    /// 01 §6.6: pick the file on this Mac; the answer stores the inferred mapping (`PathMapper.inferredMapping`).
    public static let locate = "Locate…"
    /// Open-panel message of Locate… (W-PERSIST-13 / quick-card wording).
    public static func locateMessage(_ windowsPath: String) -> String {
        let leaf = windowsPath.replacingOccurrences(of: "/", with: "\\").split(separator: "\\").last.map(String.init)
            ?? windowsPath
        return "Locate “\(leaf)” on this Mac"
    }
    /// Status line after Locate… stored a mapping (W-PERSIST-6 wording).
    public static func mappedStatus(_ m: PathMapping) -> String { "Mapped \(m.windowsPrefix) to \(m.macPath) on this Mac." }
    /// Status line when Connect to Server… did not mount the share within the retry window.
    public static func shareNotMountedStatus(_ share: String) -> String {
        "\(share) is not mounted yet — open the file again once Finder has connected."
    }
    public static let openAnyway = "Yes"
    public static let yes = "Yes"
    public static let no = "No"
    public static let cancel = "Cancel"
    public static let ok = "OK"

    // MARK: Import failures (05 §8 K-9 Mac decision)

    public static let importFailedTitle = "Import failed"
    public static func importFailed(_ names: [String], _ error: String) -> String {
        "Could not import a copy of:\n\(names.joined(separator: "\n"))\n\n\(error)\n\nLink the original in place instead (it is referenced, not copied)?"
    }
    public static let linkInPlaceInstead = "Link in Place Instead"

    // MARK: Empty states and counts (05 §6.9)

    public static let emptyTitle = "No files"
    public static let emptyMessage = "Drop files here or use Add File."
    public static func emptyTabMessage(_ tab: String) -> String { "Nothing in \(tab). Drop files here or use Add File." }
    public static let missingBadgeHelp = "The file is missing at its stored location."
    public static let unmappedBadgeHelp = "A Windows path — map it in Settings ▸ File Links to open it on this Mac."

    // MARK: View modes, footer, drop feedback, source help (Mac additions, 05 §6.9)

    public static let viewAsList = "as List"
    public static let viewAsIcons = "as Icons"
    public static let viewModeHelp = "View the files as a list or as icons"
    /// Footer: `1 item` / `{n} items`, prefixed by `{k} of ` and suffixed by ` selected` when rows are selected.
    public static func footerCount(shown: Int, selected: Int) -> String {
        let items = shown == 1 ? "1 item" : "\(shown) items"
        return selected > 0 ? "\(selected) of \(items) selected" : items
    }
    public static func lockedSharersCount(_ n: Int) -> String { "\(n) locked" }
    public static let dropToLinkInPlace = "Drop to link in place (originals are referenced)"
    public static let dropToImportCopy = "Drop to import a copy"
    public static let sourceWebLinkHelp = "A web link."
    public static let sourceLiveHelp = "Linked in place — opening it edits the original file."
    public static let sourceCopyHelp = "A copy stored in AA's data folder."

    // MARK: Shared containers (DECISIONS 05 — Container.SharedWithContainerIds)

    public static let sharedTab = "Shared"
    public static let stopSharing = "Stop Sharing"
    public static let sharing = "Sharing"
    public static let shareWith = "Share With…"
    public static let sharedWithHeader = "This file bank is shared with"
    public static let sharedIntoHeader = "Shared into this file bank by"
    public static let notShared = "Not shared with any other file bank"
    public static let nothingSharedIn = "No other file bank shares with this one"
    public static func sharePickerPrompt(_ owner: String) -> String {
        "Share the files of '\(owner)' with these file banks (they will list them under Shared)"
    }
    public static func sharedWithCount(_ n: Int) -> String { n == 1 ? "Shared with 1" : "Shared with \(n)" }
    public static let sharedFromColumn = "Shared from"
    public static let sharedReadOnlyHint = "Files shared from other file banks — open them here; edit them in their own file bank."
    public static let sharedEmptyTitle = "Nothing shared here"
    public static let sharedEmptyMessage = "Use Share With… in another file bank to list its files here."
    public static let lockedOwnerFiles = "(locked item — unlock it to see its files)"
    public static let unknownContainer = "(unknown file bank)"

    // MARK: "Linked to" and backlinks (DECISIONS 05 — FileItem.LinkedItemIds)

    public static let linkedToColumn = "Linked to"
    public static let backlinksTitle = "Linked files"
    public static func backlinksCount(_ n: Int) -> String { n == 1 ? "1 file is linked to this item" : "\(n) files are linked to this item" }
    public static let backlinksEmpty = "No files are linked to this item. Use Link to Items… on a file in any file bank."
    public static let backlinksInColumn = "In"
    public static let unlinkFromItem = "Unlink from This Item"
    public static let entryGone = "That file is no longer in the loaded data — nothing was changed."

    // MARK: Read-only viewer (04 HIER-136, 05 CONT-098, 01 OC-12)

    public static func viewerWindowTitle(_ title: String) -> String { "View — \(title)" }
    public static let viewerDefaultSubtitle = "Read-only view — click a link to open it. Editing is disabled."
    /// The Saved Lists caller's subtitle (HIER-136): without ` · {list}` when the list is unnamed.
    public static func savedListSubtitle(listName: String?) -> String {
        if let n = listName, !NetText.isBlank(n) {
            return "Saved-list item · \(n) — read-only. Click a link to open it; double-click a file to open it."
        }
        return "Saved-list item — read-only. Click a link to open it; double-click a file to open it."
    }
    public static let viewerNoNotes = "(no notes)"
    public static let viewerLocked = "(locked content)"
    public static let viewerFilesNone = "Files — none"
    public static func viewerFilesCount(_ n: Int) -> String { "Files (\(n)) — double-click to open" }
    public static let viewerOpenAllFiles = "Open All Files"
    public static let viewerOpenAllFilesHelp = "Open every file listed below."
    public static let viewerClose = "Close"
    public static let viewerOpenAllFilesTitle = "Open all files"
    public static let viewerNoFiles = "This item has no files."
    public static func viewerOpenAllPrompt(_ n: Int) -> String { "Open all \(n) files?" }
    public static let viewerMissingTitle = "Open file"
    public static func viewerMissing(_ path: String) -> String { "That file is missing:\n\n\(path)" }
    public static let viewerOpenTitle = "Open"
    public static func viewerCouldNotOpen(_ target: String, _ error: String) -> String {
        "Could not open:\n\n\(target)\n\n\(error)"
    }
    public static let viewerPathColumn = "Path / URL"
    public static let viewerNoLinkHandler = "No application is set to open this link."
    public static let viewerNotesAccessibility = "Notes (read-only)"

    // MARK: Column titles (CONT-080)

    public static let columnName = "Name"
    public static let columnKind = "Kind"
    public static let columnSource = "Source"
    public static let columnAdded = "Added"
    public static let columnPath = "Path"
    public static let columnURL = "URL"
}
