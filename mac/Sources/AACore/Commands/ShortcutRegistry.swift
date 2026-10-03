// Spec: 03 §6.5.1 (the authoritative shortcut & menu registry: §6.5.1.3 menu rows SHELL-530…663, §6.5.1.4 in-window
//       rows SHELL-665…695, SHELL-508 titles/tooltips, SHELL-509 hidden aliases, §6.5.1.9 key renderings,
//       §6.5.1.11 data format), DECISIONS R-70; ARCHITECTURE.md §6.9, §7.6. Tooltips are the Windows texts with the
//       §6.5.1.9 renderings and "PC" → "Mac" where the text names this machine.
import Foundation

/// One registry row (03 §6.5.1.11).
public struct ShortcutRow: Sendable, Hashable {
    public let id: String
    public let command: CommandID
    public let title: String
    /// Canonical key (see `ShellShortcutChord.key`); nil = no key equivalent.
    public let key: String?
    /// Canonical modifier names in ⌃ ⌥ ⇧ ⌘ order.
    public let modifiers: [String]
    /// Hidden aliases in glyph notation (SHELL-509), e.g. `["⇧⌘O"]`.
    public let aliases: [String]
    /// Menu path, e.g. `["File", "Shared Save"]`; empty for in-window rows.
    public let menuPath: [String]
    public let windowsGesture: String
    /// `APP`, `MAIN`, `SECT(x)`, `LIST(role)`, `RICH`, `TEXT`, `always`, `system`, `in-window`.
    public let scope: String
    /// `CMD`, `TXT`, `EDITOR`, `ROUTE`, `system`.
    public let precedence: String
    public let symbol: String?
    public let help: String?

    public init(id: String, command: CommandID, title: String, key: String?, modifiers: [String], aliases: [String],
                menuPath: [String], windowsGesture: String, scope: String, precedence: String, symbol: String?,
                help: String?) {
        self.id = id; self.command = command; self.title = title; self.key = key; self.modifiers = modifiers
        self.aliases = aliases; self.menuPath = menuPath; self.windowsGesture = windowsGesture; self.scope = scope
        self.precedence = precedence; self.symbol = symbol; self.help = help
    }

    /// The key equivalent as a chord (nil when the row has no key).
    public var chord: ShellShortcutChord? { key.map { ShellShortcutChord(key: $0, modifiers: modifiers) } }
    public var aliasChords: [ShellShortcutChord] { aliases.compactMap { ShellShortcutChord($0) } }
    /// Glyph rendering of the key (`⇧⌘S`), "" when none.
    public var keyDisplay: String { chord?.description ?? "" }
    public var isMenuItem: Bool { !menuPath.isEmpty }
    /// System-provided items AA keeps (Services, Hide, Cut/Copy/Paste, Minimize, …): built by AppKit / SwiftUI.
    public var isSystemProvided: Bool { precedence == "system" }
    /// The stable `NSUserInterfaceItemIdentifier` raw value (SHELL-508).
    public var itemIdentifier: String { "aa.cmd." + command.rawValue }
}

public enum ShortcutRegistry {
    /// Builds a row from glyph notation (`"⇧⌘S"`); "" = no key.
    static func r(_ id: String, _ command: CommandID, _ title: String, _ key: String, _ menu: [String],
                  _ windows: String, _ scope: String, _ precedence: String, symbol: String? = nil,
                  help: String? = nil, aliases: [String] = []) -> ShortcutRow {
        let chord = key.isEmpty ? nil : ShellShortcutChord(key)
        return ShortcutRow(id: id, command: command, title: title, key: chord?.key, modifiers: chord?.modifiers ?? [],
                           aliases: aliases, menuPath: menu, windowsGesture: windows, scope: scope,
                           precedence: precedence, symbol: symbol, help: help)
    }

    static let aa = ["AA"], file = ["File"], edit = ["Edit"], find = ["Edit", "Find"], view = ["View"],
               tools = ["Tools"], window = ["Window"], help = ["Help"], shared = ["File", "Shared Save"],
               drive = ["File", "Google Drive"], font = ["Format", "Font"], baseline = ["Format", "Font", "Baseline"],
               text = ["Format", "Text"], lists = ["Format", "Lists"], insert = ["Format", "Insert"],
               format = ["Format"], vessel = ["Tools", "Vessel"]

    /// Every row of 03 §6.5.1.3 (menu bar, menu order) followed by §6.5.1.4 (in-window keys).
    public static let rows: [ShortcutRow] = menuRows + sectionRows + inWindowRows

