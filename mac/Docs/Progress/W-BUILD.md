# W-BUILD — progress record

Owner of: builders, editors, procedure checklist area, Saved Lists tab (OWNERSHIP §3 "W-BUILD").

## Counts
- Feature IDs: **90 / 90 done** (BUILD 80, REPO 3, HIER 5, SHELL 1, VIEW 1); remaining: 0.
- Algorithm ids: **8 / 8 done** (BUILD-A1–A6, A10, A11).
- Vectors (06 §7.3, §7.5–§7.8, §7.14; T-KB-32/33/40/45): done — `Tests/AACoreTests/Builders/` (5 suites, 39 tests).
  Not testable here (code owned elsewhere): 06 §7.5 PDF headings and §7.6 PDF H2 (W-PDF), §7.6 saved-list picker row
  (W-PLAN, BUILD-101) and schedule count line (W-CREW).
- ContractStatus: `wBuildImplemented = true`; `Scripts/check-placeholders.sh W-BUILD`: empty.

## Where
- AACore (`Sources/AACore/Builders/`): `BuilderTemplateSession` (template editor write-back / vanished rescue, D3),
  `BuilderAlgorithms` (A1–A5, BUILD-004/013/053, wording), `BuilderEngine`
  (generic builder over steps / subtasks, log lines BUILD-135), `BuilderSavedLists` (tab rows A10 + D1, texts, guards,
  list/group operations), `BuilderProcedureSteps` (BUILD-030…036), `BuilderEditing` (BUILD-021/022, 051…056).
- AA (`Sources/AA/Builders/`): `ChecklistBuilderView` / `ChecklistBuilderSheet` (procedure, crew, saved-list hosts),
  `BuilderItemsPane` (two-pane builder), `ChecklistStepEditorSheet` (+ detached overload), `SubtaskBuilderSheet`,
  `TaskItemEditorSheet` (+ nested Subtasks section), `ProcedureChecklistSection`, `SavedListsTabView`,
  `BuilderTemplateFlows` (save / load / manage saved lists), `BuilderSupport`, `BuildersDebugSnapshots`.
- Snapshot fixture: `Tests/AACoreTests/Fixtures/ui/w-build/sample-data.json`; debug sheets `w-build.*` (10).

## Audit (independent pass, 2026-10-02)
- All 90 feature IDs + 8 algorithm IDs re-checked against 06 / 04 / 02 / 07 / 03 and the C# where unclear.
- Fixed: rows scroll into view after add / insert / Move to (BUILD-006, 009) and after + List, Duplicate and
  reorders in Saved Lists (BUILD-080, 083, 085); template-editor logic moved to AACore (`BuilderTemplateSession`) and
  tested (BUILD-063, D3, R1, T-KB-40/45); missing 06 §7.6 / §7.8 vector assertions and BUILD-064 added.
- Visual: every W-BUILD surface now uses the app's monospaced identity (ARCH §8.3; previously mixed system / mono),
  lists use thin row separators without alternating fills (03 SHELL-155). Snapshots re-checked light + dark.

## Verification fixes (FIX-W-BUILD, 2026-10-03) — 8 / 8 fixed, 0 remaining
- REPO-132/133/134 (V-02): a list whose `GroupId` names a deleted group is arranged inside "Ungrouped", where D1
  shows it — ↑ / ↓, Move to position… (incl. its "Before:" rows) and drag all work on the resolved group
  (`BuilderSavedLists.arrangeGroupID` / `arrangeSpan` / `nudge` / `moveTo` / `reorderAvailability`). Same algorithm
  and same flat result as F2's `SavedListOrder` whenever no id dangles (randomised equivalence test, 300 cases);
  the stored `GroupId` is never touched (pure permutation). Tests: `danglingGroupArrangesInsideUngrouped`,
  `resolvedArrangeMatchesSavedListOrderWithoutDanglingIDs`.
- HIER-091 / PDF-010 (V-04, V-11): the procedure Checklist tab has 16-pt side margins of its own; the builder banner
  never truncates — the two exports dock right of it when the row fits, else move under it (ViewThatFits); the step
  bar is one row (labels when they fit, icons otherwise).
