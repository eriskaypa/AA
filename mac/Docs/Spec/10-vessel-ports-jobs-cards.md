# 10 — Vessel dashboard: Quick Cards, Work Orders (Shippalm), Ports of Call, Ports Database

Porting spec for the **vessel-ports-jobs-cards** subsystem of AA (Windows WPF, .NET 10, C#) →
native macOS app in **Swift** (SwiftUI + AppKit where needed, macOS 26+, Swift 6.4, Xcode 27).

Feature-ID prefix: **`VESSEL-`**. IDs are stable. Do not renumber them. Gaps are deliberate, to leave room.

> This document is the contract. A Swift implementer who has never seen the C# must be able to rebuild
> every behaviour from it. A verifier must be able to check the Mac build against it line by line.
> Where the Windows app has a quirk or bug, the spec records it and says whether to **replicate** it
> (the default, for data and behaviour parity) or flags it as an **open question** (§9).

---

## 0. Source files covered (all read completely)

| File (under `AA/`) | Lines | Role |
|---|---|---|
| `Views/QuickCardsPanel.xaml` / `.xaml.cs` | 28 / 277 | Per-vessel free-form card canvas |
| `Views/QuickCardEditorWindow.xaml` / `.xaml.cs` | 74 / 166 | Modal card editor (target, icon, colour, size, preview) |
| `Views/ShipJobsPanel.xaml` / `.xaml.cs` | 129 / 462 | Per-vessel Shippalm work orders ("Work Orders" tab) + `JobRow` |
| `Views/PortsPanel.xaml` / `.xaml.cs` | 55 / 162 | Per-vessel ports of call ("Ports" tab) |
| `Views/PortsPage.xaml` / `.xaml.cs` | 63 / 69 | Global "Ports" main tab (Ports Database) |
| `Services/PortsService.cs` | 147 | Apply/merge imports, remove call, Excel export |
| `Services/PortCallReader.cs` | 246 | Reads both ports-of-call xlsx layouts |
| `Services/ShippalmReader.cs` | 171 | Reads/writes the Shippalm Work Order List xlsx |
| `Services/MaritimeIcons.cs` | 63 | Icon set, colour palette, readable-foreground maths |
| `Models/Models.cs` (L283–452) | — | `Vessel`, `PortCall`, `Port`, `PortVisit`, `ShipJob`, `QuickCard` |
| `Models/CrewMember.cs` L142 | — | `CrewMember.ParseDate` (shared date parser used here) |
| `Services/CrewMapping.cs` L11 | — | `CrewText.Norm` (header normaliser used by the Shippalm reader) |
| `Services/DataStore.cs` | — | JSON options, `ImportFile`, `ResolveFilePath`, `AppFolder`/`FilesFolder` |
| `Services/AppRepository.cs` | — | `MarkDirty` (750 ms debounce), `FlushIfDirty`, `Save`, `LogAdded` |
| `Views/HierarchyPage.xaml(.cs)` | — | Hosts the three vessel tabs; selection/lock/detach wiring |
| `MainWindow.xaml(.cs)` | — | Hosts the global Ports tab; `StatusBlock`; global Ctrl+Z |
| `Views/PromptWindow.xaml(.cs)` | — | The "Web link" URL prompt |
| `AA/POC/Last Ports - 24 Months (4).xlsx` | — | Sample of import layout **A** (inspected cell by cell) |
| `AA/POC/Port of Call List - Last 10 Ports (14).xlsx` | — | Sample of import layout **B** (inspected cell by cell) |

PROGRESS.md sections folded in: "Per-vessel Quick Cards dashboard", "Per-ship Shippalm work-order import +
per-job notification choice", "Follow-up (2026-07-04): per-vessel export + notifications kept inside the vessel
tab", "Performance pass for large imports (2026-07-04)", "Update (2026-07-08): work-orders area — filtering,
sorting, completion & deletion", "Ports of call import (two formats) → per-vessel + global database", "Link files
in place", "Batch delete … (QuickCard targets note)", "IV. Vessels", "Crew date parser" (for the date-parsing caveat),
"Open a task / procedure / equipment in its own window" (detach interplay), "Floating due-dates window".

**Rich text / XAML:** this subsystem neither produces nor consumes any WPF XAML or rich text. The vessel's own
`Container` (notes and file bank) is covered by the container spec. **No XAML↔NSAttributedString work is needed here.**

**Encrypted blobs:** none in this subsystem. The per-item lock (`LockHash`/`LockSalt`) only *gates* these tabs
(VESSEL-004). It does not encrypt any of the data described here.

---

## 1. Overview

### 1.1 Purpose
A **Vessel** is one of the four hierarchy kinds (Equipment/Area, Task, Procedure, Vessel). On top of the generic
container and relationships, each vessel owns three ship-operations tools:

1. **Quick Cards.** A free-form dashboard of resizable, draggable, coloured tiles with icons. Each tile is a
   shortcut to one of four targets: an **imported copy** of a file, a **file linked in place** (e.g. on a network
   drive), a **folder linked in place**, or a **web link**. This is the vessel's *first screen*.
2. **Work Orders.** An import of the Shippalm PMS "Work Order List" export (thousands of recurring maintenance
   jobs), with analysis, filtering, sorting, per-job completion, per-job *Notify* flags, a per-ship notifications
   master switch and an in-panel notifications bar, plus an xlsx export that round-trips.
3. **Ports.** An import of a ports-of-call list in one of two xlsx layouts (auto-detected), merged per vessel by
   *port + arrival date*. It also feeds a global **Ports Database**.

The global **Ports Database** is a top-level main tab. It lists every port any vessel has called and, for the
selected port, which vessels called and when.

### 1.2 Where it sits in the app
```
MainWindow
├── TabControl (main tabs, draggable order, Ctrl+1..9 jumps to Nth tab)
│   ├── … Equipment/Area | Tasks | Procedures | Vessels (HierarchyPage kind=Vessel) …
│   │        └── details pane → DetailsTabs (TabControl):
│   │              [Quick Cards] [Work Orders] [Ports] [Container] [Relationships]   (Specifics hidden for vessels)
│   │               QuickCardsPanel  ShipJobsPanel  PortsPanel
│   ├── … Calendar | Board | Planner | Relationship Map | Crew | Saved Lists | Buckets …
│   ├── [Ports]  → PortsPage  (global Ports Database)          ← MainWindow.xaml:188
│   └── [SIRE 2.0]
└── status bar: StatusBlock (TextBlock) ← all "StatusHint(...)" messages from these panels land here
```
* The three vessel tabs are declared in `HierarchyPage.xaml:151-159` with `Visibility="Collapsed"`. They become
  visible only when the page kind is `Vessel` (`HierarchyPage.xaml.cs:64-66`).
* On vessel selection (`HierarchyPage.xaml.cs:532-538`) all three panels get `Load(vessel, repo)` and **Quick
  Cards is made the selected tab**.
* `PortsPage.Init(repo)` is called when the data is loaded or reloaded (`MainWindow.xaml.cs:1213`). `PortsPage.Refresh()`
  runs every time its main tab is selected (`MainWindow.xaml.cs:1417`).

### 1.3 Data ownership (all inside the one `data.json`)
```
AppData
├── Vessels[]                               (HierarchyItem subclass; generic keys covered elsewhere)
│   ├── QuickCards[]   : QuickCard          ← Quick Cards tab
│   ├── Jobs[]         : ShipJob            ← Work Orders tab (keyed by JobNo, case-insensitive)
│   ├── NotificationsEnabled : bool (default true)
│   └── PortCalls[]    : PortCall           ← Ports tab (keyed by lower(PortName)+"@"+ArrivalDate)
└── Ports[]            : Port               ← global Ports Database (fed only by vessel port imports)
    └── Visits[]       : PortVisit          (one per vessel + arrival date; snapshot of vessel name)
```
Imported-copy Quick Card files live in `<AppFolder>/files/<32-hex-guid>_<original name>`. Those files travel
in `.aaz`/`.zip` bundles along with the rest of `files/`.

### 1.4 Persistence triggers at a glance
| Action | Call | Effect |
|---|---|---|
| Quick card add (OK), edit (OK), duplicate, delete, move end, resize end | `MarkDirty()` + `FlushIfDirty()` | **Immediate synchronous save** |
| Quick card edit **Cancel** | none | In-memory edits reverted from snapshot |
| Work orders import | `Save()` | Immediate synchronous save |
| Per-row **Notify** checkbox | `MarkDirty()` | **Debounced** save (750 ms after last change) |
| Per-row **Done** checkbox | `MarkDirty()` | **Debounced** save (750 ms) |
| Mark completed / Mark active / Notify ON-OFF (selected or shown) / 🔔 shown ON / 🔕 shown OFF / Delete jobs | `Save()` | Immediate |
| Notifications master switch | `MarkDirty()` + `FlushIfDirty()` | Immediate |
| Ports import | `LogAdded(...)` (marks dirty) then `Save()` | Immediate. Adds an activity-log entry |
| Ports delete | `Save()` | Immediate |
| Exports (both) | none | Writes the xlsx only |

`AppRepository` contract (for the Mac repository port): `MarkDirty()` restarts a **750 ms** one-shot timer that
serialises on the UI thread and writes on a background queue. `Save()` stamps `LastModified = DateTime.Now`,
serialises, queues the write after any pending write, and **blocks until it is on disk** (15 s timeout → throws).
`FlushIfDirty()` calls `Save()` only if dirty. When `SuspendSaving` is set (safe mode) all of these are no-ops.

---

## 2. FEATURE CHECKLIST

Notation: **UI strings are quoted exactly** (including emoji, curly quotes “ ”, em dash —, middle dot ·,
ellipsis …, ≤, ▸, •). `\n` = newline. `{x}` = interpolated value. MessageBox → (caption, body, buttons, icon).

### A. Hosting & navigation

**VESSEL-001 — Vessel-only detail tabs.**
Vessels show detail tabs in this order: `Quick Cards`, `Work Orders`, `Ports`, `Container`, `Relationships`.
The `Specifics` tab is hidden for vessels. For every other kind the three vessel tabs are hidden and the
`Container` tab is selected by name (not by index; an earlier index-based bug was fixed that way).

**VESSEL-002 — Quick Cards is the vessel's first screen.**
Whenever a vessel is selected in the Vessels list, all three panels are (re)loaded for that vessel and the
**Quick Cards** tab is selected, whatever tab was showing before.

**VESSEL-003 — Panel state survives vessel switches (session only).**
One instance of each panel is reused for every vessel. On `Load`:
* Quick Cards fully rebuilds.
* Work Orders keeps its **search text, Due/overdue-only and Notify-on-only toggles, Completion filter selection
  and sort column/direction**. The Status/Category/Rank combos are repopulated from the new vessel's jobs, and each
  keeps its previous selection if that exact value (case-sensitive) exists for the new vessel. Otherwise it resets
  to "(all …)".
* Ports keeps its **search text and sort column/direction**.
None of this state is persisted to disk. A restart resets it: Work Orders sort `Due` ascending, Ports sort
`Arrival` descending, filters cleared.

**VESSEL-004 — Lock gate.**
If the selected vessel is password-locked and not unlocked this session, the whole details tab control
(including these three tabs) is hidden behind the lock overlay (`HierarchyPage.ApplyLockGate`). Nothing in this
subsystem is viewable or editable until the vessel is unlocked.

**VESSEL-005 — Detached vessel ("Open in new window").**
When the selected vessel is open in its own `ItemWindow`, `HierarchyPage` returns early. The three vessel panels
are **not** reloaded and the details root is disabled. Windows therefore shows the *previously loaded* vessel's
panels, greyed out. This is a Windows quirk; see §9 Q5. The `ItemWindow` itself does not host these panels.

**VESSEL-006 — Status line hints.**
Panels post one-line confirmations to the main window's status bar `StatusBlock` via
`Window.GetWindow(this).FindName("StatusBlock")`. If the host window has no `StatusBlock`, the hint is silently
dropped. Every hint text is listed in the feature that emits it.

**VESSEL-007 — Global "Ports" main tab.**
A main tab with header `Ports` hosts the Ports Database (VESSEL-250…). It is initialised on data load and
refreshed every time the tab is selected. It participates in draggable tab order and Ctrl+1..9 like every main tab.

---

### B. Quick Cards panel (`QuickCardsPanel`)

**VESSEL-010 — Header bar.**
A bordered panel (`Panel` background, `BorderB` 1 px border, corner radius 4, padding 10,8) holds:
* the title `Quick Cards` (bold, 16, `Accent` colour);
* the hint `Double-click a card to open it. Drag to move, drag the corner to resize, right-click to edit.`
  (`Muted`, 14 px left margin, character-ellipsis trimming);
* on the right, the accent-styled button `+ Quick card`.

**VESSEL-011 — Canvas and scrolling.**
Below the header is a bordered panel with a two-way auto-scrolling area containing a free-form canvas. Its size is
recomputed after every add, edit, move and resize (`SizeCanvas`):
`width = max(1000, max over cards of (X + Width + 40))` and `height = max(640, max over cards of (Y + Height + 40))`.
The canvas never shrinks below 1000×640 and always keeps 40 px of slack beyond the right-most and bottom-most card.

**VESSEL-012 — Empty state.**
With zero cards, a centred, wrapped, non-interactive muted text is shown over the canvas:
`No quick cards yet for this vessel.\nClick '+ Quick card' to add a shortcut to a file, folder, or web link.`
It is hidden as soon as one card exists.

**VESSEL-013 — Card rendering.**
Each card is a rounded rectangle:
* Size: exactly `Width × Height`. Top-left at canvas `(X, Y)`.
* Background: the card `Color` parsed as a colour (`#AARRGGBB`, `#RRGGBB` or any WPF colour string). Invalid or
  empty → `#FF1E88E5`. **Alpha is honoured**, so a semi-transparent colour shows the panel behind it.
* Corner radius 10. Border 1 px in the theme `BorderB` colour (light theme `#000000`, dark `#3F3F46`).
* Hand cursor. Tooltip per VESSEL-015.
* Content: a vertically and horizontally centred stack with 6 px margin:
  * the **icon** glyph (`Icon` string) at font size `max(18, min(Width, Height) × 0.36)`, centred, in the readable
    foreground;
  * if `Title` is not blank/whitespace, the **title** in bold 13, wrapped, centred, 4 px top margin, same foreground.
    Blank titles render no title line at all.
* The icon size is computed when the card is built. During a live resize the frame changes but the icon size
  updates only when the card is rebuilt at the end of the resize.

**VESSEL-014 — Readable foreground.**
Icon, title and resize grip use black-ish `#1A1A1A` or white, chosen from the background colour by
`MaritimeIcons.ReadableForeground` (§3.1.3): luminance `(0.299R + 0.587G + 0.114B)/255 > 0.6` → `#1A1A1A`, else
white. Alpha is ignored.

**VESSEL-015 — Card tooltip.**
Three lines:
```
{Title, or "(untitled)" if blank}
{kind}: {Target, or "(no target — right-click ▸ Edit)" if blank}
Double-click to open • drag to move • drag corner to resize
```
`kind` = `Web link` if `IsLink`; else `Folder (live)` if `IsFolder`; else `File (live)` if `LinkInPlace`; else
`Imported copy`. The kind is shown even when the target is blank, e.g. `Imported copy: (no target — right-click ▸ Edit)`.
For imported copies the tooltip shows the stored relative path (`files/…`), not the resolved absolute path.

**VESSEL-016 — Resize grip.**
A 16×16 grip at the card's bottom-right (2 px right and bottom margin), NW-SE resize cursor, element opacity 0.55. It is
drawn as a filled right triangle with path `M16,0 L16,16 L0,16 Z` in the readable foreground at opacity 0.8, so the
effective opacity is about 0.44.

**VESSEL-017 — Drag to move.**
Left-button press on a card (anywhere except the grip) starts a move and captures the mouse. While the button is held:
`X = max(0, originX + (mouseX − startMouseX))` and `Y = max(0, originY + (mouseY − startMouseY))`, in canvas coordinates.
The card follows live and the model `X`/`Y` update live. There is **no upper clamp** and **no snapping**.
On release: release capture, recompute the canvas size, and **save immediately**. A plain click with no movement also
triggers a save, which is harmless. Z-order does not change while dragging (no bring-to-front).

**VESSEL-018 — Resize.**
Dragging the grip changes `Width = max(90, Width + dx)` and `Height = max(64, Height + dy)` live. There is **no maximum**
when resizing by drag. The editor caps at 900×700, VESSEL-051. On drag completed: recompute the canvas size, **save
immediately**, and rebuild all cards, which re-evaluates the icon size.

**VESSEL-019 — Double-click opens.**
A double left-click (`ClickCount == 2`) on a card, outside the grip, opens its target (VESSEL-025). The first click of the
double-click has already begun and ended a zero-distance drag, so a save happened. That is harmless.

**VESSEL-020 — Card context menu (right-click).**
Items in order: `Open`, `Edit...`, `Duplicate`, separator, `Delete`.

**VESSEL-021 — Add a card (`+ Quick card`).**
Create an unsaved `QuickCard` with defaults: `Title ""`, `Target ""`, `IsLink/LinkInPlace/IsFolder false`,
`Icon "⚓"` (U+2693), `Color "#FF1E88E5"`, `Width 180`, `Height 120`, and a cascade position:
`n = current card count` gives `X = Y = 24 + (n mod 6) × 28`, so the sequence is 24, 52, 80, 108, 136, 164, then 24 again.
The editor opens modally, owned by the main window. Only on **OK** is the card appended to `Vessel.QuickCards`, saved
immediately and the canvas rebuilt. Cancel discards it, but see VESSEL-055.

**VESSEL-022 — Edit a card (`Edit...`).**
Take a snapshot (`Clone()`, all fields including Id) and open the editor on the **live** card object; edits apply to it
while the dialog is open. OK → save immediately. Cancel or window close → restore every field from the snapshot
(`CopyFrom`, all fields except Id). Rebuild the canvas either way.

**VESSEL-023 — Duplicate.**
Clone the card, give it a **new Id**, offset it by `X+24, Y+24`, append it to the end of the list (so it is drawn on top),
save immediately and rebuild. An imported-copy duplicate points at the **same** `files/…` file. The file is shared, not
copied.

**VESSEL-024 — Delete (with confirmation).**
MessageBox, caption `Confirm`, body `Delete quick card '{Title, or Icon if Title is blank/whitespace}'?`,
buttons Yes/No, question icon. Yes → remove the card, save immediately and rebuild. The imported file (if any) is
**not** deleted from `files/`, deliberately (it may be shared, see PROGRESS "Batch delete"). There is no undo.
Global Ctrl+Z restores the last *trashed hierarchy item*, not a quick card.

**VESSEL-025 — Open a card's target.**
1. If `Target` is blank or whitespace → MessageBox caption `Quick card`, body
   `This card has no target yet. Right-click ▸ Edit to point it at a file, folder, or web link.`, OK, information icon. Stop.
2. `path = (IsLink || LinkInPlace) ? Target : DataStore.ResolveFilePath(Target)`. Imported copies resolve
   `files/…` against the app data folder. Rooted paths and URLs pass through unchanged.
3. If **not** `IsLink` and `path` is neither an existing file nor an existing directory → MessageBox caption
   `Open failed`, body `Not found:\n{path}`, OK, warning icon. Stop.
4. Shell-open `path` (`Process.Start` with `UseShellExecute=true`): a URL opens in the default browser, a file in its default
   application, a folder in Explorer.
5. Any exception → MessageBox caption `Open failed`, body = exception message, OK, error icon.
Web links are **not** existence-checked. A malformed URL fails at step 4 and shows the OS error message.

**VESSEL-026 — Persistence.**
Every structural change is saved immediately (§1.4). The layout is stored per vessel: order, X, Y, Width, Height.

**VESSEL-027 — Ordering and z-order.**
Cards are drawn in `Vessel.QuickCards` list order, so later cards are on top. Adding and duplicating append. There is no
reordering UI.

**VESSEL-028 — No keyboard interaction and no multi-select.**
The Windows panel has no keyboard shortcuts, no focus visuals, no selection state and no multi-selection. All interaction
is by mouse. The Mac may add keyboard access as an enhancement (§6.3), without removing any mouse behaviour.

---

### C. Quick Card editor (`QuickCardEditorWindow`)

**VESSEL-040 — Window.**
Modal dialog titled `Quick card`, 660×600, not resizable, centred on its owner, app icon. There are two columns: a left
form (`*`) and, after a 14 px gap, a 210 px right column (preview). Bottom right: `Cancel` (min width 90,
**IsCancel**, so Esc) and `OK` (min width 110, accent style, **IsDefault**, so Enter).

**VESSEL-041 — Title field.**
Label `Title` (bold) with a text box. Every keystroke writes `card.Title` live and refreshes the preview. The title box
has keyboard focus when the window loads.

**VESSEL-042 — Target display.**
Label `Target` (bold). A **read-only** text box shows `Target`, or `(none — pick a file, folder, or web link)` when blank.
To its right is a muted type label: empty when there is no target, else `Web link` / `Folder (live)` / `File (live)` /
`Imported copy`, using the same precedence as VESSEL-015.

**VESSEL-043 — `🔗 Link file (in place)`.**
Tooltip: `Reference a file at its original location (e.g. on a network drive) — no copy.`
Opens a file-open dialog titled `Link a file in place (no copy)` (no filter). On OK: `Target = chosen absolute path`
(may be a UNC path), `IsLink=false, LinkInPlace=true, IsFolder=false`. Title auto-fill applies (VESSEL-047). The target UI
and preview refresh.

**VESSEL-044 — `📄 Import a copy`.**
Tooltip: `Copy the file into the app data folder.`
Opens a file-open dialog titled `Import a copy of a file`. On OK: **immediately** copy the file via `DataStore.ImportFile`
into `<AppFolder>/files/{guid:N}_{originalFileName}` (overwrite). `Target = "files/{guid:N}_{originalFileName}"` (forward
slash, relative). `IsLink=false, LinkInPlace=false, IsFolder=false`. Title auto-fill applies. If the copy throws →
MessageBox caption `Import failed`, body = exception message, error icon. The target is unchanged.

**VESSEL-045 — `📁 Link folder`.**
Tooltip: `Reference a folder (opens in Explorer).`
Opens a folder picker with description `Link a folder (opens in Explorer)`. On OK: `Target = selected folder path`,
`IsLink=false, LinkInPlace=true, IsFolder=true`. Title auto-fill takes the folder's own name (last path component). For a
drive root such as `C:\`, the name is the root itself.

**VESSEL-046 — `🌐 Web link...`.**
No tooltip. Opens the generic prompt (VESSEL-046a) with window title `Web link`, prompt `URL:`, initial text `https://`
(pre-selected). OK with non-blank text → `Target = text.Trim()`, `IsLink=true, LinkInPlace=false, IsFolder=false`. The title
is **not** auto-filled for web links. Cancel or blank → no change. No URL validation is done, so `https://` alone is accepted.

**VESSEL-046a — Prompt dialog.**
440×170, non-resizable. The bold title (14) repeats the window title, followed by the prompt label and a single-line text box
that has focus with all text selected. Buttons: `Cancel` (80) and `OK` (80, accent, default, Enter). Cancel is **not**
`IsCancel` in the Windows XAML, so Esc does nothing there. On the Mac, Esc should cancel (a native sheet convention); this
does not change data.

**VESSEL-047 — Title auto-fill.**
Only when the current Title is blank or whitespace: Link file / Import copy → file name **without extension**. Link folder →
folder name. Web link → never. The title box text is updated without re-triggering the change handler.

**VESSEL-048 — Icon picker.**
Label `Icon` (bold). A bordered box (radius 4, height 116, vertical scroll) holds a wrap of **50 icon buttons**
(40×36, glyph font size 20, 2 px margin, tooltip = friendly name). The list and order are in §4.6. Clicking a button sets
`card.Icon = glyph` and refreshes the preview. The current icon is **not** highlighted in the Windows UI. The Mac may
highlight it, as an enhancement.

**VESSEL-049 — Colour palette.**
Label `Colour` (bold). A wrap of **20 swatches** (28×28, 2 px margin, 1 px `BorderB` border, background = colour,
tooltip = hex string). Clicking one sets `card.Color = hex` (the exact palette string, e.g. `#FF1E88E5`) and refreshes the
preview. There is no selection highlight in Windows.

**VESSEL-050 — `Custom colour...`.**
Opens the system colour dialog (full custom panel open), initialised to the current colour. On OK:
`card.Color = "#FF" + RR + GG + BB` (upper-case hex, **alpha forced to FF**).

**VESSEL-051 — Width / Height fields.**
Two 64 px text boxes labelled `Width` and `Height`, initialised to `(int)Width` / `(int)Height` (truncated). On every text
change: if the text parses as a number (current culture) **and** is ≥ 80 → `Width = min(900, value)`. If it parses and is
≥ 60 → `Height = min(700, value)`. Anything else, including values below the minimum, empty or non-numeric text, is
**silently ignored** and the previous value is kept. There is no error UI. The preview size does **not** change with these
fields. Note the drag minimums differ: 90×64 (VESSEL-018).

**VESSEL-052 — Live preview.**
Label `Preview` (bold). A fixed 190×130 rounded card (radius 10) with the current colour as background, the icon at font 40,
and the title in bold 14, wrapped, centred, margin 6,6,6,0, shown as `(untitled)` when blank. Colours are the readable
foreground. It updates on title, icon, colour and target changes. There is no border on the preview.

**VESSEL-053 — Tip.**
Muted wrapped text under the preview: `Tip: on the vessel screen, drag a card to move it and drag its bottom-right corner to resize.`

**VESSEL-054 — OK / Cancel semantics.**
OK → dialog result true. Cancel, Esc or closing the window → false. The editor itself never saves. The caller decides
(VESSEL-021/022).

**VESSEL-055 — Orphan on cancel (quirk, replicate).**
"Import a copy" copies the file **at click time**. If the dialog is then cancelled, or another target is chosen afterwards, the
copied file stays in `files/` unreferenced. There is no cleanup. Keep this behaviour. Do not add a sweep: files may be shared
across cards, templates and containers.

---

### D. Work Orders panel (`ShipJobsPanel`, tab "Work Orders")

**VESSEL-100 — Layout (four rows).**
1. **Toolbar** (wrapping row), left to right:
   * `Import Shippalm (.xlsx)...` (accent). Tooltip `Import a Shippalm Work Order List export into THIS ship. Jobs are keyed by job number (No.).`
   * `Export (.xlsx)...`. Tooltip `Export THIS ship's work orders (including notify & completion choices) to an .xlsx that can be re-imported.` (the tooltip over-promises, see §9 Q1)
   * Search box, 180 wide. Intended placeholder `Search job no / title / function...`. It is stored in `Tag` and **never
     rendered** on Windows. Use it as the Mac placeholder.
   * Status combo, 130. Tooltip `Filter by Work Order Status.`
   * Category combo, 120. Tooltip `Filter by Work Order Category.`
   * Rank combo, 130. Tooltip `Filter by Responsible rank.`
   * Completion combo, 130. Tooltip `Show all, only active (not completed), or only completed work orders.`
   * Toggle button `Due/overdue only`. Tooltip `Show only jobs that are overdue or due within 90 days.`
   * Toggle button `Notify on only`. Tooltip `Show only jobs set to raise notifications.`
   * `✓ Mark completed`. Tooltip `Mark the selected work orders (or all shown, if none selected) as completed.`
   * `↺ Mark active`. Tooltip `Clear the completed flag on the selected work orders (or all shown, if none selected).`
   * `🗑 Delete`. Tooltip `Delete the selected work orders from this ship (permanent).`
   * `🔔 shown ON`. Tooltip `Turn ON notifications for every job currently shown.`
   * `🔕 shown OFF`. Tooltip `Turn OFF notifications for every job currently shown.`
2. **Notifications bar** (`PanelAlt` background, radius 4, padding 10,6, a **3 px coloured bottom border**): the checkbox
   `🔔 Notifications for this ship` (tooltip `Master on/off switch for THIS ship's work-order notifications.`) and the
   wrapped status text. See VESSEL-120.
3. **Summary box** (`PanelAlt`, 1 px border, radius 4): wrapped text. See VESSEL-119. XAML default text
   `No work orders imported yet for this ship.`
4. **Jobs list**: multi-select (Shift/Ctrl extended selection), virtualised with recycling, horizontal scroll, clickable
   column headers, context menu. See VESSEL-109/118.

**VESSEL-101 — Import Shippalm.**
File-open dialog titled `Import Shippalm Work Order List for {vessel.Name}`, filter
`Excel workbook (*.xlsx)|*.xlsx|All files (*.*)|*.*`. On OK:
* wait cursor; summary text becomes `Reading Shippalm export… (large files take a few seconds)`;
* the file is parsed **off the UI thread** (`ShippalmReader.Read`, §3.4.1);
* upsert per VESSEL-102; then `Save()` (immediate); repopulate the filter combos; rebuild the view;
* status hint `Imported {parsedCount} work orders for {vessel.Name} ({added} new, {updated} updated).`
  `parsedCount` counts every parsed row, including in-file duplicates.
* On any exception (parse, IO or save): MessageBox caption `Import failed`, body
  `Could not import the Shippalm file:\n\n{exception message}`, error icon. Then rebuild the view, which restores the summary text.
* The wait cursor is always cleared.
* **No activity-log entry** is written for Shippalm imports. Compare Ports, VESSEL-204.

**VESSEL-102 — Upsert rules (primary key `JobNo`, case-insensitive).**
* Build `byNo` from the existing jobs: group by `JobNo` (OrdinalIgnoreCase), keep the **first** of each group.
* For each parsed job, in file order:
  * **exists** → copy the existing `Notify`, `IsCompleted` and `CompletedDate` onto the parsed job, then
    `existing.CopyFrom(parsed)`. That updates **every** field in place, including `JobNo` casing, `ImportedAt` and all
    Shippalm fields. The per-job user choices survive. `updated++`.
  * **new** → append to `Vessel.Jobs` and add to `byNo`. `Notify` comes from the file's `Notify` column if present
    (AA's own export), else false. `IsCompleted=false`, `CompletedDate=""`. `added++`.
* In-file duplicates: the 2nd occurrence updates the 1st (counted as `updated`).
* Jobs **absent** from the new file are **kept** (no pruning).
* Re-importing an AA export into the **same** ship does *not* apply the file's Notify values to existing jobs. The existing
  choice wins. Into a **different** ship, new jobs take the file's Notify.
* Complexity is O(n) through the dictionary and in-place copy. PROGRESS measured about 3 ms for 2524 jobs; keep it linear.

**VESSEL-103 — Export.**
* If the ship has 0 jobs → MessageBox caption `Export`, body `No work orders to export for this ship.`, info icon. Stop.
* Save dialog titled `Export work orders for {vessel.Name}`, filter `Excel workbook (*.xlsx)|*.xlsx`, default file name
  `WorkOrders-{safeName}.xlsx`, where `safeName` = vessel name (or `vessel` if null) with every Windows-invalid file-name
  character replaced by `_` (§3.6). Default extension `.xlsx`, added automatically.
* Write **all** jobs of the ship, **not** the filtered view, in collection order, via `ShippalmReader.Write` (§3.4.2, §4.4).
  Wait cursor during the write.
* On error: MessageBox caption `Export failed`, body `Could not export:\n\n{message}`, error icon. Stop.
* Success: status hint `Exported {count} work orders for {vessel.Name}.`, then shell-open the file (e.g. Excel). A failure
  to open is ignored silently.

**VESSEL-104 — Search (debounced 200 ms).**
Each text change restarts a 200 ms one-shot timer, and the view rebuilds when it fires. The trimmed query is matched
**case-insensitive substring** against `JobNo`, `Title`, `FunctionDescription` **and** `ResponsibleRank`. The intended
placeholder mentions only three of these, but rank is also searched. An empty query matches all.

**VESSEL-105 — Status / Category / Rank filters.**
Each combo = first item `(all statuses)` / `(all categories)` / `(all ranks)`, followed by the **distinct non-blank** values of
`Status` / `Category` / `ResponsibleRank` across the vessel's jobs. Distinctness is case-insensitive and keeps the first-seen
casing. Values are sorted OrdinalIgnoreCase. Index 0 = no filter. Otherwise keep jobs whose field **equals** the selected value
case-insensitively. Combos are repopulated on `Load`, after import and after delete. Repopulation keeps the previous selection
if the new list contains the identical string (case-sensitive), else selects index 0. Repopulation must not trigger an extra
rebuild (`_populating` guard).

**VESSEL-106 — Completion filter.**
Items `All`, `Active only`, `Completed only` (created once, default `All`). `Active only` keeps `!IsCompleted`.
`Completed only` keeps `IsCompleted`.

**VESSEL-107 — `Due/overdue only` toggle.**
Keeps jobs with `!IsCompleted` **and** a parseable due date **and** `daysUntilDue ≤ 90` (`DueSoonDays = 90`). Overdue jobs
(negative days) are included. Jobs without a valid due date are excluded.

**VESSEL-108 — `Notify on only` toggle.**
Keeps jobs with `Notify == true`, **including completed** ones.

Filters combine with AND in this order: search → status → category → rank → completion → due-soon → notify.
Sorting comes last (VESSEL-111).

**VESSEL-109 — Columns (header text, width, content).**
| Header | Width | Content |
|---|---|---|
| `Done` | 48 | centred checkbox bound two-way to `IsCompleted`. Tooltip `Mark this work order completed. Completed jobs are excluded from due/overdue counts and notifications.` |
| `Notify` | 52 | centred checkbox bound two-way to `Notify`. Tooltip `Raise a due/overdue notification for this recurring job.` |
| `Job No.` | 110 | `JobNo` |
| `Title` | 260 | `Title`, wrapped, **struck through when `IsCompleted`** |
| `Due` | 150 | due text (VESSEL-110), **bold**, coloured, wrapped |
| `Interval` | 80 | `Interval` |
| `Status` | 90 | `Status` |
| `Due Status` | 90 | `DueStatus` |
| `Category` | 80 | `Category` |
| `Responsible` | 130 | `ResponsibleRank` |
| `Function` | 220 | `FunctionDescription`, wrapped |
`WorkPlanNo`, `ClassCode`, `FunctionNo`, `FinishedDate`, `LastDoneDate`, `OverdueDays` and `ImportedAt` are stored and exported
but **not shown**.

**VESSEL-110 — Due cell text and colour** (`DueInfo`, today = local date):
| Condition (first match wins) | Text | Colour |
|---|---|---|
| `IsCompleted` and `CompletedDate` blank | `✓ completed` | Green |
| `IsCompleted` | `✓ completed {CompletedDate}` | Green |
| due date not parseable | `{DueDate}` raw (or empty) | Gray |
| d < 0 | `OVERDUE {−d}d  ({DueDate})` (two spaces) | Red |
| d == 0 | `DUE TODAY  ({DueDate})` | Red |
| d ≤ 30 | `in {d}d  ({DueDate})` | Orange |
| d ≤ 90 | `in {d}d  ({DueDate})` | Amber |
| else | `{DueDate}  (in {d}d)` | Green |
Colours are fixed in both themes: Red `#D45050`, Orange `#E8890C`, Amber `#C9A227`, Green `#2E9E5B`, Gray `#8A8A8A`.

**VESSEL-111 — Column sorting.**
Clicking a header whose text is non-empty: the same column toggles the direction. A different column becomes the sort column,
**ascending**. Default: column `Due`, ascending. Keys:
* `Job No.`, `Title`, `Interval`, `Status`, `Due Status`, `Category`, `Responsible`, `Function` → the field string, OrdinalIgnoreCase.
* `Done` → `IsCompleted` (false < true). `Notify` → `Notify` (false < true).
* `Due` (and any unrecognised header) → first `IsCompleted` (false < true), then `daysUntilDue ?? Int.max`. Descending reverses
  **both** keys: completed first, then no-date first, then furthest due.
* **Always** a final tiebreak `JobNo` **ascending** OrdinalIgnoreCase, regardless of direction. The sort is stable.

**VESSEL-112 — `Done` checkbox (per row).**
Toggling flips `IsCompleted`. `CompletedDate` becomes today `yyyy-MM-dd` (local) when checked and `""` when unchecked.
`MarkDirty()` (debounced save). The **whole view rebuilds**, because strike-through, due colour, counts, sort and filters all
depend on completion. The row may move or vanish and the selection is lost.

**VESSEL-113 — `Notify` checkbox (per row).**
Toggling flips `Notify` and calls `MarkDirty()` (**debounced**, so bulk ticking does not rewrite the file per click). If
`Notify on only` is active → full rebuild, since membership changed. Otherwise update only the summary and the notifications
bar (no list rebuild, selection kept).

**VESSEL-114 — Mark completed / Mark active.**
Available as toolbar buttons and in the context menu. Target = **selected rows, or every shown row if nothing is selected**.
There is **no confirmation**. With 0 targets: status hint
`No work orders to update — select rows, or clear filters so some are shown.` Otherwise, for every target:
`IsCompleted = done`, `CompletedDate = done ? today "yyyy-MM-dd" : ""`. Re-marking an already-completed job re-stamps its date
to today. Then `Save()`, rebuild, and status hint `Marked {n} work order(s) completed.` / `Marked {n} work order(s) active.`

**VESSEL-115 — Context `🔔 Notify ON` / `🔕 Notify OFF`.**
Target = selected rows, or all shown if none are selected. With 0 targets, nothing happens (no hint). Set `Notify`, `Save()`,
rebuild, and status hint `Notifications turned ON for {n} work order(s).` / `… OFF …`.

**VESSEL-116 — Toolbar `🔔 shown ON` / `🔕 shown OFF`.**
Target = **every shown row, ignoring selection**. With 0 shown, nothing happens. Set `Notify`, `Save()`, rebuild, and status
hint `Notifications turned ON for {n} shown job(s).` / `… OFF …`.

**VESSEL-117 — Delete work orders.**
Toolbar or context. Target = **selected rows only**. With 0 selected: status hint `Select one or more work orders to delete.`
Otherwise MessageBox caption `Delete work orders`, body
`Delete {n} work order(s) from {vessel.Name}? This is permanent (re-import to restore).`, Yes/No, warning icon. Yes → remove
them, `Save()`, repopulate the combos, rebuild, and status hint `Deleted {n} work order(s) from {vessel.Name}.` The Trash is not
used and there is no undo.

**VESSEL-118 — List context menu.**
`✓ Mark completed`, `↺ Mark active`, separator, `🔔 Notify ON`, `🔕 Notify OFF`, separator, `🗑 Delete`. Right-clicking a row
selects it first (standard WPF ListViewItem behaviour). Right-clicking empty space keeps the current selection. If none, the
"selected-or-shown" actions apply to every shown row.

**VESSEL-119 — Summary line.**
With 0 jobs: `No work orders imported yet for this ship. Click “Import Shippalm (.xlsx)...”.` With no vessel: `No ship selected.`
Otherwise two lines:
```
⚙ {total} work orders   ·   ⚠ {overdue} overdue   ·   {due30} due ≤30d   ·   {due90} due ≤90d   ·   ✓ {completed} completed   ·   🔔 {notify} notify-on   ·   showing {shown}
By category: {cat1} {n1}   {cat2} {n2}   …(top 5)
```
(separators are three spaces, `·`, three spaces; the category items are joined by three spaces.) Definitions (over **all** jobs of
the ship):
* `overdue` = !completed ∧ d < 0.
* `due30` = !completed ∧ 0 ≤ d ≤ 30.
* `due90` = !completed ∧ 0 ≤ d ≤ 90 (**includes** due30).
* `completed` = IsCompleted.
* `notify` = Notify (**includes completed**).
* `shown` = rows currently in the list.
* Categories: group by `Category` (**case-sensitive**, blank → `(none)`), order by count descending (stable, so ties keep
  first-appearance order), take 5, format `{key} {count}`.

**VESSEL-120 — Notifications bar and per-ship master switch.**
The checkbox reflects `Vessel.NotificationsEnabled` (default **true**). Clicking it sets the flag, **saves immediately**
(MarkDirty + FlushIfDirty) and refreshes the bar. The bar is recomputed after every view rebuild. Rules (today = local date):
1. Switch **off** → border Gray, text Gray: `Off — turn on to track this ship's due / overdue work orders here.`
2. `flagged` = jobs with `Notify ∧ !IsCompleted`. If empty → border Gray, text in theme `Fg`:
   `On — no active flagged jobs. Tick the Notify box (or “🔔 shown ON”) on the recurring jobs you want tracked.`
3. `overdue` = flagged with d < 0, sorted by d ascending (most overdue first). `dueSoon` = flagged with 0 ≤ d ≤ 30, sorted by d
   ascending. `attention = overdue ++ dueSoon`. If attention is empty → border Green, text Green:
   `On — {flagged.Count} flagged job(s), all clear (none due within 30 days).`
4. Otherwise border and text are **Red** if any overdue, else **Orange**:
   `⚠ {attention.Count} flagged work order(s) need attention — {overdue.Count} overdue, {dueSoon.Count} due ≤30d:  ` (two
   trailing spaces), then the first 4 attention items joined by `",   "` (comma + three spaces), each `{JobNo} (overdue {−d}d)`
   or `{JobNo} (in {d}d)` (d = 0 → `(in 0d)`), then `   …` (three spaces + ellipsis) if more than 4.
Filters do not affect the bar. It always considers all of the ship's jobs.

**VESSEL-121 — Scope of "notifications".**
Work-order "notifications" are **only this in-panel bar**. Shippalm jobs were deliberately *removed* from the global floating
due-dates window. They also do not appear in the tray reminder balloon or the once-a-day digest. The master switch affects only
this bar. **Do not** post system notifications for work orders on the Mac unless a later decision adds it (§9 Q7).

**VESSEL-122 — Row objects and selection.**
Every rebuild recreates the row wrappers (`JobRow{Job, DueInfo, DueBrush}`), so the selection is lost on any rebuild. The Mac may
preserve selection by identity (JobNo) as an improvement. That is harmless.

**VESSEL-123 — Performance requirements.**
Ships carry about 2,500+ jobs. The list must be virtualised. Search must be debounced (200 ms). Import parsing must run off the
main thread with a busy indicator. The upsert must be linear. Notify and Done toggles must use the debounced save. The data file
is written compact (no indentation). This is a cross-cutting requirement, but it exists *because of* this subsystem: about 5×
faster saves with 2,524 jobs.

---

### E. Per-vessel Ports panel (`PortsPanel`, tab "Ports")

**VESSEL-200 — Layout.**
1. **Toolbar** (wrap):
   * `Import ports (.xlsx)...` (accent). Tooltip `Import a ports-of-call list for THIS vessel. Both the 'Last Ports of Call' and the 'Port of Call List' layouts are auto-detected.`
   * `Export (.xlsx)...`. Tooltip `Export this vessel's ports of call to Excel.`
   * Search box, 200 wide. Intended placeholder `Search port / country / UN-LOCODE...`, which is not rendered on Windows.
   * `🗑 Delete`. Tooltip `Delete the selected port calls (also removes their visit from the ports database).`
2. **Summary box** (`PanelAlt`, border, radius 4). XAML default `No ports imported yet for this vessel.` See VESSEL-210.
3. **Calls list**: extended multi-select, virtualised, horizontal scroll, clickable headers. **No context menu. No keyboard Delete.**

**VESSEL-201 — Import ports (auto-detect).**
File-open dialog titled `Import ports of call for {vessel.Name}`, filter `Excel workbook (*.xlsx)|*.xlsx|All files (*.*)|*.*`.
Wait cursor. Parse **off the UI thread** with `PortCallReader.Read` (§3.3). Clear the cursor. Different-vessel check (VESSEL-202).
Then `PortsService.Apply` (§3.2.1), the activity-log entry (VESSEL-204), `Save()`, rebuild, and status hint:
`Imported {calls.Count} port(s) for {vessel.Name} ({added} new, {updated} updated) — {format}. {newVisits} new visit(s) in the ports database.`
`{format}` is `Last Ports of Call (2 years)` or `Port of Call List (last 10 ports)`.
On exception: MessageBox caption `Import failed`, body `Could not import the ports file:\n\n{message}`, error icon (reader error
texts in §3.3.8). The global Ports tab is **not** refreshed immediately. It refreshes when selected.

**VESSEL-202 — Different-vessel confirmation.**
If the file names a vessel (layout B header `Vessel Name`) and that name ≠ `vessel.Name` (case-insensitive), show MessageBox
caption `Different vessel`, body
`This file lists vessel "{fileVessel}", but you're importing into "{vessel.Name}".\n\nImport these {n} port call(s) for {vessel.Name} anyway?`
(straight double quotes), Yes/No, question icon. No → abort silently, with no change. Layout A files carry no vessel name and are
never questioned.

**VESSEL-203 — Merge semantics.**
Per vessel, calls are upserted by `Key = lower(PortName) + "@" + ArrivalDate`. The merge (`CopyInto`) always takes the incoming
`PortName` and `ImportedAt`, and takes each optional field **only if the incoming value is non-empty**. Importing both layouts
therefore enriches one call: country from A, UN/LOCODE, times and facility from B. Each call also upserts a **port** and a
**visit** in the global database. Full algorithm in §3.2.1.

**VESSEL-204 — Activity-log entry.**
Each successful ports import appends an activity log entry: `Action "Added"`, `Kind "Ports import"`,
`Name "{added} new, {updated} updated"`, `Detail "{vessel.Name} · {format}"`, `TimestampUtc = UtcNow` (§4.3). The log is capped
at 10,000 entries, oldest dropped.

**VESSEL-205 — Export ports.**
* 0 calls → MessageBox caption `Export`, body `No ports to export for this vessel.`, info icon.
* Save dialog titled `Export ports of call`, filter `Excel workbook (*.xlsx)|*.xlsx`, file name `Ports-{safeName}.xlsx`.
* Write via `PortsService.Export` (§3.2.3, §4.5). Success hint `Exported {count} port(s) for {vessel.Name}.` Then shell-open the
  file, ignoring errors.
* Error → caption `Export failed`, body `Could not export:\n\n{message}`, error icon.
* The export is **not** re-importable as a faithful round trip. It re-imports as layout B with only port names, see VESSEL-212.

**VESSEL-206 — Search (not debounced).**
Trimmed query, case-insensitive substring on `PortName`, `Country` or `UnLocode`. The list rebuilds on each keystroke.

**VESSEL-207 — Columns.**
| Header | Width | Content |
|---|---|---|
| `Port` | 150 | `PortName` |
| `Country` | 120 | `Country` |
| `UN/LOCODE` | 90 | `UnLocode` |
| `Arrival` | 130 | `"{ArrivalDate} {ArrivalTime}".Trim()` |
| `Departure` | 130 | `"{DepartureDate} {DepartureTime}".Trim()` |
| `Sec P` | 55 | `SecurityLevelPort` |
| `Sec V` | 55 | `SecurityLevelVessel` |
| `SSP` | 50 | `SspFollowed` |
| `Port Facility` | 180 | `PortFacility`, wrapped |
| `Special measures` | 200 | `SpecialMeasures`, wrapped |
`PfNo` and `ImportedAt` are not shown.

**VESSEL-208 — Sorting.**
Default: `Arrival`, **descending** (most recent first). Header click: the same column toggles, a different column becomes
ascending. Keys:
* `Port`/`Country`/`UN/LOCODE`/`Sec P`/`Sec V`/`SSP`/`Port Facility` → the field, OrdinalIgnoreCase.
* `Departure` → the string `DepartureDate + " " + DepartureTime`, OrdinalIgnoreCase.
* `Arrival` **and any other header, including `Special measures`** → `ArrivalValue ?? DateTime.MinValue`, then `ArrivalTime`
  string.
There is no further tiebreak (stable sort, collection order). Quirk: clicking `Special measures` sorts by arrival but still
toggles the direction and stores `Special measures` as the sort column. Replicate.

**VESSEL-209 — Delete port calls.**
Target = selected rows only. With 0: status hint `Select one or more ports to delete.` Otherwise MessageBox caption `Delete ports`,
body `Delete {n} port call(s) from {vessel.Name}? Their visit is also removed from the ports database.`, Yes/No, warning icon. Yes →
`PortsService.RemoveCall` for each (§3.2.2): this removes the call, removes the matching visit in **every** port, and **prunes every
port left with zero visits**. Then `Save()`, rebuild, and status hint `Deleted {n} port call(s).` There is no undo.

**VESSEL-210 — Summary line.**
With 0 calls: `No ports imported yet for this vessel. Click “Import ports (.xlsx)...”.` With no vessel: `No vessel selected.`
Otherwise: `⚓ {total} port call(s)` + (`  ·  showing {shown}` if filtered) + `  ·  latest: {DisplayName} ({ArrivalDate})`. "Latest"
is the call with the maximum `ArrivalValue`, with unparseable dates treated as the minimum and ties going to the first in collection
order. `DisplayName = Country ? "{PortName}, {Country}" : PortName`. Separators are two spaces, `·`, two spaces.

**VESSEL-211 — Other behaviour.**
Imo and CallSign are parsed from layout B but **never stored or shown**. Parse them anyway (for parity and possible future use),
but do not persist them.

**VESSEL-212 — Export is lossy on re-import (quirk, replicate).**
Re-importing an AA ports export: header `UN/LOCODE` makes it detect as layout B. There is no `UN locator` row, so the `un/locode`
header row (row 1) is used as the sub-header. The category row would be row 0, so every category is empty and no column maps except
the fallback port-name column = first used column (`Port`). The result is calls with only `PortName` set (empty dates), keyed
`"{name}@"`, which creates new date-less calls and visits. See §9 Q2.

---

### F. Global Ports Database (`PortsPage`, main tab "Ports")

**VESSEL-250 — Layout.**
Two panes with a draggable 6 px splitter. The left pane starts at 320 px wide.
* **Left** (bordered, radius 4):
  * header strip (`PanelAlt`, bottom border): `⚓ Ports Database` (bold, 15, accent);
  * muted wrapped description:
    `Every port any vessel has called, built from the ports imported on each vessel's Ports tab. Select a port to see which vessels called and when.`;
  * search box (intended placeholder `Search port / country / UN-LOCODE...`, not rendered on Windows);
  * port list (no horizontal scroll, single selection);
  * muted wrapped status text at the bottom.
* **Right** (bordered, radius 4, 10 px margin): a header (17, bold, wrapped) and a visits list.

**VESSEL-251 — Port list.**
Each row: `Port.Display` (semi-bold, wrapped) on the left, and on the right `{Visits.Count} visits` (muted, size 11). There is **no
singular form**: one visit renders `1 visits` (§9 Q8). `Display = (UnLocode ? "{Name} ({UnLocode})" : Name) + (Country ? ", {Country}" : "")`.
Filter: trimmed query, case-insensitive substring on `Name`, `Country` or `UnLocode`. Order: `Name` OrdinalIgnoreCase (stable). The
search is not debounced.

**VESSEL-252 — Status text.**
With 0 ports in the DB: `No ports yet. Import a ports-of-call list on any vessel's “Ports” tab.` Otherwise
`{P} port(s)  ·  {V} visit(s)`, plus `  ·  showing {n}` when the filtered count ≠ P (totals over the whole DB).

**VESSEL-253 — Visits pane.**
With no selection: header `Select a port to see the vessels that called.` and an empty list. With a selection: header
`⚓ {Display}   —   {n} visit(s)` (three spaces around the em dash). Columns: `Vessel` (220, wrapped `VesselName`), `Arrival` (140,
`ArrivalDisplay`), `Departure` (140), `Imported` (140, raw `ImportedAt`). Order: `ArrivalValue` descending (unparseable = min),
then `ArrivalTime` descending. The list is virtualised. **Not sortable, not editable, no context menu.** `VesselName` is the name
at import time and does not follow renames.

**VESSEL-254 — Selection retention.**
`Refresh()` remembers the selected port Id and re-selects it if it is still in the filtered list. Otherwise nothing is selected
and the header resets.

**VESSEL-255 — Refresh triggers.**
The DB view refreshes on data (re)load (`Init`), on main-tab selection and on each search keystroke. It does **not** live-update
while visible if a vessel import happens elsewhere, which on Windows is impossible anyway because the vessel tabs are in a different
main tab. Mac: if the Ports DB is visible in another window at the same time, observe the model and refresh (§6.5).

**VESSEL-256 — Read-only.**
There are no edit, delete, merge or rename operations on the DB tab. The DB changes only through vessel port imports (Apply) and
vessel port-call deletions (RemoveCall).

---

### G. Cross-cutting behaviour

**VESSEL-280 — Vessel delete and restore.**
Deleting a vessel soft-deletes it to the Trash with its full JSON payload, including `QuickCards`, `Jobs`,
`NotificationsEnabled` and `PortCalls`. Restore brings them back intact. The global `Ports[].Visits` are **not** touched by vessel
deletion, restore or permanent removal, so visits of a deleted vessel remain in the DB. Replicate.

**VESSEL-281 — Vessel rename.**
Existing `PortVisit.VesselName` values keep the old name. `Apply` still matches a visit by `VesselId` (or name). **Quirk:**
`RemoveCall` matches a visit by `VisitKey`, which is built from the vessel's *current* name, so after a rename, deleting a call
no longer removes its old visit. Replicate (§9 Q3).

**VESSEL-282 — Portability.**
Quick-card imported copies (`files/…`) travel in full `.aaz`/`.zip` bundles and not in text-only exports or Flash Sync. A missing file
opens as "Not found". In-place links (absolute Windows paths, UNC paths) travel verbatim and resolve only on machines that can see
them. `DataStore.NormalizeFilePaths` / `MigrateLegacyAbsolutePaths` only walk *containers*, so they **never rewrite QuickCard.Target**.

**VESSEL-283 — Not covered by global search or change preview.**
Global search (`SearchService`) and the import/change-preview diff (`DataDiff`) walk hierarchy items only. Quick cards, jobs, port
calls and the Ports DB are not searched and not itemised in change previews. Match this on the Mac unless those specs extend it.

**VESSEL-284 — Flash Sync.**
`Vessels` is an Id-keyed top-level collection, so a vessel with any quick-card, job or port change travels **whole**. `Ports` is an
Id-keyed top-level collection, so each changed port travels whole, with all its visits. Nothing here is excluded from sync.
Collection order matters for `Apply`'s first-match port lookup (§3.2.1), so Flash Sync `Order` must be honoured for `Ports`.

**VESSEL-285 — Global Ctrl+Z does not undo these deletions.**
Ctrl+Z outside text input restores the last *trashed hierarchy item*. Quick-card, job and port-call deletions are permanent. The Mac
must not suggest otherwise, for example by an Edit ▸ Undo item that appears to undo a quick-card delete but actually restores some
other item.

---

## 3. LOGIC & ALGORITHMS

All "today" and "now" values are **local time**. All string comparisons marked OIC are .NET `OrdinalIgnoreCase` (upper-case
invariant, then UTF-16 code-unit ordinal compare). Swift equivalent: `a.uppercased()` compared by `.utf16` lexicographically. Do
**not** use `localizedStandardCompare`, which has natural-number ordering: `"ARA.22.10" < "ARA.22.9"` must hold, ordinal.

### 3.1 Quick Cards

#### 3.1.1 `QuickCardsPanel.Refresh` (QuickCardsPanel.xaml.cs:35-46)
Clear the canvas. If there is no vessel, stop. Show the empty hint iff the count is 0. Build every card in list order. Call
`SizeCanvas()`.

#### 3.1.2 `SizeCanvas` (48-59)
`maxX = 1000, maxY = 640`. For each card, `maxX = max(maxX, X+Width+40)` and `maxY = max(maxY, Y+Height+40)`. Set the canvas
width and height.

#### 3.1.3 `MaritimeIcons.ParseColor / ReadableForeground / BackgroundBrush` (MaritimeIcons.cs:36-62)
* `ParseColor(hex)`: blank → `#FF1E88E5`. Otherwise use WPF `ColorConverter`, which accepts `#RGB`, `#ARGB`, `#RRGGBB`, `#AARRGGBB`,
  named colours (`Red`, `Transparent`, … the 141 WPF `Colors` names, case-insensitive) and `sc#` scRGB. On failure →
  `#FF1E88E5`. Mac: support at least the four hex forms and the WPF named colours. Anything else falls back to `#FF1E88E5`.
  `#RGB` expands each nibble (`#1AF` → `#FF11AAFF`). `#ARGB` expands similarly.
* `ReadableForeground(c)`: `l = (0.299·R + 0.587·G + 0.114·B) / 255` using 0–255 channels. `l > 0.6` → `#FF1A1A1A`, else
  `#FFFFFFFF`.

#### 3.1.4 `BuildCard` (61-126)
See VESSEL-013/016/018/019/020. `iconSize = max(18, min(W, H) × 0.36)` as a double font size.

#### 3.1.5 Drag state machine (160-192)
```
mouseDown(card, e):
    if e.source is inside the resize grip → return      (grip handles its own drag)
    if e.clickCount == 2 → open(card); handled; return
    dragCard = card; startMouse = e.pos(canvas); origin = (card.X, card.Y); capture mouse; handled
mouseMove(card, e):
    if dragCard != card or left button not pressed → return
    nx = max(0, origin.x + (p.x − startMouse.x)); ny = max(0, origin.y + (p.y − startMouse.y))
    move view; card.X = nx; card.Y = ny
mouseUp(card):
    if dragCard != card → return
    release; dragCard = nil; sizeCanvas(); save()                 // save = markDirty + flushIfDirty
```
Resize (grip) `DragDelta`: `W = max(90, W+dx)`, `H = max(64, H+dy)`, apply live. `DragCompleted`: `sizeCanvas(); save(); refresh()`.

#### 3.1.6 `Add_Click` (195-207), `Edit` (209-216), `Duplicate` (218-227), `Delete` (229-237)
See VESSEL-021..024. `Clone()` copies Id, Title, Target, IsLink, LinkInPlace, IsFolder, Icon, Color, X, Y, Width, Height.
`CopyFrom()` copies the same fields **except Id**.

#### 3.1.7 `Open` (239-261)
See VESSEL-025. `DataStore.ResolveFilePath(stored)` (DataStore.cs:485):
```
if empty → ""
if starts with http:// | https:// | mailto: (case-insensitive) → stored
if Path.IsPathRooted(stored) → stored
else → Path.GetFullPath(Path.Combine(AppFolder, stored))
```
**Mac rule for "rooted":** a POSIX absolute path (`/…`), a Windows drive path `^[A-Za-z]:[\\/]` (and bare `^[A-Za-z]:`), a UNC or
backslash-rooted path `^[\\/]{2}` or `^\\`, all count as rooted and pass through. Only then combine the remainder with the Mac
AppFolder, normalising `\` to `/` and resolving `..`. Otherwise a Windows `F:\Docs\x.pdf` would wrongly become
`<AppFolder>/F:\Docs\x.pdf`.

#### 3.1.8 `TargetTooltip` (263-268)
See VESSEL-015.

#### 3.1.9 `Save` (270-274)
`repo.MarkDirty(); repo.FlushIfDirty();`, which is an immediate synchronous save.

#### 3.1.10 `DataStore.ImportFile` (DataStore.cs:471-481)
```
ensure <AppFolder>/files exists
name = file name of source (with extension)
dest = <AppFolder>/files/{Guid.NewGuid():N}_{name}      // N = 32 lowercase hex, no dashes
copy source → dest (overwrite)
return "files/" + fileName(dest)                         // always forward slash
```

#### 3.1.11 Editor (`QuickCardEditorWindow.xaml.cs`)
* ctor (16-32): suppress change events while populating Title, Width, Height (`(int)` truncation), icons, swatches and target UI.
  Then refresh the preview and focus Title on load.
* `Size_Changed` (80-85): see VESSEL-051. Parsing uses `double.TryParse(text, out v)`, current culture, `Float|AllowThousands`.
  Mac: parse with the current `Locale` (`NumberFormatter`). Also accept `.` as the decimal separator.
* `LinkFile_Click` (87-95), `ImportCopy_Click` (97-106), `LinkFolder_Click` (108-116), `WebLink_Click` (118-125): see
  VESSEL-043..046. Flag assignments:

| Action | Target | IsLink | LinkInPlace | IsFolder |
|---|---|---|---|---|
| Link file (in place) | absolute path | false | **true** | false |
| Import a copy | `files/{guid}_{name}` | false | false | false |
| Link folder | absolute folder path | false | **true** | **true** |
| Web link | trimmed text | **true** | false | false |

* `CustomColor_Click` (127-136): see VESSEL-050, `$"#FF{R:X2}{G:X2}{B:X2}"`.
* `UpdateTargetUi` (144-152), `UpdatePreview` (154-162): see VESSEL-042/052.

### 3.2 PortsService

#### 3.2.1 `Apply(data, vessel, calls) → (addedCalls, updatedCalls, newVisits)` (PortsService.cs:13-70)
```
byKey = dictionary OIC: for p in vessel.PortCalls: byKey[p.Key] = p       // later duplicates overwrite earlier
for call in calls (file order):
    // (a) vessel's own list
    if byKey[call.Key] exists as existing: CopyInto(existing, call); updated++
    else: vessel.PortCalls.append(call); byKey[call.Key] = call; added++
    // (b) global port: FIRST port in data.Ports (list order) where
    //       (call.UnLocode != "" && port.UnLocode ==OIC call.UnLocode)
    //    || (port.Name ==OIC call.PortName && (port.Country == "" || call.Country == "" || port.Country ==OIC call.Country))
    if none: port = Port{Name: call.PortName, Country: call.Country, UnLocode: call.UnLocode, Visits: []}; data.Ports.append(port)
    else:
        if port.UnLocode == "" && call.UnLocode != "": port.UnLocode = call.UnLocode
        if port.Country  == "" && call.Country  != "": port.Country  = call.Country
        // port.Name is never changed after creation
    // (c) visit: FIRST visit in port.Visits where
    //       (visit.VesselId == vessel.Id || visit.VesselName ==OIC vessel.Name) && visit.ArrivalDate == call.ArrivalDate   (ordinal, case-sensitive)
    if none: port.Visits.append(PortVisit{VesselName: vessel.Name, VesselId: vessel.Id,
                 ArrivalDate, ArrivalTime, DepartureDate, DepartureTime (from call), ImportedAt: call.ImportedAt}); newVisits++
    else:
        visit.VesselId ??= vessel.Id
        if visit.ArrivalTime   == "": visit.ArrivalTime   = call.ArrivalTime
        if visit.DepartureDate == "": visit.DepartureDate = call.DepartureDate
        if visit.DepartureTime == "": visit.DepartureTime = call.DepartureTime
        // visit.ImportedAt NOT updated; VesselName NOT updated
return (added, updated, newVisits)
```
Notes:
* `PortCall.Key = PortName.ToLowerInvariant() + "@" + ArrivalDate`. The dictionary is OIC anyway. The country is **not** part of
  the key.
* When a call matches an existing one, the **incoming** object is discarded after `CopyInto`. The global-DB step still uses the
  incoming call's values.
* `Port.Key` (Models.cs:337) exists but is **unused**. Do not use it for matching.
* Port lookup is first-match in list order. For two same-named ports in different countries, a call with **no** country (layout B)
  attaches to whichever comes first. With the samples this is `Freeport, United States` (see §7.6).

#### 3.2.2 `RemoveCall(data, vessel, call)` (73-87)
```
vessel.PortCalls.remove(call)                       // by reference
vk = lower("{vessel.Name}|{call.ArrivalDate}|{call.ArrivalTime}")      // current vessel name
for port in data.Ports:                            // EVERY port, not just the matching one
    visit = FIRST v in port.Visits where (v.VesselId == vessel.Id || v.VesselName ==OIC vessel.Name) && v.VisitKey == vk
    if visit: port.Visits.remove(visit)
for i from last to first: if data.Ports[i].Visits.isEmpty → remove   // prunes ALL empty ports DB-wide
```
`PortVisit.VisitKey = lower("{VesselName}|{ArrivalDate}|{ArrivalTime}")`, which uses the visit's stored name. Consequences, all to
replicate:
* The visit is removed from *any* port whose visit has the same vessel, date and time. If a vessel has two calls on the same date
  with identical (possibly empty) times at different ports, deleting one removes the visit from both ports.
* After a vessel rename, `vk` (new name) ≠ `VisitKey` (old name), so the visit is not removed.
* A visit whose time was enriched (B after A) still matches, because `CopyInto` also enriched the call's time identically. A visit
  created with a time the call never had is a theoretical mismatch.

#### 3.2.3 `CopyInto(dst, src)` (91-107)
```
dst.PortName = src.PortName                                   // always
Keep(incoming, existing) = incoming.length > 0 ? incoming : existing
Country, UnLocode, PortFacility, PfNo, ArrivalTime, DepartureDate, DepartureTime,
SecurityLevelPort, SecurityLevelVessel, SspFollowed, SpecialMeasures = Keep(src.X, dst.X)
dst.ImportedAt = src.ImportedAt                               // always
// ArrivalDate is equal by key; Id is kept
```
The **last import wins** for any non-empty field, e.g. security level `1` (A) vs `SL 1` (B), see §7.6.

#### 3.2.4 `Export(vessel, path)` (110-146)
See §4.5. Rows are ordered by `ArrivalValue ?? DateTime.MinValue` **descending**, stable. Every cell value is written as **text**.

### 3.3 PortCallReader (both layouts)

#### 3.3.1 Workbook, sheet and bounds (`Read`, PortCallReader.cs:30-66)
* Sheet = the first worksheet (in workbook order) that has any used cell. If none, the first sheet. If it has no used range →
  throw `The workbook is empty.`
* Bounds (ClosedXML `RangeUsed()`, content-based): `firstRow/lastRow/firstCol/lastCol` = min/max row and column over cells with
  non-empty content. Merged areas contribute only their anchor cell's value. Mac: compute from cells whose rendered value
  (§3.3.2) is non-empty. Cells that carry only a style must not extend the bounds.
* **Detection scan**: rows `firstRow … min(lastRow, firstRow+12)`, columns `firstCol … lastCol`. For each cell `v = Cell(r,c)`,
  `lv = lower(v)`:
  * `looksB` if `lv` contains `un locator`, `un/locode` or `port of call list`;
  * `looksA` if `lv` contains `date arrived`, `port name, country` or `last ports of call`;
  * `vesselName` (first only) if `lv == "vessel name"` **exactly** → `NextValue` (the first non-empty cell to the right in the same row);
  * `imo` (first only) if `lv` contains `imo number` → `NextValue`;
  * `callSign` (first only) if `lv` contains `call sign` → `NextValue`.
* Dispatch: `looksB && !looksA` → B. Else `looksA` → A (A wins when both match). Else `looksB` → B. Else throw
  `Couldn't recognise this as a ports-of-call list. Expected either a 'Last Ports of Call' sheet or a 'Port of Call List' sheet with an Arrival/Departure header.`
* Afterwards: set `VesselName/Imo/CallSign` on the result, and stamp every call's `ImportedAt = now "yyyy-MM-dd HH:mm"` (local).

#### 3.3.2 `Cell(r, c)` rendering (208-220)
| Cell type (ClosedXML) | Rendered string |
|---|---|
| empty | `""` |
| DateTime (numeric with a date/time number format, or `t="d"`) | time-of-day == 0 → `yyyy-MM-dd`, else `yyyy-MM-dd HH:mm` |
| TimeSpan (duration/time-only formats) | `hh:mm` (hours mod 24, zero-padded) |
| Number | `value.ToString("0.####", Invariant)`: up to 4 decimals, trailing zeros trimmed, no thousands separator, `-` for negatives |
| Text / Boolean / other | `GetString().Trim()`: text trimmed. Booleans `TRUE`/`FALSE`. Errors as their literal, e.g. `#N/A` |
Date serial → date uses the OLE Automation epoch 1899-12-30 (1900 system). Honour `workbookPr/@date1904` by adding 1462 days if
present (§9 Q9).

#### 3.3.3 Layout A: "Last Ports of Call - 2 Years" (`ReadFormatA`, 69-108)
1. `hdr` = the first row (scanning **all** rows `firstRow…lastRow`, all columns) containing a cell whose lower text contains
   `port name`. None → throw `Could not find the 'Port Name' header row.`
2. For each column of `hdr`, with `h = lower(cell)`, non-empty, first matching rule wins **per column**. If several columns match
   the same rule, the **last** such column wins:
   * contains `port name` → portCol
   * contains `date arrived` → arrCol
   * contains `date depart` → depCol
   * contains `security level in port` → secPortCol
   * contains `security level on vessel` → secVesselCol
   * contains `appropriate measures` **or** `ssp` → sspCol
   * contains `special security` → specialCol
3. portCol missing → throw `Could not find the port-name column.`
4. Rows `hdr+1 … lastRow`: skip if the port cell is empty. `(name, country) = SplitPort(raw)` splits at the **last** comma, and
   both parts are trimmed. With no comma → (trimmed, ""). Then build a `PortCall`:
   `ArrivalDate = NormDate(arr)`, `DepartureDate = NormDate(dep)`, `SecurityLevelPort`, `SecurityLevelVessel`, `SspFollowed`,
   `SpecialMeasures` are the raw rendered strings. Missing columns → `""`. There are **no times, UN/LOCODE, facility or PF no.**
5. `Format = "Last Ports of Call (2 years)"`.

#### 3.3.4 Layout B: "Port of Call List - Last 10 Ports" (`ReadFormatB`, 111-181)
1. `subRow` = the first row containing `un locator`. Otherwise the first row containing `un/locode`. None → throw
   `Could not find the 'UN locator' header row.` `catRow = subRow − 1`.
2. Walk columns left to right with a **sticky category**. If `catRow ≥ firstRow` and the cell at `(catRow, c)` is non-empty,
   `cat = lower(it)`. Otherwise `cat` keeps the previous value, which emulates merged header cells. `sub = lower(cell(subRow, c))`.
   * cat contains `port facility`: sub contains `name` → facilityCol. Else sub contains `pf no` → pfNoCol.
   * else cat **starts with** `port`: sub contains `name` → portNameCol. Else sub contains `un locator` or `locode` → unlocodeCol.
   * else cat contains `security level`: sub contains `vessel` → secVesselCol. Else sub non-empty → secPortCol (e.g. `PF`).
   * else cat contains `arrival`: sub contains `date` → arrDateCol. Else sub contains `time` → arrTimeCol.
   * else cat contains `departure`: sub `date` → depDateCol. Else `time` → depTimeCol.
   * else cat contains `special` → specialCol, for **every** such column, so the last one wins.
3. portNameCol missing → **fall back to firstCol** (no error).
4. Rows `subRow+1 … lastRow`: skip if the name cell is empty. `PortName` = the raw name (no comma split, `Country = ""`).
   `UnLocode`, `PortFacility`, `PfNo`, `SecurityLevelPort`, `SecurityLevelVessel` and `SpecialMeasures` are raw.
   `ArrivalDate = NormDate`, `ArrivalTime = NormTime`, `DepartureDate = NormDate`, `DepartureTime = NormTime`. `SspFollowed` is
   always `""` because layout B has none.
5. `Format = "Port of Call List (last 10 ports)"`.

#### 3.3.5 `NormDate(s)` (222-238), which returns canonical `yyyy-MM-dd` or the input unchanged
```
s = trim(s); if s == "" → ""
m = /^(\d{4})-(\d{1,2})-(\d{1,2})/            (prefix match, no end anchor)
    if match and a valid Gregorian date(y, mo, d) → "yyyy-MM-dd"; invalid → fall through
m = /^(\d{1,2})[\/.\-](\d{1,2})[\/.\-](\d{2,4})/   (prefix; DAY-FIRST: d, mo, y)
    y < 100 → y += 2000   (always 20xx, no pivot)
    if valid date(y, mo, d) → "yyyy-MM-dd"; invalid → fall through
if DateTime.TryParse(s, InvariantCulture) → "yyyy-MM-dd"   (month-first for numeric forms, English month names)
return s                                        (unparseable text kept verbatim)
```
Note: a 3-digit year is accepted literally (`202` → year 0202). Trailing text after the matched prefix (e.g. a time) is ignored.

#### 3.3.6 `NormTime(s)` (240-245)
`s = trim(s)`. Take the **first** (unanchored) match of `/(\d{1,2}):(\d{2})/` → `twoDigit(Int(g1)) + ":" + g2`. No match → `""`.
Seconds are dropped. There is no range validation (`99:99` → `99:99`).

#### 3.3.7 `FindRow` (184-190), `NextValue` (192-200), `SplitPort` (202-206)
As described. `FindRow` scans rows top to bottom and, within each row, columns left to right, and returns the first row where some
cell's lower text contains the needle.

#### 3.3.8 Error strings (thrown as `InvalidDataException`, shown inside the Import failed box)
* `The workbook is empty.`
* `Couldn't recognise this as a ports-of-call list. Expected either a 'Last Ports of Call' sheet or a 'Port of Call List' sheet with an Arrival/Departure header.`
* `Could not find the 'Port Name' header row.`
* `Could not find the port-name column.`
* `Could not find the 'UN locator' header row.`
* Plus any library error for a corrupt or non-xlsx file. The Mac should word these as
  `The file could not be opened as an Excel workbook (.xlsx).` plus detail.

### 3.4 ShippalmReader

#### 3.4.1 `Read(path) → [ShipJob]` (ShippalmReader.cs:16-82)
1. Sheet = the first worksheet with a used range, else the first sheet. No used range → return an **empty list**. That is not an
   error: the panel reports `Imported 0 work orders … (0 new, 0 updated).`
2. Header row = the first row in `firstRow … min(lastRow, firstRow+15)` having one cell with `Norm(cell) == "no."` **and** another
   with `Norm(cell) == "title"`. None → throw `Could not find the Shippalm header row (expected 'No.' and 'Title').`
   `CrewText.Norm(s)`: null or empty → `""`. Replace `’` (U+2019) with `'`, `\n` and `\r` with spaces. Collapse `\s+` to a single
   space. Trim. Lower-case invariant.
3. Column map: for each header cell, `h = Norm(text)`. If non-empty and not already mapped → `col[h] = c` (the **first** duplicate
   wins).
4. `imported = now "yyyy-MM-dd HH:mm"` (local, once per file).
5. For each row after the header: `no = G("No.").Trim()`. Skip if blank. Build:

| ShipJob field | Header (Norm-matched) | Transform |
|---|---|---|
| JobNo | `No.` | trimmed |
| Title | `Title` | raw |
| WorkPlanNo | `Work Plan No.` | raw |
| Status | `Work Order Status` | raw |
| ClassCode | `Class Code` | raw |
| Category | `Work Order Category Code` | raw |
| ResponsibleRank | `Responsible Rank` | raw |
| FunctionNo | `Function No.` | raw |
| FunctionDescription | `Function Description` | raw |
| Interval | `Interval` | raw |
| DueStatus | `Due Status` | raw |
| DueDate | `Due Date` | `ExcelDate` |
| FinishedDate | `Finished Date-Time` | `ExcelDate` (the time is dropped) |
| LastDoneDate | `Last Done Date` | `ExcelDate` |
| OverdueDays | `Overdue Days` | `int.TryParse(NumberStyles.Any, Invariant)`, fail → 0 |
| Notify | `Notify` | `ParseBool`. Absent column → false |
| ImportedAt | — | `imported` |
| IsCompleted / CompletedDate | — | false / "" |

Missing columns yield `""` (or 0/false).

`Cell(r,c)` for Shippalm (136-154), which is **different from the ports reader**:

| Type | Rendered |
|---|---|
| empty | `""` |
| Number | whole number → `Int64` decimal string (`48108`). Else shortest round-trip invariant (`12.5`, `1E-05`) |
| DateTime | `yyyy-MM-dd` (the time is dropped) |
| Boolean | `TRUE` / `FALSE` |
| else | `GetString().Trim()` |

`int.TryParse("12.0", Any)` → 12. `"12.5"` → fails → 0. `"1,234"` → 1234. `"(5)"` → −5. `" 7 "` → 7.

#### 3.4.2 `Write(jobs, path)` (86-125)
See §4.4. The Due Date and Last Done Date columns are formatted as text (`@`) so a re-read yields the same `yyyy-MM-dd` strings.

#### 3.4.3 `ParseBool(s)` (127-134)
Trim. True iff OIC-equal to `yes`, `true` or `y`, or exactly `1`. Everything else → false (`No`, `0`, `""`, `FALSE`, `on`).

#### 3.4.4 `ExcelDate(raw)` (158-170)
```
if blank → ""
raw = trim(raw)
if CrewMember.ParseDate(raw) → "yyyy-MM-dd"
if Double.parse(raw, NumberStyles.Any, Invariant) = serial && 20000 < serial < 200000 → DateTime.FromOADate(serial) date → "yyyy-MM-dd"
return raw                                                   // unparseable kept verbatim (shown grey)
```
`CrewMember.ParseDate(s)` (CrewMember.cs:142): blank → nil. Trim. Try the exact formats `yyyy-MM-dd`, `yyyy/MM/dd`, `yyyy.MM.dd`
(two-digit month and day required). Then .NET `DateTime.TryParse(s, InvariantCulture)`, which is **month-first** for numeric slash
dates, accepts English month names, optional times and ISO `T` forms. Else nil. **Month-first trap:** a day-first `03/04/2026` string
in a Shippalm date column becomes **4 March**. Replicate for parity, because it is the documented Windows behaviour (see PROGRESS
"Crew date parser"). Shippalm exports use real date cells or serials in practice, so this rarely triggers.

Serial window: 20000 is 1954-10-04 and 200000 is about 2447. `FromOADate` keeps the whole-day part (fractional time dropped).

#### 3.4.5 `ShipJob.DaysUntilDue(today)` (Models.cs:394-398)
`due = ParseDate(DueDate)`. nil → nil. Else `(due.date − today.date).TotalDays` as Int, which is a calendar-day difference (no DST
effect in .NET since `DateTime` arithmetic is naive). **Swift:** compute on calendar dates, e.g. `Calendar(gregorian).dateComponents([.day], from: startOfDay(today), to: startOfDay(due)).day`
with both in the current time zone, or better, Julian-day numbers of `(y,m,d)`. Never divide seconds by 86400 across a DST change.

### 3.5 ShipJobsPanel algorithms
* `PopulateFilters` (56-69), `FillCombo` (71-81): see VESSEL-105/106.
* `Import_Click` (84-130): see VESSEL-101/102.
* `Export_Click` (133-168): see VESSEL-103.
* `NotifEnabled_Click` (171-178), `UpdateNotifications` (180-227): see VESSEL-120.
* `Search_Changed` (232-236): 200 ms `DispatcherTimer` debounce (restart on each keystroke).
* `Header_Click` (238-245): see VESSEL-111. Only real headers with non-empty string text count.
* `Filtered` (247-281), `ApplySort` (283-304): see VESSEL-104..108/111.
* `BuildView` (310-322): with no vessel → clear the list and show `No ship selected.`. Else rows = Filtered, then sorted, each with
  `DueInfo`. Set the list. `UpdateSummary`. `UpdateNotifications`.
* `UpdateSummary` (324-344), `DueInfo` (346-358): see VESSEL-119/110.
* `NotifyToggle_Click` (361-370), `SetNotifyForShown` (375-384), `CompletedToggle_Click` (387-394), `SetCompletedForTarget` (399-409),
  `Delete_Click` (412-425), `SetNotifyForTarget` (431-440), `TargetRows` (443-448): see VESSEL-112..117.
  `TargetRows` = selected jobs if any, else all shown jobs.
* `Save()` failures: in Import they are caught and shown as `Import failed`. Elsewhere (`SetCompletedForTarget`, `Delete`, etc.)
  they propagate to the app's global unhandled-exception handler. On the Mac, route every save failure through the app's standard
  save-error UI. The in-memory change stays and is dirty (retry on the next save).

### 3.6 Safe file name (`PortsPanel.xaml.cs:79`, `ShipJobsPanel.xaml.cs:142`)
`safe = (vessel.Name ?? "vessel")` with each char in `Path.GetInvalidFileNameChars()` replaced by `_`. On Windows that set is
`" < > | \0 … \x1F : * ? \ /`. **Mac:** use the same Windows set for identical suggested names. Also note that `/` and `:` are the
only characters macOS itself rejects.

### 3.7 PortsPanel / PortsPage algorithms
* `PortsPanel.BuildView` (120-153): filter (VESSEL-206), sort (VESSEL-208), summary (VESSEL-210).
* `PortsPanel.Header_Click` (112-118): same toggle rule as jobs.
* `PortsPage.Refresh` (22-49), `ShowVisits` (54-68): see VESSEL-251..254.

---

## 4. DATA FORMATS

### 4.1 JSON serialisation rules (System.Text.Json, `DataStore.Opts`, DataStore.cs:267-275)
* **PascalCase** property names, exactly as the C# names (no naming policy).
* `WriteIndented = false` (compact). `DefaultIgnoreCondition = WhenWritingNull` (null properties are **omitted**. Empty strings,
  `false` and `0` **are** written). `ReferenceHandler.IgnoreCycles`.
* **No `JsonStringEnumConverter`**: enums would be numbers. This subsystem has no enums.
* **Default encoder**: every non-ASCII character is written as a `\uXXXX` escape (emoji as surrogate pairs, e.g. `"⚓"` →
  `"\u2693"`, `"🚢"` → `"\uD83D\uDEA2"`). HTML-sensitive ASCII `< > & ' + "` and `` ` `` are also escaped (`\u003C`, `\u003E`,
  `\u0026`, `\u0027`, `\u002B`, `\u0022`, `\u0060`). The Mac reader must decode escapes (Foundation does). The Mac writer may emit raw UTF-8.
  Windows reads either. Semantic equality is what matters.
* `Guid` → `"D"` format, **lower-case** (`"3f2504e0-4f89-11d3-9a0c-0305e82c3301"`). The Mac must write **lower-case**. Swift's
  `UUID.uuidString` is upper-case, so lower-case it explicitly, because Flash Sync diffs compare Id strings. Accept either case on read.
* `double` → shortest round-trip JSON number (`24`, `180`, `123.5`). The Mac must write finite numbers only.
* `int` (`OverdueDays`) must be written as an **integer literal**. STJ **rejects** `3.0` for an `Int32`.
* **Missing keys** → C# property initialiser defaults (listed below). **JSON `null`** on a non-nullable string → STJ stores null,
  so the Mac should treat null as the default.
* `[JsonIgnore]` computed members are never written: `PortCall.Key/ArrivalValue/DisplayName/ArrivalDisplay/DepartureDisplay`,
  `Port.Key/Display`, `PortVisit.VisitKey/ArrivalValue/ArrivalDisplay/DepartureDisplay`, `ShipJob.DueDateValue`.
* Key **order is not significant**. Do not rely on it.
* **Unknown keys:** `AppData` and `UiState` preserve unknown members (`[JsonExtensionData]`). `Vessel`, `QuickCard`, `ShipJob`,
  `PortCall`, `Port` and `PortVisit` do **not**. So any extra key the Mac adds inside these objects is **dropped** by Windows on
  its next save. Therefore **do not store Mac-only state inside these objects** (e.g. security-scoped bookmarks, §6.2). The Mac
  itself *should* preserve unknown keys on these objects, to be forward-compatible with newer Windows builds.

### 4.2 Keys touched by this subsystem

`Vessel` (inside `AppData.Vessels[]`; generic HierarchyItem keys `Id, Name, Description, Container, RelatedIds, Tags, GroupId,
BucketIds, LockHash, LockSalt, LockHint` are specified elsewhere):

| Key | Type | Default if missing | Notes |
|---|---|---|---|
| `QuickCards` | array of QuickCard | `[]` | order = z-order |
| `Jobs` | array of ShipJob | `[]` | insertion order. Key JobNo (OIC) |
| `NotificationsEnabled` | bool | **`true`** | master switch |
| `PortCalls` | array of PortCall | `[]` | insertion order |

`QuickCard`:

| Key | Type | Default | Values |
|---|---|---|---|
| `Id` | Guid string | new Guid | |
| `Title` | string | `""` | |
| `Target` | string | `""` | `files/{32hex}_{name}` (imported), absolute path (in place / folder, may be `C:\…`, `\\server\share\…`, or a Mac `/Volumes/…`), or URL |
| `IsLink` | bool | false | |
| `LinkInPlace` | bool | false | |
| `IsFolder` | bool | false | |
| `Icon` | string | `"⚓"` (U+2693) | one of §4.6 glyph strings (exact code points incl. VS16/ZWJ) |
| `Color` | string | `"#FF1E88E5"` | `#AARRGGBB` produced by the app. Readers accept §3.1.3 forms |
| `X` | double | 24 | canvas DIP/pt, ≥ 0 |
| `Y` | double | 24 | ≥ 0 |
| `Width` | double | 180 | ≥ 80 (editor) / 90 (drag) |
| `Height` | double | 120 | ≥ 60 (editor) / 64 (drag) |

Target kind resolution order everywhere: `IsLink` → web. Else `IsFolder` → folder. Else `LinkInPlace` → live file. Else imported copy.

`ShipJob` (no Id):

| Key | Type | Default | Format |
|---|---|---|---|
| `JobNo` | string | `""` | e.g. `ARA.22.3120` |
| `Title` | string | `""` | |
| `WorkPlanNo` | string | `""` | |
| `Status` | string | `""` | e.g. `Execution` |
| `ClassCode` | string | `""` | |
| `Category` | string | `""` | e.g. `ROUTINE`, `CBM` |
| `ResponsibleRank` | string | `""` | |
| `FunctionNo` | string | `""` | |
| `FunctionDescription` | string | `""` | |
| `Interval` | string | `""` | e.g. `64,000 H`, `60M` |
| `DueStatus` | string | `""` | e.g. `in Window` |
| `DueDate` | string | `""` | `yyyy-MM-dd`, or raw text if unparseable |
| `FinishedDate` | string | `""` | `yyyy-MM-dd` or raw |
| `LastDoneDate` | string | `""` | `yyyy-MM-dd` or raw |
| `OverdueDays` | int | 0 | integer literal |
| `Notify` | bool | false | |
| `IsCompleted` | bool | false | |
| `CompletedDate` | string | `""` | `yyyy-MM-dd` local |
| `ImportedAt` | string | `""` | `yyyy-MM-dd HH:mm` local |

`PortCall`:

| Key | Type | Default | Format |
|---|---|---|---|
| `Id` | Guid | new | |
| `PortName` | string | `""` | |
| `Country` | string | `""` | layout A only |
| `UnLocode` | string | `""` | e.g. `NGBON` |
| `PortFacility` | string | `""` | |
| `PfNo` | string | `""` | text, leading zeros kept (`0001`) |
| `ArrivalDate` | string | `""` | `yyyy-MM-dd`, or raw text |
| `ArrivalTime` | string | `""` | `HH:mm` or `""` |
| `DepartureDate` | string | `""` | as ArrivalDate |
| `DepartureTime` | string | `""` | as ArrivalTime |
| `SecurityLevelPort` | string | `""` | raw (`1`, `SL 1`) |
| `SecurityLevelVessel` | string | `""` | raw |
| `SspFollowed` | string | `""` | raw (`YES`/`NO`/blank) |
| `SpecialMeasures` | string | `""` | raw, trimmed |
| `ImportedAt` | string | `""` | `yyyy-MM-dd HH:mm` local |

`Port` (in `AppData.Ports[]`):

| Key | Type | Default |
|---|---|---|
| `Id` | Guid | new |
| `Name` | string | `""` |
| `Country` | string | `""` |
| `UnLocode` | string | `""` |
| `Visits` | array of PortVisit | `[]` |

`PortVisit` (no Id):

| Key | Type | Default | Notes |
|---|---|---|---|
| `VesselName` | string | `""` | snapshot |
| `VesselId` | Guid? | null → **omitted** | legacy visits may lack it |
| `ArrivalDate`, `ArrivalTime`, `DepartureDate`, `DepartureTime` | string | `""` | as PortCall |
| `ImportedAt` | string | `""` | from the creating import |

**Date/time strings are culture-formatted on Windows.** `DateTime.ToString("yyyy-MM-dd HH:mm")` uses the current culture's
calendar and time separator. On an exotic culture (e.g. `th-TH` Buddhist calendar) this can yield `2569-…`. Mac writers must
always use `en_US_POSIX` + Gregorian. Mac readers must tolerate odd values, since `ImportedAt` is display-only and `CompletedDate` is
display-only.

### 4.3 Activity-log entry written by a ports import (`AppData.Log[]`)
```json
{"TimestampUtc":"2026-07-17T15:10:02.1234567Z","Action":"Added","Kind":"Ports import",
 "Name":"47 new, 0 updated","Detail":"BW Pavilion Aranda \u00B7 Last Ports of Call (2 years)"}
```
The `TimestampUtc` format is STJ's ISO-8601 DateTime form with `Z` (Kind=Utc): up to 7 fractional digits, trailing zeros
trimmed, and no fraction at all when it is zero. The Mac should write the same shape, or at least an ISO-8601 UTC timestamp that
STJ parses. The log schema is owned by the activity-log
spec.

### 4.4 Shippalm xlsx: import expectations and AA export layout
**Import (raw Shippalm "Work Order List" export):** any sheet (the first non-empty one). The header row (within the first 16 used
rows) contains at least `No.` and `Title`. Columns are matched by normalised header text, so their order is irrelevant. Recognised
headers are listed in §3.4.1. Other columns are ignored. Dates may be real date cells, pre-formatted text, or bare serial numbers
(e.g. `48108`). No sample Shippalm file is in the repo. PROGRESS records a real export of **2,524 jobs** with no duplicate numbers.

**AA export (`ShippalmReader.Write`):**
* Sheet name `report`. Row 1 = headers (whole row **bold**). Data from row 2. No freeze panes, no filters.
* Column order (A → P):

| Col | Header | Value | Cell type |
|---|---|---|---|
| A | `No.` | JobNo | text |
| B | `Title` | Title | text |
| C | `Work Plan No.` | WorkPlanNo | text |
| D | `Work Order Status` | Status | text |
| E | `Class Code` | ClassCode | text |
| F | `Work Order Category Code` | Category | text |
| G | `Responsible Rank` | ResponsibleRank | text |
| H | `Finished Date-Time` | FinishedDate | text |
| I | `Due Date` | DueDate | text, **column number format `@`** |
| J | `Interval` | Interval | text |
| K | `Function Description` | FunctionDescription | text |
| L | `Due Status` | DueStatus | text |
| M | `Function No.` | FunctionNo | text |
| N | `Last Done Date` | LastDoneDate | text, **column number format `@`** |
| O | `Overdue Days` | OverdueDays | **number** |
| P | `Notify` | `Yes` / `No` | text |

* Columns auto-fit to their contents (ClosedXML `AdjustToContents`). Mac: width ≈ max display chars × 1.1 + 2, capped at 100.
* `IsCompleted` / `CompletedDate` are **not exported** (§9 Q1).
* Round trip: `Read(Write(jobs))` yields the same JobNo, Title, WorkPlanNo, Status, ClassCode, Category, ResponsibleRank,
  FunctionNo, FunctionDescription, Interval, DueStatus, DueDate, FinishedDate, LastDoneDate, OverdueDays and Notify, assuming the
  dates were canonical `yyyy-MM-dd` strings. PROGRESS verified this with a 9-check harness on the 2,524-row file.

### 4.5 Ports-of-call xlsx: AA export layout (`PortsService.Export`)
* Sheet `Ports of Call`. Row 1 headers, **each header cell bold**. Rows from 2, ordered by arrival descending.
* Columns A → M: `Port`, `Country`, `UN/LOCODE`, `Port Facility`, `PF no.`, `Arrival Date`, `Arrival Time`, `Departure Date`,
  `Departure Time`, `Sec. Port`, `Sec. Vessel`, `SSP`, `Special measures`, holding PortName, Country, UnLocode, PortFacility, PfNo,
  ArrivalDate, ArrivalTime, DepartureDate, DepartureTime, SecurityLevelPort, SecurityLevelVessel, SspFollowed and SpecialMeasures.
  **All text cells.**
* Columns auto-fit. No number formats set.

### 4.6 Maritime icon set (exact order, glyph code points, tooltip name). Stored verbatim in `QuickCard.Icon`
| # | Glyph | Code points | Name |
|---|---|---|---|
| 1 | ⚓ | U+2693 | Anchor |
| 2 | 🚢 | U+1F6A2 | Ship |
| 3 | ⛴️ | U+26F4 U+FE0F | Ferry |
| 4 | ⛵ | U+26F5 | Sailboat |
| 5 | 🛥️ | U+1F6E5 U+FE0F | Motorboat |
| 6 | 🛟 | U+1F6DF | Lifebuoy |
| 7 | ⛑️ | U+26D1 U+FE0F | Rescue |
| 8 | 🧭 | U+1F9ED | Compass |
| 9 | 🗺️ | U+1F5FA U+FE0F | Chart |
| 10 | 🛞 | U+1F6DE | Helm/Wheel |
| 11 | ⚙️ | U+2699 U+FE0F | Engine |
| 12 | 🔧 | U+1F527 | Wrench |
| 13 | 🛠️ | U+1F6E0 U+FE0F | Tools |
| 14 | 🧰 | U+1F9F0 | Toolbox |
| 15 | 🔩 | U+1F529 | Fasteners |
| 16 | ⚡ | U+26A1 | Electrical |
| 17 | 💡 | U+1F4A1 | Lights |
| 18 | 🔦 | U+1F526 | Torch |
| 19 | 📡 | U+1F4E1 | Radar |
| 20 | 📻 | U+1F4FB | Radio |
| 21 | 📞 | U+1F4DE | Phone |
| 22 | 🔥 | U+1F525 | Fire |
| 23 | 🧯 | U+1F9EF | Extinguisher |
| 24 | 🚨 | U+1F6A8 | Alarm |
| 25 | ⚠️ | U+26A0 U+FE0F | Warning |
| 26 | ⛽ | U+26FD | Fuel |
| 27 | 🛢️ | U+1F6E2 U+FE0F | Oil/Bunker |
| 28 | 💧 | U+1F4A7 | Fresh water |
| 29 | 🌊 | U+1F30A | Sea/Ballast |
| 30 | ❄️ | U+2744 U+FE0F | Reefer |
| 31 | 🌡️ | U+1F321 U+FE0F | Temperature |
| 32 | 📦 | U+1F4E6 | Cargo |
| 33 | 🗃️ | U+1F5C3 U+FE0F | Stores |
| 34 | 🗂️ | U+1F5C2 U+FE0F | Files |
| 35 | 📁 | U+1F4C1 | Folder |
| 36 | 📄 | U+1F4C4 | Document |
| 37 | 📋 | U+1F4CB | Checklist |
| 38 | 📅 | U+1F4C5 | Schedule |
| 39 | 🩺 | U+1FA7A | Medical |
| 40 | 🧪 | U+1F9EA | Lab/Test |
| 41 | 🪝 | U+1FA9D | Hook/Crane |
| 42 | 🔗 | U+1F517 | Link |
| 43 | 🚪 | U+1F6AA | Door/Hatch |
| 44 | 🪟 | U+1FA9F | Bridge |
| 45 | 🧑‍✈️ | U+1F9D1 U+200D U+2708 U+FE0F | Crew |
| 46 | 🌐 | U+1F310 | Network |
| 47 | ☎️ | U+260E U+FE0F | Comms |
| 48 | 🧭 | U+1F9ED | Navigation (**duplicate glyph of #8, keep it**) |
| 49 | 🔔 | U+1F514 | Bell |
| 50 | ⭐ | U+2B50 | Favourite |

`MaritimeIcons.DefaultIcon = "⚓"` (U+2693).

### 4.7 Colour palette (exact strings, order) and readable foreground
| # | Hex | FG | # | Hex | FG |
|---|---|---|---|---|---|
| 1 | `#FF1E88E5` | white | 11 | `#FF8E24AA` | white |
| 2 | `#FF3949AB` | white | 12 | `#FF5E35B1` | white |
| 3 | `#FF00897B` | white | 13 | `#FF546E7A` | white |
| 4 | `#FF43A047` | white | 14 | `#FF6D4C41` | white |
| 5 | `#FF7CB342` | white (l=0.587) | 15 | `#FF26A69A` | white |
| 6 | `#FFFDD835` | `#1A1A1A` | 16 | `#FF455A64` | white |
| 7 | `#FFFB8C00` | `#1A1A1A` (l=0.6166) | 17 | `#FF263238` | white |
| 8 | `#FFF4511E` | white | 18 | `#FF9E9E9E` | `#1A1A1A` (l=0.6196) |
| 9 | `#FFE53935` | white | 19 | `#FFEEEEEE` | `#1A1A1A` |
| 10 | `#FFD81B60` | white | 20 | `#FFFFFFFF` | `#1A1A1A` |

### 4.8 Sample import layout A: `AA/POC/Last Ports - 24 Months (4).xlsx` (inspected)
* One sheet named `Last 2 Years`. All values are **shared strings** (dates are text, not date cells).
* Row 2: `C2` = `Last Ports of Call - 2 Years` (merged C2:K3). Used range starts at row 2.
* Row 5 (header): `A5 No` · `B5 Port Name, Country` · `C5 Date Arrived` (merged C:D) · `E5 Date Departured` (E:F) ·
  `G5 Security level in Port` (G:H) · `I5 Security level on vessel` (I:J) · `K5 Appropriate measures followed as per SSP` (K:L) ·
  `M5 Any special security measures taken`.
* Rows 6–52: 47 data rows. Examples:
  * `6: 1 | Bonny, Nigeria | 15/07/2026 | 17/07/2026 | 1 | 1 | YES | (blank)`
  * `17: 12 | Portland, United Kingdom | 13/02/2026 | 14/02/2026 | 1 | 1 | YES | Bunker barge 'Monjasa Promoter'`
  * `29: 24 | Hong Kong, Hong Kong S.A.R. | 16/09/2025 | 17/09/2025 | 1 | 1 | YES |`
  * `47–52`: security levels blank, special = `ArrPurpose: …` (e.g. `52: 47 | Ceuta, Spain | 29/07/2024 | 29/07/2024 | | | YES | ArrPurpose: DO Bunkering`)
* Row 53: a stray `E53 = 22/07/2024` (departure only, no port) → **skipped** because the port cell is empty.
* Dates are **day-first `dd/MM/yyyy` text**, parsed by the NormDate day-first regex.
* The column mapping yields: portCol=B(2), arrCol=C(3), depCol=E(5), secPortCol=G(7), secVesselCol=I(9), sspCol=K(11),
  specialCol=M(13).

### 4.9 Sample import layout B: `AA/POC/Port of Call List - Last 10 Ports (14).xlsx` (inspected)
* Sheets `Sheet1` (data), `Sheet2` and `Sheet3` (empty). All values are shared strings.
* `A1` = `PORT OF CALL LIST - LAST 10 PORTS` (merged A1:L1).
* Row 2: `A2 Vessel Name` (A:B) · `C2 BW PAVILION ARANDA` (C:F) · `G2 IMO Number` (G:H) · `I2 9792606` (I:L).
* Row 3: `A3 Date` · `C3 17/07/2026` · `G3 Call sign` · `I3 9V6330`.
* Row 5 (category row): `A5 Port` (A:C) · `D5 Port Facility` (D:E) · `F5 Security Level` (F:G) · `H5 Arrival` (H:I) ·
  `J5 Departure` (J:K) · `L5 Special or Additional Security Measures Taken by the Ship` (L5:L6).
* Row 6 (sub-header): `A6 Name` (A:B) · `C6 UN locator` · `D6 Name` · `E6 PF no.` · `F6 PF` · `G6 Vessel` · `H6 Date` ·
  `I6 Time` · `J6 Date` · `K6 Time`.
* Rows 7–16: 10 ports (§7.5). Times are text `HH:mm`. PF numbers are text with leading zeros.
* Row 18 footer: `G18 Master: ` · `H18 RENE MORATA SUBONG` · `K18 Date:` · `L18 17/07/2026`. It is skipped because A18 is empty.
* Mapping: portName=A(1), unlocode=C(3), facility=D(4), pfNo=E(5), secPort=F(6), secVessel=G(7), arrDate=H(8), arrTime=I(9),
  depDate=J(10), depTime=K(11), special=L(12).

---

## 5. DEPENDENCIES

### 5.1 Called by this subsystem
| Callee | Used for |
|---|---|
| `AppRepository.MarkDirty / FlushIfDirty / Save / LogAdded`, `.Data` | persistence, activity log, `Data.Ports` |
| `DataStore.ImportFile`, `DataStore.ResolveFilePath`, `DataStore.AppFolder/FilesFolder` | quick-card imported copies and opening |
| `CrewMember.ParseDate` | `ShipJob.DueDateValue`, `PortCall.ArrivalValue`, `PortVisit.ArrivalValue`, `ExcelDate` |
| `CrewText.Norm` | Shippalm header matching |
| `MaritimeIcons.All / Palette / ParseColor / ReadableForegroundBrush / BackgroundBrush` | cards and editor |
| `PromptWindow` | web-link URL prompt |
| `UiTree.FindAncestor<Thumb>` | ignore card mouse-down on the resize grip |
| `BoolToStrikethroughConverter` (`BoolToStrike`) | struck-through job titles |
| ClosedXML 0.104.2 (`XLWorkbook`, `RangeUsed`, `Cell`, `DataType`, `AdjustToContents`, `SaveAs`) | all xlsx read/write |
| Theme brushes `Panel`, `PanelAlt`, `BorderB`, `Muted`, `Accent`, `Fg`; style `AccentButton` | styling |

### 5.2 Calls into this subsystem
| Caller | Call |
|---|---|
| `HierarchyPage` (Vessels page) selection change, `HierarchyPage.xaml.cs:532-538` | `QuickCardsCtrl.Load`, `ShipJobsCtrl.Load`, `PortsCtrl.Load`; selects the Quick Cards tab |
| `HierarchyPage` kind setup, `:64-68` | vessel tabs visibility |
| `MainWindow` data (re)load, `:1213` | `PortsPg.Init(repo)` |
| `MainWindow.MainTabs_SelectionChanged`, `:1417` | `PortsPg.Refresh()` |
| Trash / undo (`AppRepository` Trash of Vessel) | serialises the vessel incl. QuickCards/Jobs/PortCalls |
| Flash Sync, bundle export/import, Drive sync | carry `Vessels` and `Ports` as ordinary data |

### 5.3 Windows-only APIs used
| API | Where | Purpose |
|---|---|---|
| `System.Diagnostics.Process.Start(ProcessStartInfo{UseShellExecute=true})` | QuickCardsPanel.Open, both exports | shell-open file, folder (Explorer) or URL |
| `Microsoft.Win32.OpenFileDialog` / `SaveFileDialog` | editor, both panels | pickers |
| `System.Windows.Forms.FolderBrowserDialog` | editor Link folder | folder picker |
| `System.Windows.Forms.ColorDialog` | editor Custom colour | colour picker |
| `System.Windows.MessageBox` | everywhere | alerts and confirmations |
| `Mouse.OverrideCursor = Cursors.Wait` | imports and exports | busy cursor |
| `DispatcherTimer` | search debounce, repo debounce | timers |
| WPF `Canvas`, `Thumb`, `Border`, `ListView/GridView`, `ContextMenu`, `ToggleButton`, `ComboBox` | panels | UI |
| `Path.GetInvalidFileNameChars()` (Windows set) | exports | safe file names |
| `Path.IsPathRooted`, `File.Exists`, `Directory.Exists`, UNC paths | Open | target resolution |
| ClosedXML (.NET, not Windows-only, but unavailable to Swift) | readers/writers | xlsx |

---

## 6. macOS ADAPTATION NOTES

### 6.1 Overall structure (suggested)
```
Services/  MaritimeIcons.swift  HexColor.swift  ShippalmReader.swift  PortCallReader.swift  PortsService.swift
           XlsxReader.swift (shared)  XlsxWriter.swift (shared)  LegacyDate.swift (ParseDate/NormDate/NormTime/ExcelDate/LocalDate)
Models/    QuickCard.swift  ShipJob.swift  PortCall.swift  Port.swift  PortVisit.swift  (+ Vessel fields)
Views/     VesselDetailView  (tabs: Quick Cards | Work Orders | Ports | Notes | Relationships)
           QuickCardsCanvasView  QuickCardView  QuickCardEditorSheet  WebLinkPromptSheet
           WorkOrdersView (+ WorkOrdersViewModel @Observable)  VesselPortsView  PortsDatabaseView
```
* Keep pure logic (readers, merge, sort, filter, due maths, summary strings) in UI-free types so it can be unit-tested (§7).
* The Swift models must decode with the defaults of §4.2 (`decodeIfPresent ?? default`, null → default) and should round-trip
  unknown keys, e.g. by holding `[String: JSONValue]` extras.

### 6.2 Quick Cards on macOS
* **Canvas:** a SwiftUI `ScrollView([.horizontal, .vertical])` containing a `ZStack(alignment: .topLeading)` sized per
  `SizeCanvas`, with each card placed via `.offset(x:y:)` (top-left origin, Y down, same as WPF). An AppKit alternative is
  `NSScrollView` + a flipped `NSView` (`isFlipped = true`). **1 WPF DIP = 1 macOS point.** Store coordinates unchanged so layouts
  look the same on both platforms.
* **Card look:** `RoundedRectangle(cornerRadius: 10, style: .continuous)` filled with the card colour (alpha honoured), with a 1 pt
  `separatorColor`-style stroke (the Mac analogue of `BorderB`). Icon via `Text(icon).font(.system(size: iconSize))`, rendered as
  colour emoji, so the readable foreground only affects the title and grip. The title is `.font(.system(size: 13, weight: .bold))`,
  `.multilineTextAlignment(.center)`. Hover: a subtle shadow or lift. While dragging: a slightly larger shadow and 0.95 opacity.
  Spring animation on drop. Tooltip via `.help(tooltipText)`. Pointing-hand cursor on hover (`NSCursor.pointingHand`) and the
  NW-SE resize cursor on the grip (`NSCursor.frameResize(position: .bottomRight, directions: .all)` on macOS 15+).
* **Gestures:** `DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))` on the body, with a separate `DragGesture` on
  the grip. Detect double-click with `.onTapGesture(count: 2)` placed with `.simultaneousGesture`, or handle `NSEvent.clickCount`
  in an AppKit view, which is more reliable alongside dragging. Keep the Windows semantics: clamp ≥ 0, no max, grip minimum
  90×64, save on mouse-up (even with no movement, which is harmless) and on resize end.
* **Context menu:** `.contextMenu { Open; Edit…; Duplicate; Divider; Delete… }`. Mac text uses `…` (U+2026) in place of `...`,
  which is an acceptable Mac-ism, but keep the same words.
* **Opening targets:** `NSWorkspace.shared.open(URL)`. Files go to the default app, folders to **Finder** (the Mac equivalent of
  Explorer), URLs to the default browser. For file targets build `URL(fileURLWithPath:)`. For web links use `URL(string:)`. If the
  text has no scheme (e.g. `www.example.com`), prepend `https://`, which matches Windows shell URL guessing. Existence check:
  `FileManager.fileExists(atPath:isDirectory:)`. On `open` returning false, show the **Open failed** alert.
* **Windows paths on the Mac:** `C:\…` and `\\server\share\…` targets will not exist. Show the standard `Not found:\n{path}`
  alert. Recommended enhancement (§9 Q4): a **per-device path-mapping table** in Mac-local settings, mapping Windows prefixes to Mac
  mount points (e.g. `\\fileserver\ships` → `/Volumes/ships`, `F:\` → `/Volumes/Data`). It is applied **at open time only, never
  written back** into `Target`. For UNC paths with no mapping, offer "Connect to Server…" (open `smb://server/share` via
  NSWorkspace, which mounts it), then retry via the `/Volumes/<share>/…` mapping. Never rewrite the stored Target automatically.
* **Sandbox:** in-place file and folder links need persistent access. Recommended: ship **non-sandboxed** (Developer ID +
  notarisation), because live network-drive links are a core capability. If sandboxed, store **security-scoped bookmarks in a
  Mac-local side store** (e.g. `<AppFolder>/mac-bookmarks.plist`, keyed by `QuickCard.Id` + target path). **Never** store them in
  `data.json`: Windows would drop the unknown key, and the bookmark is machine-bound anyway.
* **Imported copies:** `<AppFolder>/files/<32 lower-hex>_<name>` with a forward-slash relative Target, exactly as §3.1.10. The Mac
  AppFolder location (e.g. `~/Library/Application Support/AA`, overridable by `AA_DATA_DIR`) is defined by the persistence spec.
* **Quick Look (optional enhancement):** Space on a focused file card → `QLPreviewPanel` preview. It does not replace
  double-click-to-open.
* **Drag-in (optional enhancement):** dropping a Finder file, folder or URL onto the canvas could open the editor pre-filled.
  Following the file bank convention, a plain drop imports a copy and Option-drop links in place. This is not in Windows, so it is
  optional and marked as an enhancement.

### 6.3 Quick Card editor on macOS
* Present as a **sheet** on the main window (same modality). The layout follows §VESSEL-040 at about 660×600. Fixed size is fine.
* `TextField("Title")` focused on appear (`@FocusState`). A read-only target field (`Text` with `.textSelection(.enabled)` in a
  rounded field style) plus a secondary-coloured kind label.
* Four target buttons with SF Symbols **plus** keeping the emoji-prefixed labels (e.g. `🔗 Link file (in place)`), or use the
  SF Symbols `link`, `doc.on.doc`, `folder`, `globe` with the same words.
  * **Link file** → `NSOpenPanel` (files only, `message: "Link a file in place (no copy)"`).
  * **Import a copy** → `NSOpenPanel` (`message: "Import a copy of a file"`). Copy immediately with `FileManager.copyItem`
    (remove any existing destination first, to emulate overwrite).
  * **Link folder** → `NSOpenPanel` (`canChooseDirectories = true, canChooseFiles = false`,
    `message: "Link a folder (opens in Explorer)"`). Mac wording may say "Finder", see §9 Q6.
  * **Web link…** → a small sheet (`Web link` / `URL:` / prefilled `https://`, selected). Return = OK, Esc = Cancel.
* **Icon grid:** `LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))])` in a 116 pt tall scroll box. `.help(name)` per icon. It
  is OK to highlight the current icon.
* **Colours:** 20 swatches (28 pt circles or rounded squares, `.help(hex)`), plus `Custom colour…` → `NSColorPanel` or SwiftUI
  `ColorPicker(supportsOpacity: false)`. **Convert the result to sRGB** (`NSColor.usingColorSpace(.sRGB)`) before extracting
  components. Round `component × 255` and format `"#FF%02X%02X%02X"`.
* **Width/Height:** `TextField` with the same accept/ignore rules (≥80 → min 900; ≥60 → min 700). No error UI. A `Stepper` may be
  added, as long as it respects the same bounds.
* **Preview:** 190×130 rounded card, icon 40 pt, title 14 bold, `(untitled)` placeholder, plus the tip text.
* **Buttons:** `Cancel` (`.keyboardShortcut(.cancelAction)`) and `OK` (`.keyboardShortcut(.defaultAction)`, prominent). Live-edit
  and revert semantics as in VESSEL-022: either edit a copy and commit on OK, or edit live and restore the snapshot on cancel. Both
  are acceptable as long as the canvas behaves identically after OK/Cancel and **nothing is saved on Cancel**.

### 6.4 Work Orders on macOS
* **Container:** a vertical stack of toolbar area, notifications banner, summary, then a `Table`. Place the actions in the window
  toolbar when the Work Orders tab is active, or in an in-content toolbar row. A `ToolbarItemGroup` with `ControlGroup`s works well:
  * `Import Shippalm…` (SF `square.and.arrow.down`), `Export…` (`square.and.arrow.up`);
  * search field (`.searchable` or `NSSearchField` with placeholder `Search job no / title / function...`), with a 200 ms debounce
    (`Task.sleep` cancellation or `AsyncStream` debounce);
  * `Picker`s in menu style for Status/Category/Rank/Show, using the exact item labels `(all statuses)` etc. and `All`,
    `Active only`, `Completed only`;
  * `Toggle(.button)` for `Due/overdue only` and `Notify on only`;
  * buttons `✓ Mark completed`, `↺ Mark active`, `🗑 Delete`, `🔔 shown ON`, `🔕 shown OFF`. SF Symbols `checkmark.circle`,
    `arrow.uturn.backward`, `trash`, `bell.fill`, `bell.slash` may be added. Keep the words and tooltips (`.help`).
* **Table:** SwiftUI `Table(rows, selection: $selection /* Set<JobNo-lowercased> */, sortOrder: $sortOrder)` with the 11 columns
  and widths of VESSEL-109. Table rows are lazily materialised, which covers 2,500+ rows. If profiling shows hitches, use an
  `NSTableView` wrapper. Implement sorting with **custom comparators** reproducing §VESSEL-111 exactly: the JobNo tiebreak,
  `Due`'s two-key order, and OIC ordinal compare. The initial sort is `Due` ascending. Clicking a new header sorts ascending and
  clicking the same one toggles, which matches `Table` defaults.
  * Done / Notify cells: `Toggle("", isOn:)` checkboxes with `.help` tooltips. Wire the side-effects of VESSEL-112/113, including
    the debounced save.
  * Title cell: `.strikethrough(job.isCompleted)`. Due cell: bold, coloured with the fixed hex colours, `.lineLimit(nil)`.
  * `.contextMenu(forSelectionType:)` with the 7 entries of VESSEL-118. With an empty selection (right-click on blank area) the
    selected-or-shown actions apply to all shown rows.
  * Keyboard (Mac enhancements, none conflict with global shortcuts): ⌘A select all (native), ⌫/⌦ → Delete (same confirmation),
    Space → toggle Done on the selection (optional).
* **Notifications banner:** a rounded `PanelAlt`-style box with a **3 pt coloured bottom edge** (or leading bar) in
  Gray/Green/Orange/Red. `Toggle("🔔 Notifications for this ship", isOn:)` with `.help(...)`, and wrapped text in the state colour
  (the theme label colour in state 2). The text strings are exact.
* **Busy state:** while importing, show a `ProgressView` (small, in the toolbar or an overlay) and replace the summary text with
  `Reading Shippalm export… (large files take a few seconds)`. Disable the import button. Parse in `Task.detached`, then apply on
  `@MainActor`.
* **Alerts:** `NSAlert` (or `.alert`) as a window-modal sheet. Map the WPF caption to `messageText` and the body to
  `informativeText`. Destructive confirmations use a `.destructive` role button. For parity the **body text is exact**. Buttons
  `Yes`/`No` may be rendered as Mac verbs (`Delete`/`Cancel`) with the same meaning.
* **Status hints:** post to the main window's status line (the Mac equivalent of `StatusBlock`, e.g. a footer `Text` in the window).
  If the view is in a window without one, drop it silently or show it in that window's footer.
* **File dialogs:** `NSOpenPanel.allowedContentTypes = [UTType(filenameExtension: "xlsx")!]`. To honour "All files (*.*)", set
  `allowsOtherFileTypes = true` or omit types behind an accessory toggle. `NSSavePanel` with
  `nameFieldStringValue = "WorkOrders-\(safe).xlsx"` and `allowedContentTypes = [.xlsx]`. After export,
  `NSWorkspace.shared.open(url)` (Excel or Numbers), ignoring failure.
* **Dark mode:** the due colours are fixed hex in both appearances, matching Windows. Everything else uses semantic system colours
  (`labelColor`, `secondaryLabelColor` for Muted, `separatorColor` for BorderB, `controlBackgroundColor` for PanelAlt). The
  Windows light theme renders Muted as pure black. Using `secondaryLabelColor` on the Mac is an accepted native improvement.
* **No system notifications** by default (VESSEL-121). A later decision may add `UserNotifications` for flagged overdue jobs,
  respecting `NotificationsEnabled` (§9 Q7).

### 6.5 Ports (per vessel) and Ports Database on macOS
* **Per-vessel Ports:** the same toolbar pattern (`Import ports…`, `Export…`, search, `🗑 Delete`), a summary text, and a `Table`
  with 10 columns, multi-select and sort semantics per VESSEL-208 (including the `Special measures` quirk: sort by arrival, toggle
  the direction). The Mac may add `.contextMenu` with `Delete…` and ⌫, which is additive.
* **Ports Database tab:** `HSplitView` (or `NavigationSplitView` with a sidebar) with a left column of 320 pt ideal width,
  resizable. Left: header `⚓ Ports Database` (SF `ferry`/`anchor` optional), description, `.searchable` field, `List(selection:)`
  of ports showing `Display` plus a trailing `"{n} visits"` in `.caption` secondary, and a status text footer. Right: header
  `⚓ {Display}   —   {n} visit(s)` and a read-only `Table` with Vessel / Arrival / Departure / Imported.
* **Live refresh:** with SwiftUI `@Observable` models, the DB view can re-derive whenever `ports` changes, which is a strict
  improvement because the Mac may show it in a separate window at the same time. Keep the selection-by-Id retention rule.
* **Import:** as for Shippalm (background parse, progress, NSAlert texts). The different-vessel prompt is a two-button alert
  (`Import Anyway` / `Cancel` may be used as Mac labels) with the exact body text.

### 6.6 XLSX reading and writing (no ClosedXML on the Mac)
* **Reading:** use an OOXML reader. Options:
  * **CoreXLSX** (MIT; brings ZIPFoundation + XMLCoder);
  * an in-house reader: ZIPFoundation, or Apple's `Compression` framework for raw DEFLATE plus a minimal ZIP central-directory
    parser, then `XMLParser` over `xl/workbook.xml`, `xl/_rels/workbook.xml.rels`, `xl/sharedStrings.xml`, `xl/styles.xml` and
    `xl/worksheets/sheetN.xml`.
  The reader must provide:
  1. Sheets in **workbook order** (`<sheets>`), resolved via rels. Pick the first sheet with any non-empty cell.
  2. Cell values by `t`: `s` (shared string, concatenating all `<t>` in `<si>` including rich runs `<r>`, ignoring `<rPh>` phonetic
     runs), `inlineStr` (`<is>`), `str` (formula string result), `b`, `e`, `d` (ISO date), `n`/absent (number).
  3. **Date detection** from `styles.xml`: `cellXfs[s].numFmtId`. Built-in date/time ids are 14–22, 27–36, 45–47 and 50–58. For
     custom ids, read `numFmts`: strip `"…"` literals, `\x` escapes and `[…]` sections other than elapsed `[h]`/`[m]`/`[s]`. If
     `y`, `d`, `h` or `s` remains, or `m` outside a pure-number context, treat it as a date/time. Time-only or elapsed formats
     (ids 18–21, 45–47, or custom with only h/m/s) render as `HH:mm` for the ports reader. Number → date via the 1900 epoch
     `1899-12-30` (`FromOADate` semantics). Honour `date1904` (+1462 days).
  4. Merged regions: only the anchor has a value, which matches ClosedXML. No special handling is needed.
  5. Used-range bounds from non-empty values (§3.3.1).
  Then implement the two `Cell` renderers exactly: §3.3.2 (ports) and §3.4.1 (Shippalm).
* **Writing:** extend the shared minimal SpreadsheetML writer (the Mac port of `Services/XlsxWriter.cs`) to support:
  * a per-cell type (text vs number): Shippalm `Overdue Days` must be numeric;
  * a bold header row;
  * a text number format (`numFmtId 49`, `@`) on specific columns (I and N of the Shippalm export);
  * column widths;
  * sheet names `report` and `Ports of Call`.
  Use shared or inline strings. Store text exactly and never auto-convert date-looking strings to dates. Deflate with
  ZIPFoundation or `Compression` (`COMPRESSION_ZLIB` produces raw DEFLATE, suitable for ZIP method 8).
* Files written by the Mac must open in Excel (Windows and Mac) and must re-import on Windows via ClosedXML with identical results.

### 6.7 Dates and numbers in Swift
* `LocalDate(y, m, d)` value type for all "today" and due maths. Formatters use `Locale(identifier: "en_US_POSIX")`,
  `Calendar(identifier: .gregorian)` and `TimeZone.current`, with `yyyy-MM-dd` and `yyyy-MM-dd HH:mm`.
* Port `CrewMember.ParseDate` faithfully (shared with the crew spec): exact `yyyy-MM-dd`, `yyyy/MM/dd` and `yyyy.MM.dd` (2-digit M
  and d), then an **invariant-culture fallback** emulating .NET `DateTime.TryParse(InvariantCulture)` for at least: `M/d/yyyy`,
  `M/d/yy` (.NET 8+ two-digit-year window: 00–49 → 20xx, 50–99 → 19xx, per the Gregorian `TwoDigitYearMax=2049`; verify against
  the crew spec's shared parser), `yyyy-M-d`,
  `yyyy/M/d`, ISO `yyyy-MM-ddTHH:mm[:ss[.fff]][Z|±hh:mm]` (date part only, with **no** time-zone conversion), `d MMM yyyy`,
  `MMM d, yyyy`, `d MMMM yyyy`, `MMMM d, yyyy`, `dddd, dd MMMM yyyy`, each with an optional trailing time `H:mm[:ss]` or
  `h:mm[:ss] tt`. English month and day names are case-insensitive. Anything else → nil.
* NormDate step 4 uses the same fallback.
* `.NET "0.####"` for the ports Number cell: round to 4 decimals (half away from zero), trim trailing zeros and the dot, use
  invariant digits, and keep a `-` sign. `-0` → `0`.
* Shippalm Number cell: whole → `String(Int64(d))`. Else the shortest round-trip, using .NET's exponent style (`1E-05`, `1E+16`) when
  Swift's `"\(d)"` would produce `1e-05`. Convert `e` → `E` and pad the exponent to at least 2 digits with an explicit sign.

### 6.8 Shortcut and command mapping
| Windows | Mac |
|---|---|
| Dialog Enter (OK) / Esc (Cancel) | Return / Esc (`.defaultAction` / `.cancelAction`) |
| Ctrl-click / Shift-click multi-select | ⌘-click / ⇧-click (native Table) |
| Global Ctrl+Z (undo last trashed item) | ⌘Z maps to the global undo-last-delete (spec'd elsewhere). **It does not undo** quick-card, job or port deletions (VESSEL-285) |
| Ctrl+1..9 main tabs (includes "Ports") | ⌘1..⌘9 per the main-window spec |
| Search boxes (no shortcut) | ⌘F focuses the current panel's search field (additive) |
| — | Optional menu commands (a "Vessel" menu or the File ▸ Import submenu): *Import Shippalm Work Orders…*, *Import Ports of Call…*, *Export Work Orders…*, *Export Ports of Call…*, *New Quick Card*. Enabled when a vessel is selected. Do not bind ⌘N, ⌘O or ⌘R, which the global spec owns |

### 6.9 Things that are impossible or different on macOS, and the closest faithful alternative
| Windows capability | Mac status | Alternative |
|---|---|---|
| Opening `\\server\share\file` UNC links directly | no UNC namespace | Path-mapping table plus `smb://` connect, with the Target left unchanged (§6.2) |
| Drive-letter targets `F:\…` | no drive letters | Same mapping table. Otherwise "Not found" |
| "Opens in Explorer" | Finder | `NSWorkspace.open(folderURL)` opens a Finder window. `activateFileViewerSelecting` is an alternative for "reveal" |
| Opening the exported xlsx "with Excel" | depends on the default app (Excel or Numbers) | `NSWorkspace.open`. Failures are ignored, as on Windows |
| WinForms ColorDialog custom colours | NSColorPanel | Convert to sRGB, force alpha FF |
| Wait cursor | discouraged on the Mac | ProgressView and disabled controls |
Nothing in this subsystem is genuinely impossible.

---

## 7. TEST VECTORS / VERIFICATION

Today is assumed to be **2026-09-29** (local) where relevant.

### 7.1 `NormDate`
| Input | Output |
|---|---|
| `15/07/2026` | `2026-07-15` (day-first) |
| `01/07/2026` | `2026-07-01` |
| `5.7.26` | `2026-07-05` |
| `1/2/99` | `2099-02-01` (y<100 → +2000, no pivot) |
| `2026-7-5` | `2026-07-05` |
| `2026-07-15 22:00` | `2026-07-15` |
| `15/07/2026 22:00` | `2026-07-15` |
| `07/15/2026` | `2026-07-15` (step 2 invalid month 15 → invariant month-first) |
| `03/04/2026` | `2026-04-03` (step 2 day-first wins) |
| `Jul 15, 2026` | `2026-07-15` |
| `2026-02-30` | `2026-02-30` (invalid everywhere → returned verbatim) |
| `  ` / `` | `` |
| `TBC` | `TBC` |
| `15/07/202` | `0202-07-15` (3-digit year accepted literally) |

### 7.2 `NormTime`
| Input | Output |
|---|---|
| `22:00` | `22:00` |
| `9:05` | `09:05` |
| `00:01` | `00:01` |
| `22:00:59` | `22:00` |
| `1899-12-30 22:00` | `22:00` |
| `123:45` | `23:45` (first match starts at index 1) |
| `2200` | `` |
| `` | `` |

### 7.3 `SplitPort`, keys, displays
* `Hong Kong, Hong Kong S.A.R.` → (`Hong Kong`, `Hong Kong S.A.R.`). `A, B, C` → (`A, B`, `C`). `Singapore` → (`Singapore`, ``).
  ` Bonny ,Nigeria ` → (`Bonny`, `Nigeria`).
* `PortCall{PortName:"Bonny", ArrivalDate:"2026-07-15"}.Key` = `bonny@2026-07-15`.
* `Port.Display`: (Bonny, NGBON, Nigeria) → `Bonny (NGBON), Nigeria`. (Bonny, "", Nigeria) → `Bonny, Nigeria`. (Bonny, NGBON, "")
  → `Bonny (NGBON)`. (Bonny, "", "") → `Bonny`.
* `PortVisit{VesselName:"BW Pavilion Aranda", ArrivalDate:"2026-07-15", ArrivalTime:"22:00"}.VisitKey` =
  `bw pavilion aranda|2026-07-15|22:00`.
* `PortCall.DisplayName`: (Bonny, Nigeria) → `Bonny, Nigeria`. (Bonny, "") → `Bonny`.
* `ArrivalDisplay`: ("2026-07-15", "") → `2026-07-15`. ("2026-07-15", "22:00") → `2026-07-15 22:00`.

### 7.4 Layout A sample → `PortCallReader.Read`
* `Format = "Last Ports of Call (2 years)"`, `VesselName = ""`, `Imo = ""`, `CallSign = ""`, **47 calls** (row 53 skipped).
* Call 1: `{PortName:"Bonny", Country:"Nigeria", UnLocode:"", ArrivalDate:"2026-07-15", ArrivalTime:"", DepartureDate:"2026-07-17", DepartureTime:"", SecurityLevelPort:"1", SecurityLevelVessel:"1", SspFollowed:"YES", SpecialMeasures:""}`.
* Call 12: `Portland`, `United Kingdom`, `2026-02-13`, `2026-02-14`, `1`, `1`, `YES`, `Bunker barge 'Monjasa Promoter'`.
* Call 24: `Hong Kong`, `Hong Kong S.A.R.`, `2025-09-16`, `2025-09-17`.
* Call 42: `Brunsbuttel`, `Germany`, `2024-11-01`, `2024-11-04`, sec `""`/`""`, `YES`, special `ArrPurpose:` (trimmed from `ArrPurpose: `).
* Call 47: `Ceuta`, `Spain`, `2024-07-29`, `2024-07-29`, `""`, `""`, `YES`, `ArrPurpose: DO Bunkering`.
* All 47 `(lower(name), date)` keys are distinct. Every call's `ImportedAt` has the same `yyyy-MM-dd HH:mm` stamp.

### 7.5 Layout B sample → `PortCallReader.Read`
* `Format = "Port of Call List (last 10 ports)"`, `VesselName = "BW PAVILION ARANDA"`, `Imo = "9792606"`, `CallSign = "9V6330"`, **10 calls**
  (footer row 18 skipped). `Country` and `SspFollowed` are `""` and `SpecialMeasures` is `""` for all.

| # | PortName | UnLocode | PortFacility | PfNo | SecP | SecV | ArrDate | ArrTime | DepDate | DepTime |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Bonny | NGBON | | | SL 1 | SL 1 | 2026-07-15 | 22:00 | 2026-07-17 | 13:00 |
| 2 | Montevideo | UYMVD | | | SL 1 | SL 1 | 2026-07-01 | 14:20 | 2026-07-01 | 18:45 |
| 3 | Escobar LNG | ARBDE | | | SL 1 | SL 1 | 2026-06-29 | 16:25 | 2026-06-30 | 22:35 |
| 4 | Savannah | USSAV | Savannah Port Area | 0001 | SL 1 | SL 1 | 2026-06-13 | 08:46 | 2026-06-14 | 08:06 |
| 5 | Eemshaven | NLEEM | Eemshaven: Eems Energy Terminal | 0039 | SL 1 | SL 1 | 2026-06-01 | 00:01 | 2026-06-03 | 01:15 |
| 6 | Corpus Christi | USCRP | Corpus Christi Port Area | 0001 | SL 1 | SL 1 | 2026-05-15 | 10:00 | 2026-05-16 | 07:20 |
| 7 | Algeciras | ESALG | Zonas de Fondeo | 0014 | SL 1 | SL 1 | 2026-05-01 | 06:00 | 2026-05-02 | 17:15 |
| 8 | Enez | TRENE | | | SL 1 | SL 1 | 2026-04-25 | 00:01 | 2026-04-26 | 17:15 |
| 9 | Freeport | USFPO | | | SL 1 | SL 1 | 2026-04-03 | 23:00 | 2026-04-04 | 12:28 |
| 10 | Dunkerque | FRDKK | DUNKERQUE LNG SAS | 0117 | SL 1 | SL 1 | 2026-03-20 | 21:00 | 2026-03-22 | 18:24 |

### 7.6 `PortsService.Apply` / `RemoveCall` scenarios (vessel `V` = "BW Pavilion Aranda", empty DB)
1. **Import A** → returns `(47, 0, 47)`. The DB has **36 ports, 47 visits**. Multi-visit ports: Corpus Christi/United States 4,
   Barrow Island/Australia 4, Savannah/US 2, Singapore 2, Hong Kong/Hong Kong S.A.R. 2, Incheon/South Korea 2, Rotterdam/Netherlands 2.
   `Freeport, United States` and `Freeport, Bahamas` are **two separate ports**. Every port has `UnLocode ""`.
2. **Then import B** into the same vessel. There is **no** different-vessel prompt: the file's `BW PAVILION ARANDA` equals
   `BW Pavilion Aranda` case-insensitively. Returns `(0, 10, 0)`. The DB still has 36 ports and 47 visits. The Bonny call becomes
   `{Country:"Nigeria", UnLocode:"NGBON", ArrivalTime:"22:00", DepartureTime:"13:00", SecurityLevelPort:"SL 1", SecurityLevelVessel:"SL 1", SspFollowed:"YES"}`.
   The Bonny port gets `UnLocode "NGBON"`. Its visit gets `ArrivalTime "22:00"`, `DepartureTime "13:00"` and `VesselId`
   preserved. The B `Freeport` (no country) attaches to **`Freeport, United States`**, the first in list order, which gains `USFPO`.
3. **Re-import B** → `(0, 10, 0)`, idempotent. Re-import A → `(0, 47, 0)`, and the security levels revert to `1` (last non-empty
   import wins).
4. **Reverse order** (fresh): B → `(10, 0, 10)`, 10 ports with UN/LOCODE and no country. Then A → `(37, 10, 37)`. The DB ends at 36
   ports and 47 visits. `Freeport, United States` matches the existing `Freeport` (country empty → compatible) and sets its country.
   `Freeport, Bahamas` now mismatches the country and creates a new port. Bonny ends with `SecurityLevelPort "1"` (A imported last).
5. **Different vessel:** importing B into a vessel named `Other` → the prompt body is
   `This file lists vessel "BW PAVILION ARANDA", but you're importing into "Other".\n\nImport these 10 port call(s) for Other anyway?`.
   No → nothing changes.
6. **RemoveCall** after scenario 2: delete the Bonny call → its visit (`bw pavilion aranda|2026-07-15|22:00`) is removed and the
   Bonny port has 0 visits, so it is pruned. The DB has **35 ports, 46 visits**.
7. **Rename quirk:** after scenario 2, rename V to `Aranda`, then delete the Montevideo call → `vk = "aranda|2026-07-01|14:20"` ≠ the
   visit key `"bw pavilion aranda|…"`, so the visit **remains**. The DB still has 36 ports.
8. **Same-day cross-port quirk:** V has calls X@2026-01-01 (no time) and Y@2026-01-01 (no time). Deleting X also removes Y's visit,
   and Y's port is pruned if it is now empty.

### 7.7 Ports export → re-import (lossy quirk)
Export the vessel from scenario 2, then import that file into a fresh vessel. Detection gives **B**: `UN/LOCODE` in row 1 sets
`looksB`, there is no `un locator`, so row 1 is the sub-header and the empty category row 0 maps nothing. Port-name falls back to
column A. The reader returns **47 calls** with only `PortName` set (`ArrivalDate ""`, everything else `""`). Keys collapse per
lower-cased name (`"{name}@"`). The sample has **35 distinct names**, because `Freeport` appears twice (United States and Bahamas).
Expected `Apply` result: **`(added 35, updated 12, newVisits 35)`**. Each new date-less call attaches a visit with
`ArrivalDate ""` to the first existing port of that name.

### 7.8 Shippalm `ExcelDate` / `ParseBool` / `Overdue Days`
| Raw | ExcelDate |
|---|---|
| `48108` | `2031-09-17` |
| `46218` | `2026-07-15` |
| `45000` | `2023-03-15` |
| `20001` | `1954-10-04` |
| `15000` | `15000` (outside the window, kept raw) |
| `2026-07-15` | `2026-07-15` |
| `2026/07/15` | `2026-07-15` |
| `07/15/2026` | `2026-07-15` (invariant month-first) |
| `03/04/2026` | `2026-03-04` (**month-first trap**, replicate) |
| `15/07/2026` | `15/07/2026` (unparseable → raw → Due shown grey) |
| `` | `` |

`ParseBool`: `Yes`, `yes `, `TRUE`, `true`, `Y`, `1` → true. `No`, `0`, `FALSE`, `on`, `` → false.
`Overdue Days`: `12` → 12. `-3` → −3. `12.0` → 12. `12.5` → 0. `1,234` → 1234. `abc` → 0.

### 7.9 Shippalm header detection
* Row with `No.` + `Title` in row 3 of the used range → header = row 3. `No` (no dot) → **not** recognised and it throws.
* Header cell `Work Order\nStatus` normalises to `work order status` and maps to Status. `Due  Date` (double space) → `due date`.
* Two `Title` columns → the first one wins.
* An empty workbook → `[]`, and the panel status reads `Imported 0 work orders for {V} (0 new, 0 updated).`

### 7.10 Upsert
Existing: `[{JobNo:"ARA.1", Notify:true, IsCompleted:true, CompletedDate:"2026-09-01", Title:"Old"}]`. File rows:
`ara.1 / New title / Notify=No`, `ARA.2 / Notify=Yes`, `ARA.2 / Title B`.
Result: `ARA.1` is updated in place → `JobNo "ara.1"`, `Title "New title"`, `Notify true`, `IsCompleted true`,
`CompletedDate "2026-09-01"`. `ARA.2` is added with `Notify true`, then updated by the duplicate row to `Title "Title B"` with
`Notify true` kept. Counts: `added 1, updated 2`, status `Imported 3 work orders for {V} (1 new, 2 updated).`

### 7.11 DueInfo / days (today 2026-09-29)
| DueDate | IsCompleted | CompletedDate | Text | Colour |
|---|---|---|---|---|
| 2026-09-28 | no | | `OVERDUE 1d  (2026-09-28)` | Red |
| 2026-09-29 | no | | `DUE TODAY  (2026-09-29)` | Red |
| 2026-10-29 | no | | `in 30d  (2026-10-29)` | Orange |
| 2026-10-30 | no | | `in 31d  (2026-10-30)` | Amber |
| 2026-12-28 | no | | `in 90d  (2026-12-28)` | Amber |
| 2026-12-29 | no | | `2026-12-29  (in 91d)` | Green |
| `` | no | | `` | Gray |
| `15/07/2026` | no | | `15/07/2026` | Gray |
| 2026-01-01 | yes | `2026-09-20` | `✓ completed 2026-09-20` | Green |
| 2026-01-01 | yes | `` | `✓ completed` | Green |
DST check: with today 2026-03-28 and due 2026-03-30 in a zone with a DST change on 03-29 → **2** days, not 1.

### 7.12 Summary and notifications (today 2026-09-29)
Jobs:
* J1 due 2026-09-20, Notify, active;
* J2 due 2026-10-10, Notify, active;
* J3 due 2026-12-01, active;
* J4 due 2026-09-01, Notify, **completed**;
* J5 no date, category blank;
* categories: J1–J3 `ROUTINE`, J4 `CBM`.

Summary (unfiltered, 5 shown):
```
⚙ 5 work orders   ·   ⚠ 1 overdue   ·   1 due ≤30d   ·   2 due ≤90d   ·   ✓ 1 completed   ·   🔔 3 notify-on   ·   showing 5
By category: ROUTINE 3   CBM 1   (none) 1
```
Bar (enabled): flagged = J1, J2. Overdue = [J1 (−9)] and dueSoon = [J2 (11)], so it is Red:
`⚠ 2 flagged work order(s) need attention — 1 overdue, 1 due ≤30d:  J1 (overdue 9d),   J2 (in 11d)`
Disabled: `Off — turn on to track this ship's due / overdue work orders here.` (Gray).
Flagged but none within 30 days (e.g. only J3 with Notify) → Green `On — 1 flagged job(s), all clear (none due within 30 days).`

### 7.13 Filters and sort
* `Due/overdue only` over the set above → J1, J2, J3 (J4 is completed, J5 has no date).
* `Notify on only` → J1, J2, J4.
* `Completed only` → J4.
* Default sort (`Due` ascending) → J1 (−9), J2 (11), J3 (63), J5 (no date = MaxValue), J4 (completed last). Descending → J4, J5,
  J3, J2, J1.
* Ties: two jobs with the same due date sort by JobNo OIC ascending in **both** directions.
* `Job No.` ascending over `ARA.22.10`, `ara.22.9`, `ARA.22.100` → `ARA.22.10`, `ARA.22.100`, `ara.22.9` (ordinal after uppercasing).
* Ports default (Arrival descending) after scenario 2 → first row Bonny `2026-07-15 22:00`, last row Ceuta `2024-07-29`.

### 7.14 Quick cards
* Add positions for existing counts 0..7 → (24,24), (52,52), (80,80), (108,108), (136,136), (164,164), (24,24), (52,52).
* Icon size: 180×120 → 43.2. 90×64 → 23.04. 300×400 → 108. 200×40 (hand-edited) → 18.
* `SizeCanvas` with one card at (900, 700, 180, 120) → canvas 1120×860. With none → 1000×640.
* Drag clamp: origin (10, 10), mouse delta (−50, +30) → (0, 40).
* Resize from 100×70 by (−30, −30) → 90×64.
* Editor sizes: `50` → ignored (keeps the previous value). `80` → 80. `1200` → 900. Height `59` → ignored. `60` → 60. `800` → 700.
  `abc` → ignored.
* Custom colour RGB(10, 20, 255) → `#FF0A14FF`.
* `ParseColor`: `""` → `#FF1E88E5`. `#1AF` → `#FF11AAFF`. `#80FF0000` → alpha 0x80 red. `Red` → `#FFFF0000`. `bogus` → `#FF1E88E5`.
* Readable foreground: see the §4.7 table (e.g. `#FFFB8C00` → `#1A1A1A`, `#FF7CB342` → white).
* Tooltip for `{Title:"", Target:"", flags all false}` →
  `(untitled)\nImported copy: (no target — right-click ▸ Edit)\nDouble-click to open • drag to move • drag corner to resize`.
* Delete prompt for `{Title:"  ", Icon:"🚢"}` → `Delete quick card '🚢'?`.
* `ImportFile("/Users/x/Manual v2.pdf")` → a `files/[0-9a-f]{32}_Manual v2.pdf` Target and a file present at that path.
* `ResolveFilePath` (Mac): `files/abc_x.pdf` → `<AppFolder>/files/abc_x.pdf`. `C:\Docs\x.pdf` → unchanged. `\\srv\sh\x.pdf` →
  unchanged. `/Volumes/sh/x.pdf` → unchanged. `https://a.b` → unchanged. `mailto:a@b.c` → unchanged.
* Safe file name: `BW Pavilion: Aranda?` → `WorkOrders-BW Pavilion_ Aranda_.xlsx` and `Ports-BW Pavilion_ Aranda_.xlsx`.

### 7.15 JSON round trip (cross-version)
* Decode the Windows-written
  `{"QuickCards":[{"Id":"0b6e…","Title":"PMS","Target":"files/0f…_a.pdf","IsLink":false,"LinkInPlace":false,"IsFolder":false,"Icon":"\u2693","Color":"#FF1E88E5","X":24,"Y":24,"Width":180,"Height":120}],"Jobs":[],"NotificationsEnabled":true,"PortCalls":[]}`
  (vessel fragment). Re-encode it, and Windows must re-read it identically: `Icon` is the same code points, `X` is a number, and the
  Id is lower-case.
* A legacy vessel **without** `NotificationsEnabled` decodes as `true`. A `QuickCard` missing `Icon`/`Color`/`Width` decodes to
  `⚓`/`#FF1E88E5`/180.
* `PortVisit` without `VesselId` decodes as nil and is re-encoded **without** the key.
* `OverdueDays` is encoded as `5`, never `5.0`.

### 7.16 Shippalm export → import round trip
Write 3 jobs (one with `DueDate "2031-09-17"`, `Notify true`, `OverdueDays 12`). Re-read into a new vessel: all 16 exported fields
are equal, `Notify` true, and `IsCompleted` false (not exported). In the xlsx, cell `I2` is a text cell with column style `@`,
cell `O2` is numeric `12` and `P2` is `Yes`. The sheet is named `report` and row 1 is bold.

---

## 8. Verification checklist for the Mac build (quick reference)
1. Selecting a vessel lands on **Quick Cards**. The three tabs are absent for other kinds.
2. Cards: drag clamps at 0, grip minimum 90×64, immediate save on release, double-click opens, context menu order, delete prompt
   text, duplicate offset +24, cascade add positions.
3. The editor's four target kinds set the exact flag combinations. The imported copy lands in `files/` with a 32-hex prefix. Cancel
   reverts an edit. Size bounds 80–900 / 60–700.
4. Work orders: header detection, serial dates, the upsert that keeps Notify/Completed, the summary and bar strings, the 200 ms
   search debounce, sort semantics with the JobNo tiebreak, bulk actions on selection-or-shown, delete confirmation, the 16-column
   export.
5. Ports: both samples parse to §7.4/§7.5. The merge scenarios in §7.6 reproduce the exact counts. Delete prunes empty ports. The
   log entry is written.
6. Ports DB: 36 ports and 47 visits after importing A (and B). Display strings. `1 visits`. Selection retention.
7. `data.json` written by the Mac loads in Windows AA unchanged, and vice versa. Lower-case Guids. Integer `OverdueDays`. No extra
   keys inside these objects.

---

## 9. Known quirks and open questions (decide before or while implementing)

| # | Topic | Windows behaviour | Recommendation |
|---|---|---|---|
| Q1 | Work-order export tooltip says "including notify & completion choices" | Only `Notify` is exported. `IsCompleted`/`CompletedDate` are not | Default: exact 16-column parity. Option: add trailing `Completed`/`Completed Date` columns on both platforms together (Windows `Read` ignores unknown columns today, so this is harmless). Do not diverge unilaterally |
| Q2 | Ports export not re-importable | Re-imports as layout B with names only (VESSEL-212) | Replicate. Optionally teach **both** readers a third "AA export" layout later |
| Q3 | `RemoveCall` after vessel rename / same-day cross-port | Wrong visit kept or removed (§3.2.2) | Replicate for parity. A future fix (match by `VesselId` + port + date) must land on both platforms |
| Q4 | In-place links across OSes | Windows paths do not resolve on the Mac and vice versa | Per-device path-mapping table (Mac-local settings), applied at open time only |
| Q5 | Detached vessel shows stale panels | The previous vessel's panels stay visible but disabled | Mac: show the detached vessel's own panels. They do not conflict with the container editor. Or a placeholder. Never show another vessel's data |
| Q6 | Wording "opens in Explorer" | Windows-specific | The Mac may say "opens in Finder" (tooltip and dialog message). All other strings exact |
| Q7 | System notifications for flagged jobs | None (in-panel bar only) | None by default. If added later, gate on `NotificationsEnabled` + `Notify` + `!IsCompleted` |
| Q8 | `1 visits` plural | No singular form | Keep for parity, or pluralise properly on the Mac (cosmetic, no data impact). Decide once for all count strings |
| Q9 | `date1904` workbooks | ClosedXML behaviour not verified | Honour date1904 on the Mac. Such files are rare |
| Q10 | Orphaned imported copies on editor cancel | Left in `files/` | Replicate (no sweep) |
| Q11 | Search placeholders stored in `Tag` | Never rendered on Windows | Render them as placeholders on the Mac (pure improvement) |
| Q12 | `Special measures` header sort | Sorts by arrival, toggles direction | Replicate |
| Q13 | Month-first parsing in `CrewMember.ParseDate` for Shippalm text dates | `03/04/2026` → 4 March | Replicate for parity. Any change belongs to the shared date-parser decision (crew spec) and must be applied on both platforms |

---

## Addendum: One normative AACore XLSX reader contract (09 and 10 currently diverge)

**Status: NORMATIVE.** This addendum is the single contract for reading `.xlsx` files on the Mac. COMPAS crew import
(spec 09), Shippalm work orders (this spec §3.4) and ports of call (this spec §3.3) all read through one shared module,
`AACore/Xlsx`, plus three thin per-reader renderers. Where this addendum disagrees with 09 §3.3, 09 §6.2, 09 §7.7,
10 §3.3.1, 10 §3.3.2, 10 §6.6 or 10 §9 Q9, **this addendum wins** (see §X.2 for the item-by-item ruling). The ground
truth is what **ClosedXML 0.104.2** (the exact version in `AA/AA.csproj:33`) does on the Windows build, read from its
source at git tag `0.104.2`. The target is not "what Excel shows". The target is "what the Windows build persists", because
the rendered strings land verbatim in `data.json` and must match byte for byte when a user moves data between the
two builds.

Feature IDs continue this spec's prefix at **VESSEL-300**. Section numbers use the prefix **X.** so they cannot
collide with §0–§9 above.

### X.0 Sources read for this addendum

| Source | Lines | What it decides |
|---|---|---|
| `AA/Services/CompasReader.cs` | 26-67 `Read`, 32 `RangeUsed`, 70-88 `CellString` | COMPAS sheet choice, bounds, renderer A |
| `AA/Services/ShippalmReader.cs` | 16-82 `Read`, 86-125 `Write`, 136-154 `Cell`, 158-170 `ExcelDate` | Shippalm sheet choice, bounds, renderer B |
| `AA/Services/PortCallReader.cs` | 30-66 `Read`, 208-220 `Cell`, 222-245 `NormDate`/`NormTime` | ports sheet choice, bounds, renderer C |
| `AA/Services/CrewMapping.cs` | 11-17 `CrewText.Norm` | header normalisation shared by COMPAS and Shippalm |
| `AA/Models/CrewMember.cs` | 142-151 `ParseDate` | downstream of renderer B (`ExcelDate`) |
| `AA/Views/CrewPage.xaml.cs` 240-305, `ShipJobsPanel.xaml.cs` 84-130, `PortsPanel.xaml.cs` 30-70 | call sites | file dialogs, error boxes, threading |
| ClosedXML `Excel/XLWorkbook_Load.cs` | 133-135 (`date1904`), 186-189 (styles), 208-265 (sheet passes), 313-320 (merges), 364-448 (tables), 1122-1248 `LoadCell`, 1350-1416 `SetCellValue` + `DateCellFormats`, 1424-1470 `SetCellText`, 1473-1549 `LoadRow`, 1608-1680 `GetNumberDataType` / `GetDataTypeFromFormat`, 2537-2639 `ApplyStyle` / `LoadStyle` | typing, strings, 1904, merges, tables |
| ClosedXML `Excel/Cells/XLCell.cs` | 307-317 getters, 497 `GetString`, 542-558 `Evaluate`, 590-602 `Value`, 697 `DataType`, 865 `NeedsRecalculation`, 901-950 `IsEmpty` | what the readers see |
| ClosedXML `Excel/XLCellValue.cs` | 14-80 ctors, 335-343 `GetDateTime`/`GetTimeSpan`/`FromSerial*`, 384-395 `ToString(culture)` | value model, `GetString` text |
| ClosedXML `Excel/Ranges/XLRangeBase.cs` 654-715, 1559-1570, 1930-1975; `Excel/Cells/XLCells.cs` 95-125; `Excel/XLCellsUsedOptions.cs` | `RangeUsed()` default options = `AllContents` | used range |
| ClosedXML `Extensions/DoubleExtensions.cs` 20-28, `DateTimeExtensions.cs` 45-52, `TimeSpanExtensions.cs` 14-45, `XLHelper.cs` 26-27 + 325-330, `Extensions/XLErrorExtensions.cs`, `Utils/XmlEncoder.cs`, `Extensions/StringExtensions.cs` 13 + 50-53 | serial maths, time text, error text, `_xHHHH_`, newline fix-up |
| ClosedXML `Excel/Style/XLPredefinedFormat.cs`, `Excel/Style/XLNumberFormatKey.cs` | built-in id names, custom id = −1 |
| ClosedXML `Excel/XLWorkbook.cs` 482-506, 745-760 | extension gate |
| ClosedXML `Excel/XLWorksheet.cs` 1582-1608, `Excel/Tables/XLTable.cs` 58-110, 533-561, 569-584 | table side effects |
| ClosedXML tests `ClosedXML.Tests/Excel/Loading/LoadingTests.cs` 101-126, 461-489 | confirms 1904 and `TimeSpan` text (`13:30:55.2`, `0:30:55.2`) |
| `AA/POC/Last Ports - 24 Months (4).xlsx`, `AA/POC/Port of Call List - Last 10 Ports (14).xlsx` | inspected part by part (§X.8.9) |
| Specs 09 §3.3, §4.9, §6.2, §7.7, §8 Q7; 10 §3.3.1-3.3.2, §3.4, §6.6-6.7, §7.8, §9 Q9 | the texts being reconciled |

### X.1 Overview

**Purpose.** Turn an `.xlsx` file into a grid of typed cells exactly as ClosedXML 0.104.2 would, then turn each cell
into the exact string that each Windows reader would have produced. The subsystem has no UI of its own. It surfaces in
three places:

| Entry point (user action) | Windows reader | Renderer | Downstream logic (unchanged, owned elsewhere) |
|---|---|---|---|
| Crew tab → **Import COMPAS…** (09 feature D) | `CompasReader.Read` | A `CompasReader.CellString` | 09 §3.3 header search, `CrewConverter`, `DateResolver` |
| Vessel → Work Orders → **Import…** (VESSEL-101) | `ShippalmReader.Read` | B `ShippalmReader.Cell` (+ `ExcelDate`) | §3.4 header map, upsert |
| Vessel → Ports → **Import…** (VESSEL-201/202) | `PortCallReader.Read` | C `PortCallReader.Cell` | §3.3 layout detection, `NormDate`/`NormTime`, `PortsService.Apply` |

The writers (`XlsxWriter`, `ShippalmReader.Write`, `PortsService.Export`) are **out of scope** here. Only their
round-trip into this reader matters (§X.8.7 R-vectors).

**Pipeline (normative layering):**

```
URL ──► FileGate (extension) ──► ZipPackage (in-house, AACore/Zip) ──► XlsxWorkbook
        (VESSEL-301)              (VESSEL-302)                          ├─ worksheets[] in workbook order (VESSEL-303)
                                                                        ├─ Styles: cellXfs[s] → (numFmtId, formatCode)
                                                                        ├─ SharedStrings (plain / rich, phonetic dropped)
                                                                        └─ date1904
XlsxWorksheet (lazy, per sheet) ──► cells[(row,col)] = XlsxCell (VESSEL-305) ──► rangeUsed() (VESSEL-320)
                                                                                 cell(r,c) never nil (VESSEL-321)
Renderer A/B/C (VESSEL-326..328) ──► String ──► reader logic (09 §3.3 / 10 §3.3 / 10 §3.4) ──► model ──► data.json
```

### X.2 Where 09 and 10 diverge, and the ruling

| # | Topic | 09 says (§3.3 / §6.2) | 10 says (§3.3.2 / §6.6) | **ClosedXML 0.104.2 does, so this is normative** |
|---|---|---|---|---|
| D1 | Built-in ids that make a number a **date** | 14–22, 27–36, 45–47, 50–58 | 14–22, 27–36, 45–47, 50–58 (18–21 and 45–47 as time-only) | **DateTime: 14, 15, 16, 22 only.** **TimeSpan: 18, 19, 20, 21, 45, 46, 47.** **Number: everything else**, including **17** (`mmm-yy`), **27–36** and **50–58**, unless the file's `<numFmts>` redefines that id (§X.4.3) |
| D2 | Custom format codes | strip quotes, `\x` escapes and `[…]`, then look for `d`, `y` or month-`m` | strip quotes, `\x` and `[…]` except elapsed, then look for `y`, `d`, `h`, `s` or `m` | **First decisive character wins, scanning left to right:** `0 # ?` → Number; `y d` → DateTime; `h s` → TimeSpan; `m` → look ahead (§X.4.4). `"…"` and `[…]` are skipped (elapsed `[h]` too). **No `\` escape handling.** Nothing decisive → Number |
| D3 | Time-only cell in renderer A (COMPAS default branch) | `HH:mm:ss` | n/a | `GetString()` = `TimeSpan.ToExcelString`: **`H:mm:ss`, hours not padded and not wrapped** (`6:00:00`, `36:00:00`), plus `.f`/`.ff`/`.fff` when milliseconds ≠ 0 (`12:00:00.086`) |
| D4 | Time-only cell in renderer C | n/a | `hh:mm`, hours mod 24 | Confirmed: `TimeSpan.ToString(@"hh\:mm")`, the hours **component** (0–23), zero-padded |
| D5 | 1904 system | epoch 1904-01-01 | +1462 days | **+1462 days to DateTime-typed cells only** (including `t="d"` cells), applied at load. **Not** applied to Number or TimeSpan cells, so Shippalm's `ExcelDate` serial fallback is **never** 1904-corrected. Serials ≤ 60 come out **one day late** (ClosedXML's 1900 leap-year shim runs first) |
| D6 | 1900 leap-year bug | "as Excel does" | `FromOADate` semantics | `v ≥ 61` → `FromOADate(v)`. `v ≤ 60` → `FromOADate(v + 1)`. **`60 < v < 61` throws.** So 59 → 1900-02-28, **60 → 1900-03-01**, 61 → 1900-03-01, 0 → 1899-12-31 |
| D7 | Used range | "cells that have a value (ignore style-only cells)" | "cells whose **rendered** value is non-empty" | Bounding box of cells that are **not `IsEmpty()`**: a non-blank value (any non-Text kind, or Text with length > 0, **including whitespace-only text**), **or a formula**, **or a comment**. Style-only cells and merge areas do not count. Rendering and trimming play no part |
| D8 | Merged cells | "take the top-left value only" | "only the anchor has a value … no special handling" | ClosedXML loads merges with `Merge(false)`, which **clears nothing and propagates nothing**. Every cell reads **its own stored value**. Excel stores values only in anchors, so the result usually matches, but a non-anchor cell that carries a value (some non-Excel writers do this) **is read** and **does extend** the used range |
| D9 | Shared-string text | concatenate all `<t>` incl. runs, exclude `<rPh>` | same | Same, **plus**: `_xHHHH_` escapes are decoded **only** for plain `<si><t>` (never for runs, inline strings or `t="str"`). Rich runs and inline strings get newline fix-up to **CRLF** on Windows (§X.4.6) |
| D10 | Formula cells | cached `<v>`; none → `""` | cached value | Cached value when present. **Without a cached value ClosedXML recalculates** on first read. The Mac cannot, so this is a documented divergence (VESSEL-318) |
| D11 | Errors | error text | literal | Only the 7 classic codes (`#NULL!` `#DIV/0!` `#VALUE!` `#REF!` `#NAME?` `#NUM!` `#N/A`). **Any other code (`#SPILL!`, `#CALC!`, `#GETTING_DATA`, …) loads as an empty cell** |
| D12 | `t="d"` ISO cells | "ISO → date" | "ISO date" | Only 3 exact shapes parse. **Anything else makes the whole workbook fail to open** (VESSEL-317) |
| D13 | Libraries | ZIPFoundation "or" custom | CoreXLSX / ZIPFoundation "or" in-house | `mac/Docs/ARCHITECTURE-BRIEF.md` forbids third-party dependencies, so the reader is **in-house** (AACore ZIP reader + `Compression` + `XMLParser`). The CoreXLSX suggestion in 10 §6.6 is withdrawn |
| D14 | 10 §9 Q9 "ClosedXML behaviour not verified" | — | open | **Resolved** by D5 / VESSEL-310 |

Consequences for existing vectors: 09 §7.7 "date-formatted serial 46096 → `2026-03-15`" holds only when the style's
kind is DateTime (ids 14/15/16/22 or a custom date code). With id 17, 27–36 or 50–58 the same cell renders `46096`.
The rest of 09 §7.7 and every vector in 10 §7.1–§7.16 are unaffected.

### X.3 FEATURE CHECKLIST

**VESSEL-300 — One reader, three adapters.** All three importers read through `AACore/Xlsx` (§X.7.1). No importer
parses XML itself. The only per-reader code is the renderer (VESSEL-326/327/328) and the reader's own header and row
logic (09 §3.3, 10 §3.3, 10 §3.4), which this addendum does not change. A behaviour fix in the shared layer fixes
all three at once. That is the point, and it is why the shared layer must match ClosedXML rather than any one reader's
expectations.

**VESSEL-301 — File gate (extension check).** Before opening, the file name's extension (text after the last `.`,
compared case-insensitively) must be one of `xlsx`, `xlsm`, `xltx`, `xltm`. Otherwise the import fails with the
ClosedXML messages, verbatim:
* no extension → `Empty extension is not supported.`
* any other → `Extension '{ext}' is not supported. Supported extensions are '.xlsx', '.xlsm', '.xltx' and '.xltm'.`
  where `{ext}` is the extension **lower-cased, without the dot** (e.g. `csv`, `xls`).

This matters because all three Windows open dialogs offer `All files (*.*)` (`CrewPage.xaml.cs:244`,
`ShipJobsPanel.xaml.cs:90`, `PortsPanel.xaml.cs:38`). The message appears inside the reader's existing failure box:
`Could not import the COMPAS file:\n\n{msg}`, `Could not import the Shippalm file:\n\n{msg}` or
`Could not import the ports file:\n\n{msg}` (title `Import failed`). The gate checks the **name only**. The content is
not sniffed, so an `.xlsx` that is really a CSV fails later in VESSEL-302. Mac drag-and-drop onto the panels (an
additive nicety) must go through the same gate.

**VESSEL-302 — Package open and corrupt files.** The file is opened read-only as an OPC ZIP package. Main part =
the target of the `officeDocument` relationship in `_rels/.rels` (normally `xl/workbook.xml`). Any structural failure
(not a ZIP, missing workbook part, malformed XML, a `cellXfs` index out of range, an unknown `t` value, a string over
32,767 characters, a `NaN`/`Infinity` number) fails the whole import. Windows shows the library's `ex.Message`, which
has no stable wording. The Mac shows `The file could not be opened as an Excel workbook (.xlsx).` followed by a
one-line detail (10 §3.3.8). The exceptions are VESSEL-301 and the two date-serial messages in VESSEL-309, which are
reproduced verbatim.

**VESSEL-303 — Worksheet enumeration.** `Worksheets` = the `<sheet>` elements of `workbook.xml` `<sheets>` in
**document order**, keeping only those whose relationship resolves to a **worksheet** part. Chart sheets, dialog
sheets and macro sheets are skipped entirely (not counted, not selectable). A `<sheet>` with an empty or missing
`r:id` becomes an **empty** worksheet, kept in order. Visibility (`state="hidden"`/`veryHidden`) is ignored: hidden
sheets are enumerated and selectable. Sheet names compare with ordinal ignore-case.

**VESSEL-304 — Sheet selection policies** (unchanged reader logic, restated so the adapters are complete):

| Reader | Rule | No-data result |
|---|---|---|
| COMPAS | first worksheet whose name equals `report` (ordinal ignore-case), else the first worksheet, **even if empty** | `RangeUsed()` nil → `[]` (what the Crew page then does with zero rows is 09's to define) |
| Shippalm | first worksheet with a non-nil `RangeUsed()`, else the first worksheet | nil → `[]` → `Imported 0 work orders for {V} (0 new, 0 updated).` |
| Ports | first worksheet with a non-nil `RangeUsed()`, else `Worksheet(1)` (position 1) | nil → throw `The workbook is empty.` |

Quirk: if **every** worksheet is empty and workbook position 1 is a chart sheet, Windows `Worksheet(1)` throws
`There isn't a worksheet associated with that position.` The Mac may show `The workbook is empty.` instead. That is
cosmetic, since both fail.

**VESSEL-305 — Typed cell model.** Each cell has exactly one **kind**: `blank`, `text(String)`, `number(Double)`,
`boolean(Bool)`, `error(XlsxErrorCode)`, `dateTime(serial: Double)` or `timeSpan(serial: Double)`, plus two flags,
`hasFormula` and `hasComment`. (Earlier notes call the first kind "Empty". ClosedXML calls it `Blank`, and this
contract uses `blank` so that "empty" can keep its separate `IsEmpty()` meaning in VESSEL-319.) DateTime and TimeSpan
keep ClosedXML's representation: the **serial number**, already shifted for 1904 (VESSEL-310). Calendar values are
computed on demand, and that computation can throw (VESSEL-309), as ClosedXML's `GetDateTime()` does. Any `(row, col)`
not present in the file is a `blank` cell with both flags false.

**VESSEL-306 — Kind from the `t` attribute** (`LoadCell` 1135-1146, `SetCellValue` 1350-1410):

| `t` | `<v>` present | Resulting kind |
|---|---|---|
| absent or `n` | parses as a number (§X.4.5) | `number`, `dateTime` or `timeSpan` according to the cell's style (VESSEL-307/308) |
| absent or `n` | missing, empty, or not a number (e.g. `1,234`, `abc`) | `blank` (no error) |
| `s` | valid index into the shared strings | `text` (VESSEL-312) |
| `s` | index missing, negative or out of range | `text("")` (so `IsEmpty` unless it has a formula) |
| `s` or `str` | no `<v>` | `text("")` |
| `str` | yes | `text(v)` verbatim: no `_xHHHH_` decode, no newline fix-up, no trim |
| `inlineStr` | (value lives in `<is>`) | `text` from `<is>` (VESSEL-313). `<is>` missing → `blank` |
| `b` | yes | `boolean(v == "1" \|\| v equals "TRUE" ignoring case)`. Any other text (`0`, `false`, `yes`) → `false` |
| `b` | no | `blank` |
| `e` | one of the 7 codes (after trimming) | `error` |
| `e` | unknown code or no `<v>` | `blank` |
| `d` | yes | `dateTime` (VESSEL-317) |
| anything else | — | **whole import fails** (`Unknown cell type.`) |

The style never changes a `t="s"`/`str`/`inlineStr`/`b`/`e` cell. Text styled as a date stays text. That is exactly the
case of both POC files (§X.8.9), whose dates are shared strings in cells styled `numFmtId 14` and `20`.

**VESSEL-307 — Numeric kind from built-in number-format ids** (`GetNumberDataType` 1608-1639). Only numeric cells
(`t` absent or `n`) are affected. Take `xf = cellXfs[s]` (`s` absent → 0) and `id = xf@numFmtId` (absent → 0). If
`<numFmts>` has an entry with that id **and a non-empty** `formatCode`, the style is **custom** and goes to
VESSEL-308, even when the id is below 164 (a file may redefine `14`). Otherwise:

| id | ClosedXML name | Kind |
|---|---|---|
| 14 | `DayMonthYear4WithSlashes` (`M/d/yyyy`) | **DateTime** |
| 15 | `DayMonthAbbrYear2WithDashes` (`d-MMM-yy`) | **DateTime** |
| 16 | `DayMonthAbbrWithDash` (`d-MMM`) | **DateTime** |
| 17 | `MonthAbbrYear2WithDash` (`MMM-yy`) | **Number** (not in either list; a ClosedXML quirk, replicate) |
| 18 | `Hour12MinutesAmPm` | **TimeSpan** |
| 19 | `Hour12MinutesSecondsAmPm` | **TimeSpan** |
| 20 | `Hour24Minutes` (`H:mm`) | **TimeSpan** |
| 21 | `Hour24MinutesSeconds` | **TimeSpan** |
| 22 | `MonthDayYear4WithDashesHour24Minutes` (`M/d/yyyy H:mm`) | **DateTime** |
| 45 | `MinutesSeconds` (`mm:ss`) | **TimeSpan** |
| 46 | `Hour12MinutesSeconds` (`[h]:mm:ss`) | **TimeSpan** |
| 47 | `MinutesSecondsMillis1` (`mm:ss.0`) | **TimeSpan** |
| 27–36, 50–58 (CJK locale dates), 0–13, 37–44, 48, 49, 164+ undefined, any other | — | **Number** |

The `applyNumberFormat` attribute, `xfId` / `cellStyleXfs` inheritance, and row (`<row s customFormat>`) or column
(`<col style>`) styles are **ignored** for cell typing. Only the cell's own `s` counts. No styles part, or no
`<cellXfs>` → every number is `number`. `s` ≥ the number of `<xf>` elements → the whole import fails.

**VESSEL-308 — Custom format-code classifier** (`GetDataTypeFromFormat` 1641-1680). If the custom code is
whitespace-only → Number. Otherwise lower-case it and scan left to right:
* `"` → skip to the next `"`. If there is none, Windows **loops forever** (a hang). The Mac returns "no decision" → Number.
* `[` → skip to the next `]`. If there is none → Number. This skips colours, conditions, locale tags **and elapsed
  `[h]`/`[m]`/`[s]`**.
* `0`, `#` or `?` → **Number**.
* `y` or `d` → **DateTime**.
* `h` or `s` → **TimeSpan**.
* `m` → look ahead from the next character: skip further `m`s; `s` → **TimeSpan**; any other ASCII letter or digit →
  **DateTime**; any other character (punctuation, space, non-ASCII) is **skipped and the look-ahead continues**; end of
  string → **DateTime**.
* anything else (including `\`, `_`, `*`, `e`, `g`, `a`, `b`, `/`, `:`, spaces, non-ASCII) → keep scanning.
* End of string with no decision → **Number**.

There is **no** escape handling (`\d` is a date signal), no section splitting (`;`), and `AM/PM` is not special. So
`AM/PM h:mm` → DateTime, because the `m` of `AM` looks ahead to `p`. See §X.8.2 for 30 classified codes.

**VESSEL-309 — Serial → date-time (1900 system).** `dateTime` cells convert through ClosedXML
`DoubleExtensions.ToSerialDateTime` and then .NET `DateTime.FromOADate` (§X.4.7): the leap-year shim of D6,
**round half away from zero to the millisecond**, epoch 1899-12-30, valid OA range `(−657435, 2958466)` exclusive.
Failures happen **when the cell is read**, not at load, and abort the import with these messages, verbatim:
* `60 < serial < 61` → `Serial date 60 is on a leap year of 1900 - date that doesn't exist and isn't representable in DateTime.`
* out of range → `Not a legal OleAut date.`

Only cells a reader actually renders can fail. A bad serial in a column the reader never visits is harmless.

**VESSEL-310 — 1904 date system.** `workbook.xml` `<workbookPr date1904="1|true"/>` sets `use1904`. At load, **every
`dateTime` cell** (from a numeric cell with a DateTime style, **or from `t="d"`**) is replaced by
`toSerial(fromSerial(v) + 1462 days)` (`LoadCell` 1239-1244). Effects:
* 1904 serial 44623 (id 14) → `2026-03-04`, correct.
* 1904 serials 0…60 come out **one day late** (0 → 1904-01-02), and `60 < v < 61` fails the **whole workbook open**,
  because the conversion runs at load. Replicate both.
* `t="d"` ISO dates in a 1904 workbook are shifted by +1462 days (a ClosedXML bug). Replicate.
* `number` cells are **not** shifted, so Shippalm's `ExcelDate` serial fallback reads a raw 1904 serial with the 1900
  epoch (4 years and 1 day early). `timeSpan` cells are not shifted either. Replicate.

**VESSEL-311 — Serial → duration.** `timeSpan` cells convert through `XLHelper.GetTimeSpan`: `TimeSpan.FromDays(v)`
(ticks truncated), then **round to whole milliseconds, half to even** (§X.4.9). Negative durations are possible. They
render through the same formulas and look strange, as on Windows.

**VESSEL-312 — Shared strings** (`sharedStrings.xml`, `SetCellText` 1424-1470). For each `<si>`:
* If it has one or more `<r>` children (rich text), the text = concatenation, in order, of each run's `<t>` text. There is **no
  `_xHHHH_` decoding**, and the **newline fix-up** applies (VESSEL-314). A `<t>` directly under `<si>` is then ignored.
* Otherwise, the text = the direct child `<t>` text, **with `_xHHHH_` decoding** (VESSEL-314) and **no** newline fix-up.
  A missing `<t>` → `""`.
* `<rPh>` phonetic runs (and their nested `<t>`) and `<phoneticPr>` are **never** part of the text.
* XML entities are decoded by the XML parser. Whitespace is preserved exactly (readers trim later). The XML parser
  already normalises literal CR/CRLF in the file to LF (XML end-of-line rule), and `&#13;` survives as CR.

**VESSEL-313 — Inline strings.** `t="inlineStr"` with `<is>`: if `<is>` has a direct `<t>`, the text = that text **with newline
fix-up but no `_xHHHH_` decoding**. Else, rich runs as in VESSEL-312 (fix-up, no decoding). `<is>` present but empty
→ `""`. For any other `t`, an `<is>` element is ignored.

**VESSEL-314 — Escapes and newline fix-up (Windows emulation).**
* `_xHHHH_` decoding (plain shared strings only), as .NET `XmlConvert.DecodeName` after ClosedXML's pre-pass:
  `_xHHHH_` (lower-case `x`, 4 hex digits in either case) → that UTF-16 unit, and `_xHHHHHHHH_` (8 hex digits) → that
  code point. `_x005F_` → `_`, so `_x005F_x000D_` → the literal `_x000D_`. **Upper-case `_XHHHH_` is not decoded**
  (ClosedXML rewrites it to `_x005F_XHHHH_` first). Swift cannot hold a lone surrogate (`_xD800_`), so emit U+FFFD.
  Windows would keep the lone unit. That is an accepted divergence.
* Newline fix-up (`StringExtensions.FixNewLines`): if the text contains `\n`, every `\n` not preceded by `\r` becomes
  `Environment.NewLine`, which on the Windows build is **`\r\n`**. The Mac **must emit `\r\n`** here too (not `\n`),
  because these strings are persisted (e.g. a multi-line Shippalm `Title` from a rich-text cell). Lone `\r` is untouched.

**VESSEL-315 — Booleans** render `TRUE` / `FALSE` in every renderer (A and B explicitly, C via `GetString`).
Downstream: Shippalm `Notify` → `ParseBool("TRUE")` = true.

**VESSEL-316 — Errors.** Display text (`XLErrorExtensions.ToDisplayString`): `#NULL!`, `#DIV/0!`, `#VALUE!`,
`#REF!`, `#NAME?`, `#NUM!`, `#N/A`. `<v>` is matched after `.Trim()`, ordinal (case-sensitive). All renderers
output the display text. Unknown codes → `blank` (D11), so such a cell is `IsEmpty` and does not extend the used range.

**VESSEL-317 — ISO date cells (`t="d"`).** `<v>` is parsed with `DateTime.ParseExact`, invariant culture, leading and
trailing white space allowed, trying exactly: `yyyy-MM-ddTHH:mm:ss.fff` (3-digit fraction required), `yyyy-MM-ddTHH:mm`,
`yyyy-MM-dd`. The result is stored as a `dateTime` serial. **Any other shape** (e.g. `2026-03-04T10:30:00`, a trailing
`Z`, an offset) → `FormatException` → **the whole workbook fails to open**. Excel does not write `t="d"` in normal
files, so this is rare. Replicate (fail with VESSEL-302's message).

**VESSEL-318 — Formulas and cached values.** A `<c>` with `<f>` has `hasFormula = true`, whatever its value. With a
cached `<v>`, the kind comes from `t` and the style exactly as for a constant (e.g. `<f>1+1</f><v>2</v>` → `number(2)`,
`t="str"` → text, `t="e"` → error). **Without `<v>`** the cell's slice value stays `blank` (or `text("")` for
`t="s"`/`str`), and ClosedXML marks the formula dirty. The first `GetString()`/`GetDouble()`/… then **recalculates the
formula with ClosedXML's CalcEngine** and renders the computed value. The Mac cannot evaluate Excel formulas. Normative
Mac behaviour: such a cell renders as `""` (it is still non-empty for `IsEmpty`/`RangeUsed`), and the importer records
one diagnostic per file, appended to the success status line. This is **Mac-only text**:
`{n} formula cell(s) had no saved result; open and re-save the file in Excel to include them.` This is a **documented divergence** (§X.10 Q14). Real COMPAS, Shippalm and
port-list exports contain no formulas (verified for both POC files).

**VESSEL-319 — `IsEmpty()`** (ClosedXML default options `AllContents` = Contents | DataType | Comments). A cell is
empty iff its kind is `blank` **or** `text("")`, **and** it has no formula, **and** it has no comment. Whitespace-only
text is **not** empty. Merge membership, styles, data validation and conditional formats do **not** make a cell non-empty.

**VESSEL-320 — Used range (`RangeUsed()`).** `firstRow/lastRow/firstCol/lastCol` = min/max over all cells that are
**not** `IsEmpty()`. nil when there are none. The `<dimension>` element is **ignored**. Hidden rows and columns count. The
readers iterate **every** `(r, c)` inside these bounds (COMPAS from row 1 / column 1, the other two from the range's
first row / column; see §3.3.1, §3.4.1, 09 §3.3), so bounds errors change which rows are scanned (e.g. the COMPAS
`≤ 20` header window, the ports `firstRow+12` detection window and the Shippalm `firstRow+15` window).

**VESSEL-321 — Addressing.** A `<row>` without `r` gets `++lastRow`, a counter that starts at 0 per sheet and is **only**
advanced by rows lacking `r` (a quirk: mixing numbered and unnumbered rows restarts at 1). A `<c>` without `r` gets
`(rowIndex, lastColumn + 1)`. `lastColumn` resets to 0 at each `<row>` and is set to the column of every `<c>`
(explicit or implied). A `<c r>` whose row differs from its `<row r>` is stored at its own reference. When a
reference appears twice, the later `<c>` overwrites the value it sets. A later `<c>` that sets no value (e.g. `t="n"`
without `<v>`) leaves the earlier value. `cell(r, c)` for any in-sheet coordinate never fails and returns a `blank` for
absent cells.

**VESSEL-322 — Merged cells.** `<mergeCells>` is parsed for completeness but has **no effect** on values, kinds,
`IsEmpty` or `RangeUsed` (D8). Header logic that needs "merged header" behaviour already emulates it itself (ports
layout B's sticky category, §3.3.4). COMPAS and Shippalm see only the anchor column of a merged header.

**VESSEL-323 — Comments.** Cells referenced by `<comment ref="…">` in the sheet's legacy comments part (worksheet
relationship type `…/comments`) get `hasComment = true`. So a comment on an otherwise empty cell extends the used range
and makes `IsEmpty()` false. It still renders `""`. Threaded comments (Excel 365) always come with a legacy
comments part, so only the legacy part is read.

**VESSEL-324 — Table (ListObject) side effects** (`XLWorksheet.Table` 1582-1608, `XLTable.OnAddedToTables` 550-561).
For each table part of the sheet (worksheet relationship type `…/table`, attribute `ref`), after all cells are loaded:
1. If `ref` spans **exactly one row**, ClosedXML inserts one row below it **within the table's column span**: every cell
   in those columns below the table moves down one row. Cells outside the span do not move.
2. For every cell in the table's **first row** (the header row, and the first row even when `headerRowCount="0"`) that
   is empty by *Contents* (blank or `text("")`, no formula), ClosedXML writes text `Column{n}`. `n` = the 1-based
   column offset within the table. It is made unique only against the header texts **to its left** in that row
   (their `GetString()`, ordinal, case-sensitive) by incrementing `n` until unused. Cells to the right are not
   consulted, so a duplicate is possible.

Item 1's column-span restriction is how `XLRange.InsertRowsBelow` behaves for a non-full-row range. **VERIFY** it with
the golden harness.

Excel never leaves table headers empty and never writes one-row tables, so real exports are unaffected (the POC files
have no tables). The Mac **should** implement both (cheap in the cell map). A Mac build without them diverges only
on hand-crafted files. Totals-row field rescans are not replicated (§X.10 Q18).

**VESSEL-325 — `GetString()` emulation.** Renderers fall back to ClosedXML `XLCell.GetString()` =
`Value.ToString(CultureInfo.CurrentCulture)` (`XLCellValue.cs` 384-395). The Mac uses one fixed **reference culture**
(Gregorian calendar, time separator `:`, decimal separator `.`), which equals every English culture the Windows build
is used with (§X.10 Q17):

| Kind | `GetString()` |
|---|---|
| blank | `""` |
| boolean | `TRUE` / `FALSE` |
| number | .NET shortest round-trip text (VESSEL-329) |
| text | the text, verbatim (no trim) |
| error | display text (VESSEL-316) |
| dateTime | .NET `DateTime.ToString()` of the culture. **Unreachable** from all three renderers (they handle DateTime first). Define it as `M/d/yyyy h:mm:ss tt` (en-US) for completeness |
| timeSpan | `ToExcelString`: `{totalHours}:{mm}:{ss}[.{f}]` (§X.4.9) |

**VESSEL-326 — Renderer A: `CompasReader.CellString`** (`CompasReader.cs:70-88`).
```
if cell.isEmpty            → ""
number(d)                  → d is integral ? Int64Saturating(d) text : NetShortest(d)
dateTime(s)                → fromSerial(s) → "yyyy-MM-dd"   (time dropped; may throw per VESSEL-309)
boolean(b)                 → "TRUE" / "FALSE"
default (text, timeSpan, error, blank-with-formula/comment) → GetString().trim()
```
So TimeSpan cells (ids 18–21, 45–47, custom `h`/`s`/`m…s` codes) reach the **default branch** and render as
`H:mm:ss[.fff]` (`6:00:00`), never as a date and never zero-padded (D3). `trim()` = .NET `String.Trim()` (Unicode
`White_Space`: U+0009–U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000–U+200A, U+2028, U+2029, U+202F, U+205F,
U+3000), which equals Swift `CharacterSet.whitespacesAndNewlines` applied to **unicode scalars**, not Characters.

**VESSEL-327 — Renderer B: `ShippalmReader.Cell` and `ExcelDate`** (`ShippalmReader.cs:136-170`). `Cell` is
**byte-identical in behaviour to renderer A**. Implement it as the same function, with a Shippalm alias for
traceability. `ExcelDate(raw)` post-processes only the three date columns (`Due Date`, `Finished Date-Time`,
`Last Done Date`):
```
raw blank/whitespace → ""
raw = trim(raw)
CrewMember.ParseDate(raw) succeeds → its date "yyyy-MM-dd"        (shared parser, 09 §6.3; see note)
Double.parse(raw, NumberStyles.Any, invariant) = v and 20000 < v < 200000
     → FromOADate(v) date "yyyy-MM-dd"   (pure .NET FromOADate: no leap shim, no 1904 shift, ms rounding)
else → raw
```
Note: because TimeSpan cells render `H:mm:ss`, a time-only cell in a Shippalm date column becomes a **time-only
string**. .NET `DateTime.TryParse` accepts that as **today at that time**, so `ExcelDate` returns **today's local date**.
The Mac's shared `ParseDate` port **must** accept time-only input (`H:mm`, `H:mm:ss`, `H:mm:ss.fff`, `h:mm[:ss] AM/PM`)
and return today (the 09 §6.3 shape list does not mention this). Replicate.

**VESSEL-328 — Renderer C: `PortCallReader.Cell`** (`PortCallReader.cs:208-220`).
```
if cell.isEmpty       → ""
dateTime(s)           → t = fromSerial(s);  t.msOfDay == 0 ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm"   (seconds dropped, not rounded)
timeSpan(s)           → ms = toTimeSpanMs(s);  pad2(|hoursComponent|) + ":" + pad2(|minutesComponent|)   (days dropped)
number(d)             → Net0_4(d)       ("0.####", VESSEL-330)
default (text, boolean, error, blank-with-formula/comment) → GetString().trim()
```
The "midnight" test uses the millisecond-rounded value, so `46218.999999999` → `2026-07-16` and
`46218.99999999` → `2026-07-15 23:59` (§X.8.3). Downstream `NormDate`/`NormTime` are unchanged (§3.3.5–§3.3.6).
Consequences: a time-only cell in a **date** column gives `NormDate("12:00")` = **today** (the .NET general parser),
and a bare serial `48108` in a date column stays `48108` (ports have **no** serial fallback, unlike Shippalm).

**VESSEL-329 — .NET shortest round-trip number text** (renderers A/B, and `GetString` of numbers). Integral doubles
(`d == floor(d)`) render through `(long)d`, which **saturates** on .NET 9+ (the app runs on .NET 10), so `1e20` →
`9223372036854775807`. `-0.0` → `0`. Non-integral doubles use .NET Core 3.0+ `double.ToString(InvariantCulture)`:
the **shortest** digit string that round-trips, in fixed notation when the decimal exponent `E` satisfies
`-5 < E < 15`, else scientific `d[.ddd]E±XX` (sign always, at least 2 exponent digits): `1E-05`, `1.5E-10`,
`1.0000000000000005E+15`.

**VESSEL-330 — .NET `"0.####"` number text** (renderer C). Take **15 significant digits, correctly rounded**, then
round that decimal digit string at 4 decimal places **half-up** (on the digit string), trim trailing zeros and a
trailing point, no grouping, `-` for negatives. When everything rounds away the result is `0` (provisional: the sign of
negative values that round to zero is unverified, §X.10 Q19). Because of the 15-digit pre-rounding, `2.00005` →
`2.0001` and `1234.56785` → `1234.5679`, even though the exact binary values lie just below the midpoint. Values of
10^15 or more show at most 15 significant digits followed by zeros (`12345678901234567` → `12345678901234600`).

**VESSEL-331 — Errors surfaced to the user.** The reader throws. Each importer's existing catch shows its box (above),
and nothing is imported (the upsert happens only after a successful read). Mac: `NSAlert` sheet on the panel's window,
style critical, title `Import failed`, message text exactly as Windows (`Could not import the … file:` then a blank
line, then the message), single `OK` button.

**VESSEL-332 — Performance and threading.** Windows parses Shippalm and ports **off the UI thread**
(`Task.Run`) and COMPAS **on** it. The Mac parses all three in a detached task and returns a `Sendable` value. A
2,524-row × 16-column Shippalm export (PROGRESS) must open and render in under 1 s on Apple silicon. Parsing is SAX
(`XMLParser`). Sheets are parsed **lazily in order**, only as far as selection needs. Shared strings are parsed once.
Styles are resolved to a per-`s` kind cache.

**VESSEL-333 — Culture independence (documented Windows variance).** The Windows renderers format with the **current
UI culture** in four places: `DateTime.ToString("yyyy-MM-dd")` / `"yyyy-MM-dd HH:mm"` (calendar, and the time
separator for `:`), `GetString()` of TimeSpans (time separator, and the decimal separator for milliseconds), and
`GetString()` of numbers (formula-recalculated cells only). On a Windows machine set to a non-Gregorian default
calendar (e.g. `th-TH` Buddhist, `ar-SA` Um Al-Qura, `fa-IR` Persian) or a `.` time separator (e.g. `fi-FI`), the
Windows build persists different strings. The Mac always uses the reference culture (VESSEL-325), which matches the
English cultures in use. This is not a bug to replicate (§X.10 Q17).

**VESSEL-334 — Cross-reference for 09 §6.2.** 09 §6.2's bullets on cell typing, used range and merged cells are
superseded by this addendum. The one-line cross-reference that 09 §6.2 should carry is given verbatim in §X.9.

### X.4 LOGIC & ALGORITHMS

#### X.4.1 Open and gate (`XLWorkbook(String)` → `GetSpreadsheetDocumentType`, XLWorkbook.cs 482-506, 750-760)
```
func open(url) throws -> XlsxWorkbook
  let name = url.lastPathComponent
  let ext  = name.lastIndex(of: ".").map { String(name[name.index(after: $0)...]) } ?? ""   // .NET Path.GetExtension
  // Do NOT use URL.pathExtension: it returns "" for a file literally named ".xlsx", which .NET accepts.
  guard !ext.isEmpty else { throw .gate("Empty extension is not supported.") }
  let e = ext.lowercased()                          // ToLowerInvariant
  guard ["xlsx","xlsm","xltx","xltm"].contains(e) else {
      throw .gate("Extension '\(e)' is not supported. Supported extensions are '.xlsx', '.xlsm', '.xltx' and '.xltm'.") }
  let zip = try ZipReader(url)                      // AACore/Zip (shared with .aaz bundles and Flash Sync)
  let main = try zip.relationshipTarget(source: "", type: officeDocument)   // _rels/.rels
  ...
```
`.NET Path.GetExtension("a.")` returns `""`, so it hits the empty-extension message. For a file named `.xlsx` (dot
first), `GetExtension` returns `.xlsx`, which is accepted. The manual computation above matches both.

#### X.4.2 Package parts and relationships
* Relationship `Target`s resolve relative to the source part's folder (`xl/` for `xl/workbook.xml`). A leading `/`
  means package-absolute. `TargetMode="External"` is ignored. ZIP entry names match **case-insensitively** (OPC), and
  `%XX` escapes are decoded.
* Relationship types used (transitional namespace `http://schemas.openxmlformats.org/officeDocument/2006/relationships/`
  + suffix): `officeDocument`, `worksheet`, `styles`, `sharedStrings`, `comments`, `table`. The Mac also accepts the
  Strict equivalents (`http://purl.oclc.org/ooxml/officeDocument/relationships/…`) and the Strict SpreadsheetML
  namespace. Windows (OpenXML SDK) does not read Strict files, so this is an accepted superset.
* Elements are matched by **namespace + local name** (`XMLParser.shouldProcessNamespaces = true`), so prefixed markup
  (`<x:c>`) works. `mc:AlternateContent` is not expected inside `sheetData`. If present, the Mac reads the
  `mc:Choice` whose `Requires` it understands, else `mc:Fallback`.
* Security: `shouldResolveExternalEntities = false` (the default). Cap the inflated size of any single part (suggest
  1 GiB) and the entry count (suggest 10,000). Exceeding either → VESSEL-302 failure.

#### X.4.3 Styles → numeric kind
```
struct StyleKinds { kinds: [NumberKind] }        // index = cellXfs position
build():
  numFmts = [Int: String]  from <numFmts><numFmt numFmtId formatCode/>   (first entry per id wins)
  for xf in <cellXfs><xf …> (document order):
      id = Int(xf@numFmtId) ?? 0
      if let code = numFmts[id], !code.isEmpty { kind = classifyCustom(code) }   // numberFormatId = -1 in ClosedXML
      else { kind = builtinKind(id) }
builtinKind(id):
  [18,19,20,21,45,46,47].contains(id) → .timeSpan
  [14,15,16,22].contains(id)          → .dateTime
  default                              → .number
classifyCustom(code):
  code is all whitespace → .number
  return scan(code) ?? .number                    // §X.4.4
kind(forStyleIndex s):
  no styles part or no <cellXfs> → .number
  s >= kinds.count → throw (whole import fails)
  return kinds[s]
```

#### X.4.4 `scan(code)`, the custom classifier (exact port of `GetDataTypeFromFormat`)
```
let f = Array(code.lowercased().unicodeScalars)     // ASCII-relevant; .NET uses current-culture ToLower (no impact on y/d/h/s/m)
var i = 0
while i < f.count {
  let c = f[i]
  switch c {
  case "\"": guard let k = f.firstIndex(of: "\"", from: i+1) else { return nil }   // Windows: infinite loop
             i = k
  case "[":  guard let k = f.firstIndex(of: "]", from: i+1) else { return nil }
             i = k
  case "0", "#", "?": return .number
  case "y", "d":      return .dateTime
  case "h", "s":      return .timeSpan
  case "m":
      var j = i + 1
      while j < f.count {
          if f[j] == "m" { j += 1; continue }
          if f[j] == "s" { return .timeSpan }
          if ("a"..."z").contains(f[j]) || ("0"..."9").contains(f[j]) { return .dateTime }
          j += 1                                        // punctuation, space, non-ASCII: keep looking
      }
      return .dateTime
  default: break
  }
  i += 1
}
return nil
```

#### X.4.5 Cell loading (per `<c>`)
```
s     = Int(@s) ?? 0
addr  = @r ?? (rowIndex, lastColumn + 1);  lastColumn = addr.col
t     = @t (nil → "n")
f     = child <f> present → hasFormula = true (formula text itself is not needed)
v     = child <v> text (nil if absent)
is    = child <is>
switch t:
 "n":   if let v, let d = parseNumber(v) {
            switch styles.kind(s) { .number: number(d); .dateTime: dateTime(serial: d); .timeSpan: timeSpan(serial: d) } }
        // else: leave the cell as it was (blank for a new cell)
 "s":   value = v.flatMap(parseIndex).flatMap(sst.at) ?? text("")         // missing <v> also → text("")
 "str": text(v ?? "")
 "inlineStr": if let is { text(inlineText(is)) }                           // <v> ignored
 "b":   if let v { boolean(v == "1" || v.caseInsensitiveEquals("TRUE")) }
 "e":   if let v, let code = XlsxErrorCode(v.trimmed) { error(code) }
 "d":   if let v { dateTime(serial: toSerial(try parseIsoExact(v))) }       // throws → whole import fails
 other: throw .unknownCellType
if use1904, case .dateTime(let x) = value { value = .dateTime(serial: toSerial(try fromSerial(x).addingDays(1462))) }
```
`parseNumber` = .NET `double.TryParse(v, AllowLeadingWhite | AllowTrailingWhite | AllowLeadingSign | AllowDecimalPoint |
AllowExponent, Invariant)`: optional white space, optional `+`/`-`, digits with optional `.` fraction (either side may be
empty but not both), optional `e`/`E` exponent with optional sign. **No** thousands separators, hex or currency.
`Infinity`, `-Infinity` or `NaN` parse and then **fail the import** (ClosedXML rejects non-finite values). Swift: a
hand-written scanner followed by `Double(String)` on the canonicalised text. Do not use `NumberFormatter`, which is
locale-sensitive.

`parseIndex` = `Int32.TryParse` with the same styles. A decimal point followed only by zeros (`3.0`) is accepted as 3.
Negative or ≥ count → nil.

`toSerial(DateTime)` (`DateTimeExtensions.ToSerialDateTime`): `oa = ToOADate(dt)` (days since 1899-12-30 plus the
fraction, for dates on or after 1899-12-30); `oa <= 60 ? oa - 1 : oa`.

#### X.4.6 String assembly (§VESSEL-312–314)
```
sharedItem(si):
  runs = si.children("r")
  if !runs.isEmpty { return fixNewLines(runs.map { $0.child("t")?.text ?? "" }.joined()) }
  return decodeXHHHH(si.child("t")?.text ?? "")
inlineText(is):
  if let t = is.child("t") { return fixNewLines(t.text) }
  let runs = is.children("r"); return runs.isEmpty ? "" : fixNewLines(runs.map { $0.child("t")?.text ?? "" }.joined())
fixNewLines(x): x.contains("\n") ? x.replacing(/(?<!\r)\n|\r\n/, with: "\r\n") : x
decodeXHHHH(x):
  x = x.replacing(/_(X[0-9A-Fa-f]{4})_/, with: "_x005F_$1_")      // protect upper-case X
  scan for "_x": if 8 hex digits + "_" follow → that scalar (invalid/lone surrogate → U+FFFD);
                 else if 4 hex digits + "_" follow → that UTF-16 unit (surrogate pairs from two consecutive escapes
                 combine; lone surrogate → U+FFFD);
                 else copy "_" literally and continue
```
In the SAX parser, only a `<t>` whose parent is `<si>`, `<is>` or an `<r>` directly under them contributes. `<t>` under
`<rPh>` never does.

#### X.4.7 Serial → calendar date-time (`ToSerialDateTime` + `DateTime.FromOADate`)
```
struct NetDateTime { year, month, day, hour, minute, second, millisecond: Int; var msOfDay: Int }
func fromSerial(_ v: Double) throws -> NetDateTime
  let oa: Double
  if v >= 61 { oa = v } else if v <= 60 { oa = v + 1 }
  else { throw .message("Serial date 60 is on a leap year of 1900 - date that doesn't exist and isn't representable in DateTime.") }
  return try fromOADate(oa)
func fromOADate(_ d: Double) throws -> NetDateTime
  guard d < 2958466.0, d > -657435.0 else { throw .message("Not a legal OleAut date.") }
  var ms = Int64(d * 86_400_000.0 + (d >= 0 ? 0.5 : -0.5))      // Int64(...) truncates toward zero
  if ms < 0 { ms -= (ms % 86_400_000) * 2 }                       // OA negative-date rule: time part counts forward
  let day = floorDiv(ms, 86_400_000), msOfDay = ms - day * 86_400_000
  civil = civilFromDays(daysFrom(1899-12-30) + day)               // proleptic Gregorian, no time zone
```
**Never** go through `Date` + `TimeZone.current`, because a DST transition shifts the hour or even the day. Use pure civil
arithmetic (days-from-civil). `"yyyy-MM-dd"` = 4-digit zero-padded year, 2-digit month and day. `"HH:mm"` = 24-hour,
2 digits each.

#### X.4.8 1904 (VESSEL-310)
Applied once per `dateTime` cell at load: `serial' = toSerial(fromSerial(serial) + 1462 days)`. `fromSerial` can throw
here, which fails the **workbook open**. Adding 1462 days past 9999-12-31 also throws. For every real date the net
effect is `serial + 1462`.

#### X.4.9 Serial → duration and its two text forms
```
func toTimeSpanMs(_ v: Double) throws -> Int64                    // XLHelper.GetTimeSpan
  let ticks = v * 864_000_000_000.0; guard abs(ticks) < 9.2e18 else { throw overflow }
  let t = Int64(ticks)                                            // TimeSpan.FromDays truncates to ticks
  return Int64((Double(t) / 10_000.0).rounded(.toNearestOrEven))  // Math.Round default = banker's
components (all truncating, signs follow .NET): days = ms / 86_400_000; hours = (ms / 3_600_000) % 24;
  minutes = (ms / 60_000) % 60; seconds = (ms / 1_000) % 60; frac = ms % 1_000
ToExcelString:  "\(hours + 24*days):\(D2(minutes)):\(D2(seconds))" + (frac == 0 ? "" : "." +
                (frac % 100 == 0 ? "\(frac/100)" : frac % 10 == 0 ? D2(frac/10) : D3(frac)))
Ports "hh\:mm": pad2(abs(hours)) + ":" + pad2(abs(minutes))
D2/D3 = .NET "D2"/"D3": "-" for negatives, then zero-pad the absolute value
```

#### X.4.10 `IsEmpty`, `RangeUsed`, `cell(r,c)`
```
isEmpty(cell) = (cell.value == .blank || cell.value == .text("")) && !cell.hasFormula && !cell.hasComment
rangeUsed()   = bounds over { (r,c) | !isEmpty(cell(r,c)) }  or nil
```
Compute bounds after all of the sheet's cells, comments and table side effects are applied.

#### X.4.11 Renderers: one module, three thin adapters
```
enum XlsxRender {
  static func compas(_ c: XlsxCell) throws -> String      // VESSEL-326
  static func shippalm(_ c: XlsxCell) throws -> String    // VESSEL-327 = compas(c)
  static func ports(_ c: XlsxCell) throws -> String       // VESSEL-328
  static func getString(_ c: XlsxCell) -> String          // VESSEL-325 (reference culture)
}
enum ShippalmDates { static func excelDate(_ raw: String, today: LocalDate) -> String }   // §3.4.4 + VESSEL-327 note
```
`today` is injected (the shared `ParseDate` needs it for time-only strings and year-less shapes). The readers stay
where they are (`CompasReader`, `ShippalmReader`, `PortCallReader` in AACore). They call `XlsxWorkbook.open`, choose the sheet
(VESSEL-304), take `rangeUsed()`, and call their renderer for each `(r, c)` they visit, exactly as the C# does.

#### X.4.12 Number text helpers
```
Int64Saturating(d): d >= 9.223372036854775807e18 → Int64.max; d < -9.223372036854775808e18 → Int64.min; else Int64(d)
NetShortest(d):     // .NET Core 3.0+ double.ToString(Invariant) ("R"/"G" shortest)
  (digits, exp) = shortest round-trip decimal digits of |d| and the exponent of its first digit
                  (take them from Swift's `d.description`, which is also shortest-round-trip, by parsing out mantissa and exponent)
  if -5 < exp && exp < 15: fixed notation (pad with zeros; no trailing ".0")
  else: first digit + (more digits ? "." + rest : "") + "E" + (exp < 0 ? "-" : "+") + pad2(abs(exp))
  prefix "-" when d < 0
Net0_4(d):          // .NET custom format "0.####"
  if d == 0 → "0"
  (D, E) = 15 significant digits, correctly rounded, of |d| (String(format: "%.14e", |d|) with the POSIX locale), E = exponent
  keep = E + 1 + 4                                   // digits up to and including the 4th decimal
  if keep < 0 → "0"
  if keep < 15 {                                     // .NET RoundNumber(pos = keep), half-up on the digit string
      if D[keep] >= "5" {
          if keep == 0 { D = "1"; E += 1 }            // e.g. 0.00005 → 0.0001
          else { D = D[0..<keep] incremented with carry; all nines → D = "1", E += 1 }
      } else { D = D[0..<keep] }                     // keep == 0 → D = "" → "0"
  }                                                  // keep ≥ 15: no rounding, all 15 digits stay
  strip trailing "0"s from D; D empty → "0"
  intPart  = E >= 0 ? D[0...E] (right-pad with "0" to E+1 digits) : "0"
  fracPart = E >= 0 ? D[(E+1)...] : String(repeating: "0", count: -E-1) + D     // at most 4 digits by construction
  result = intPart + (fracPart.isEmpty ? "" : "." + fracPart);  prefix "-" if d < 0 and result != "0"
```

#### X.4.13 Error model
```
enum XlsxReadError: Error, LocalizedError {
  case gate(String)                 // VESSEL-301, message verbatim
  case message(String)              // VESSEL-309 verbatim messages
  case corrupt(detail: String)      // VESSEL-302: "The file could not be opened as an Excel workbook (.xlsx)." + detail
}
```
Reader-level errors (`Could not find the Shippalm header row …`, `The workbook is empty.`, …) stay in the readers
exactly as 09 §3.3 / 10 §3.3.8 / 10 §3.4.1 define them.

### X.5 DATA FORMATS

#### X.5.1 OOXML consumed (read-only)
| Part | Elements / attributes read | Everything else |
|---|---|---|
| `[Content_Types].xml` | not needed (relationships decide part types) | ignored |
| `_rels/.rels` | `Relationship@Type=…/officeDocument`, `@Target` | ignored |
| `xl/workbook.xml` | `workbookPr@date1904`, `sheets/sheet@name`, `@r:id` (`@state` ignored) | calcPr, definedNames, views: ignored |
| `xl/_rels/workbook.xml.rels` | `@Id`, `@Type`, `@Target` | — |
| `xl/styles.xml` | `numFmts/numFmt@numFmtId`, `@formatCode`; `cellXfs/xf@numFmtId` (position = style index) | fonts, fills, borders, cellStyleXfs, dxfs: ignored |
| `xl/sharedStrings.xml` | `si`, `si/t`, `si/r/t` (`rPh`, `phoneticPr`, `rPr` ignored) | — |
| `xl/worksheets/sheetN.xml` | `sheetData/row@r`, `c@r`, `@s`, `@t`, `c/f` (presence), `c/v`, `c/is` (`t`, `r/t`); `mergeCells` (parsed, no effect) | dimension, sheetViews, cols, autoFilter, conditionalFormatting, dataValidations, hyperlinks: ignored |
| `xl/worksheets/_rels/sheetN.xml.rels` | `comments` and `table` targets | — |
| `xl/commentsN.xml` | `commentList/comment@ref` | text ignored |
| `xl/tables/tableN.xml` | `table@ref`, `@headerRowCount` | — |

#### X.5.2 Persisted outputs (why byte parity matters)
The renderer strings (after each reader's own trimming and post-processing) are persisted verbatim:
* `CrewMember` string fields via `CrewConverter` (09 §4.2), after DateResolver/mapping;
* `ShipJob` `JobNo`, `Title`, `WorkPlanNo`, `Status`, `ClassCode`, `Category`, `ResponsibleRank`, `FunctionNo`,
  `FunctionDescription`, `Interval`, `DueStatus`, `DueDate`, `FinishedDate`, `LastDoneDate` (strings), `OverdueDays`
  (int from `int.TryParse` of renderer B's text), `Notify` (bool);
* `PortCall` `PortName`, `Country`, `UnLocode`, `PortFacility`, `PfNo`, `SecurityLevelPort`, `SecurityLevelVessel`,
  `SspFollowed`, `SpecialMeasures`, `ArrivalDate`, `ArrivalTime`, `DepartureDate`, `DepartureTime`, and the vessel
  `VesselName`/`Imo`/`CallSign` comparison (§3.3.1).

JSON key names and value formats are unchanged (§4.2 and 09 §4.2). The only new rule here is **which characters**
those strings contain: interior `\r\n` from rich or inline text (VESSEL-314), `H:mm:ss` for TimeSpans in COMPAS and
Shippalm text columns, `#N/A`-style error text, and `TRUE`/`FALSE`.

#### X.5.3 Cross-version compatibility rules
1. For the same `.xlsx`, a Mac import and a Windows import (English culture) must produce identical model strings,
   so `data.json` diffs clean. This is the acceptance test (§X.7.6).
2. Files written by AA itself (`ShippalmReader.Write`, `PortsService.Export`, `XlsxWriter`) contain only text, numbers and a
   bold style. The Mac writer must keep Due Date / Last Done Date as **text** cells (`t="s"` or `inlineStr`) in
   columns styled `@` (numFmtId 49 → Number kind, harmless for text). Then Windows and Mac readers agree regardless of
   styles. Never write dates as serials (a serial styled 14 would re-import identically, but one styled 17 or unstyled
   would not).
3. Where the Mac knowingly differs (formula recalculation Q14, lone surrogates, Strict files, hangs, the table-totals
   rescan), the Mac is **more lenient or empty, never different-but-plausible**. It never invents a value that Windows
   would not produce.

### X.6 DEPENDENCIES

* **Called by:** `CompasReader.Read` (09, from `CrewPage` import), `ShippalmReader.Read` (VESSEL-101), `PortCallReader.Read`
  (VESSEL-201), and AACoreTests.
* **Calls:** `AACore/Zip` (`ZipReader`: central directory, stored + DEFLATE via `Compression` `COMPRESSION_ZLIB`, CRC-32
  check; shared with `.aaz` bundles, 01 / 13), Foundation `XMLParser`, the shared `CrewMember.ParseDate` port (09 §6.3,
  only through `ExcelDate`), and `CrewText.Norm` (09 §3.2, only in the readers).
* **Windows-only / .NET-only pieces replaced:** ClosedXML 0.104.2 + DocumentFormat.OpenXml SDK (`XLWorkbook`,
  `RangeUsed`, `Cell`, `DataType`, `GetString/GetDouble/GetDateTime/GetTimeSpan/GetBoolean`, `IsEmpty`), .NET
  `DateTime.FromOADate`, `TimeSpan.FromDays`, `double.ToString` (shortest and custom), `String.Trim`,
  `XmlConvert.DecodeName`, `Environment.NewLine`, `CultureInfo.CurrentCulture`. None is OS-specific (ClosedXML is
  cross-platform .NET), but none is available to Swift, so each is re-specified above.

### X.7 macOS ADAPTATION NOTES

#### X.7.1 Module layout (AACore, no third-party dependencies)
| File | Contents |
|---|---|
| `AACore/Xlsx/XlsxWorkbook.swift` | `public struct XlsxWorkbook: Sendable { let worksheets: [XlsxWorksheetRef]; let use1904: Bool; static func open(_ url: URL) throws -> XlsxWorkbook; func worksheet(named:) ; func load(_ ref) throws -> XlsxWorksheet }` |
| `AACore/Xlsx/XlsxWorksheet.swift` | `public struct XlsxWorksheet: Sendable { let name: String; func cell(_ r: Int, _ c: Int) -> XlsxCell; func rangeUsed() -> XlsxRange? }` (storage: `[Int: [Int: XlsxCell]]` row → col, or a sorted row array) |
| `AACore/Xlsx/XlsxCell.swift` | `enum XlsxValue: Sendable, Equatable { case blank, text(String), number(Double), boolean(Bool), error(XlsxErrorCode), dateTime(serial: Double), timeSpan(serial: Double) }`; `struct XlsxCell { var value: XlsxValue; var hasFormula: Bool; var hasComment: Bool; var isEmpty: Bool }` |
| `AACore/Xlsx/XlsxStyles.swift` | `enum NumberKind { number, dateTime, timeSpan }`, `builtinKind(_:)`, `classifyCustom(_:)` (§X.4.3–4) |
| `AACore/Xlsx/XlsxSharedStrings.swift`, `XlsxSheetParser.swift` | SAX delegates (§X.4.5–6) |
| `AACore/Xlsx/ExcelSerial.swift` | `NetDateTime`, `fromSerial`, `fromOADate`, `toSerial`, `toTimeSpanMs`, `excelString(ms:)` (§X.4.7–9) |
| `AACore/Xlsx/NetNumberText.swift` | `int64Saturating`, `netShortest`, `net0_4` (§X.4.12) |
| `AACore/Xlsx/XlsxRender.swift` | the three adapters + `getString` (§X.4.11) |

`Sendable` value types throughout, so a detached `Task` can parse and hand the result to the `@MainActor` store.
Swift language mode 5 (per the architecture brief). Avoid `NSRegularExpression` in hot loops. The two regexes in
§X.4.6 run only on strings that contain `\n` or `_X`.

#### X.7.2 Parsing strategy
* One `XMLParser` pass per part. A 2,524 × 16 sheet has about 40,000 `<c>`, which parses in well under 200 ms. Build
  shared strings into `[String]` before any sheet. Resolve `s` → `NumberKind` through the prebuilt array (O(1)).
* Parse sheets lazily in workbook order. COMPAS needs at most one sheet (the `report` lookup needs names only), and
  Shippalm and Ports parse until the first sheet with `rangeUsed() != nil`.
* Keep formula text out of memory (only the presence flag). Comments: read only `@ref`. Tables: only `@ref` and
  `@headerRowCount`.

#### X.7.3 UI touch points (native, no capability dropped)
* Open panels: `NSOpenPanel` with an accessory pop-up **Excel workbook (.xlsx) / All files**, mirroring the Windows
  filter pair. For "Excel workbook", `allowedContentTypes = [UTType("org.openxmlformats.spreadsheetml.sheet")!]`.
  "All files" allows everything, and VESSEL-301 then gates by name with the Windows messages. Panel titles as the
  Windows dialogs (`Select COMPAS crew report`, `Import Shippalm Work Order List for {V}`,
  `Import ports of call for {V}`).
* Drag an `.xlsx` from Finder onto the Crew roster / Work Orders / Ports panel → the same import (additive; the drop
  highlight uses the system accent). It goes through the same gate and the same confirmation prompts.
* While parsing, show an indeterminate `ProgressView` in the panel's status area and disable the Import button,
  instead of the Windows wait cursor. Keep the Windows status text `Reading Shippalm export… (large files take a few seconds)`.
* Errors: VESSEL-331 (sheet-modal `NSAlert`).

#### X.7.4 Things that are impossible on the Mac, and the faithful alternative
| Windows behaviour | Why impossible | Mac alternative |
|---|---|---|
| Recalculating formulas that lack cached values (ClosedXML CalcEngine) | no Excel formula engine on the Mac, and writing one is out of scope | render `""`, count them, and append the VESSEL-318 hint. Real exports have cached values |
| Infinite loop on an unterminated `"` in a custom format | a hang is a bug, not a behaviour | classify as Number |
| Lone UTF-16 surrogates from `_xD800_` | Swift `String` is Unicode-scalar-valid | U+FFFD |
| Culture-dependent calendars and separators | the Mac has no .NET culture | fixed reference culture (VESSEL-325/333) |

#### X.7.5 What not to do
* Do not use `NSNumberFormatter`/`DateFormatter` (locale, time-zone and DST effects) for any value in this contract.
* Do not "improve" typing (e.g. treating id 17 as a date, detecting serials in COMPAS columns, filling merged areas).
  Improvements must land on both platforms together (see 09 §8 Q7).
* Do not trim, normalise or Unicode-fold text in the shared layer. Only the renderers trim, exactly where the C# does.

#### X.7.6 Verification harness (Windows golden files)
Add `mac/Tools/XlsxGolden/` (C# console, `net10.0`, `ClosedXML` 0.104.2 pinned; allowed under `mac/` by the
architecture brief's rule zero). For every fixture in `mac/Tests/Fixtures/xlsx/`, it writes
`{fixture}.golden.json`: per worksheet name, the used range, and for every cell in the used range
`{kind, compas, shippalm, ports}` strings plus any exception message. AACoreTests loads the fixtures with `XlsxWorkbook`
and asserts equality with the golden JSON. Run the console on a Windows machine with an **en-US** or **en-GB** culture.
Items marked **VERIFY** in §X.8 are settled by this harness, and the spec is updated to match its output.

### X.8 TEST VECTORS / VERIFICATION

Notation: `idN` = the cell's `s` points at an `<xf numFmtId="N">` with no `<numFmts>` override; `cNNN "code"` =
custom `<numFmt numFmtId="NNN" formatCode="code">`. `{today}` = the local date at import, `yyyy-MM-dd`. A = renderer
A (COMPAS `CellString`), B = renderer B (Shippalm `Cell`), B+ = `ExcelDate(B)` as applied to a Shippalm date column,
C = renderer C (Ports `Cell`), C·D = `NormDate(C)` (ports date column), C·T = `NormTime(C)` (ports time column).
Fixtures are tiny hand-built packages written by the AACore ZIP writer in the test, so no Excel is needed. The two POC
files are **copied** into `mac/Tests/Fixtures/xlsx/`.

#### X.8.1 The required matrix
| # | Cell XML (sheet) + style | Kind | A | B | B+ (date col) | C | C·D | C·T |
|---|---|---|---|---|---|---|---|---|
| M1 | `<c s=".."><v>45000</v></c>` id14 | dateTime | `2023-03-15` | `2023-03-15` | `2023-03-15` | `2023-03-15` | `2023-03-15` | `` |
| M1a | `45000.75` id22 | dateTime | `2023-03-15` | `2023-03-15` | `2023-03-15` | `2023-03-15 18:00` | `2023-03-15` | `18:00` |
| M1b | `45000` c164 `"dd/mm/yyyy"` | dateTime | `2023-03-15` | `2023-03-15` | `2023-03-15` | `2023-03-15` | `2023-03-15` | `` |
| M1c | `45000` **id17** (`mmm-yy`) | **number** | `45000` | `45000` | `2023-03-15` (serial window) | `45000` | `45000` | `` |
| M1d | `45000` **id30** (CJK date, not in `numFmts`) | **number** | `45000` | `45000` | `2023-03-15` | `45000` | `45000` | `` |
| M2 | `<v>0.5</v>` id20 (`H:mm`) | timeSpan | `12:00:00` | `12:00:00` | **`{today}`** | `12:00` | **`{today}`** | `12:00` |
| M2a | `0.25` id20 | timeSpan | `6:00:00` | `6:00:00` | `{today}` | `06:00` | `{today}` | `06:00` |
| M2b | `1.5` id46 (`[h]:mm:ss`) | timeSpan | `36:00:00` | `36:00:00` | `36:00:00` † | `12:00` | `{today}` | `12:00` |
| M2c | `0.500001` id21 | timeSpan | `12:00:00.086` | `12:00:00.086` | `{today}` | `12:00` | `{today}` | `12:00` |
| M2d | `0.5` **id14** | dateTime | `1899-12-31` | `1899-12-31` | `1899-12-31` | `1899-12-31 12:00` | `1899-12-31` | `12:00` |
| M2e | `1.5` c164 `"[h]:mm"` | **dateTime** (D2) | `1900-01-01` | `1900-01-01` | `1900-01-01` | `1900-01-01 12:00` | `1900-01-01` | `12:00` |
| M3 | `<c t="s"><v>k</v></c>`, sst[k] = `2026-03-04`, style id14 or id0 | text | `2026-03-04` | `2026-03-04` | `2026-03-04` | `2026-03-04` | `2026-03-04` | `` |
| M3a | sst[k] = `  2026-03-04 ` | text | `2026-03-04` | `2026-03-04` | `2026-03-04` | `2026-03-04` | `2026-03-04` | `` |
| M3b | `<c t="inlineStr"><is><t>2026-03-04</t></is></c>` | text | `2026-03-04` | `2026-03-04` | `2026-03-04` | `2026-03-04` | `2026-03-04` | `` |
| M4 | `<v>48108</v>` id0 (unstyled) | number | `48108` | `48108` | **`2031-09-17`** | `48108` | **`48108`** (kept) | `` |
| M4a | same, Shippalm `Overdue Days` column | number | — | `48108` → `OverdueDays = 48108` | — | — | — | — |
| M5 | `<c t="b"><v>1</v></c>` | boolean | `TRUE` | `TRUE` (`Notify` → true) | `TRUE` | `TRUE` | `TRUE` | `` |
| M5a | `<c t="b"><v>0</v></c>` / `<v>false</v>` / `<v>yes</v>` | boolean false | `FALSE` | `FALSE` | `FALSE` | `FALSE` | `FALSE` | `` |
| M6 | `<c t="e"><v>#N/A</v></c>` | error | `#N/A` | `#N/A` | `#N/A` | `#N/A` | `#N/A` | `` |
| M6a | `<c t="e"><v>#SPILL!</v></c>` | **blank** | `` | `` | `` | `` | `` | `` |
| M7 | merged header `A5:C5` = `Port` in `A5`, no `<c>` for B5/C5 | text / blank / blank | A5 `Port`, B5 ``, C5 `` | same | — | same | — | — |
| M7a | merged `A5:C5`, but C5 holds a stale shared string `X` (non-Excel writer) | text | C5 `X` (read, not cleared) | `X` | — | `X` | — | — |
| M7b | COMPAS: `B4:C4` merged, `B4` = `First name`; `C4` empty; data rows fill C | — | header map `{2: "first name"}`. Column C is **dropped** (no header) | | | | | |

† `ExcelDate("36:00:00")`: the .NET general parser rejects hour 36, so the result is the raw `36:00:00`, not today.
**VERIFY** with the harness (the `≥ 24` hour case). For `H < 24` the result is `{today}`.

Per-reader header consequence of M7 for ports layout B (§4.9): the sticky category spreads `Port` over A–C and
`Port Facility` over D–E, which is the reason §3.3.4 exists. With the POC file this yields the mapping in §4.9 unchanged.

#### X.8.2 Custom-format classification (`classifyCustom`)
| Code | Kind | Why |
|---|---|---|
| `General` | number | no decisive char (`g e n e r a l`) |
| `@` | number | none |
| `0.00` / `#,##0` / `# ?/?` / `0.00E+00` | number | `0`/`#`/`?` first |
| `[Red]0.00;[Blue]-0.00` | number | brackets skipped, then `0` |
| `"Day "0` | number | quote skipped, then `0` |
| `_(* #,##0.00_)` | number | `#` |
| `dd/mm/yyyy` | dateTime | `d` |
| `m/d/yyyy` | dateTime | `m` → `/` skipped → `d` |
| `mmm-yy` | dateTime | `m…` → `-` → `y` |
| `mmmm` | dateTime | end of string |
| `yyyy-mm-dd h:mm` | dateTime | `y` first |
| `[$-409]d-mmm-yy;@` | dateTime | locale tag skipped, `d` |
| `[$-F800]dddd, mmmm dd, yyyy` | dateTime | `d` |
| `yyyy"年"m"月"d"日"` | dateTime | `y` |
| `\d0` | dateTime | no escape handling |
| `AM/PM h:mm` | dateTime | `m` of `AM` → `/` → `p` |
| `[h]:mm` | **dateTime** | `[h]` skipped, `m` → end |
| `h:mm` / `hh:mm:ss AM/PM` | timeSpan | `h` |
| `[h]:mm:ss` | timeSpan | `m` → `:` → `s` |
| `mm:ss` / `mm:ss.0` / `[mm]:ss` | timeSpan | `m` → `:` → `s` (or brackets skipped) |
| `ss` | timeSpan | `s` |
| `;;;` | number | none |
| `"abc` (unterminated) | number | Mac only (Windows hangs) |
| `[Red` (unterminated) | number | `IndexOf(']') == -1` |
| `   ` | number | whitespace-only |
| id 14 redefined `<numFmt numFmtId="14" formatCode="0.00"/>` | number | override wins |
| id 20 redefined as `yyyy-mm-dd` | dateTime | override wins |
| id 14 with `formatCode=""` | dateTime | empty override ignored → built-in |

#### X.8.3 Serials
| Serial | Style | Result |
|---|---|---|
| 0 | id14 | `1899-12-31` |
| 1 | id14 | `1900-01-01` |
| 59 | id14 | `1900-02-28` |
| 60 | id14 | `1900-03-01` |
| 60.5 | id14 | import fails: `Serial date 60 is on a leap year of 1900 - date that doesn't exist and isn't representable in DateTime.` |
| 61 | id14 | `1900-03-01` |
| 46085 | id14 | `2026-03-04` |
| 46096 | id14 | `2026-03-15` (09 §7.7) |
| 46218.99999999 | id22 | C `2026-07-15 23:59` (ms 999 kept) |
| 46218.999999999 | id22 | C `2026-07-16` (rounds to midnight) |
| −1.25 | id22 | C `1899-12-30 06:00` (`v ≤ 60` → `FromOADate(−0.25)`; OA negative rule: the time part counts forward from the day) |
| −0.25 | id22 | C `1899-12-30 18:00` (`FromOADate(0.75)`) |
| 2958465.999999 | id14 | `9999-12-31` |
| 2958466 | id14 | import fails: `Not a legal OleAut date.` |
| 1904 workbook: 44623 | id14 | `2026-03-04` |
| 1904 workbook: 45000 | id14 | `2027-03-16` |
| 1904 workbook: 0 | id14 | `1904-01-02` (Excel shows 1904-01-01; replicate) |
| 1904 workbook: 44623 | id0 | A `44623`; B+ `2022-03-03` (1900 epoch, not corrected); C `44623` |
| 1904 workbook: `<c t="d"><v>2026-03-04</v></c>` | — | `2030-03-05` (+1462; replicate) |
| `<c t="d"><v>2026-03-04</v></c>` (1900) | — | `2026-03-04` |
| `<c t="d"><v>2026-03-04T10:30</v></c>` | — | A `2026-03-04`; C `2026-03-04 10:30` |
| `<c t="d"><v>2026-03-04T10:30:00.000</v></c>` | — | C `2026-03-04 10:30` |
| `<c t="d"><v>2026-03-04T10:30:00</v></c>` | — | whole import fails (VESSEL-302 message) |
| ExcelDate `48108` / `46218` / `20001` / `15000` | text | `2031-09-17` / `2026-07-15` / `1954-10-04` / `15000` (10 §7.8, unchanged) |

#### X.8.4 Durations (`toTimeSpanMs` → A text / C text)
| Serial | ms | A (`ToExcelString`) | C (`hh:mm`) |
|---|---|---|---|
| 0 | 0 | `0:00:00` | `00:00` |
| 0.25 | 21600000 | `6:00:00` | `06:00` |
| 0.5 | 43200000 | `12:00:00` | `12:00` |
| 0.500001 | 43200086 | `12:00:00.086` | `12:00` |
| 0.999999 | 86399914 | `23:59:59.914` | `23:59` |
| 1.5 | 129600000 | `36:00:00` | `12:00` |
| 0.5 + 200 ms (0.50000231481…) | 43200200 | `12:00:00.2` | `12:00` |
| 0.5 + 250 ms | 43200250 | `12:00:00.25` | `12:00` |
| 0.5625 (13:30) + 55.2 s → `13:30:55.2` | 48655200 | `13:30:55.2` (matches ClosedXML's own test) | `13:30` |

#### X.8.5 Number text
| Double | A/B (`Int64` or `NetShortest`) | C (`Net0_4`) |
|---|---|---|
| 12345.0 | `12345` | `12345` |
| 180.5 | `180.5` | `180.5` |
| 0.1 + 0.2 = 0.30000000000000004 | `0.30000000000000004` | `0.3` |
| 1e-7 | `1E-07` | `0` |
| 0.0001 | `0.0001` | `0.0001` |
| 0.00001234 | `1.234E-05` | `0` |
| 0.00005 | `5E-05` | `0.0001` |
| 2.00005 | `2.00005` | `2.0001` (15-digit pre-rounding) |
| 1234.56785 | `1234.56785` | `1234.5679` (**VERIFY**) |
| 1234.56789 | `1234.56789` | `1234.5679` |
| −3 | `-3` | `-3` |
| −1.5 | `-1.5` | `-1.5` |
| −0.0 | `0` | `0` |
| −0.00001 | `-1E-05` | `0` (**VERIFY** sign, Q19) |
| 9792606 | `9792606` | `9792606` |
| 123456789012345.6 | `123456789012345.6` | `123456789012346` (only 15 significant digits survive; **VERIFY**) |
| 1000000000000000.5 | `1.0000000000000005E+15` | `1000000000000000` (**VERIFY**) |
| 12345678901234567 (integral) | `12345678901234568` | `12345678901234600` |
| 1e20 | `9223372036854775807` (saturating cast) | `100000000000000000000` |

Magnitudes of 10^14 and above never occur in port lists. The **VERIFY** rows pin the 15-digit rule and are settled by
the golden harness (§X.7.6) before anyone relies on them.

#### X.8.6 Strings
| Source XML | Text value | A / B / C |
|---|---|---|
| `<si><t>Hello</t></si>` | `Hello` | `Hello` |
| `<si><r><t>Hello </t></r><r><rPr><b/></rPr><t>World</t></r><rPh sb="0" eb="1"><t>ハロー</t></rPh><phoneticPr fontId="1"/></si>` | `Hello World` | `Hello World` |
| `<si><t>東京</t><rPh sb="0" eb="2"><t>トウキョウ</t></rPh></si>` | `東京` | `東京` |
| `<si><t>A_x000D_&#10;B</t></si>` | `A\r\nB` | `A\r\nB` (trim does not touch the interior) |
| `<si><t>Line1&#10;Line2</t></si>` (plain) | `Line1\nLine2` (LF kept) | `Line1\nLine2` |
| `<si><r><t>Line1&#10;Line2</t></r></si>` (rich) | `Line1\r\nLine2` | `Line1\r\nLine2` |
| `<c t="inlineStr"><is><t>A&#10;B</t></is></c>` | `A\r\nB` | `A\r\nB` |
| `<c t="inlineStr"><is><t>A_x000D_B</t></is></c>` | `A_x000D_B` (no decode) | same |
| `<si><t>_x005F_x000D_</t></si>` | `_x000D_` | same |
| `<si><t>_X000D_</t></si>` | `_X000D_` (upper-case X not decoded) | same |
| `<si><t>_x0041__x0042_</t></si>` | `AB` | same |
| `<si><t>_xD83D__xDE00_</t></si>` | `😀` (pair combines) | same |
| `<si><t>   </t></si>` | `   ` (non-empty, extends the used range) | `` |
| `<c t="str"><f>A1</f><v>  x  </v></c>` | `  x  ` (hasFormula) | `x` |
| `<c t="s"/>` (no `<v>`) | `""` (empty) | `` |
| `<c t="s"><v>999</v></c>` with 91 strings | `""` | `` |

#### X.8.7 Used range, sheet choice, merges, tables, comments
| Scenario | Expected |
|---|---|
| POC layout A (`Last Ports - 24 Months (4).xlsx`) | `RangeUsed` rows **2–53**, cols **A–M** (1–13). The 269 style-only cells (220 General-styled, e.g. `D2`, and 49 id14-styled, e.g. `D6`; `t` absent, no `<v>`) do not count |
| POC layout B (`Port of Call List - Last 10 Ports (14).xlsx`) | Sheet1 chosen (Sheet2/3 have no cells). `RangeUsed` rows **1–18**, cols **A–L** (1–12) |
| Sheet with only a comment on `C3` | `RangeUsed` = C3:C3. Shippalm → throws the header message. Ports → throws `Couldn't recognise this as a ports-of-call list. …`. COMPAS → throws the COMPAS header message |
| Only `<c r="B2" t="s"><v>k</v></c>` with sst[k] = `" "` | `RangeUsed` = B2:B2, renders `` everywhere |
| Only `<c r="B2" t="e"><v>#SPILL!</v></c>` | `RangeUsed` = nil (Shippalm `[]`, Ports `The workbook is empty.`) |
| Only `<c r="D4"><f>NOW()</f></c>` (no `<v>`) | `RangeUsed` = D4:D4. Mac renders `` + hint. Windows recalculates (Q14) |
| `<dimension ref="A1:Z999"/>` with data only in B2:C3 | `RangeUsed` = B2:C3 (dimension ignored) |
| Workbook sheets `[Chart1 (chartsheet), Empty, Data]` | Worksheets = `[Empty, Data]`. Shippalm/Ports read `Data`. COMPAS (no `report`) reads `Empty` → `[]` |
| Sheets `Summary`, `REPORT` | COMPAS reads `REPORT` (09 §7.7) |
| Hidden sheet `report` + visible `Sheet1` | COMPAS reads the hidden `report` |
| Rows without `r`: `<row><c t="s"><v>0</v></c></row><row><c t="s"><v>1</v></c></row>` | cells at A1 and A2 |
| `<row r="5">…</row><row>…</row>` | the second row is row **1** (counter only advanced by unnumbered rows; quirk) |
| Cells without `r` in `<row r="3">`: three `<c>` | A3, B3, C3 |
| `<c r="C3"/>` then `<c>` (no r) in the same row | the second is D3 |
| Table `ref="A1:C1"` (one row) with a data cell at `B2` | after load, `B2`'s value is at **B3**. A cell at `D2` (outside the span) stays at D2 |
| Table `ref="A1:C5"` with `A1`=`Column2`, `B1` empty | `B1` becomes text `Column3` (`Column2` is taken on its left) |
| Table `ref="A1:C5"` with `A1`=`Name`, `B1` empty, `C1`=`Column2` | `B1` becomes text `Column2`: uniqueness only looks **left**, so the duplicate is allowed |
| Round trip: `ShippalmReader.Write` (Mac writer) → Mac reader and Windows reader | identical `ShipJob` fields (§7.16). Due Date text cells in `@`-styled columns render as text |

#### X.8.8 Gate and error messages
| Input | Message shown (inside `Could not import the Shippalm file:\n\n…`) |
|---|---|
| `jobs.csv` | `Extension 'csv' is not supported. Supported extensions are '.xlsx', '.xlsm', '.xltx' and '.xltm'.` |
| `jobs.XLS` | `Extension 'xls' is not supported. Supported extensions are '.xlsx', '.xlsm', '.xltx' and '.xltm'.` |
| `jobs` / `jobs.` | `Empty extension is not supported.` |
| `JOBS.XLSX`, `jobs.xlsm` | accepted |
| `jobs.xlsx` that is a CSV | `The file could not be opened as an Excel workbook (.xlsx).` + detail (Mac wording) |
| `<c t="z">` | same corrupt-file message (Windows: `Unknown cell type.`) |
| `s="99"` with 12 `<xf>` | same corrupt-file message |

#### X.8.9 POC fixture expectations (end to end, unchanged from §7.4/§7.5 but now derived through this contract)
* Layout A: every date cell (`C6`, `E6`, …) is `t="s"` in an id14-styled cell → **text** → `15/07/2026` → `NormDate` →
  `2026-07-15`. The merged `C45:D45`-style regions have style-only non-anchors (`D45`, no `<v>`) → blank → no effect. 47
  calls, as §7.4.
* Layout B: `H7`/`J7` (id14) and `I7`/`K7` (id20) are **text** (`t="s"`), not serials. `I7` text `22:00` → C `22:00` →
  `NormTime` `22:00`. The 10 calls are as §7.5. Vessel `BW PAVILION ARANDA`, IMO `9792606` (text, so C renders `9792606`,
  not via `Net0_4`), call sign `9V6330`.
* Neither file has `numFmts`, formulas, comments, tables, rich text, phonetic runs, `_xHHHH_` escapes, whitespace-only
  strings or `date1904`. The contract's extra rules are exercised only by the synthetic fixtures above.

### X.9 Cross-reference line for 09 §6.2 (verbatim)

> **09 §6.2 cross-reference:** Cell typing, date/time detection (numFmtId lists and custom-code rules), the 1900/1904
> serial conversion, time-only text, used-range bounds, merged cells, shared/inline/rich strings, formulas and
> errors for the COMPAS reader are defined **normatively** by spec 10, *Addendum: One normative AACore XLSX reader
> contract*, which supersedes the corresponding bullets of 09 §6.2 and the typing notes in 09 §3.3. In particular,
> only ids 14, 15, 16 and 22 are dates. Ids 18–21 and 45–47 are durations, and `CellString` renders them as `H:mm:ss`.
> Id 17, ids 27–36 and ids 50–58 are plain numbers. `CompasReader.CellString` is renderer A (VESSEL-326).

This file must not edit spec 09. The line above is what 09 §6.2 should point to, and 09 implementers must treat it
as already in force.

### X.10 Quirks and open questions (continuing §9's numbering)

| # | Topic | Windows behaviour | Recommendation |
|---|---|---|---|
| Q14 | Formula cells without a cached value | ClosedXML recalculates on first read (CalcEngine). Unsupported functions may throw | Mac renders `""` and shows the VESSEL-318 hint. Never seen in real exports. Revisit only if a real file needs it |
| Q15 | Built-in id 17 (`mmm-yy`) and CJK date ids 27–36 / 50–58 are numbers | Serials show as `45000` in COMPAS and Ports (Shippalm recovers them via `ExcelDate`) | Replicate. A joint fix (treat them as DateTime) must land in both builds, e.g. by pinning a newer ClosedXML and re-deriving this table |
| Q16 | 1904 early-date off-by-one, `t="d"` +1462 bug, and no 1904 correction in `ExcelDate` | as described (VESSEL-310) | Replicate. 1904 files are rare (old Mac Excel) |
| Q17 | Culture-dependent output (calendar, separators) | a Windows user on `th-TH`, `ar-SA`, `fa-IR` or `fi-FI` persists different strings | Mac uses the reference culture. Record as a known Windows variance; no Mac setting |
| Q18 | Table totals-row rescan converts non-text header cells to text via `CurrentCulture` | only when a table has a totals row | Not replicated. Affects only typed (date/bool/error) header cells in totals-row tables, which no known export has |
| Q19 | Sign of `"0.####"` for negative values that round to zero (`-0.00001`) | .NET Core formats floating `-0` specially. Unverified whether `RoundNumber` keeps the sign here | Provisionally `0` (as §6.7). Settle with the golden harness (§X.7.6) |
| Q20 | `ExcelDate` of `H:mm:ss` with H ≥ 24 (`36:00:00`) | expected raw (the .NET parser rejects hour 36) | **VERIFY** with the harness. For H < 24 it is `{today}` (a surprising but faithful result) |
| Q21 | Time-only strings in date columns become today (Shippalm `ExcelDate`, Ports `NormDate`) | as described | Replicate. This requires the shared `ParseDate` port to accept time-only input (VESSEL-327 note), which 09 §6.3 must add |
| Q22 | Hang on an unterminated `"` in a custom format | Windows import never returns | Mac classifies as Number. A divergence by necessity |