    static let menuRows: [ShortcutRow] = [
        // AA (application) menu
        r("SHELL-530", .about, "About AA", "", aa, "top-level _About (SHELL-115)", "always", "CMD", symbol: "info.circle"),
        r("SHELL-531", .settings, "Settings…", "⌘,", aa, "— (Mac addition, §6.4)", "APP", "CMD", symbol: "gearshape"),
        r("SHELL-532", .services, "Services", "", aa, "—", "system", "system"),
        r("SHELL-533a", .hideApp, "Hide AA", "⌘H", aa, "—", "always", "system"),
        r("SHELL-533b", .hideOthers, "Hide Others", "⌥⌘H", aa, "—", "always", "system"),
        r("SHELL-533c", .showAll, "Show All", "", aa, "—", "always", "system"),
        r("SHELL-534", .quit, "Quit AA", "⌘Q", aa, "E_xit; ✕ or Alt+F4 on main (SHELL-056/082)", "always", "CMD"),

        // File menu
        r("SHELL-540", .newItem, "New Item", "⇧⌘N", file, "+ New buttons (HIER-021, VIEW-053, VIEW-147, 06 New List)",
          "SECT(Equipment|Tasks|Procedures|Vessels|Board|Buckets|Saved Lists)", "CMD", symbol: "plus"),
        r("SHELL-541", .openInNewWindow, "Open in New Window", "", file, "sidebar context Open in new window (HIER-110)",
          "SECT(hierarchy)", "CMD", symbol: "macwindow.badge.plus"),
        r("SHELL-542", .rename, "Rename", "F2", file, "F2 (SHELL-046)", "SECT(hierarchy)", "TXT", symbol: "pencil"),
        r("SHELL-543", .quickLook, "Quick Look", "⌘Y", file, "— (Mac addition, 04 HIER-M06, 05 §6.9)",
          "LIST(fileBank|viewerFiles)", "TXT", symbol: "eye"),
        r("SHELL-544", .deleteFamily, "Delete", "⌘⌫", file, "the focused list's Delete/Remove button", "LIST(*)", "TXT",
          symbol: "trash"),
        r("SHELL-545", .close, "Close", "⌘W", file, "✕ / Alt+F4 (no Ctrl+W on Windows — W-12)", "always", "CMD"),
        r("SHELL-546", .save, "Save", "⌘S", file, "Ctrl+S, _Save, header Save (Ctrl+S)", "APP", "CMD",
          symbol: "square.and.arrow.down", help: "Save (⌘S)"),
        r("SHELL-547", .saveCopyAs, "Save a Copy As JSON…", "⇧⌘S", file, "Save _As...", "APP", "CMD", symbol: "doc.on.doc"),
        r("SHELL-548", .reloadFromDisk, "Reload from Disk", "", file, "_Reload from disk, header Load", "APP", "CMD",
          symbol: "arrow.clockwise"),
        r("R-70", .recoverConflictCopies, "Recover Conflict Copies…", "", file, "— (DECISIONS R-70, 01 DATA-181)",
          "APP", "CMD", symbol: "doc.on.clipboard",
          help: "Open the copies AA kept when the data file was changed outside this copy of AA."),
        r("SHELL-549", .importFromFile, "Import from File…", "", file, "_Import from file...", "APP", "CMD",
          symbol: "square.and.arrow.down.on.square"),
        r("SHELL-550", .trash, "Trash (Restore Deleted Items)…", "", file, "_Trash (restore deleted items)...", "APP",
          "CMD", symbol: "trash.circle",
          help: "Restore items you deleted, or remove them for good. Deletes go here instead of vanishing — ⌘Z undoes the last one."),
        r("SHELL-551", .encryptLocalData, "Encrypt Local Data File (This Mac)", "", file,
          "Encr_ypt local data file (this PC)", "APP", "CMD", symbol: "lock.doc",
          help: "Encrypt this Mac's data file at rest with a key kept in your macOS Keychain. Shared, exported and Google Drive copies stay portable plaintext, so sync between machines is unaffected."),
        r("SHELL-552", .setSharedSaveFile, "Set Shared Save File…", "", shared, "Set s_hared save file...", "APP", "CMD",
          help: "Use ONE save file at a location you choose (e.g. a network drive or a synced folder). AA autosaves there every minute and auto-reloads when another copy of AA updates it — point every computer at the same file to keep them in sync."),
        r("SHELL-553", .stopSharedSaveFile, "Stop Shared Save File", "", shared, "Stop shared save file", "APP", "CMD",
          help: "Go back to saving locally on this Mac only."),
        r("SHELL-554", .checkSharedSaveNow, "Check Shared Save Now", "", shared,
          "— (optional Mac addition, 01 §6.10)", "APP", "CMD",
          help: "Check the shared save file for a newer save right now."),
        r("SHELL-555", .setAppIdentity, "Set App Identity…", "", file, "Set app _identity...", "APP", "CMD",
          symbol: "person.text.rectangle",
          help: "Name this installation (e.g. a vessel or operator). It is stamped into every shared save and Google Drive export so you can tell which machine/operator produced a save. Always editable; defaults to the Mac name."),
        r("SHELL-556", .openDataFolder, "Open Data Folder", "", file, "Open data _folder", "APP", "CMD", symbol: "folder"),
        r("SHELL-557", .exportDataFolder, "Export Data Folder (ZIP)…", "", file, "_Export data folder (ZIP)...", "APP",
          "CMD", symbol: "archivebox"),
        r("SHELL-558", .importDataFolder, "Import Data Folder (ZIP)…", "", file, "I_mport data folder (ZIP)...", "APP",
          "CMD"),
        r("SHELL-559", .exportTextOnly, "Export Text Only (No Attachments)", "", file,
          "Export _text only (no attachments)", "APP", "CMD",
          help: "When on, exports and Google Drive saves carry only your text, changes and formatting — not the attached files. Much smaller and far quicker over a slow link. Importing one leaves the attachments already on the other PC exactly as they are."),
        r("SHELL-560", .driveSaveCopy, "Save a Copy to Google Drive (Synced Folder)", "", drive,
          "Save a copy to Google _Drive (synced folder)", "APP", "CMD",
          help: "Save a timestamped backup ZIP into your Google Drive desktop folder, which syncs it to the cloud."),
        r("SHELL-561", .driveSetFolder, "Set Google Drive Folder…", "", drive, "Set Google Drive folde_r...", "APP", "CMD",
          help: "Choose which local folder is your Google Drive (the one Google Drive for desktop syncs)."),
        r("SHELL-562", .driveUpload, "Upload Backup to Google Drive (OAuth)…", "", drive,
          "Upload backup to Google Drive (O_Auth)...", "APP", "CMD",
          help: "Upload a backup directly to Google Drive via the Drive API (no desktop client needed). Requires a Google OAuth client."),
        r("SHELL-563", .driveLoad, "Load Backup from Google Drive (OAuth)…", "", drive,
          "_Load backup from Google Drive (OAuth)...", "APP", "CMD",
          help: "Download a backup from your Google Drive and (after a newer/older check) replace your current data with it."),
        r("SHELL-564", .driveSetOAuthClient, "Set Google OAuth Client (client_secret.json)…", "", drive,
          "Set Google OAuth _client (client_secret.json)...", "APP", "CMD",
          help: "Load the client_secret.json you downloaded from Google Cloud Console (OAuth 'Desktop app' client)."),
        r("SHELL-565", .driveSignOut, "Sign Out of Google", "", drive, "Sign out of _Google", "APP", "CMD",
          help: "Forget the cached Google sign-in for OAuth uploads."),
        r("SHELL-566", .driveSyncOnSave, "Sync to Google Drive on Save", "", drive, "_Sync to Google Drive on save",
          "APP", "CMD",
          help: "When on, ⌘S also pushes your data to Google Drive (OAuth), and the app checks for a newer save pushed from other PCs."),
        r("SHELL-567", .driveCheckNewer, "Check Google Drive for Newer Save", "", drive,
          "C_heck Google Drive for newer save", "APP", "CMD",
          help: "Ask Google Drive whether a newer save state exists, and offer to load it."),
        r("SHELL-568", .flashSync, "Flash Sync with iPhone (QR)…", "", file, "Flash S_ync with iPhone (QR)...", "APP",
          "CMD", symbol: "qrcode",
          help: "Transfer your text, changes and formatting to or from the iPhone app by flashing QR codes on screen — no network, no cable, no Wi-Fi. Attachments are not included."),
        r("SHELL-569", .exportPDF, "Export as PDF…", "⌥⌘E", file, "header button Export PDF... (PDF-001)", "APP", "CMD",
          symbol: "arrow.up.doc"),
        r("SHELL-570", .print, "Print…", "⌘P", file, "— (optional Mac addition, 11 §6.2)", "APP", "CMD", symbol: "printer"),

        // Edit menu
        r("SHELL-575", .undo, "Undo", "⌘Z", edit, "Ctrl+Z (text undo; else main-window undo-delete)", "ROUTE", "ROUTE"),
        r("SHELL-576", .redo, "Redo", "⇧⌘Z", edit, "Ctrl+Y (text)", "TEXT", "EDITOR"),
        r("SHELL-577a", .cut, "Cut", "⌘X", edit, "Ctrl+X / Shift+Del", "system", "system"),
        r("SHELL-577b", .copy, "Copy", "⌘C", edit, "Ctrl+C / Ctrl+Ins", "system", "system"),
        r("SHELL-577c", .paste, "Paste", "⌘V", edit, "Ctrl+V / Shift+Ins", "system", "system"),
        r("SHELL-578", .pasteAndMatchStyle, "Paste and Match Style", "⌥⇧⌘V", edit,
          "Ctrl+Shift+V / context Paste text only (CONT-034)", "RICH", "EDITOR", aliases: ["⇧⌘V"]),
        r("SHELL-579", .delete, "Delete", "", edit, "Del on a text selection", "system", "system"),
        r("SHELL-580", .selectAll, "Select All", "⌘A", edit, "Ctrl+A", "system", "system"),
        r("SHELL-581", .moveUp, "Move Up", "⌃⌘↑", edit, "editor Ctrl+Alt+Up / ⤒ (CONT-046); list ↑ buttons", "ROUTE",
          "ROUTE", symbol: "arrow.up.to.line"),
        r("SHELL-582", .moveDown, "Move Down", "⌃⌘↓", edit, "editor Ctrl+Alt+Down / ⤓; list ↓ buttons", "ROUTE", "ROUTE",
          symbol: "arrow.down.to.line"),
        r("SHELL-583", .moveTo, "Move To…", "⇧⌘M", edit, "Move to... / Move to position... buttons", "LIST(*)", "TXT"),
        r("SHELL-584", .find, "Find…", "⌘F", find, "Ctrl+F (global Search window)", "APP", "ROUTE",
          symbol: "magnifyingglass"),
        r("SHELL-585", .searchAll, "Search All Items…", "⇧⌘F", find, "Ctrl+F / header Search (Ctrl+F)", "APP", "CMD",
          help: "Search all items (⌘F; ⇧⌘F from inside a note)"),
        r("SHELL-586", .searchCurrentList, "Search Current List", "⌥⌘F", find, "— (Mac addition, 10 §6.8, 12 §6.3)",
          "MAIN", "TXT"),
        r("SHELL-587", .findNext, "Find Next", "⌘G", find, "—", "RICH", "EDITOR"),
        r("SHELL-588", .findPrevious, "Find Previous", "⇧⌘G", find, "—", "RICH", "EDITOR"),
        r("SHELL-589", .useSelectionForFind, "Use Selection for Find", "⌘E", find, "—", "RICH", "EDITOR"),
        r("SHELL-590", .jumpToSelection, "Jump to Selection", "⌘J", find, "—", "RICH", "EDITOR"),
        r("SHELL-591a", .spellingAndGrammar, "Show Spelling and Grammar", "⌘:", ["Edit", "Spelling and Grammar"],
          "editor spell-check context menu (CONT-033)", "RICH", "system"),
        r("SHELL-591b", .checkDocumentNow, "Check Document Now", "⌘;", ["Edit", "Spelling and Grammar"],
          "editor spell-check context menu (CONT-033)", "RICH", "system"),
        r("SHELL-592a", .substitutions, "Substitutions", "", edit, "—", "RICH", "system"),
        r("SHELL-592b", .transformations, "Transformations", "", edit, "—", "RICH", "system"),
        r("SHELL-592c", .speech, "Speech", "", edit, "—", "RICH", "system"),
        r("SHELL-593", .systemTextServices, "Writing Tools / AutoFill / Start Dictation… / Emoji & Symbols", "", edit,
          "—", "system", "system"),

        // Format menu
        r("SHELL-600", .showFonts, "Show Fonts", "⌘T", font, "font-family combo (CONT-020)", "RICH", "EDITOR",
          symbol: "textformat"),
        r("SHELL-601", .bold, "Bold", "⌘B", font, "Ctrl+B, B Bold (Ctrl+B) (CONT-023)", "RICH", "EDITOR",
          symbol: "bold", help: "Bold (⌘B)"),
        r("SHELL-602", .italic, "Italic", "⌘I", font, "Ctrl+I", "RICH", "EDITOR", symbol: "italic", help: "Italic (⌘I)"),
        r("SHELL-603", .underline, "Underline", "⌘U", font, "Ctrl+U", "RICH", "EDITOR", symbol: "underline",
          help: "Underline (⌘U)"),
        r("SHELL-604", .strikethrough, "Strikethrough", "⇧⌘X", font, "S Strikethrough (CONT-024)", "RICH", "EDITOR",
          symbol: "strikethrough", help: "Strikethrough (⇧⌘X)"),
        r("SHELL-605", .bigger, "Bigger", "⌘+", font, "WPF built-in Ctrl+] (editor); Calendar A+ (VIEW-017)", "ROUTE",
          "ROUTE", aliases: ["⌘="]),
        r("SHELL-606", .smaller, "Smaller", "⌘−", font, "WPF built-in Ctrl+[; Calendar A-", "ROUTE", "ROUTE"),
        r("SHELL-607a", .baselineDefault, "Use Default", "", baseline, "—", "RICH", "EDITOR"),
        r("SHELL-607b", .superscript, "Superscript", "⌃⌘+", baseline, "WPF built-in Ctrl+Shift+= (CONT-030)", "RICH",
          "EDITOR", aliases: ["⌃⌘="]),
        r("SHELL-607c", .subscript, "Subscript", "⌃⌘−", baseline, "WPF built-in Ctrl+= (CONT-030)", "RICH", "EDITOR"),
        r("SHELL-608", .showColors, "Show Colors", "⇧⌘C", font, "A▾ other colour (CONT-025)", "RICH", "EDITOR",
          symbol: "paintpalette"),
        r("SHELL-609", .highlight, "Highlight", "", font, "HL (CONT-026)", "RICH", "EDITOR", symbol: "highlighter"),
        r("SHELL-610", .alignLeft, "Align Left", "⌘{", text, "Ctrl+L (CONT-027)", "RICH", "EDITOR",
          symbol: "text.alignleft"),
        r("SHELL-611", .center, "Center", "⌘|", text, "Ctrl+E", "RICH", "EDITOR", symbol: "text.aligncenter"),
        r("SHELL-612", .justify, "Justify", "", text, "Ctrl+J", "RICH", "EDITOR", symbol: "text.justify"),
        r("SHELL-613", .alignRight, "Align Right", "⌘}", text, "Ctrl+R in the editor (X-16)", "RICH", "EDITOR",
          symbol: "text.alignright"),
        r("SHELL-614", .bulletedList, "Bulleted List", "⇧⌘7", lists, "Ctrl+Shift+L, • Bullets (CONT-040)", "RICH",
          "EDITOR", symbol: "list.bullet"),
        r("SHELL-615", .numberedList, "Numbered List", "⇧⌘9", lists, "Ctrl+Shift+N, 1. Numbered (CONT-041)", "RICH",
          "EDITOR", symbol: "list.number"),
        r("SHELL-616", .indent, "Indent", "⌘]", lists, "Ctrl+T, →| (CONT-043)", "RICH", "EDITOR",
          symbol: "increase.indent", help: "Indent (Tab at the start of a list item)"),
        r("SHELL-617", .outdent, "Outdent", "⌘[", lists, "Ctrl+Shift+T, |←", "RICH", "EDITOR",
          symbol: "decrease.indent", help: "Outdent (⇧Tab at the start of a list item)"),
        r("SHELL-618", .insertLink, "Link…", "⌘K", insert, "🔗 Insert hyperlink (CONT-031)", "RICH", "EDITOR",
          symbol: "link"),
        r("SHELL-619", .insertTable, "Table…", "", insert, "▦ (CONT-032)", "RICH", "EDITOR", symbol: "tablecells"),
        r("SHELL-620", .insertSavedList, "Saved List…", "⌥⌘L", insert, "≔ (CONT-047/048)", "RICH", "EDITOR",
          symbol: "list.bullet.indent"),
        r("SHELL-621", .clearFormatting, "Clear Formatting", "", format, "Clr (CONT-028)", "RICH", "EDITOR",
          symbol: "eraser"),
        r("SHELL-622", .lockSelection, "Lock Highlighted Text…", "", format, "🔒 (CONT-060)", "RICH", "EDITOR",
          symbol: "lock"),
        r("SHELL-623", .unlockSelection, "Unlock Highlighted Text…", "", format, "🔓 (CONT-061)", "RICH", "EDITOR",
          symbol: "lock.open"),

        // View menu (after the section items, which are built from the current TabOrder)
        r("SHELL-631a", .previousSection, "Previous Section", "", view, "WPF TabControl Ctrl+Shift+Tab", "APP", "CMD"),
        r("SHELL-631b", .nextSection, "Next Section", "", view, "WPF TabControl Ctrl+Tab", "APP", "CMD"),
        r("SHELL-632", .plannerPrevious, "Previous", "⌘←", view, "Planner ◀ (VIEW-081)", "SECT(Planner)", "TXT",
          symbol: "chevron.left"),
        r("SHELL-633", .plannerToday, "Go to Today", "⇧⌘T", view, "Planner Today", "SECT(Planner)", "CMD",
          symbol: "calendar.circle"),
        r("SHELL-634", .plannerNext, "Next", "⌘→", view, "Planner ▶", "SECT(Planner)", "TXT", symbol: "chevron.right"),
        r("SHELL-635", .toggleSidebar, "Show Sidebar / Hide Sidebar", "⌃⌘S", view, "— (standard)", "MAIN", "system"),
        r("SHELL-636a", .toggleToolbar, "Hide Toolbar / Show Toolbar", "⌥⌘T", view, "— (standard)", "MAIN", "system"),
        r("SHELL-636b", .customizeToolbar, "Customize Toolbar…", "", view, "— (standard)", "MAIN", "system"),
        r("SHELL-637", .shortcutBar, "Shortcut Bar", "", view, "⌨ _Shortcut bar (SHELL-111)", "APP", "CMD",
          symbol: "keyboard",
          help: "Show/hide the keyboard-shortcuts reminder strip at the bottom of the window."),
        r("SHELL-638", .darkMode, "Dark Mode", "", view, "🌙 _Dark mode (SHELL-110)", "APP", "CMD", symbol: "moon",
          help: "Switch between the light and dark theme (remembered across launches)."),
        r("SHELL-639", .tabColors, "Customize Tab Colors…", "", view, "🎨 _Customize tab colors... (SHELL-112)", "APP",
          "CMD", symbol: "paintpalette",
          help: "Give each main tab its own background colour (remembered across launches)."),
        r("SHELL-640", .fullScreen, "Enter Full Screen / Exit Full Screen", "⌃⌘F", view, "—", "system", "system"),

        // Tools menu (Windows order kept)
        r("SHELL-645", .folderBuilder, "Folder Builder…", "", tools, "_Folder builder... (SHELL-090)", "APP", "CMD",
          symbol: "folder.badge.plus",
          help: "Bulk-create a folder structure (with subfolders) at a location of your choice."),
        r("SHELL-646", .dateCalculator, "Date Calculator…", "", tools, "Date _calculator... (SHELL-091)", "APP", "CMD",
          symbol: "calendar.badge.clock", help: "Find the range between two dates, or add/subtract days from a date."),
        r("SHELL-647", .dueDates, "Floating Due-Dates Window", "⌘R", tools,
          "Ctrl+R, Floating _due-dates window, header 📌 Due (SHELL-044/092)", "APP", "CMD", symbol: "pin",
          help: "Show a small always-on-top window of items due today and tomorrow."),
        r("SHELL-648", .quickWork, "Quick Work Window", "⌘N", tools, "Ctrl+N, Quick _work window (Ctrl+N)", "APP",
          "CMD", symbol: "square.grid.2x2",
          help: "Big window: all tasks & procedures on the left (active first), a comprehensive builder on the right."),
        r("SHELL-649", .quickSwitcher, "Quick Switcher…", "⌘O", tools,
          "Ctrl+O, Quick s_witcher (Ctrl+O), header Go to (Ctrl+O)", "APP", "CMD", symbol: "arrow.right.circle",
          help: "Fuzzy-jump to any item by name, kind or #tag — Obsidian-style. Type, then Return.", aliases: ["⇧⌘O"]),
        r("SHELL-650", .activityLog, "Activity Log…", "", tools, "_Activity log... (SHELL-095)", "APP", "CMD",
          symbol: "list.bullet.clipboard", help: "UTC-timestamped log of every entry added and removed."),
        r("SHELL-651", .unitConverter, "Unit Converter…", "", tools, "U_nit converter... (SHELL-096)", "APP", "CMD",
          symbol: "arrow.left.arrow.right",
          help: "Convert maritime units — speed, distance, pressure, temperature, volume, mass and more."),
        r("SHELL-652", .importCompasCrew, "Import COMPAS Crew (.xlsx)…", "", tools, "Import COMPAS _crew (.xlsx)...",
          "APP", "CMD", symbol: "person.badge.plus",
          help: "Import a COMPAS crew report and keep each member as an info card; tracks contract sign-off expiries."),
        r("SHELL-653", .checkCrewExpiries, "Check Crew Contract Expiries", "", tools, "Check crew contract e_xpiries",
          "APP", "CMD", symbol: "person.badge.clock",
          help: "List crew whose contracts (sign-off dates) are due soon or overdue."),
        r("SHELL-654a", .vesselImportWorkOrders, "Import Shippalm Work Orders (.xlsx)…", "", vessel,
          "vessel panel button (VESSEL-101)", "SECT(Vessels)", "CMD"),
        r("SHELL-654b", .vesselExportWorkOrders, "Export Work Orders (.xlsx)…", "", vessel, "vessel panel button",
          "SECT(Vessels)", "CMD"),
        r("SHELL-654c", .vesselImportPorts, "Import Ports of Call (.xlsx)…", "", vessel, "vessel panel button",
          "SECT(Vessels)", "CMD"),
        r("SHELL-654d", .vesselExportPorts, "Export Ports of Call (.xlsx)…", "", vessel, "vessel panel button",
          "SECT(Vessels)", "CMD"),
        r("SHELL-654e", .vesselNewQuickCard, "New Quick Card…", "", vessel, "quick-card add button", "SECT(Vessels)",
          "CMD"),
        r("SHELL-655", .sireExport, "SIRE 2.0 Export…", "", tools, "SIRE 2.0 e_xport... (SHELL-099)", "APP", "CMD",
          symbol: "checkmark.shield",
          help: "Export SIRE inspection data (checklist, tasks, status report, and more) to a text file or the clipboard."),
        r("SHELL-656", .setGeminiKey, "Set Gemini API Key…", "", tools, "Set _Gemini API key... (SHELL-100)", "APP",
          "CMD", symbol: "key",
          help: "Set your Google Gemini API key to enable AI task suggestions on the SIRE tab. Stored locally, never committed."),
        r("SHELL-657", .setPassword, "Set / Change Password…", "", tools, "Set / change _password... (SHELL-101)", "APP",
          "CMD", symbol: "key.horizontal"),
        r("SHELL-658", .lockNow, "Lock Now", "⌃⌘L", tools, "_Lock now (SHELL-102)", "APP", "CMD", symbol: "lock.fill",
          help: "Forget the unlocked password for this session. Any open locked container will require re-unlock."),

        // Window and Help menus
        r("SHELL-660a", .minimize, "Minimize", "⌘M", window, "—", "system", "system"),
        r("SHELL-660b", .zoom, "Zoom", "", window, "—", "system", "system"),
        r("SHELL-660c", .bringAllToFront, "Bring All to Front", "", window, "—", "system", "system"),
        r("SHELL-662", .keyboardShortcuts, "AA Keyboard Shortcuts", "", help,
          "the shortcut strip is the nearest Windows analogue", "always", "CMD", symbol: "keyboard"),
        r("SHELL-663", .helpSearch, "Search", "⇧⌘/", help, "Alt/F10 menu access keys (SHELL-690)", "system", "system"),
    ]

