# W-BUILD — progress record

Owner of: builders, editors, procedure checklist area, Saved Lists tab (OWNERSHIP §3 "W-BUILD").

## Counts
- Feature IDs: **90 / 90 done** (BUILD 80, REPO 3, HIER 5, SHELL 1, VIEW 1); remaining: 0.
- Algorithm ids: **8 / 8 done** (BUILD-A1–A6, A10, A11).
- Vectors (06 §7.3, §7.5–§7.8, §7.14; T-KB-32/33): done — `Tests/AACoreTests/Builders/` (4 suites, 32 tests).
- ContractStatus: `wBuildImplemented = true`; `Scripts/check-placeholders.sh W-BUILD`: empty.

## Where
- AACore (`Sources/AACore/Builders/`): `BuilderAlgorithms` (A1–A5, BUILD-004/013/053, wording), `BuilderEngine`
  (generic builder over steps / subtasks, log lines BUILD-135), `BuilderSavedLists` (tab rows A10 + D1, texts, guards,
  list/group operations), `BuilderProcedureSteps` (BUILD-030…036), `BuilderEditing` (BUILD-021/022, 051…056).
- AA (`Sources/AA/Builders/`): `ChecklistBuilderView` / `ChecklistBuilderSheet` (procedure, crew, saved-list hosts),
  `BuilderItemsPane` (two-pane builder), `ChecklistStepEditorSheet` (+ detached overload), `SubtaskBuilderSheet`,
  `TaskItemEditorSheet` (+ nested Subtasks section), `ProcedureChecklistSection`, `SavedListsTabView`,
  `BuilderTemplateFlows` (save / load / manage saved lists), `BuilderSupport`, `BuildersDebugSnapshots`.
- Snapshot fixture: `Tests/AACoreTests/Fixtures/ui/w-build/sample-data.json`; debug sheets `w-build.*` (10).

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
- `swift build` / `swift test` (431 tests) green; `check-placeholders.sh W-BUILD` empty.
- `check-ownership.sh` is green on every code commit; it flags only this file (`Docs/Progress/W-BUILD.md`), which the
  DECISIONS REQ-F1-01 ruling requires but the script does not own yet — REQ-W-BUILD-02.