- BUILD-050 (V-06): the task / subtask editor sheet is 980×700 minimum (ideal 1060×780) and the container editor pane
  640 minimum, so the format bar, File Bank toolbar and footer are not clipped next to the nested Subtasks pane.
- BUILD-042 (V-06) + V-DESIGN: builder item bars (Current items / Current subtasks, nested Subtasks, procedure steps)
  are a single non-wrapping row (`BuilderCommandBar`: labelled accessory-bar buttons when they fit, else 24-pt icons;
  help = Windows tooltip, accessibility label = spec button text). The bulk bar drops "Replace existing" under the
  buttons instead of wrapping it; the "Saved lists:" strip collapses into one "Saved lists" menu when narrow.
- PDF-022 / DEV-10 (V-11): "Export ALL (PDF)…" stays enabled with zero lists (the flow answers "No saved lists to
  export."), and is also in the Saved Lists overflow menu (§6.5), with every other list command by its spec name.
- V-DESIGN: Saved Lists rows are regular weight (headers alone are bold), header = title (16 bold accent) + muted
  count, one icon bar (+ List/Group menu, Delete, Sort A-Z toggle, ↑, ↓, overflow `ellipsis.circle`).
- Snapshots (light + dark): `scratchpad/snapshots/fix1-W-BUILD/` — task-editor, lists, proc-1400, proc-1100,
  subtask-builder, crew-embedded, checklist-builder.

## Stage V round 2 fixes (FIX2-W-BUILD)
- V2-J7 #1 (DECISIONS 06 "log the unlogged actions: yes", 06 §8 D8): group create / rename / delete, saved-list
  rename and Move to group now add log entries — `Added · List group · {name} · ""`, `Added · List group · {new} ·
  renamed from '{old}'`, `Removed · List group · {name} · {n} list(s) ungrouped`, `Added · Saved list · {new} ·
  renamed from '{old}'`, `Added · Saved list · {name} · moved to group '{g}'` / `moved to Ungrouped`. Unchanged
  renames and moves to the current group are not logged. Test: `BuilderSavedListsTests.d8GroupAndRenameActionsAreLogged`.
- V2-J7 #2 (06 §8 D3): the template-editor rescue ("Save as New List") and its prompt use the list's latest name —
  `BuilderTemplateSession` remembers the template object it last resolved, so a rename through "Manage saved lists…"
  followed by a delete rescues as the renamed list (`openedName` → `lastKnownName`). Tests:
  `BuilderTemplateSessionTests.rescueAfterRenameThenDeleteUsesTheLatestName`, `…EvenWhenTheHeaderNeverReadIt`.
- Gate: build + 1,657 tests green with `-warnings-as-errors`; `check-ownership.sh` green. No UI layout change (log
  rows and a prompt name only), so no new snapshots.

## Not done / post-merge (Stage V)
- Editors show the real rich-text + file-bank pane once W-CONT's `ContainerEditorView` lands (placeholder in this
  worktree).
- Export buttons (checklist PDF/XLSX, saved lists PDF) produce files once W-PDF's `PdfExportFlows` lands.
- Batch done / deadline context menu of the step grid appears once W-HIER's `BatchContextMenuItems` lands.
- Item viewer subtitle: REQ-W-BUILD-01 (W-FILES).
- Not W-BUILD's by OWNERSHIP §4 (listed so nothing looks forgotten): BUILD-091…096 (W-PDF), BUILD-100 (W-CONT),
  BUILD-101 `SavedListPicker` (W-PLAN), BUILD-102 (W-QUICK), BUILD-110…125 crew schedule builder (W-CREW),
  BUILD-130/131/136…150 (F3).

## Gate
- `swift build` / `swift test` (438 tests) green; `check-placeholders.sh W-BUILD` empty.
- `check-ownership.sh` is green on every code commit; it flags only this file (`Docs/Progress/W-BUILD.md`), which the
  DECISIONS REQ-F1-01 ruling requires but the script does not own yet — REQ-W-BUILD-02.