    /// SHELL-630: the 13 section items in display order; positions 1–9 carry ⌘1…⌘9 (titles come from TabOrder).
    static let sectionRows: [ShortcutRow] = CommandID.sectionCommands.enumerated().map { i, c in
        r("SHELL-630.\(i + 1)", c, "Section \(i + 1)", i < 9 ? "⌘\(i + 1)" : "", view,
          i < 9 ? "Ctrl+\(i + 1) / NumPad\(i + 1) (SHELL-045)" : "— (tabs 10–13 have no shortcut)", "APP", "CMD")
    }

    static let inWindowRows: [ShortcutRow] = [
        r("SHELL-665", .kbDefaultButton, "Default button", "↩", [], "IsDefault buttons; Enter handlers", "in-window", "CMD"),
        r("SHELL-666", .kbCancel, "Cancel or close", "⎋", [], "IsCancel buttons; switcher Esc", "in-window", "CMD",
          aliases: ["⌘."]),
        r("SHELL-667", .kbListPrimary, "List primary action (Hierarchy sidebar: Rename)", "↩", [], "double-click",
          "LIST(*)", "CMD"),
        r("SHELL-668", .kbBulkPrimary, "Add all / Create folders", "⌘↩", [], "— (Mac addition)", "in-window", "CMD"),
        r("SHELL-669", .kbSpace, "Quick Look / toggle", "Space", [], "— / checkbox Space", "LIST(fileBank|viewerFiles)",
          "CMD"),
        r("SHELL-670", .kbListDelete, "Delete with confirmation", "⌫", [], "—", "LIST(*)", "CMD", aliases: ["⌦"]),
        r("SHELL-671", .kbOpenFile, "Open the selected file", "⌘↓", [], "double-click / Open", "LIST(fileBank)", "CMD"),
        r("SHELL-672", .kbSwitcherKeys, "Quick switcher: move, open, close", "↑", [],
          "SearchBox_PreviewKeyDown (QuickSwitcherWindow.xaml.cs:81-90)", "in-window", "CMD", aliases: ["↓", "↩", "⎋"]),
        r("SHELL-673", .kbSearchReturn, "Search: run / navigate", "↩", [], "QueryBox_KeyDown, Results_Key", "in-window",
          "CMD"),
        r("SHELL-674", .kbFieldReturn, "Field Return actions (Sign in, unlock, commit name, add task)", "↩", [],
          "Enter handlers", "in-window", "CMD", aliases: ["⌥↩"]),
        r("SHELL-675", .kbTrashSheetKeys, "Trash: Put Back / Delete Immediately… / Empty Trash…", "⌘⌫", [],
          "buttons, no keys", "in-window", "CMD", aliases: ["⌥⌘⌫", "⇧⌘⌫"]),
        r("SHELL-676", .kbFlashSyncKeys, "Flash Sync: Stop", "⌘.", [], "—", "in-window", "CMD", aliases: ["⎋"]),
        r("SHELL-677", .kbMultiSelect, "Select all / toggle / range in lists", "⌘A", [],
          "Ctrl+A, Ctrl-click, Shift-click", "in-window", "CMD"),
        r("SHELL-678", .kbOpenLink, "Open a link (⌘-click)", "", [], "—", "RICH", "EDITOR"),
        r("SHELL-679", .kbDropModifiers, "File-bank drop: copy / link in place (⇧ or ⌥⌘)", "", [], "none/Shift at drop",
          "in-window", "CMD"),
        r("SHELL-680", .kbEditorTab, "Nest / un-nest list item", "⇥", [], "Tab / Shift+Tab (CONT-044)", "RICH", "EDITOR",
          aliases: ["⇧⇥"]),
        r("SHELL-681", .kbEditorReturn, "New list item / line break", "↩", [], "Enter / Shift+Enter", "RICH", "EDITOR",
          aliases: ["⇧↩"]),
        r("SHELL-682", .kbEditorBackspace, "Outdent at list-item start", "⌫", [], "Rtb_PreviewKeyDown Backspace (CONT-045)",
          "RICH", "EDITOR"),
        r("SHELL-683", .kbDeleteWord, "Delete word", "⌥⌫", [], "Ctrl+Backspace / Ctrl+Delete", "TEXT", "EDITOR",
          aliases: ["⌥⌦"]),
        r("SHELL-684", .kbTextNavigation, "Word / line / document / paragraph / page moves", "⌥←", [],
          "Ctrl+←/→, Home/End, Ctrl+Home/End, Ctrl+↑/↓, PgUp/PgDn", "TEXT", "EDITOR",
          aliases: ["⌥→", "⌘←", "⌘→", "⌘↑", "⌘↓", "⌥↑", "⌥↓"]),
        r("SHELL-685", .kbEscapeInRichText, "⎋ passed to the sheet", "⎋", [], "none", "RICH", "EDITOR"),
        r("SHELL-686", .kbOvertype, "Insert (overtype) — not available", "", [], "WPF ToggleInsert", "in-window", "CMD"),
        r("SHELL-687", .kbResetFormat, "Ctrl+Space — not mapped (Format ▸ Clear Formatting)", "", [], "WPF internal",
          "in-window", "CMD"),
        r("SHELL-688", .kbSireBodyKeys, "SIRE body keys (insertion only)", "", [], "DetailBox_PreviewKeyDown", "RICH",
          "EDITOR"),
        r("SHELL-689", .kbLockedText, "Locked text: only mutations are blocked", "", [], "CONT-063", "RICH", "EDITOR"),
        r("SHELL-690", .kbAccessKeys, "Menu access: ⌃F2 / Help search", "⌃F2", [], "Alt / F10 access keys", "system",
          "system"),
        r("SHELL-691", .kbContextMenuKey, "Context menu: ⌃-click", "", [], "Shift+F10 / Menu key", "system", "system"),
        r("SHELL-692", .kbAltF4, "Close window / quit (⌘W / ⌘Q)", "", [], "Alt+F4", "system", "system"),
        r("SHELL-693", .kbCtrlTab, "Previous / Next Section, ↑/↓ in the sidebar", "", [], "Ctrl+Tab / Ctrl+Shift+Tab",
          "MAIN", "CMD"),
        r("SHELL-694", .kbPopUpKeys, "Pop-ups and date fields", "", [], "Alt+↓ / F4 on DatePicker and ComboBox",
          "system", "system"),
        r("SHELL-695", .kbTypeAhead, "Type-ahead in lists", "", [], "WPF TextSearch", "system", "system"),
    ]

    /// The row for `command` (first match).
    public static func row(_ command: CommandID) -> ShortcutRow? { byCommand[command] }

    static let byCommand: [CommandID: ShortcutRow] = {
        var d: [CommandID: ShortcutRow] = [:]
        for r in rows where d[r.command] == nil { d[r.command] = r }
        return d
    }()

    public static func title(_ command: CommandID) -> String { row(command)?.title ?? command.rawValue }

    /// Menu rows whose key AA owns (system rows included), for the uniqueness check (SHELL-500).
    public static var menuChords: [(row: ShortcutRow, chord: ShellShortcutChord)] {
        rows.filter(\.isMenuItem).flatMap { r -> [(row: ShortcutRow, chord: ShellShortcutChord)] in
            (r.chord.map { [$0] } ?? []).map { (r, $0.normalized) } + r.aliasChords.map { (r, $0.normalized) }
        }
    }

    /// Reserved chords a row may still own because it IS that standard command (Quit ⌘Q, Hide ⌘H, …).
    public static let standardOwners: [CommandID: String] = [
        .quit: "⌘Q", .hideApp: "⌘H", .hideOthers: "⌥⌘H", .settings: "⌘,", .minimize: "⌘M", .fullScreen: "⌃⌘F",
        .helpSearch: "⇧⌘/",
    ]

    /// Toolbar help text with the key in parentheses (SHELL-510).
    public static func toolbarHelp(_ command: CommandID, base: String? = nil) -> String {
        let r = row(command)
        let text = base ?? r?.help ?? r?.title ?? command.rawValue
        guard let key = r?.keyDisplay, !key.isEmpty, !text.contains("(\(key))") else { return text }
        return "\(text) (\(key))"
    }
}
